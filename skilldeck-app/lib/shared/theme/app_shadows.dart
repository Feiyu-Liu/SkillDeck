import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';

import 'app_palette.dart';

abstract final class AppShadows {
  static AppResolvedShadows of(BuildContext context) =>
      AppResolvedShadows(AppPalette.of(context));
  static const contentPanel = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(
      color: Color(0x12000000),
      blurRadius: 24,
      spreadRadius: -8,
      offset: Offset(0, 10),
    ),
  ];

  static const selectedNavigation = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(
      color: Color(0x12000000),
      blurRadius: 16,
      spreadRadius: -4,
      offset: Offset(0, 6),
    ),
  ];

  static const floatingControl = <BoxShadow>[
    BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(
      color: Color(0x22000000),
      blurRadius: 36,
      spreadRadius: -8,
      offset: Offset(0, 16),
    ),
  ];

  // The same lift as before, shifted so more of it falls below the card.
  static const hoveredCard = <BoxShadow>[
    BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 4)),
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 28,
      spreadRadius: -10,
      offset: Offset(0, 26),
    ),
  ];

  static const _commandLineGlowColors = [
    Color(0xFF2E7BFF),
    Color(0xFFA03BFF),
    Color(0xFFFF2E8A),
    Color(0xFFFFA414),
  ];

  /// The colored glow that replaces [hoveredCard] while the command line is
  /// working on a Skill card. Each color leans out from its own side of the
  /// card, and [turn] (0 to 1) carries them around it.
  ///
  /// [reach] is how far the light has spread: at 0 it is still tucked behind
  /// the card's edge, and at 1 it is the resting glow. [opacity] (0 to 1)
  /// fades it.
  static List<BoxShadow> commandLineGlow({
    required double opacity,
    double reach = 1,
    double turn = 0,
  }) {
    if (opacity <= 0) return const [];
    final count = _commandLineGlowColors.length;
    return [
      for (var i = 0; i < count; i++)
        _glowFrom(
          _commandLineGlowColors[i],
          opacity: opacity,
          reach: reach,
          angle: 2 * math.pi * (turn + i / count),
        ),
    ];
  }

  static BoxShadow _glowFrom(
    Color color, {
    required double opacity,
    required double reach,
    required double angle,
  }) => BoxShadow(
    color: color.withValues(alpha: 0.7 * opacity),
    blurRadius: 4 + 14 * reach,
    spreadRadius: -12 + 6 * reach,
    // Centered on the card: colored light cast downward reads as a muddy
    // shadow rather than a glow.
    offset: Offset(math.cos(angle), math.sin(angle)) * (6 * reach),
  );
}

/// Dark elevations use black shadows with approximately triple the light alpha.
final class AppResolvedShadows {
  const AppResolvedShadows(this.palette);
  final AppPalette palette;

  List<BoxShadow> _resolve(List<BoxShadow> shadows) =>
      palette.brightness == Brightness.light
      ? shadows
      : [
          for (final shadow in shadows)
            shadow.copyWith(
              color: const Color(0xFF000000)
                  .withValues(alpha: (shadow.color.a * 3).clamp(0, 1)),
            ),
        ];

  List<BoxShadow> get contentPanel => _resolve(AppShadows.contentPanel);
  List<BoxShadow> get selectedNavigation =>
      _resolve(AppShadows.selectedNavigation);
  List<BoxShadow> get floatingControl => _resolve(AppShadows.floatingControl);
  List<BoxShadow> get hoveredCard => _resolve(AppShadows.hoveredCard);
  BoxShadow get commandLine => BoxShadow(
    color: palette.brightness == Brightness.light
        ? const Color(0x66000000)
        : const Color(0xFF000000),
    blurRadius: 36,
    spreadRadius: -10,
    offset: const Offset(0, 12),
  );
}
