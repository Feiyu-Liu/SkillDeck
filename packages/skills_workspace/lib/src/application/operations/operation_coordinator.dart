import 'dart:async';

import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/lock_wait_policy.dart';
import '../ports/operation_ports.dart';
import 'operation_models.dart';

typedef OperationPlanBuilder =
    FutureOr<OperationPlan> Function(
      OperationId operationId,
      RepositoryRevision currentRevision,
    );

typedef PreparedOperationEnvelopeBuilder =
    PreparedOperationEnvelope Function(
      OperationId operationId,
      RepositoryRevision currentRevision,
    );

typedef DeferredCandidateBuilder<T> =
    Future<T> Function(
      PreparedOperationEnvelope envelope,
      CancellationToken cancellationToken,
    );

typedef DeferredOperationPlanBuilder<T> =
    OperationPlan Function(
      PreparedOperationEnvelope envelope,
      T preparedCandidate,
    );

final class OperationCoordinator {
  const OperationCoordinator({
    required WorkspaceWriterLockPort writerLock,
    required OperationControlPlanePort controlPlane,
    required OperationRecoveryPort recovery,
    required OperationRevisionReferenceMaintenancePort referenceMaintenance,
    OperationAbortClassifier classifyAbort = classifyOperationAbort,
  }) : _writerLock = writerLock,
       _controlPlane = controlPlane,
       _recovery = recovery,
       _referenceMaintenance = referenceMaintenance,
       _classifyAbort = classifyAbort;

  final WorkspaceWriterLockPort _writerLock;
  final OperationControlPlanePort _controlPlane;
  final OperationRecoveryPort _recovery;
  final OperationRevisionReferenceMaintenancePort _referenceMaintenance;
  final OperationAbortClassifier _classifyAbort;

  Future<OperationExecutionOutcome> execute({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required OperationPlanBuilder buildPlan,
    LockWaitPolicy? lockWaitPolicy,
    CancellationToken? cancellationToken,
    void Function()? onBusinessCommitted,
  }) async {
    final cancellation = cancellationToken ?? CancellationToken.none();
    WorkspaceWriterLease lease;
    try {
      lease = await _writerLock.acquire(waitPolicy: lockWaitPolicy);
    } on Object {
      return const OperationRejected(
        reason: OperationAbortReason.lockUnavailable,
      );
    }

    try {
      if (cancellation.isCancelled) {
        return const OperationRejected(reason: OperationAbortReason.cancelled);
      }

      final RepositoryRevision currentRevision;
      try {
        currentRevision = await _controlPlane.readRepositoryRevision();
      } on Object {
        return const OperationRejected(
          reason: OperationAbortReason.snapshotReadFailed,
        );
      }
      if (currentRevision != expectedRepositoryRevision) {
        return OperationRejected(
          reason: OperationAbortReason.staleRepositoryRevision,
          actualRepositoryRevision: currentRevision,
        );
      }
      if (cancellation.isCancelled) {
        return const OperationRejected(reason: OperationAbortReason.cancelled);
      }

      final OperationPlan plan;
      try {
        plan = await buildPlan(operationId, currentRevision);
      } on Object catch (error) {
        return OperationRejected(
          reason: OperationAbortReason.preparationFailed,
          detail: _classifyAbort(error),
        );
      }
      if (cancellation.isCancelled) {
        return const OperationRejected(reason: OperationAbortReason.cancelled);
      }
      if (plan.operationId != operationId ||
          plan.expectedRepositoryRevision != currentRevision) {
        throw StateError('The plan builder returned an inconsistent plan.');
      }

      try {
        await _controlPlane.persistPrepared(plan);
      } on Object {
        return const OperationRejected(
          reason: OperationAbortReason.journalWriteFailed,
        );
      }
      try {
        await _referenceMaintenance.reconcileRevisionReferences(
          selectedSkillIds: _referenceSkillIds(plan),
        );
      } on Object catch (error) {
        return await _rollback(
          plan,
          OperationAbortReason.preparationFailed,
          OperationJournalPhase.prepared,
          detail: _classifyAbort(error),
        );
      }

      return await _executePreparedPlan(
        plan,
        cancellation: cancellation,
        preparationStartIndex: 0,
        onBusinessCommitted: onBusinessCommitted,
      );
    } finally {
      await lease.release();
    }
  }

  /// Executes an operation whose revision/object facts are discovered only by
  /// candidate construction.
  ///
  /// The minimal envelope is durable before [prepareCandidate] is called. The
  /// resulting complete plan is atomically sealed while still Prepared, then
  /// execution rejoins the normal transaction path.
  Future<OperationExecutionOutcome> executeDeferred<T>({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required PreparedOperationEnvelopeBuilder buildEnvelope,
    required DeferredCandidateBuilder<T> prepareCandidate,
    required DeferredOperationPlanBuilder<T> buildPlan,
    LockWaitPolicy? lockWaitPolicy,
    CancellationToken? cancellationToken,
    void Function()? onBusinessCommitted,
  }) async {
    final preparedRecovery = _recovery is PreparedOperationRecoveryPort
        ? _recovery as PreparedOperationRecoveryPort
        : null;
    if (preparedRecovery == null) {
      return const OperationRejected(
        reason: OperationAbortReason.preparationFailed,
      );
    }
    final cancellation = cancellationToken ?? CancellationToken.none();
    WorkspaceWriterLease lease;
    try {
      lease = await _writerLock.acquire(waitPolicy: lockWaitPolicy);
    } on Object {
      return const OperationRejected(
        reason: OperationAbortReason.lockUnavailable,
      );
    }

    try {
      if (cancellation.isCancelled) {
        return const OperationRejected(reason: OperationAbortReason.cancelled);
      }
      final RepositoryRevision currentRevision;
      try {
        currentRevision = await _controlPlane.readRepositoryRevision();
      } on Object {
        return const OperationRejected(
          reason: OperationAbortReason.snapshotReadFailed,
        );
      }
      if (currentRevision != expectedRepositoryRevision) {
        return OperationRejected(
          reason: OperationAbortReason.staleRepositoryRevision,
          actualRepositoryRevision: currentRevision,
        );
      }
      if (cancellation.isCancelled) {
        return const OperationRejected(reason: OperationAbortReason.cancelled);
      }

      final envelope = buildEnvelope(operationId, currentRevision);
      if (envelope.operationId != operationId ||
          envelope.expectedRepositoryRevision != currentRevision) {
        throw StateError(
          'The envelope builder returned an inconsistent envelope.',
        );
      }
      try {
        await _controlPlane.persistPreparedEnvelope(envelope);
      } on Object {
        return const OperationRejected(
          reason: OperationAbortReason.journalWriteFailed,
        );
      }

      final OperationPlan plan;
      try {
        _throwIfCancelled(cancellation);
        for (final step in envelope.preparationSteps) {
          await _controlPlane.markStepStarted(operationId, step.stepId);
        }
        _throwIfCancelled(cancellation);
        final prepared = await prepareCandidate(envelope, cancellation);
        _throwIfCancelled(cancellation);
        for (final step in envelope.preparationSteps) {
          await _controlPlane.markStepCompleted(operationId, step.stepId);
        }
        plan = buildPlan(envelope, prepared);
        if (!envelope.isSealedBy(plan)) {
          throw StateError(
            'The deferred plan does not preserve its Prepared envelope.',
          );
        }
        await _controlPlane.sealPreparedPlan(envelope, plan);
        await _referenceMaintenance.reconcileRevisionReferences(
          selectedSkillIds: _referenceSkillIds(plan),
        );
      } on _CancellationBeforeCommit {
        return await _rollbackPreparedEnvelope(
          envelope,
          OperationAbortReason.cancelled,
          preparedRecovery,
        );
      } on Object catch (error) {
        return await _rollbackPreparedEnvelope(
          envelope,
          OperationAbortReason.preparationFailed,
          preparedRecovery,
          detail: _classifyAbort(error),
        );
      }
      return await _executePreparedPlan(
        plan,
        cancellation: cancellation,
        preparationStartIndex: envelope.preparationSteps.length,
        onBusinessCommitted: onBusinessCommitted,
      );
    } finally {
      await lease.release();
    }
  }

  Future<OperationExecutionOutcome> _executePreparedPlan(
    OperationPlan plan, {
    required CancellationToken cancellation,
    required int preparationStartIndex,
    void Function()? onBusinessCommitted,
  }) async {
    var abortReason = OperationAbortReason.preparationFailed;
    var preCommitPhase = OperationJournalPhase.prepared;
    try {
      for (final step in plan.preparationSteps.skip(preparationStartIndex)) {
        _throwIfCancelled(cancellation);
        await _controlPlane.markStepStarted(plan.operationId, step.stepId);
        _throwIfCancelled(cancellation);
        await _recovery.prepareStep(step, cancellation);
        await _controlPlane.markStepCompleted(plan.operationId, step.stepId);
      }
      _throwIfCancelled(cancellation);
      await _controlPlane.markApplying(plan.operationId);
      preCommitPhase = OperationJournalPhase.applying;

      abortReason = OperationAbortReason.applyFailed;
      for (final step in plan.applyingSteps) {
        _throwIfCancelled(cancellation);
        await _controlPlane.markStepStarted(plan.operationId, step.stepId);
        _throwIfCancelled(cancellation);
        await _recovery.applyStep(step, cancellation);
        await _controlPlane.markStepCompleted(plan.operationId, step.stepId);
      }
      _throwIfCancelled(cancellation);

      abortReason = OperationAbortReason.businessCommitFailed;
      await _controlPlane.commitBusinessState(plan);
    } on _CancellationBeforeCommit {
      return _rollback(plan, OperationAbortReason.cancelled, preCommitPhase);
    } on ExternalOperationPreconditionChanged {
      return _rollback(
        plan,
        OperationAbortReason.externalPreconditionChanged,
        preCommitPhase,
      );
    } on Object catch (error) {
      return _rollback(
        plan,
        abortReason,
        preCommitPhase,
        detail: _classifyAbort(error),
      );
    }

    // Cancellation is deliberately ignored after the Business Commit Point.
    try {
      onBusinessCommitted?.call();
    } on Object {
      // An in-memory observer can never change durable recovery direction.
    }
    try {
      await _controlPlane.markFinalizing(plan.operationId);
      for (final step in plan.finalizationSteps) {
        await _controlPlane.markStepStarted(plan.operationId, step.stepId);
        final effect = await _recovery.finalizeStep(step);
        if (effect != null) {
          await _controlPlane.applyFinalizationEffect(plan.operationId, effect);
        }
        await _controlPlane.markStepCompleted(plan.operationId, step.stepId);
      }
      // Retention refs are derived from committed SQLite pointers. Reconcile
      // them only after all recovery-backed finalization entries have been
      // installed and verified; changing refs earlier would invalidate the
      // sealed Store snapshot that those entries still need to verify.
      await _referenceMaintenance.reconcileRevisionReferences(
        selectedSkillIds: _referenceSkillIds(plan),
      );
      await _controlPlane.complete(plan);
    } on Object {
      return OperationCommittedFinalizationPending(
        operationId: plan.operationId,
        committedRepositoryRevision: plan.committedRepositoryRevision,
      );
    }

    var cleanupPending = false;
    try {
      await _recovery.cleanupCompleted(plan);
      await _controlPlane.deleteCompletedJournal(plan.operationId);
      await _referenceMaintenance.reconcileRevisionReferences(
        selectedSkillIds: _referenceSkillIds(plan),
      );
    } on Object {
      if (plan.businessChanges.incrementsDestructionEpoch) {
        return OperationCommittedFinalizationPending(
          operationId: plan.operationId,
          committedRepositoryRevision: plan.committedRepositoryRevision,
        );
      }
      cleanupPending = true;
    }
    return OperationCompleted(
      operationId: plan.operationId,
      committedRepositoryRevision: plan.committedRepositoryRevision,
      cleanupPending: cleanupPending,
    );
  }

  Future<OperationExecutionOutcome> _rollback(
    OperationPlan plan,
    OperationAbortReason reason,
    OperationJournalPhase observedPhase, {
    OperationAbortDetail? detail,
  }) async {
    try {
      await _recovery.rollback(plan, observedPhase: observedPhase);
      await _controlPlane.completeRollback(plan, reason);
      await _referenceMaintenance.reconcileRevisionReferences(
        selectedSkillIds: _referenceSkillIds(plan),
      );
      return OperationRolledBack(
        operationId: plan.operationId,
        reason: reason,
        detail: detail,
      );
    } on Object {
      return OperationRollbackPending(
        operationId: plan.operationId,
        originalReason: reason,
      );
    }
  }

  Future<OperationExecutionOutcome> _rollbackPreparedEnvelope(
    PreparedOperationEnvelope envelope,
    OperationAbortReason reason,
    PreparedOperationRecoveryPort preparedRecovery, {
    OperationAbortDetail? detail,
  }) async {
    try {
      await preparedRecovery.rollbackPreparedEnvelope(
        envelope,
        observedPhase: OperationJournalPhase.prepared,
      );
      await _controlPlane.completePreparedEnvelopeRollback(envelope, reason);
      await _referenceMaintenance.reconcileRevisionReferences(
        selectedSkillIds: _referenceSkillIds(envelope),
      );
      return OperationRolledBack(
        operationId: envelope.operationId,
        reason: reason,
        detail: detail,
      );
    } on Object {
      return OperationRollbackPending(
        operationId: envelope.operationId,
        originalReason: reason,
      );
    }
  }

  Future<OperationRecoveryReport> recover() async {
    final lease = await _writerLock.acquire();
    try {
      return await _recoverUnderWriterLock();
    } finally {
      await lease.release();
    }
  }

  /// Recovers Journals while an outer startup coordinator owns the lock.
  ///
  /// Normal callers use [recover]. This entry point prevents startup from
  /// recursively acquiring the same cross-process Writer Lock.
  Future<OperationRecoveryReport> recoverUnderWriterLock({
    required Set<ManagedSkillId> isolatedSkillIds,
  }) => _recoverUnderWriterLock(isolatedSkillIds: isolatedSkillIds);

  Future<OperationRecoveryReport> _recoverUnderWriterLock({
    Set<ManagedSkillId>? isolatedSkillIds,
  }) async {
    final journaled = await _controlPlane.loadRecoverableOperations();
    final recovered = <RecoveredOperation>[];
    for (final operation in journaled) {
      try {
        final definition = operation.definition;
        if (definition case final PreparedOperationEnvelope envelope) {
          final preparedRecovery = _recovery is PreparedOperationRecoveryPort
              ? _recovery as PreparedOperationRecoveryPort
              : null;
          if (preparedRecovery == null) {
            throw StateError('Prepared-envelope recovery is unavailable.');
          }
          switch (operation.phase) {
            case OperationJournalPhase.prepared:
              await preparedRecovery.rollbackPreparedEnvelope(
                envelope,
                observedPhase: operation.phase,
              );
              await _controlPlane.completePreparedEnvelopeRollback(
                envelope,
                OperationAbortReason.preparationFailed,
              );
              await _cleanupRecoveredPreparedEnvelope(
                envelope,
                preparedRecovery,
              );
              recovered.add(
                RecoveredOperation(
                  operationId: envelope.operationId,
                  observedPhase: operation.phase,
                  disposition: RecoveredOperationDisposition.rolledBack,
                ),
              );
            case OperationJournalPhase.completed:
              await _cleanupRecoveredPreparedEnvelope(
                envelope,
                preparedRecovery,
              );
              recovered.add(
                RecoveredOperation(
                  operationId: envelope.operationId,
                  observedPhase: operation.phase,
                  disposition: RecoveredOperationDisposition.cleanedCompleted,
                ),
              );
            case OperationJournalPhase.applying:
            case OperationJournalPhase.committed:
            case OperationJournalPhase.finalizing:
              throw StateError(
                'An unsealed Prepared envelope cannot enter this phase.',
              );
          }
          continue;
        }
        final plan = definition as OperationPlan;
        switch (operation.phase) {
          case OperationJournalPhase.prepared:
          case OperationJournalPhase.applying:
            await _recovery.rollback(plan, observedPhase: operation.phase);
            await _controlPlane.completeRollback(
              plan,
              OperationAbortReason.preparationFailed,
            );
            await _cleanupRecoveredCompleted(plan);
            recovered.add(
              RecoveredOperation(
                operationId: plan.operationId,
                observedPhase: operation.phase,
                disposition: RecoveredOperationDisposition.rolledBack,
              ),
            );
            break;
          case OperationJournalPhase.committed:
          case OperationJournalPhase.finalizing:
            await _controlPlane.markFinalizing(plan.operationId);
            final effects = await _recovery.rollForward(plan);
            for (final effect in effects) {
              await _controlPlane.applyFinalizationEffect(
                plan.operationId,
                effect,
              );
            }
            await _referenceMaintenance.reconcileRevisionReferences(
              isolatedSkillIds: isolatedSkillIds,
              selectedSkillIds: _referenceSkillIds(plan),
            );
            await _controlPlane.complete(plan);
            await _cleanupRecoveredCompleted(plan);
            recovered.add(
              RecoveredOperation(
                operationId: plan.operationId,
                observedPhase: operation.phase,
                disposition: RecoveredOperationDisposition.rolledForward,
              ),
            );
            break;
          case OperationJournalPhase.completed:
            await _cleanupRecoveredCompleted(plan);
            recovered.add(
              RecoveredOperation(
                operationId: plan.operationId,
                observedPhase: operation.phase,
                disposition: RecoveredOperationDisposition.cleanedCompleted,
              ),
            );
            break;
        }
      } on Object {
        recovered.add(
          RecoveredOperation(
            operationId: operation.definition.operationId,
            observedPhase: operation.phase,
            disposition: RecoveredOperationDisposition.retryRequired,
          ),
        );
      }
    }
    return OperationRecoveryReport(recovered);
  }

  Future<void> _cleanupRecoveredCompleted(OperationPlan plan) async {
    await _recovery.cleanupCompleted(plan);
    await _controlPlane.deleteCompletedJournal(plan.operationId);
  }

  Future<void> _cleanupRecoveredPreparedEnvelope(
    PreparedOperationEnvelope envelope,
    PreparedOperationRecoveryPort preparedRecovery,
  ) async {
    await preparedRecovery.cleanupCompletedPreparedEnvelope(envelope);
    await _controlPlane.deleteCompletedJournal(envelope.operationId);
  }
}

void _throwIfCancelled(CancellationToken token) {
  if (token.isCancelled) throw const _CancellationBeforeCommit();
}

Set<ManagedSkillId> _referenceSkillIds(OperationJournalDefinition definition) =>
    Set<ManagedSkillId>.unmodifiable(<ManagedSkillId>{
      for (final subject in definition.record.subjects) subject.managedSkillId,
      if (definition case final OperationPlan plan)
        for (final change in plan.revisionSelectionChanges)
          change.managedSkillId,
    });

final class _CancellationBeforeCommit implements Exception {
  const _CancellationBeforeCommit();
}
