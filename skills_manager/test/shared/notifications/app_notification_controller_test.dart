import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

void main() {
  test('publishes every notification as a uniquely sequenced event', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      appNotificationControllerProvider.notifier,
    );
    final events = <AppNotificationEvent>[];
    final subscription = container.listen(appNotificationControllerProvider, (
      _,
      next,
    ) {
      if (next != null) events.add(next);
    });
    addTearDown(subscription.close);

    controller
      ..info(AppNotificationMessage.operationCancelled)
      ..success(AppNotificationMessage.repositoryRefreshed)
      ..warning(AppNotificationMessage.completedWithWarnings)
      ..error(AppNotificationMessage.translationFailed)
      ..failure(
        StateError('/private/path?token=secret'),
        operationKey: 'refreshRepository',
      );

    expect(events.map((event) => event.sequence), [1, 2, 3, 4, 5]);
    expect(events.map((event) => event.notification.severity), [
      AppNotificationSeverity.info,
      AppNotificationSeverity.success,
      AppNotificationSeverity.warning,
      AppNotificationSeverity.error,
      AppNotificationSeverity.error,
    ]);
    expect(events.last.notification.failure?.context, isEmpty);
    expect(
      events.last.notification.failure.toString(),
      isNot(contains('secret')),
    );
  });

  test('task handle publishes one id and ignores events after termination', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      appNotificationControllerProvider.notifier,
    );
    final events = <AppNotificationEvent>[];
    final subscription = container.listen(appNotificationControllerProvider, (
      _,
      next,
    ) {
      if (next != null) events.add(next);
    });
    addTearDown(subscription.close);

    final task = controller.startTask(
      const AppNotification.message(
        severity: AppNotificationSeverity.info,
        message: AppNotificationMessage.translationStarted,
      ),
    );
    task.update(
      const AppNotification.message(
        severity: AppNotificationSeverity.info,
        message: AppNotificationMessage.translationProgress,
        progress: AppNotificationProgress(completed: 2, total: 5),
      ),
    );
    task.finish(
      const AppNotification.message(
        severity: AppNotificationSeverity.success,
        message: AppNotificationMessage.translationCompleted,
      ),
    );
    task
      ..update(
        const AppNotification.message(
          severity: AppNotificationSeverity.info,
          message: AppNotificationMessage.translationProgress,
        ),
      )
      ..dismiss();

    expect(events.map((event) => event.kind), [
      AppNotificationEventKind.taskStarted,
      AppNotificationEventKind.taskUpdated,
      AppNotificationEventKind.taskFinished,
    ]);
    expect(events.map((event) => event.taskId).toSet(), hasLength(1));
    expect(events.first.taskId, isNotNull);
    expect(events[1].notification.progress?.fraction, 0.4);
  });

  test('task dismissal is explicit and idempotent', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      appNotificationControllerProvider.notifier,
    );
    final events = <AppNotificationEvent>[];
    final subscription = container.listen(appNotificationControllerProvider, (
      _,
      next,
    ) {
      if (next != null) events.add(next);
    });
    addTearDown(subscription.close);

    final task = controller.startTask(
      const AppNotification.message(
        severity: AppNotificationSeverity.info,
        message: AppNotificationMessage.translationStarted,
      ),
    );
    task
      ..dismiss()
      ..dismiss();

    expect(events.map((event) => event.kind), [
      AppNotificationEventKind.taskStarted,
      AppNotificationEventKind.taskDismissed,
    ]);
  });
}
