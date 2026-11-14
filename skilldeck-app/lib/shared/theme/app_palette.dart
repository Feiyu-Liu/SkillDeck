import 'package:cupertino_ui/cupertino_ui.dart';

import 'app_colors.dart';

/// Semantic colors for a single platform appearance.
///
/// Derived dark colors: danger fill/hover/press #E53535/#F04A4A/#B91C1C,
/// warning #E3A44A, warning hover/border #3B2D1A/#6D502B, info #6C9BF5,
/// primary hover/press #FFFFFF/#C6C6CA, and modal scrim #99000000.
/// Success hover/press are #58CE98/#2A9E6B; dialog footer is #B31F1F21.
/// Source surfaces are #2D2316/#1A2540 and translation success #16291F.
/// Candidate accents are #51C5B5, #E3A44A, #B89AFF, #6C9BF5 and #F26868.
/// Highlight colors follow GitHub dark: #8B949E, #FF7B72, #79C0FF,
/// #A5D6FF, #D2A8FF and #FFA657.
@immutable
final class AppPalette {
  const AppPalette._(this.brightness);

  static const light = AppPalette._(Brightness.light);
  static const dark = AppPalette._(Brightness.dark);

  static AppPalette of(BuildContext context) => forBrightness(
    MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
  );

  static AppPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  final Brightness brightness;

  Color _color(Color light, Color dark) =>
      brightness == Brightness.dark ? dark : light;

  Color get ink => _color(AppColors.ink, const Color(0xFFF2F2F3));
  Color get white => _color(AppColors.white, const Color(0xFF1A1A1C));
  Color get canvas => _color(AppColors.canvas, const Color(0xFF0F0F10));
  Color get surface => white;
  Color get surfaceTransparent =>
      _color(AppColors.surfaceTransparent, const Color(0x001A1A1C));
  Color get surfaceSubtle =>
      _color(AppColors.surfaceSubtle, const Color(0xFF1F1F21));
  Color get surfaceMuted =>
      _color(AppColors.surfaceMuted, const Color(0xFF27272A));
  Color get surfacePressed =>
      _color(AppColors.surfacePressed, const Color(0xFF2A2A2D));
  Color get textPrimary => ink;
  Color get emphasis => ink;
  Color get bodyContent =>
      _color(AppColors.bodyContent, const Color(0xFFD4D4D7));
  Color get textSecondary =>
      _color(AppColors.textSecondary, const Color(0xFF8D8D94));
  Color get textMuted => textSecondary;
  Color get textFaint => textSecondary;
  Color get controlInactive =>
      _color(AppColors.controlInactive, const Color(0xFF4A4A4F));
  Color get propertyCardBackground => surfaceSubtle;
  Color get inlineCodeBackground => surfacePressed;
  Color get divider => surfacePressed;
  Color get border => divider;
  Color get borderStrong =>
      _color(AppColors.borderStrong, const Color(0xFF38383C));
  Color get danger => _color(AppColors.danger, const Color(0xFFF26868));
  Color get dangerFill => _color(AppColors.dangerFill, const Color(0xFFE53535));
  Color get dangerHovered =>
      _color(AppColors.dangerHovered, const Color(0xFFF04A4A));
  Color get dangerPressed =>
      _color(AppColors.dangerPressed, const Color(0xFFB91C1C));
  Color get dangerSoft => _color(AppColors.dangerSoft, const Color(0xFF361C1D));
  Color get success => _color(AppColors.success, const Color(0xFF3FBF85));
  Color get successHovered =>
      _color(AppColors.successHovered, const Color(0xFF58CE98));
  Color get successPressed =>
      _color(AppColors.successPressed, const Color(0xFF2A9E6B));
  Color get successSoft =>
      _color(AppColors.successSoft, const Color(0xFF16291F));
  Color get warning => _color(AppColors.warning, const Color(0xFFE3A44A));
  Color get warningStrong =>
      _color(AppColors.warningStrong, const Color(0xFFE3A44A));
  Color get warningSoft =>
      _color(AppColors.warningSoft, const Color(0xFF2D2316));
  Color get warningSoftHovered =>
      _color(AppColors.warningSoftHovered, const Color(0xFF3B2D1A));
  Color get warningBorder =>
      _color(AppColors.warningBorder, const Color(0xFF6D502B));
  Color get info => _color(AppColors.info, const Color(0xFF6C9BF5));
  Color get infoStrong => _color(AppColors.infoStrong, const Color(0xFF6C9BF5));
  Color get infoSoft => _color(AppColors.infoSoft, const Color(0xFF1A2540));
  Color get metaBarBackground => propertyCardBackground;
  Color get codeComment =>
      _color(AppColors.codeComment, const Color(0xFF8B949E));
  Color get codeKeyword =>
      _color(AppColors.codeKeyword, const Color(0xFFFF7B72));
  Color get codeNumber => _color(AppColors.codeNumber, const Color(0xFF79C0FF));
  Color get codeString => _color(AppColors.codeString, const Color(0xFFA5D6FF));
  Color get codeTitle => _color(AppColors.codeTitle, const Color(0xFFD2A8FF));
  Color get codeMeta => _color(AppColors.codeMeta, const Color(0xFFFFA657));
  Color get buttonPrimaryHovered =>
      _color(AppColors.buttonPrimaryHovered, const Color(0xFFFFFFFF));
  Color get buttonPrimaryPressed =>
      _color(AppColors.buttonPrimaryPressed, const Color(0xFFC6C6CA));
  Color get transparent => AppColors.transparent;
  Color get modalScrim => _color(AppColors.modalScrim, const Color(0x99000000));
  Color get tooltipBackground =>
      _color(const Color(0xCC1A1A1A), const Color(0xFF2E2E31));
  Color get tooltipForeground =>
      _color(AppColors.white, const Color(0xFFF2F2F3));
  Color get onPrimary => _color(AppColors.white, const Color(0xFF161618));
  Color get localSourceSurface =>
      _color(const Color(0xFFFFF3E0), const Color(0xFF2D2316));
  Color get webSourceSurface =>
      _color(const Color(0xFFEFF6FF), const Color(0xFF1A2540));
  Color get agentChip => _color(AppColors.white, const Color(0xFF2A2A2D));
  Color get translationSuccessSoft =>
      _color(const Color(0xFFEEF8F2), const Color(0xFF16291F));
  List<Color> get candidateAccents => [
    _color(const Color(0xFF0D9488), const Color(0xFF51C5B5)),
    _color(const Color(0xFFD97706), const Color(0xFFE3A44A)),
    _color(const Color(0xFF7C3AED), const Color(0xFFB89AFF)),
    _color(const Color(0xFF2563EB), const Color(0xFF6C9BF5)),
    _color(const Color(0xFFDC2626), const Color(0xFFF26868)),
  ];
  Color get dialogFooter =>
      _color(const Color(0xB3F9F9F9), const Color(0xB31F1F21));

  Color surfaceVeil(Color lightColor) => brightness == Brightness.light
      ? lightColor
      : surface.withValues(alpha: lightColor.a);
  Color get appBg => canvas;
  Color get updateGreen => success;
  Color get amber => warning;
  Color get blue => info;
  Color get metaBarBg => metaBarBackground;
}
