import 'dart:typed_data';

import 'identifiers.dart';
import 'immutable.dart';
import 'source_descriptor.dart';

enum ActivationScope { global, project }

enum ActivationMode { copy, symbolicLink }

enum RequestedActivationMode { automatic, copy, symbolicLink }

enum WorkspaceIntegrityStatus { healthy, recovered, corrupt }

enum SkillIntegrityStatus {
  healthy,
  recovered,
  unverified,
  validating,
  driftPending,
  repairFailed,
  revisionStoreCorrupt,
}

enum DraftPurpose { customization, updateCandidateResolution }

enum UpdateCandidateStatus { conflicted, validationFailed }

enum ConflictKind { text, rename, deleteModify, binary, executableMode }

enum UpdateConflictResolutionState { unresolved, resolved }

enum SkillDriftLocationKind {
  repositoryCopy,
  copyActivation,
  symbolicLinkActivation,
}

enum SkillDriftKind { contentChanged, wrongEntryType, wrongLinkTarget }

enum WorkspaceOperationKind {
  open,
  refresh,
  resumeFinalizationRecovery,
  close,
  inspectSource,
  listEffectiveFiles,
  readEffectiveFile,
  install,
  confirmInstallTakeover,
  adopt,
  checkUpdates,
  update,
  replaceSource,
  inspectActivationTargets,
  inspectAgents,
  inspectAgentRootOwnership,
  activate,
  confirmActivationTakeover,
  deactivate,
  discoverExternalSkills,
  registerProjectRoot,
  unregisterProjectRoot,
  remove,
  reconfigureAgentCatalog,
  setFavorite,
  saveNote,
  deleteNote,
  createPersonalTag,
  updatePersonalTag,
  deletePersonalTag,
  assignPersonalTag,
  unassignPersonalTag,
  ensureDraft,
  inspectDraft,
  discardDraft,
  publishDraft,
  inspectUpdateCandidate,
  resolveUpdateConflict,
  publishUpdateCandidate,
  abandonUpdateCandidate,
  inspectOperationHistory,
  inspectPublishedHistory,
  inspectDiff,
  restorePublish,
  validateWorkspace,
  inspectSkillDrift,
  exportSkillDriftArtifact,
  resolveSkillDrift,
}

enum OperationProgressPhase {
  queued,
  inspecting,
  preparing,
  applying,
  committing,
  finalizing,
}

enum OperationTerminalStatus {
  succeeded,
  failed,
  cancelled,
  committedFinalizationPending,
}

enum DiffFileStatus { added, deleted, modified, renamed, modeChanged }

enum DiffLineKind { context, addition, deletion }

enum DesktopPlatform { macos, windows, linux }

enum AgentDetectionKind { pathExists, packageDependency }

enum AgentSkillRootRole { canonicalActivation, compatibilityDiscovery }

enum AgentRootOwnershipIssueReason {
  ownerMismatch,
  outsideUserHome,
  notDirectory,
  inspectionFailed,
}

final class WorkspaceIntegrity {
  WorkspaceIntegrity({
    this.status = WorkspaceIntegrityStatus.healthy,
    List<ManagedSkillIntegrity> skills = const [],
  }) : skills = List.unmodifiable(skills);

  final WorkspaceIntegrityStatus status;
  final List<ManagedSkillIntegrity> skills;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceIntegrity &&
          status == other.status &&
          listsEqual(skills, other.skills);

  @override
  int get hashCode => Object.hash(status, Object.hashAll(skills));
}

final class ManagedSkillIntegrity {
  const ManagedSkillIntegrity({
    required this.managedSkillId,
    required this.status,
  });

  final ManagedSkillId managedSkillId;
  final SkillIntegrityStatus status;
  bool get mutationBlocked => switch (status) {
    SkillIntegrityStatus.driftPending ||
    SkillIntegrityStatus.repairFailed ||
    SkillIntegrityStatus.revisionStoreCorrupt => true,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedSkillIntegrity &&
          managedSkillId == other.managedSkillId &&
          status == other.status;

  @override
  int get hashCode => Object.hash(managedSkillId, status);
}

final class WorkspaceValidationReport {
  WorkspaceValidationReport({
    required this.checkedSkillCount,
    required this.repairedArtifactCount,
    required this.healthySkillCount,
    required List<ManagedSkillId> repairedSkillIds,
    required List<ManagedSkillId> driftedSkillIds,
    required List<ManagedSkillId> failedSkillIds,
  }) : repairedSkillIds = List.unmodifiable(repairedSkillIds),
       driftedSkillIds = List.unmodifiable(driftedSkillIds),
       failedSkillIds = List.unmodifiable(failedSkillIds);

  final int checkedSkillCount;
  final int repairedArtifactCount;
  final int healthySkillCount;
  final List<ManagedSkillId> repairedSkillIds;
  final List<ManagedSkillId> driftedSkillIds;
  final List<ManagedSkillId> failedSkillIds;
}

final class ProjectRoot {
  ProjectRoot({required this.id, required this.path}) {
    _requireNonEmpty(id, 'id');
    _requireAbsolutePath(path, 'path');
  }

  final String id;
  final String path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectRoot && id == other.id && path == other.path;

  @override
  int get hashCode => Object.hash(id, path);
}

final class SkillFavorite {
  const SkillFavorite({required this.isFavorite, this.changedAt});

  final bool isFavorite;
  final DateTime? changedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillFavorite &&
          isFavorite == other.isFavorite &&
          changedAt == other.changedAt;

  @override
  int get hashCode => Object.hash(isFavorite, changedAt);
}

final class SkillNote {
  SkillNote({required this.text, required this.updatedAt}) {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be empty');
    }
  }

  final String text;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillNote && text == other.text && updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(text, updatedAt);
}

final class PersonalTag {
  PersonalTag({
    required this.id,
    required this.name,
    this.color,
    required this.createdAt,
    required this.updatedAt,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(name, 'name');
    if (color != null && !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color!)) {
      throw ArgumentError.value(
        color,
        'color',
        'must be a six-digit hex color',
      );
    }
  }

  final String id;
  final String name;
  final String? color;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonalTag &&
          id == other.id &&
          name == other.name &&
          color == other.color &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(id, name, color, createdAt, updatedAt);
}

final class ManagedSkillRevisionSummary {
  ManagedSkillRevisionSummary({
    required this.contentHash,
    required this.fileCount,
    required this.byteSize,
    required this.publishedAt,
    this.resolvedSourceRevision,
  }) {
    _requireSha256(contentHash, 'contentHash');
    _requireNonNegative(fileCount, 'fileCount');
    _requireNonNegative(byteSize, 'byteSize');
  }

  final String contentHash;
  final int fileCount;
  final int byteSize;
  final DateTime publishedAt;
  final String? resolvedSourceRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedSkillRevisionSummary &&
          contentHash == other.contentHash &&
          fileCount == other.fileCount &&
          byteSize == other.byteSize &&
          publishedAt == other.publishedAt &&
          resolvedSourceRevision == other.resolvedSourceRevision;

  @override
  int get hashCode => Object.hash(
    contentHash,
    fileCount,
    byteSize,
    publishedAt,
    resolvedSourceRevision,
  );
}

/// Immutable metadata for every regular file in the current Effective
/// Revision of one managed Skill.
///
/// This does not expose an Internal Revision Store address, Git object ID, or
/// any Workspace filesystem layout. Callers use [contentHash] as the
/// precondition for a subsequent [ReadEffectiveFileRequest].
final class EffectiveSkillFileManifest {
  EffectiveSkillFileManifest({
    required this.managedSkillId,
    required this.contentHash,
    required List<EffectiveSkillFileEntry> files,
  }) : files = List.unmodifiable(files) {
    _requireSha256(contentHash, 'contentHash');
    _requireUnique(this.files.map((file) => file.relativePath), 'files paths');
  }

  final ManagedSkillId managedSkillId;
  final String contentHash;
  final List<EffectiveSkillFileEntry> files;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EffectiveSkillFileManifest &&
          managedSkillId == other.managedSkillId &&
          contentHash == other.contentHash &&
          listsEqual(files, other.files);

  @override
  int get hashCode =>
      Object.hash(managedSkillId, contentHash, Object.hashAll(files));
}

/// Metadata for one regular file in an [EffectiveSkillFileManifest].
final class EffectiveSkillFileEntry {
  const EffectiveSkillFileEntry({
    required this.relativePath,
    required this.byteSize,
    required this.isExecutable,
  });

  final String relativePath;
  final int byteSize;
  final bool isExecutable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EffectiveSkillFileEntry &&
          relativePath == other.relativePath &&
          byteSize == other.byteSize &&
          isExecutable == other.isExecutable;

  @override
  int get hashCode => Object.hash(relativePath, byteSize, isExecutable);
}

/// A defensive byte copy from a file in the current Effective Revision.
///
/// The caller owns [bytes] and may mutate that returned buffer without
/// affecting any Workspace-owned content.
final class EffectiveSkillFileContent {
  EffectiveSkillFileContent({
    required this.managedSkillId,
    required this.contentHash,
    required this.relativePath,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes) {
    _requireSha256(contentHash, 'contentHash');
  }

  final ManagedSkillId managedSkillId;
  final String contentHash;
  final String relativePath;
  final Uint8List bytes;
}

final class SkillActivation {
  SkillActivation({
    required this.location,
    required this.scope,
    required this.mode,
    required List<String> agentIds,
    this.projectRootId,
    this.projectRootPath,
  }) : agentIds = List.unmodifiable(agentIds) {
    _requireAbsolutePath(location, 'location');
    _requireNonEmptyList(this.agentIds, 'agentIds');
    if (scope == ActivationScope.project &&
        (projectRootId == null || projectRootPath == null)) {
      throw ArgumentError(
        'Project activations require Project Root provenance.',
      );
    }
    if (scope == ActivationScope.global &&
        (projectRootId != null || projectRootPath != null)) {
      throw ArgumentError(
        'Global activations cannot have Project Root provenance.',
      );
    }
    if (projectRootPath != null) {
      _requireAbsolutePath(projectRootPath!, 'projectRootPath');
    }
  }

  final String location;
  final ActivationScope scope;
  final ActivationMode mode;
  final List<String> agentIds;
  final String? projectRootId;
  final String? projectRootPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillActivation &&
          location == other.location &&
          scope == other.scope &&
          mode == other.mode &&
          listsEqual(agentIds, other.agentIds) &&
          projectRootId == other.projectRootId &&
          projectRootPath == other.projectRootPath;

  @override
  int get hashCode => Object.hash(
    location,
    scope,
    mode,
    Object.hashAll(agentIds),
    projectRootId,
    projectRootPath,
  );
}

final class DraftSummary {
  DraftSummary({
    required this.purpose,
    required this.path,
    required this.isDirty,
    required this.updatedAt,
  }) {
    _requireAbsolutePath(path, 'path');
  }

  final DraftPurpose purpose;
  final String path;
  final bool isDirty;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DraftSummary &&
          purpose == other.purpose &&
          path == other.path &&
          isDirty == other.isDirty &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(purpose, path, isDirty, updatedAt);
}

final class UpdateConflict {
  UpdateConflict({
    required this.path,
    required this.kind,
    required this.resolutionState,
  }) {
    _requireSafeRelativePath(path, 'path');
  }

  final String path;
  final ConflictKind kind;
  final UpdateConflictResolutionState resolutionState;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateConflict &&
          path == other.path &&
          kind == other.kind &&
          resolutionState == other.resolutionState;

  @override
  int get hashCode => Object.hash(path, kind, resolutionState);
}

final class UpdateCandidateSummary {
  UpdateCandidateSummary({
    required this.status,
    required List<UpdateConflict> conflicts,
    required this.createdAt,
    this.validationCode,
  }) : conflicts = List.unmodifiable(conflicts) {
    if (status == UpdateCandidateStatus.conflicted && conflicts.isEmpty) {
      throw ArgumentError.value(conflicts, 'conflicts', 'must not be empty');
    }
    if (status == UpdateCandidateStatus.validationFailed &&
        (validationCode == null || validationCode!.trim().isEmpty)) {
      throw ArgumentError(
        'Validation-failed candidates require validationCode.',
      );
    }
  }

  final UpdateCandidateStatus status;
  final List<UpdateConflict> conflicts;
  final String? validationCode;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateCandidateSummary &&
          status == other.status &&
          listsEqual(conflicts, other.conflicts) &&
          validationCode == other.validationCode &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      Object.hash(status, Object.hashAll(conflicts), validationCode, createdAt);
}

final class ManagedSkill {
  ManagedSkill({
    required this.id,
    required this.slotKey,
    required this.declaredName,
    required this.displayName,
    required this.description,
    required this.source,
    required this.currentRevision,
    this.favorite = const SkillFavorite(isFavorite: false),
    this.note,
    List<String> personalTagIds = const [],
    List<SkillActivation> activations = const [],
    this.draft,
    this.updateCandidate,
  }) : personalTagIds = List.unmodifiable(personalTagIds),
       activations = List.unmodifiable(activations) {
    _requireNonEmpty(slotKey, 'slotKey');
    _requireNonEmpty(declaredName, 'declaredName');
    _requireNonEmpty(displayName, 'displayName');
    _requireNonEmpty(description, 'description');
    _requireNonEmptyList(
      this.personalTagIds,
      'personalTagIds',
      allowEmpty: true,
    );
  }

  final ManagedSkillId id;
  final String slotKey;
  final String declaredName;
  final String displayName;
  final String description;
  final SourceDescriptor source;
  final ManagedSkillRevisionSummary currentRevision;
  final SkillFavorite favorite;
  final SkillNote? note;
  final List<String> personalTagIds;
  final List<SkillActivation> activations;
  final DraftSummary? draft;
  final UpdateCandidateSummary? updateCandidate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedSkill &&
          id == other.id &&
          slotKey == other.slotKey &&
          declaredName == other.declaredName &&
          displayName == other.displayName &&
          description == other.description &&
          source == other.source &&
          currentRevision == other.currentRevision &&
          favorite == other.favorite &&
          note == other.note &&
          listsEqual(personalTagIds, other.personalTagIds) &&
          listsEqual(activations, other.activations) &&
          draft == other.draft &&
          updateCandidate == other.updateCandidate;

  @override
  int get hashCode => Object.hashAll([
    id,
    slotKey,
    declaredName,
    displayName,
    description,
    source,
    currentRevision,
    favorite,
    note,
    Object.hashAll(personalTagIds),
    Object.hashAll(activations),
    draft,
    updateCandidate,
  ]);
}

final class RepositorySnapshot {
  RepositorySnapshot({
    required this.revision,
    List<ManagedSkill> managedSkills = const [],
    List<ProjectRoot> projectRoots = const [],
    List<PersonalTag> personalTags = const [],
    WorkspaceIntegrity? integrity,
  }) : managedSkills = List.unmodifiable(managedSkills),
       projectRoots = List.unmodifiable(projectRoots),
       personalTags = List.unmodifiable(personalTags),
       integrity = integrity ?? WorkspaceIntegrity() {
    _requireUnique(
      this.managedSkills.map((skill) => skill.id),
      'managedSkills IDs',
    );
    _requireUnique(
      this.managedSkills.map((skill) => skill.slotKey),
      'managedSkills Slot Keys',
    );
    _requireUnique(this.projectRoots.map((root) => root.id), 'projectRoot IDs');
    _requireUnique(this.personalTags.map((tag) => tag.id), 'personalTag IDs');
  }

  factory RepositorySnapshot.empty() =>
      RepositorySnapshot(revision: RepositoryRevision.initial());

  final RepositoryRevision revision;
  final List<ManagedSkill> managedSkills;
  final List<ProjectRoot> projectRoots;
  final List<PersonalTag> personalTags;
  final WorkspaceIntegrity integrity;

  ManagedSkill? findSkill(ManagedSkillId id) =>
      _firstWhereOrNull(managedSkills, (skill) => skill.id == id);

  ManagedSkill? findSkillBySlotKey(String slotKey) =>
      _firstWhereOrNull(managedSkills, (skill) => skill.slotKey == slotKey);

  ProjectRoot? findProjectRoot(String id) =>
      _firstWhereOrNull(projectRoots, (root) => root.id == id);

  PersonalTag? findPersonalTag(String id) =>
      _firstWhereOrNull(personalTags, (tag) => tag.id == id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepositorySnapshot &&
          revision == other.revision &&
          listsEqual(managedSkills, other.managedSkills) &&
          listsEqual(projectRoots, other.projectRoots) &&
          listsEqual(personalTags, other.personalTags) &&
          integrity == other.integrity;

  @override
  int get hashCode => Object.hash(
    revision,
    Object.hashAll(managedSkills),
    Object.hashAll(projectRoots),
    Object.hashAll(personalTags),
    integrity,
  );
}

final class SourceCandidate {
  SourceCandidate({
    required this.declaredName,
    required this.description,
    required this.slotKey,
    required this.skillPath,
    required this.contentHash,
    required this.fileCount,
    required this.byteSize,
  }) {
    _requireNonEmpty(declaredName, 'declaredName');
    _requireNonEmpty(description, 'description');
    _requireNonEmpty(slotKey, 'slotKey');
    _requireSha256(contentHash, 'contentHash');
    _requireNonNegative(fileCount, 'fileCount');
    _requireNonNegative(byteSize, 'byteSize');
  }

  final String declaredName;
  final String description;
  final String slotKey;
  final String skillPath;
  final String contentHash;
  final int fileCount;
  final int byteSize;
}

final class SourceInspection {
  SourceInspection({
    required this.source,
    required List<SourceCandidate> candidates,
  }) : candidates = List.unmodifiable(candidates);

  final SourceDescriptor source;
  final List<SourceCandidate> candidates;
}

enum UpdateStatus {
  current,
  updateAvailable,
  sourceUnavailable,
  updateUnsupported,
  resolutionRequired,
}

enum UpdateCheckFailureReason {
  sourceUnavailable,
  authenticationRequired,
  gitUnavailable,
  developerToolsRequired,
  timedOut,
  gitFailed,
  ioFailure,
}

final class UpdateReport {
  const UpdateReport({
    required this.managedSkillId,
    required this.status,
    this.currentContentHash,
    this.availableContentHash,
    this.resolvedSourceRevision,
    this.failureReason,
  });

  final ManagedSkillId managedSkillId;
  final UpdateStatus status;
  final String? currentContentHash;
  final String? availableContentHash;
  final String? resolvedSourceRevision;
  final UpdateCheckFailureReason? failureReason;
}

final class UpdateCheckRecord {
  const UpdateCheckRecord({
    required this.managedSkillId,
    required this.basisFingerprint,
    required this.status,
    required this.checkedAt,
    this.currentContentHash,
    this.availableContentHash,
    this.resolvedSourceRevision,
  });

  final ManagedSkillId managedSkillId;
  final String basisFingerprint;
  final UpdateStatus status;
  final String? currentContentHash;
  final String? availableContentHash;
  final String? resolvedSourceRevision;
  final DateTime checkedAt;
}

final class UpdateCheckCacheSnapshot {
  UpdateCheckCacheSnapshot({
    required List<UpdateCheckRecord> records,
    this.lastFullSweepAt,
  }) : records = List.unmodifiable(records);

  final List<UpdateCheckRecord> records;
  final DateTime? lastFullSweepAt;
}

final class MutationReport {
  MutationReport({
    required this.snapshot,
    required Set<ManagedSkillId> affectedSkillIds,
  }) : affectedSkillIds = Set.unmodifiable(affectedSkillIds);

  final RepositorySnapshot snapshot;
  final Set<ManagedSkillId> affectedSkillIds;
}

final class OccupiedInstallTarget {
  OccupiedInstallTarget({
    required this.slotKey,
    required this.location,
    required this.targetPath,
    required List<String> agentIds,
    required this.kind,
    required this.contentRelation,
    this.existingDeclaredName,
    this.linkTarget,
  }) : agentIds = List.unmodifiable(agentIds);

  final String slotKey;
  final String location;
  final String targetPath;
  final List<String> agentIds;
  final ActivationTargetOccupancyKind kind;
  final ActivationContentRelation contentRelation;
  final String? existingDeclaredName;
  final String? linkTarget;
}

abstract interface class InstallTakeoverDraft {
  RepositoryRevision get reviewedRevision;
  List<OccupiedInstallTarget> get targets;
}

sealed class InstallAttempt {
  const InstallAttempt();
}

final class InstallCompleted extends InstallAttempt {
  const InstallCompleted(this.report);
  final MutationReport report;
}

final class InstallTakeoverRequired extends InstallAttempt {
  const InstallTakeoverRequired(this.draft);
  final InstallTakeoverDraft draft;
}

final class ExternalSkillCandidate {
  ExternalSkillCandidate({
    required this.slotKey,
    required this.declaredName,
    required this.description,
    required this.contentHash,
    required List<String> locations,
    required List<String> agentIds,
    List<String> destinationLocations = const <String>[],
  }) : locations = List.unmodifiable(locations),
       agentIds = List.unmodifiable(agentIds),
       destinationLocations = List.unmodifiable(destinationLocations);

  final String slotKey;
  final String declaredName;
  final String description;
  final String contentHash;
  final List<String> locations;
  final List<String> agentIds;
  final List<String> destinationLocations;
}

final class ExternalSkillConflict {
  ExternalSkillConflict({
    required this.slotKey,
    required Map<String, String> contentHashByLocation,
    List<String> destinationLocations = const <String>[],
    Map<String, List<String>> agentIdsByLocation =
        const <String, List<String>>{},
  }) : contentHashByLocation = Map.unmodifiable(contentHashByLocation),
       destinationLocations = List.unmodifiable(destinationLocations),
       agentIdsByLocation = Map.unmodifiable({
         for (final entry in agentIdsByLocation.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       });

  final String slotKey;
  final Map<String, String> contentHashByLocation;
  final List<String> destinationLocations;

  /// The Agents whose folder holds each conflicting copy, so a reviewer can
  /// choose by Agent rather than by path. A shared folder lists every Agent
  /// that reads it.
  final Map<String, List<String>> agentIdsByLocation;
}

/// The user-reviewed external occurrences to import as one managed Skill.
///
/// The location/hash map is a freshness precondition. The Workspace rescans
/// every location and reacquires the authoritative occurrence; it never trusts
/// caller-supplied content bytes.
final class ExternalAdoptionSelection {
  ExternalAdoptionSelection({
    required this.slotKey,
    required Map<String, String> reviewedContentHashByLocation,
    required this.authoritativeLocation,
  }) : reviewedContentHashByLocation = Map.unmodifiable(
         Map<String, String>.from(reviewedContentHashByLocation),
       ) {
    _requireNonEmpty(slotKey, 'slotKey');
    _requireAbsolutePath(authoritativeLocation, 'authoritativeLocation');
    if (this.reviewedContentHashByLocation.isEmpty) {
      throw ArgumentError.value(
        reviewedContentHashByLocation,
        'reviewedContentHashByLocation',
        'must not be empty',
      );
    }
    for (final entry in this.reviewedContentHashByLocation.entries) {
      _requireAbsolutePath(entry.key, 'reviewedContentHashByLocation key');
      _requireSha256(entry.value, 'reviewedContentHashByLocation value');
    }
    if (!this.reviewedContentHashByLocation.containsKey(
      authoritativeLocation,
    )) {
      throw ArgumentError.value(
        authoritativeLocation,
        'authoritativeLocation',
        'must be one reviewed location',
      );
    }
  }

  factory ExternalAdoptionSelection.fromCandidate(
    ExternalSkillCandidate candidate,
    String authoritativeLocation,
  ) {
    final reviewed = <String, String>{
      for (final location in candidate.locations)
        location: candidate.contentHash,
    };
    if (reviewed.length != candidate.locations.length) {
      throw ArgumentError.value(
        candidate.locations,
        'candidate.locations',
        'must not contain duplicate locations',
      );
    }
    return ExternalAdoptionSelection(
      slotKey: candidate.slotKey,
      reviewedContentHashByLocation: reviewed,
      authoritativeLocation: authoritativeLocation,
    );
  }

  factory ExternalAdoptionSelection.fromConflict(
    ExternalSkillConflict conflict,
    String authoritativeLocation,
  ) => ExternalAdoptionSelection(
    slotKey: conflict.slotKey,
    reviewedContentHashByLocation: conflict.contentHashByLocation,
    authoritativeLocation: authoritativeLocation,
  );

  final String slotKey;
  final Map<String, String> reviewedContentHashByLocation;
  final String authoritativeLocation;
}

final class ExternalSkillsDiscovery {
  ExternalSkillsDiscovery({
    required List<ExternalSkillCandidate> candidates,
    required List<ExternalSkillConflict> conflicts,
  }) : candidates = List.unmodifiable(candidates),
       conflicts = List.unmodifiable(conflicts);

  final List<ExternalSkillCandidate> candidates;
  final List<ExternalSkillConflict> conflicts;
}

final class ActivationTargetInfo {
  ActivationTargetInfo({
    required this.agentId,
    required this.displayName,
    required this.detected,
    required this.location,
    required this.scope,
    this.projectRootId,
    this.projectRootPath,
  });

  final String agentId;
  final String displayName;
  final bool detected;
  final String location;
  final ActivationScope scope;
  final String? projectRootId;
  final String? projectRootPath;
}

enum ActivationTargetOccupancyKind {
  skillDirectory,
  skillSymbolicLink,
  file,
  invalidDirectory,
  brokenSymbolicLink,
}

enum ActivationContentRelation {
  matchesCurrentRevision,
  differsFromCurrentRevision,
  indeterminate,
}

final class OccupiedActivationTarget {
  OccupiedActivationTarget({
    required this.managedSkillId,
    required this.location,
    required this.targetPath,
    required List<String> agentIds,
    required this.kind,
    required this.contentRelation,
    this.existingDeclaredName,
    this.linkTarget,
  }) : agentIds = List.unmodifiable(agentIds);

  final ManagedSkillId managedSkillId;
  final String location;
  final String targetPath;
  final List<String> agentIds;
  final ActivationTargetOccupancyKind kind;
  final ActivationContentRelation contentRelation;
  final String? existingDeclaredName;
  final String? linkTarget;
}

/// Opaque confirmation handle returned after inspecting occupied targets.
///
/// Callers may render the reviewed projection and pass the same instance back
/// to [ConfirmActivationTakeoverRequest]. The implementation additionally
/// retains the original target intent and private occupancy fingerprints so a
/// forged or stale confirmation can never authorize replacement.
abstract interface class ActivationTakeoverDraft {
  RepositoryRevision get reviewedRevision;
  List<OccupiedActivationTarget> get targets;
}

/// A reviewed external change to one published materialization.
final class SkillDriftArtifact {
  SkillDriftArtifact({
    required this.artifactId,
    required this.locationKind,
    required this.driftKind,
    this.targetPath,
    this.activationLocation,
    this.scope,
    this.projectRootId,
    List<String> agentIds = const [],
    this.fileCount,
    this.byteSize,
    required this.canKeepExternal,
    required this.canExport,
  }) : agentIds = List.unmodifiable(agentIds);

  final String artifactId;
  final SkillDriftLocationKind locationKind;
  final SkillDriftKind driftKind;

  /// Agent-visible target path; absent for the private Repository Copy.
  final String? targetPath;
  final String? activationLocation;
  final ActivationScope? scope;
  final String? projectRootId;
  final List<String> agentIds;
  final int? fileCount;
  final int? byteSize;
  final bool canKeepExternal;
  final bool canExport;
}

/// Opaque review handle returned by published-artifact drift inspection.
///
/// Pass the same instance back when exporting or resolving the reviewed change.
/// Private revision identity and filesystem fingerprints remain internal, and
/// implementations reject foreign or stale review handles.
abstract interface class SkillDriftReview {
  ManagedSkillId get managedSkillId;
  String get effectiveContentHash;
  List<SkillDriftArtifact> get artifacts;
  int get missingArtifactCount;
}

sealed class SkillDriftResolution {
  const SkillDriftResolution();
}

/// Publishes one reviewed artifact and rebuilds the other materializations.
final class KeepExternalSkillDrift extends SkillDriftResolution {
  const KeepExternalSkillDrift(this.artifactId);

  final String artifactId;
}

/// Rebuilds reviewed drifted and missing artifacts from the Effective Revision.
final class RestoreManagedSkillDrift extends SkillDriftResolution {
  const RestoreManagedSkillDrift();
}

final class SkillDriftExport {
  const SkillDriftExport({required this.exportedPath});

  final String exportedPath;
}

sealed class ActivationAttempt {
  const ActivationAttempt();
}

final class ActivationCompleted extends ActivationAttempt {
  const ActivationCompleted(this.report);
  final MutationReport report;
}

final class ActivationTakeoverRequired extends ActivationAttempt {
  const ActivationTakeoverRequired(this.draft);
  final ActivationTakeoverDraft draft;
}

final class AgentDetectionPath {
  AgentDetectionPath.absolute(this.path)
    : kind = AgentDetectionKind.pathExists,
      relativeToProject = false,
      dependencyName = null {
    _requireAbsolutePath(path, 'path');
  }

  AgentDetectionPath.projectRelative(this.path)
    : kind = AgentDetectionKind.pathExists,
      relativeToProject = true,
      dependencyName = null {
    _requireSafeRelativePath(path, 'path');
  }

  factory AgentDetectionPath.projectPackageDependency(String dependencyName) {
    _requireNonEmpty(dependencyName, 'dependencyName');
    return AgentDetectionPath._(
      kind: AgentDetectionKind.packageDependency,
      path: 'package.json',
      relativeToProject: true,
      dependencyName: dependencyName,
    );
  }

  const AgentDetectionPath._({
    required this.kind,
    required this.path,
    required this.relativeToProject,
    required this.dependencyName,
  });

  final AgentDetectionKind kind;
  final String path;
  final bool relativeToProject;
  final String? dependencyName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentDetectionPath &&
          kind == other.kind &&
          path == other.path &&
          relativeToProject == other.relativeToProject &&
          dependencyName == other.dependencyName;

  @override
  int get hashCode =>
      Object.hash(kind, path, relativeToProject, dependencyName);
}

final class AgentPlatformDefinition {
  AgentPlatformDefinition({
    this.globalSkillsPath,
    this.projectSkillsPath,
    List<String> globalDiscoverySkillsPaths = const <String>[],
    List<String> projectDiscoverySkillsPaths = const <String>[],
    List<AgentDetectionPath> detectionPaths = const [],
    this.requireAllDetectionPaths = false,
  }) : globalDiscoverySkillsPaths = List.unmodifiable(
         globalDiscoverySkillsPaths,
       ),
       projectDiscoverySkillsPaths = List.unmodifiable(
         projectDiscoverySkillsPaths,
       ),
       detectionPaths = List.unmodifiable(detectionPaths) {
    if (globalSkillsPath == null && projectSkillsPath == null) {
      throw ArgumentError('At least one Activation scope must be supported.');
    }
    if (globalSkillsPath != null) {
      _requireAbsolutePath(globalSkillsPath!, 'globalSkillsPath');
    }
    if (projectSkillsPath != null) {
      _requireSafeRelativePath(projectSkillsPath!, 'projectSkillsPath');
    }
    if (globalSkillsPath == null && globalDiscoverySkillsPaths.isNotEmpty) {
      throw ArgumentError(
        'Global discovery paths require a global Activation path.',
      );
    }
    if (projectSkillsPath == null && projectDiscoverySkillsPaths.isNotEmpty) {
      throw ArgumentError(
        'Project discovery paths require a project Activation path.',
      );
    }
    for (final discoveryPath in globalDiscoverySkillsPaths) {
      _requireAbsolutePath(discoveryPath, 'globalDiscoverySkillsPaths');
    }
    for (final discoveryPath in projectDiscoverySkillsPaths) {
      _requireSafeRelativePath(discoveryPath, 'projectDiscoverySkillsPaths');
    }
  }

  final String? globalSkillsPath;
  final String? projectSkillsPath;
  final List<String> globalDiscoverySkillsPaths;
  final List<String> projectDiscoverySkillsPaths;
  final List<AgentDetectionPath> detectionPaths;
  final bool requireAllDetectionPaths;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentPlatformDefinition &&
          globalSkillsPath == other.globalSkillsPath &&
          projectSkillsPath == other.projectSkillsPath &&
          listsEqual(
            globalDiscoverySkillsPaths,
            other.globalDiscoverySkillsPaths,
          ) &&
          listsEqual(
            projectDiscoverySkillsPaths,
            other.projectDiscoverySkillsPaths,
          ) &&
          listsEqual(detectionPaths, other.detectionPaths) &&
          requireAllDetectionPaths == other.requireAllDetectionPaths;

  @override
  int get hashCode => Object.hash(
    globalSkillsPath,
    projectSkillsPath,
    Object.hashAll(globalDiscoverySkillsPaths),
    Object.hashAll(projectDiscoverySkillsPaths),
    Object.hashAll(detectionPaths),
    requireAllDetectionPaths,
  );
}

/// Current-platform catalog metadata, independent of target path resolution.
final class AgentInfo {
  AgentInfo({
    required this.id,
    required this.displayName,
    required this.isBuiltIn,
    required Set<ActivationScope> supportedScopes,
    required this.detectedGlobally,
    required Set<String> detectedProjectRootIds,
  }) : supportedScopes = Set.unmodifiable(supportedScopes),
       detectedProjectRootIds = Set.unmodifiable(detectedProjectRootIds);

  final String id;
  final String displayName;
  final bool isBuiltIn;
  final Set<ActivationScope> supportedScopes;
  final bool detectedGlobally;
  final Set<String> detectedProjectRootIds;
}

final class AgentDefinition {
  AgentDefinition({
    required this.id,
    required this.displayName,
    required Map<DesktopPlatform, AgentPlatformDefinition> platforms,
  }) : platforms = Map.unmodifiable(platforms) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(displayName, 'displayName');
    if (platforms.isEmpty) {
      throw ArgumentError.value(platforms, 'platforms', 'must not be empty');
    }
  }

  final String id;
  final String displayName;
  final Map<DesktopPlatform, AgentPlatformDefinition> platforms;

  AgentPlatformDefinition? onPlatform(DesktopPlatform platform) =>
      platforms[platform];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentDefinition &&
          id == other.id &&
          displayName == other.displayName &&
          mapsEqual(platforms, other.platforms);

  @override
  int get hashCode => Object.hash(id, displayName, unorderedMapHash(platforms));
}

final class AgentRootOwnershipIssue {
  AgentRootOwnershipIssue({
    required this.rootPath,
    required Set<String> agentIds,
    Set<String> customAgentIds = const <String>{},
    required Set<AgentSkillRootRole> roles,
    required this.reason,
    required this.repairable,
  }) : agentIds = Set.unmodifiable(agentIds),
       customAgentIds = Set.unmodifiable(customAgentIds),
       roles = Set.unmodifiable(roles) {
    _requireNonEmpty(rootPath, 'rootPath');
    if (this.agentIds.isEmpty) {
      throw ArgumentError.value(agentIds, 'agentIds', 'must not be empty');
    }
    if (this.roles.isEmpty) {
      throw ArgumentError.value(roles, 'roles', 'must not be empty');
    }
    if (!this.agentIds.containsAll(this.customAgentIds)) {
      throw ArgumentError.value(
        customAgentIds,
        'customAgentIds',
        'must be a subset of agentIds',
      );
    }
  }

  final String rootPath;
  final Set<String> agentIds;
  final Set<String> customAgentIds;
  final Set<AgentSkillRootRole> roles;
  final AgentRootOwnershipIssueReason reason;
  final bool repairable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentRootOwnershipIssue &&
          rootPath == other.rootPath &&
          setsEqual(agentIds, other.agentIds) &&
          setsEqual(customAgentIds, other.customAgentIds) &&
          setsEqual(roles, other.roles) &&
          reason == other.reason &&
          repairable == other.repairable;

  @override
  int get hashCode => Object.hash(
    rootPath,
    unorderedSetHash(agentIds),
    unorderedSetHash(customAgentIds),
    unorderedSetHash(roles),
    reason,
    repairable,
  );
}

final class AgentRootOwnershipAudit {
  AgentRootOwnershipAudit({
    required this.supported,
    required this.examinedRootCount,
    required List<AgentRootOwnershipIssue> issues,
    this.currentUserId,
  }) : issues = List.unmodifiable(issues) {
    if (examinedRootCount < 0) {
      throw ArgumentError.value(
        examinedRootCount,
        'examinedRootCount',
        'must not be negative',
      );
    }
    if (supported != (currentUserId != null)) {
      throw ArgumentError(
        'A supported audit requires a current user ID and an unsupported '
        'audit must not expose one.',
      );
    }
  }

  final bool supported;
  final int? currentUserId;
  final int examinedRootCount;
  final List<AgentRootOwnershipIssue> issues;

  bool get isClean => supported && issues.isEmpty;
  List<AgentRootOwnershipIssue> get repairableIssues =>
      List.unmodifiable(issues.where((issue) => issue.repairable));
  List<AgentRootOwnershipIssue> get blockedIssues =>
      List.unmodifiable(issues.where((issue) => !issue.repairable));
}

final class OperationProgress {
  const OperationProgress({
    required this.operationId,
    required this.kind,
    required this.phase,
    this.currentItem,
    this.completed = 0,
    this.total,
  });

  final OperationId operationId;
  final WorkspaceOperationKind kind;
  final OperationProgressPhase phase;
  final String? currentItem;
  final int completed;
  final int? total;
}

final class OperationSubjectSummary {
  const OperationSubjectSummary({
    required this.reference,
    required this.managedSkillId,
    required this.displayName,
    this.beforeContentHash,
    this.afterContentHash,
  });

  final OperationSubjectReference reference;
  final ManagedSkillId managedSkillId;
  final String displayName;
  final String? beforeContentHash;
  final String? afterContentHash;
}

final class OperationHistoryEntry {
  OperationHistoryEntry({
    required this.operationId,
    required this.kind,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required List<OperationSubjectSummary> subjects,
  }) : subjects = List.unmodifiable(subjects);

  final OperationId operationId;
  final WorkspaceOperationKind kind;
  final OperationTerminalStatus status;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<OperationSubjectSummary> subjects;
}

final class OperationHistoryPage {
  OperationHistoryPage({
    required List<OperationHistoryEntry> entries,
    this.nextCursor,
  }) : entries = List.unmodifiable(entries);

  final List<OperationHistoryEntry> entries;
  final String? nextCursor;
}

final class PublishedRevisionSummary {
  const PublishedRevisionSummary({
    required this.reference,
    required this.managedSkillId,
    required this.kind,
    required this.publishedAt,
    required this.contentHash,
  });

  final OperationSubjectReference reference;
  final ManagedSkillId managedSkillId;
  final WorkspaceOperationKind kind;
  final DateTime publishedAt;
  final String contentHash;
}

final class PublishedHistoryPage {
  PublishedHistoryPage({
    required List<PublishedRevisionSummary> revisions,
    this.nextCursor,
  }) : revisions = List.unmodifiable(revisions);

  final List<PublishedRevisionSummary> revisions;
  final String? nextCursor;
}

final class DiffLine {
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final DiffLineKind kind;
  final String text;
  final int? oldLineNumber;
  final int? newLineNumber;
}

final class DiffHunk {
  DiffHunk({required this.header, required List<DiffLine> lines})
    : lines = List.unmodifiable(lines);

  final String header;
  final List<DiffLine> lines;
}

final class SkillFileDiff {
  SkillFileDiff({
    required this.path,
    required this.status,
    required this.isBinary,
    this.previousPath,
    required this.additions,
    required this.deletions,
    List<DiffHunk> hunks = const [],
  }) : hunks = List.unmodifiable(hunks);

  final String path;
  final String? previousPath;
  final DiffFileStatus status;
  final bool isBinary;
  final int additions;
  final int deletions;
  final List<DiffHunk> hunks;
}

final class SkillDiff {
  SkillDiff({
    required this.managedSkillId,
    this.from,
    required this.to,
    required List<SkillFileDiff> files,
  }) : files = List.unmodifiable(files);

  final ManagedSkillId managedSkillId;
  final OperationSubjectReference? from;
  final OperationSubjectReference to;
  final List<SkillFileDiff> files;
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requireNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}

void _requireSha256(String value, String name) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a lowercase SHA-256 digest',
    );
  }
}

void _requireAbsolutePath(String value, String name) {
  _requireNonEmpty(value, name);
  final isAbsolute =
      value.startsWith('/') ||
      value.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:\\').hasMatch(value);
  if (!isAbsolute) {
    throw ArgumentError.value(value, name, 'must be an absolute path');
  }
}

void _requireSafeRelativePath(String value, String name) {
  _requireNonEmpty(value, name);
  final parts = value.split(RegExp(r'[\\/]'));
  if (value.startsWith('/') ||
      value.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw ArgumentError.value(
      value,
      name,
      'must be a normalized relative path',
    );
  }
}

void _requireNonEmptyList(
  List<String> values,
  String name, {
  bool allowEmpty = false,
}) {
  if ((!allowEmpty && values.isEmpty) ||
      values.any((value) => value.trim().isEmpty)) {
    throw ArgumentError.value(values, name, 'must contain non-empty values');
  }
}

void _requireUnique(Iterable<Object> values, String name) {
  final seen = <Object>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw ArgumentError.value(value, name, 'contains a duplicate');
    }
  }
}
