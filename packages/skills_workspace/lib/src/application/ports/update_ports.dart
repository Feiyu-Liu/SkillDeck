import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../runtime/revision_engine_port.dart';
import '../update/update_models.dart';

/// Performs the authoritative full Draft comparison required before Update.
abstract interface class UpdateDraftInspectionPort {
  Future<UpdateDraftInspectionResult> inspectForUpdate({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  });
}

/// Reads current lineage, generation, and revision selections atomically.
abstract interface class UpdateRevisionStatePort {
  Future<UpdateRevisionState?> readUpdateState(ManagedSkillId managedSkillId);
}

/// Verifies every Repository and Activation destination of a source rename.
abstract interface class UpdateSlotMigrationInspectionPort {
  Future<UpdateSlotMigrationInspectionResult> inspect({
    required RepositorySnapshot snapshot,
    required ManagedSkill skill,
    required String newSlotKey,
    required CancellationToken cancellationToken,
  });
}

/// Reads the complete persisted Session state, including item resolution.
abstract interface class UpdateCandidateStatePort {
  Future<UpdateCandidateState?> readCandidateState(
    ManagedSkillId managedSkillId, {
    required CancellationToken cancellationToken,
  });
}

sealed class UpdateRevisionPreparationResult {
  const UpdateRevisionPreparationResult();
}

enum UpdateRevisionPreparationFailureCode {
  operationCancelled,
  staleIntent,
  dirtyDraftResolutionRequired,
  draftChangedDuringPublish,
  invalidSkill,
  unresolvedUpdateConflicts,
  declaredNameChangeNotAllowed,
  revisionStoreUnavailable,
  recoveryEvidenceFailed,
  ioFailure,
}

final class UpdateRevisionPreparationSuccess
    extends UpdateRevisionPreparationResult {
  const UpdateRevisionPreparationSuccess(this.prepared);

  final PreparedUpdateRevision prepared;
}

final class UpdateRevisionPreparationFailure
    extends UpdateRevisionPreparationResult {
  const UpdateRevisionPreparationFailure(this.code, {this.detail});

  final RevisionEngineFailureCode? detail;

  final UpdateRevisionPreparationFailureCode code;
}

sealed class UpdateCandidatePublishPreparationResult {
  const UpdateCandidatePublishPreparationResult();
}

final class UpdateCandidatePublishPreparationSuccess
    extends UpdateCandidatePublishPreparationResult {
  const UpdateCandidatePublishPreparationSuccess(this.prepared);

  final PreparedUpdateCandidatePublish prepared;
}

final class UpdateCandidatePublishPreparationFailure
    extends UpdateCandidatePublishPreparationResult {
  const UpdateCandidatePublishPreparationFailure(this.code, {this.detail});

  final RevisionEngineFailureCode? detail;

  final UpdateRevisionPreparationFailureCode code;
}

sealed class UpdateCandidateAbandonPreparationResult {
  const UpdateCandidateAbandonPreparationResult();
}

final class UpdateCandidateAbandonPreparationSuccess
    extends UpdateCandidateAbandonPreparationResult {
  const UpdateCandidateAbandonPreparationSuccess(this.prepared);

  final PreparedUpdateCandidateAbandon prepared;
}

final class UpdateCandidateAbandonPreparationFailure
    extends UpdateCandidateAbandonPreparationResult {
  const UpdateCandidateAbandonPreparationFailure(this.code, {this.detail});

  final RevisionEngineFailureCode? detail;

  final UpdateRevisionPreparationFailureCode code;
}

/// The only boundary allowed to create Update Git candidates or staged Drafts.
///
/// Both methods require an already allocated Operation ID. Their caller must
/// first persist a durable Journal containing the immutable input intent and
/// operation-scoped recovery contract. Implementations may then create only
/// the candidate evidence represented by the returned typed result.
///
/// `prepareUpdate` must authoritatively revalidate an expected clean Draft
/// before its first Store write and must freeze the post-commit Draft
/// disposition into its result. `prepareCandidatePublish` must capture one
/// stable Draft snapshot, require the intent's Declared Name, validate it, and
/// resolve every conflict before creating the Effective merge commit. Neither
/// method may reread mutable Draft bytes after that snapshot.
abstract interface class UpdateRevisionPreparationPort {
  Future<UpdateRevisionPreparationResult> prepareUpdate({
    required OperationId operationId,
    required UpdateRevisionPreparationIntent intent,
    required CancellationToken cancellationToken,
  });

  Future<UpdateCandidatePublishPreparationResult> prepareCandidatePublish({
    required OperationId operationId,
    required UpdateCandidatePublishPreparationIntent intent,
    required CancellationToken cancellationToken,
  });

  /// Rebuilds the current-lineage Bundle without Session-only roots.
  ///
  /// This intentionally does not compact the primary Store. Once the Session
  /// rows are committed away, derived retention refs are reconciled and the
  /// now-unreachable candidate objects are eligible for later maintenance GC.
  Future<UpdateCandidateAbandonPreparationResult> prepareCandidateAbandon({
    required OperationId operationId,
    required UpdateCandidateCleanupIntent intent,
    required CancellationToken cancellationToken,
  });
}
