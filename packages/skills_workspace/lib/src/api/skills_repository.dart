import '../domain/git_environment.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'requests.dart';
import 'result.dart';
import 'update_check_store.dart';

abstract interface class SkillsOperation<T> {
  /// Stable identity shared by progress, Journal, and history projections.
  OperationId get operationId;

  /// Broadcast progress that ends before [completed] resolves.
  Stream<OperationProgress> get progress;

  /// The operation's single terminal result.
  Future<SkillsResult<T>> get completed;

  /// Cooperatively requests cancellation before the business commit point.
  Future<void> cancel();
}

/// The sole public facade for the local Skill Workspace bounded context.
///
/// Implementations serialize lifecycle transitions. [open], [refresh], and
/// [close] are idempotent: repeating one against its already-achieved state
/// returns the corresponding current state without duplicating resources or
/// durable mutations. New work is rejected after closing begins.
abstract interface class SkillsRepository {
  /// Durable external-observation cache for update checks.
  UpdateCheckStore get updateCheckStore;

  /// Whether the facade currently owns an opened Workspace runtime.
  bool get isOpen;

  /// The latest immutable committed snapshot.
  ///
  /// Access before a successful [open] or after [close] is a programming error.
  RepositorySnapshot get snapshot;

  /// Broadcast committed snapshots, with no events after [close] completes.
  Stream<RepositorySnapshot> get snapshots;

  /// Reports whether the host can run system Git.
  ///
  /// Not a [SkillsOperation]: the check has no failure mode — every outcome,
  /// including a missing Git, is a successful classification — and it must stay
  /// answerable while the Workspace is closed or unopenable, which is exactly
  /// when a user is diagnosing their machine.
  ///
  /// Runs only when called. On a macOS host without the developer command line
  /// tools the probe itself causes the operating system to present its install
  /// dialog, so callers must invoke it from an explicit user action and never
  /// during startup.
  Future<GitEnvironmentReport> probeGitEnvironment();

  /// Opens and recovers the Workspace without exposing a partially writable state.
  SkillsOperation<RepositorySnapshot> open();

  /// Reloads the authoritative committed snapshot.
  SkillsOperation<RepositorySnapshot> refresh();

  /// Validates either selected Skills or the complete Workspace.
  SkillsOperation<WorkspaceValidationReport> validateWorkspace(
    ValidateWorkspaceRequest request,
  );

  /// Resumes durable post-commit finalization without exposing Journal or
  /// filesystem recovery details.
  ///
  /// Concurrent calls coalesce onto one lock-protected recovery attempt. A
  /// successful result contains the freshly published authoritative Snapshot;
  /// unresolved Journal work reports [SkillsErrorCode.finalizationRecoveryFailed].
  SkillsOperation<RepositorySnapshot> resumeFinalizationRecovery();

  /// Stops new work and deterministically releases all runtime resources.
  SkillsOperation<void> close();

  SkillsOperation<SourceInspection> inspectSource(InspectSourceRequest request);
  SkillsOperation<EffectiveSkillFileManifest> listEffectiveFiles(
    ListEffectiveFilesRequest request,
  );
  SkillsOperation<EffectiveSkillFileContent> readEffectiveFile(
    ReadEffectiveFileRequest request,
  );
  SkillsOperation<InstallAttempt> install(InstallRequest request);
  SkillsOperation<MutationReport> confirmInstallTakeover(
    ConfirmInstallTakeoverRequest request,
  );
  SkillsOperation<MutationReport> adopt(AdoptRequest request);
  SkillsOperation<List<UpdateReport>> checkUpdates(CheckUpdatesRequest request);
  SkillsOperation<MutationReport> update(UpdateRequest request);
  SkillsOperation<MutationReport> replaceSource(ReplaceSourceRequest request);

  SkillsOperation<List<ActivationTargetInfo>> inspectActivationTargets(
    InspectActivationTargetsRequest request,
  );
  SkillsOperation<List<AgentInfo>> inspectAgents();
  SkillsOperation<AgentRootOwnershipAudit> inspectAgentRootOwnership(
    InspectAgentRootOwnershipRequest request,
  );
  SkillsOperation<ActivationAttempt> activate(ActivateRequest request);
  SkillsOperation<MutationReport> confirmActivationTakeover(
    ConfirmActivationTakeoverRequest request,
  );
  SkillsOperation<MutationReport> deactivate(DeactivateRequest request);

  SkillsOperation<ExternalSkillsDiscovery> discoverExternalSkills(
    DiscoverExternalSkillsRequest request,
  );
  SkillsOperation<MutationReport> registerProjectRoot(
    RegisterProjectRootRequest request,
  );
  SkillsOperation<MutationReport> unregisterProjectRoot(
    UnregisterProjectRootRequest request,
  );
  SkillsOperation<MutationReport> remove(RemoveRequest request);
  SkillsOperation<RepositorySnapshot> reconfigureAgentCatalog(
    ReconfigureAgentCatalogRequest request,
  );

  SkillsOperation<RepositorySnapshot> setFavorite(SetFavoriteRequest request);
  SkillsOperation<RepositorySnapshot> saveNote(SaveNoteRequest request);
  SkillsOperation<RepositorySnapshot> deleteNote(DeleteNoteRequest request);
  SkillsOperation<PersonalTag> createPersonalTag(
    CreatePersonalTagRequest request,
  );
  SkillsOperation<PersonalTag> updatePersonalTag(
    UpdatePersonalTagRequest request,
  );
  SkillsOperation<RepositorySnapshot> deletePersonalTag(
    DeletePersonalTagRequest request,
  );
  SkillsOperation<RepositorySnapshot> assignPersonalTag(
    AssignPersonalTagRequest request,
  );
  SkillsOperation<RepositorySnapshot> unassignPersonalTag(
    UnassignPersonalTagRequest request,
  );

  SkillsOperation<DraftSummary> ensureDraft(EnsureDraftRequest request);
  SkillsOperation<DraftSummary?> inspectDraft(InspectDraftRequest request);
  SkillsOperation<RepositorySnapshot> discardDraft(DiscardDraftRequest request);
  SkillsOperation<MutationReport> publishDraft(PublishDraftRequest request);

  SkillsOperation<UpdateCandidateSummary?> inspectUpdateCandidate(
    InspectUpdateCandidateRequest request,
  );
  SkillsOperation<RepositorySnapshot> resolveUpdateConflict(
    ResolveUpdateConflictRequest request,
  );
  SkillsOperation<MutationReport> publishUpdateCandidate(
    PublishUpdateCandidateRequest request,
  );
  SkillsOperation<RepositorySnapshot> abandonUpdateCandidate(
    AbandonUpdateCandidateRequest request,
  );

  SkillsOperation<OperationHistoryPage> inspectOperationHistory(
    OperationHistoryRequest request,
  );
  SkillsOperation<PublishedHistoryPage> inspectPublishedHistory(
    PublishedHistoryRequest request,
  );
  SkillsOperation<SkillDiff> inspectDiff(InspectDiffRequest request);
  SkillsOperation<MutationReport> restorePublish(RestorePublishRequest request);

  /// Reviews external changes without modifying published materializations.
  SkillsOperation<SkillDriftReview> inspectSkillDrift(
    InspectSkillDriftRequest request,
  );

  /// Exports one unchanged reviewed artifact to a writable external directory.
  SkillsOperation<SkillDriftExport> exportSkillDriftArtifact(
    ExportSkillDriftArtifactRequest request,
  );

  /// Publishes reviewed external content or restores the managed revision.
  SkillsOperation<MutationReport> resolveSkillDrift(
    ResolveSkillDriftRequest request,
  );
}
