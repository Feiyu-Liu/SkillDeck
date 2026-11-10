import 'package:skills_manager/l10n/app_failure_l10n.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';

AppNotificationContent localizeAppNotification(
  AppLocalizations l10n,
  AppNotification notification, {
  bool taskRunning = false,
}) {
  final message = notification.message;
  final failure = notification.failure;
  // A failure that lists several items, such as each blocked Agent folder,
  // keeps its first line as the summary and the rest behind "Show details".
  final failureLines = failure == null
      ? null
      : localizeAppFailure(l10n, failure).split('\n');
  final hasDetail = failureLines != null && failureLines.length > 1;
  return AppNotificationContent(
    severity: notification.severity,
    message:
        failureLines?.first ??
        notification.providerError ??
        _localizeMessage(l10n, message!, notification.progress),
    progress: notification.progress,
    taskRunning: taskRunning,
    copyText: notification.providerError,
    detail: hasDetail ? failureLines.skip(1).join('\n') : null,
    detailLabel: hasDetail ? l10n.notificationShowDetails : null,
  );
}

AppNotificationPresentation localizeAppNotificationEvent(
  AppLocalizations l10n,
  AppNotificationEvent event,
) => AppNotificationPresentation(
  kind: switch (event.kind) {
    AppNotificationEventKind.transient =>
      AppNotificationPresentationKind.transient,
    AppNotificationEventKind.taskStarted =>
      AppNotificationPresentationKind.taskStarted,
    AppNotificationEventKind.taskUpdated =>
      AppNotificationPresentationKind.taskUpdated,
    AppNotificationEventKind.taskFinished =>
      AppNotificationPresentationKind.taskFinished,
    AppNotificationEventKind.taskDismissed =>
      AppNotificationPresentationKind.taskDismissed,
  },
  taskId: event.taskId,
  content: localizeAppNotification(
    l10n,
    event.notification,
    taskRunning:
        event.kind == AppNotificationEventKind.taskStarted ||
        event.kind == AppNotificationEventKind.taskUpdated,
  ),
);

String _localizeMessage(
  AppLocalizations l10n,
  AppNotificationMessage message,
  AppNotificationProgress? progress,
) => switch (message) {
  AppNotificationMessage.repositoryRefreshed =>
    l10n.notificationRepositoryRefreshed,
  AppNotificationMessage.skillsInstalled => l10n.notificationSkillsInstalled,
  AppNotificationMessage.activationEnabled =>
    l10n.notificationActivationEnabled,
  AppNotificationMessage.activationDisabled =>
    l10n.notificationActivationDisabled,
  AppNotificationMessage.skillFavorited => l10n.notificationSkillFavorited,
  AppNotificationMessage.skillUnfavorited => l10n.notificationSkillUnfavorited,
  AppNotificationMessage.skillUpdated => l10n.notificationSkillUpdated,
  AppNotificationMessage.skillRemoved => l10n.notificationSkillRemoved,
  AppNotificationMessage.updatesApplied => l10n.notificationUpdatesApplied,
  AppNotificationMessage.projectRootRegistered =>
    l10n.notificationProjectRootRegistered,
  AppNotificationMessage.projectRootUnregistered =>
    l10n.notificationProjectRootUnregistered,
  AppNotificationMessage.externalSkillsAdopted =>
    l10n.notificationExternalSkillsAdopted,
  AppNotificationMessage.externalSkillsPartiallyAdopted =>
    l10n.notificationExternalSkillsPartiallyAdopted,
  AppNotificationMessage.openLocationFailed =>
    l10n.notificationOpenLocationFailed,
  AppNotificationMessage.translationStarted =>
    l10n.notificationTranslationStarted,
  AppNotificationMessage.translationProgress =>
    progress == null
        ? l10n.notificationTranslationStarted
        : l10n.notificationTranslationProgress(
            progress.completed,
            progress.total,
          ),
  AppNotificationMessage.translationCancelling =>
    l10n.notificationTranslationCancelling,
  AppNotificationMessage.translationCompleted =>
    l10n.notificationTranslationCompleted,
  AppNotificationMessage.translationCancelled =>
    l10n.notificationTranslationCancelled,
  AppNotificationMessage.translationFailed =>
    l10n.notificationTranslationFailed,
  AppNotificationMessage.translationConfigureFirst =>
    l10n.translationConfigureFirst,
  AppNotificationMessage.translationCacheDeleted =>
    l10n.notificationTranslationCacheDeleted,
  AppNotificationMessage.translationSettingsSaved =>
    l10n.notificationTranslationSettingsSaved,
  AppNotificationMessage.finalizationPending =>
    l10n.notificationFinalizationPending,
  AppNotificationMessage.finalizationRecovered =>
    l10n.notificationFinalizationRecovered,
  AppNotificationMessage.updateCheckStarted =>
    l10n.notificationUpdateCheckStarted,
  AppNotificationMessage.updateCheckCurrent =>
    l10n.notificationUpdateCheckCurrent,
  AppNotificationMessage.updateCheckAvailable =>
    l10n.notificationUpdateCheckAvailable,
  AppNotificationMessage.updateCheckUnavailable =>
    l10n.notificationUpdateCheckUnavailable,
  AppNotificationMessage.updateCheckUnsupported =>
    l10n.notificationUpdateCheckUnsupported,
  AppNotificationMessage.updateCheckResolutionRequired =>
    l10n.notificationUpdateCheckResolutionRequired,
  AppNotificationMessage.updateCandidateAbandoned =>
    l10n.notificationUpdateCandidateAbandoned,
  AppNotificationMessage.operationCancelled =>
    l10n.notificationOperationCancelled,
  AppNotificationMessage.completedWithWarnings =>
    l10n.notificationCompletedWithWarnings,
};
