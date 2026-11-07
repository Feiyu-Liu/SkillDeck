import 'package:skills_manager/shared/operations/app_operation_tracker.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

enum WorkspaceScope { global, project }

enum WorkspaceActivationMode { copy, symbolicLink }

/// How a new Activation should be materialized.
///
/// [automatic] links when the target can hold a link and copies otherwise.
/// An explicit method is strict: a link request fails rather than copying.
enum WorkspaceActivationMethod { automatic, copy, symbolicLink }

enum WorkspaceDriftLocationKind {
  repositoryCopy,
  copyActivation,
  symbolicLinkActivation,
}

enum WorkspaceDriftKind { contentChanged, wrongEntryType, wrongLinkTarget }

final class WorkspaceDriftedArtifact {
  WorkspaceDriftedArtifact({
    required this.artifactId,
    required this.locationKind,
    required this.driftKind,
    this.targetPath,
    this.scope,
    List<String> agentIds = const [],
    required this.canKeepExternal,
    required this.canExport,
  }) : agentIds = List.unmodifiable(agentIds);

  final String artifactId;
  final WorkspaceDriftLocationKind locationKind;
  final WorkspaceDriftKind driftKind;
  final String? targetPath;
  final WorkspaceScope? scope;
  final List<String> agentIds;
  final bool canKeepExternal;
  final bool canExport;
}

abstract interface class WorkspaceSkillDriftReview {
  WorkspaceSkillId get skillId;
  List<WorkspaceDriftedArtifact> get artifacts;
  int get missingArtifactCount;
}

sealed class WorkspaceDriftResolution {
  const WorkspaceDriftResolution();
  const factory WorkspaceDriftResolution.keepExternal(String artifactId) =
      WorkspaceKeepExternalSkillDrift;
  const factory WorkspaceDriftResolution.restoreManaged() =
      WorkspaceRestoreManagedSkillDrift;
}

final class WorkspaceKeepExternalSkillDrift extends WorkspaceDriftResolution {
  const WorkspaceKeepExternalSkillDrift(this.artifactId);
  final String artifactId;
}

final class WorkspaceRestoreManagedSkillDrift extends WorkspaceDriftResolution {
  const WorkspaceRestoreManagedSkillDrift();
}

final class WorkspaceSkillDriftExport {
  const WorkspaceSkillDriftExport({required this.exportedPath});
  final String exportedPath;
}

enum WorkspaceSourceKind { local, git, wellKnown, adoptedSnapshot }

enum WorkspaceUpdateStatus {
  current,
  updateAvailable,
  sourceUnavailable,
  updateUnsupported,
  resolutionRequired,
}

enum WorkspaceIntegrityStatus { healthy, recovered, corrupt }

enum WorkspaceSkillIntegrityStatus {
  healthy,
  recovered,
  unverified,
  validating,
  driftPending,
  repairFailed,
  revisionStoreCorrupt,
}

extension WorkspaceSkillIntegrityStatusX on WorkspaceSkillIntegrityStatus {
  bool get mutationBlocked => switch (this) {
    WorkspaceSkillIntegrityStatus.driftPending ||
    WorkspaceSkillIntegrityStatus.repairFailed ||
    WorkspaceSkillIntegrityStatus.revisionStoreCorrupt => true,
    _ => false,
  };
}

enum WorkspaceDraftPurpose { customization, updateCandidateResolution }

enum WorkspaceUpdateCandidateStatus { conflicted, validationFailed }

enum WorkspaceDesktopPlatform { macos, windows, linux }

enum WorkspaceAgentSkillRootRole { canonicalActivation, compatibilityDiscovery }

enum WorkspaceAgentRootOwnershipIssueReason {
  ownerMismatch,
  outsideUserHome,
  notDirectory,
  inspectionFailed,
}

final class WorkspaceAgentRootOwnershipIssue {
  WorkspaceAgentRootOwnershipIssue({
    required this.rootPath,
    required Set<String> agentIds,
    Set<String> customAgentIds = const <String>{},
    required Set<WorkspaceAgentSkillRootRole> roles,
    required this.reason,
    required this.repairable,
  }) : agentIds = Set.unmodifiable(agentIds),
       customAgentIds = Set.unmodifiable(customAgentIds),
       roles = Set.unmodifiable(roles);

  final String rootPath;
  final Set<String> agentIds;
  final Set<String> customAgentIds;
  final Set<WorkspaceAgentSkillRootRole> roles;
  final WorkspaceAgentRootOwnershipIssueReason reason;
  final bool repairable;

  bool get requiresCustomAgentConfirmation => customAgentIds.isNotEmpty;
}

final class WorkspaceAgentRootOwnershipAudit {
  WorkspaceAgentRootOwnershipAudit({
    required this.supported,
    required this.examinedRootCount,
    required List<WorkspaceAgentRootOwnershipIssue> issues,
    this.currentUserId,
  }) : issues = List.unmodifiable(issues);

  final bool supported;
  final int? currentUserId;
  final int examinedRootCount;
  final List<WorkspaceAgentRootOwnershipIssue> issues;

  bool get isClean => supported && issues.isEmpty;
  List<WorkspaceAgentRootOwnershipIssue> get repairableIssues =>
      List.unmodifiable(issues.where((issue) => issue.repairable));
  List<WorkspaceAgentRootOwnershipIssue> get blockedIssues =>
      List.unmodifiable(issues.where((issue) => !issue.repairable));
}

final class WorkspaceAgentPlatformDefinition {
  WorkspaceAgentPlatformDefinition({
    this.globalSkillsPath,
    this.projectSkillsPath,
    List<String> globalDiscoverySkillsPaths = const <String>[],
    List<String> projectDiscoverySkillsPaths = const <String>[],
  }) : globalDiscoverySkillsPaths = List.unmodifiable(
         globalDiscoverySkillsPaths,
       ),
       projectDiscoverySkillsPaths = List.unmodifiable(
         projectDiscoverySkillsPaths,
       );

  final String? globalSkillsPath;
  final String? projectSkillsPath;
  final List<String> globalDiscoverySkillsPaths;
  final List<String> projectDiscoverySkillsPaths;
}

final class WorkspaceAgentDefinition {
  WorkspaceAgentDefinition({
    required this.id,
    required this.displayName,
    required Map<WorkspaceDesktopPlatform, WorkspaceAgentPlatformDefinition>
    platforms,
  }) : platforms = Map.unmodifiable(platforms);

  final String id;
  final String displayName;
  final Map<WorkspaceDesktopPlatform, WorkspaceAgentPlatformDefinition>
  platforms;
}

enum WorkspaceOperationKind {
  open,
  refresh,
  resumeFinalizationRecovery,
  readDocument,
  inspectSource,
  inspectActivationTargets,
  inspectAgents,
  inspectAgentRootOwnership,
  discoverExternalSkills,
  install,
  confirmInstallTakeover,
  adopt,
  replaceSource,
  activate,
  confirmActivationTakeover,
  deactivate,
  remove,
  checkUpdates,
  update,
  registerProjectRoot,
  unregisterProjectRoot,
  close,
  reconfigureAgentCatalog,
  setFavorite,
  saveNote,
  deleteNote,
  createPersonalTag,
  updatePersonalTag,
  deletePersonalTag,
  assignPersonalTag,
  unassignPersonalTag,
  abandonUpdateCandidate,
  validateWorkspace,
  inspectSkillDrift,
  exportSkillDriftArtifact,
  resolveSkillDrift,
}

enum WorkspaceOperationPhase {
  queued,
  preparing,
  inspecting,
  waitingForLock,
  planning,
  applying,
  committing,
  finalizing,
  recovering,
  rollingBack,
  succeeded,
  failed,
  cancelled;

  bool get isTerminal =>
      this == WorkspaceOperationPhase.succeeded ||
      this == WorkspaceOperationPhase.failed ||
      this == WorkspaceOperationPhase.cancelled;
}

/// App-owned identity for a managed Skill.
///
/// It deliberately has no knowledge of the backend's identifier type. The
/// package adapter is the only boundary that encodes or decodes that value.
final class WorkspaceSkillId {
  WorkspaceSkillId(String value) : value = _requireWorkspaceSkillId(value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceSkillId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'WorkspaceSkillId($value)';
}

String _requireWorkspaceSkillId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.contains('/') ||
      normalized.contains('\\')) {
    throw ArgumentError.value(value, 'value', 'must be a non-empty opaque ID');
  }
  return normalized;
}

/// Host Git capability as reported by Skill Workspace.
///
/// Mirrors the package enum at the anti-corruption seam. "Not yet checked" is
/// intentionally absent: that is presentation state, and conflating it with a
/// result would let an unprobed default read as an answer.
enum WorkspaceGitEnvironmentStatus {
  available,
  notInstalled,
  developerToolsRequired,
  developerToolsInstalling,
  probeFailed,
}

enum WorkspaceErrorCode {
  sourceUnavailable,
  sourceAuthenticationRequired,
  gitUnavailable,
  gitFailed,
  developerToolsRequired,
  transportRejected,
  httpFailure,
  digestMismatch,
  archiveInvalid,
  skillNotFound,
  staleSnapshot,
  staleInstallTakeover,
  staleActivationTakeover,
  invalidSkill,
  unsupportedSkillName,
  skillContentLimitExceeded,
  duplicateSkillSlot,
  sourceReplacementRequired,
  updateUnsupported,
  externalConflict,
  activationUnavailable,
  activationUnsupported,
  projectRootNotFound,
  invalidProjectRoot,
  projectRootConflict,
  agentNotFound,
  duplicateAgentId,
  agentRootOwnership,
  personalTagNotFound,
  duplicatePersonalTag,
  repositoryBusy,
  operationCancelled,
  unsupportedStateVersion,
  unsupportedJournalVersion,
  stateCorrupt,
  journalCorrupt,
  journalMaintenanceFailed,
  migrationFailed,
  controlPlaneCorrupt,
  revisionStoreCorrupt,
  invalidEffectiveFilePath,
  effectiveFileNotFound,
  finalizationRecoveryFailed,
  dirtyDraftResolutionRequired,
  updateCandidateResolutionRequired,
  draftChangedDuringPublish,
  declaredNameChangeNotAllowed,
  historicalNameMismatch,
  rollbackFailed,
  recoveryFailed,
  ioFailure,
  operationFailed,
  repositoryNotOpen,
  documentUnavailable,
  invalidSource,
  staleDriftReview,
  driftResolutionUnavailable,
}

enum WorkspaceWarningCode {
  internalSymlinkSkipped,
  sourceEntrySkipped,
  noActivationTarget,
  projectSymbolicLinkPortability,
  duplicateExposure,
  agentUndetected,
  activationTargetSkipped,
  recoveryCleanupDeferred,
  draftPreservedAfterPublish,
  finalizationDeferred,
  sharedActivationLocation,
}

final class WorkspaceWarning implements AppWarning {
  WorkspaceWarning({
    required this.code,
    Map<String, Object?> context = const {},
  }) : context = Map.unmodifiable(context);

  final WorkspaceWarningCode code;

  @override
  String get codeKey => code.name;

  @override
  final Map<String, Object?> context;
}

class WorkspaceFailure implements AppFailure {
  WorkspaceFailure({
    required this.code,
    required this.operation,
    Map<String, Object?> context = const {},
    this.diagnostic,
    List<WorkspaceWarning> warnings = const [],
  }) : context = Map.unmodifiable(context),
       warnings = List.unmodifiable(warnings);

  final WorkspaceErrorCode code;
  final WorkspaceOperationKind operation;

  @override
  final String? diagnostic;

  @override
  String get codeKey => code.name;

  @override
  String get operationKey => operation.name;

  @override
  AppFailureMessage get message => switch (code) {
    WorkspaceErrorCode.sourceUnavailable ||
    WorkspaceErrorCode.httpFailure => AppFailureMessage.sourceUnavailable,
    WorkspaceErrorCode.sourceAuthenticationRequired =>
      AppFailureMessage.authenticationRequired,
    WorkspaceErrorCode.gitUnavailable ||
    WorkspaceErrorCode.gitFailed => AppFailureMessage.gitUnavailable,
    // Kept apart from gitUnavailable so the acquisition flow can offer setup
    // guidance instead of a retry that cannot succeed.
    WorkspaceErrorCode.developerToolsRequired =>
      AppFailureMessage.developerToolsRequired,
    WorkspaceErrorCode.transportRejected => AppFailureMessage.transportRejected,
    WorkspaceErrorCode.digestMismatch ||
    WorkspaceErrorCode.archiveInvalid => AppFailureMessage.archiveInvalid,
    WorkspaceErrorCode.skillNotFound => AppFailureMessage.skillNotFound,
    WorkspaceErrorCode.documentUnavailable ||
    WorkspaceErrorCode.invalidEffectiveFilePath ||
    WorkspaceErrorCode.effectiveFileNotFound => AppFailureMessage.documentRead,
    WorkspaceErrorCode.staleSnapshot ||
    WorkspaceErrorCode.staleDriftReview ||
    WorkspaceErrorCode.staleInstallTakeover ||
    WorkspaceErrorCode.staleActivationTakeover =>
      AppFailureMessage.staleSnapshot,
    WorkspaceErrorCode.invalidSkill ||
    WorkspaceErrorCode.unsupportedSkillName ||
    WorkspaceErrorCode.skillContentLimitExceeded ||
    WorkspaceErrorCode.invalidSource ||
    WorkspaceErrorCode.personalTagNotFound ||
    WorkspaceErrorCode.duplicatePersonalTag => AppFailureMessage.invalidSkill,
    WorkspaceErrorCode.dirtyDraftResolutionRequired ||
    WorkspaceErrorCode.draftChangedDuringPublish =>
      AppFailureMessage.dirtyDraftResolutionRequired,
    WorkspaceErrorCode.updateCandidateResolutionRequired =>
      AppFailureMessage.updateCandidateResolutionRequired,
    WorkspaceErrorCode.declaredNameChangeNotAllowed ||
    WorkspaceErrorCode.historicalNameMismatch =>
      AppFailureMessage.nameChangeNotAllowed,
    WorkspaceErrorCode.duplicateSkillSlot ||
    WorkspaceErrorCode.sourceReplacementRequired =>
      AppFailureMessage.duplicateSkill,
    WorkspaceErrorCode.externalConflict =>
      AppFailureMessage.externalSkillConflict,
    WorkspaceErrorCode.updateUnsupported => AppFailureMessage.updateUnsupported,
    WorkspaceErrorCode.activationUnavailable ||
    WorkspaceErrorCode.activationUnsupported => AppFailureMessage.activation,
    WorkspaceErrorCode.projectRootNotFound ||
    WorkspaceErrorCode.invalidProjectRoot ||
    WorkspaceErrorCode.projectRootConflict => AppFailureMessage.projectRoot,
    WorkspaceErrorCode.agentNotFound ||
    WorkspaceErrorCode.duplicateAgentId => AppFailureMessage.agent,
    WorkspaceErrorCode.agentRootOwnership =>
      AppFailureMessage.agentRootOwnership,
    WorkspaceErrorCode.repositoryBusy => AppFailureMessage.repositoryBusy,
    WorkspaceErrorCode.operationCancelled =>
      AppFailureMessage.operationCancelled,
    WorkspaceErrorCode.repositoryNotOpen => AppFailureMessage.repositoryState,
    WorkspaceErrorCode.unsupportedStateVersion ||
    WorkspaceErrorCode.unsupportedJournalVersion ||
    WorkspaceErrorCode.stateCorrupt ||
    WorkspaceErrorCode.journalCorrupt ||
    WorkspaceErrorCode.journalMaintenanceFailed ||
    WorkspaceErrorCode.controlPlaneCorrupt =>
      AppFailureMessage.controlPlaneCorrupt,
    WorkspaceErrorCode.migrationFailed => AppFailureMessage.migrationFailed,
    WorkspaceErrorCode.revisionStoreCorrupt =>
      AppFailureMessage.revisionStoreCorrupt,
    WorkspaceErrorCode.driftResolutionUnavailable =>
      AppFailureMessage.driftResolutionUnavailable,
    WorkspaceErrorCode.finalizationRecoveryFailed =>
      AppFailureMessage.finalizationRecoveryFailed,
    WorkspaceErrorCode.rollbackFailed ||
    WorkspaceErrorCode.recoveryFailed => AppFailureMessage.rollback,
    WorkspaceErrorCode.ioFailure => AppFailureMessage.io,
    WorkspaceErrorCode.operationFailed => AppFailureMessage.unexpected,
  };

  @override
  AppRecoveryPolicy get recoveryPolicy => switch (code) {
    // A blocked folder stays blocked until the user changes it, so the page
    // offers to check again rather than to repeat the operation.
    WorkspaceErrorCode.agentRootOwnership
        when context['reason'] == 'agentRootOwnershipBlocked' =>
      AppRecoveryPolicy.refreshThenReview,
    WorkspaceErrorCode.staleSnapshot ||
    WorkspaceErrorCode.staleDriftReview ||
    WorkspaceErrorCode.staleInstallTakeover ||
    WorkspaceErrorCode.staleActivationTakeover ||
    WorkspaceErrorCode.externalConflict => AppRecoveryPolicy.refreshThenReview,
    WorkspaceErrorCode.skillNotFound ||
    WorkspaceErrorCode.documentUnavailable => AppRecoveryPolicy.refresh,
    WorkspaceErrorCode.repositoryBusy ||
    WorkspaceErrorCode.sourceUnavailable ||
    WorkspaceErrorCode.sourceAuthenticationRequired ||
    WorkspaceErrorCode.gitUnavailable ||
    WorkspaceErrorCode.gitFailed ||
    WorkspaceErrorCode.httpFailure ||
    WorkspaceErrorCode.operationCancelled ||
    WorkspaceErrorCode.agentRootOwnership ||
    WorkspaceErrorCode.finalizationRecoveryFailed =>
      AppRecoveryPolicy.retryExplicitly,
    // Explicit rather than left to the wildcard: retrying reruns the same
    // command, and recovery is an operating-system install done elsewhere.
    WorkspaceErrorCode.developerToolsRequired => AppRecoveryPolicy.none,
    _ => AppRecoveryPolicy.none,
  };

  @override
  final Map<String, Object?> context;

  @override
  final List<WorkspaceWarning> warnings;

  @override
  String toString() => 'WorkspaceFailure($operation, $code)';
}

/// Expected failure used by the few App APIs that are inherently Future-based,
/// such as opening the repository or decoding a selected document.
///
/// Workspace operations themselves carry [WorkspaceFailure] through
/// [WorkspaceFailed] and do not use exception control flow.
final class WorkspaceException extends WorkspaceFailure implements Exception {
  WorkspaceException({
    required super.code,
    required super.operation,
    super.context,
    super.diagnostic,
    super.warnings,
  });
}

final class SkillProjectRoot {
  const SkillProjectRoot({required this.id, required this.path});

  final String id;
  final String path;
}

final class SkillSourceProvenance {
  const SkillSourceProvenance({
    required this.kind,
    required this.locator,
    this.ref,
    this.repositorySubpath = '',
    this.skillPath = '',
  });

  final WorkspaceSourceKind kind;
  final String locator;
  final String? ref;
  final String repositorySubpath;
  final String skillPath;
}

final class SkillRevision {
  const SkillRevision({
    required this.contentHash,
    required this.fileCount,
    required this.byteSize,
    required this.acquiredAt,
    this.resolvedSourceRevision,
  });

  final String contentHash;
  final int fileCount;
  final int byteSize;
  final DateTime acquiredAt;
  final String? resolvedSourceRevision;
}

final class WorkspacePersonalTag {
  const WorkspacePersonalTag({
    required this.id,
    required this.name,
    this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? color;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class WorkspaceDraftSummary {
  const WorkspaceDraftSummary({
    required this.purpose,
    required this.path,
    required this.isDirty,
    required this.updatedAt,
  });

  final WorkspaceDraftPurpose purpose;
  final String path;
  final bool isDirty;
  final DateTime updatedAt;
}

final class WorkspaceUpdateCandidateSummary {
  WorkspaceUpdateCandidateSummary({
    required this.status,
    required List<String> conflictPaths,
    this.validationCode,
    required this.createdAt,
  }) : conflictPaths = List.unmodifiable(conflictPaths);

  final WorkspaceUpdateCandidateStatus status;
  final List<String> conflictPaths;
  final String? validationCode;
  final DateTime createdAt;
}

final class SkillActivationLocation {
  SkillActivationLocation({
    required this.location,
    required this.scope,
    required this.mode,
    required List<String> agentIds,
    this.projectRootId,
    this.projectRootPath,
  }) : agentIds = List.unmodifiable(agentIds);

  final String location;
  final WorkspaceScope scope;
  final WorkspaceActivationMode mode;
  final List<String> agentIds;
  final String? projectRootId;
  final String? projectRootPath;
}

final class WorkspaceSkill {
  WorkspaceSkill({
    required this.id,
    required this.slotKey,
    required this.declaredName,
    required this.displayName,
    required this.description,
    required this.source,
    required this.currentRevision,
    required List<SkillActivationLocation> activations,
    this.isFavorite = false,
    this.note,
    List<String> personalTagIds = const [],
    this.integrity = WorkspaceSkillIntegrityStatus.healthy,
    this.draft,
    this.updateCandidate,
  }) : activations = List.unmodifiable(activations),
       personalTagIds = List.unmodifiable(personalTagIds);

  final WorkspaceSkillId id;
  final String slotKey;
  final String declaredName;
  final String displayName;
  final String description;
  final SkillSourceProvenance source;
  final SkillRevision currentRevision;
  final List<SkillActivationLocation> activations;
  final bool isFavorite;
  final String? note;
  final List<String> personalTagIds;
  final WorkspaceSkillIntegrityStatus integrity;
  final WorkspaceDraftSummary? draft;
  final WorkspaceUpdateCandidateSummary? updateCandidate;

  int get activationCount => activations.length;

  WorkspaceSkill copyWith({
    String? slotKey,
    bool? isFavorite,
    Object? note = _workspaceUnset,
    List<String>? personalTagIds,
    Object? updateCandidate = _workspaceUnset,
  }) => WorkspaceSkill(
    id: id,
    slotKey: slotKey ?? this.slotKey,
    declaredName: declaredName,
    displayName: displayName,
    description: description,
    source: source,
    currentRevision: currentRevision,
    activations: activations,
    isFavorite: isFavorite ?? this.isFavorite,
    note: identical(note, _workspaceUnset) ? this.note : note as String?,
    personalTagIds: personalTagIds ?? this.personalTagIds,
    integrity: integrity,
    draft: draft,
    updateCandidate: identical(updateCandidate, _workspaceUnset)
        ? this.updateCandidate
        : updateCandidate as WorkspaceUpdateCandidateSummary?,
  );
}

final class WorkspaceValidationReport {
  WorkspaceValidationReport({
    required this.checkedSkillCount,
    required this.repairedArtifactCount,
    required this.healthySkillCount,
    required List<WorkspaceSkillId> repairedSkillIds,
    required List<WorkspaceSkillId> driftedSkillIds,
    required List<WorkspaceSkillId> failedSkillIds,
  }) : repairedSkillIds = List.unmodifiable(repairedSkillIds),
       driftedSkillIds = List.unmodifiable(driftedSkillIds),
       failedSkillIds = List.unmodifiable(failedSkillIds);

  final int checkedSkillCount;
  final int repairedArtifactCount;
  final int healthySkillCount;
  final List<WorkspaceSkillId> repairedSkillIds;
  final List<WorkspaceSkillId> driftedSkillIds;
  final List<WorkspaceSkillId> failedSkillIds;
}

const _workspaceUnset = Object();

final class SkillsWorkspaceSnapshot {
  SkillsWorkspaceSnapshot({
    required this.revision,
    required List<SkillProjectRoot> projectRoots,
    required List<WorkspaceSkill> skills,
    List<WorkspacePersonalTag> personalTags = const [],
    this.integrity = WorkspaceIntegrityStatus.healthy,
  }) : projectRoots = List.unmodifiable(projectRoots),
       skills = List.unmodifiable(skills),
       personalTags = List.unmodifiable(personalTags);

  factory SkillsWorkspaceSnapshot.empty() => SkillsWorkspaceSnapshot(
    revision: 0,
    projectRoots: const [],
    skills: const [],
  );

  final int revision;
  final List<SkillProjectRoot> projectRoots;
  final List<WorkspaceSkill> skills;
  final List<WorkspacePersonalTag> personalTags;
  final WorkspaceIntegrityStatus integrity;

  WorkspaceSkill? findSkillById(WorkspaceSkillId id) {
    for (final skill in skills) {
      if (skill.id == id) return skill;
    }
    return null;
  }

  WorkspaceSkill? findSkillBySlotKey(String slotKey) {
    for (final skill in skills) {
      if (skill.slotKey == slotKey) return skill;
    }
    return null;
  }

  WorkspacePersonalTag? findPersonalTag(String id) {
    for (final tag in personalTags) {
      if (tag.id == id) return tag;
    }
    return null;
  }
}

final class SkillSourceInput {
  const SkillSourceInput({
    required this.kind,
    required this.locator,
    this.ref,
    this.repositorySubpath = '',
    this.skillPath = '',
  });

  final WorkspaceSourceKind kind;
  final String locator;
  final String? ref;
  final String repositorySubpath;

  /// Selects one Skill when the Source exposes several.
  ///
  /// Inspection candidates report the value that selects them, so carrying a
  /// candidate's `skillPath` back into a request narrows the Source to that
  /// Skill alone — which Source Replacement requires, since it has no
  /// selection field of its own.
  final String skillPath;
}

final class WorkspaceSourceCandidate {
  const WorkspaceSourceCandidate({
    required this.declaredName,
    required this.description,
    required this.slotKey,
    required this.skillPath,
    required this.contentHash,
    required this.fileCount,
    required this.byteSize,
  });

  final String declaredName;
  final String description;
  final String slotKey;
  final String skillPath;
  final String contentHash;
  final int fileCount;
  final int byteSize;
}

final class WorkspaceSourceInspection {
  WorkspaceSourceInspection({
    required this.source,
    required List<WorkspaceSourceCandidate> candidates,
  }) : candidates = List.unmodifiable(candidates);

  final SkillSourceInput source;
  final List<WorkspaceSourceCandidate> candidates;
}

final class WorkspaceAgentInfo {
  WorkspaceAgentInfo({
    required this.id,
    required this.displayName,
    required this.isBuiltIn,
    required Set<WorkspaceScope> supportedScopes,
    required this.detectedGlobally,
    required Set<String> detectedProjectRootIds,
  }) : supportedScopes = Set.unmodifiable(supportedScopes),
       detectedProjectRootIds = Set.unmodifiable(detectedProjectRootIds);

  final String id;
  final String displayName;
  final bool isBuiltIn;
  final Set<WorkspaceScope> supportedScopes;
  final bool detectedGlobally;
  final Set<String> detectedProjectRootIds;
  bool get detected => detectedGlobally || detectedProjectRootIds.isNotEmpty;
}

final class WorkspaceActivationTarget {
  const WorkspaceActivationTarget({
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
  final WorkspaceScope scope;
  final String? projectRootId;
  final String? projectRootPath;
}

final class WorkspaceInstallRequest {
  WorkspaceInstallRequest({
    required this.source,
    Set<String>? skillNames,
    required this.scope,
    this.projectRootId,
    Set<String> agentIds = const {},
    this.storeOnly = false,
    this.activationMethod = WorkspaceActivationMethod.automatic,
  }) : skillNames = skillNames == null ? null : Set.unmodifiable(skillNames),
       agentIds = Set.unmodifiable(agentIds);

  final SkillSourceInput source;
  final Set<String>? skillNames;
  final WorkspaceScope scope;
  final String? projectRootId;
  final Set<String> agentIds;
  final bool storeOnly;
  final WorkspaceActivationMethod activationMethod;
}

final class WorkspaceMutationReceipt {
  WorkspaceMutationReceipt({
    required this.snapshot,
    Set<WorkspaceSkillId> affectedSkillIds = const {},
  }) : affectedSkillIds = Set.unmodifiable(affectedSkillIds);

  final SkillsWorkspaceSnapshot snapshot;
  final Set<WorkspaceSkillId> affectedSkillIds;
}

abstract interface class WorkspaceInstallTakeoverDraft {
  int get expectedRevision;
  List<WorkspaceOccupiedActivationTarget> get targets;
}

sealed class WorkspaceInstallAttempt {
  const WorkspaceInstallAttempt();
}

final class WorkspaceInstallCompleted extends WorkspaceInstallAttempt {
  const WorkspaceInstallCompleted(this.receipt);
  final WorkspaceMutationReceipt receipt;
}

final class WorkspaceInstallTakeoverRequired extends WorkspaceInstallAttempt {
  const WorkspaceInstallTakeoverRequired(this.draft);
  final WorkspaceInstallTakeoverDraft draft;
}

enum WorkspaceActivationTargetOccupancyKind {
  skillDirectory,
  skillSymbolicLink,
  file,
  invalidDirectory,
  brokenSymbolicLink,
}

enum WorkspaceActivationContentRelation {
  matchesCurrentRevision,
  differsFromCurrentRevision,
  indeterminate,
}

final class WorkspaceOccupiedActivationTarget {
  WorkspaceOccupiedActivationTarget({
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
  final WorkspaceActivationTargetOccupancyKind kind;
  final WorkspaceActivationContentRelation contentRelation;
  final String? existingDeclaredName;
  final String? linkTarget;
}

abstract interface class WorkspaceActivationTakeoverDraft {
  int get expectedRevision;

  List<WorkspaceOccupiedActivationTarget> get targets;
}

sealed class WorkspaceActivationAttempt {
  const WorkspaceActivationAttempt();
}

final class WorkspaceActivationCompleted extends WorkspaceActivationAttempt {
  const WorkspaceActivationCompleted(this.receipt);

  final WorkspaceMutationReceipt receipt;
}

final class WorkspaceActivationTakeoverRequired
    extends WorkspaceActivationAttempt {
  const WorkspaceActivationTakeoverRequired(this.draft);

  final WorkspaceActivationTakeoverDraft draft;
}

final class WorkspaceUpdateReport {
  const WorkspaceUpdateReport({
    required this.skillId,
    required this.status,
    this.currentContentHash,
    this.availableContentHash,
    this.resolvedSourceRevision,
    this.failureReason,
  });

  final WorkspaceSkillId skillId;
  final WorkspaceUpdateStatus status;
  final String? currentContentHash;
  final String? availableContentHash;
  final String? resolvedSourceRevision;
  final WorkspaceUpdateCheckFailureReason? failureReason;
}

enum WorkspaceUpdateCheckFailureReason {
  sourceUnavailable,
  authenticationRequired,
  gitUnavailable,
  developerToolsRequired,
  timedOut,
  gitFailed,
  ioFailure,
}

final class WorkspaceUpdateCacheRecord {
  const WorkspaceUpdateCacheRecord({
    required this.skillId,
    required this.basisFingerprint,
    required this.report,
    required this.checkedAt,
  });

  final WorkspaceSkillId skillId;
  final String basisFingerprint;
  final WorkspaceUpdateReport report;
  final DateTime checkedAt;
}

final class WorkspaceUpdateCacheSnapshot {
  WorkspaceUpdateCacheSnapshot({
    required List<WorkspaceUpdateCacheRecord> records,
    this.lastFullSweepAt,
  }) : records = List.unmodifiable(records);

  final List<WorkspaceUpdateCacheRecord> records;
  final DateTime? lastFullSweepAt;
}

final class WorkspaceOperationProgress {
  WorkspaceOperationProgress({
    required this.operationId,
    required this.kind,
    required this.phase,
    this.currentItem,
    this.completed = 0,
    this.total,
    List<WorkspaceWarning> warnings = const [],
  }) : warnings = List.unmodifiable(warnings);

  final String operationId;
  final WorkspaceOperationKind kind;
  final WorkspaceOperationPhase phase;
  final String? currentItem;
  final int completed;
  final int? total;
  final List<WorkspaceWarning> warnings;

  double? get fraction =>
      total == null || total == 0 ? null : completed / total!;
}

sealed class WorkspaceCompletion<T> {
  const WorkspaceCompletion({this.warnings = const []});

  final List<WorkspaceWarning> warnings;
}

final class WorkspaceCompleted<T> extends WorkspaceCompletion<T> {
  WorkspaceCompleted({
    required this.value,
    List<WorkspaceWarning> warnings = const [],
  }) : super(warnings: List.unmodifiable(warnings));

  final T value;
}

final class WorkspaceCommittedPending<T> extends WorkspaceCompletion<T> {
  WorkspaceCommittedPending({
    required this.operationId,
    required this.committedRevision,
    List<WorkspaceWarning> warnings = const [],
  }) : super(warnings: List.unmodifiable(warnings));

  final String operationId;
  final int committedRevision;
}

final class WorkspaceFailed<T> extends WorkspaceCompletion<T> {
  WorkspaceFailed({
    required this.failure,
    List<WorkspaceWarning> warnings = const [],
  }) : super(warnings: List.unmodifiable(warnings));

  final WorkspaceFailure failure;
}

final class WorkspaceTask<T> {
  const WorkspaceTask({
    required this.current,
    required this.states,
    required this.completed,
    required this.cancel,
  });

  final WorkspaceOperationProgress current;
  final Stream<WorkspaceOperationProgress> states;
  final Future<WorkspaceCompletion<T>> completed;
  final Future<void> Function() cancel;
}

typedef WorkspaceOperationState =
    AppOperationState<WorkspaceOperationProgress, WorkspaceWarning>;

typedef WorkspaceOperationTracker =
    AppOperationTracker<WorkspaceOperationProgress, WorkspaceWarning>;

extension WorkspaceTaskTracking<T> on WorkspaceTask<T> {
  Future<WorkspaceCompletion<T>> trackedCompletionBy(
    WorkspaceOperationTracker tracker,
  ) => tracker.runCompletion(
    current: current,
    states: states,
    completed: completed,
    warningsOfCompletion: (completion) => completion.warnings,
    cancel: cancel,
  );
}

Object workspaceWarningKey(WorkspaceWarning warning) =>
    '${warning.code.name}:${warning.context}';
