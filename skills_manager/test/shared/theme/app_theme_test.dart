import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:smooth_corner/smooth_corner.dart';

void main() {
  group('SkillsTheme', () {
    test('connects semantic tokens to the Cupertino theme', () {
      expect(SkillsTheme.theme.scaffoldBackgroundColor, AppColors.canvas);
      expect(SkillsTheme.theme.primaryColor, AppColors.textPrimary);
      expect(SkillsTheme.theme.textTheme.textStyle.fontFamily, AppFonts.ui);
      expect(
        SkillsTheme.theme.textTheme.textStyle.fontFamilyFallback,
        AppFonts.fallback,
      );
      expect(SkillsTheme.theme.applyThemeToAll, isTrue);
    });

    test('uses the same CJK fallback for product text roles', () {
      expect(AppFonts.fallback, const ['PingFang SC', 'Noto Sans SC']);
      for (final style in <TextStyle>[
        AppTypography.pageTitle,
        AppTypography.title,
        AppTypography.subtitle,
        AppTypography.sectionLabel,
        AppTypography.navigation,
        AppTypography.navigationSelected,
        AppTypography.body,
        AppTypography.bodyMuted,
        AppTypography.control,
        AppTypography.caption,
        AppTypography.mono,
      ]) {
        expect(style.fontFamilyFallback, AppFonts.fallback);
      }
    });

    test('uses the product color roles', () {
      expect(AppColors.textPrimary, const Color(0xFF1A1A1A));
      expect(AppColors.emphasis, const Color(0xFF1A1A1A));
      expect(AppColors.canvas, const Color(0xFFEBEBEC));
      expect(AppColors.textSecondary, const Color(0xFF8E8E93));
      expect(AppColors.propertyCardBackground, const Color(0xFFF9F9F9));
      expect(AppColors.bodyContent, const Color(0xFF333333));
      expect(AppColors.surfaceSubtle, AppColors.propertyCardBackground);
      expect(AppColors.surfacePressed, AppColors.divider);
      expect(AppColors.inlineCodeBackground, AppColors.divider);
      expect(AppColors.controlInactive, const Color(0xFFC9CBCC));
      expect(AppTypography.body.color, AppColors.bodyContent);
    });

    test('keeps compact desktop metrics internally consistent', () {
      expect(AppSizes.navItemHeight, lessThanOrEqualTo(36));
      expect(AppSizes.compactControlHeight, lessThan(AppSizes.navItemHeight));
      expect(AppRadii.control, lessThan(AppRadii.panel));
      expect(AppTypography.pageTitle.letterSpacing, 0);
      expect(AppSizes.pageHorizontalPadding, 28);
      expect(AppInsets.pageHeader.top, 16);
      expect(AppInsets.shellContent.top, AppInsets.shellContent.right);
      expect(AppInsets.shellContent.right, AppInsets.shellContent.bottom);
    });

    test('builds rounded rectangles with smooth_corner', () {
      expect(AppCorners.smoothness, 0.8);

      final decoration = AppCorners.smooth(
        color: AppColors.surface,
        radius: AppRadii.control,
      );

      expect(decoration.shape, isA<SmoothRectangleBorder>());
      expect(
        (decoration.shape as SmoothRectangleBorder).smoothness,
        AppCorners.smoothness,
      );
    });

    test('defines the selected-row gradient from light top to deep bottom', () {
      expect(AppGradients.selection.begin, Alignment.topCenter);
      expect(AppGradients.selection.end, Alignment.bottomCenter);
      expect(AppGradients.selection.colors, const [
        Color(0xFFB8D9FF),
        Color(0xFF78A9E6),
      ]);

      final decoration = AppCorners.smooth(
        gradient: AppGradients.selection,
        radius: AppRadii.sm,
      );

      expect(decoration.color, isNull);
      expect(decoration.gradient, AppGradients.selection);
      expect(decoration.shape, isA<SmoothRectangleBorder>());
    });

    test('defines a subtle shadow for the main content panel', () {
      expect(AppShadows.contentPanel, hasLength(2));
      expect(
        AppShadows.contentPanel.every((shadow) => shadow.color.a < 0.1),
        isTrue,
      );
    });

    test('defines one compact product button system', () {
      final buttons = SkillsButtonTheme.neo;
      expect(buttons.medium.height, AppSizes.buttonHeight);
      expect(buttons.small.height, AppSizes.compactControlHeight);
      expect(buttons.large.height, AppSizes.pageCommandBarHeight);
      expect(buttons.smoothness, AppCorners.smoothness);
      expect(buttons.palette.primary.resolve(Brightness.light), AppColors.ink);
      expect(buttons.palette.card.resolve(Brightness.light), AppColors.white);
      expect(
        buttons.palette.destructive.resolve(Brightness.light),
        AppColors.dangerFill,
      );
      expect(
        SkillsButtonTheme.morphingMenu.style.smoothness,
        AppCorners.smoothness,
      );
      expect(
        SkillsButtonTheme.morphingMenu.style.openCurve,
        const ElasticOutCurve(1.4),
      );
      expect(
        SkillsButtonTheme.morphingMenu.style.closeCurve,
        const ElasticOutCurve(1.4),
      );
      expect(
        SkillsButtonTheme.morphingMenu.style.duration,
        const Duration(milliseconds: 600),
      );
      expect(
        SkillsButtonTheme.morphingMenu.style.reverseDuration,
        const Duration(milliseconds: 600),
      );
    });
  });

  testWidgets(
    'AppButton uses Neo Cupertino interaction and invokes its action',
    (tester) async {
      var pressed = false;

      await tester.pumpWidget(
        CupertinoApp(
          theme: SkillsTheme.theme,
          home: CupertinoPageScaffold(
            child: Center(
              child: AppButton(
                label: 'Install',
                onPressed: () => pressed = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CupertinoButton), findsOneWidget);
      await tester.tap(find.text('Install'));
      expect(pressed, isTrue);
    },
  );

  testWidgets(
    'Morphing menu options expose selected semantics without hover animation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: AppMorphingMenuOption(
              label: 'Global',
              selected: true,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((widget) => widget.properties.selected == true),
        isTrue,
      );
      expect(find.byType(AnimatedContainer), findsNothing);
      semantics.dispose();
    },
  );
}
