import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

import '../../support/fake_skills_workspace_repository.dart';

void main() {
  test('deduplicates operation IDs and serializes recovery commands', () async {
    final first = Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
    final second = Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
    final repository = FakeSkillsWorkspaceRepository()
      ..finalizationRecoveryTasks.addAll([
        _task('recovery-one', first.future),
        _task('recovery-two', second.future),
      ]);
    final container = _container(repository);
    addTearDown(container.dispose);
    final events = _recordEvents(container);
    final coordinator = container.read(
      workspaceFinalizationCoordinatorProvider.notifier,
    );
    final firstPending = WorkspaceCommittedPending<void>(
      operationId: 'operation-one',
      committedRevision: 3,
    );

    coordinator
      ..register(firstPending)
      ..register(firstPending)
      ..register(
        WorkspaceCommittedPending<void>(
          operationId: 'operation-two',
          committedRevision: 4,
        ),
      );
    await _eventually(() => repository.finalizationRecoveryCalls == 1);

    expect(
      events.where(
        (event) => event.kind == AppNotificationEventKind.taskStarted,
      ),
      hasLength(2),
    );
    expect(
      container
          .read(workspaceFinalizationCoordinatorProvider)
          .pendingOperationIds,
      {'operation-one', 'operation-two'},
    );

    first.complete(WorkspaceCompleted(value: _snapshot(3)));
    await _eventually(() => repository.finalizationRecoveryCalls == 2);
    expect(
      container
          .read(workspaceFinalizationCoordinatorProvider)
          .activeOperationId,
      'operation-two',
    );

    second.complete(WorkspaceCompleted(value: _snapshot(4)));
    await _eventually(
      () =>
          events
              .where(
                (event) => event.kind == AppNotificationEventKind.taskFinished,
              )
              .length ==
          2,
    );

    expect(
      events
          .where((event) => event.kind == AppNotificationEventKind.taskFinished)
          .map((event) => event.notification.message),
      [
        AppNotificationMessage.finalizationRecovered,
        AppNotificationMessage.finalizationRecovered,
      ],
    );
    expect(
      container
          .read(workspaceFinalizationCoordinatorProvider)
          .pendingOperationIds,
      isEmpty,
    );

    coordinator.register(firstPending);
    await Future<void>.delayed(Duration.zero);
    expect(repository.finalizationRecoveryCalls, 2);
  });

  test('finishes the task with the typed recovery failure', () async {
    final failure = WorkspaceFailure(
      code: WorkspaceErrorCode.finalizationRecoveryFailed,
      operation: WorkspaceOperationKind.resumeFinalizationRecovery,
    );
    final repository = FakeSkillsWorkspaceRepository()
      ..finalizationRecoveryTasks.add(
        _task(
          'recovery-failure',
          Future.value(WorkspaceFailed(failure: failure)),
        ),
      );
    final container = _container(repository);
    addTearDown(container.dispose);
    final events = _recordEvents(container);

    container
        .read(workspaceFinalizationCoordinatorProvider.notifier)
        .register(
          WorkspaceCommittedPending<void>(
            operationId: 'operation-failure',
            committedRevision: 8,
          ),
        );

    await _eventually(
      () => events.any(
        (event) => event.kind == AppNotificationEventKind.taskFinished,
      ),
    );
    final finished = events.singleWhere(
      (event) => event.kind == AppNotificationEventKind.taskFinished,
    );
    expect(finished.notification.failure, same(failure));
    expect(repository.finalizationRecoveryCalls, 1);
    final state = container.read(workspaceFinalizationCoordinatorProvider);
    expect(state.pendingOperationIds, {'operation-failure'});
    expect(state.failedOperationIds, {'operation-failure'});
    expect(state.canRetry, isTrue);
  });

  test(
    'deduplicates pending and recovery warnings at the terminal task',
    () async {
      final shared = WorkspaceWarning(
        code: WorkspaceWarningCode.finalizationDeferred,
        context: const {'path': 'shared'},
      );
      final cleanup = WorkspaceWarning(
        code: WorkspaceWarningCode.recoveryCleanupDeferred,
      );
      final repository = FakeSkillsWorkspaceRepository()
        ..finalizationRecoveryTasks.add(
          _task(
            'recovery-warning',
            Future.value(
              WorkspaceCompleted(
                value: _snapshot(5),
                warnings: [shared, cleanup],
              ),
            ),
          ),
        );
      final container = _container(repository);
      addTearDown(container.dispose);
      final events = _recordEvents(container);

      container
          .read(workspaceFinalizationCoordinatorProvider.notifier)
          .register(
            WorkspaceCommittedPending<void>(
              operationId: 'operation-warning',
              committedRevision: 5,
              warnings: [shared],
            ),
          );

      await _eventually(
        () => events.any(
          (event) => event.kind == AppNotificationEventKind.taskFinished,
        ),
      );
      final finished = events.singleWhere(
        (event) => event.kind == AppNotificationEventKind.taskFinished,
      );
      expect(finished.notification.severity, AppNotificationSeverity.warning);
      expect(
        finished.notification.message,
        AppNotificationMessage.completedWithWarnings,
      );
    },
  );

  test(
    'retains merged warnings while failed finalization awaits retry',
    () async {
      final pendingWarning = WorkspaceWarning(
        code: WorkspaceWarningCode.finalizationDeferred,
      );
      final recoveryWarning = WorkspaceWarning(
        code: WorkspaceWarningCode.recoveryCleanupDeferred,
      );
      final repository = FakeSkillsWorkspaceRepository()
        ..finalizationRecoveryTasks.add(
          _task(
            'recovery-warning-failure',
            Future.value(
              WorkspaceFailed(
                failure: WorkspaceFailure(
                  code: WorkspaceErrorCode.finalizationRecoveryFailed,
                  operation: WorkspaceOperationKind.resumeFinalizationRecovery,
                ),
                warnings: [recoveryWarning],
              ),
            ),
          ),
        );
      final container = _container(repository);
      addTearDown(container.dispose);
      final events = _recordEvents(container);

      container
          .read(workspaceFinalizationCoordinatorProvider.notifier)
          .register(
            WorkspaceCommittedPending<void>(
              operationId: 'operation-warning-failure',
              committedRevision: 6,
              warnings: [pendingWarning],
            ),
          );

      await _eventually(
        () => container
            .read(workspaceFinalizationCoordinatorProvider)
            .failedOperationIds
            .contains('operation-warning-failure'),
      );
      final state = container.read(workspaceFinalizationCoordinatorProvider);
      expect(
        state.warningsByOperationId['operation-warning-failure']?.map(
          (warning) => warning.code,
        ),
        [
          WorkspaceWarningCode.finalizationDeferred,
          WorkspaceWarningCode.recoveryCleanupDeferred,
        ],
      );
      final finished = events.lastWhere(
        (event) => event.kind == AppNotificationEventKind.taskFinished,
      );
      expect(
        finished.notification.failure?.warnings.map(
          (warning) => warning.codeKey,
        ),
        [
          WorkspaceWarningCode.finalizationDeferred.name,
          WorkspaceWarningCode.recoveryCleanupDeferred.name,
        ],
      );
    },
  );

  test(
    'retries a failed recovery without accepting a duplicate pending',
    () async {
      final firstFailure = WorkspaceFailure(
        code: WorkspaceErrorCode.finalizationRecoveryFailed,
        operation: WorkspaceOperationKind.resumeFinalizationRecovery,
      );
      final repository = FakeSkillsWorkspaceRepository()
        ..finalizationRecoveryTasks.addAll([
          _task(
            'recovery-first-attempt',
            Future.value(WorkspaceFailed(failure: firstFailure)),
          ),
          _task(
            'recovery-second-attempt',
            Future.value(WorkspaceCompleted(value: _snapshot(9))),
          ),
        ]);
      final container = _container(repository);
      addTearDown(container.dispose);
      final events = _recordEvents(container);
      final coordinator = container.read(
        workspaceFinalizationCoordinatorProvider.notifier,
      );
      var afterRecoveryCalls = 0;
      final pending = WorkspaceCommittedPending<void>(
        operationId: 'operation-retry',
        committedRevision: 9,
      );

      coordinator.register(
        pending,
        afterRecovery: () async {
          afterRecoveryCalls += 1;
          return true;
        },
      );
      await _eventually(
        () => container
            .read(workspaceFinalizationCoordinatorProvider)
            .failedOperationIds
            .contains('operation-retry'),
      );
      coordinator.register(pending);
      await Future<void>.delayed(Duration.zero);
      expect(repository.finalizationRecoveryCalls, 1);

      coordinator.retryFailed('operation-retry');
      await _eventually(
        () => container
            .read(workspaceFinalizationCoordinatorProvider)
            .pendingOperationIds
            .isEmpty,
      );

      expect(repository.finalizationRecoveryCalls, 2);
      expect(afterRecoveryCalls, 1);
      expect(
        events
            .where(
              (event) => event.kind == AppNotificationEventKind.taskStarted,
            )
            .length,
        2,
      );
      expect(
        events
            .where(
              (event) => event.kind == AppNotificationEventKind.taskFinished,
            )
            .map((event) => event.notification.message),
        [null, AppNotificationMessage.finalizationRecovered],
      );

      coordinator.register(pending);
      await Future<void>.delayed(Duration.zero);
      expect(repository.finalizationRecoveryCalls, 2);
      expect(afterRecoveryCalls, 1);
    },
  );

  test('post-finalization cleanup failure completes with a warning', () async {
    final repository = FakeSkillsWorkspaceRepository()
      ..finalizationRecoveryTasks.add(
        _task(
          'recovery-cleanup-warning',
          Future.value(WorkspaceCompleted(value: _snapshot(4))),
        ),
      );
    final container = _container(repository);
    addTearDown(container.dispose);
    final events = _recordEvents(container);

    container
        .read(workspaceFinalizationCoordinatorProvider.notifier)
        .register(
          WorkspaceCommittedPending<void>(
            operationId: 'operation-cleanup-warning',
            committedRevision: 4,
          ),
          afterRecovery: () async => false,
        );

    await _eventually(
      () => container
          .read(workspaceFinalizationCoordinatorProvider)
          .pendingOperationIds
          .isEmpty,
    );
    final finished = events.lastWhere(
      (event) => event.kind == AppNotificationEventKind.taskFinished,
    );
    expect(finished.notification.severity, AppNotificationSeverity.warning);
    expect(
      finished.notification.message,
      AppNotificationMessage.completedWithWarnings,
    );
  });

  test('rejects recovery that cannot publish the committed revision', () async {
    final repository = FakeSkillsWorkspaceRepository()
      ..finalizationRecoveryTasks.add(
        _task(
          'recovery-stale-snapshot',
          Future.value(WorkspaceCompleted(value: _snapshot(6))),
        ),
      );
    final container = _container(repository);
    addTearDown(container.dispose);
    final events = _recordEvents(container);

    container
        .read(workspaceFinalizationCoordinatorProvider.notifier)
        .register(
          WorkspaceCommittedPending<void>(
            operationId: 'operation-revision-seven',
            committedRevision: 7,
          ),
        );

    await _eventually(
      () => events.any(
        (event) => event.kind == AppNotificationEventKind.taskFinished,
      ),
    );
    final failure = events
        .singleWhere(
          (event) => event.kind == AppNotificationEventKind.taskFinished,
        )
        .notification
        .failure;
    expect(
      failure?.codeKey,
      WorkspaceErrorCode.finalizationRecoveryFailed.name,
    );
    expect(failure?.context['committedRevision'], 7);
    expect(failure?.context['observedRevision'], 6);
    expect(
      container
          .read(workspaceFinalizationCoordinatorProvider)
          .failedOperationIds,
      {'operation-revision-seven'},
    );
  });
}

ProviderContainer _container(FakeSkillsWorkspaceRepository repository) =>
    ProviderContainer(
      overrides: [
        skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
      ],
    );

List<AppNotificationEvent> _recordEvents(ProviderContainer container) {
  final events = <AppNotificationEvent>[];
  container.listen(appNotificationControllerProvider, (_, next) {
    if (next != null) events.add(next);
  });
  return events;
}

WorkspaceTask<SkillsWorkspaceSnapshot> _task(
  String operationId,
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> completion,
) => WorkspaceTask(
  current: WorkspaceOperationProgress(
    operationId: operationId,
    kind: WorkspaceOperationKind.resumeFinalizationRecovery,
    phase: WorkspaceOperationPhase.finalizing,
  ),
  states: const Stream.empty(),
  completed: completion,
  cancel: () async {},
);

SkillsWorkspaceSnapshot _snapshot(int revision) => SkillsWorkspaceSnapshot(
  revision: revision,
  projectRoots: const [],
  skills: const [],
);

Future<void> _eventually(bool Function() predicate) async {
  for (var index = 0; index < 50; index++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition did not become true.');
}
