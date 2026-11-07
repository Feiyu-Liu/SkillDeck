import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/ports/update_ports.dart';
import '../application/runtime/revision_engine_port.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../application/source/source_acquisition_models.dart';
import '../application/update/update_command_ports.dart';
import '../application/update/update_models.dart';
import '../application/update/update_planner.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'mutation_command_support.dart';

List<SkillsCommandHandler> buildUpdateCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required UpdatePlanner updates,
  required UpdateCandidatePlanner candidates,
  required UpdatePlanAssembler assembler,
  required UpdateRevisionPreparationPort revisions,
  required UpdateOperationPlanPort plans,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<UpdateRequest, MutationReport>(
    kind: WorkspaceOperationKind.update,
    handle: (request, context) => _update(
      request: request,
      context: context,
      snapshots: snapshots,
      operations: operations,
      updates: updates,
      assembler: assembler,
      revisions: revisions,
      plans: plans,
    ),
  ),
  TypedSkillsCommandHandler<PublishUpdateCandidateRequest, MutationReport>(
    kind: WorkspaceOperationKind.publishUpdateCandidate,
    handle: (request, context) => _publishCandidate(
      request: request,
      context: context,
      snapshots: snapshots,
      operations: operations,
      candidates: candidates,
      assembler: assembler,
      revisions: revisions,
      plans: plans,
    ),
  ),
  TypedSkillsCommandHandler<ResolveUpdateConflictRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.resolveUpdateConflict,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final planned = await candidates.planResolution(
        snapshot: snapshot,
        managedSkillId: request.managedSkillId,
        path: request.path,
        resolutionState: request.resolutionState,
        cancellationToken: context.cancellationToken,
      );
      final failure = planned.failureOrNull;
      if (failure != null) return _updateFailure<RepositorySnapshot>(failure);
      final resolution = planned.valueOrNull!;
      if (!resolution.changed) {
        return SkillsSuccess<RepositorySnapshot>(
          value: snapshot,
          changed: false,
        );
      }
      return executeMutation<RepositorySnapshot>(
        context: context,
        planningSnapshot: snapshot,
        operations: operations,
        buildPlan: (operationId, currentRevision) =>
            plans.createConflictResolutionPlan(
              operationId: operationId,
              expectedRepositoryRevision: currentRevision,
              managedSkillId: request.managedSkillId,
              resolutionPlan: resolution,
            ),
        snapshots: snapshots,
        valueFromSnapshot: (committed) => committed,
      );
    },
  ),
  TypedSkillsCommandHandler<AbandonUpdateCandidateRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.abandonUpdateCandidate,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final planned = await candidates.planAbandon(
        snapshot: snapshot,
        managedSkillId: request.managedSkillId,
        cancellationToken: context.cancellationToken,
      );
      final failure = planned.failureOrNull;
      if (failure != null) return _updateFailure<RepositorySnapshot>(failure);
      final abandonPlan = planned.valueOrNull!;
      UpdatePlanningFailure<Object?>? preparationFailure;
      final outcome = await operations
          .executeDeferred<PreparedUpdateCandidateAbandon>(
            operationId: context.operationId,
            expectedRepositoryRevision: snapshot.revision,
            lockWaitPolicy: context.lockWaitPolicy,
            buildEnvelope: (operationId, currentRevision) =>
                plans.createCandidateAbandonEnvelope(
                  operationId: operationId,
                  expectedRepositoryRevision: currentRevision,
                  abandonPlan: abandonPlan,
                ),
            prepareCandidate: (envelope, cancellationToken) async {
              final prepared = await revisions.prepareCandidateAbandon(
                operationId: envelope.operationId,
                intent: abandonPlan.cleanupIntent,
                cancellationToken: cancellationToken,
              );
              if (prepared case UpdateCandidateAbandonPreparationFailure(
                :final code,
                :final detail,
              )) {
                preparationFailure = _preparationFailure(code, detail);
                throw const _UpdatePreparationRejected();
              }
              return (prepared as UpdateCandidateAbandonPreparationSuccess)
                  .prepared;
            },
            buildPlan: (envelope, prepared) => plans.sealCandidateAbandonPlan(
              envelope: envelope,
              abandonPlan: abandonPlan,
              prepared: prepared,
            ),
            cancellationToken: context.cancellationToken,
            onBusinessCommitted: () {
              context.markBusinessCommitted();
              context.reportProgress(OperationProgressPhase.committing);
            },
          );
      if (preparationFailure case final failure?) {
        if (outcome is OperationRolledBack) {
          return _updateFailure<RepositorySnapshot>(failure);
        }
      }
      return mapMutationOutcome<RepositorySnapshot>(
        outcome: outcome,
        context: context,
        snapshots: snapshots,
        valueFromSnapshot: (committed) => committed,
      );
    },
  ),
];

Future<SkillsResult<MutationReport>> _update({
  required UpdateRequest request,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required UpdatePlanner updates,
  required UpdatePlanAssembler assembler,
  required UpdateRevisionPreparationPort revisions,
  required UpdateOperationPlanPort plans,
}) async {
  context.reportProgress(OperationProgressPhase.inspecting);
  final snapshot = snapshots.current;
  final ids = request.managedSkillIds.toList()
    ..sort((left, right) => left.value.compareTo(right.value));
  final preflights = <UpdatePreparationRequired>[];
  final warnings = <SkillsWarning>[];
  // Reject every pre-existing dirty Draft/Session before importing any Source
  // in this batch. Each subsequent planUpdate repeats the check to catch a
  // Draft save that races this initial barrier.
  for (final id in ids) {
    final barrier = await updates.validateUpdateBarrier(
      snapshot: snapshot,
      managedSkillId: id,
      cancellationToken: context.cancellationToken,
    );
    if (barrier.failureOrNull case final failure?) {
      return _updateFailure<MutationReport>(failure);
    }
  }
  for (var index = 0; index < ids.length; index += 1) {
    final id = ids[index];
    context.reportProgress(
      OperationProgressPhase.inspecting,
      currentItem: id.value,
      completed: index,
      total: ids.length,
    );
    final planned = await updates.planUpdate(
      snapshot: snapshot,
      managedSkillId: id,
      cancellationToken: context.cancellationToken,
    );
    final failure = planned.failureOrNull;
    if (failure != null) {
      return _updateFailure<MutationReport>(failure, extraWarnings: warnings);
    }
    final value = planned.valueOrNull!;
    if (value case UpdateNoChange(:final sourceWarnings)) {
      warnings.addAll(_sourceWarnings(sourceWarnings));
      continue;
    }
    final preflight = value as UpdatePreparationRequired;
    warnings.addAll(_sourceWarnings(preflight.sourceWarnings));
    preflights.add(preflight);
  }
  if (preflights.isEmpty) {
    return SkillsSuccess<MutationReport>(
      value: MutationReport(
        snapshot: snapshot,
        affectedSkillIds: const <ManagedSkillId>{},
      ),
      changed: false,
      warnings: warnings,
    );
  }

  UpdatePlanningFailure<Object?>? preparationFailure;
  final outcome = await operations.executeDeferred<List<PreparedUpdatePlan>>(
    operationId: context.operationId,
    expectedRepositoryRevision: snapshot.revision,
    lockWaitPolicy: context.lockWaitPolicy,
    buildEnvelope: (operationId, currentRevision) => plans.createUpdateEnvelope(
      operationId: operationId,
      expectedRepositoryRevision: currentRevision,
      preflights: preflights,
    ),
    prepareCandidate: (envelope, cancellationToken) async {
      final assembled = <PreparedUpdatePlan>[];
      for (final preflight in preflights) {
        final prepared = await revisions.prepareUpdate(
          operationId: envelope.operationId,
          intent: preflight.intent,
          cancellationToken: cancellationToken,
        );
        if (prepared case UpdateRevisionPreparationFailure(
          :final code,
          :final detail,
        )) {
          preparationFailure = _preparationFailure(code, detail);
          throw const _UpdatePreparationRejected();
        }
        final result = assembler.assembleUpdate(
          preflight: preflight,
          prepared: (prepared as UpdateRevisionPreparationSuccess).prepared,
        );
        if (result.failureOrNull case final failure?) {
          preparationFailure = failure;
          throw const _UpdatePreparationRejected();
        }
        assembled.add(result.valueOrNull!);
      }
      return assembled;
    },
    buildPlan: (envelope, preparedPlans) => plans.sealUpdatePlan(
      envelope: envelope,
      preflights: preflights,
      preparedPlans: preparedPlans,
    ),
    cancellationToken: context.cancellationToken,
    onBusinessCommitted: () {
      context.markBusinessCommitted();
      context.reportProgress(OperationProgressPhase.committing);
    },
  );
  if (preparationFailure case final failure?) {
    if (outcome is OperationRolledBack) {
      return _updateFailure<MutationReport>(failure, extraWarnings: warnings);
    }
  }
  return _mapMutationOutcome(
    outcome: outcome,
    affectedSkillIds: preflights.map((item) => item.managedSkillId).toSet(),
    warnings: warnings,
    context: context,
    snapshots: snapshots,
  );
}

Future<SkillsResult<MutationReport>> _publishCandidate({
  required PublishUpdateCandidateRequest request,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required UpdateCandidatePlanner candidates,
  required UpdatePlanAssembler assembler,
  required UpdateRevisionPreparationPort revisions,
  required UpdateOperationPlanPort plans,
}) async {
  context.reportProgress(OperationProgressPhase.inspecting);
  final snapshot = snapshots.current;
  final planned = await candidates.planPublish(
    snapshot: snapshot,
    managedSkillId: request.managedSkillId,
    cancellationToken: context.cancellationToken,
  );
  final failure = planned.failureOrNull;
  if (failure != null) return _updateFailure<MutationReport>(failure);
  final preflight = planned.valueOrNull!;

  UpdatePlanningFailure<Object?>? preparationFailure;
  final outcome = await operations.executeDeferred<PreparedUpdatePlan>(
    operationId: context.operationId,
    expectedRepositoryRevision: preflight.snapshotRevision,
    lockWaitPolicy: context.lockWaitPolicy,
    buildEnvelope: (operationId, currentRevision) =>
        plans.createCandidatePublishEnvelope(
          operationId: operationId,
          expectedRepositoryRevision: currentRevision,
          preflight: preflight,
        ),
    prepareCandidate: (envelope, cancellationToken) async {
      final prepared = await revisions.prepareCandidatePublish(
        operationId: envelope.operationId,
        intent: preflight.intent,
        cancellationToken: cancellationToken,
      );
      if (prepared case UpdateCandidatePublishPreparationFailure(
        :final code,
        :final detail,
      )) {
        preparationFailure = _preparationFailure(code, detail);
        throw const _UpdatePreparationRejected();
      }
      final assembled = assembler.assembleCandidatePublish(
        preflight: preflight,
        prepared:
            (prepared as UpdateCandidatePublishPreparationSuccess).prepared,
      );
      if (assembled.failureOrNull case final failure?) {
        preparationFailure = failure;
        throw const _UpdatePreparationRejected();
      }
      return assembled.valueOrNull!;
    },
    buildPlan: (envelope, preparedPlan) => plans.sealCandidatePublishPlan(
      envelope: envelope,
      preflight: preflight,
      preparedPlan: preparedPlan,
    ),
    cancellationToken: context.cancellationToken,
    onBusinessCommitted: () {
      context.markBusinessCommitted();
      context.reportProgress(OperationProgressPhase.committing);
    },
  );
  if (preparationFailure case final failure?) {
    if (outcome is OperationRolledBack) {
      return _updateFailure<MutationReport>(failure);
    }
  }
  return _mapMutationOutcome(
    outcome: outcome,
    affectedSkillIds: <ManagedSkillId>{request.managedSkillId},
    warnings: const <SkillsWarning>[],
    context: context,
    snapshots: snapshots,
  );
}

Future<SkillsResult<MutationReport>> _mapMutationOutcome({
  required OperationExecutionOutcome outcome,
  required Set<ManagedSkillId> affectedSkillIds,
  required List<SkillsWarning> warnings,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
}) async => switch (outcome) {
  OperationCompleted(
    :final operationId,
    :final committedRepositoryRevision,
    :final cleanupPending,
  ) =>
    _reloadMutation(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      affectedSkillIds: affectedSkillIds,
      warnings: <SkillsWarning>[
        ...warnings,
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
    SkillsCommittedFinalizationPending<MutationReport>(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      warnings: <SkillsWarning>[
        ...warnings,
        SkillsWarning(code: SkillsWarningCode.finalizationDeferred),
      ],
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
      warnings: warnings,
    ),
  OperationRolledBack(:final reason, :final detail) =>
    SkillsFailure<MutationReport>(
      code: _abortCode(reason),
      context: <String, Object?>{
        'reason': reason.name,
        if (detail != null) 'detail': detail.name,
      },
      warnings: warnings,
    ),
  OperationRollbackPending(:final originalReason) =>
    SkillsFailure<MutationReport>(
      code: SkillsErrorCode.recoveryFailed,
      context: <String, Object?>{'reason': originalReason.name},
      warnings: warnings,
    ),
};

Future<SkillsResult<MutationReport>> _reloadMutation({
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

UpdatePlanningFailure<Object?> _preparationFailure(
  UpdateRevisionPreparationFailureCode code,
  RevisionEngineFailureCode? detail,
) => UpdatePlanningFailure<Object?>(
  code: switch (code) {
    UpdateRevisionPreparationFailureCode.operationCancelled =>
      UpdatePlanningFailureCode.operationCancelled,
    UpdateRevisionPreparationFailureCode.dirtyDraftResolutionRequired =>
      UpdatePlanningFailureCode.dirtyDraftResolutionRequired,
    UpdateRevisionPreparationFailureCode.unresolvedUpdateConflicts =>
      UpdatePlanningFailureCode.unresolvedUpdateConflicts,
    UpdateRevisionPreparationFailureCode.declaredNameChangeNotAllowed =>
      UpdatePlanningFailureCode.declaredNameChangeNotAllowed,
    UpdateRevisionPreparationFailureCode.staleIntent =>
      UpdatePlanningFailureCode.staleIntent,
    UpdateRevisionPreparationFailureCode.draftChangedDuringPublish =>
      UpdatePlanningFailureCode.draftChangedDuringPublish,
    UpdateRevisionPreparationFailureCode.invalidSkill =>
      UpdatePlanningFailureCode.invalidSkill,
    UpdateRevisionPreparationFailureCode.revisionStoreUnavailable =>
      UpdatePlanningFailureCode.revisionStoreUnavailable,
    UpdateRevisionPreparationFailureCode.recoveryEvidenceFailed =>
      UpdatePlanningFailureCode.recoveryEvidenceFailed,
    UpdateRevisionPreparationFailureCode.ioFailure =>
      UpdatePlanningFailureCode.ioFailure,
  },
  context: <String, Object?>{
    'preparationCode': code.name,
    if (detail != null) 'detail': detail.name,
  },
);

SkillsFailure<T> _updateFailure<T>(
  UpdatePlanningFailure<Object?> failure, {
  List<SkillsWarning> extraWarnings = const <SkillsWarning>[],
}) => SkillsFailure<T>(
  code: switch (failure.code) {
    UpdatePlanningFailureCode.operationCancelled =>
      SkillsErrorCode.operationCancelled,
    UpdatePlanningFailureCode.skillNotFound => SkillsErrorCode.skillNotFound,
    UpdatePlanningFailureCode.updateUnsupported =>
      SkillsErrorCode.updateUnsupported,
    UpdatePlanningFailureCode.updateCandidateResolutionRequired ||
    UpdatePlanningFailureCode.updateCandidateNotFound ||
    UpdatePlanningFailureCode.updateConflictNotFound ||
    UpdatePlanningFailureCode.unresolvedUpdateConflicts =>
      SkillsErrorCode.updateCandidateResolutionRequired,
    UpdatePlanningFailureCode.dirtyDraftResolutionRequired =>
      SkillsErrorCode.dirtyDraftResolutionRequired,
    UpdatePlanningFailureCode.unsupportedSkillName =>
      SkillsErrorCode.unsupportedSkillName,
    UpdatePlanningFailureCode.declaredNameChangeNotAllowed =>
      SkillsErrorCode.declaredNameChangeNotAllowed,
    UpdatePlanningFailureCode.staleIntent => SkillsErrorCode.staleSnapshot,
    UpdatePlanningFailureCode.draftChangedDuringPublish =>
      SkillsErrorCode.draftChangedDuringPublish,
    UpdatePlanningFailureCode.invalidSkill => SkillsErrorCode.invalidSkill,
    UpdatePlanningFailureCode.revisionStoreUnavailable =>
      SkillsErrorCode.revisionStoreCorrupt,
    UpdatePlanningFailureCode.recoveryEvidenceFailed =>
      SkillsErrorCode.recoveryFailed,
    UpdatePlanningFailureCode.ioFailure => SkillsErrorCode.ioFailure,
    UpdatePlanningFailureCode.sourceAcquisitionFailed ||
    UpdatePlanningFailureCode.sourceContinuityLost =>
      SkillsErrorCode.sourceUnavailable,
    UpdatePlanningFailureCode.slotMigrationConflict =>
      SkillsErrorCode.duplicateSkillSlot,
    UpdatePlanningFailureCode.draftInspectionFailed ||
    UpdatePlanningFailureCode.revisionStateUnavailable ||
    UpdatePlanningFailureCode.invalidPreparedEvidence =>
      SkillsErrorCode.operationFailed,
  },
  context: failure.context,
  warnings: <SkillsWarning>[
    ...extraWarnings,
    ..._sourceWarnings(failure.sourceWarnings),
  ],
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

final class _UpdatePreparationRejected implements Exception {
  const _UpdatePreparationRejected();
}
