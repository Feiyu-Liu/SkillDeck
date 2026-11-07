import '../../domain/identifiers.dart';
import '../../domain/draft_snapshot.dart';
import '../../domain/public_models.dart';
import '../operations/operation_models.dart';
import '../operations/workspace_business_changes.dart';
import '../runtime/revision_engine_port.dart';
import '../drafts/draft_models.dart';

enum HistoryFailureCode {
  operationCancelled,
  skillNotFound,
  historicalRevisionNotFound,
  historicalRevisionOutsideCurrentLineage,
  updateCandidateResolutionRequired,
  dirtyDraftResolutionRequired,
  draftInspectionFailed,
  historicalNameMismatch,
  invalidSkill,
  revisionStateUnavailable,
  revisionStoreUnavailable,
  recoveryEvidenceFailed,
  ioFailure,
  invalidPreparedEvidence,
}

sealed class HistoryResult<T> {
  const HistoryResult();

  T? get valueOrNull;
  HistoryFailure<T>? get failureOrNull;
}

final class HistorySuccess<T> extends HistoryResult<T> {
  const HistorySuccess(this.value);

  final T value;

  @override
  T get valueOrNull => value;

  @override
  HistoryFailure<T>? get failureOrNull => null;
}

final class HistoryFailure<T> extends HistoryResult<T> {
  HistoryFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map<String, Object?>.unmodifiable(context);

  final HistoryFailureCode code;
  final Map<String, Object?> context;

  @override
  T? get valueOrNull => null;

  @override
  HistoryFailure<T> get failureOrNull => this;
}

final class HistoricalRevisionSelection {
  const HistoricalRevisionSelection({
    required this.reference,
    required this.managedSkillId,
    required this.sourceLineage,
    required this.objectId,
    required this.contentHash,
    required this.declaredName,
  });

  final OperationSubjectReference reference;
  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId objectId;
  final String contentHash;
  final String declaredName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoricalRevisionSelection &&
          reference == other.reference &&
          managedSkillId == other.managedSkillId &&
          sourceLineage == other.sourceLineage &&
          objectId == other.objectId &&
          contentHash == other.contentHash &&
          declaredName == other.declaredName;

  @override
  int get hashCode => Object.hash(
    reference,
    managedSkillId,
    sourceLineage,
    objectId,
    contentHash,
    declaredName,
  );
}

final class RestoreRevisionState {
  const RestoreRevisionState({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.currentUpstream,
    required this.currentEffective,
    required this.managedSkillCreatedAtMicros,
    required this.draftCreatedAtMicros,
  });

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId currentUpstream;
  final RevisionObjectId currentEffective;
  final int managedSkillCreatedAtMicros;
  final int? draftCreatedAtMicros;
}

final class RestorePublishPreflight {
  const RestorePublishPreflight({
    required this.snapshotRevision,
    required this.plannedAtMicros,
    required this.skill,
    required this.selected,
    required this.state,
    required this.hadCleanDraft,
  });

  final RepositoryRevision snapshotRevision;
  final int plannedAtMicros;
  final ManagedSkill skill;
  final HistoricalRevisionSelection selected;
  final RestoreRevisionState state;
  final bool hadCleanDraft;
}

enum RestoreDraftAction { noDraft, deleteUnchanged, preserveAndReanchor }

final class PreparedRestorePublish {
  PreparedRestorePublish({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.selectedObjectId,
    required this.treeObjectId,
    required this.effectiveObjectId,
    required this.effectiveRequest,
    required this.contentHash,
    required this.fileCount,
    required this.byteSize,
    required this.declaredName,
    required this.description,
    required this.draftAction,
    required this.capturedDraftFingerprint,
    required this.candidateRecoveryReference,
    required this.bundleRecoveryReference,
    required this.materializationRecoveryReference,
    required this.draftRecoveryReference,
  }) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(contentHash)) {
      throw ArgumentError.value(contentHash, 'contentHash');
    }
  }

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId selectedObjectId;
  final RevisionObjectId treeObjectId;
  final RevisionObjectId effectiveObjectId;
  final RevisionCommitRequest effectiveRequest;
  final String contentHash;
  final int fileCount;
  final int byteSize;
  final String declaredName;
  final String description;
  final RestoreDraftAction draftAction;
  final DraftFingerprint? capturedDraftFingerprint;
  final RecoveryReference candidateRecoveryReference;
  final RecoveryReference bundleRecoveryReference;
  final RecoveryReference materializationRecoveryReference;
  final RecoveryReference draftRecoveryReference;
}

final class RestoreRevisionRecoveryIntent {
  RestoreRevisionRecoveryIntent({
    required this.managedSkillId,
    required this.sourceLineage,
    required List<RevisionObjectId> retainedRoots,
    required this.candidateRecoveryReference,
    required this.bundleRecoveryReference,
    required this.draftCleanup,
  }) : retainedRoots = List<RevisionObjectId>.unmodifiable(retainedRoots);

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final List<RevisionObjectId> retainedRoots;
  final RecoveryReference candidateRecoveryReference;
  final RecoveryReference bundleRecoveryReference;
  final PublishedDraftCleanupIntent? draftCleanup;
}

sealed class RestoreMaterializationIntent {
  const RestoreMaterializationIntent({
    required this.managedSkillId,
    required this.revision,
    required this.recoveryReference,
  });

  final ManagedSkillId managedSkillId;
  final RevisionAddress revision;
  final RecoveryReference recoveryReference;
}

final class RestoreRepositoryMaterializationIntent
    extends RestoreMaterializationIntent {
  const RestoreRepositoryMaterializationIntent({
    required super.managedSkillId,
    required super.revision,
    required super.recoveryReference,
    required this.slotKey,
  });

  final String slotKey;
}

final class RestoreActivationMaterializationIntent
    extends RestoreMaterializationIntent {
  const RestoreActivationMaterializationIntent({
    required super.managedSkillId,
    required super.revision,
    required super.recoveryReference,
    required this.activation,
    required this.slotKey,
  });

  final SkillActivation activation;
  final String slotKey;
}

final class PreparedRestorePublishPlan {
  PreparedRestorePublishPlan({
    required this.businessChanges,
    required List<RevisionSelectionChangePlan> revisionSelectionChanges,
    required this.recoveryIntent,
    required List<RestoreMaterializationIntent> materializationIntents,
  }) : revisionSelectionChanges = List.unmodifiable(revisionSelectionChanges),
       materializationIntents = List.unmodifiable(materializationIntents);

  final WorkspaceBusinessChangeSet businessChanges;
  final List<RevisionSelectionChangePlan> revisionSelectionChanges;
  final RestoreRevisionRecoveryIntent recoveryIntent;
  final List<RestoreMaterializationIntent> materializationIntents;
}
