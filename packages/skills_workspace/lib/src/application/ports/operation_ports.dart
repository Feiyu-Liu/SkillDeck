import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/lock_wait_policy.dart';
import '../operations/destructive_recovery_intent.dart';
import '../operations/operation_models.dart';

abstract interface class WorkspaceWriterLease {
  Future<void> release();
}

abstract interface class WorkspaceWriterLockPort {
  Future<WorkspaceWriterLease> acquire({LockWaitPolicy? waitPolicy});
}

/// Repairs derived Revision retention refs from authoritative SQLite and
/// Journal state while the caller owns the Workspace Writer Lock.
abstract interface class OperationRevisionReferenceMaintenancePort {
  /// Uses [isolatedSkillIds] during startup, before the first public Snapshot
  /// exists. A normal open-runtime call omits it and derives the same boundary
  /// from the current Snapshot integrity.
  Future<void> reconcileRevisionReferences({
    Set<ManagedSkillId>? isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  });
}

/// Allocates the stable per-Skill subject identity stored in operation history.
///
/// Operation IDs are allocated synchronously by the public facade so the
/// progress stream, cancellation handle, Journal, and history always share one
/// identity from the moment an operation is returned to the caller.
abstract interface class OperationSubjectIdentityPort {
  String allocateOperationSubjectId();
}

/// Filesystem layout facts required by operation recovery adapters.
///
/// Keeping this seam application-owned lets the platform recovery adapter
/// address its private staging and recovery roots without depending on the
/// infrastructure layout implementation.
abstract interface class OperationRecoveryLayoutPort {
  String get stagingRoot;

  String get recoveryRoot;

  String operationStagingPath(OperationId operationId);

  String operationRecoveryPath(OperationId operationId);
}

/// Opaque recovery-owned steps contributed to one application operation plan.
final class OperationRecoveryPlanSteps {
  OperationRecoveryPlanSteps({
    required List<PreparationOperationStep> preparationSteps,
    required List<ApplyingOperationStep> applyingSteps,
    required List<FinalizationOperationStep> finalizationSteps,
  }) : preparationSteps = List.unmodifiable(preparationSteps),
       applyingSteps = List.unmodifiable(applyingSteps),
       finalizationSteps = List.unmodifiable(finalizationSteps);

  final List<PreparationOperationStep> preparationSteps;
  final List<ApplyingOperationStep> applyingSteps;
  final List<FinalizationOperationStep> finalizationSteps;
}

/// Creates recovery-owned plan fragments without exposing bundle paths or
/// reference encodings to application planners.
abstract interface class OperationRecoveryPlanFactoryPort {
  /// Creates the recovery-step prefix that can be journaled before a
  /// destructive candidate exists.
  ///
  /// The returned steps allocate opaque operation-owned recovery references
  /// only. Implementations must not register a complete recovery bundle or
  /// create filesystem evidence until the candidate-dependent plan is sealed.
  List<PreparationOperationStep> createDestructiveEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
  });

  OperationRecoveryPlanSteps createSqliteOnly({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required bool destructive,
  });

  OperationRecoveryPlanSteps createDestructive({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required DestructiveOperationRecoveryIntent intent,
  });
}

/// Owns the durable Journal and every SQLite business-state transaction.
abstract interface class OperationControlPlanePort {
  Future<RepositoryRevision> readRepositoryRevision();

  /// Persists the recovery-safe facts known before candidate construction.
  Future<void> persistPreparedEnvelope(PreparedOperationEnvelope envelope);

  /// Atomically replaces a still-Prepared envelope with its immutable plan.
  ///
  /// Implementations preserve existing preparation-step statuses and add only
  /// the newly discovered sealed-plan steps.
  Future<void> sealPreparedPlan(
    PreparedOperationEnvelope envelope,
    OperationPlan plan,
  );

  /// Compatibility path for operations whose complete plan is known before
  /// their first operation-scoped external mutation.
  Future<void> persistPrepared(OperationPlan plan);

  Future<void> markApplying(OperationId operationId);

  /// Durably records step progress around each idempotent external action.
  Future<void> markStepStarted(OperationId operationId, String stepId);

  Future<void> markStepCompleted(OperationId operationId, String stepId);

  /// The single Business Commit Point.
  ///
  /// Implementations atomically commit all business rows, revision pointers,
  /// Repository Revision, optional Destruction Epoch, and the Journal's
  /// committed marker in one SQLite transaction.
  Future<void> commitBusinessState(OperationPlan plan);

  /// Idempotently applies a post-commit effect selected by durable recovery
  /// evidence. Implementations must compare any supplied business identity so
  /// a stale cleanup can never delete a newer row.
  Future<void> applyFinalizationEffect(
    OperationId operationId,
    OperationFinalizationEffect effect,
  );

  Future<void> markFinalizing(OperationId operationId);

  /// Atomically upserts the Record and Subjects and marks the Journal completed.
  Future<void> complete(OperationPlan plan);

  /// Records successful rollback and makes its Journal eligible for cleanup.
  Future<void> completeRollback(
    OperationPlan plan,
    OperationAbortReason reason,
  );

  /// Records successful rollback when candidate construction failed before
  /// the Prepared envelope could be sealed.
  Future<void> completePreparedEnvelopeRollback(
    PreparedOperationEnvelope envelope,
    OperationAbortReason reason,
  );

  Future<List<JournaledOperation>> loadRecoverableOperations();

  Future<void> deleteCompletedJournal(OperationId operationId);
}

/// Owns all filesystem and Revision Engine preparation and recovery details.
abstract interface class OperationRecoveryPort {
  Future<void> prepareStep(
    PreparationOperationStep step,
    CancellationToken cancellationToken,
  );

  Future<void> applyStep(
    ApplyingOperationStep step,
    CancellationToken cancellationToken,
  );

  Future<OperationFinalizationEffect?> finalizeStep(
    FinalizationOperationStep step,
  );

  /// Idempotently restores pre-commit state using only Journal recovery refs.
  Future<void> rollback(
    OperationPlan plan, {
    required OperationJournalPhase observedPhase,
  });

  /// Idempotently establishes committed state using only Journal recovery refs.
  Future<List<OperationFinalizationEffect>> rollForward(OperationPlan plan);

  /// Idempotently removes residue for an already Completed operation.
  Future<void> cleanupCompleted(OperationPlan plan);
}

/// Optional recovery capability for Journals that stopped before plan sealing.
///
/// This is a separate additive interface so existing one-stage recovery
/// adapters remain valid until a deferred operation is wired into a facade.
abstract interface class PreparedOperationRecoveryPort {
  /// Idempotently removes candidate evidence through envelope recovery refs.
  Future<void> rollbackPreparedEnvelope(
    PreparedOperationEnvelope envelope, {
    required OperationJournalPhase observedPhase,
  });

  /// Idempotently removes residue after an envelope rollback was completed.
  Future<void> cleanupCompletedPreparedEnvelope(
    PreparedOperationEnvelope envelope,
  );
}
