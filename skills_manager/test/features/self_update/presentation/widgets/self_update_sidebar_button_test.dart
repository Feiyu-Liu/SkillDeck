import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/self_update/presentation/widgets/self_update_sidebar_button.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_sidebar.dart';

import '../../../../support/memory_app_settings_store.dart';

void main() {
  late _FakeAutoUpdaterPlatform platform;
  late AppUpdateCoordinator coordinator;

  setUp(() {
    platform = _FakeAutoUpdaterPlatform();
    coordinator = AppUpdateCoordinator.forTesting(platform: platform);
  });

  tearDown(() async {
    coordinator.dispose();
    await platform.close();
  });

  const button = Key('nav-item-self-update');

  testWidgets('stays hidden while there is nothing to act on', (tester) async {
    await tester.pumpWidget(_testApp(coordinator));

    expect(find.byKey(button), findsNothing);
  });

  testWidgets('labels each prompt with a short sidebar action', (tester) async {
    await tester.pumpWidget(_testApp(coordinator));

    coordinator.onUpdaterUpdateAvailable(
      const AppcastItem(displayVersionString: '1.2.0'),
    );
    await tester.pump();
    // The version stays in Settings; the sidebar only says there is one.
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('1.2.0'), findsNothing);

    coordinator.onUpdaterUpdateDownloaded(null);
    await tester.pump();
    expect(find.text('Install update'), findsOneWidget);
  });

  testWidgets('stays in place as a busy control while its check runs', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(coordinator));
    coordinator.onUpdaterUpdateAvailable(null);
    await tester.pump();

    await tester.tap(find.byKey(button));
    await tester.pump();

    expect(platform.checkCount, 1);
    expect(find.byKey(button), findsOneWidget);
    expect(find.text('Checking…'), findsOneWidget);
    expect(
      find.byKey(const Key('nav-item-self-update-progress')),
      findsOneWidget,
    );
    expect(
      tester.widget<CupertinoButton>(find.byKey(button)).onPressed,
      isNull,
    );

    platform.emit('update-not-available');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(button), findsNothing);
  });

  testWidgets('keeps an icon-only prompt on the collapsed rail', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_testApp(coordinator, rail: true));
    coordinator.onUpdaterUpdateAvailable(
      const AppcastItem(displayVersionString: '1.2.0'),
    );
    await tester.pump();

    expect(find.byKey(button), findsOneWidget);
    expect(find.text('Update available'), findsNothing);
    expect(find.bySemanticsLabel('Update available'), findsOneWidget);
    // The bare icon must not read as the Updates nav item next to it.
    expect(find.byIcon(LucideIcons.circleFadingArrowUp), findsOneWidget);
    expect(find.byIcon(NavSection.updates.icon), findsNothing);
    semantics.dispose();
  });
}

Widget _testApp(AppUpdateCoordinator coordinator, {bool rail = false}) =>
    ProviderScope(
      overrides: [
        appUpdateCoordinatorProvider.overrideWithValue(coordinator),
        appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
      ],
      child: CupertinoApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SkillsTheme.theme,
        home: CupertinoPageScaffold(
          child: Center(
            child: SizedBox(
              width: rail ? 44 : 200,
              child: SelfUpdateSidebarButton(rail: rail),
            ),
          ),
        ),
      ),
    );

final class _FakeAutoUpdaterPlatform extends AutoUpdaterPlatform {
  final _events = StreamController<Map<Object?, Object?>>.broadcast();
  int checkCount = 0;

  void emit(String type) => _events.add({'type': type});

  @override
  Stream<Map<Object?, Object?>> get sparkleEvents => _events.stream;

  @override
  Future<void> setFeedURL(String feedUrl) async {}

  @override
  Future<UpdateCheckStart> checkForUpdates({bool? inBackground}) async {
    checkCount++;
    return UpdateCheckStart.started;
  }

  @override
  Future<void> setScheduledCheckInterval(int interval) async {}

  Future<void> close() => _events.close();
}
