import 'package:flutter/cupertino.dart';

/// Raw and semantic colors used by the Skills Manager interface.
///
/// Keep feature widgets on these named colors so palette changes stay local to
/// the design system.
abstract final class AppColors {
  static const ink = Color(0xFF1A1A1A);
  static const white = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFEBEBEC);

  static const _offWhite = Color(0xFFF9F9F9);
  static const _mutedSurface = Color(0xFFF2F2F1);
  static const _line = Color(0xFFE5E6E6);
  static const _strongLine = Color(0xFFD6D6D4);
  static const _inactive = Color(0xFFC9CBCC);
  static const _secondary = Color(0xFF8E8E93);
  static const _body = Color(0xFF333333);

  static const surface = white;
  static const surfaceTransparent = Color(0x00FFFFFF);
  static const surfaceSubtle = _offWhite;
  static const surfaceMuted = _mutedSurface;
  static const surfacePressed = _line;
  static const textPrimary = ink;
  static const emphasis = textPrimary;
  static const bodyContent = _body;
  static const textSecondary = _secondary;
  static const textMuted = textSecondary;
  static const textFaint = textSecondary;
  static const controlInactive = _inactive;
  static const propertyCardBackground = surfaceSubtle;
  static const inlineCodeBackground = _line;
  static const divider = _line;
  static const border = divider;
  static const borderStrong = _strongLine;

  static const danger = Color(0xFFDC2626);

  /// The destructive fill for solid buttons.
  ///
  /// Lighter than [danger], which stays reserved for red text and icons where
  /// the smaller strokes need the darker tone to hold their contrast.
  static const dangerFill = Color(0xFFE53535);
  static const dangerHovered = Color(0xFFE23B3B);
  static const dangerPressed = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFEF2F2);
  static const success = Color(0xFF1E9E64);
  static const successHovered = Color(0xFF2EAA70);
  static const successPressed = Color(0xFF178052);
  static const successSoft = Color(0xFFE8F6EF);
  static const warning = Color(0xFFE8930A);

  /// Amber for warning text and glyphs on a light surface, where [warning]
  /// itself is too light to hold its contrast.
  static const warningStrong = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFFF7E8);
  static const warningSoftHovered = Color(0xFFFDEDCF);
  static const warningBorder = Color(0xFFF3D3A0);
  static const info = Color(0xFF3B82F6);

  /// Blue for info glyphs on [infoSoft], where [info] is too light to hold its
  /// contrast.
  static const infoStrong = Color(0xFF2563EB);
  static const infoSoft = Color(0xFFE8F0FE);
  static const metaBarBackground = propertyCardBackground;

  static const codeComment = Color(0xFF6E7781);
  static const codeKeyword = Color(0xFFCF222E);
  static const codeNumber = Color(0xFF0550AE);
  static const codeString = Color(0xFF116329);
  static const codeTitle = Color(0xFF8250DF);
  static const codeMeta = Color(0xFF953800);

  static const buttonPrimaryHovered = bodyContent;
  static const buttonPrimaryPressed = Color(0xFF111111);

  static const transparent = Color(0x00000000);
  static const modalScrim = Color(0x66000000);

  // Compatibility aliases. New code should prefer the semantic names above.
  static const appBg = canvas;
  static const updateGreen = success;
  static const amber = warning;
  static const blue = info;
  static const metaBarBg = metaBarBackground;
}
