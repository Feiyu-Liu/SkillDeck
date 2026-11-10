import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/l10n/app_notification_l10n.dart';
import 'package:skills_manager/l10n/generated/app_localizations_en.dart';
import 'package:skills_manager/l10n/generated/app_localizations_zh.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';

void main() {
  test('Provider error text is shown verbatim in either locale', () {
    const raw = 'invalid_api_key: Provider echoed private-source';
    const notification = AppNotification.message(
      severity: AppNotificationSeverity.error,
      message: AppNotificationMessage.translationFailed,
      providerError: raw,
    );

    for (final l10n in [AppLocalizationsEn(), AppLocalizationsZh()]) {
      final content = localizeAppNotification(l10n, notification);
      expect(content.message, raw);
      expect(content.copyText, raw);
    }
  });

  test('failure without Provider fields retains the localized fallback', () {
    const notification = AppNotification.message(
      severity: AppNotificationSeverity.error,
      message: AppNotificationMessage.translationFailed,
    );

    expect(
      localizeAppNotification(AppLocalizationsEn(), notification).message,
      'Translation failed. The previous translation or original content has been restored.',
    );
    expect(
      localizeAppNotification(AppLocalizationsZh(), notification).copyText,
      isNull,
    );
  });
}
