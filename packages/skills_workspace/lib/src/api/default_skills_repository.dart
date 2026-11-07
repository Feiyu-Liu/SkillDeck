import 'dart:async';

import '../application/ports/git_environment_ports.dart';
import '../application/runtime/workspace_open_models.dart';
import '../application/runtime/workspace_request_gate.dart';
import '../domain/cancellation.dart';
import '../domain/git_environment.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'finalization_recovery_command.dart';
import 'requests.dart';
import 'result.dart';
import 'skills_operation_controller.dart';
import 'skills_repository.dart';
import 'update_check_store.dart';

/// Runtime boundary used by the public facade without exposing implementation
/// resources or persistence types.
abstract interface class SkillsRepositoryRuntime {
  UpdateCheckStore get updateCheckStore;

  bool get isOpen;

  RepositorySnapshot get snapshot;

  Stream<RepositorySnapshot> get snapshots;

  Future<WorkspaceOpenOutcome> open();

  Future<WorkspaceCloseOutcome> close();

  WorkspaceRequestAdmission? admit({
    required OperationId operationId,
    required Future<void> Function() cancelBeforeCommit,
  });
}

typedef SkillsProgressReporter =
    void Function(
      OperationProgressPhase phase, {
      String? currentItem,
      int completed,
      int? total,
    });

/// Type-erased only at the private composition seam. The public facade keeps
/// each request and result generic pair intact at every call site.
abstract interface class SkillsRepositoryCommandDispatcher {
  Future<SkillsResult<T>> execute<T>({
    required OperationId operationId,
    required WorkspaceOperationKind kind,
    required Object request,
    required CancellationToken cancellationToken,
    required void Function() markBusinessCommitted,
    required SkillsProgressReporter reportProgress,
  });
}

/// Concrete operation-owning implementation behind [SkillsRepository].
///
/// This class owns public operation identity, progress, cancellation, request
/// admission and terminal completion. Business handlers remain behind the
/// private dispatcher and can never return a second operation identity.
final class DefaultSkillsRepository implements SkillsRepository {
  DefaultSkillsRepository({
    required SkillsRepositoryRuntime runtime,
    required SkillsRepositoryCommandDispatcher dispatcher,
    required OperationId Function() operationIds,
    required GitEnvironmentProbe gitEnvironment,
  }) : _runtime = runtime,
       _dispatcher = dispatcher,
       _operationIds = operationIds,
       _gitEnvironment = gitEnvironment;

  final SkillsRepositoryRuntime _runtime;
  final SkillsRepositoryCommandDispatcher _dispatcher;
  final OperationId Function() _operationIds;
  final GitEnvironmentProbe _gitEnvironment;

  @override
  UpdateCheckStore get updateCheckStore => _runtime.updateCheckStore;

  @override
  bool get isOpen => _runtime.isOpen;

  @override
  RepositorySnapshot get snapshot => _runtime.snapshot;

  @override
  Stream<RepositorySnapshot> get snapshots => _runtime.snapshots;

  /// Deliberately bypasses request admission: a host capability answer must
  /// remain available when the Workspace is closed or failed to open.
  @override
  Future<GitEnvironmentReport> probeGitEnvironment() => _gitEnvironment.probe();

  @override
  SkillsOperation<RepositorySnapshot> open() {
    final controller = _controller<RepositorySnapshot>(
      WorkspaceOperationKind.open,
    );
    unawaited(Future<void>.microtask(() => _open(controller)));
    return controller.operation;
  }

  Future<void> _open(
    SkillsOperationController<RepositorySnapshot> controller,
  ) async {
    controller.emit(OperationProgressPhase.queued);
    controller.emit(OperationProgressPhase.inspecting);
    try {
      final outcome = await _runtime.open();
      final result = switch (outcome) {
        WorkspaceOpened(:final snapshot) => SkillsSuccess<RepositorySnapshot>(
          value: snapshot,
          changed: true,
        ),
        WorkspaceOpenFailed(:final code, :final cleanupFailures) =>
          SkillsFailure<RepositorySnapshot>(
            code: _openFailureCode(code),
            context: <String, Object?>{
              'reason': code.name,
              if (cleanupFailures.isNotEmpty)
                'cleanupPending': cleanupFailures.length,
            },
          ),
      };
      await controller.finish(result);
    } on Object {
      await controller.finish(
        SkillsFailure<RepositorySnapshot>(
          code: SkillsErrorCode.operationFailed,
          context: const <String, Object?>{'operation': 'open'},
        ),
      );
    }
  }

  @override
  SkillsOperation<RepositorySnapshot> refresh() {
    _requireOpen();
    return _dispatch<RepositorySnapshot>(
      kind: WorkspaceOperationKind.refresh,
      request: const RefreshWorkspaceCommand(),
    );
  }

  @override
  SkillsOperation<WorkspaceValidationReport> validateWorkspace(
    ValidateWorkspaceRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.validateWorkspace,
    request: request,
  );

  @override
  SkillsOperation<RepositorySnapshot> resumeFinalizationRecovery() => _dispatch(
    kind: WorkspaceOperationKind.resumeFinalizationRecovery,
    request: const ResumeFinalizationRecoveryCommand(),
  );

  @override
  SkillsOperation<void> close() {
    final controller = _controller<void>(WorkspaceOperationKind.close);
    unawaited(Future<void>.microtask(() => _close(controller)));
    return controller.operation;
  }

  Future<void> _close(SkillsOperationController<void> controller) async {
    controller.emit(OperationProgressPhase.queued);
    controller.emit(OperationProgressPhase.finalizing);
    try {
      final outcome = await _runtime.close();
      final result = switch (outcome) {
        WorkspaceClosed(:final alreadyClosed) => SkillsSuccess<void>(
          value: null,
          changed: !alreadyClosed,
        ),
        WorkspaceCloseFailed(:final failures) => SkillsFailure<void>(
          code: SkillsErrorCode.finalizationRecoveryFailed,
          context: <String, Object?>{'cleanupPending': failures.length},
        ),
      };
      await controller.finish(result);
    } on Object {
      await controller.finish(
        SkillsFailure<void>(
          code: SkillsErrorCode.finalizationRecoveryFailed,
          context: const <String, Object?>{'operation': 'close'},
        ),
      );
    }
  }

  @override
  SkillsOperation<SourceInspection> inspectSource(
    InspectSourceRequest request,
  ) => _dispatch(kind: WorkspaceOperationKind.inspectSource, request: request);

  @override
  SkillsOperation<EffectiveSkillFileManifest> listEffectiveFiles(
    ListEffectiveFilesRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.listEffectiveFiles,
    request: request,
  );

  @override
  SkillsOperation<EffectiveSkillFileContent> readEffectiveFile(
    ReadEffectiveFileRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.readEffectiveFile,
    request: request,
  );

  @override
  SkillsOperation<InstallAttempt> install(InstallRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.install, request: request);

  @override
  SkillsOperation<MutationReport> confirmInstallTakeover(
    ConfirmInstallTakeoverRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.confirmInstallTakeover,
    request: request,
  );

  @override
  SkillsOperation<MutationReport> adopt(AdoptRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.adopt, request: request);

  @override
  SkillsOperation<List<UpdateReport>> checkUpdates(
    CheckUpdatesRequest request,
  ) => _dispatch(kind: WorkspaceOperationKind.checkUpdates, request: request);

  @override
  SkillsOperation<MutationReport> update(UpdateRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.update, request: request);

  @override
  SkillsOperation<MutationReport> replaceSource(ReplaceSourceRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.replaceSource, request: request);

  @override
  SkillsOperation<List<AgentInfo>> inspectAgents() => _dispatch(
    kind: WorkspaceOperationKind.inspectAgents,
    request: const InspectAgentsRequest(),
  );

  @override
  SkillsOperation<List<ActivationTargetInfo>> inspectActivationTargets(
    InspectActivationTargetsRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.inspectActivationTargets,
    request: request,
  );

  @override
  SkillsOperation<AgentRootOwnershipAudit> inspectAgentRootOwnership(
    InspectAgentRootOwnershipRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.inspectAgentRootOwnership,
    request: request,
  );

  @override
  SkillsOperation<ActivationAttempt> activate(ActivateRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.activate, request: request);

  @override
  SkillsOperation<MutationReport> confirmActivationTakeover(
    ConfirmActivationTakeoverRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.confirmActivationTakeover,
    request: request,
  );

  @override
  SkillsOperation<MutationReport> deactivate(DeactivateRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.deactivate, request: request);

  @override
  SkillsOperation<ExternalSkillsDiscovery> discoverExternalSkills(
    DiscoverExternalSkillsRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.discoverExternalSkills,
    request: request,
  );

  @override
  SkillsOperation<MutationReport> registerProjectRoot(
    RegisterProjectRootRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.registerProjectRoot,
    request: request,
  );

  @override
  SkillsOperation<MutationReport> unregisterProjectRoot(
    UnregisterProjectRootRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.unregisterProjectRoot,
    request: request,
  );

  @override
  SkillsOperation<MutationReport> remove(RemoveRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.remove, request: request);

  @override
  SkillsOperation<RepositorySnapshot> reconfigureAgentCatalog(
    ReconfigureAgentCatalogRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.reconfigureAgentCatalog,
    request: request,
  );

  @override
  SkillsOperation<RepositorySnapshot> setFavorite(SetFavoriteRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.setFavorite, request: request);

  @override
  SkillsOperation<RepositorySnapshot> saveNote(SaveNoteRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.saveNote, request: request);

  @override
  SkillsOperation<RepositorySnapshot> deleteNote(DeleteNoteRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.deleteNote, request: request);

  @override
  SkillsOperation<PersonalTag> createPersonalTag(
    CreatePersonalTagRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.createPersonalTag,
    request: request,
  );

  @override
  SkillsOperation<PersonalTag> updatePersonalTag(
    UpdatePersonalTagRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.updatePersonalTag,
    request: request,
  );

  @override
  SkillsOperation<RepositorySnapshot> deletePersonalTag(
    DeletePersonalTagRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.deletePersonalTag,
    request: request,
  );

  @override
  SkillsOperation<RepositorySnapshot> assignPersonalTag(
    AssignPersonalTagRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.assignPersonalTag,
    request: request,
  );

  @override
  SkillsOperation<RepositorySnapshot> unassignPersonalTag(
    UnassignPersonalTagRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.unassignPersonalTag,
    request: request,
  );

  @override
  SkillsOperation<DraftSummary> ensureDraft(EnsureDraftRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.ensureDraft, request: request);

  @override
  SkillsOperation<DraftSummary?> inspectDraft(InspectDraftRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.inspectDraft, request: request);

  @override
  SkillsOperation<RepositorySnapshot> discardDraft(
    DiscardDraftRequest request,
  ) => _dispatch(kind: WorkspaceOperationKind.discardDraft, request: request);

  @override
  SkillsOperation<MutationReport> publishDraft(PublishDraftRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.publishDraft, request: request);

  @override
  SkillsOperation<UpdateCandidateSummary?> inspectUpdateCandidate(
    InspectUpdateCandidateRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.inspectUpdateCandidate,
    request: request,
  );

  @override
  SkillsOperation<RepositorySnapshot> resolveUpdateConflict(
    ResolveUpdateConflictRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.resolveUpdateConflict,
    request: request,
  );

  @override
  SkillsOperation<MutationReport> publishUpdateCandidate(
    PublishUpdateCandidateRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.publishUpdateCandidate,
    request: request,
  );

  @override
  SkillsOperation<RepositorySnapshot> abandonUpdateCandidate(
    AbandonUpdateCandidateRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.abandonUpdateCandidate,
    request: request,
  );

  @override
  SkillsOperation<OperationHistoryPage> inspectOperationHistory(
    OperationHistoryRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.inspectOperationHistory,
    request: request,
  );

  @override
  SkillsOperation<PublishedHistoryPage> inspectPublishedHistory(
    PublishedHistoryRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.inspectPublishedHistory,
    request: request,
  );

  @override
  SkillsOperation<SkillDiff> inspectDiff(InspectDiffRequest request) =>
      _dispatch(kind: WorkspaceOperationKind.inspectDiff, request: request);

  @override
  SkillsOperation<MutationReport> restorePublish(
    RestorePublishRequest request,
  ) => _dispatch(kind: WorkspaceOperationKind.restorePublish, request: request);

  @override
  SkillsOperation<SkillDriftReview> inspectSkillDrift(
    InspectSkillDriftRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.inspectSkillDrift,
    request: request,
  );

  @override
  SkillsOperation<SkillDriftExport> exportSkillDriftArtifact(
    ExportSkillDriftArtifactRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.exportSkillDriftArtifact,
    request: request,
  );

  @override
  SkillsOperation<MutationReport> resolveSkillDrift(
    ResolveSkillDriftRequest request,
  ) => _dispatch(
    kind: WorkspaceOperationKind.resolveSkillDrift,
    request: request,
  );

  SkillsOperation<T> _dispatch<T>({
    required WorkspaceOperationKind kind,
    required Object request,
  }) {
    _requireOpen();
    final controller = _controller<T>(kind);
    final admission = _runtime.admit(
      operationId: controller.operation.operationId,
      cancelBeforeCommit: controller.operation.cancel,
    );
    if (admission == null) {
      throw StateError('The SkillsRepository is closing or closed.');
    }
    unawaited(
      Future<void>.microtask(
        () => _execute(controller, admission, kind, request),
      ),
    );
    return controller.operation;
  }

  Future<void> _execute<T>(
    SkillsOperationController<T> controller,
    WorkspaceRequestAdmission admission,
    WorkspaceOperationKind kind,
    Object request,
  ) async {
    controller.emit(OperationProgressPhase.queued);
    try {
      final result = await _dispatcher.execute<T>(
        operationId: controller.operation.operationId,
        kind: kind,
        request: request,
        cancellationToken: controller.cancellationToken,
        markBusinessCommitted: admission.markBusinessCommitted,
        reportProgress: (phase, {currentItem, completed = 0, total}) =>
            controller.emit(
              phase,
              currentItem: currentItem,
              completed: completed,
              total: total,
            ),
      );
      await controller.finish(result);
    } on Object {
      await controller.finish(
        SkillsFailure<T>(
          code: controller.cancellationToken.isCancelled
              ? SkillsErrorCode.operationCancelled
              : SkillsErrorCode.operationFailed,
          context: <String, Object?>{'operation': kind.name},
        ),
      );
    } finally {
      admission.finish();
    }
  }

  SkillsOperationController<T> _controller<T>(WorkspaceOperationKind kind) =>
      SkillsOperationController<T>(operationId: _operationIds(), kind: kind);

  void _requireOpen() {
    if (!_runtime.isOpen) {
      throw StateError('The SkillsRepository is not open.');
    }
  }
}

final class RefreshWorkspaceCommand {
  const RefreshWorkspaceCommand();
}

SkillsErrorCode _openFailureCode(WorkspaceOpenFailureCode code) =>
    switch (code) {
      WorkspaceOpenFailureCode.writerLockUnavailable =>
        SkillsErrorCode.repositoryBusy,
      WorkspaceOpenFailureCode.controlPlaneRecoveryBlocked =>
        SkillsErrorCode.controlPlaneCorrupt,
      WorkspaceOpenFailureCode.controlPlaneOpenFailed =>
        SkillsErrorCode.migrationFailed,
      WorkspaceOpenFailureCode.revisionWorkerStartupFailed ||
      WorkspaceOpenFailureCode.revisionMaintenanceFailed =>
        SkillsErrorCode.revisionStoreCorrupt,
      WorkspaceOpenFailureCode.journalRecoveryFailed ||
      WorkspaceOpenFailureCode.revisionReferenceReconciliationFailed ||
      WorkspaceOpenFailureCode.materializationReconciliationFailed =>
        SkillsErrorCode.recoveryFailed,
      WorkspaceOpenFailureCode.snapshotReadFailed ||
      WorkspaceOpenFailureCode.snapshotPublicationFailed ||
      WorkspaceOpenFailureCode.requestGateOpenFailed ||
      WorkspaceOpenFailureCode.repositoryClosed =>
        SkillsErrorCode.operationFailed,
    };
