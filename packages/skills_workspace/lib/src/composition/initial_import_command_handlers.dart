import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/activation/activation_result.dart';
import '../application/activation/activation_models.dart';
import '../application/discovery/external_discovery_models.dart';
import '../application/discovery/external_skill_scanner.dart';
import '../application/install/initial_import_models.dart';
import '../application/install/initial_import_planner.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/ports/initial_import_ports.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../application/source/source_acquisition_coordinator.dart';
import '../application/source/source_acquisition_models.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';

/// Builds initial Install and Adoption commands around the two-stage Journal.
///
/// Source reads, target resolution, and occupancy checks finish before the
/// writer transaction. Candidate Store/Bundle work begins only inside
/// [OperationCoordinator.executeDeferred], after the Prepared envelope is
/// durable. The candidate-dependent plan is then sealed before any live
/// materialization replacement.
List<SkillsCommandHandler> buildInitialImportCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required SourceAcquisitionCoordinator sources,
  required ExternalSkillScanner Function() externalSkills,
  required InitialImportPlanner initialImports,
  required InitialImportOperationPlanPort plans,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<InstallRequest, InstallAttempt>(
    kind: WorkspaceOperationKind.install,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final acquiredResult = await sources.acquire(
        source: request.source,
        selectedSkillNames: request.selectedSkillNames ?? const <String>{},
        options: SourceAcquisitionOptions(
          includeInternal: request.includeInternal,
          fullDepth: request.fullDepth,
        ),
        cancellationToken: context.cancellationToken,
      );
      final acquired = acquiredResult.valueOrNull;
      if (acquired == null) {
        return _sourceFailure<InstallAttempt>(acquiredResult.failureOrNull!);
      }
      final planned = await initialImports.planInstall(
        snapshot: snapshot,
        acquiredSource: acquired,
        activationSelection: request.activationSelection,
        activationMode: request.activationMode,
        sourceWarnings: acquiredResult.warnings,
        cancellationToken: context.cancellationToken,
      );
      if (planned.takeoverOrNull case final takeover?) {
        final draft = _InstallTakeoverDraft(
          reviewedRevision: snapshot.revision,
          request: request,
          acquiredSource: acquired,
          sourceWarnings: acquiredResult.warnings,
          inspection: takeover,
        );
        return SkillsSuccess<InstallAttempt>(
          value: InstallTakeoverRequired(draft),
          changed: false,
          warnings: <SkillsWarning>[
            ..._sourceWarnings(takeover.preflight.sourceWarnings),
            ..._activationWarnings(takeover.preflight.activationWarnings),
          ],
        );
      }
      final report = await _executeInitialImport(
        planned: planned,
        initialWarnings: const <SkillsWarning>[],
        context: context,
        snapshots: snapshots,
        operations: operations,
        initialImports: initialImports,
        plans: plans,
      );
      return _installAttempt(report);
    },
  ),
  TypedSkillsCommandHandler<ConfirmInstallTakeoverRequest, MutationReport>(
    kind: WorkspaceOperationKind.confirmInstallTakeover,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final draft = request.draft;
      if (draft is! _InstallTakeoverDraft) {
        return SkillsFailure<MutationReport>(
          code: SkillsErrorCode.operationFailed,
          context: const <String, Object?>{
            'reason': 'invalidInstallTakeoverDraft',
          },
        );
      }
      final snapshot = snapshots.current;
      if (snapshot.revision != draft.reviewedRevision) {
        return _staleInstallDraft<MutationReport>(
          draft,
          snapshot,
          reason: 'repositoryRevisionChanged',
        );
      }
      final planned = await initialImports.planInstall(
        snapshot: snapshot,
        acquiredSource: draft.acquiredSource,
        activationSelection: draft.request.activationSelection,
        activationMode: draft.request.activationMode,
        sourceWarnings: draft.sourceWarnings,
        cancellationToken: context.cancellationToken,
        confirmedTakeoverFingerprints: draft.fingerprintsByTargetPath,
        expectedTargetSignatures: draft.targetSignatures,
      );
      if (planned.takeoverOrNull != null) {
        return _staleInstallDraft<MutationReport>(
          draft,
          snapshot,
          reason: 'activationTargetChanged',
        );
      }
      return _executeInitialImport(
        planned: planned,
        initialWarnings: const <SkillsWarning>[],
        context: context,
        snapshots: snapshots,
        operations: operations,
        initialImports: initialImports,
        plans: plans,
      );
    },
  ),
  TypedSkillsCommandHandler<AdoptRequest, MutationReport>(
    kind: WorkspaceOperationKind.adopt,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final scanner = externalSkills();
      final resolved = scanner.resolveAllLocations(snapshot);
      final targets = resolved.valueOrNull;
      if (targets == null) {
        return _externalFailure<MutationReport>(resolved.failureOrNull!);
      }
      final scanned = await scanner.scanTargets(
        targets,
        snapshot: snapshot,
        includeInternal: false,
        selectedSlotKeys: <String>{request.selection.slotKey},
        cancellationToken: context.cancellationToken,
      );
      final scan = scanned.valueOrNull;
      if (scan == null) {
        return _externalFailure<MutationReport>(scanned.failureOrNull!);
      }
      final planned = await initialImports.planAdoption(
        snapshot: snapshot,
        selection: request.selection,
        scan: scan,
        activationMode: request.activationMode,
        cancellationToken: context.cancellationToken,
      );
      return _executeInitialImport(
        planned: planned,
        initialWarnings: _externalWarnings(scanned.warnings),
        context: context,
        snapshots: snapshots,
        operations: operations,
        initialImports: initialImports,
        plans: plans,
      );
    },
  ),
];

Future<SkillsResult<MutationReport>> _executeInitialImport({
  required InitialImportPlanningResult<InitialImportPreflight> planned,
  required List<SkillsWarning> initialWarnings,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required InitialImportPlanner initialImports,
  required InitialImportOperationPlanPort plans,
}) async {
  switch (planned) {
    case InitialImportPlanningSuccess(:final value):
      return _executePreparedInitialImport(
        preflight: value,
        initialWarnings: initialWarnings,
        context: context,
        snapshots: snapshots,
        operations: operations,
        initialImports: initialImports,
        plans: plans,
      );
    case InitialImportPlanningFailure():
      return _initialImportFailure<MutationReport>(planned);
    case InitialImportPlanningTakeoverRequired(:final takeover):
      // Install consumes takeover inspections before reaching this executor.
      return _adoptionTargetOccupied(takeover, initialWarnings);
  }
}

// Keep this collection-heavy map out of the async state machine, including
// in release builds where the optimizer would otherwise inline it again.
@pragma('vm:never-inline')
SkillsFailure<MutationReport> _adoptionTargetOccupied(
  InitialImportTakeoverInspection takeover,
  List<SkillsWarning> initialWarnings,
) {
  return SkillsFailure<MutationReport>(
    code: SkillsErrorCode.activationUnavailable,
    context: <String, Object?>{
      'reason': 'adoptionTargetOccupied',
      'slotKey': takeover.preflight.subjects.single.skill.slotKey,
      'occupant': takeover.occupancies.first.adoptionOccupant.name,
      'occupantFailureCode': ?takeover.occupancies.first.occupantFailureCode,
      'occupantFailureReason':
          ?takeover.occupancies.first.occupantFailureReason,
      'occupants': [
        for (final occupancy in takeover.occupancies)
          {
            'targetPath': occupancy.targetPath,
            'occupant': occupancy.adoptionOccupant.name,
            'occupantFailureCode': ?occupancy.occupantFailureCode,
            'occupantFailureReason': ?occupancy.occupantFailureReason,
          },
      ],
      'targetPaths': [
        for (final occupancy in takeover.occupancies) occupancy.targetPath,
      ],
    },
    warnings: <SkillsWarning>[
      ...initialWarnings,
      ..._sourceWarnings(takeover.preflight.sourceWarnings),
      ..._activationWarnings(takeover.preflight.activationWarnings),
    ],
  );
}

// Pass a resolved preflight into the async executor instead of capturing a
// switch-assigned local across its suspension point. Dart 3.14's AOT
// allocator crashes on the combined dispatch/execution function.
Future<SkillsResult<MutationReport>> _executePreparedInitialImport({
  required InitialImportPreflight preflight,
  required List<SkillsWarning> initialWarnings,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required InitialImportPlanner initialImports,
  required InitialImportOperationPlanPort plans,
}) async {
  InitialImportPlanningFailure<InitialImportPlan>? preparationFailure;
  context.reportProgress(OperationProgressPhase.preparing);
  final outcome = await operations.executeDeferred<InitialImportPlan>(
    operationId: context.operationId,
    expectedRepositoryRevision: preflight.snapshotRevision,
    lockWaitPolicy: context.lockWaitPolicy,
    buildEnvelope: (operationId, currentRevision) => plans.createEnvelope(
      operationId: operationId,
      expectedRepositoryRevision: currentRevision,
      preflight: preflight,
    ),
    prepareCandidate: (envelope, cancellationToken) async {
      final prepared = await initialImports.prepareAndAssemble(
        preflight: preflight,
        envelope: envelope,
        cancellationToken: cancellationToken,
      );
      final failure = prepared.failureOrNull;
      if (failure != null) {
        preparationFailure = failure;
        throw const _InitialImportPreparationRejected();
      }
      return prepared.valueOrNull!;
    },
    buildPlan: (envelope, initialImportPlan) => plans.sealPlan(
      envelope: envelope,
      preflight: preflight,
      initialImportPlan: initialImportPlan,
    ),
    cancellationToken: context.cancellationToken,
    onBusinessCommitted: () {
      context.reportProgress(OperationProgressPhase.committing);
      context.markBusinessCommitted();
    },
  );

  if (preparationFailure case final failure?) {
    if (outcome is OperationRolledBack) {
      return _initialImportFailure<MutationReport>(failure);
    }
    if (outcome is OperationRollbackPending) {
      return SkillsFailure<MutationReport>(
        code: SkillsErrorCode.recoveryFailed,
        context: <String, Object?>{'reason': outcome.originalReason.name},
      );
    }
  }
  final warnings = <SkillsWarning>[
    ...initialWarnings,
    ..._sourceWarnings(preflight.sourceWarnings),
    ..._activationWarnings(preflight.activationWarnings),
  ];
  return _mapExecutionOutcome(
    outcome: outcome,
    affectedSkillIds: preflight.affectedSkillIds,
    baseWarnings: warnings,
    context: context,
    snapshots: snapshots,
  );
}

Future<SkillsResult<MutationReport>> _mapExecutionOutcome({
  required OperationExecutionOutcome outcome,
  required Set<ManagedSkillId> affectedSkillIds,
  required List<SkillsWarning> baseWarnings,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
}) async => switch (outcome) {
  OperationCompleted(
    :final operationId,
    :final committedRepositoryRevision,
    :final cleanupPending,
  ) =>
    _completed(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      affectedSkillIds: affectedSkillIds,
      warnings: <SkillsWarning>[
        ...baseWarnings,
        if (cleanupPending)
          SkillsWarning(code: SkillsWarningCode.recoveryCleanupDeferred),
      ],
      context: context,
      snapshots: snapshots,
    ),
  OperationCommittedFinalizationPending(
    :final operationId,
    :final committedRepositoryRevision,
  ) =>
    _committedPending(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      warnings: baseWarnings,
      context: context,
      snapshots: snapshots,
    ),
  OperationRejected(
    :final reason,
    :final actualRepositoryRevision,
    :final detail,
  ) =>
    SkillsFailure<MutationReport>(
      code: _abortCode(reason),
      context: <String, Object?>{
        'reason': reason.name,
        if (detail != null) 'detail': detail.name,
        if (actualRepositoryRevision != null)
          'actualRepositoryRevision': actualRepositoryRevision.value,
      },
      warnings: baseWarnings,
    ),
  OperationRolledBack(:final reason, :final detail) =>
    SkillsFailure<MutationReport>(
      code: _abortCode(reason),
      context: <String, Object?>{
        'reason': reason.name,
        if (detail != null) 'detail': detail.name,
      },
      warnings: baseWarnings,
    ),
  OperationRollbackPending(:final originalReason) =>
    SkillsFailure<MutationReport>(
      code: SkillsErrorCode.recoveryFailed,
      context: <String, Object?>{'reason': originalReason.name},
      warnings: baseWarnings,
    ),
};

Future<SkillsResult<MutationReport>> _completed({
  required OperationId operationId,
  required RepositoryRevision committedRepositoryRevision,
  required Set<ManagedSkillId> affectedSkillIds,
  required List<SkillsWarning> warnings,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
}) async {
  context.reportProgress(OperationProgressPhase.finalizing);
  try {
    final snapshot = await snapshots.reload();
    return SkillsSuccess<MutationReport>(
      value: MutationReport(
        snapshot: snapshot,
        affectedSkillIds: affectedSkillIds,
      ),
      changed: true,
      warnings: warnings,
    );
  } on Object {
    return SkillsCommittedFinalizationPending<MutationReport>(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      warnings: <SkillsWarning>[
        ...warnings,
        SkillsWarning(code: SkillsWarningCode.finalizationDeferred),
      ],
    );
  }
}

Future<SkillsResult<MutationReport>> _committedPending({
  required OperationId operationId,
  required RepositoryRevision committedRepositoryRevision,
  required List<SkillsWarning> warnings,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
}) async {
  context.reportProgress(OperationProgressPhase.finalizing);
  try {
    await snapshots.reload();
  } on Object {
    // Durable commit direction cannot be downgraded by Snapshot publication.
  }
  return SkillsCommittedFinalizationPending<MutationReport>(
    operationId: operationId,
    committedRepositoryRevision: committedRepositoryRevision,
    warnings: <SkillsWarning>[
      ...warnings,
      SkillsWarning(code: SkillsWarningCode.finalizationDeferred),
    ],
  );
}

SkillsFailure<T> _initialImportFailure<T>(
  InitialImportPlanningFailure<Object?> failure,
) => SkillsFailure<T>(
  code: switch (failure.code) {
    InitialImportFailureCode.operationCancelled =>
      SkillsErrorCode.operationCancelled,
    InitialImportFailureCode.duplicateSkillSlot =>
      SkillsErrorCode.duplicateSkillSlot,
    InitialImportFailureCode.sourceReplacementRequired =>
      SkillsErrorCode.sourceReplacementRequired,
    InitialImportFailureCode.dirtyDraftResolutionRequired =>
      SkillsErrorCode.dirtyDraftResolutionRequired,
    InitialImportFailureCode.sourceReacquisitionFailed =>
      SkillsErrorCode.sourceUnavailable,
    InitialImportFailureCode.staleExternalCandidate =>
      SkillsErrorCode.staleSnapshot,
    InitialImportFailureCode.staleInstallTakeover =>
      SkillsErrorCode.staleInstallTakeover,
    InitialImportFailureCode.externalConflict =>
      SkillsErrorCode.externalConflict,
    InitialImportFailureCode.activationUnavailable =>
      SkillsErrorCode.activationUnavailable,
    InitialImportFailureCode.activationUnsupported =>
      SkillsErrorCode.activationUnsupported,
    InitialImportFailureCode.agentNotFound => SkillsErrorCode.agentNotFound,
    InitialImportFailureCode.projectRootNotFound =>
      SkillsErrorCode.projectRootNotFound,
    InitialImportFailureCode.sourcePayloadInvalid =>
      SkillsErrorCode.invalidSkill,
    InitialImportFailureCode.revisionPreparationFailed =>
      SkillsErrorCode.operationFailed,
  },
  context: failure.context,
  warnings: <SkillsWarning>[
    ..._sourceWarnings(failure.sourceWarnings),
    ..._activationWarnings(failure.activationWarnings),
  ],
);

SkillsResult<InstallAttempt> _installAttempt(
  SkillsResult<MutationReport> result,
) => result.fold<SkillsResult<InstallAttempt>>(
  onSuccess: (success) => SkillsSuccess<InstallAttempt>(
    value: InstallCompleted(success.value),
    changed: success.changed,
    warnings: success.warnings,
  ),
  onFailure: (failure) => SkillsFailure<InstallAttempt>(
    code: failure.code,
    context: failure.context,
    diagnostic: failure.diagnostic,
    warnings: failure.warnings,
  ),
  onCommittedFinalizationPending: (pending) =>
      SkillsCommittedFinalizationPending<InstallAttempt>(
        operationId: pending.operationId,
        committedRepositoryRevision: pending.committedRepositoryRevision,
        warnings: pending.warnings,
      ),
);

SkillsFailure<T> _staleInstallDraft<T>(
  _InstallTakeoverDraft draft,
  RepositorySnapshot snapshot, {
  required String reason,
}) => SkillsFailure<T>(
  code: SkillsErrorCode.staleInstallTakeover,
  context: <String, Object?>{
    'expectedRepositoryRevision': draft.reviewedRevision.value,
    'actualRepositoryRevision': snapshot.revision.value,
    'reason': reason,
  },
);

final class _InstallTakeoverDraft implements InstallTakeoverDraft {
  _InstallTakeoverDraft({
    required this.reviewedRevision,
    required this.request,
    required this.acquiredSource,
    required this.sourceWarnings,
    required InitialImportTakeoverInspection inspection,
  }) : targets = List<OccupiedInstallTarget>.unmodifiable(
         inspection.occupancies.map(_publicInstallOccupancy),
       ),
       fingerprintsByTargetPath = inspection.fingerprintsByTargetPath,
       targetSignatures = inspection.targetSignatures;

  @override
  final RepositoryRevision reviewedRevision;
  @override
  final List<OccupiedInstallTarget> targets;

  final InstallRequest request;
  final AcquiredSource acquiredSource;
  final List<SourceAcquisitionWarning> sourceWarnings;
  final Map<String, String> fingerprintsByTargetPath;
  final Map<String, String> targetSignatures;
}

OccupiedInstallTarget _publicInstallOccupancy(
  InspectedActivationOccupancy occupancy,
) => OccupiedInstallTarget(
  slotKey: occupancy.slotKey,
  location: occupancy.target.location,
  targetPath: occupancy.targetPath,
  agentIds: occupancy.target.agentIds,
  kind: switch (occupancy.kind) {
    InspectedActivationOccupancyKind.skillDirectory =>
      ActivationTargetOccupancyKind.skillDirectory,
    InspectedActivationOccupancyKind.skillSymbolicLink =>
      ActivationTargetOccupancyKind.skillSymbolicLink,
    InspectedActivationOccupancyKind.file => ActivationTargetOccupancyKind.file,
    InspectedActivationOccupancyKind.invalidDirectory =>
      ActivationTargetOccupancyKind.invalidDirectory,
    InspectedActivationOccupancyKind.brokenSymbolicLink =>
      ActivationTargetOccupancyKind.brokenSymbolicLink,
    InspectedActivationOccupancyKind.unsupported => throw StateError(
      'An unsupported target cannot enter an install takeover draft.',
    ),
  },
  contentRelation: switch (occupancy.contentRelation) {
    InspectedActivationContentRelation.matchesCurrentRevision =>
      ActivationContentRelation.matchesCurrentRevision,
    InspectedActivationContentRelation.differsFromCurrentRevision =>
      ActivationContentRelation.differsFromCurrentRevision,
    InspectedActivationContentRelation.indeterminate =>
      ActivationContentRelation.indeterminate,
  },
  existingDeclaredName: occupancy.existingDeclaredName,
  linkTarget: occupancy.linkTarget,
);

SkillsFailure<T> _sourceFailure<T>(
  SourceAcquisitionFailure<Object?> failure,
) => SkillsFailure<T>(
  code: switch (failure.code) {
    SourceAcquisitionFailureCode.sourceUnavailable =>
      SkillsErrorCode.sourceUnavailable,
    SourceAcquisitionFailureCode.sourceAuthenticationRequired =>
      SkillsErrorCode.sourceAuthenticationRequired,
    SourceAcquisitionFailureCode.gitUnavailable =>
      SkillsErrorCode.gitUnavailable,
    SourceAcquisitionFailureCode.gitFailed ||
    SourceAcquisitionFailureCode.gitTimedOut => SkillsErrorCode.gitFailed,
    SourceAcquisitionFailureCode.developerToolsRequired =>
      SkillsErrorCode.developerToolsRequired,
    SourceAcquisitionFailureCode.transportRejected =>
      SkillsErrorCode.transportRejected,
    SourceAcquisitionFailureCode.httpFailure => SkillsErrorCode.httpFailure,
    SourceAcquisitionFailureCode.digestMismatch =>
      SkillsErrorCode.digestMismatch,
    SourceAcquisitionFailureCode.archiveInvalid =>
      SkillsErrorCode.archiveInvalid,
    SourceAcquisitionFailureCode.skillNotFound => SkillsErrorCode.skillNotFound,
    SourceAcquisitionFailureCode.invalidSkill => SkillsErrorCode.invalidSkill,
    SourceAcquisitionFailureCode.unsupportedSkillName =>
      SkillsErrorCode.unsupportedSkillName,
    SourceAcquisitionFailureCode.skillContentLimitExceeded =>
      SkillsErrorCode.skillContentLimitExceeded,
    SourceAcquisitionFailureCode.duplicateSkillSlot =>
      SkillsErrorCode.duplicateSkillSlot,
    SourceAcquisitionFailureCode.updateUnsupported =>
      SkillsErrorCode.updateUnsupported,
    SourceAcquisitionFailureCode.operationCancelled =>
      SkillsErrorCode.operationCancelled,
    SourceAcquisitionFailureCode.ioFailure => SkillsErrorCode.ioFailure,
  },
  context: failure.context,
  warnings: _sourceWarnings(failure.warnings),
);

SkillsFailure<T> _externalFailure<T>(
  ExternalDiscoveryFailure<Object?> failure,
) => SkillsFailure<T>(
  code: switch (failure.code) {
    ExternalDiscoveryFailureCode.agentNotFound => SkillsErrorCode.agentNotFound,
    ExternalDiscoveryFailureCode.activationUnsupported =>
      SkillsErrorCode.activationUnsupported,
    ExternalDiscoveryFailureCode.projectRootNotFound =>
      SkillsErrorCode.projectRootNotFound,
    ExternalDiscoveryFailureCode.sourceUnavailable =>
      SkillsErrorCode.sourceUnavailable,
    ExternalDiscoveryFailureCode.invalidSkill => SkillsErrorCode.invalidSkill,
    ExternalDiscoveryFailureCode.contentLimitExceeded =>
      SkillsErrorCode.skillContentLimitExceeded,
    ExternalDiscoveryFailureCode.operationCancelled =>
      SkillsErrorCode.operationCancelled,
    ExternalDiscoveryFailureCode.ioFailure => SkillsErrorCode.ioFailure,
  },
  context: failure.context,
  warnings: _externalWarnings(failure.warnings),
);

List<SkillsWarning> _sourceWarnings(List<SourceAcquisitionWarning> warnings) =>
    warnings
        .map(
          (warning) => SkillsWarning(
            code: SkillsWarningCode.sourceEntrySkipped,
            context: warning.context,
          ),
        )
        .toList(growable: false);

List<SkillsWarning> _activationWarnings(List<ActivationWarning> warnings) =>
    warnings
        .map(
          (warning) => SkillsWarning(
            code: switch (warning.code) {
              ActivationWarningCode.noActivationTarget =>
                SkillsWarningCode.noActivationTarget,
              ActivationWarningCode.projectSymbolicLinkPortability =>
                SkillsWarningCode.projectSymbolicLinkPortability,
              ActivationWarningCode.duplicateExposure =>
                SkillsWarningCode.duplicateExposure,
              ActivationWarningCode.activationTargetSkipped =>
                SkillsWarningCode.activationTargetSkipped,
              ActivationWarningCode.sharedActivationLocation =>
                SkillsWarningCode.sharedActivationLocation,
            },
            context: warning.context,
          ),
        )
        .toList(growable: false);

List<SkillsWarning> _externalWarnings(
  List<ExternalDiscoveryWarning> warnings,
) => warnings
    .map(
      (warning) => SkillsWarning(
        code: switch (warning.code) {
          ExternalDiscoveryWarningCode.noActivationTarget =>
            SkillsWarningCode.noActivationTarget,
          ExternalDiscoveryWarningCode.projectSymbolicLinkPortability =>
            SkillsWarningCode.projectSymbolicLinkPortability,
          ExternalDiscoveryWarningCode.duplicateExposure =>
            SkillsWarningCode.duplicateExposure,
          ExternalDiscoveryWarningCode.activationTargetSkipped =>
            SkillsWarningCode.activationTargetSkipped,
          ExternalDiscoveryWarningCode.sourceEntrySkipped =>
            SkillsWarningCode.sourceEntrySkipped,
          ExternalDiscoveryWarningCode.sharedActivationLocation =>
            SkillsWarningCode.sharedActivationLocation,
        },
        context: warning.context,
      ),
    )
    .toList(growable: false);

SkillsErrorCode _abortCode(OperationAbortReason reason) => switch (reason) {
  OperationAbortReason.cancelled => SkillsErrorCode.operationCancelled,
  OperationAbortReason.staleRepositoryRevision ||
  OperationAbortReason.externalPreconditionChanged =>
    SkillsErrorCode.staleSnapshot,
  OperationAbortReason.lockUnavailable => SkillsErrorCode.repositoryBusy,
  OperationAbortReason.snapshotReadFailed => SkillsErrorCode.stateCorrupt,
  OperationAbortReason.journalWriteFailed => SkillsErrorCode.journalCorrupt,
  OperationAbortReason.preparationFailed ||
  OperationAbortReason.applyFailed ||
  OperationAbortReason.businessCommitFailed => SkillsErrorCode.operationFailed,
};

final class _InitialImportPreparationRejected implements Exception {
  const _InitialImportPreparationRejected();
}
