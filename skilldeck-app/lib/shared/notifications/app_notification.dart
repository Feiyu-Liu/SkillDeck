import 'package:skills_manager/shared/failures/app_failure.dart';

enum AppNotificationSeverity { info, success, warning, error }

enum AppNotificationMessage {
  repositoryRefreshed,
  skillsInstalled,
  activationEnabled,
  activationDisabled,
  skillFavorited,
  skillUnfavorited,
  skillUpdated,
  skillRemoved,
  updatesApplied,
  projectRootRegistered,
  projectRootUnregistered,
  externalSkillsAdopted,
  externalSkillsPartiallyAdopted,
  openLocationFailed,
  translationStarted,
  translationProgress,
  translationCancelling,
  translationCompleted,
  translationCancelled,
  translationFailed,
  translationConfigureFirst,
  translationCacheDeleted,
  translationSettingsSaved,
  finalizationPending,
  finalizationRecovered,
  updateCheckStarted,
  updateCheckCurrent,
  updateCheckAvailable,
  updateCheckUnavailable,
  updateCheckUnsupported,
  updateCheckResolutionRequired,
  updateCandidateAbandoned,
  operationCancelled,
  completedWithWarnings,
}

final class AppNotification {
  const AppNotification.message({
    required this.severity,
    required this.message,
    this.progress,
    this.providerError,
  }) : assert(
         providerError == null ||
             message == AppNotificationMessage.translationFailed,
       ),
       failure = null;

  const AppNotification.failure(this.failure)
    : severity = AppNotificationSeverity.error,
      message = null,
      progress = null,
      providerError = null;

  final AppNotificationSeverity severity;
  final AppNotificationMessage? message;
  final AppFailure? failure;
  final AppNotificationProgress? progress;

  /// Verbatim Provider code/message for the translation failure toast only.
  final String? providerError;
}

final class AppNotificationProgress {
  const AppNotificationProgress({required this.completed, required this.total})
    : assert(completed >= 0),
      assert(total > 0),
      assert(completed <= total);

  final int completed;
  final int total;

  double get fraction => completed / total;
}

enum AppNotificationEventKind {
  transient,
  taskStarted,
  taskUpdated,
  taskFinished,
  taskDismissed,
}

final class AppNotificationEvent {
  const AppNotificationEvent({
    required this.sequence,
    required this.notification,
    this.kind = AppNotificationEventKind.transient,
    this.taskId,
  });

  final int sequence;
  final AppNotification notification;
  final AppNotificationEventKind kind;
  final int? taskId;
}
