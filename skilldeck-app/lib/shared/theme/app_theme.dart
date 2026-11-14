import 'package:cupertino_ui/cupertino_ui.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_typography.dart';

export 'app_button_theme.dart';
export 'app_colors.dart';
export 'app_corners.dart';
export 'app_gradients.dart';
export 'app_metrics.dart';
export 'app_palette.dart';
export 'app_markdown_code_block_painter.dart';
export 'app_markdown_code_highlighter.dart';
export 'app_markdown_theme.dart';
export 'app_shadows.dart';
export 'app_typography.dart';

abstract final class SkillsTheme {
  static CupertinoThemeData forBrightness(Brightness brightness) {
    if (brightness == Brightness.light) return theme;
    final colors = AppPalette.dark;
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: colors.textPrimary,
      primaryContrastingColor: const Color(0xFF161618),
      scaffoldBackgroundColor: colors.canvas,
      barBackgroundColor: colors.surfaceSubtle,
      applyThemeToAll: true,
      textTheme: CupertinoTextThemeData(
        textStyle: AppTypography.body.copyWith(color: colors.bodyContent),
        actionTextStyle: AppTypography.control.copyWith(
          color: colors.textSecondary,
        ),
        navTitleTextStyle: theme.textTheme.navTitleTextStyle.copyWith(
          color: colors.textPrimary,
        ),
      ),
    );
  }

  static const CupertinoThemeData theme = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.textPrimary,
    primaryContrastingColor: AppColors.white,
    scaffoldBackgroundColor: AppColors.canvas,
    barBackgroundColor: AppColors.surfaceSubtle,
    applyThemeToAll: true,
    textTheme: CupertinoTextThemeData(
      textStyle: AppTypography.body,
      actionTextStyle: AppTypography.control,
      navTitleTextStyle: TextStyle(
        fontFamily: AppFonts.ui,
        fontFamilyFallback: AppFonts.fallback,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      ),
    ),
  );
}
