import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/notifications/toastification_app_notification_presenter.dart';

final appNotificationPresenterProvider = Provider<AppNotificationPresenter>((
  ref,
) {
  final presenter = ToastificationAppNotificationPresenter();
  ref.onDispose(presenter.dispose);
  return presenter;
});
