import '../../domain/identifiers.dart';
import '../../domain/draft_snapshot.dart';
import '../../domain/public_models.dart';
import '../../domain/revision_content.dart';
import '../operations/operation_models.dart';
import '../operations/workspace_business_changes.dart';
import '../runtime/revision_engine_port.dart';
import '../drafts/draft_models.dart';
import '../source/source_acquisition_models.dart';

enum UpdatePlanningFailureCode {
  operationCancelled,
  skillNotFound,
  updateUnsupported,
  updateCandidateNotFound,
  updateConflictNotFound,
  updateCandidateResolutionRequired,
  dirtyDraftResolutionRequired,
  draftInspectionFailed,
  revisionStateUnavailable,
  sourceAcquisitionFailed,
  sourceContinuityLost,
  unsupportedSkillName,
  slotMigrationConflict,
  unresolvedUpdateConflicts,
  declaredNameChangeNotAllowed,
  staleIntent,
  draftChangedDuringPublish,
  invalidSkill,
  revisionStoreUnavailable,
  recoveryEvidenceFailed,
  ioFailure,
  invalidPreparedEvidence,
}

sealed class UpdatePlanningResult<T> {
  const UpdatePlanningResult();

  T? get valueOrNull;
  UpdatePlanningFailure<T>? get failureOrNull;
}

final class UpdatePlanningSuccess<T> extends UpdatePlanningResult<T> {
  const UpdatePlanningSuccess(this.value);

  final T value;

  @override
  T get valueOrNull => value;

  @override
  UpdatePlanningFailure<T>? get failureOrNull => null;
}

final class UpdatePlanningFailure<T> extends UpdatePlanningResult<T> {
  UpdatePlanningFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
    List<SourceAcquisitionWarning> sourceWarnings =
        const <SourceAcquisitionWarning>[],
  }) : context = Map<String, Object?>.unmodifiable(context),
       sourceWarnings = List<SourceAcquisitionWarning>.unmodifiable(
         sourceWarnings,
       );

  final UpdatePlanningFailureCode code;
  final Map<String, Object?> context;
  final List<SourceAcquisitionWarning> sourceWarnings;

  @override
  T? get valueOrNull => null;

  @override
  UpdatePlanningFailure<T> get failureOrNull => this;
}

/// Authoritative revision facts read from one Control Plane snapshot.
final class UpdateRevisionState {
  UpdateRevisionState({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.previousUpstream,
    required this.currentEffective,
    required this.previousUpstreamContentHash,
    required this.managedSkillCreatedAtMicros,
    required this.draftCreatedAtMicros,
  }) {
    _requireHash(previousUpstreamContentHash, 'previousUpstreamContentHash');
    _requireTimestamp(
      managedSkillCreatedAtMicros,
      'managedSkillCreatedAtMicros',
    );
    if (draftCreatedAtMicros case final created?) {
      _requireTimestamp(created, 'draftCreatedAtMicros');
    }
  }

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId previousUpstream;
  final RevisionObjectId currentEffective;
  final String previousUpstreamContentHash;
  final int managedSkillCreatedAtMicros;
  final int? draftCreatedAtMicros;
}

enum UpdateDraftInspectionState { absent, clean, dirty }

final class UpdateDraftInspection {
  const UpdateDraftInspection.absent()
    : state = UpdateDraftInspectionState.absent;

  const UpdateDraftInspection.clean()
    : state = UpdateDraftInspectionState.clean;

  const UpdateDraftInspection.dirty()
    : state = UpdateDraftInspectionState.dirty;

  final UpdateDraftInspectionState state;

  bool get isDirty => state == UpdateDraftInspectionState.dirty;
  bool get hasCleanDraft => state == UpdateDraftInspectionState.clean;
}

sealed class UpdateDraftInspectionResult {
  const UpdateDraftInspectionResult();
}

final class UpdateDraftInspectionSuccess extends UpdateDraftInspectionResult {
  const UpdateDraftInspectionSuccess(this.inspection);

  final UpdateDraftInspection inspection;
}

final class UpdateDraftInspectionFailure extends UpdateDraftInspectionResult {
  const UpdateDraftInspectionFailure(this.reason);

  final String reason;
}

sealed class UpdateSlotMigrationInspectionResult {
  const UpdateSlotMigrationInspectionResult();
}

final class UpdateSlotMigrationInspectionSuccess
    extends UpdateSlotMigrationInspectionResult {
  const UpdateSlotMigrationInspectionSuccess();
}

final class UpdateSlotMigrationInspectionFailure
    extends UpdateSlotMigrationInspectionResult {
  const UpdateSlotMigrationInspectionFailure(this.reason);

  final String reason;
}

sealed class PlannedUpdate {
  const PlannedUpdate({required this.managedSkillId});

  final ManagedSkillId managedSkillId;
}

final class UpdateCheck {
  UpdateCheck({
    required this.managedSkillId,
    required this.currentUpstreamContentHash,
    required this.incomingContentHash,
    required this.incomingDeclaredName,
    required this.incomingSlotKey,
    this.resolvedSourceRevision,
    List<SourceAcquisitionWarning> sourceWarnings =
        const <SourceAcquisitionWarning>[],
  }) : sourceWarnings = List<SourceAcquisitionWarning>.unmodifiable(
         sourceWarnings,
       ) {
    _requireHash(currentUpstreamContentHash, 'currentUpstreamContentHash');
    _requireHash(incomingContentHash, 'incomingContentHash');
    _requireText(incomingDeclaredName, 'incomingDeclaredName');
    _requireText(incomingSlotKey, 'incomingSlotKey');
  }

  final ManagedSkillId managedSkillId;
  final String currentUpstreamContentHash;
  final String incomingContentHash;
  final String incomingDeclaredName;
  final String incomingSlotKey;
  final String? resolvedSourceRevision;
  final List<SourceAcquisitionWarning> sourceWarnings;

  bool get changed => currentUpstreamContentHash != incomingContentHash;
}

final class UpdateNoChange extends PlannedUpdate {
  UpdateNoChange({
    required super.managedSkillId,
    required this.contentHash,
    List<SourceAcquisitionWarning> sourceWarnings =
        const <SourceAcquisitionWarning>[],
  }) : sourceWarnings = List<SourceAcquisitionWarning>.unmodifiable(
         sourceWarnings,
       ) {
    _requireHash(contentHash, 'contentHash');
  }

  final String contentHash;
  final List<SourceAcquisitionWarning> sourceWarnings;
}

/// Pure, Journal-safe description of the revision work an Update requires.
///
/// This intent may be constructed before an Operation ID exists because it
/// contains no Store object, staging path, or recovery reference. A caller
/// must allocate the Operation ID and durably journal this intent before
/// invoking [UpdateRevisionPreparationPort].
final class UpdateRevisionPreparationIntent {
  UpdateRevisionPreparationIntent({
    required this.managedSkillId,
    required this.expectedRepositoryRevision,
    required this.sourceLineage,
    required this.previousUpstream,
    required this.currentEffective,
    required this.currentSlotKey,
    required this.currentDeclaredName,
    required this.currentDisplayName,
    required List<SkillActivation> activations,
    required this.managedSkillCreatedAtMicros,
    required this.draftCreatedAtMicros,
    required this.incomingTree,
    required this.incomingDeclaredName,
    required this.incomingDescription,
    required this.incomingSlotKey,
    required this.resolvedSourceRevision,
    required this.hadCleanDraft,
  }) : activations = List<SkillActivation>.unmodifiable(activations);

  final ManagedSkillId managedSkillId;
  final RepositoryRevision expectedRepositoryRevision;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId previousUpstream;
  final RevisionObjectId currentEffective;
  final String currentSlotKey;
  final String currentDeclaredName;
  final String currentDisplayName;
  final List<SkillActivation> activations;
  final int managedSkillCreatedAtMicros;
  final int? draftCreatedAtMicros;
  final NormalizedSkillTree incomingTree;
  final String incomingDeclaredName;
  final String incomingDescription;
  final String incomingSlotKey;
  final String? resolvedSourceRevision;
  final bool hadCleanDraft;
}

final class UpdatePreparationRequired extends PlannedUpdate {
  UpdatePreparationRequired({
    required super.managedSkillId,
    required this.snapshotRevision,
    required this.plannedAtMicros,
    required this.currentSkill,
    required this.revisionState,
    required this.intent,
    List<SourceAcquisitionWarning> sourceWarnings =
        const <SourceAcquisitionWarning>[],
  }) : sourceWarnings = List<SourceAcquisitionWarning>.unmodifiable(
         sourceWarnings,
       );

  final RepositoryRevision snapshotRevision;
  final int plannedAtMicros;
  final ManagedSkill currentSkill;
  final UpdateRevisionState revisionState;
  final UpdateRevisionPreparationIntent intent;
  final List<SourceAcquisitionWarning> sourceWarnings;
}

enum UpdateDraftDisposition { noDraft, deleteUnchanged, preserveAndReanchor }

sealed class PreparedUpdateOutcome {
  const PreparedUpdateOutcome();
}

final class PreparedUpdateClean extends PreparedUpdateOutcome {
  PreparedUpdateClean({
    required this.effectiveObjectId,
    required this.mergedTreeObjectId,
    required this.effectiveRequest,
    required this.mergedTree,
    required this.declaredName,
    required this.description,
    required this.draftDisposition,
    required this.capturedDraftFingerprint,
  }) {
    _requireText(declaredName, 'declaredName');
    _requireText(description, 'description');
  }

  final RevisionObjectId effectiveObjectId;
  final RevisionObjectId mergedTreeObjectId;
  final RevisionCommitRequest effectiveRequest;
  final NormalizedSkillTree mergedTree;
  final String declaredName;
  final String description;
  final UpdateDraftDisposition draftDisposition;
  final DraftFingerprint? capturedDraftFingerprint;
}

final class PreparedUpdateConflict extends PreparedUpdateOutcome {
  PreparedUpdateConflict({
    required this.candidateObjectId,
    required this.candidateTree,
    required List<WorkspaceUpdateCandidateItem> conflicts,
  }) : conflicts = List<WorkspaceUpdateCandidateItem>.unmodifiable(conflicts) {
    if (conflicts.isEmpty ||
        conflicts.any(
          (item) => item.state != WorkspaceUpdateCandidateItemState.unresolved,
        )) {
      throw ArgumentError.value(
        conflicts,
        'conflicts',
        'must contain unresolved conflicts',
      );
    }
  }

  final RevisionObjectId candidateObjectId;
  final NormalizedSkillTree candidateTree;
  final List<WorkspaceUpdateCandidateItem> conflicts;
}

final class PreparedUpdateValidationFailure extends PreparedUpdateOutcome {
  PreparedUpdateValidationFailure({
    required this.candidateObjectId,
    required this.candidateTree,
    required this.validationCode,
  }) {
    _requireText(validationCode, 'validationCode');
  }

  final RevisionObjectId candidateObjectId;
  final NormalizedSkillTree candidateTree;
  final String validationCode;
}

/// Post-Journal evidence produced by the Revision preparation boundary.
final class PreparedUpdateRevision {
  const PreparedUpdateRevision({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.incomingTreeObjectId,
    required this.incomingUpstreamObjectId,
    required this.incomingRequest,
    required this.outcome,
    required this.candidateRecoveryReference,
    required this.bundleRecoveryReference,
    required this.materializationRecoveryReference,
    required this.draftRecoveryReference,
  });

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId incomingTreeObjectId;
  final RevisionObjectId incomingUpstreamObjectId;
  final RevisionCommitRequest incomingRequest;
  final PreparedUpdateOutcome outcome;
  final RecoveryReference candidateRecoveryReference;
  final RecoveryReference bundleRecoveryReference;
  final RecoveryReference materializationRecoveryReference;
  final RecoveryReference draftRecoveryReference;
}

enum PreparedUpdatePlanKind { published, sessionCreated }

final class UpdateRevisionRecoveryIntent {
  UpdateRevisionRecoveryIntent({
    required this.managedSkillId,
    required this.sourceLineage,
    required List<RevisionObjectId> retainedRoots,
    required this.candidateRecoveryReference,
    required this.bundleRecoveryReference,
    this.draftCleanup,
  }) : retainedRoots = List<RevisionObjectId>.unmodifiable(retainedRoots) {
    if (retainedRoots.isEmpty) {
      throw ArgumentError.value(
        retainedRoots,
        'retainedRoots',
        'must not be empty',
      );
    }
  }

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final List<RevisionObjectId> retainedRoots;
  final RecoveryReference candidateRecoveryReference;
  final RecoveryReference bundleRecoveryReference;
  final PublishedDraftCleanupIntent? draftCleanup;
}

sealed class UpdateMaterializationIntent {
  const UpdateMaterializationIntent({
    required this.managedSkillId,
    required this.revision,
    required this.recoveryReference,
  });

  final ManagedSkillId managedSkillId;
  final RevisionAddress revision;
  final RecoveryReference recoveryReference;
}

final class UpdateRepositoryMaterializationIntent
    extends UpdateMaterializationIntent {
  const UpdateRepositoryMaterializationIntent({
    required super.managedSkillId,
    required super.revision,
    required super.recoveryReference,
    required this.oldSlotKey,
    required this.newSlotKey,
  });

  final String oldSlotKey;
  final String newSlotKey;
}

final class UpdateActivationMaterializationIntent
    extends UpdateMaterializationIntent {
  const UpdateActivationMaterializationIntent({
    required super.managedSkillId,
    required super.revision,
    required super.recoveryReference,
    required this.activation,
    required this.oldSlotKey,
    required this.newSlotKey,
  });

  final SkillActivation activation;
  final String oldSlotKey;
  final String newSlotKey;
}

final class UpdateCandidateDraftMaterializationIntent
    extends UpdateMaterializationIntent {
  const UpdateCandidateDraftMaterializationIntent({
    required super.managedSkillId,
    required super.revision,
    required super.recoveryReference,
    required this.draftRecoveryReference,
  });

  final RecoveryReference draftRecoveryReference;
}

final class PreparedUpdatePlan {
  PreparedUpdatePlan({
    required this.kind,
    required this.businessChanges,
    required List<RevisionSelectionChangePlan> revisionSelectionChanges,
    required this.recoveryIntent,
    required List<UpdateMaterializationIntent> materializationIntents,
  }) : revisionSelectionChanges =
           List<RevisionSelectionChangePlan>.unmodifiable(
             revisionSelectionChanges,
           ),
       materializationIntents = List<UpdateMaterializationIntent>.unmodifiable(
         materializationIntents,
       );

  final PreparedUpdatePlanKind kind;
  final WorkspaceBusinessChangeSet businessChanges;
  final List<RevisionSelectionChangePlan> revisionSelectionChanges;
  final UpdateRevisionRecoveryIntent recoveryIntent;
  final List<UpdateMaterializationIntent> materializationIntents;
}

final class UpdateCandidateState {
  UpdateCandidateState({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.previousUpstream,
    required this.previousEffective,
    required this.incomingUpstream,
    required this.candidateObjectId,
    required this.incomingDeclaredName,
    required this.incomingSlotKey,
    required this.incomingDescription,
    required this.managedSkillCreatedAtMicros,
    required this.draftCreatedAtMicros,
    required List<RevisionObjectId> retainedPublishedRoots,
    required List<WorkspaceUpdateCandidateItem> conflicts,
  }) : retainedPublishedRoots = List<RevisionObjectId>.unmodifiable(
         _normalizeRevisionRoots(retainedPublishedRoots),
       ),
       conflicts = List<WorkspaceUpdateCandidateItem>.unmodifiable(conflicts) {
    _requireText(incomingDeclaredName, 'incomingDeclaredName');
    _requireText(incomingSlotKey, 'incomingSlotKey');
    _requireText(incomingDescription, 'incomingDescription');
    _requireTimestamp(
      managedSkillCreatedAtMicros,
      'managedSkillCreatedAtMicros',
    );
    _requireTimestamp(draftCreatedAtMicros, 'draftCreatedAtMicros');
  }

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId previousUpstream;
  final RevisionObjectId previousEffective;
  final RevisionObjectId incomingUpstream;
  final RevisionObjectId candidateObjectId;
  final String incomingDeclaredName;
  final String incomingSlotKey;
  final String incomingDescription;
  final int managedSkillCreatedAtMicros;
  final int draftCreatedAtMicros;
  final List<RevisionObjectId> retainedPublishedRoots;
  final List<WorkspaceUpdateCandidateItem> conflicts;

  bool get hasUnresolvedConflicts => conflicts.any(
    (item) => item.state == WorkspaceUpdateCandidateItemState.unresolved,
  );
}

final class UpdateCandidatePublishPreparationIntent {
  UpdateCandidatePublishPreparationIntent({
    required this.managedSkillId,
    required this.expectedRepositoryRevision,
    required this.sourceLineage,
    required this.previousUpstream,
    required this.previousEffective,
    required this.incomingUpstream,
    required this.candidateObjectId,
    required this.requiredDeclaredName,
    required this.currentSlotKey,
    required this.currentDeclaredName,
    required this.currentDisplayName,
    required List<SkillActivation> activations,
    required this.incomingSlotKey,
    required this.incomingDescription,
    required this.managedSkillCreatedAtMicros,
    required this.draftCreatedAtMicros,
  }) : activations = List<SkillActivation>.unmodifiable(activations);

  final ManagedSkillId managedSkillId;
  final RepositoryRevision expectedRepositoryRevision;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId previousUpstream;
  final RevisionObjectId previousEffective;
  final RevisionObjectId incomingUpstream;
  final RevisionObjectId candidateObjectId;
  final String requiredDeclaredName;
  final String currentSlotKey;
  final String currentDeclaredName;
  final String currentDisplayName;
  final List<SkillActivation> activations;
  final String incomingSlotKey;
  final String incomingDescription;
  final int managedSkillCreatedAtMicros;
  final int draftCreatedAtMicros;
}

final class UpdateCandidatePublishPreflight {
  const UpdateCandidatePublishPreflight({
    required this.snapshotRevision,
    required this.plannedAtMicros,
    required this.currentSkill,
    required this.state,
    required this.intent,
  });

  final RepositoryRevision snapshotRevision;
  final int plannedAtMicros;
  final ManagedSkill currentSkill;
  final UpdateCandidateState state;
  final UpdateCandidatePublishPreparationIntent intent;
}

/// Post-Journal immutable Draft and revision evidence for Session Publish.
final class PreparedUpdateCandidatePublish {
  PreparedUpdateCandidatePublish({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.effectiveObjectId,
    required this.publishedTreeObjectId,
    required this.effectiveRequest,
    required this.publishedTree,
    required this.declaredName,
    required this.description,
    required this.draftDisposition,
    required this.capturedDraftFingerprint,
    required this.candidateRecoveryReference,
    required this.bundleRecoveryReference,
    required this.materializationRecoveryReference,
    required this.draftRecoveryReference,
  }) {
    _requireText(declaredName, 'declaredName');
    _requireText(description, 'description');
  }

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId effectiveObjectId;
  final RevisionObjectId publishedTreeObjectId;
  final RevisionCommitRequest effectiveRequest;
  final NormalizedSkillTree publishedTree;
  final String declaredName;
  final String description;
  final UpdateDraftDisposition draftDisposition;
  final DraftFingerprint capturedDraftFingerprint;
  final RecoveryReference candidateRecoveryReference;
  final RecoveryReference bundleRecoveryReference;
  final RecoveryReference materializationRecoveryReference;
  final RecoveryReference draftRecoveryReference;
}

final class UpdateCandidateCleanupIntent {
  UpdateCandidateCleanupIntent({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.previousUpstream,
    required this.previousEffective,
    required this.incomingUpstream,
    required this.candidateObjectId,
    required List<RevisionObjectId> retainedPublishedRoots,
  }) : retainedPublishedRoots = List<RevisionObjectId>.unmodifiable(
         _normalizeRevisionRoots(retainedPublishedRoots),
       );

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId previousUpstream;
  final RevisionObjectId previousEffective;
  final RevisionObjectId incomingUpstream;
  final RevisionObjectId candidateObjectId;
  final List<RevisionObjectId> retainedPublishedRoots;
}

/// Verified operation-private Bundle evidence used when abandoning a Session.
///
/// Candidate and incoming objects may remain physically present in the Store
/// until a future maintenance compaction, but they are deliberately absent
/// from this retained-root set and from the replacement recovery Bundle.
final class PreparedUpdateCandidateAbandon {
  PreparedUpdateCandidateAbandon({
    required this.managedSkillId,
    required this.sourceLineage,
    required List<RevisionObjectId> retainedPublishedRoots,
    required this.bundleRecoveryReference,
  }) : retainedPublishedRoots = List<RevisionObjectId>.unmodifiable(
         _normalizeRevisionRoots(retainedPublishedRoots),
       );

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final List<RevisionObjectId> retainedPublishedRoots;
  final RecoveryReference bundleRecoveryReference;
}

final class UpdateCandidateAbandonPlan {
  UpdateCandidateAbandonPlan({
    required this.businessChanges,
    required List<RevisionSelectionChangePlan> revisionSelectionChanges,
    required this.cleanupIntent,
  }) : revisionSelectionChanges =
           List<RevisionSelectionChangePlan>.unmodifiable(
             revisionSelectionChanges,
           );

  final WorkspaceBusinessChangeSet businessChanges;
  final List<RevisionSelectionChangePlan> revisionSelectionChanges;
  final UpdateCandidateCleanupIntent cleanupIntent;
}

final class UpdateConflictResolutionPlan {
  const UpdateConflictResolutionPlan({
    required this.changed,
    required this.businessChanges,
  });

  final bool changed;
  final WorkspaceBusinessChangeSet businessChanges;
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(value, name, 'must be non-empty text');
  }
}

void _requireHash(String value, String name) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a lowercase SHA-256 hash');
  }
}

List<RevisionObjectId> _normalizeRevisionRoots(
  Iterable<RevisionObjectId> roots,
) {
  final byValue = <String, RevisionObjectId>{
    for (final root in roots) root.value: root,
  };
  final normalized = byValue.values.toList(growable: false)
    ..sort((left, right) => left.value.compareTo(right.value));
  return normalized;
}

void _requireTimestamp(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}
