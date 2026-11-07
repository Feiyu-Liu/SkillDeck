import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/project_roots_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

import '../../../../support/fake_skills_workspace_repository.dart';

void main() {
  test(
    'register publishes one success event without writing a Browser catalog',
    () async {
      final workspace = FakeSkillsWorkspaceRepository();
      final container = _container(workspace);
      addTearDown(container.dispose);
      final subscription = container.listen(
        projectRootsViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await container
          .read(projectRootsViewModelProvider.notifier)
          .register('/workspace/project');

      final state = container.read(projectRootsViewModelProvider);
      expect(state.busy, isFalse);
      expect(state.failure, isNull);
      expect(state.operation.running, isFalse);
      expect(workspace.registrations.single.path, '/workspace/project');
      final event = container.read(appNotificationControllerProvider)!;
      expect(event.sequence, 1);
      expect(event.notification.severity, AppNotificationSeverity.success);
      expect(
        event.notification.message,
        AppNotificationMessage.projectRootRegistered,
      );
    },
  );

  test('unregister keeps a typed inline failure and publishes it', () async {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.projectRootNotFound,
      operation: WorkspaceOperationKind.unregisterProjectRoot,
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 1,
        projectRoots: const [
          SkillProjectRoot(id: 'project-1', path: '/workspace/project'),
        ],
        skills: const [],
      ),
    )..unregisterError = failure;
    final container = _container(workspace);
    addTearDown(container.dispose);
    final subscription = container.listen(
      projectRootsViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container
        .read(projectRootsViewModelProvider.notifier)
        .unregister('project-1');

    final state = container.read(projectRootsViewModelProvider);
    expect(state.busy, isFalse);
    expect(state.failure, same(failure));
    expect(workspace.unregistrations, ['project-1']);
    final notification = container
        .read(appNotificationControllerProvider)!
        .notification;
    expect(notification.severity, AppNotificationSeverity.error);
    expect(notification.failure, same(failure));
  });

  test('cancellation publishes info without an inline failure', () async {
    final workspace = FakeSkillsWorkspaceRepository()
      ..registerError = WorkspaceException(
        code: WorkspaceErrorCode.operationCancelled,
        operation: WorkspaceOperationKind.registerProjectRoot,
      );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final subscription = container.listen(
      projectRootsViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container
        .read(projectRootsViewModelProvider.notifier)
        .register('/workspace/project');

    expect(container.read(projectRootsViewModelProvider).failure, isNull);
    final notification = container
        .read(appNotificationControllerProvider)!
        .notification;
    expect(notification.severity, AppNotificationSeverity.info);
    expect(notification.message, AppNotificationMessage.operationCancelled);
  });
}

ProviderContainer _container(FakeSkillsWorkspaceRepository workspace) =>
    ProviderContainer(
      overrides: [
        skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
      ],
    );
