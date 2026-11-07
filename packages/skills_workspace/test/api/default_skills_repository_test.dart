import 'dart:async';

import 'package:skills_workspace/src/api/default_skills_repository.dart';
import 'package:skills_workspace/src/api/destructive_intent.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/api/skills_repository.dart';
import 'package:skills_workspace/src/api/update_check_store.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/application/ports/git_environment_ports.dart';
import 'package:skills_workspace/src/application/runtime/workspace_open_models.dart';
import 'package:skills_workspace/src/application/runtime/workspace_request_gate.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/git_environment.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../support/fake_skill_drift_review.dart';

void main() {
  test(
    'owns operation identity, progress, admission, and typed completion',
    () async {
      final runtime = _Runtime();
      final dispatcher = _Dispatcher();
      final repository = DefaultSkillsRepository(
        runtime: runtime,
        dispatcher: dispatcher,
        operationIds: _operationIds(),
        gitEnvironment: _GitEnvironment(),
      );

      final open = repository.open();
      final openProgress = open.progress.toList();
      final opened = await open.completed;
      expect(opened, isA<SkillsSuccess<RepositorySnapshot>>());
      expect((await openProgress).map((item) => item.phase), [
        OperationProgressPhase.queued,
        OperationProgressPhase.inspecting,
      ]);
      expect(repository.isOpen, isTrue);

      final operation = repository.setFavorite(
        SetFavoriteRequest(
          managedSkillId: ManagedSkillId(_skillId),
          isFavorite: true,
        ),
      );
      final progress = operation.progress.toList();
      final result = await operation.completed;

      expect(result, isA<SkillsSuccess<RepositorySnapshot>>());
      expect(dispatcher.operationIdObserved, operation.operationId);
      expect((await progress).map((item) => item.phase), [
        OperationProgressPhase.queued,
        OperationProgressPhase.inspecting,
        OperationProgressPhase.committing,
      ]);
      expect(runtime.gate.activeRequestCount, 0);
    },
  );

  test(
    'close cancels pre-commit work and waits for terminal completion',
    () async {
      final runtime = _Runtime();
      final dispatcher = _Dispatcher()..waitForCancellation = true;
      final repository = DefaultSkillsRepository(
        runtime: runtime,
        dispatcher: dispatcher,
        operationIds: _operationIds(),
        gitEnvironment: _GitEnvironment(),
      );
      await repository.open().completed;

      final request = repository.setFavorite(
        SetFavoriteRequest(
          managedSkillId: ManagedSkillId(_skillId),
          isFavorite: true,
        ),
      );
      await dispatcher.started.future;
      final close = repository.close();

      expect(
        (await request.completed).failureOrNull?.code,
        SkillsErrorCode.operationCancelled,
      );
      expect((await close.completed).isSuccess, isTrue);
      expect(repository.isOpen, isFalse);
      expect(runtime.gate.activeRequestCount, 0);
    },
  );

  test('close does not cancel work after its business commit point', () async {
    final runtime = _Runtime();
    final dispatcher = _Dispatcher()..waitAfterCommit = true;
    final repository = DefaultSkillsRepository(
      runtime: runtime,
      dispatcher: dispatcher,
      operationIds: _operationIds(),
      gitEnvironment: _GitEnvironment(),
    );
    await repository.open().completed;

    final request = repository.setFavorite(
      SetFavoriteRequest(
        managedSkillId: ManagedSkillId(_skillId),
        isFavorite: true,
      ),
    );
    await dispatcher.committed.future;
    final close = repository.close();
    var closeCompleted = false;
    close.completed.then((_) => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);

    expect(dispatcher.cancelledAfterCommit, isFalse);
    expect(closeCompleted, isFalse);
    dispatcher.finishAfterCommit.complete();
    expect((await request.completed).isSuccess, isTrue);
    expect((await close.completed).isSuccess, isTrue);
  });

  test('rejects ordinary operations outside the open lifetime', () async {
    final runtime = _Runtime();
    final repository = DefaultSkillsRepository(
      runtime: runtime,
      dispatcher: _Dispatcher(),
      operationIds: _operationIds(),
      gitEnvironment: _GitEnvironment(),
    );
    final request = SetFavoriteRequest(
      managedSkillId: ManagedSkillId(_skillId),
      isFavorite: true,
    );

    expect(() => repository.setFavorite(request), throwsStateError);
    await repository.open().completed;
    await repository.close().completed;
    expect(() => repository.setFavorite(request), throwsStateError);
    expect(() => repository.snapshot, throwsStateError);
  });

  test(
    'routes every public command through its typed operation kind',
    () async {
      final runtime = _Runtime();
      final dispatcher = _FailingRecordingDispatcher();
      final repository = DefaultSkillsRepository(
        runtime: runtime,
        dispatcher: dispatcher,
        operationIds: _operationIds(),
        gitEnvironment: _GitEnvironment(),
      );
      await repository.open().completed;

      final skillId = ManagedSkillId(_skillId);
      final source = LocalSourceDescriptor(locator: '/tmp/source');
      final candidate = ExternalSkillCandidate(
        slotKey: 'sample-skill',
        declaredName: 'sample-skill',
        description: 'Sample',
        contentHash: 'a' * 64,
        locations: const ['/tmp/source/sample-skill'],
        agentIds: const ['agent'],
      );
      final subject = OperationSubjectReference(
        operationId: OperationId('123e4567-e89b-42d3-a456-426614174100'),
        subjectId: '123e4567-e89b-42d3-a456-426614174101',
      );

      Future<void> route<T>(
        WorkspaceOperationKind expected,
        SkillsOperation<T> operation,
      ) async {
        expect(
          (await operation.completed).failureOrNull?.code,
          SkillsErrorCode.operationFailed,
        );
        expect(dispatcher.calls.last.$1, expected);
      }

      await route(WorkspaceOperationKind.refresh, repository.refresh());
      await route(
        WorkspaceOperationKind.resumeFinalizationRecovery,
        repository.resumeFinalizationRecovery(),
      );
      await route(
        WorkspaceOperationKind.inspectSource,
        repository.inspectSource(InspectSourceRequest(source: source)),
      );
      await route(
        WorkspaceOperationKind.listEffectiveFiles,
        repository.listEffectiveFiles(
          ListEffectiveFilesRequest(managedSkillId: skillId),
        ),
      );
      await route(
        WorkspaceOperationKind.readEffectiveFile,
        repository.readEffectiveFile(
          ReadEffectiveFileRequest(
            managedSkillId: skillId,
            expectedContentHash: 'a' * 64,
            relativePath: 'SKILL.md',
          ),
        ),
      );
      await route(
        WorkspaceOperationKind.install,
        repository.install(InstallRequest(source: source)),
      );
      await route(
        WorkspaceOperationKind.confirmInstallTakeover,
        repository.confirmInstallTakeover(
          ConfirmInstallTakeoverRequest(draft: const _InstallTakeoverDraft()),
        ),
      );
      await route(
        WorkspaceOperationKind.adopt,
        repository.adopt(
          AdoptRequest(
            selection: ExternalAdoptionSelection.fromCandidate(
              candidate,
              '/tmp/source/sample-skill',
            ),
          ),
        ),
      );
      await route(
        WorkspaceOperationKind.checkUpdates,
        repository.checkUpdates(CheckUpdatesRequest()),
      );
      await route(
        WorkspaceOperationKind.update,
        repository.update(UpdateRequest(managedSkillIds: {skillId})),
      );
      await route(
        WorkspaceOperationKind.replaceSource,
        repository.replaceSource(
          ReplaceSourceRequest(
            managedSkillId: skillId,
            source: source,
            intent: DestructiveIntent(reviewedRevision: RepositoryRevision(0)),
          ),
        ),
      );
      await route(
        WorkspaceOperationKind.inspectActivationTargets,
        repository.inspectActivationTargets(
          InspectActivationTargetsRequest(scope: ActivationScope.global),
        ),
      );
      await route(
        WorkspaceOperationKind.inspectAgents,
        repository.inspectAgents(),
      );
      await route(
        WorkspaceOperationKind.inspectAgentRootOwnership,
        repository.inspectAgentRootOwnership(
          const InspectAgentRootOwnershipRequest(),
        ),
      );
      await route(
        WorkspaceOperationKind.activate,
        repository.activate(
          ActivateRequest(
            managedSkillIds: {skillId},
            selection: const ActivationSelection.automatic(),
          ),
        ),
      );
      await route(
        WorkspaceOperationKind.confirmActivationTakeover,
        repository.confirmActivationTakeover(
          ConfirmActivationTakeoverRequest(draft: const _TakeoverDraft()),
        ),
      );
      await route(
        WorkspaceOperationKind.deactivate,
        repository.deactivate(DeactivateRequest(managedSkillIds: {skillId})),
      );
      await route(
        WorkspaceOperationKind.discoverExternalSkills,
        repository.discoverExternalSkills(
          const DiscoverExternalSkillsRequest(),
        ),
      );
      await route(
        WorkspaceOperationKind.registerProjectRoot,
        repository.registerProjectRoot(
          RegisterProjectRootRequest(path: '/tmp'),
        ),
      );
      await route(
        WorkspaceOperationKind.unregisterProjectRoot,
        repository.unregisterProjectRoot(
          UnregisterProjectRootRequest(id: 'root'),
        ),
      );
      await route(
        WorkspaceOperationKind.remove,
        repository.remove(
          RemoveRequest(
            managedSkillIds: {skillId},
            intent: DestructiveIntent(reviewedRevision: RepositoryRevision(0)),
          ),
        ),
      );
      await route(
        WorkspaceOperationKind.reconfigureAgentCatalog,
        repository.reconfigureAgentCatalog(
          ReconfigureAgentCatalogRequest(agents: const []),
        ),
      );
      await route(
        WorkspaceOperationKind.setFavorite,
        repository.setFavorite(
          SetFavoriteRequest(managedSkillId: skillId, isFavorite: true),
        ),
      );
      await route(
        WorkspaceOperationKind.saveNote,
        repository.saveNote(
          SaveNoteRequest(managedSkillId: skillId, text: 'note'),
        ),
      );
      await route(
        WorkspaceOperationKind.deleteNote,
        repository.deleteNote(DeleteNoteRequest(managedSkillId: skillId)),
      );
      await route(
        WorkspaceOperationKind.createPersonalTag,
        repository.createPersonalTag(CreatePersonalTagRequest(name: 'tag')),
      );
      await route(
        WorkspaceOperationKind.updatePersonalTag,
        repository.updatePersonalTag(
          UpdatePersonalTagRequest(tagId: 'tag-id', name: 'renamed'),
        ),
      );
      await route(
        WorkspaceOperationKind.deletePersonalTag,
        repository.deletePersonalTag(DeletePersonalTagRequest(tagId: 'tag-id')),
      );
      await route(
        WorkspaceOperationKind.assignPersonalTag,
        repository.assignPersonalTag(
          AssignPersonalTagRequest(managedSkillId: skillId, tagId: 'tag-id'),
        ),
      );
      await route(
        WorkspaceOperationKind.unassignPersonalTag,
        repository.unassignPersonalTag(
          UnassignPersonalTagRequest(managedSkillId: skillId, tagId: 'tag-id'),
        ),
      );
      await route(
        WorkspaceOperationKind.ensureDraft,
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: skillId)),
      );
      await route(
        WorkspaceOperationKind.inspectDraft,
        repository.inspectDraft(InspectDraftRequest(managedSkillId: skillId)),
      );
      await route(
        WorkspaceOperationKind.discardDraft,
        repository.discardDraft(DiscardDraftRequest(managedSkillId: skillId)),
      );
      await route(
        WorkspaceOperationKind.publishDraft,
        repository.publishDraft(PublishDraftRequest(managedSkillId: skillId)),
      );
      await route(
        WorkspaceOperationKind.inspectUpdateCandidate,
        repository.inspectUpdateCandidate(
          InspectUpdateCandidateRequest(managedSkillId: skillId),
        ),
      );
      await route(
        WorkspaceOperationKind.resolveUpdateConflict,
        repository.resolveUpdateConflict(
          ResolveUpdateConflictRequest(
            managedSkillId: skillId,
            path: 'SKILL.md',
            resolutionState: UpdateConflictResolutionState.resolved,
          ),
        ),
      );
      await route(
        WorkspaceOperationKind.publishUpdateCandidate,
        repository.publishUpdateCandidate(
          PublishUpdateCandidateRequest(managedSkillId: skillId),
        ),
      );
      await route(
        WorkspaceOperationKind.abandonUpdateCandidate,
        repository.abandonUpdateCandidate(
          AbandonUpdateCandidateRequest(managedSkillId: skillId),
        ),
      );
      await route(
        WorkspaceOperationKind.inspectOperationHistory,
        repository.inspectOperationHistory(
          OperationHistoryRequest(managedSkillId: skillId),
        ),
      );
      await route(
        WorkspaceOperationKind.inspectPublishedHistory,
        repository.inspectPublishedHistory(
          PublishedHistoryRequest(managedSkillId: skillId),
        ),
      );
      await route(
        WorkspaceOperationKind.inspectDiff,
        repository.inspectDiff(
          InspectDiffRequest(managedSkillId: skillId, to: subject),
        ),
      );
      await route(
        WorkspaceOperationKind.restorePublish,
        repository.restorePublish(
          RestorePublishRequest(
            managedSkillId: skillId,
            selectedRevision: subject,
          ),
        ),
      );
      await route(
        WorkspaceOperationKind.validateWorkspace,
        repository.validateWorkspace(const ValidateWorkspaceRequest()),
      );
      final driftReview = FakeSkillDriftReview(
        managedSkillId: skillId,
        effectiveContentHash: 'a' * 64,
      );
      await route(
        WorkspaceOperationKind.inspectSkillDrift,
        repository.inspectSkillDrift(
          InspectSkillDriftRequest(managedSkillId: skillId),
        ),
      );
      await route(
        WorkspaceOperationKind.exportSkillDriftArtifact,
        repository.exportSkillDriftArtifact(
          ExportSkillDriftArtifactRequest(
            review: driftReview,
            artifactId: 'repositoryCopy',
            destinationDirectory: '/exports',
          ),
        ),
      );
      await route(
        WorkspaceOperationKind.resolveSkillDrift,
        repository.resolveSkillDrift(
          ResolveSkillDriftRequest(
            review: driftReview,
            resolution: const RestoreManagedSkillDrift(),
          ),
        ),
      );

      expect(
        dispatcher.calls.map((call) => call.$1),
        WorkspaceOperationKind.values.where(
          (kind) =>
              kind != WorkspaceOperationKind.open &&
              kind != WorkspaceOperationKind.close,
        ),
      );
    },
  );

  test('answers a host Git probe without opening the Workspace', () async {
    final gitEnvironment = _GitEnvironment(
      GitEnvironmentStatus.developerToolsRequired,
    );
    final repository = DefaultSkillsRepository(
      runtime: _Runtime(),
      dispatcher: _Dispatcher(),
      operationIds: _operationIds(),
      gitEnvironment: gitEnvironment,
    );

    // Diagnosing a host is exactly when the Workspace may be unopenable, so the
    // answer must not depend on request admission.
    expect(repository.isOpen, isFalse);
    final report = await repository.probeGitEnvironment();

    expect(report.status, GitEnvironmentStatus.developerToolsRequired);
    expect(gitEnvironment.calls, 1);
  });

  test('never probes the host as a side effect of ordinary use', () async {
    final gitEnvironment = _GitEnvironment();
    final repository = DefaultSkillsRepository(
      runtime: _Runtime(),
      dispatcher: _Dispatcher(),
      operationIds: _operationIds(),
      gitEnvironment: gitEnvironment,
    );

    await repository.open().completed;
    await repository.refresh().completed;

    expect(gitEnvironment.calls, isZero);
  });
}

const _skillId = '123e4567-e89b-42d3-a456-426614174000';

OperationId Function() _operationIds() {
  var value = 1;
  return () {
    final suffix = value.toString().padLeft(12, '0');
    value += 1;
    return OperationId('123e4567-e89b-42d3-a456-$suffix');
  };
}

final class _Runtime implements SkillsRepositoryRuntime {
  @override
  UpdateCheckStore get updateCheckStore => InMemoryUpdateCheckStore();

  final WorkspaceRequestGate gate = WorkspaceRequestGate();
  final StreamController<RepositorySnapshot> _snapshots =
      StreamController<RepositorySnapshot>.broadcast();
  RepositorySnapshot? _snapshot;
  bool _closed = false;

  @override
  bool get isOpen => _snapshot != null && !_closed;

  @override
  RepositorySnapshot get snapshot {
    final current = _snapshot;
    if (current == null || _closed) throw StateError('not open');
    return current;
  }

  @override
  Stream<RepositorySnapshot> get snapshots => _snapshots.stream;

  @override
  Future<WorkspaceOpenOutcome> open() async {
    if (_closed) {
      return WorkspaceOpenFailed(
        code: WorkspaceOpenFailureCode.repositoryClosed,
      );
    }
    final current = _snapshot;
    if (current != null) {
      return WorkspaceOpened(
        snapshot: current,
        primaryRecovery: ControlPlanePrimaryReady(
          const ControlPlaneIdentity(
            schemaVersion: 1,
            repositoryRevision: 0,
            destructionEpoch: 0,
          ),
        ),
        recoveredSkillIds: const {},
        isolatedSkillIds: const {},
      );
    }
    await gate.openForRequests();
    final created = RepositorySnapshot.empty();
    _snapshot = created;
    _snapshots.add(created);
    return WorkspaceOpened(
      snapshot: created,
      primaryRecovery: ControlPlanePrimaryReady(
        const ControlPlaneIdentity(
          schemaVersion: 1,
          repositoryRevision: 0,
          destructionEpoch: 0,
        ),
      ),
      recoveredSkillIds: const {},
      isolatedSkillIds: const {},
    );
  }

  @override
  WorkspaceRequestAdmission? admit({
    required OperationId operationId,
    required Future<void> Function() cancelBeforeCommit,
  }) => gate.admit(
    operationId: operationId,
    cancelBeforeCommit: cancelBeforeCommit,
  );

  @override
  Future<WorkspaceCloseOutcome> close() async {
    if (_closed) return const WorkspaceClosed(alreadyClosed: true);
    await gate.stopAccepting();
    await gate.settleInFlightByCommitState();
    await gate.close();
    _closed = true;
    _snapshot = null;
    await _snapshots.close();
    return const WorkspaceClosed(alreadyClosed: false);
  }
}

final class _Dispatcher implements SkillsRepositoryCommandDispatcher {
  final Completer<void> started = Completer<void>();
  final Completer<void> committed = Completer<void>();
  final Completer<void> finishAfterCommit = Completer<void>();
  bool waitForCancellation = false;
  bool waitAfterCommit = false;
  bool cancelledAfterCommit = false;
  OperationId? operationIdObserved;

  @override
  Future<SkillsResult<T>> execute<T>({
    required OperationId operationId,
    required WorkspaceOperationKind kind,
    required Object request,
    required CancellationToken cancellationToken,
    required void Function() markBusinessCommitted,
    required SkillsProgressReporter reportProgress,
  }) async {
    operationIdObserved = operationId;
    reportProgress(OperationProgressPhase.inspecting);
    if (!started.isCompleted) started.complete();
    if (waitForCancellation) {
      await cancellationToken.whenCancelled;
      return SkillsFailure<T>(code: SkillsErrorCode.operationCancelled);
    }
    reportProgress(OperationProgressPhase.committing);
    markBusinessCommitted();
    if (!committed.isCompleted) committed.complete();
    if (waitAfterCommit) {
      await Future.any<void>([
        finishAfterCommit.future,
        cancellationToken.whenCancelled.then((_) {
          cancelledAfterCommit = true;
        }),
      ]);
    }
    final value = RepositorySnapshot.empty();
    return SkillsSuccess<T>(value: value as T, changed: true);
  }
}

final class _FailingRecordingDispatcher
    implements SkillsRepositoryCommandDispatcher {
  final List<(WorkspaceOperationKind, Object)> calls = [];

  @override
  Future<SkillsResult<T>> execute<T>({
    required OperationId operationId,
    required WorkspaceOperationKind kind,
    required Object request,
    required CancellationToken cancellationToken,
    required void Function() markBusinessCommitted,
    required SkillsProgressReporter reportProgress,
  }) async {
    calls.add((kind, request));
    return SkillsFailure<T>(code: SkillsErrorCode.operationFailed);
  }
}

final class _TakeoverDraft implements ActivationTakeoverDraft {
  const _TakeoverDraft();

  @override
  RepositoryRevision get reviewedRevision => RepositoryRevision(0);

  @override
  List<OccupiedActivationTarget> get targets => const [];
}

final class _InstallTakeoverDraft implements InstallTakeoverDraft {
  const _InstallTakeoverDraft();

  @override
  RepositoryRevision get reviewedRevision => RepositoryRevision(0);

  @override
  List<OccupiedInstallTarget> get targets => const [];
}

/// Records probe calls so tests can assert the host is never touched
/// incidentally.
final class _GitEnvironment implements GitEnvironmentProbe {
  _GitEnvironment([this.status = GitEnvironmentStatus.available]);

  final GitEnvironmentStatus status;
  int calls = 0;

  @override
  Future<GitEnvironmentReport> probe() async {
    calls += 1;
    return GitEnvironmentReport(status: status);
  }
}
