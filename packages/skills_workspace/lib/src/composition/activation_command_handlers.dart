import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/activation/activation_models.dart';
import '../application/activation/activation_mutation_models.dart';
import '../application/activation/activation_mutation_planner.dart';
import '../application/activation/activation_occupancy_inspector.dart';
import '../application/activation/activation_result.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_plan_assembler.dart';
import '../application/ports/activation_mutation_ports.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'mutation_command_support.dart';

/// Builds Activation mutations without exposing filesystem or Drift adapters.
List<SkillsCommandHandler> buildActivationCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required ActivationOccupancyInspector Function() occupancyInspector,
  required ActivationMetadataReaderPort activationMetadata,
  required ActivationMutationPlanner activationMutations,
  required ActivationOperationPlanPort plans,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<ActivateRequest, ActivationAttempt>(
    kind: WorkspaceOperationKind.activate,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final inspected = await occupancyInspector().inspect(
        snapshot: snapshot,
        managedSkillIds: request.managedSkillIds,
        selection: request.selection,
        mode: request.mode,
        cancellationToken: context.cancellationToken,
      );
      final inspection = inspected.valueOrNull;
      if (inspection == null) {
        return _activationFailure<ActivationAttempt>(inspected.failureOrNull!);
      }
      if (!inspection.canReplace) {
        return _blockedOccupancy<ActivationAttempt>(inspection);
      }
      if (inspection.occupancies.isNotEmpty && !inspection.allContentMatches) {
        final draft = _ActivationTakeoverDraft(
          reviewedRevision: snapshot.revision,
          request: request,
          inspection: inspection,
        );
        return SkillsSuccess<ActivationAttempt>(
          value: ActivationTakeoverRequired(draft),
          changed: false,
          warnings: _warnings(inspection.warnings),
        );
      }
      return _applyActivation(
        kind: WorkspaceOperationKind.activate,
        snapshot: snapshot,
        managedSkillIds: request.managedSkillIds,
        inspection: inspection,
        context: context,
        snapshots: snapshots,
        operations: operations,
        activationMetadata: activationMetadata,
        activationMutations: activationMutations,
        plans: plans,
      );
    },
  ),
  TypedSkillsCommandHandler<ConfirmActivationTakeoverRequest, MutationReport>(
    kind: WorkspaceOperationKind.confirmActivationTakeover,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final draft = request.draft;
      if (draft is! _ActivationTakeoverDraft) {
        return SkillsFailure<MutationReport>(
          code: SkillsErrorCode.operationFailed,
          context: const <String, Object?>{
            'reason': 'invalidActivationTakeoverDraft',
          },
        );
      }
      final snapshot = snapshots.current;
      if (snapshot.revision != draft.reviewedRevision) {
        return _staleDraft<MutationReport>(
          draft,
          snapshot,
          reason: 'repositoryRevisionChanged',
        );
      }
      final inspected = await occupancyInspector().inspect(
        snapshot: snapshot,
        managedSkillIds: draft.request.managedSkillIds,
        selection: draft.request.selection,
        mode: draft.request.mode,
        cancellationToken: context.cancellationToken,
      );
      final inspection = inspected.valueOrNull;
      if (inspection == null) {
        final failure = inspected.failureOrNull!;
        if (failure.code == ActivationFailureCode.operationCancelled) {
          return _activationFailure<MutationReport>(failure);
        }
        return _staleDraft<MutationReport>(
          draft,
          snapshot,
          reason: 'activationIntentUnavailable',
        );
      }
      if (!_sameStrings(
            draft.targetSignatures,
            _targetSignatures(inspection.resolvedTargets),
          ) ||
          !_sameStrings(
            draft.fingerprintsByTargetPath,
            _fingerprints(inspection),
          )) {
        return _staleDraft<MutationReport>(
          draft,
          snapshot,
          reason: 'activationTargetChanged',
        );
      }
      if (!inspection.canReplace) {
        return _blockedOccupancy<MutationReport>(inspection);
      }
      final result = await _applyActivationReport(
        kind: WorkspaceOperationKind.confirmActivationTakeover,
        snapshot: snapshot,
        managedSkillIds: draft.request.managedSkillIds,
        inspection: inspection,
        context: context,
        snapshots: snapshots,
        operations: operations,
        activationMetadata: activationMetadata,
        activationMutations: activationMutations,
        plans: plans,
      );
      return result;
    },
  ),
  TypedSkillsCommandHandler<DeactivateRequest, MutationReport>(
    kind: WorkspaceOperationKind.deactivate,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final persisted = await _readActivationMetadata<MutationReport>(
        activationMetadata,
        request.managedSkillIds,
      );
      if (persisted.failure != null) return persisted.failure!;
      final planned = activationMutations.deactivate(
        snapshot: snapshot,
        managedSkillIds: request.managedSkillIds,
        locations: request.locations,
        persistedActivations: persisted.value!,
      );
      final failure = planned.failureOrNull;
      if (failure != null) return _planningFailure<MutationReport>(failure);
      return _executeReport(
        kind: WorkspaceOperationKind.deactivate,
        snapshot: snapshot,
        mutation: planned.valueOrNull!,
        context: context,
        snapshots: snapshots,
        operations: operations,
        plans: plans,
      );
    },
  ),
];

Future<SkillsResult<ActivationAttempt>> _applyActivation({
  required WorkspaceOperationKind kind,
  required RepositorySnapshot snapshot,
  required Set<ManagedSkillId> managedSkillIds,
  required ActivationTakeoverInspection inspection,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required ActivationMetadataReaderPort activationMetadata,
  required ActivationMutationPlanner activationMutations,
  required ActivationOperationPlanPort plans,
}) async {
  final result = await _applyActivationReport(
    kind: kind,
    snapshot: snapshot,
    managedSkillIds: managedSkillIds,
    inspection: inspection,
    context: context,
    snapshots: snapshots,
    operations: operations,
    activationMetadata: activationMetadata,
    activationMutations: activationMutations,
    plans: plans,
  );
  return result.fold<SkillsResult<ActivationAttempt>>(
    onSuccess: (success) => SkillsSuccess<ActivationAttempt>(
      value: ActivationCompleted(success.value),
      changed: success.changed,
      warnings: success.warnings,
    ),
    onFailure: (failure) => SkillsFailure<ActivationAttempt>(
      code: failure.code,
      context: failure.context,
      diagnostic: failure.diagnostic,
      warnings: failure.warnings,
    ),
    onCommittedFinalizationPending: (pending) =>
        SkillsCommittedFinalizationPending<ActivationAttempt>(
          operationId: pending.operationId,
          committedRepositoryRevision: pending.committedRepositoryRevision,
          warnings: pending.warnings,
        ),
  );
}

Future<SkillsResult<MutationReport>> _applyActivationReport({
  required WorkspaceOperationKind kind,
  required RepositorySnapshot snapshot,
  required Set<ManagedSkillId> managedSkillIds,
  required ActivationTakeoverInspection inspection,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required ActivationMetadataReaderPort activationMetadata,
  required ActivationMutationPlanner activationMutations,
  required ActivationOperationPlanPort plans,
}) async {
  final persisted = await _readActivationMetadata<MutationReport>(
    activationMetadata,
    managedSkillIds,
  );
  if (persisted.failure != null) return persisted.failure!;
  final planned = activationMutations.activate(
    snapshot: snapshot,
    managedSkillIds: managedSkillIds,
    resolvedTargets: inspection.resolvedTargets,
    occupancies: inspection.occupancies,
    persistedActivations: persisted.value!,
  );
  final failure = planned.failureOrNull;
  if (failure != null) return _planningFailure<MutationReport>(failure);
  return _executeReport(
    kind: kind,
    snapshot: snapshot,
    mutation: planned.valueOrNull!,
    context: context,
    snapshots: snapshots,
    operations: operations,
    plans: plans,
  );
}

Future<SkillsResult<MutationReport>> _executeReport({
  required WorkspaceOperationKind kind,
  required RepositorySnapshot snapshot,
  required ActivationMutationPlan mutation,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required ActivationOperationPlanPort plans,
}) async {
  final warnings = _warnings(mutation.warnings);
  if (!mutation.changed) {
    return SkillsSuccess<MutationReport>(
      value: MutationReport(
        snapshot: snapshot,
        affectedSkillIds: mutation.affectedSkillIds,
      ),
      changed: false,
      warnings: warnings,
    );
  }
  final subjects = <OperationSubjectIntent>[
    for (final managedSkillId in mutation.affectedSkillIds)
      if (snapshot.findSkill(managedSkillId) case final skill?)
        OperationSubjectIntent(
          managedSkillId: skill.id,
          displayName: skill.displayName,
          beforeContentHash: skill.currentRevision.contentHash,
          afterContentHash: skill.currentRevision.contentHash,
        ),
  ];
  final result = await executeMutation<MutationReport>(
    context: context,
    planningSnapshot: snapshot,
    operations: operations,
    buildPlan: (operationId, revision) => plans.assemble(
      operationId: operationId,
      expectedRepositoryRevision: revision,
      planningSnapshot: snapshot,
      kind: kind,
      mutation: mutation,
      subjects: subjects,
    ),
    snapshots: snapshots,
    valueFromSnapshot: (committed) => MutationReport(
      snapshot: committed,
      affectedSkillIds: mutation.affectedSkillIds,
    ),
  );
  return _appendWarnings(result, warnings);
}

Future<_MetadataRead<T>> _readActivationMetadata<T>(
  ActivationMetadataReaderPort reader,
  Set<ManagedSkillId> managedSkillIds,
) async {
  try {
    return _MetadataRead.value(await reader.readForSkills(managedSkillIds));
  } on Object {
    return _MetadataRead.failure(
      SkillsFailure<T>(
        code: SkillsErrorCode.stateCorrupt,
        context: const <String, Object?>{
          'reason': 'activationMetadataUnreadable',
        },
      ),
    );
  }
}

SkillsResult<T> _appendWarnings<T>(
  SkillsResult<T> result,
  List<SkillsWarning> warnings,
) => result.fold<SkillsResult<T>>(
  onSuccess: (success) => SkillsSuccess<T>(
    value: success.value,
    changed: success.changed,
    warnings: <SkillsWarning>[...warnings, ...success.warnings],
  ),
  onFailure: (failure) => SkillsFailure<T>(
    code: failure.code,
    context: failure.context,
    diagnostic: failure.diagnostic,
    warnings: <SkillsWarning>[...warnings, ...failure.warnings],
  ),
  onCommittedFinalizationPending: (pending) =>
      SkillsCommittedFinalizationPending<T>(
        operationId: pending.operationId,
        committedRepositoryRevision: pending.committedRepositoryRevision,
        warnings: <SkillsWarning>[...warnings, ...pending.warnings],
      ),
);

SkillsFailure<T> _planningFailure<T>(
  ActivationMutationPlanningFailure failure,
) => SkillsFailure<T>(
  code: switch (failure.code) {
    ActivationMutationFailureCode.skillNotFound =>
      SkillsErrorCode.skillNotFound,
    ActivationMutationFailureCode.activationUnsupported =>
      SkillsErrorCode.activationUnsupported,
    ActivationMutationFailureCode.activationUnavailable =>
      SkillsErrorCode.activationUnavailable,
    ActivationMutationFailureCode.stateInconsistent =>
      SkillsErrorCode.stateCorrupt,
  },
  context: failure.context,
  warnings: _warnings(failure.warnings),
);

SkillsFailure<T> _activationFailure<T>(
  ActivationFailure<Object?> failure,
) => SkillsFailure<T>(
  code: switch (failure.code) {
    ActivationFailureCode.duplicateAgentId => SkillsErrorCode.duplicateAgentId,
    ActivationFailureCode.agentNotFound => SkillsErrorCode.agentNotFound,
    ActivationFailureCode.activationUnsupported =>
      SkillsErrorCode.activationUnsupported,
    ActivationFailureCode.projectRootNotFound =>
      SkillsErrorCode.projectRootNotFound,
    ActivationFailureCode.activationUnavailable =>
      SkillsErrorCode.activationUnavailable,
    ActivationFailureCode.externalConflict => SkillsErrorCode.externalConflict,
    ActivationFailureCode.skillNotFound => SkillsErrorCode.skillNotFound,
    ActivationFailureCode.operationCancelled =>
      SkillsErrorCode.operationCancelled,
  },
  context: failure.context,
  warnings: _warnings(failure.warnings),
);

SkillsFailure<T> _blockedOccupancy<T>(ActivationTakeoverInspection inspection) {
  final blocked = inspection.occupancies.firstWhere(
    (occupancy) => !occupancy.replaceable,
  );
  return SkillsFailure<T>(
    code: SkillsErrorCode.activationUnavailable,
    context: <String, Object?>{
      'managedSkillId': blocked.managedSkillId.value,
      'location': blocked.target.location,
      'targetPath': blocked.targetPath,
      'reason': 'targetNotSafelyReplaceable',
    },
    warnings: _warnings(inspection.warnings),
  );
}

SkillsFailure<T> _staleDraft<T>(
  _ActivationTakeoverDraft draft,
  RepositorySnapshot snapshot, {
  required String reason,
}) => SkillsFailure<T>(
  code: SkillsErrorCode.staleActivationTakeover,
  context: <String, Object?>{
    'expectedRepositoryRevision': draft.reviewedRevision.value,
    'actualRepositoryRevision': snapshot.revision.value,
    'reason': reason,
  },
);

final class _ActivationTakeoverDraft implements ActivationTakeoverDraft {
  _ActivationTakeoverDraft({
    required this.reviewedRevision,
    required this.request,
    required ActivationTakeoverInspection inspection,
  }) : targets = List<OccupiedActivationTarget>.unmodifiable(
         inspection.occupancies.map(_publicOccupancy),
       ),
       fingerprintsByTargetPath = Map<String, String>.unmodifiable(
         _fingerprints(inspection),
       ),
       targetSignatures = Map<String, String>.unmodifiable(
         _targetSignatures(inspection.resolvedTargets),
       );

  @override
  final RepositoryRevision reviewedRevision;
  @override
  final List<OccupiedActivationTarget> targets;

  final ActivateRequest request;
  final Map<String, String> fingerprintsByTargetPath;
  final Map<String, String> targetSignatures;
}

OccupiedActivationTarget _publicOccupancy(
  InspectedActivationOccupancy occupancy,
) => OccupiedActivationTarget(
  managedSkillId: occupancy.managedSkillId,
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
      'An unsupported target cannot enter a takeover draft.',
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

Map<String, String> _fingerprints(ActivationTakeoverInspection inspection) =>
    <String, String>{
      for (final occupancy in inspection.occupancies)
        occupancy.targetPath: occupancy.fingerprint,
    };

Map<String, String> _targetSignatures(ResolvedActivationTargets targets) =>
    <String, String>{
      for (final target in targets.targets)
        target.location:
            '${target.scope.name}\u0000${target.mode.name}\u0000'
            '${target.projectRootId ?? ''}\u0000'
            '${target.projectRootPath ?? ''}\u0000'
            '${([...target.agentIds]..sort()).join('\u0001')}',
    };

bool _sameStrings(Map<String, String> left, Map<String, String> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

List<SkillsWarning> _warnings(List<ActivationWarning> warnings) =>
    <SkillsWarning>[
      for (final warning in warnings)
        SkillsWarning(
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
    ];

final class _MetadataRead<T> {
  const _MetadataRead.value(this.value) : failure = null;
  const _MetadataRead.failure(this.failure) : value = null;

  final List<PersistedActivation>? value;
  final SkillsFailure<T>? failure;
}
