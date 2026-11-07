import '../api/composite_command_dispatcher.dart';
import '../api/result.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';

/// Runs one already-planned mutation through the transaction coordinator and
/// turns its commit/recovery outcome into the stable public result contract.
///
/// The caller supplies the public value derived from the reloaded committed
/// Snapshot. This keeps Drift and transaction types out of individual command
/// handlers while preserving the Business Commit Point owned by the facade.
Future<SkillsResult<T>> executeMutation<T>({
  required SkillsCommandContext context,
  required RepositorySnapshot planningSnapshot,
  required OperationCoordinator operations,
  required OperationPlanBuilder buildPlan,
  required WorkspaceSnapshotPublisher snapshots,
  required T Function(RepositorySnapshot snapshot) valueFromSnapshot,
}) async {
  context.reportProgress(OperationProgressPhase.preparing);
  final outcome = await operations.execute(
    operationId: context.operationId,
    expectedRepositoryRevision: planningSnapshot.revision,
    buildPlan: buildPlan,
    lockWaitPolicy: context.lockWaitPolicy,
    cancellationToken: context.cancellationToken,
    onBusinessCommitted: () {
      context.reportProgress(OperationProgressPhase.committing);
      context.markBusinessCommitted();
    },
  );

  return mapMutationOutcome(
    outcome: outcome,
    context: context,
    snapshots: snapshots,
    valueFromSnapshot: valueFromSnapshot,
  );
}

/// Maps one already-executed transaction outcome onto the public mutation
/// contract. Deferred operations use this after their Prepared-envelope phase.
Future<SkillsResult<T>> mapMutationOutcome<T>({
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
    _completed(
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
    _committedPending<T>(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      context: context,
      snapshots: snapshots,
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

Future<SkillsResult<T>> _completed<T>({
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

Future<SkillsResult<T>> _committedPending<T>({
  required OperationId operationId,
  required RepositoryRevision committedRepositoryRevision,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
}) async {
  context.reportProgress(OperationProgressPhase.finalizing);
  try {
    await snapshots.reload();
  } on Object {
    // The transaction is already committed and recovery direction is durable.
    // Snapshot refresh can be retried by refresh/open and cannot downgrade the
    // terminal result to a pre-commit failure.
  }
  return SkillsCommittedFinalizationPending<T>(
    operationId: operationId,
    committedRepositoryRevision: committedRepositoryRevision,
    warnings: <SkillsWarning>[
      SkillsWarning(code: SkillsWarningCode.finalizationDeferred),
    ],
  );
}

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
