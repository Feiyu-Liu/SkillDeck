import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/drafts/draft_models.dart';
import '../application/drafts/draft_plan_assembler.dart';
import '../application/drafts/draft_planner.dart';
import '../application/drafts/draft_ports.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'mutation_command_support.dart';

List<SkillsCommandHandler> buildDraftCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required DraftPlanner drafts,
  required DraftPlanAssembler assembler,
  required DraftRevisionPreparationPort revisions,
  required DraftOperationPlanPort plans,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<EnsureDraftRequest, DraftSummary>(
    kind: WorkspaceOperationKind.ensureDraft,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final planned = await drafts.planEnsure(
        snapshot: snapshots.current,
        managedSkillId: request.managedSkillId,
        cancellationToken: context.cancellationToken,
      );
      final failure = planned.failureOrNull;
      if (failure != null) return _draftFailure<DraftSummary>(failure);
      final value = planned.valueOrNull!;
      if (value case ExistingDraft(:final summary)) {
        return SkillsSuccess<DraftSummary>(value: summary, changed: false);
      }
      final preflight = value as EnsureDraftPreparationRequired;
      DraftPlanningFailure<PreparedEnsureDraft>? preparationFailure;
      final outcome = await operations.executeDeferred<PreparedEnsureDraft>(
        operationId: context.operationId,
        expectedRepositoryRevision: preflight.snapshotRevision,
        lockWaitPolicy: context.lockWaitPolicy,
        buildEnvelope: (operationId, currentRevision) =>
            plans.createEnsureEnvelope(
              operationId: operationId,
              expectedRepositoryRevision: currentRevision,
              preflight: preflight,
            ),
        prepareCandidate: (envelope, cancellationToken) async {
          final prepared = await revisions.prepareEnsureDraft(
            envelope: envelope,
            preflight: preflight,
            cancellationToken: cancellationToken,
          );
          if (prepared.failureOrNull case final candidateFailure?) {
            preparationFailure = candidateFailure;
            throw const _DraftPreparationRejected();
          }
          final assembled = assembler.assembleEnsure(
            preflight: preflight,
            prepared: prepared.valueOrNull!,
          );
          if (assembled.failureOrNull case final assemblyFailure?) {
            preparationFailure = DraftPlanningFailure<PreparedEnsureDraft>(
              code: assemblyFailure.code,
              context: assemblyFailure.context,
            );
            throw const _DraftPreparationRejected();
          }
          return prepared.valueOrNull!;
        },
        buildPlan: (envelope, prepared) {
          final assembled = assembler.assembleEnsure(
            preflight: preflight,
            prepared: prepared,
          );
          return plans.sealEnsurePlan(
            envelope: envelope,
            preflight: preflight,
            preparedPlan: assembled.valueOrNull!,
          );
        },
        cancellationToken: context.cancellationToken,
        onBusinessCommitted: () {
          context.markBusinessCommitted();
          context.reportProgress(OperationProgressPhase.committing);
        },
      );
      if (preparationFailure case final failure?) {
        if (outcome is OperationRolledBack) {
          return _draftFailure<DraftSummary>(failure);
        }
      }
      return _mapOutcome<DraftSummary>(
        outcome: outcome,
        context: context,
        snapshots: snapshots,
        valueFromSnapshot: (snapshot) =>
            snapshot.findSkill(request.managedSkillId)!.draft!,
      );
    },
  ),
  TypedSkillsCommandHandler<InspectDraftRequest, DraftSummary?>(
    kind: WorkspaceOperationKind.inspectDraft,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final result = await drafts.inspect(
        snapshot: snapshots.current,
        managedSkillId: request.managedSkillId,
        cancellationToken: context.cancellationToken,
      );
      final failure = result.failureOrNull;
      if (failure != null) return _draftFailure<DraftSummary?>(failure);
      return SkillsSuccess<DraftSummary?>(
        value: result.valueOrNull,
        changed: false,
      );
    },
  ),
  TypedSkillsCommandHandler<DiscardDraftRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.discardDraft,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final planned = await drafts.planDiscard(
        snapshot: snapshot,
        managedSkillId: request.managedSkillId,
        cancellationToken: context.cancellationToken,
      );
      final failure = planned.failureOrNull;
      if (failure != null) return _draftFailure<RepositorySnapshot>(failure);
      final plan = planned.valueOrNull!;
      return executeMutation<RepositorySnapshot>(
        context: context,
        planningSnapshot: snapshot,
        operations: operations,
        buildPlan: (operationId, currentRevision) => plans.createDiscardPlan(
          operationId: operationId,
          expectedRepositoryRevision: currentRevision,
          plan: plan,
        ),
        snapshots: snapshots,
        valueFromSnapshot: (committed) => committed,
      );
    },
  ),
  TypedSkillsCommandHandler<PublishDraftRequest, MutationReport>(
    kind: WorkspaceOperationKind.publishDraft,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final planned = await drafts.planPublish(
        snapshot: snapshots.current,
        managedSkillId: request.managedSkillId,
        cancellationToken: context.cancellationToken,
      );
      final failure = planned.failureOrNull;
      if (failure != null) return _draftFailure<MutationReport>(failure);
      final preflight = planned.valueOrNull!;
      DraftPlanningFailure<PreparedDraftPublish>? preparationFailure;
      final outcome = await operations.executeDeferred<PreparedDraftPublish>(
        operationId: context.operationId,
        expectedRepositoryRevision: preflight.snapshotRevision,
        lockWaitPolicy: context.lockWaitPolicy,
        buildEnvelope: (operationId, currentRevision) =>
            plans.createPublishEnvelope(
              operationId: operationId,
              expectedRepositoryRevision: currentRevision,
              preflight: preflight,
            ),
        prepareCandidate: (envelope, cancellationToken) async {
          final prepared = await revisions.preparePublishDraft(
            envelope: envelope,
            preflight: preflight,
            cancellationToken: cancellationToken,
          );
          if (prepared.failureOrNull case final candidateFailure?) {
            preparationFailure = candidateFailure;
            throw const _DraftPreparationRejected();
          }
          final assembled = assembler.assemblePublish(
            preflight: preflight,
            prepared: prepared.valueOrNull!,
          );
          if (assembled.failureOrNull case final assemblyFailure?) {
            preparationFailure = DraftPlanningFailure<PreparedDraftPublish>(
              code: assemblyFailure.code,
              context: assemblyFailure.context,
            );
            throw const _DraftPreparationRejected();
          }
          return prepared.valueOrNull!;
        },
        buildPlan: (envelope, prepared) {
          final assembled = assembler.assemblePublish(
            preflight: preflight,
            prepared: prepared,
          );
          return plans.sealPublishPlan(
            envelope: envelope,
            preflight: preflight,
            preparedPlan: assembled.valueOrNull!,
          );
        },
        cancellationToken: context.cancellationToken,
        onBusinessCommitted: () {
          context.markBusinessCommitted();
          context.reportProgress(OperationProgressPhase.committing);
        },
      );
      if (preparationFailure case final failure?) {
        if (outcome is OperationRolledBack) {
          return _draftFailure<MutationReport>(failure);
        }
      }
      return _mapOutcome<MutationReport>(
        outcome: outcome,
        context: context,
        snapshots: snapshots,
        valueFromSnapshot: (snapshot) => MutationReport(
          snapshot: snapshot,
          affectedSkillIds: <ManagedSkillId>{request.managedSkillId},
        ),
      );
    },
  ),
];

Future<SkillsResult<T>> _mapOutcome<T>({
  required OperationExecutionOutcome outcome,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required T Function(RepositorySnapshot snapshot) valueFromSnapshot,
}) async => switch (outcome) {
  OperationCompleted(
    :final operationId,
    :final committedRepositoryRevision,
    :final cleanupPending,
  ) =>
    _reloadCompleted(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      cleanupPending: cleanupPending,
      context: context,
      snapshots: snapshots,
      valueFromSnapshot: valueFromSnapshot,
    ),
  OperationCommittedFinalizationPending(
    :final operationId,
    :final committedRepositoryRevision,
  ) =>
    SkillsCommittedFinalizationPending<T>(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      warnings: <SkillsWarning>[
        SkillsWarning(code: SkillsWarningCode.finalizationDeferred),
      ],
    ),
  OperationRejected(
    :final reason,
    :final actualRepositoryRevision,
    :final detail,
  ) =>
    SkillsFailure<T>(
      code: _abortCode(reason),
      context: <String, Object?>{
        'reason': reason.name,
        if (detail != null) 'detail': detail.name,
        if (actualRepositoryRevision != null)
          'actualRepositoryRevision': actualRepositoryRevision.value,
      },
    ),
  OperationRolledBack(:final reason, :final detail) => SkillsFailure<T>(
    code: _abortCode(reason),
    context: <String, Object?>{
      'reason': reason.name,
      if (detail != null) 'detail': detail.name,
    },
  ),
  OperationRollbackPending(:final originalReason) => SkillsFailure<T>(
    code: SkillsErrorCode.recoveryFailed,
    context: <String, Object?>{'reason': originalReason.name},
  ),
};

Future<SkillsResult<T>> _reloadCompleted<T>({
  required OperationId operationId,
  required RepositoryRevision committedRepositoryRevision,
  required bool cleanupPending,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required T Function(RepositorySnapshot snapshot) valueFromSnapshot,
}) async {
  context.reportProgress(OperationProgressPhase.finalizing);
  try {
    final snapshot = await snapshots.reload();
    return SkillsSuccess<T>(
      value: valueFromSnapshot(snapshot),
      changed: true,
      warnings: cleanupPending
          ? <SkillsWarning>[
              SkillsWarning(code: SkillsWarningCode.recoveryCleanupDeferred),
            ]
          : const <SkillsWarning>[],
    );
  } on Object {
    return SkillsCommittedFinalizationPending<T>(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      warnings: <SkillsWarning>[
        SkillsWarning(code: SkillsWarningCode.finalizationDeferred),
      ],
    );
  }
}

SkillsFailure<T> _draftFailure<T>(DraftPlanningFailure<Object?> failure) =>
    SkillsFailure<T>(
      code: switch (failure.code) {
        DraftPlanningFailureCode.operationCancelled =>
          SkillsErrorCode.operationCancelled,
        DraftPlanningFailureCode.skillNotFound => SkillsErrorCode.skillNotFound,
        DraftPlanningFailureCode.updateCandidateResolutionRequired =>
          SkillsErrorCode.updateCandidateResolutionRequired,
        DraftPlanningFailureCode.draftChangedDuringPublish =>
          SkillsErrorCode.draftChangedDuringPublish,
        DraftPlanningFailureCode.declaredNameChangeNotAllowed =>
          SkillsErrorCode.declaredNameChangeNotAllowed,
        DraftPlanningFailureCode.revisionStoreUnavailable =>
          SkillsErrorCode.revisionStoreCorrupt,
        DraftPlanningFailureCode.ioFailure => SkillsErrorCode.ioFailure,
        DraftPlanningFailureCode.draftNotFound ||
        DraftPlanningFailureCode.invalidSkill ||
        DraftPlanningFailureCode.revisionStateUnavailable ||
        DraftPlanningFailureCode.recoveryEvidenceFailed ||
        DraftPlanningFailureCode.invalidPreparedEvidence =>
          SkillsErrorCode.invalidSkill,
      },
      context: <String, Object?>{
        ...failure.context,
        if (failure.code == DraftPlanningFailureCode.draftNotFound)
          'reason': 'draftNotFound',
      },
    );

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

final class _DraftPreparationRejected implements Exception {
  const _DraftPreparationRejected();
}
