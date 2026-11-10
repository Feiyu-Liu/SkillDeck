import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';

final appNotificationControllerProvider =
    NotifierProvider<AppNotificationController, AppNotificationEvent?>(
      AppNotificationController.new,
    );

final class AppNotificationController extends Notifier<AppNotificationEvent?> {
  var _sequence = 0;
  var _taskSequence = 0;
  var _disposed = false;

  @override
  AppNotificationEvent? build() {
    ref.onDispose(() => _disposed = true);
    return null;
  }

  void publish(AppNotification notification) {
    _publish(notification, kind: AppNotificationEventKind.transient);
  }

  AppNotificationTaskHandle startTask(AppNotification notification) {
    final taskId = ++_taskSequence;
    _publish(
      notification,
      kind: AppNotificationEventKind.taskStarted,
      taskId: taskId,
    );
    return AppNotificationTaskHandle._(
      taskId: taskId,
      initialNotification: notification,
      publish: _publishTaskEvent,
    );
  }

  void success(AppNotificationMessage message) {
    publish(
      AppNotification.message(
        severity: AppNotificationSeverity.success,
        message: message,
      ),
    );
  }

  void warning(AppNotificationMessage message) {
    publish(
      AppNotification.message(
        severity: AppNotificationSeverity.warning,
        message: message,
      ),
    );
  }

  void info(AppNotificationMessage message) {
    publish(
      AppNotification.message(
        severity: AppNotificationSeverity.info,
        message: message,
      ),
    );
  }

  void error(AppNotificationMessage message) {
    publish(
      AppNotification.message(
        severity: AppNotificationSeverity.error,
        message: message,
      ),
    );
  }

  void failure(
    Object error, {
    required String operationKey,
    StackTrace? stackTrace,
  }) {
    publish(
      AppNotification.failure(
        ref
            .read(appFailureReporterProvider)
            .capture(
              error,
              stackTrace ?? StackTrace.current,
              operationKey: operationKey,
            ),
      ),
    );
  }

  void _publishTaskEvent(
    int taskId,
    AppNotificationEventKind kind,
    AppNotification notification,
  ) {
    _publish(notification, kind: kind, taskId: taskId);
  }

  void _publish(
    AppNotification notification, {
    required AppNotificationEventKind kind,
    int? taskId,
  }) {
    if (_disposed) return;
    state = AppNotificationEvent(
      sequence: ++_sequence,
      notification: notification,
      kind: kind,
      taskId: taskId,
    );
  }
}

final class AppNotificationTaskHandle {
  AppNotificationTaskHandle._({
    required int taskId,
    required AppNotification initialNotification,
    required void Function(
      int taskId,
      AppNotificationEventKind kind,
      AppNotification notification,
    )
    publish,
  }) : _taskId = taskId,
       _notification = initialNotification,
       _publish = publish;

  final int _taskId;
  final void Function(
    int taskId,
    AppNotificationEventKind kind,
    AppNotification notification,
  )
  _publish;

  AppNotification _notification;
  bool _active = true;

  void update(AppNotification notification) {
    if (!_active) return;
    _notification = notification;
    _publish(_taskId, AppNotificationEventKind.taskUpdated, notification);
  }

  void finish(AppNotification notification) {
    if (!_active) return;
    _active = false;
    _notification = notification;
    _publish(_taskId, AppNotificationEventKind.taskFinished, notification);
  }

  void dismiss() {
    if (!_active) return;
    _active = false;
    _publish(_taskId, AppNotificationEventKind.taskDismissed, _notification);
  }
}
