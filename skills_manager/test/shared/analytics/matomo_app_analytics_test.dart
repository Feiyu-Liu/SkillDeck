import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/analytics/matomo_app_analytics.dart';

void main() {
  test('requires a site id and an HTTP endpoint', () {
    expect(
      const MatomoAnalyticsConfiguration(
        url: 'https://analytics.example.com/matomo.php',
        siteId: '1',
      ).isValid,
      isTrue,
    );
    expect(
      const MatomoAnalyticsConfiguration(url: '', siteId: '1').isValid,
      isFalse,
    );
    expect(
      const MatomoAnalyticsConfiguration(
        url: 'file:///tmp/matomo',
        siteId: '1',
      ).isValid,
      isFalse,
    );
  });
}
