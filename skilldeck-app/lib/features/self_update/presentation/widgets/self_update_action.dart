import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/notifications/app_notification_providers.dart';

Future<void> openNativeUpdateDialog(
  BuildContext context,
  WidgetRef ref,
  AppUpdateCoordinator coordinator, {
  required bool blocked,
}) async {
  final presenter = ref.read(appNotificationPresenterProvider);
  final message = context.l10n.settingsAppUpdateProcessing;
  final result = await coordinator.openUpdateDialog(blocked: blocked);
  if (!context.mounted || result != UpdateCheckStart.busy) return;
  presenter.present(
    AppNotificationPresentation(
      kind: AppNotificationPresentationKind.transient,
      content: AppNotificationContent(
        severity: AppNotificationSeverity.info,
        message: message,
      ),
    ),
  );
}
