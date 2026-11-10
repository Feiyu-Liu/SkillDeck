import 'package:skills_manager/shared/notifications/app_notification.dart';

final class AppNotificationContent {
  const AppNotificationContent({
    required this.severity,
    required this.message,
    this.progress,
    this.taskRunning = false,
    this.copyText,
    this.detail,
    this.detailLabel,
  }) : assert((detail == null) == (detailLabel == null));

  final AppNotificationSeverity severity;
  final String message;
  final AppNotificationProgress? progress;
  final bool taskRunning;
  final String? copyText;

  /// Lines that would not fit beneath [message], shown when the user expands
  /// the toast.
  final String? detail;

  /// The localized "Show details" label. The toast renders above the App's
  /// localizations, so it arrives with the content.
  final String? detailLabel;
}

enum AppNotificationPresentationKind {
  transient,
  taskStarted,
  taskUpdated,
  taskFinished,
  taskDismissed,
}

final class AppNotificationPresentation {
  const AppNotificationPresentation({
    required this.kind,
    required this.content,
    this.taskId,
  });

  final AppNotificationPresentationKind kind;
  final AppNotificationContent content;
  final int? taskId;
}

abstract interface class AppNotificationPresenter {
  void present(AppNotificationPresentation presentation);

  void dismissAll();

  void dispose();
}
