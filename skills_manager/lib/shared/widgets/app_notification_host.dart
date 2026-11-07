import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/l10n/app_notification_l10n.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/notifications/app_notification_providers.dart';

class AppNotificationHost extends ConsumerWidget {
  const AppNotificationHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(appNotificationControllerProvider, (previous, next) {
      if (next == null || previous?.sequence == next.sequence) return;
      try {
        ref
            .read(appNotificationPresenterProvider)
            .present(localizeAppNotificationEvent(context.l10n, next));
      } on Object {
        // Notification presentation must never enter the global error pipeline.
      }
    });
    return child;
  }
}
