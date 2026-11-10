import 'package:skills_manager/shared/analytics/app_analytics.dart';

final class RecordingAppAnalytics implements AppAnalytics {
  final List<AppAnalyticsEvent> events = [];
  final List<bool> enabledValues = [];

  @override
  void dispose() {}

  @override
  Future<void> setEnabled(bool enabled) async => enabledValues.add(enabled);

  @override
  void track(AppAnalyticsEvent event) => events.add(event);
}
