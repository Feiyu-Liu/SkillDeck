import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_drift_review_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

import '../../../../support/fake_directory_picker.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/fake_skill_drift_reviews.dart';
import '../../../../support/skill_drift_test_support.dart';

void main() {
  late FakeSkillsWorkspaceRepository repository;
  late FakeWorkspaceSkillDriftReview review;
  late ProviderContainer container;
  late SkillDriftReviewViewModel notifier;
  var disposed = false;
  final provider = skillDriftReviewViewModelProvider(driftReviewSkillId);

  setUp(() {
    disposed = false;
    repository = FakeSkillsWorkspaceRepository(snapshot: _pendingSnapshot());
    review = driftReviewFixture();
    repository.inspectSkillDriftTasks.add(
      completedWorkspaceTask(
        kind: WorkspaceOperationKind.inspectSkillDrift,
        value: review,
      ),
    );
    container = ProviderContainer(
      overrides: [
        skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
        directoryPickerProvider.overrideWithValue(
          FakeDirectoryPicker('/exports'),
        ),
      ],
    );
    container.listen(provider, (_, _) {});
    notifier = container.read(provider.notifier);
  });
  tearDown(() async {
    if (!disposed) container.dispose();
    await repository.dispose();
  });

  SkillDriftReviewState state() => container.read(provider);
  Future<void> selectCopy() async {
    await notifier.load();
    notifier.select('repositoryCopy');
  }

  test(
    'load exposes the opaque review with no default authority selection',
    () async {
      expect(state().status, SkillDriftReviewStatus.loading);
      expect(state().isBusy, isFalse);
      await notifier.load();
      expect(state().status, SkillDriftReviewStatus.loaded);
      expect(state().review, same(review));
      expect(state().selectedArtifactId, isNull);
      expect(state().canKeepExternal, isFalse);
      expect(state().canRestoreManaged, isTrue);
      expect(await notifier.keepExternal(), isFalse);
      expect(repository.resolvedSkillDrifts, isEmpty);
    },
  );

  test('selection accepts only keepable reviewed artifacts', () async {
    await notifier.load();
    notifier.select('missing');
    notifier.select('linkActivation');
    expect(state().selectedArtifactId, isNull);
    notifier.select('repositoryCopy');
    expect(state().canKeepExternal, isTrue);
    notifier.select('copyActivation');
    expect(state().selectedArtifactId, 'copyActivation');
  });

  test('family state is isolated by stable Skill identity', () async {
    await selectCopy();
    final other = skillDriftReviewViewModelProvider(WorkspaceSkillId('other'));
    container.listen(other, (_, _) {});
    await container.read(other.notifier).load();
    expect(container.read(other).selectedArtifactId, isNull);
    expect(state().selectedArtifactId, 'repositoryCopy');
  });

  test('inspection is single flight and authorization stays disabled while loading', () async {
    final pending = DeferredDriftReviewTask<WorkspaceSkillDriftReview>(
      WorkspaceOperationKind.inspectSkillDrift,
    );
    addTearDown(pending.dispose);
    repository.inspectSkillDriftTasks
      ..clear()
      ..add(pending.task);
    final first = notifier.load();
    await notifier.load(refresh: true);
    expect(repository.inspectedSkillDrifts, hasLength(1));
    expect(repository.refreshCalls, 0);
    expect(state().canRestoreManaged, isFalse);
    expect(state().isBusy, isFalse);
    pending.completed.complete(WorkspaceCompleted(value: review));
    await first;
    expect(state().status, SkillDriftReviewStatus.loaded);
  });

  test(
    'export uses the directory picker and keeps selection plus output path',
    () async {
      await selectCopy();
      repository.exportSkillDriftArtifactTasks.add(
        completedWorkspaceTask(
          kind: WorkspaceOperationKind.exportSkillDriftArtifact,
          value: const WorkspaceSkillDriftExport(
            exportedPath: '/exports/sample-external-20261014090000',
          ),
        ),
      );
      await notifier.export('repositoryCopy');
      expect(
        repository.exportedSkillDriftArtifacts.single.review,
        same(review),
      );
      expect(
        repository.exportedSkillDriftArtifacts.single.destinationDirectory,
        '/exports',
      );
      expect(
        state().exportedPaths['repositoryCopy'],
        '/exports/sample-external-20261014090000',
      );
      expect(state().selectedArtifactId, 'repositoryCopy');
      expect(state().status, SkillDriftReviewStatus.loaded);
    },
  );

  test(
    'cancelled picker restores the loaded review without exporting',
    () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
          directoryPickerProvider.overrideWithValue(FakeDirectoryPicker(null)),
        ],
      );
      container.listen(provider, (_, _) {});
      notifier = container.read(provider.notifier);
      await selectCopy();
      await notifier.export('repositoryCopy');
      expect(repository.exportedSkillDriftArtifacts, isEmpty);
      expect(state().status, SkillDriftReviewStatus.loaded);
      expect(state().selectedArtifactId, 'repositoryCopy');
      expect(state().failure, isNull);
    },
  );

  test(
    'a pending picker excludes duplicate export, selection, load and mutations',
    () async {
      final picker = DeferredDriftDirectoryPicker();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
          directoryPickerProvider.overrideWithValue(picker),
        ],
      );
      container.listen(provider, (_, _) {});
      notifier = container.read(provider.notifier);
      await selectCopy();
      final pending = notifier.export('repositoryCopy');
      notifier.select('copyActivation');
      await notifier.export('repositoryCopy');
      await notifier.load();
      expect(await notifier.keepExternal(), isFalse);
      expect(await notifier.restoreManaged(), isFalse);
      expect(picker.calls, 1);
      expect(repository.inspectedSkillDrifts, hasLength(1));
      expect(state().selectedArtifactId, 'repositoryCopy');
      picker.completed.complete(null);
      await pending;
      expect(state().status, SkillDriftReviewStatus.loaded);
    },
  );

  test(
    'restore-only artifacts cannot invoke export or become keep authorities',
    () async {
      await notifier.load();
      await notifier.export('linkActivation');
      expect(repository.exportedSkillDriftArtifacts, isEmpty);
      notifier.select('linkActivation');
      expect(await notifier.keepExternal(), isFalse);
    },
  );

  test('keep sends exactly the selected artifact and review handle', () async {
    await selectCopy();
    expect(await notifier.keepExternal(), isTrue);
    final request = repository.resolvedSkillDrifts.single;
    expect(request.review, same(review));
    expect(
      (request.resolution as WorkspaceKeepExternalSkillDrift).artifactId,
      'repositoryCopy',
    );
    expect(repository.refreshCalls, 0);
  });

  test('restore requires no selected external authority', () async {
    await notifier.load();
    expect(await notifier.restoreManaged(), isTrue);
    expect(
      repository.resolvedSkillDrifts.single.resolution,
      isA<WorkspaceRestoreManagedSkillDrift>(),
    );
    expect(state().status, SkillDriftReviewStatus.loaded);
  });

  test(
    'an unchanged restore is success without an imperative catalog refresh',
    () async {
      repository.inspectSkillDriftTasks
        ..clear()
        ..add(
          completedWorkspaceTask(
            kind: WorkspaceOperationKind.inspectSkillDrift,
            value: FakeWorkspaceSkillDriftReview(skillId: driftReviewSkillId),
          ),
        );
      await notifier.load();
      expect(await notifier.restoreManaged(), isTrue);
      expect(repository.current.revision, 7);
      expect(repository.refreshCalls, 0);
    },
  );

  test(
    'nonstale failure preserves review, selection and exported paths for retry',
    () async {
      await selectCopy();
      await notifier.export('repositoryCopy');
      final exportedPath = state().exportedPaths['repositoryCopy'];
      final failure = WorkspaceException(
        code: WorkspaceErrorCode.ioFailure,
        operation: WorkspaceOperationKind.resolveSkillDrift,
      );
      repository.resolveSkillDriftTasks.add(
        failedWorkspaceTask(
          kind: WorkspaceOperationKind.resolveSkillDrift,
          error: failure,
        ),
      );
      expect(await notifier.keepExternal(), isFalse);
      expect(state().status, SkillDriftReviewStatus.failed);
      expect(state().failure, same(failure));
      expect(state().review, same(review));
      expect(state().selectedArtifactId, 'repositoryCopy');
      expect(state().exportedPaths['repositoryCopy'], exportedPath);
      expect(
        repository.current.skills.single.integrity,
        WorkspaceSkillIntegrityStatus.driftPending,
      );
      expect(state().canKeepExternal, isTrue);
      expect(await notifier.keepExternal(), isTrue);
      expect(repository.resolvedSkillDrifts, hasLength(2));
    },
  );

  for (final code in [
    WorkspaceErrorCode.staleDriftReview,
    WorkspaceErrorCode.staleSnapshot,
  ]) {
    test(
      '$code clears authorization and refreshes before reinspecting',
      () async {
        await selectCopy();
        repository.resolveSkillDriftTasks.add(
          failedWorkspaceTask(
            kind: WorkspaceOperationKind.resolveSkillDrift,
            error: WorkspaceException(
              code: code,
              operation: WorkspaceOperationKind.resolveSkillDrift,
            ),
          ),
        );
        expect(await notifier.keepExternal(), isFalse);
        expect(state().status, SkillDriftReviewStatus.stale);
        expect(state().review, isNull);
        expect(state().selectedArtifactId, isNull);
        expect(await notifier.restoreManaged(), isFalse);
        final pending = DeferredDriftReviewTask<WorkspaceSkillDriftReview>(
          WorkspaceOperationKind.inspectSkillDrift,
        );
        addTearDown(pending.dispose);
        repository.inspectSkillDriftTasks.add(pending.task);
        final reload = notifier.load(refresh: true);
        expect(repository.refreshCalls, 1);
        expect(repository.inspectedSkillDrifts, hasLength(1));
        await Future<void>.delayed(Duration.zero);
        expect(repository.inspectedSkillDrifts, hasLength(2));
        pending.completed.complete(
          WorkspaceCompleted(value: driftReviewFixture()),
        );
        await reload;
        expect(state().status, SkillDriftReviewStatus.loaded);
        expect(state().selectedArtifactId, isNull);
        expect(state().failure, isNull);
      },
    );
  }

  test('failed refresh prevents inspection with obsolete authority', () async {
    repository.refreshError = WorkspaceException(
      code: WorkspaceErrorCode.ioFailure,
      operation: WorkspaceOperationKind.refresh,
    );
    await notifier.load(refresh: true);
    expect(repository.inspectedSkillDrifts, isEmpty);
    expect(state().status, SkillDriftReviewStatus.failed);
    expect(state().review, isNull);
  });

  test('unsafe inspection remains a typed failure without changing pending integrity', () async {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.driftResolutionUnavailable,
      operation: WorkspaceOperationKind.inspectSkillDrift,
      context: const {'reason': 'unsafeInspection'},
    );
    repository.inspectSkillDriftTasks
      ..clear()
      ..add(
        failedWorkspaceTask(
          kind: WorkspaceOperationKind.inspectSkillDrift,
          error: failure,
        ),
      );
    await notifier.load();
    expect(state().status, SkillDriftReviewStatus.failed);
    expect(state().failure, same(failure));
    expect(state().review, isNull);
    expect(
      repository.current.skills.single.integrity,
      WorkspaceSkillIntegrityStatus.driftPending,
    );
  });

  test('stale export clears the previous review authorization', () async {
    await selectCopy();
    repository.exportSkillDriftArtifactTasks.add(
      failedWorkspaceTask(
        kind: WorkspaceOperationKind.exportSkillDriftArtifact,
        error: WorkspaceException(
          code: WorkspaceErrorCode.staleDriftReview,
          operation: WorkspaceOperationKind.exportSkillDriftArtifact,
        ),
      ),
    );
    await notifier.export('repositoryCopy');
    expect(state().status, SkillDriftReviewStatus.stale);
    expect(state().review, isNull);
  });

  test('mutation progress and terminal warnings are retained', () async {
    await selectCopy();
    final pending = DeferredDriftReviewTask<WorkspaceMutationReceipt>(
      WorkspaceOperationKind.resolveSkillDrift,
    );
    addTearDown(pending.dispose);
    repository.resolveSkillDriftTasks.add(pending.task);
    final result = notifier.keepExternal();
    expect(await notifier.keepExternal(), isFalse);
    expect(await notifier.restoreManaged(), isFalse);
    notifier.select('copyActivation');
    expect(repository.resolvedSkillDrifts, hasLength(1));
    final warning = WorkspaceWarning(
      code: WorkspaceWarningCode.recoveryCleanupDeferred,
    );
    pending.progress.add(
      WorkspaceOperationProgress(
        operationId: 'drift-resolve',
        kind: WorkspaceOperationKind.resolveSkillDrift,
        phase: WorkspaceOperationPhase.applying,
        completed: 1,
        total: 2,
        warnings: [warning],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state().isBusy, isTrue);
    expect(state().operation.progress!.completed, 1);
    pending.completed.complete(
      WorkspaceCompleted(
        value: WorkspaceMutationReceipt(snapshot: repository.current),
        warnings: [warning],
      ),
    );
    expect(await result, isTrue);
    expect(state().operation.warnings, [warning]);
    expect(state().operation.running, isFalse);
    expect(
      container.read(appNotificationControllerProvider)!.notification.message,
      AppNotificationMessage.completedWithWarnings,
    );
  });

  test(
    'committed pending is success and registers root finalization recovery',
    () async {
      await selectCopy();
      final completion = DeferredDriftReviewTask<WorkspaceMutationReceipt>(
        WorkspaceOperationKind.resolveSkillDrift,
      );
      addTearDown(completion.dispose);
      final recovery = DeferredDriftReviewTask<SkillsWorkspaceSnapshot>(
        WorkspaceOperationKind.resumeFinalizationRecovery,
      );
      addTearDown(recovery.dispose);
      repository.resolveSkillDriftTasks.add(completion.task);
      repository.finalizationRecoveryTasks.add(recovery.task);
      final result = notifier.keepExternal();
      completion.completed.complete(
        WorkspaceCommittedPending(
          operationId: 'drift-committed',
          committedRevision: 7,
        ),
      );
      expect(await result, isTrue);
      expect(
        container
            .read(workspaceFinalizationCoordinatorProvider)
            .pendingOperationIds,
        contains('drift-committed'),
      );
      expect(repository.finalizationRecoveryCalls, 1);
      recovery.completed.complete(
        WorkspaceCompleted(value: repository.current),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(workspaceFinalizationCoordinatorProvider)
            .pendingOperationIds,
        isEmpty,
      );
    },
  );

  test(
    'disposed inspection ignores late completion and cancels its task',
    () async {
      final pending = DeferredDriftReviewTask<WorkspaceSkillDriftReview>(
        WorkspaceOperationKind.inspectSkillDrift,
      );
      addTearDown(pending.dispose);
      repository.inspectSkillDriftTasks
        ..clear()
        ..add(pending.task);
      final result = notifier.load();
      container.dispose();
      disposed = true;
      pending.completed.complete(WorkspaceCompleted(value: review));
      await result;
      expect(pending.cancellationCalls, 1);
    },
  );

  test(
    'disposed picker cannot initiate an export after the dialog closes',
    () async {
      final picker = DeferredDriftDirectoryPicker();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
          directoryPickerProvider.overrideWithValue(picker),
        ],
      );
      container.listen(provider, (_, _) {});
      notifier = container.read(provider.notifier);
      await selectCopy();
      final result = notifier.export('repositoryCopy');
      container.dispose();
      disposed = true;
      picker.completed.complete('/exports');
      await result;
      expect(repository.exportedSkillDriftArtifacts, isEmpty);
    },
  );

  test(
    'committed pending survives disposal of only the dialog notifier',
    () async {
      await selectCopy();
      final pending = DeferredDriftReviewTask<WorkspaceMutationReceipt>(
        WorkspaceOperationKind.resolveSkillDrift,
      );
      addTearDown(pending.dispose);
      final recovery = DeferredDriftReviewTask<SkillsWorkspaceSnapshot>(
        WorkspaceOperationKind.resumeFinalizationRecovery,
      );
      addTearDown(recovery.dispose);
      repository.resolveSkillDriftTasks.add(pending.task);
      repository.finalizationRecoveryTasks.add(recovery.task);
      final result = notifier.restoreManaged();
      container.invalidate(provider);
      pending.completed.complete(
        WorkspaceCommittedPending(
          operationId: 'late-commit',
          committedRevision: 7,
        ),
      );
      expect(await result, isTrue);
      expect(
        container
            .read(workspaceFinalizationCoordinatorProvider)
            .pendingOperationIds,
        contains('late-commit'),
      );
      recovery.completed.complete(
        WorkspaceCompleted(value: repository.current),
      );
      await Future<void>.delayed(Duration.zero);
    },
  );
}

SkillsWorkspaceSnapshot _pendingSnapshot() => SkillsWorkspaceSnapshot(
  revision: 7,
  projectRoots: const [],
  skills: [
    WorkspaceSkill(
      id: driftReviewSkillId,
      slotKey: 'sample',
      declaredName: 'sample',
      displayName: 'Sample',
      description: 'Sample',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/source',
      ),
      currentRevision: SkillRevision(
        contentHash: 'managed',
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime.utc(2026),
      ),
      activations: const [],
      integrity: WorkspaceSkillIntegrityStatus.driftPending,
    ),
  ],
);
