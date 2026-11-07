import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/history/history_models.dart';
import '../application/history/history_ports.dart';
import '../application/history/history_service.dart';
import '../application/history/restore_plan_assembler.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';

List<SkillsCommandHandler> buildHistoryCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required WorkspaceHistoryService history,
  required RestorePlanAssembler assembler,
  required OperationCoordinator operations,
  required RestoreRevisionPreparationPort revisions,
  required RestoreOperationPlanPort plans,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<InspectDiffRequest, SkillDiff>(
    kind: WorkspaceOperationKind.inspectDiff,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final result = await history.inspectDiff(
        snapshot: snapshots.current,
        managedSkillId: request.managedSkillId,
        from: request.from,
        to: request.to,
        cancellationToken: context.cancellationToken,
      );
      final failure = result.failureOrNull;
      if (failure != null) return _historyFailure<SkillDiff>(failure);
      return SkillsSuccess<SkillDiff>(
        value: result.valueOrNull!,
        changed: false,
      );
    },
  ),
  TypedSkillsCommandHandler<RestorePublishRequest, MutationReport>(
    kind: WorkspaceOperationKind.restorePublish,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final planned = await history.planRestore(
        snapshot: snapshots.current,
        managedSkillId: request.managedSkillId,
        selectedRevision: request.selectedRevision,
        cancellationToken: context.cancellationToken,
      );
      final failure = planned.failureOrNull;
      if (failure != null) return _historyFailure<MutationReport>(failure);
      final preflight = planned.valueOrNull!;
      HistoryFailure<PreparedRestorePublish>? preparationFailure;
      final outcome = await operations.executeDeferred<PreparedRestorePublish>(
        operationId: context.operationId,
        expectedRepositoryRevision: preflight.snapshotRevision,
        lockWaitPolicy: context.lockWaitPolicy,
        buildEnvelope: (operationId, currentRevision) =>
            plans.createRestoreEnvelope(
              operationId: operationId,
              expectedRepositoryRevision: currentRevision,
              preflight: preflight,
            ),
        prepareCandidate: (envelope, cancellationToken) async {
          final prepared = await revisions.prepareRestorePublish(
            envelope: envelope,
            preflight: preflight,
            cancellationToken: cancellationToken,
          );
          if (prepared.failureOrNull case final candidateFailure?) {
            preparationFailure = candidateFailure;
            throw const _RestorePreparationRejected();
          }
          final assembled = assembler.assemble(
            preflight: preflight,
            prepared: prepared.valueOrNull!,
          );
          if (assembled.failureOrNull case final assemblyFailure?) {
            preparationFailure = HistoryFailure<PreparedRestorePublish>(
              code: assemblyFailure.code,
              context: assemblyFailure.context,
            );
            throw const _RestorePreparationRejected();
          }
          return prepared.valueOrNull!;
        },
        buildPlan: (envelope, prepared) {
          final assembled = assembler.assemble(
            preflight: preflight,
            prepared: prepared,
          );
          return plans.sealRestorePlan(
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
          return _historyFailure<MutationReport>(failure);
        }
      }
      return _mapRestoreOutcome(
        outcome: outcome,
        managedSkillId: request.managedSkillId,
        context: context,
        snapshots: snapshots,
      );
    },
  ),
];

Future<SkillsResult<MutationReport>> _mapRestoreOutcome({
  required OperationExecutionOutcome outcome,
  required ManagedSkillId managedSkillId,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
}) async => switch (outcome) {
  OperationCompleted(
    :final operationId,
    :final committedRepositoryRevision,
    :final cleanupPending,
  ) =>
    _reloadRestore(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      managedSkillId: managedSkillId,
      cleanupPending: cleanupPending,
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
    ),
  OperationRolledBack(:final reason, :final detail) =>
    SkillsFailure<MutationReport>(
      code: _abortCode(reason),
      context: <String, Object?>{
        'reason': reason.name,
        if (detail != null) 'detail': detail.name,
      },
    ),
  OperationRollbackPending(:final originalReason) =>
    SkillsFailure<MutationReport>(
      code: SkillsErrorCode.recoveryFailed,
      context: <String, Object?>{'reason': originalReason.name},
    ),
};

Future<SkillsResult<MutationReport>> _reloadRestore({
  required OperationId operationId,
  required RepositoryRevision committedRepositoryRevision,
  required ManagedSkillId managedSkillId,
  required bool cleanupPending,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
}) async {
  context.reportProgress(OperationProgressPhase.finalizing);
  try {
    final snapshot = await snapshots.reload();
    return SkillsSuccess<MutationReport>(
      value: MutationReport(
        snapshot: snapshot,
        affectedSkillIds: <ManagedSkillId>{managedSkillId},
      ),
      changed: true,
      warnings: cleanupPending
          ? <SkillsWarning>[
              SkillsWarning(code: SkillsWarningCode.recoveryCleanupDeferred),
            ]
          : const <SkillsWarning>[],
    );
  } on Object {
    return SkillsCommittedFinalizationPending<MutationReport>(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      warnings: <SkillsWarning>[
        SkillsWarning(code: SkillsWarningCode.finalizationDeferred),
      ],
    );
  }
}

SkillsFailure<T> _historyFailure<T>(
  HistoryFailure<Object?> failure,
) => SkillsFailure<T>(
  code: switch (failure.code) {
    HistoryFailureCode.operationCancelled => SkillsErrorCode.operationCancelled,
    HistoryFailureCode.skillNotFound => SkillsErrorCode.skillNotFound,
    HistoryFailureCode.updateCandidateResolutionRequired =>
      SkillsErrorCode.updateCandidateResolutionRequired,
    HistoryFailureCode.dirtyDraftResolutionRequired =>
      SkillsErrorCode.dirtyDraftResolutionRequired,
    HistoryFailureCode.historicalNameMismatch =>
      SkillsErrorCode.historicalNameMismatch,
    HistoryFailureCode.revisionStoreUnavailable =>
      SkillsErrorCode.revisionStoreCorrupt,
    HistoryFailureCode.ioFailure => SkillsErrorCode.ioFailure,
    HistoryFailureCode.historicalRevisionNotFound ||
    HistoryFailureCode.historicalRevisionOutsideCurrentLineage ||
    HistoryFailureCode.draftInspectionFailed ||
    HistoryFailureCode.invalidSkill ||
    HistoryFailureCode.revisionStateUnavailable ||
    HistoryFailureCode.recoveryEvidenceFailed ||
    HistoryFailureCode.invalidPreparedEvidence => SkillsErrorCode.invalidSkill,
  },
  context: failure.context,
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

final class _RestorePreparationRejected implements Exception {
  const _RestorePreparationRejected();
}
