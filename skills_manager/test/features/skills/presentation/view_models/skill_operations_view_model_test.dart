import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';

import '../../../../support/fake_app_translation_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/recording_app_diagnostic_sink.dart';

void main() {
  test('activation requests carry the global activation method', () async {
    final workspace = FakeSkillsWorkspaceRepository();
    final container = _container(
      workspace,
      activationMethod: WorkspaceActivationMethod.copy,
    );
    addTearDown(container.dispose);
    const target = WorkspaceActivationTarget(
      agentId: 'codex',
      displayName: 'Codex',
      detected: true,
      location: '/activation/alpha',
      scope: WorkspaceScope.global,
    );

    await container
        .read(skillOperationsViewModelProvider.notifier)
        .setActivation(
          skillId: _alphaId,
          target: target,
          active: true,
          onTakeoverRequired: _unexpectedTakeover,
        );

    expect(
      workspace.activations.single.activationMethod,
      WorkspaceActivationMethod.copy,
    );
  });

  test('activation changes publish one typed success event each', () async {
    final workspace = FakeSkillsWorkspaceRepository();
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(skillOperationsViewModelProvider.notifier);
    const target = WorkspaceActivationTarget(
      agentId: 'codex',
      displayName: 'Codex',
      detected: true,
      location: '/activation/alpha',
      scope: WorkspaceScope.global,
    );

    final activated = await viewModel.setActivation(
      skillId: _alphaId,
      target: target,
      active: true,
      onTakeoverRequired: _unexpectedTakeover,
    );
    expect(activated, SetActivationOutcome.completed);

    var event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 1);
    expect(event.notification.severity, AppNotificationSeverity.success);
    expect(
      event.notification.message,
      AppNotificationMessage.activationEnabled,
    );

    final deactivated = await viewModel.setActivation(
      skillId: _alphaId,
      target: target,
      active: false,
      onTakeoverRequired: _unexpectedTakeover,
    );
    expect(deactivated, SetActivationOutcome.completed);

    event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 2);
    expect(
      event.notification.message,
      AppNotificationMessage.activationDisabled,
    );
  });

  test(
    'failed activation returns failed outcome and publishes failure',
    () async {
      final failure = WorkspaceException(
        code: WorkspaceErrorCode.activationUnavailable,
        operation: WorkspaceOperationKind.activate,
      );
      final workspace = FakeSkillsWorkspaceRepository()
        ..activateError = failure;
      final container = _container(workspace);
      addTearDown(container.dispose);

      final succeeded = await container
          .read(skillOperationsViewModelProvider.notifier)
          .setActivation(
            skillId: _alphaId,
            target: const WorkspaceActivationTarget(
              agentId: 'codex',
              displayName: 'Codex',
              detected: true,
              location: '/activation/alpha',
              scope: WorkspaceScope.global,
            ),
            active: true,
            onTakeoverRequired: _unexpectedTakeover,
          );

      expect(succeeded, SetActivationOutcome.failed);
      expect(
        container.read(appNotificationControllerProvider)!.notification.failure,
        same(failure),
      );
    },
  );

  test('takeover cancellation keeps the target unchanged and silent', () async {
    final draft = FakeWorkspaceActivationTakeoverDraft(
      expectedRevision: 4,
      targets: [
        WorkspaceOccupiedActivationTarget(
          slotKey: 'alpha',
          location: '/activation',
          targetPath: '/activation/alpha',
          agentIds: const ['codex'],
          kind: WorkspaceActivationTargetOccupancyKind.skillDirectory,
          contentRelation:
              WorkspaceActivationContentRelation.differsFromCurrentRevision,
        ),
      ],
    );
    final workspace = FakeSkillsWorkspaceRepository()
      ..activateAttempt = WorkspaceActivationTakeoverRequired(draft);
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(skillOperationsViewModelProvider.notifier);
    final confirmationRequested = Completer<void>();
    final confirmationDecision = Completer<bool>();

    final pendingOutcome = viewModel.setActivation(
      skillId: _alphaId,
      target: const WorkspaceActivationTarget(
        agentId: 'codex',
        displayName: 'Codex',
        detected: true,
        location: '/activation',
        scope: WorkspaceScope.global,
      ),
      active: true,
      onTakeoverRequired: (receivedDraft) {
        expect(receivedDraft, same(draft));
        confirmationRequested.complete();
        return confirmationDecision.future;
      },
    );
    await confirmationRequested.future;

    expect(
      container
          .read(skillOperationsViewModelProvider)
          .isActivationBusy(_alphaId, '/activation'),
      isTrue,
    );
    expect(container.read(appNotificationControllerProvider), isNull);
    expect(workspace.confirmedTakeovers, isEmpty);

    confirmationDecision.complete(false);
    expect(await pendingOutcome, SetActivationOutcome.cancelled);
    expect(
      container.read(skillOperationsViewModelProvider).busyActivations,
      isEmpty,
    );
    expect(workspace.confirmedTakeovers, isEmpty);
    expect(container.read(appNotificationControllerProvider), isNull);
  });

  test(
    'takeover confirmation completes activation and publishes success',
    () async {
      final draft = _takeoverDraft();
      final workspace = FakeSkillsWorkspaceRepository()
        ..activateAttempt = WorkspaceActivationTakeoverRequired(draft);
      final container = _container(workspace);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillOperationsViewModelProvider.notifier,
      );

      final outcome = await viewModel.setActivation(
        skillId: _alphaId,
        target: const WorkspaceActivationTarget(
          agentId: 'codex',
          displayName: 'Codex',
          detected: true,
          location: '/activation',
          scope: WorkspaceScope.global,
        ),
        active: true,
        onTakeoverRequired: (_) async => true,
      );

      expect(outcome, SetActivationOutcome.completed);
      expect(workspace.confirmedTakeovers, [same(draft)]);
      expect(
        container.read(appNotificationControllerProvider)!.notification.message,
        AppNotificationMessage.activationEnabled,
      );
      expect(
        container.read(skillOperationsViewModelProvider).busyActivations,
        isEmpty,
      );
    },
  );

  test('failed takeover confirmation publishes the typed failure', () async {
    final draft = _takeoverDraft();
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.staleActivationTakeover,
      operation: WorkspaceOperationKind.confirmActivationTakeover,
    );
    final workspace = FakeSkillsWorkspaceRepository()
      ..activateAttempt = WorkspaceActivationTakeoverRequired(draft)
      ..confirmActivationTakeoverError = failure;
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(skillOperationsViewModelProvider.notifier);

    final outcome = await viewModel.setActivation(
      skillId: _alphaId,
      target: const WorkspaceActivationTarget(
        agentId: 'codex',
        displayName: 'Codex',
        detected: true,
        location: '/activation',
        scope: WorkspaceScope.global,
      ),
      active: true,
      onTakeoverRequired: (_) async => true,
    );

    expect(outcome, SetActivationOutcome.failed);
    expect(workspace.confirmedTakeovers, [same(draft)]);
    expect(
      container.read(appNotificationControllerProvider)!.notification.failure,
      same(failure),
    );
    expect(
      container.read(skillOperationsViewModelProvider).busyActivations,
      isEmpty,
    );
  });

  test(
    'update failure publishes a typed failure without blocking UI',
    () async {
      final failure = WorkspaceException(
        code: WorkspaceErrorCode.sourceUnavailable,
        operation: WorkspaceOperationKind.update,
      );
      final workspace = FakeSkillsWorkspaceRepository()..updateError = failure;
      final container = _container(workspace);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillOperationsViewModelProvider.notifier,
      );

      await viewModel.update(_alphaId);

      final event = container.read(appNotificationControllerProvider)!;
      expect(event.sequence, 1);
      expect(event.notification.severity, AppNotificationSeverity.error);
      expect(event.notification.failure, same(failure));
      expect(container.read(skillOperationsViewModelProvider).error, isNull);
    },
  );

  test('unknown update failure is normalized without raw details', () async {
    final workspace = FakeSkillsWorkspaceRepository();
    final completer =
        Completer<WorkspaceCompletion<WorkspaceMutationReceipt>>();
    workspace.updateTask = WorkspaceTask(
      current: _progress(
        WorkspaceOperationKind.update,
        WorkspaceOperationPhase.applying,
      ),
      states: const Stream.empty(),
      completed: completer.future,
      cancel: () async {},
    );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(skillOperationsViewModelProvider.notifier);

    final update = viewModel.update(_alphaId);
    completer.completeError(StateError('secret=/private/repository'));
    await update;

    final failure = container
        .read(appNotificationControllerProvider)!
        .notification
        .failure!;
    expect(failure, isA<UnexpectedAppFailure>());
    expect(failure.operationKey, WorkspaceOperationKind.update.name);
    expect(failure.context, isEmpty);
    expect(failure.toString(), isNot(contains('secret')));
    expect(failure.toString(), isNot(contains('/private')));
  });

  test('completed update with warnings publishes one warning event', () async {
    final workspace = FakeSkillsWorkspaceRepository();
    final warning = WorkspaceWarning(
      code: WorkspaceWarningCode.activationTargetSkipped,
    );
    workspace.updateTask = WorkspaceTask(
      current: _progress(
        WorkspaceOperationKind.update,
        WorkspaceOperationPhase.succeeded,
        warnings: [warning],
      ),
      states: const Stream.empty(),
      completed: Future.value(
        WorkspaceCompleted(
          value: WorkspaceMutationReceipt(
            snapshot: workspace.current,
            affectedSkillIds: {_alphaId},
          ),
        ),
      ),
      cancel: () async {},
    );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(skillOperationsViewModelProvider.notifier);

    await viewModel.update(_alphaId);

    final event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 1);
    expect(event.notification.severity, AppNotificationSeverity.warning);
    expect(
      event.notification.message,
      AppNotificationMessage.completedWithWarnings,
    );
    expect(
      container.read(skillOperationsViewModelProvider).operation.warnings,
      [warning],
    );
  });

  test('cancelled update publishes info instead of an error', () async {
    final workspace =
        FakeSkillsWorkspaceRepository(
            snapshot: SkillsWorkspaceSnapshot(
              revision: 13,
              projectRoots: const [],
              skills: const [],
            ),
          )
          ..updateError = WorkspaceException(
            code: WorkspaceErrorCode.operationCancelled,
            operation: WorkspaceOperationKind.update,
          );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(skillOperationsViewModelProvider.notifier);

    await viewModel.update(_alphaId);

    final event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 1);
    expect(event.notification.severity, AppNotificationSeverity.info);
    expect(
      event.notification.message,
      AppNotificationMessage.operationCancelled,
    );
    expect(event.notification.failure, isNull);
  });

  test('an explicitly requested check reports its failure once', () async {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.sourceUnavailable,
      operation: WorkspaceOperationKind.checkUpdates,
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWithAlpha(revision: 1),
    )..checkUpdatesError = failure;
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);
    final viewModel = container.read(skillOperationsViewModelProvider.notifier);

    final settled = await viewModel.checkUpdate(_alphaId);

    expect(settled, isA<SkillUpdateCheckFailed>());
    expect((settled as SkillUpdateCheckFailed).failure, same(failure));
    expect(
      container.read(skillUpdateStatusProvider).stateOf(_alphaId),
      same(settled),
    );
    // The checking toast resolves into the failure rather than leaving the
    // press with no visible outcome. The old guard returned silently and
    // produced neither event.
    final event = container.read(appNotificationControllerProvider)!;
    expect(event.kind, AppNotificationEventKind.taskFinished);
    expect(event.notification.severity, AppNotificationSeverity.error);
    expect(event.notification.failure, same(failure));
    expect(event.sequence, 2);
  });

  test('a settled check resolves its toast into the outcome', () async {
    for (final (status, severity, message) in [
      (
        WorkspaceUpdateStatus.current,
        AppNotificationSeverity.success,
        AppNotificationMessage.updateCheckCurrent,
      ),
      (
        WorkspaceUpdateStatus.updateAvailable,
        AppNotificationSeverity.success,
        AppNotificationMessage.updateCheckAvailable,
      ),
      (
        WorkspaceUpdateStatus.sourceUnavailable,
        AppNotificationSeverity.warning,
        AppNotificationMessage.updateCheckUnavailable,
      ),
      (
        WorkspaceUpdateStatus.updateUnsupported,
        AppNotificationSeverity.info,
        AppNotificationMessage.updateCheckUnsupported,
      ),
    ]) {
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: _snapshotWithAlpha(revision: 1),
        updateReports: [
          WorkspaceUpdateReport(skillId: _alphaId, status: status),
        ],
      );
      final container = _container(workspace);
      addTearDown(container.dispose);
      await container.read(workspaceSnapshotProvider.future);

      await container
          .read(skillOperationsViewModelProvider.notifier)
          .checkUpdate(_alphaId);

      final event = container.read(appNotificationControllerProvider)!;
      expect(
        event.kind,
        AppNotificationEventKind.taskFinished,
        reason: '$status',
      );
      expect(event.notification.severity, severity, reason: '$status');
      expect(event.notification.message, message, reason: '$status');
    }
  });

  test(
    'a resolution-required check reports with no network round trip',
    () async {
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: _snapshotWithAlpha(
          revision: 1,
          updateCandidate: WorkspaceUpdateCandidateSummary(
            status: WorkspaceUpdateCandidateStatus.conflicted,
            conflictPaths: const ['SKILL.md'],
            createdAt: DateTime.utc(2026),
          ),
        ),
      );
      final container = _container(workspace);
      addTearDown(container.dispose);
      await container.read(workspaceSnapshotProvider.future);

      await container
          .read(skillOperationsViewModelProvider.notifier)
          .checkUpdate(_alphaId);

      expect(workspace.checkUpdatesCalls, 0);
      final event = container.read(appNotificationControllerProvider)!;
      expect(event.kind, AppNotificationEventKind.taskFinished);
      expect(event.notification.severity, AppNotificationSeverity.warning);
      expect(
        event.notification.message,
        AppNotificationMessage.updateCheckResolutionRequired,
      );
    },
  );

  test('successful removal deletes the reviewed Skill cache slot', () async {
    final cache = MemoryTranslationCache();
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWithAlpha(revision: 3),
    );
    final container = _container(
      workspace,
      translationRepository: fakeAppTranslationRepository(cache: cache),
    );
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);

    final outcome = await container
        .read(skillOperationsViewModelProvider.notifier)
        .remove(skillId: _alphaId, reviewedRevision: 3);

    expect(outcome, RemoveSkillOutcome.removed);
    expect(cache.deletedSlotKeys, ['alpha-slot']);
    expect(
      container.read(appNotificationControllerProvider)!.notification.message,
      AppNotificationMessage.skillRemoved,
    );
  });

  test('cache cleanup failure keeps removal committed and warns', () async {
    final cache = MemoryTranslationCache()
      ..deleteSlotError = StateError('cache cleanup failed');
    final diagnostics = RecordingAppDiagnosticSink();
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWithAlpha(revision: 3),
    );
    final container = _container(
      workspace,
      translationRepository: fakeAppTranslationRepository(cache: cache),
      diagnostics: AppDiagnostics(sink: diagnostics),
    );
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);

    final outcome = await container
        .read(skillOperationsViewModelProvider.notifier)
        .remove(skillId: _alphaId, reviewedRevision: 3);

    expect(outcome, RemoveSkillOutcome.removed);
    expect(cache.deletedSlotKeys, ['alpha-slot']);
    expect(
      container.read(appNotificationControllerProvider)!.notification.message,
      AppNotificationMessage.completedWithWarnings,
    );
    expect(diagnostics.events, hasLength(1));
    expect(
      diagnostics.events.single.operationKey,
      'deleteSkillTranslationCache',
    );
    expect(diagnostics.events.single.context, isEmpty);
  });

  test('cache cleanup survives disposal of the operations ViewModel', () async {
    final completion =
        Completer<WorkspaceCompletion<WorkspaceMutationReceipt>>();
    final cache = MemoryTranslationCache();
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWithAlpha(revision: 3),
    )..removeTask = _removeTask(completion.future);
    final container = _container(
      workspace,
      translationRepository: fakeAppTranslationRepository(cache: cache),
    );
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);

    final removal = container
        .read(skillOperationsViewModelProvider.notifier)
        .remove(skillId: _alphaId, reviewedRevision: 3);
    await _eventually(() => workspace.removals.isNotEmpty);
    container.invalidate(skillOperationsViewModelProvider);
    completion.complete(
      WorkspaceCompleted(value: _removalReceipt(revision: 4)),
    );

    expect(await removal, RemoveSkillOutcome.removed);
    expect(cache.deletedSlotKeys, ['alpha-slot']);
  });

  test('pending removal cleans the cache only after recovery', () async {
    final recovery = Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
    final cache = MemoryTranslationCache();
    final workspace =
        FakeSkillsWorkspaceRepository(snapshot: _snapshotWithAlpha(revision: 3))
          ..removeTask = _removeTask(
            Future.value(
              WorkspaceCommittedPending<WorkspaceMutationReceipt>(
                operationId: 'remove-pending',
                committedRevision: 4,
              ),
            ),
          )
          ..finalizationRecoveryTasks.add(
            WorkspaceTask(
              current: _progress(
                WorkspaceOperationKind.resumeFinalizationRecovery,
                WorkspaceOperationPhase.recovering,
              ),
              states: const Stream.empty(),
              completed: recovery.future,
              cancel: () async {},
            ),
          );
    final container = _container(
      workspace,
      translationRepository: fakeAppTranslationRepository(cache: cache),
    );
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);

    final outcome = await container
        .read(skillOperationsViewModelProvider.notifier)
        .remove(skillId: _alphaId, reviewedRevision: 3);

    expect(outcome, RemoveSkillOutcome.pending);
    expect(cache.deletedSlotKeys, isEmpty);
    await _eventually(() => workspace.finalizationRecoveryCalls == 1);
    recovery.complete(
      WorkspaceCompleted(
        value: SkillsWorkspaceSnapshot(
          revision: 4,
          projectRoots: const [],
          skills: const [],
        ),
      ),
    );
    await _eventually(() => cache.deletedSlotKeys.isNotEmpty);

    expect(cache.deletedSlotKeys, ['alpha-slot']);
  });

  test('remove failure is notified and returned as a typed outcome', () async {
    final cache = MemoryTranslationCache();
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.ioFailure,
      operation: WorkspaceOperationKind.remove,
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWithAlpha(revision: 3),
    )..removeError = failure;
    final container = _container(
      workspace,
      translationRepository: fakeAppTranslationRepository(cache: cache),
    );
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);
    final viewModel = container.read(skillOperationsViewModelProvider.notifier);

    final outcome = await viewModel.remove(
      skillId: _alphaId,
      reviewedRevision: 3,
    );

    expect(outcome, RemoveSkillOutcome.failed);

    final event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 1);
    expect(event.notification.severity, AppNotificationSeverity.error);
    expect(event.notification.failure, same(failure));
    expect(cache.deletedSlotKeys, isEmpty);
  });

  test('cancelled removal does not delete the cache slot', () async {
    final cache = MemoryTranslationCache();
    final workspace =
        FakeSkillsWorkspaceRepository(snapshot: _snapshotWithAlpha(revision: 3))
          ..removeError = WorkspaceException(
            code: WorkspaceErrorCode.operationCancelled,
            operation: WorkspaceOperationKind.remove,
          );
    final container = _container(
      workspace,
      translationRepository: fakeAppTranslationRepository(cache: cache),
    );
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);

    final outcome = await container
        .read(skillOperationsViewModelProvider.notifier)
        .remove(skillId: _alphaId, reviewedRevision: 3);

    expect(outcome, RemoveSkillOutcome.cancelled);
    expect(cache.deletedSlotKeys, isEmpty);
  });

  test('unreviewed snapshot refreshes without submitting removal', () async {
    final cache = MemoryTranslationCache();
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWithAlpha(revision: 4),
    );
    final container = _container(
      workspace,
      translationRepository: fakeAppTranslationRepository(cache: cache),
    );
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);

    final outcome = await container
        .read(skillOperationsViewModelProvider.notifier)
        .remove(skillId: _alphaId, reviewedRevision: 3);

    expect(outcome, RemoveSkillOutcome.stale);
    expect(workspace.removals, isEmpty);
    expect(workspace.refreshCalls, 1);
    expect(cache.deletedSlotKeys, isEmpty);
  });

  test(
    'stale removal refreshes silently and requires a new revision',
    () async {
      final workspace =
          FakeSkillsWorkspaceRepository(
              snapshot: _snapshotWithAlpha(revision: 7),
            )
            ..refreshSnapshot = _snapshotWithAlpha(revision: 8)
            ..removeError = WorkspaceException(
              code: WorkspaceErrorCode.staleSnapshot,
              operation: WorkspaceOperationKind.remove,
              context: const {'expectedRevision': 7, 'actualRevision': 8},
            );
      final container = _container(workspace);
      addTearDown(container.dispose);
      await container.read(workspaceSnapshotProvider.future);
      final viewModel = container.read(
        skillOperationsViewModelProvider.notifier,
      );

      final stale = await viewModel.remove(
        skillId: _alphaId,
        reviewedRevision: 7,
      );

      expect(stale, RemoveSkillOutcome.stale);
      expect(workspace.refreshCalls, 1);
      expect(container.read(appNotificationControllerProvider), isNull);

      workspace.removeError = null;
      final removed = await viewModel.remove(
        skillId: _alphaId,
        reviewedRevision: 8,
      );

      expect(removed, RemoveSkillOutcome.removed);
      expect(workspace.removals.map((request) => request.expectedRevision), [
        7,
        8,
      ]);
      final event = container.read(appNotificationControllerProvider)!;
      expect(event.sequence, 1);
      expect(event.notification.severity, AppNotificationSeverity.success);
      expect(event.notification.message, AppNotificationMessage.skillRemoved);
    },
  );

  test(
    'replace source forwards all supported source kinds and reviewed revision',
    () async {
      final workspace = FakeSkillsWorkspaceRepository();
      final container = _container(workspace);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillOperationsViewModelProvider.notifier,
      );

      final sources = <SkillSourceInput>[
        const SkillSourceInput(
          kind: WorkspaceSourceKind.local,
          locator: '/tmp/new-alpha',
        ),
        const SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://github.com/example/skills.git',
          ref: 'main',
          repositorySubpath: 'skills/alpha',
        ),
        const SkillSourceInput(
          kind: WorkspaceSourceKind.wellKnown,
          locator: 'https://example.com/.well-known/agent-skills/index.json',
        ),
      ];
      for (final source in sources) {
        final outcome = await viewModel.replaceSource(
          skillId: _alphaId,
          source: source,
          expectedRevision: 12,
        );
        expect(outcome, ReplaceSourceOutcome.replaced);
      }

      expect(workspace.replaceSourceRequests, hasLength(3));
      expect(
        workspace.replaceSourceRequests.map((request) => request.source.kind),
        [
          WorkspaceSourceKind.local,
          WorkspaceSourceKind.git,
          WorkspaceSourceKind.wellKnown,
        ],
      );
      final request = workspace.replaceSourceRequests[1];
      expect(request.slotKey, 'alpha');
      expect(request.expectedRevision, 12);
      expect(request.source.locator, contains('github.com/example/skills.git'));
      expect(request.source.ref, 'main');
      expect(request.source.repositorySubpath, 'skills/alpha');
      expect(
        container.read(appNotificationControllerProvider)!.notification.message,
        AppNotificationMessage.skillUpdated,
      );
    },
  );

  test(
    'replace source maps stale revision to refresh without success',
    () async {
      final workspace =
          FakeSkillsWorkspaceRepository(
              snapshot: SkillsWorkspaceSnapshot(
                revision: 13,
                projectRoots: const [],
                skills: const [],
              ),
            )
            ..replaceSourceError = WorkspaceException(
              code: WorkspaceErrorCode.staleSnapshot,
              operation: WorkspaceOperationKind.replaceSource,
              context: const {'expectedRevision': 12, 'actualRevision': 13},
            );
      final container = _container(workspace);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillOperationsViewModelProvider.notifier,
      );

      final outcome = await viewModel.replaceSource(
        skillId: _alphaId,
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.local,
          locator: '/tmp/new-alpha',
        ),
        expectedRevision: 12,
      );

      expect(outcome, ReplaceSourceOutcome.stale);
      // Refreshing the catalog is a page-level concern. The view model only
      // maps the Core stale outcome so the caller can re-read the revision and
      // explicitly confirm the replacement again.
      expect(workspace.refreshCalls, 0);
      expect(container.read(appNotificationControllerProvider), isNull);
    },
  );

  test(
    'replace source failure publishes an error and preserves request state',
    () async {
      final failure = WorkspaceException(
        code: WorkspaceErrorCode.sourceUnavailable,
        operation: WorkspaceOperationKind.replaceSource,
      );
      final workspace = FakeSkillsWorkspaceRepository()
        ..replaceSourceError = failure;
      final container = _container(workspace);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillOperationsViewModelProvider.notifier,
      );

      final outcome = await viewModel.replaceSource(
        skillId: _alphaId,
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.wellKnown,
          locator: 'https://example.com/.well-known/agent-skills/index.json',
        ),
        expectedRevision: 4,
      );

      expect(outcome, isNull);
      expect(workspace.current.skills, isEmpty);
      expect(workspace.current.revision, 0);
      final notification = container
          .read(appNotificationControllerProvider)!
          .notification;
      expect(notification.severity, AppNotificationSeverity.error);
      expect(notification.failure, same(failure));
    },
  );
}

ProviderContainer _container(
  FakeSkillsWorkspaceRepository workspace, {
  AppTranslationRepository? translationRepository,
  AppDiagnostics? diagnostics,
  WorkspaceActivationMethod activationMethod =
      WorkspaceActivationMethod.automatic,
}) {
  return ProviderContainer(
    overrides: [
      skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
      globalActivationMethodProvider.overrideWithValue(activationMethod),
      appTranslationRepositoryProvider.overrideWithValue(
        translationRepository ?? fakeAppTranslationRepository(),
      ),
      if (diagnostics != null)
        appDiagnosticsProvider.overrideWithValue(diagnostics),
    ],
  );
}

SkillsWorkspaceSnapshot _snapshotWithAlpha({
  required int revision,
  WorkspaceUpdateCandidateSummary? updateCandidate,
}) => SkillsWorkspaceSnapshot(
  revision: revision,
  projectRoots: const [],
  skills: [
    WorkspaceSkill(
      id: _alphaId,
      slotKey: 'alpha-slot',
      declaredName: 'alpha',
      displayName: 'Alpha',
      description: 'Alpha description',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/source/alpha',
      ),
      currentRevision: SkillRevision(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime(2026),
        resolvedSourceRevision: 'local',
      ),
      activations: const [],
      updateCandidate: updateCandidate,
    ),
  ],
);

WorkspaceMutationReceipt _removalReceipt({required int revision}) =>
    WorkspaceMutationReceipt(
      snapshot: SkillsWorkspaceSnapshot(
        revision: revision,
        projectRoots: const [],
        skills: const [],
      ),
      affectedSkillIds: {_alphaId},
    );

WorkspaceTask<WorkspaceMutationReceipt> _removeTask(
  Future<WorkspaceCompletion<WorkspaceMutationReceipt>> completion,
) => WorkspaceTask(
  current: _progress(
    WorkspaceOperationKind.remove,
    WorkspaceOperationPhase.applying,
  ),
  states: const Stream.empty(),
  completed: completion,
  cancel: () async {},
);

WorkspaceOperationProgress _progress(
  WorkspaceOperationKind kind,
  WorkspaceOperationPhase phase, {
  List<WorkspaceWarning> warnings = const [],
}) => WorkspaceOperationProgress(
  operationId: 'test-${kind.name}',
  kind: kind,
  phase: phase,
  warnings: warnings,
);

Future<bool> _unexpectedTakeover(WorkspaceActivationTakeoverDraft draft) =>
    Future.error(
      StateError(
        'Unexpected activation takeover for ${draft.targets.length} target(s)',
      ),
    );

final _alphaId = WorkspaceSkillId('alpha');

Future<void> _eventually(bool Function() predicate) async {
  for (var index = 0; index < 50; index++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition did not become true.');
}

FakeWorkspaceActivationTakeoverDraft _takeoverDraft() =>
    FakeWorkspaceActivationTakeoverDraft(
      expectedRevision: 4,
      targets: [
        WorkspaceOccupiedActivationTarget(
          slotKey: 'alpha',
          location: '/activation',
          targetPath: '/activation/alpha',
          agentIds: const ['codex'],
          kind: WorkspaceActivationTargetOccupancyKind.skillDirectory,
          contentRelation:
              WorkspaceActivationContentRelation.differsFromCurrentRevision,
        ),
      ],
    );
