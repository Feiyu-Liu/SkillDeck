import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/self_update/data/app_update_configuration.dart';
import 'package:skills_manager/features/self_update/presentation/widgets/self_update_settings.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

void main() {
  testWidgets('renders an unconfigured build without updater controls', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Automatic Updates'), findsOneWidget);
    expect(
      find.text('Check, download, and install signed SkillDeck releases.'),
      findsNothing,
    );
    expect(find.byKey(const Key('self-update-unconfigured')), findsOneWidget);
    expect(find.byKey(const Key('self-update-check')), findsNothing);
  });

  testWidgets('initializes native updater before manual check', (tester) async {
    final platform = _FakeAutoUpdaterPlatform();
    final coordinator = AppUpdateCoordinator.forTesting(
      platform: platform,
      configuration: AppUpdateConfiguration(
        feedUrl: Uri.parse('https://updates.example.com/appcast.xml'),
      ),
    );
    addTearDown(() async {
      coordinator.dispose();
      await platform.dispose();
    });

    await tester.pumpWidget(
      _testApp(
        configuration: coordinator.configuration,
        coordinator: coordinator,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('self-update-check')));
    await tester.pump();

    expect(platform.setFeedUrls, ['https://updates.example.com/appcast.xml']);
    expect(platform.checkCalls, 1);
  });
}

Widget _testApp({
  AppUpdateConfiguration? configuration,
  AppUpdateCoordinator? coordinator,
}) => ProviderScope(
  overrides: [
    if (configuration != null)
      appUpdateConfigurationProvider.overrideWithValue(
        AsyncData(configuration),
      ),
    if (coordinator != null)
      appUpdateCoordinatorProvider.overrideWithValue(coordinator),
    appVersionProvider.overrideWithValue(const AsyncData('1.0.0')),
  ],
  child: CupertinoApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: SkillsTheme.theme,
    home: const CupertinoPageScaffold(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: SelfUpdateSettings(installBlocked: false),
      ),
    ),
  ),
);

final class _FakeAutoUpdaterPlatform extends AutoUpdaterPlatform {
  final _events = StreamController<Map<Object?, Object?>>.broadcast();
  final setFeedUrls = <String>[];
  int checkCalls = 0;

  @override
  Stream<Map<Object?, Object?>> get sparkleEvents => _events.stream;

  @override
  Future<void> setFeedURL(String feedUrl) async => setFeedUrls.add(feedUrl);

  @override
  Future<UpdateCheckStart> checkForUpdates({bool? inBackground}) async {
    checkCalls++;
    _events.add(const {'type': 'update-not-available'});
    return UpdateCheckStart.started;
  }

  @override
  Future<void> setScheduledCheckInterval(int interval) async {}

  Future<void> dispose() => _events.close();
}
