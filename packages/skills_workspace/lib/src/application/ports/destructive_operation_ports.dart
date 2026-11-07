import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../destructive/destructive_operation_models.dart';
import '../operations/destructive_recovery_intent.dart';
import '../operations/operation_models.dart';

/// Reads the complete lock-held projection required by destructive planners.
///
/// The public Repository Snapshot intentionally omits Source Lineage and Git
/// object identities, so composition obtains them through this internal port.
abstract interface class DestructivePlanningStatePort {
  Future<DestructivePlanningSnapshot> readPlanningSnapshot({
    required RepositorySnapshot publicSnapshot,
    required DestructivePlanningPurpose purpose,
    required Set<ManagedSkillId> targetManagedSkillIds,
    required CancellationToken cancellationToken,
  });
}

enum DestructivePlanningStateFailureCode {
  operationCancelled,
  draftInspectionFailed,
}

/// Typed failure emitted while reconstructing destructive planning authority.
///
/// Expected cancellation must not be collapsed into the transaction
/// coordinator's generic preparation failure.
final class DestructivePlanningStateException implements Exception {
  const DestructivePlanningStateException(this.code, {this.reason});

  final DestructivePlanningStateFailureCode code;
  final String? reason;
}

/// Prepares private filesystem recovery entries before a destructive plan is
/// assembled. Implementations may read SQLite and create operation-owned
/// staging bytes, but must not mutate live paths.
abstract interface class DestructiveRecoveryEntryPreparationPort {
  Future<void> prepareRecoveryEntries({
    required OperationId operationId,
    required DestructiveOperationRecoveryIntent intent,
    required CancellationToken cancellationToken,
  });
}

/// Performs source acquisition and operation-local Revision candidate work
/// only after the caller has validated the lock-held Destructive Intent.
///
/// Implementations may write only beneath the operation-owned staging subtree
/// identified by [PreparedOperationEnvelope.operationId]. Ownership transfers
/// to Prepared-envelope recovery before this method starts. Implementations
/// must never publish a live Store, Bundle, materialization, Journal row, or
/// SQLite business row themselves.
abstract interface class SourceReplacementPreparationPort {
  Future<SourceReplacementPreparationResult> prepareSourceReplacement(
    SourceReplacementPreparationIntent intent, {
    required PreparedOperationEnvelope envelope,
    required CancellationToken cancellationToken,
  });
}
