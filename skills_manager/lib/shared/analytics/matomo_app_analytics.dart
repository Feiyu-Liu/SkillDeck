import 'package:matomo_tracker/matomo_tracker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

final class MatomoAnalyticsConfiguration {
  const MatomoAnalyticsConfiguration({required this.url, required this.siteId});

  const MatomoAnalyticsConfiguration.fromEnvironment()
    : url = const String.fromEnvironment('SKILLDECK_MATOMO_URL'),
      siteId = const String.fromEnvironment('SKILLDECK_MATOMO_SITE_ID');

  final String url;
  final String siteId;

  bool get isValid {
    final uri = Uri.tryParse(url.trim());
    return siteId.trim().isNotEmpty &&
        uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' || uri.scheme == 'http');
  }
}

final class MatomoAppAnalytics implements AppAnalytics {
  MatomoAppAnalytics._({
    required MatomoTracker tracker,
    required String platform,
    required String appVersion,
    required bool enabled,
    required AppDiagnostics diagnostics,
  }) : _tracker = tracker,
       _platform = platform,
       _appVersion = appVersion,
       _enabled = enabled,
       _diagnostics = diagnostics;

  final MatomoTracker _tracker;
  final String _platform;
  final String _appVersion;
  final AppDiagnostics _diagnostics;
  bool _enabled;

  static Future<AppAnalytics> create({
    required MatomoAnalyticsConfiguration configuration,
    required String platform,
    required bool enabled,
    required AppDiagnostics diagnostics,
  }) async {
    if (!configuration.isValid) return const NoopAppAnalytics();
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.buildNumber.isEmpty
          ? packageInfo.version
          : '${packageInfo.version}+${packageInfo.buildNumber}';
      final tracker = MatomoTracker.instance;
      await tracker.initialize(
        siteId: configuration.siteId.trim(),
        url: configuration.url.trim(),
        packageInfo: packageInfo,
        contentBaseUrl: 'https://skilldeck.local',
        userAgent: 'SkillDeck/$appVersion ($platform)',
        dispatchSettings: const DispatchSettings.nonPersistent(),
        pingInterval: null,
        attachLastScreenInfo: false,
        optOut: !enabled,
      );
      await tracker.setOptOut(optOut: !enabled);
      if (!enabled) tracker.dropActions();
      return MatomoAppAnalytics._(
        tracker: tracker,
        platform: platform,
        appVersion: appVersion,
        enabled: enabled,
        diagnostics: diagnostics,
      );
    } on Object {
      diagnostics.info(
        'analytics.initialization.skipped',
        context: const {'reason': 'initialization_failed'},
      );
      return const NoopAppAnalytics();
    }
  }

  @override
  void track(AppAnalyticsEvent event) {
    if (!_enabled) return;
    try {
      _tracker.trackEvent(
        eventInfo: EventInfo(
          category: event.category,
          action: event.action,
          name: event.name,
          value: event.duration?.inMilliseconds,
        ),
        dimensions: event.dimensions(
          platform: _platform,
          appVersion: _appVersion,
        ),
      );
    } on Object {
      _diagnostics.info(
        'analytics.event.skipped',
        context: {'event': event.action},
      );
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!enabled) {
      _enabled = false;
      _tracker.dropActions();
      try {
        await _tracker.setOptOut(optOut: true);
      } on Object {
        _diagnostics.info(
          'analytics.preference.sync_failed',
          context: const {'enabled': false},
        );
      }
      return;
    }
    try {
      await _tracker.setOptOut(optOut: false);
      _enabled = true;
    } on Object {
      _enabled = false;
      _diagnostics.info(
        'analytics.preference.sync_failed',
        context: const {'enabled': true},
      );
    }
  }

  @override
  void dispose() => _tracker.dispose();
}
