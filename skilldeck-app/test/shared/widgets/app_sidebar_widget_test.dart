import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_sidebar.dart';

void main() {
  testWidgets('uses a compact layout and preserves navigation actions', (
    tester,
  ) async {
    NavSection? selected;

    await tester.pumpWidget(
      CupertinoApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CupertinoPageScaffold(
          child: NeoButtonTheme(
            data: SkillsButtonTheme.neo,
            child: AppSidebar(
              selected: NavSection.installed,
              onSelected: (section) => selected = section,
            ),
          ),
        ),
      ),
    );

    const installedItem = Key('nav-item-installed');
    const updatesItem = Key('nav-item-updates');

    expect(
      tester.getSize(find.byKey(const Key('app-sidebar'))).width,
      AppSizes.sidebarExpandedWidth,
    );
    expect(
      tester.getSize(find.byKey(installedItem)).height,
      AppSizes.navItemHeight,
    );
    // The brand row and its gap sit between the sidebar inset and the first
    // nav item while the sidebar is expanded.
    expect(
      tester.getTopLeft(find.byKey(installedItem)).dy,
      AppInsets.sidebar.top + 14 + AppSpacing.md,
    );
    expect(
      tester.getSize(find.byKey(installedItem)).width,
      AppSizes.sidebarExpandedWidth - AppSizes.sidebarHorizontalPadding * 2,
    );

    final installedButton = tester.widget<NeoButton>(
      find.descendant(
        of: find.byKey(installedItem),
        matching: find.byType(NeoButton),
      ),
    );
    expect(installedButton.variant, NeoButtonVariant.secondary);
    expect(installedButton.fullWidth, isTrue);
    expect(
      tester
          .widget<NeoButton>(
            find.descendant(
              of: find.byKey(updatesItem),
              matching: find.byType(NeoButton),
            ),
          )
          .variant,
      NeoButtonVariant.ghost,
    );
    expect(find.byKey(updatesItem), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(updatesItem)).dy -
          tester.getBottomLeft(find.byKey(const Key('nav-item-favorites'))).dy,
      AppSpacing.xs,
    );

    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Write'), findsNothing);
    expect(find.text('Test'), findsNothing);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Installed Skills'), findsNothing);
    expect(find.text('SkillDeck'), findsOneWidget);
    expect(find.text('WORKSPACE'), findsNothing);
    expect(find.text('MAINTENANCE'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    expect(selected, NavSection.settings);
  });

  testWidgets('collapsed presentation fits icon navigation controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CupertinoPageScaffold(
          child: NeoButtonTheme(
            data: SkillsButtonTheme.neo,
            child: AppSidebar(
              selected: NavSection.installed,
              width: AppSizes.sidebarCollapsedWidth,
              progress: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Installed'), findsNothing);
    expect(find.byIcon(NavSection.installed.icon), findsOneWidget);

    const installedItem = Key('nav-item-installed');
    // The brand row is gone entirely, so the first nav item rides up to the
    // sidebar's own top inset rather than leaving that band empty.
    expect(
      tester.getTopLeft(find.byKey(installedItem)).dy,
      AppInsets.sidebar.top,
    );
    // Only the left inset is charged to the rail: the gap before the content
    // panel supplies the button's right-hand breathing room.
    expect(
      tester.getSize(find.byKey(installedItem)).width,
      AppSizes.sidebarCollapsedWidth - AppSizes.sidebarHorizontalPadding,
    );
    expect(
      tester.getCenter(find.byIcon(NavSection.installed.icon)).dx,
      moreOrLessEquals(
        tester.getCenter(find.byKey(installedItem)).dx,
        epsilon: 0.01,
      ),
    );
    // Centred on the canvas the user sees — the rail plus the gap before the
    // content panel — not on the rail box alone.
    expect(
      tester.getCenter(find.byKey(installedItem)).dx,
      moreOrLessEquals(
        (AppSizes.sidebarCollapsedWidth + AppInsets.shellContent.left) / 2,
        epsilon: 0.01,
      ),
    );
  });

  testWidgets('brand row collapses in step with the rail', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CupertinoPageScaffold(
          child: NeoButtonTheme(
            data: SkillsButtonTheme.neo,
            child: AppSidebar(
              selected: NavSection.installed,
              width:
                  (AppSizes.sidebarExpandedWidth +
                      AppSizes.sidebarCollapsedWidth) /
                  2,
              progress: 0.5,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    // Mid-drag the header is partly collapsed, which pins the nav items
    // strictly between the two settled positions: the move is continuous, not
    // a jump at the rail threshold.
    final dy = tester
        .getTopLeft(find.byKey(const Key('nav-item-installed')))
        .dy;
    expect(dy, greaterThan(AppInsets.sidebar.top));
    expect(dy, lessThan(AppInsets.sidebar.top + 14 + AppSpacing.md));
  });

  testWidgets('keeps the update prompt on both sides of the rail threshold', (
    tester,
  ) async {
    Future<void> pumpAt(double progress) => tester.pumpWidget(
      CupertinoApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CupertinoPageScaffold(
          child: NeoButtonTheme(
            data: SkillsButtonTheme.neo,
            child: AppSidebar(
              selected: NavSection.installed,
              width: progress == 0
                  ? AppSizes.sidebarCollapsedWidth
                  : AppSizes.sidebarExpandedWidth,
              progress: progress,
              onSelected: (_) {},
              updatePromptBuilder: (rail) => SizedBox(
                key: ValueKey('update-prompt-rail-$rail'),
                height: 34,
              ),
            ),
          ),
        ),
      ),
    );

    await pumpAt(1);
    expect(find.byKey(const ValueKey('update-prompt-rail-false')), findsOne);

    await pumpAt(0);
    expect(find.byKey(const ValueKey('update-prompt-rail-true')), findsOne);
  });
}
