import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:skills_manager/features/settings/presentation/settings_section.dart';
import 'package:skills_manager/features/whats_new/presentation/whats_new_dialog.dart';
import 'package:skills_manager/features/whats_new/whats_new_catalog.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';

void main() {
  Future<GoRouter> pumpDialog(
    WidgetTester tester, {
    WhatsNewEntry? entry,
    Locale? locale,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Center(
            child: CupertinoButton(
              key: const Key('open'),
              onPressed: () => AppDialogMotion.show<void>(
                context: context,
                builder: (_) =>
                    WhatsNewDialog(entry: entry ?? whatsNewCatalog.last),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) =>
              Text('settings ${state.uri.queryParameters['section']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      CupertinoApp.router(
        routerConfig: router,
        locale: locale ?? const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    return router;
  }

  for (final entry in whatsNewCatalog) {
    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets('lays out the ${entry.version} news in $locale', (
        tester,
      ) async {
        await pumpDialog(tester, entry: entry, locale: locale);
        final l10n = lookupAppLocalizations(locale);
        expect(find.byKey(const Key('whats-new-dialog')), findsOneWidget);
        expect(
          find.text(l10n.whatsNewVersionBadge(entry.version)),
          findsOneWidget,
        );
        expect(find.text(entry.title(l10n)), findsOneWidget);
        expect(find.text(entry.body(l10n)), findsOneWidget);
        expect(find.text(entry.settingsAction!(l10n)), findsOneWidget);
        expect(find.text(l10n.whatsNewDismiss), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const Key('whats-new-version-badge')))
              .width,
          lessThan(WhatsNewDialog.width / 2),
          reason: 'The version pill hugs its label.',
        );
        expect(
          tester.getSize(find.text(entry.body(l10n))).width,
          lessThanOrEqualTo(WhatsNewDialog.bodyMaxWidth),
        );
        expect(
          tester.getSize(find.byType(Image)),
          const Size(WhatsNewDialog.width, WhatsNewDialog.heroHeight),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('${entry.version} opens its Settings section', (tester) async {
      final router = await pumpDialog(tester, entry: entry);
      await tester.tap(find.byKey(const Key('whats-new-open-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whats-new-dialog')), findsNothing);
      expect(
        router.state.uri.toString(),
        settingsLocation(entry.settingsSection),
      );
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('dark mode news uses the ${brightness.name} hero', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final entry = whatsNewCatalog.singleWhere((e) => e.version == '1.1.4');
      await pumpDialog(tester, entry: entry);
      final image = tester.widget<Image>(find.byType(Image)).image;
      expect(
        (image as AssetImage).assetName,
        brightness == Brightness.dark
            ? 'assets/whats_new/dark_mode_dark.png'
            : 'assets/whats_new/dark_mode.png',
      );
    });
  }

  for (final (name, close) in <(String, Future<void> Function(WidgetTester))>[
    ('Got It', (t) => t.tap(find.byKey(const Key('whats-new-dismiss')))),
    (
      'the close button',
      (t) => t.tap(find.byKey(const Key('whats-new-close'))),
    ),
    ('Esc', (t) => t.sendKeyEvent(LogicalKeyboardKey.escape)),
  ]) {
    testWidgets('$name closes the dialog and stays put', (tester) async {
      final router = await pumpDialog(tester);
      await close(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whats-new-dialog')), findsNothing);
      expect(router.state.uri.path, '/');
    });
  }
}
