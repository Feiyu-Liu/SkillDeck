import '../../domain/identifiers.dart';
import '../../domain/source_descriptor.dart';
import '../operations/operation_models.dart';
import '../operations/workspace_business_changes.dart';
import '../runtime/revision_engine_port.dart';

enum DestructiveDraftState { absent, clean, dirty }

/// Identifies which destructive operation is requesting the lock-held state.
///
/// Source Replacement requires an authoritative dirty-state inspection for
/// its target. Removal only needs to know whether a Draft path exists because
/// the entire aggregate is deleted regardless of unpublished content.
enum DestructivePlanningPurpose { sourceReplacement, removal }

final class DestructiveSourceLineageState {
  const DestructiveSourceLineageState({required this.sourceLineage});

  final SourceLineageReference sourceLineage;
}

/// One authoritative, lock-held planning projection.
///
/// It carries business identities and revision addresses but no physical path.
final class DestructiveManagedSkillState {
  DestructiveManagedSkillState({
    required this.managedSkillId,
    required this.slotKey,
    required this.declaredName,
    required this.displayName,
    required this.description,
    required this.createdAtMicros,
    required List<DestructiveSourceLineageState> sourceLineages,
    required this.activeSourceLineage,
    required this.currentUpstream,
    required this.currentEffective,
    required this.currentContentHash,
    required List<String> activationIds,
    required this.draftState,
    required this.hasUpdateCandidateSession,
  }) : sourceLineages = List.unmodifiable(sourceLineages),
       activationIds = List.unmodifiable(activationIds) {
    _requireText(slotKey, 'slotKey');
    _requireText(declaredName, 'declaredName');
    _requireText(displayName, 'displayName');
    _requireText(description, 'description');
    if (createdAtMicros < 0) {
      throw ArgumentError.value(
        createdAtMicros,
        'createdAtMicros',
        'must not be negative',
      );
    }
    final lineages = sourceLineages
        .map((lineage) => lineage.sourceLineage)
        .toSet();
    if (sourceLineages.isEmpty || lineages.length != sourceLineages.length) {
      throw ArgumentError.value(
        sourceLineages,
        'sourceLineages',
        'must contain unique lineages',
      );
    }
    if (!lineages.contains(activeSourceLineage)) {
      throw ArgumentError('The active Source Lineage must be present.');
    }
    if (currentUpstream.sourceLineage != activeSourceLineage ||
        currentEffective.sourceLineage != activeSourceLineage) {
      throw ArgumentError('Current revisions must use the active lineage.');
    }
    _requireHash(currentContentHash, 'currentContentHash');
    if (activationIds.any((id) => id.trim().isEmpty) ||
        activationIds.toSet().length != activationIds.length) {
      throw ArgumentError.value(
        activationIds,
        'activationIds',
        'must contain unique non-empty IDs',
      );
    }
  }

  final ManagedSkillId managedSkillId;
  final String slotKey;
  final String declaredName;
  final String displayName;
  final String description;
  final int createdAtMicros;
  final List<DestructiveSourceLineageState> sourceLineages;
  final SourceLineageReference activeSourceLineage;
  final RevisionAddress currentUpstream;
  final RevisionAddress currentEffective;
  final String currentContentHash;
  final List<String> activationIds;
  final DestructiveDraftState draftState;
  final bool hasUpdateCandidateSession;
}

final class DestructivePlanningSnapshot {
  DestructivePlanningSnapshot({
    required this.repositoryRevision,
    required List<DestructiveManagedSkillState> managedSkills,
  }) : managedSkills = List.unmodifiable(managedSkills) {
    if (managedSkills.map((skill) => skill.managedSkillId).toSet().length !=
            managedSkills.length ||
        managedSkills.map((skill) => skill.slotKey).toSet().length !=
            managedSkills.length) {
      throw ArgumentError.value(
        managedSkills,
        'managedSkills',
        'contains duplicate identity or Slot Key',
      );
    }
  }

  final RepositoryRevision repositoryRevision;
  final List<DestructiveManagedSkillState> managedSkills;

  DestructiveManagedSkillState? findSkill(ManagedSkillId id) {
    for (final skill in managedSkills) {
      if (skill.managedSkillId == id) return skill;
    }
    return null;
  }
}

final class DestructiveOperationIntent {
  const DestructiveOperationIntent({required this.reviewedRevision});

  final RepositoryRevision reviewedRevision;
}

enum DestructivePlanningFailureCode {
  staleIntent,
  managedSkillNotFound,
  operationCancelled,
  dirtyDraftResolutionRequired,
  updateCandidateResolutionRequired,
  sourcePreparationFailed,
  replacementSlotOccupied,
  invalidReplacementCandidate,
}

sealed class DestructivePlanningResult<T> {
  const DestructivePlanningResult();

  T? get valueOrNull;
  DestructivePlanningFailure<T>? get failureOrNull;
}

final class DestructivePlanningSuccess<T> extends DestructivePlanningResult<T> {
  const DestructivePlanningSuccess(this.value);

  final T value;

  @override
  T get valueOrNull => value;

  @override
  DestructivePlanningFailure<T>? get failureOrNull => null;
}

final class DestructivePlanningFailure<T> extends DestructivePlanningResult<T> {
  DestructivePlanningFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map.unmodifiable(context);

  final DestructivePlanningFailureCode code;
  final Map<String, Object?> context;

  @override
  T? get valueOrNull => null;

  @override
  DestructivePlanningFailure<T> get failureOrNull => this;
}

final class SourceReplacementPreparationIntent {
  const SourceReplacementPreparationIntent({
    required this.operationId,
    required this.managedSkillId,
    required this.source,
    required this.intendedSourceLineage,
    required this.includeInternal,
    required this.fullDepth,
  });

  final OperationId operationId;
  final ManagedSkillId managedSkillId;
  final SourceDescriptor source;
  final SourceLineageReference intendedSourceLineage;
  final bool includeInternal;
  final bool fullDepth;
}

final class PreparedSourceReplacement {
  PreparedSourceReplacement({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.objectId,
    required this.objectFormat,
    required this.persistedSourceKind,
    required this.sourcePayloadSchemaVersion,
    required this.sourcePayloadJson,
    required this.slotKey,
    required this.declaredName,
    required this.displayName,
    required this.description,
    required this.contentHash,
    required this.fileCount,
    required this.byteSize,
  }) {
    if (sourcePayloadSchemaVersion < 1) {
      throw ArgumentError('Payload schema must be positive.');
    }
    _requireText(sourcePayloadJson, 'sourcePayloadJson');
    _requireText(slotKey, 'slotKey');
    _requireText(declaredName, 'declaredName');
    _requireText(displayName, 'displayName');
    _requireText(description, 'description');
    _requireHash(contentHash, 'contentHash');
    if (fileCount < 0 || byteSize < 0) {
      throw ArgumentError('Revision counts must not be negative.');
    }
  }

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId objectId;
  final WorkspaceObjectFormat objectFormat;
  final WorkspaceSourceKind persistedSourceKind;
  final int sourcePayloadSchemaVersion;
  final String sourcePayloadJson;
  final String slotKey;
  final String declaredName;
  final String displayName;
  final String description;
  final String contentHash;
  final int fileCount;
  final int byteSize;
}

enum SourceReplacementPreparationFailureCode {
  operationCancelled,
  sourceUnavailable,
  sourceAmbiguous,
  sourcePayloadInvalid,
  revisionPreparationFailed,
  ioFailure,
}

sealed class SourceReplacementPreparationResult {
  const SourceReplacementPreparationResult();
}

final class SourceReplacementPreparationSuccess
    extends SourceReplacementPreparationResult {
  const SourceReplacementPreparationSuccess(this.candidate);

  final PreparedSourceReplacement candidate;
}

final class SourceReplacementPreparationFailure
    extends SourceReplacementPreparationResult {
  const SourceReplacementPreparationFailure(this.code);

  final SourceReplacementPreparationFailureCode code;
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
