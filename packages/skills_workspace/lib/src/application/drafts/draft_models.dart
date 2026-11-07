import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../../domain/draft_snapshot.dart';
import '../operations/operation_models.dart';
import '../operations/workspace_business_changes.dart';
import '../runtime/revision_engine_port.dart';

enum DraftPlanningFailureCode {
  operationCancelled,
  skillNotFound,
  draftNotFound,
  updateCandidateResolutionRequired,
  draftChangedDuringPublish,
  declaredNameChangeNotAllowed,
  invalidSkill,
  revisionStateUnavailable,
  revisionStoreUnavailable,
  recoveryEvidenceFailed,
  ioFailure,
  invalidPreparedEvidence,
}

sealed class DraftPlanningResult<T> {
  const DraftPlanningResult();

  T? get valueOrNull;
  DraftPlanningFailure<T>? get failureOrNull;
}

final class DraftPlanningSuccess<T> extends DraftPlanningResult<T> {
  const DraftPlanningSuccess(this.value);

  final T value;

  @override
  T get valueOrNull => value;

  @override
  DraftPlanningFailure<T>? get failureOrNull => null;
}

final class DraftPlanningFailure<T> extends DraftPlanningResult<T> {
  DraftPlanningFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map<String, Object?>.unmodifiable(context);

  final DraftPlanningFailureCode code;
  final Map<String, Object?> context;

  @override
  T? get valueOrNull => null;

  @override
  DraftPlanningFailure<T> get failureOrNull => this;
}

/// SQLite-selected facts needed by the Draft lifecycle.
final class DraftRevisionState {
  DraftRevisionState({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.currentUpstream,
    required this.currentEffective,
    required this.managedSkillCreatedAtMicros,
    required this.draftCreatedAtMicros,
  }) {
    if (managedSkillCreatedAtMicros < 0) {
      throw ArgumentError.value(
        managedSkillCreatedAtMicros,
        'managedSkillCreatedAtMicros',
      );
    }
    if (draftCreatedAtMicros case final value?) {
      if (value < 0) {
        throw ArgumentError.value(value, 'draftCreatedAtMicros');
      }
    }
  }

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId currentUpstream;
  final RevisionObjectId currentEffective;
  final int managedSkillCreatedAtMicros;
  final int? draftCreatedAtMicros;
}

sealed class PlannedEnsureDraft {
  const PlannedEnsureDraft();
}

final class ExistingDraft extends PlannedEnsureDraft {
  const ExistingDraft(this.summary);

  final DraftSummary summary;
}

final class EnsureDraftPreparationRequired extends PlannedEnsureDraft {
  const EnsureDraftPreparationRequired({
    required this.snapshotRevision,
    required this.plannedAtMicros,
    required this.skill,
    required this.state,
  });

  final RepositoryRevision snapshotRevision;
  final int plannedAtMicros;
  final ManagedSkill skill;
  final DraftRevisionState state;
}

final class PreparedEnsureDraft {
  const PreparedEnsureDraft({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.baseObjectId,
    required this.draftRecoveryReference,
  });

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId baseObjectId;
  final RecoveryReference draftRecoveryReference;
}

final class PreparedEnsureDraftPlan {
  const PreparedEnsureDraftPlan({
    required this.businessChanges,
    required this.draftRecoveryReference,
  });

  final WorkspaceBusinessChangeSet businessChanges;
  final RecoveryReference draftRecoveryReference;
}

final class DiscardDraftPlan {
  const DiscardDraftPlan({
    required this.snapshotRevision,
    required this.skill,
    required this.state,
    required this.businessChanges,
  });

  final RepositoryRevision snapshotRevision;
  final ManagedSkill skill;
  final DraftRevisionState state;
  final WorkspaceBusinessChangeSet businessChanges;
}

final class PublishDraftPreparationRequired {
  const PublishDraftPreparationRequired({
    required this.snapshotRevision,
    required this.plannedAtMicros,
    required this.skill,
    required this.state,
  });

  final RepositoryRevision snapshotRevision;
  final int plannedAtMicros;
  final ManagedSkill skill;
  final DraftRevisionState state;
}

enum PublishedDraftAction { deleteUnchanged, preserveAndReanchor }

final class PreparedDraftPublish {
  PreparedDraftPublish({
    required this.managedSkillId,
    required this.sourceLineage,
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
    if (fileCount < 0 || byteSize < 0) {
      throw ArgumentError('Draft revision counts must not be negative.');
    }
    if (declaredName.trim().isEmpty || description.trim().isEmpty) {
      throw ArgumentError('Draft metadata must not be empty.');
    }
  }

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId treeObjectId;
  final RevisionObjectId effectiveObjectId;
  final RevisionCommitRequest effectiveRequest;
  final String contentHash;
  final int fileCount;
  final int byteSize;
  final String declaredName;
  final String description;
  final PublishedDraftAction draftAction;
  final DraftFingerprint capturedDraftFingerprint;
  final RecoveryReference candidateRecoveryReference;
  final RecoveryReference bundleRecoveryReference;
  final RecoveryReference materializationRecoveryReference;
  final RecoveryReference draftRecoveryReference;
}

final class DraftRevisionRecoveryIntent {
  DraftRevisionRecoveryIntent({
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
  final PublishedDraftCleanupIntent draftCleanup;
}

/// Immutable evidence for post-commit Draft compare-and-delete.
final class PublishedDraftCleanupIntent {
  const PublishedDraftCleanupIntent({
    required this.managedSkillId,
    required this.expectedBaseObjectId,
    required this.capturedFingerprint,
  });

  final ManagedSkillId managedSkillId;
  final RevisionObjectId expectedBaseObjectId;
  final DraftFingerprint capturedFingerprint;
}

sealed class DraftMaterializationIntent {
  const DraftMaterializationIntent({
    required this.managedSkillId,
    required this.revision,
    required this.recoveryReference,
  });

  final ManagedSkillId managedSkillId;
  final RevisionAddress revision;
  final RecoveryReference recoveryReference;
}

final class DraftRepositoryMaterializationIntent
    extends DraftMaterializationIntent {
  const DraftRepositoryMaterializationIntent({
    required super.managedSkillId,
    required super.revision,
    required super.recoveryReference,
    required this.slotKey,
  });

  final String slotKey;
}

final class DraftActivationMaterializationIntent
    extends DraftMaterializationIntent {
  const DraftActivationMaterializationIntent({
    required super.managedSkillId,
    required super.revision,
    required super.recoveryReference,
    required this.activation,
    required this.slotKey,
  });

  final SkillActivation activation;
  final String slotKey;
}

final class PreparedDraftPublishPlan {
  PreparedDraftPublishPlan({
    required this.businessChanges,
    required List<RevisionSelectionChangePlan> revisionSelectionChanges,
    required this.recoveryIntent,
    required List<DraftMaterializationIntent> materializationIntents,
  }) : revisionSelectionChanges = List.unmodifiable(revisionSelectionChanges),
       materializationIntents = List.unmodifiable(materializationIntents);

  final WorkspaceBusinessChangeSet businessChanges;
  final List<RevisionSelectionChangePlan> revisionSelectionChanges;
  final DraftRevisionRecoveryIntent recoveryIntent;
  final List<DraftMaterializationIntent> materializationIntents;
}
