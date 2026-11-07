import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_ui/next_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_cupertino_controls.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_keycap_tag.dart';

import '../../support/fake_skill_browser_repository.dart';
import '../../support/skills_manager_test_app.dart';

void main() {
  testWidgets('the installed screen follows platform appearance changes', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: FakeSkillBrowserRepository()),
    );
    await tester.pumpAndSettle();
    final sidebar = tester.widget<Container>(
      find.byKey(const Key('app-sidebar')),
    );
    expect(sidebar.color, const Color(0xFF0F0F10));
    expect(
      CupertinoTheme.brightnessOf(
        tester.element(find.byKey(const Key('app-sidebar'))),
      ),
      Brightness.dark,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      tester.widget<Container>(find.byKey(const Key('app-sidebar'))).color,
      AppColors.canvas,
    );
  });

  testWidgets('dark appearance resolves surfaces, text, controls and dialog', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      CupertinoApp(
        theme: SkillsTheme.forBrightness(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            platformBrightness: Brightness.dark,
            size: Size(800, 600),
          ),
          child: NeoButtonTheme(
            data: SkillsButtonTheme.neo,
            child: Builder(
              builder: (context) {
                final colors = AppPalette.of(context);
                return ColoredBox(
                  key: const Key('canvas'),
                  color: colors.canvas,
                  child: Column(
                    children: [
                      ColoredBox(
                        key: const Key('surface'),
                        color: colors.surface,
                        child: Text(
                          'Body',
                          style: AppTypography.of(context).body,
                        ),
                      ),
                      AppButton(
                        label: 'Primary',
                        style: NeoButtonVariant.primary,
                        onPressed: () => pressed = true,
                      ),
                      AppButton(label: 'Secondary', onPressed: () {}),
                      const AppCupertinoDialogSurface(
                        width: 200,
                        child: SizedBox(height: 50),
                      ),
                      const AppKeycapTag('Tag', color: Color(0xFFE5484D)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<ColoredBox>(find.byKey(const Key('canvas'))).color,
      const Color(0xFF0F0F10),
    );
    expect(
      tester.widget<ColoredBox>(find.byKey(const Key('surface'))).color,
      const Color(0xFF1A1A1C),
    );
    expect(
      tester.widget<Text>(find.text('Body')).style!.color,
      const Color(0xFFD4D4D7),
    );
    final dialog = find.descendant(
      of: find.byType(AppCupertinoDialogSurface),
      matching: find.byType(ColoredBox),
    );
    expect(tester.widget<ColoredBox>(dialog).color, const Color(0xFF1F1F21));
    final primary = tester
        .widget<NeoSurface>(
          find.descendant(
            of: find.ancestor(
              of: find.text('Primary'),
              matching: find.byType(AppButton),
            ),
            matching: find.byType(NeoSurface),
          ),
        )
        .style;
    expect(primary.foregroundColor, const Color(0xFF161618));
    expect(primary.fillGradient!.colors, [
      const Color(0xFFFAFAFA),
      const Color(0xFFD9D9DC),
    ]);
    expect(primary.borderGradient!.colors, [
      const Color(0xE6FFFFFF),
      const Color(0xFFB8B8BD),
    ]);
    final secondary = tester
        .widget<NeoSurface>(
          find.descendant(
            of: find.ancestor(
              of: find.text('Secondary'),
              matching: find.byType(AppButton),
            ),
            matching: find.byType(NeoSurface),
          ),
        )
        .style;
    expect(secondary.fillColor, const Color(0xFF252528));
    expect(secondary.borderColor, const Color(0x1AFFFFFF));
    await tester.tap(find.text('Primary'));
    expect(pressed, isTrue);
    final tag = find.byType(AppKeycapTag);
    final decoration = tester
        .widgetList<Container>(
          find.descendant(of: tag, matching: find.byType(Container)),
        )
        .map((container) => container.decoration)
        .whereType<ShapeDecoration>()
        .single;
    const hue = Color(0xFFE5484D);
    const base = Color(0xFF18181A);
    final stroke = Color.lerp(hue, const Color(0xFFDCDCE3), 0.52)!;
    expect((decoration.gradient! as LinearGradient).colors, [
      Color.lerp(stroke, base, 0.70),
      Color.lerp(stroke, base, 0.78),
    ]);
    expect(
      (decoration.shape as SmoothRectangleBorder).side.color,
      Color.lerp(stroke, base, 0.50),
    );
    final lightLabel = Color.lerp(hue, const Color(0xFF171717), 0.24)!;
    expect(
      tester.widget<Text>(find.text('Tag')).style!.color,
      Color.lerp(lightLabel, CupertinoColors.white, 0.62),
    );
  });

  test('light palette keeps original values', () {
    expect(AppPalette.light.canvas, AppColors.canvas);
    expect(AppPalette.light.surface, AppColors.surface);
    expect(AppPalette.light.bodyContent, AppColors.bodyContent);
    expect(AppPalette.light.dangerSoft, AppColors.dangerSoft);
  });

  test('dark canvas, veil and candidate accents resolve semantically', () {
    final dark = AppPalette.forBrightness(Brightness.dark);
    expect(dark.canvas, const Color(0xFF0F0F10));
    expect(dark.surfaceVeil(const Color(0x9EFFFFFF)), const Color(0x9E1A1A1C));
    expect(dark.candidateAccents, const [
      Color(0xFF51C5B5),
      Color(0xFFE3A44A),
      Color(0xFFB89AFF),
      Color(0xFF6C9BF5),
      Color(0xFFF26868),
    ]);
    expect(
      AppPalette.light.surfaceVeil(const Color(0x9EFFFFFF)),
      const Color(0x9EFFFFFF),
    );
  });

  testWidgets('dialog and Markdown resolve dark semantic colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: SkillsTheme.forBrightness(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            platformBrightness: Brightness.dark,
            size: Size(800, 600),
          ),
          child: Builder(
            builder: (context) {
              final markdown = AppMarkdownTheme.data(context);
              expect(
                markdown.resolvedCodeTheme['keyword']!.color,
                const Color(0xFFFF7B72),
              );
              expect(
                markdown.resolvedCodeTheme['string']!.color,
                const Color(0xFFA5D6FF),
              );
              return const AppDialogScaffold(
                width: 320,
                header: Text('Dialog'),
              );
            },
          ),
        ),
      ),
    );
    final surface = find.descendant(
      of: find.byType(AppDialogScaffold),
      matching: find.byType(ColoredBox),
    );
    expect(
      tester.widgetList<ColoredBox>(surface).map((box) => box.color),
      contains(const Color(0xFF1A1A1C)),
    );
  });

  testWidgets('dark menu options keep readable labels and a dark selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: SkillsTheme.forBrightness(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            platformBrightness: Brightness.dark,
            size: Size(800, 600),
          ),
          child: Center(
            child: SizedBox(
              width: 240,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppMorphingMenuOption(
                    label: 'Selected',
                    selected: true,
                    onPressed: () {},
                  ),
                  const AppMorphingMenuDivider(),
                  AppMorphingMenuOption(
                    label: 'Other',
                    selected: false,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    for (final label in ['Selected', 'Other']) {
      expect(
        tester.widget<Text>(find.text(label)).style!.color,
        AppPalette.dark.textPrimary,
      );
    }
    final selection = tester.widget<Container>(
      find
          .ancestor(of: find.text('Selected'), matching: find.byType(Container))
          .first,
    );
    expect(
      (selection.decoration! as ShapeDecoration).color,
      AppPalette.dark.surfaceMuted,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(AppMorphingMenuDivider),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      AppPalette.dark.divider,
    );
  });
}
