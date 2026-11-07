import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

abstract interface class SkillsUpdateCheckStore {
  Future<WorkspaceUpdateCacheSnapshot> readUpdateCache();

  Future<void> upsertUpdateCache(WorkspaceUpdateCacheRecord record);

  Future<void> removeUpdateCache(WorkspaceSkillId skillId);

  Future<void> writeLastFullUpdateSweepAt(DateTime value);
}

/// App-owned data boundary for the local Skill Workspace.
///
/// Implementations translate between the bounded-context package and App
/// domain values. Presentation code never imports package identities, storage
/// paths, or backend-specific result types.
abstract interface class SkillsWorkspaceRepository {
  WorkspaceTask<WorkspaceSkillDriftReview> inspectSkillDrift(
    WorkspaceSkillId skillId,
  );

  WorkspaceTask<WorkspaceSkillDriftExport> exportSkillDriftArtifact({
    required WorkspaceSkillDriftReview review,
    required String artifactId,
    required String destinationDirectory,
  });

  WorkspaceTask<WorkspaceMutationReceipt> resolveSkillDrift({
    required WorkspaceSkillDriftReview review,
    required WorkspaceDriftResolution resolution,
  });

  SkillsWorkspaceSnapshot? get current;

  Stream<SkillsWorkspaceSnapshot> get snapshots;

  /// Opens the Workspace and reports expected failures as a typed completion.
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> open();

  /// Refreshes the authoritative Snapshot without using exceptions for expected
  /// backend failures.
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> refresh();

  WorkspaceTask<WorkspaceValidationReport> validateWorkspace({
    Set<WorkspaceSkillId>? skillIds,
  });

  /// Resumes durable post-commit recovery without exposing Journal details.
  WorkspaceTask<SkillsWorkspaceSnapshot> resumeFinalizationRecovery();

  /// Lists App-readable documents from the current Effective Revision.
  Future<WorkspaceCompletion<List<SkillDocumentEntry>>> listSkillDocuments(
    WorkspaceSkillId skillId,
  );

  /// Reads a UTF-8 App document from the current Effective Revision.
  Future<WorkspaceCompletion<String>> readSkillDocument(
    WorkspaceSkillId skillId,
    String relativePath, {
    required String expectedContentHash,
  });

  WorkspaceTask<WorkspaceSourceInspection> inspectSource(
    SkillSourceInput source,
  );

  /// Reports whether the host can run system Git.
  ///
  /// A plain Future rather than a [WorkspaceTask]: the check always completes
  /// with a classification, so there is no operation to track or cancel. Call
  /// it only from an explicit user action — on macOS without the developer
  /// command line tools the probe itself raises the system install dialog.
  Future<WorkspaceGitEnvironmentStatus> probeGitEnvironment();

  WorkspaceTask<List<WorkspaceAgentInfo>> inspectAgents();

  WorkspaceTask<List<WorkspaceActivationTarget>> inspectActivationTargets({
    required WorkspaceScope scope,
    String? projectRootId,
  });

  WorkspaceTask<WorkspaceAgentRootOwnershipAudit> inspectAgentRootOwnership();

  WorkspaceTask<ExternalSkillsDiscovery> discoverExternalSkills();

  WorkspaceTask<WorkspaceInstallAttempt> install(
    WorkspaceInstallRequest request,
  );

  WorkspaceTask<WorkspaceMutationReceipt> confirmInstallTakeover(
    WorkspaceInstallTakeoverDraft draft,
  );

  WorkspaceTask<WorkspaceMutationReceipt> adopt(
    ExternalSkillAdoptionRequest request,
  );

  WorkspaceTask<WorkspaceMutationReceipt> replaceSource({
    required WorkspaceSkillId skillId,
    required SkillSourceInput source,
    required int expectedRevision,
  });

  WorkspaceTask<WorkspaceActivationAttempt> activate({
    required Set<WorkspaceSkillId> skillIds,
    required WorkspaceScope scope,
    required Set<String> agentIds,
    String? projectRootId,
    WorkspaceActivationMethod activationMethod =
        WorkspaceActivationMethod.automatic,
  });

  WorkspaceTask<WorkspaceMutationReceipt> confirmActivationTakeover(
    WorkspaceActivationTakeoverDraft draft,
  );

  WorkspaceTask<WorkspaceMutationReceipt> deactivate({
    required Set<WorkspaceSkillId> skillIds,
    Set<String>? locations,
  });

  WorkspaceTask<WorkspaceMutationReceipt> remove({
    required Set<WorkspaceSkillId> skillIds,
    required int expectedRevision,
  });

  WorkspaceTask<List<WorkspaceUpdateReport>> checkUpdates({
    Set<WorkspaceSkillId>? skillIds,
  });

  WorkspaceTask<WorkspaceMutationReceipt> update({
    Set<WorkspaceSkillId>? skillIds,
  });

  WorkspaceTask<WorkspaceMutationReceipt> registerProjectRoot({
    required String path,
    String? id,
  });

  WorkspaceTask<WorkspaceMutationReceipt> unregisterProjectRoot(String id);

  WorkspaceTask<SkillsWorkspaceSnapshot> reconfigureAgentCatalog(
    List<WorkspaceAgentDefinition> agents,
  );

  WorkspaceTask<SkillsWorkspaceSnapshot> setFavorite({
    required WorkspaceSkillId skillId,
    required bool isFavorite,
  });

  WorkspaceTask<SkillsWorkspaceSnapshot> saveNote({
    required WorkspaceSkillId skillId,
    required String note,
  });

  WorkspaceTask<SkillsWorkspaceSnapshot> deleteNote(WorkspaceSkillId skillId);

  WorkspaceTask<WorkspacePersonalTag> createPersonalTag({
    required String name,
    String? color,
  });

  /// Replaces both name and color; pass the current color to keep it.
  WorkspaceTask<WorkspacePersonalTag> updatePersonalTag({
    required String tagId,
    required String name,
    String? color,
  });

  WorkspaceTask<SkillsWorkspaceSnapshot> deletePersonalTag(String tagId);

  WorkspaceTask<SkillsWorkspaceSnapshot> assignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  });

  WorkspaceTask<SkillsWorkspaceSnapshot> unassignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  });

  WorkspaceTask<SkillsWorkspaceSnapshot> abandonUpdateCandidate(
    WorkspaceSkillId skillId,
  );

  Future<void> close();
}
