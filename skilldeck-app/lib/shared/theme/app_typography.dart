import 'package:flutter/cupertino.dart';

import 'app_colors.dart';
import 'app_palette.dart';

abstract final class AppFonts {
  static const ui = 'Inter';
  static const display = 'Space Grotesk';
  static const mono = 'JetBrains Mono';
  static const fallback = <String>['PingFang SC', 'Noto Sans SC'];
}

abstract final class AppTypography {
  static AppTextStyles of(BuildContext context) =>
      AppTextStyles(AppPalette.of(context));
  static const pageTitle = TextStyle(
    fontFamily: AppFonts.display,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.02,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  static const title = TextStyle(
    fontFamily: AppFonts.display,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const subtitle = TextStyle(
    fontFamily: AppFonts.display,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const sectionLabel = TextStyle(
    fontFamily: AppFonts.mono,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textFaint,
  );

  static const navigation = TextStyle(
    fontFamily: AppFonts.ui,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: AppColors.textSecondary,
  );

  static const navigationSelected = TextStyle(
    fontFamily: AppFonts.ui,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: AppFonts.ui,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.bodyContent,
  );

  static const bodyMuted = TextStyle(
    fontFamily: AppFonts.ui,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textMuted,
  );

  static const control = TextStyle(
    fontFamily: AppFonts.ui,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textSecondary,
  );

  static const caption = TextStyle(
    fontFamily: AppFonts.ui,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: AppColors.textMuted,
  );

  static const mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: AppColors.bodyContent,
  );
}

/// Typography with foregrounds resolved for the current appearance.
final class AppTextStyles {
  const AppTextStyles(this.colors);

  final AppPalette colors;

  TextStyle get pageTitle =>
      AppTypography.pageTitle.copyWith(color: colors.textPrimary);
  TextStyle get title =>
      AppTypography.title.copyWith(color: colors.textPrimary);
  TextStyle get subtitle =>
      AppTypography.subtitle.copyWith(color: colors.textPrimary);
  TextStyle get sectionLabel =>
      AppTypography.sectionLabel.copyWith(color: colors.textFaint);
  TextStyle get navigation =>
      AppTypography.navigation.copyWith(color: colors.textSecondary);
  TextStyle get navigationSelected =>
      AppTypography.navigationSelected.copyWith(color: colors.textPrimary);
  TextStyle get body => AppTypography.body.copyWith(color: colors.bodyContent);
  TextStyle get bodyMuted =>
      AppTypography.bodyMuted.copyWith(color: colors.textMuted);
  TextStyle get control =>
      AppTypography.control.copyWith(color: colors.textSecondary);
  TextStyle get caption =>
      AppTypography.caption.copyWith(color: colors.textMuted);
  TextStyle get mono => AppTypography.mono.copyWith(color: colors.bodyContent);
}
