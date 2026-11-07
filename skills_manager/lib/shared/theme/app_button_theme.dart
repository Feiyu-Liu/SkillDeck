import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';

import 'app_colors.dart';
import 'app_corners.dart';
import 'app_metrics.dart';
import 'app_palette.dart';
import 'app_typography.dart';

import 'package:skills_manager/shared/widgets/app_tooltip.dart';

abstract final class SkillsButtonTheme {
  static const warningForeground = NeoColor(
    light: AppColors.warningStrong,
    dark: Color(0xFFE3A44A),
  );
  static const warningCard = NeoColor(
    light: AppColors.warningSoft,
    dark: Color(0xFF2D2316),
  );
  static const warningHover = NeoColor(
    light: AppColors.warningSoftHovered,
    dark: Color(0xFF3B2D1A),
  );
  static const warningBorder = NeoColor(
    light: AppColors.warningBorder,
    dark: Color(0xFF6D502B),
  );

  static const neo = NeoButtonThemeData(
    palette: NeoButtonPalette(
      foreground: NeoColor(light: AppColors.ink, dark: Color(0xFFF2F2F3)),
      card: NeoColor(light: AppColors.white, dark: Color(0xFF252528)),
      primary: NeoColor(light: AppColors.ink, dark: Color(0xFFEBEBED)),
      primaryForeground: NeoColor(
        light: AppColors.white,
        dark: Color(0xFF161618),
      ),
      mutedForeground: NeoColor(
        light: AppColors.textSecondary,
        dark: Color(0xFF8D8D94),
      ),
      hoverSurface: NeoColor(
        light: AppColors.surfaceMuted,
        dark: Color(0xFF27272A),
      ),
      hoverForeground: NeoColor(light: AppColors.ink, dark: Color(0xFFF2F2F3)),
      destructive: NeoColor(
        light: AppColors.dangerFill,
        dark: Color(0xFFE53535),
      ),
      border: NeoColor(light: AppColors.borderStrong, dark: Color(0x1AFFFFFF)),
      shadow: NeoColor(light: AppColors.ink, dark: Color(0xFF000000)),
    ),
    small: NeoButtonSizeSpec(
      height: 26,
      horizontalPadding: 9,
      iconSize: 12,
      fontSize: 12,
    ),
    medium: NeoButtonSizeSpec(
      height: AppSizes.buttonHeight,
      horizontalPadding: 11,
      iconSize: 14,
      fontSize: 12.5,
    ),
    large: NeoButtonSizeSpec(
      height: 36,
      horizontalPadding: 13,
      iconSize: 16,
      fontSize: 13,
    ),
    iconButton: NeoIconButtonSpec(diameter: 30, iconSize: 14),
    smoothness: 0.8,
    enableHapticFeedback: false,
  );

  static const morphingMenu = MorphingMenuButtonThemeData(
    style: MorphingMenuButtonStyle(
      collapsedBackgroundColor: AppColors.white,
      collapsedHoverColor: AppColors.propertyCardBackground,
      collapsedPressedColor: AppColors.surfaceMuted,
      expandedBackgroundColor: AppColors.white,
      foregroundColor: AppColors.ink,
      borderColor: AppColors.borderStrong,
      focusedBorderColor: AppColors.textSecondary,
      shadowColor: AppColors.ink,
      dragHandleColor: AppColors.controlInactive,
      triggerPadding: EdgeInsets.symmetric(horizontal: 11),
      panelPadding: EdgeInsets.all(8),
      textStyle: AppTypography.control,
      buttonHeight: 30,
      minButtonWidth: 30,
      iconSize: 14,
      collapsedRadius: 11.5,
      expandedRadius: 16,
      smoothness: 0.8,
      borderWidth: 0.5,
      collapsedShadow: BoxShadow(
        color: Color(0x0D000000),
        blurRadius: 6,
        offset: Offset(0, 1.5),
      ),
      expandedShadow: BoxShadow(
        color: Color(0x22000000),
        blurRadius: 36,
        offset: Offset(0, 16),
        spreadRadius: -8,
      ),
      duration: Duration(milliseconds: 600),
      reverseDuration: Duration(milliseconds: 600),
      openCurve: ElasticOutCurve(1.4),
      closeCurve: ElasticOutCurve(1.4),
    ),
  );

  static const darkPrimaryStyle = NeoButtonVisualStyle(
    foregroundColor: Color(0xFF161618),
    fontWeight: FontWeight.w600,
    fillGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFAFAFA), Color(0xFFD9D9DC)],
    ),
    borderGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xE6FFFFFF), Color(0xFFB8B8BD)],
    ),
    borderWidth: 0.66,
    innerHighlightColor: Color(0xB3FFFFFF),
    dropShadow: BoxShadow(
      color: Color(0x80000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
    hoverOverlayColor: Color(0x20FFFFFF),
  );

  static const darkSecondaryStyle = NeoButtonVisualStyle(
    foregroundColor: Color(0xFFF2F2F3),
    fontWeight: FontWeight.w500,
    fillColor: Color(0xFF252528),
    borderColor: Color(0x1AFFFFFF),
    borderWidth: 0.66,
    dropShadow: BoxShadow(
      color: Color(0x59000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
    hoverOverlayColor: Color(0xFF27272A),
  );

  static NeoButtonVisualStyle darkSecondaryFor(NeoButtonPalette palette) =>
      NeoButtonVisualStyle(
        foregroundColor: palette.foreground.dark,
        fontWeight: FontWeight.w500,
        fillColor: palette.card.dark,
        borderColor: palette.border.dark,
        borderWidth: darkSecondaryStyle.borderWidth,
        dropShadow: darkSecondaryStyle.dropShadow,
        hoverOverlayColor: palette.hoverSurface.dark,
        hoverForegroundColor: palette.hoverForeground.dark,
      );

  static NeoButtonVisualStyle resolveStyle(
    BuildContext context,
    NeoButtonVariant variant,
  ) {
    final brightness = AppPalette.of(context).brightness;
    if (brightness == Brightness.dark) {
      if (variant == NeoButtonVariant.primary) return darkPrimaryStyle;
      if (variant == NeoButtonVariant.secondary) return darkSecondaryStyle;
    }
    return resolveNeoButtonStyle(
      variant: variant,
      brightness: brightness,
      palette: NeoButtonTheme.of(context).palette,
    );
  }

  static MorphingMenuButtonThemeData morphingMenuFor(BuildContext context) {
    final colors = AppPalette.of(context);
    if (colors.brightness == Brightness.light) return morphingMenu;
    return MorphingMenuButtonThemeData(
      style: morphingMenu.style.copyWith(
        collapsedBackgroundColor: const Color(0xFF252528),
        collapsedHoverColor: colors.surfaceMuted,
        collapsedPressedColor: colors.borderStrong,
        expandedBackgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        borderColor: const Color(0x1AFFFFFF),
        focusedBorderColor: colors.textSecondary,
        shadowColor: const Color(0xFF000000),
        dragHandleColor: colors.controlInactive,
        textStyle: AppTypography.control.copyWith(color: colors.textSecondary),
        collapsedShadow: const BoxShadow(
          color: Color(0x59000000),
          blurRadius: 6,
          offset: Offset(0, 1.5),
        ),
        expandedShadow: const BoxShadow(
          color: Color(0x66000000),
          blurRadius: 36,
          offset: Offset(0, 16),
          spreadRadius: -8,
        ),
      ),
    );
  }

  static MorphingMenuButtonStyle translationTriggerStyle(
    BuildContext context, {
    required bool filled,
  }) {
    final colors = AppPalette.of(context);
    final palette = neo.palette;
    final style = colors.brightness == Brightness.dark
        ? (filled ? darkPrimaryStyle : darkSecondaryStyle)
        : resolveNeoButtonStyle(
            variant: filled
                ? NeoButtonVariant.primary
                : NeoButtonVariant.secondary,
            brightness: colors.brightness,
            palette: palette,
          );
    final surface = (filled ? palette.primary : palette.card).resolve(
      colors.brightness,
    );
    return morphingMenuFor(context).style.copyWith(
      collapsedBackgroundColor: surface,
      collapsedHoverColor: filled
          ? surface
          : palette.hoverSurface.resolve(colors.brightness),
      collapsedPressedColor: filled ? surface : colors.surfaceMuted,
      foregroundColor: style.foregroundColor,
      borderColor: style.borderColor ?? surface,
      borderWidth: style.borderWidth,
      collapsedShadow:
          style.dropShadow ?? const BoxShadow(color: AppColors.transparent),
      collapsedRadius: 17,
      smoothness: 0,
      triggerPadding: EdgeInsets.zero,
      panelPadding: const EdgeInsets.all(16),
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = NeoButtonVariant.secondary,
    this.size = NeoButtonSize.medium,
    this.height,
    this.textStyle,
    this.fullWidth = false,
    this.loading = false,
    this.contentAlignment = MainAxisAlignment.center,
    this.semanticsLabel,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NeoButtonVariant style;
  final NeoButtonSize size;
  final double? height;
  final TextStyle? textStyle;
  final bool fullWidth;

  /// Whether the button shows its spinner in place of [icon].
  ///
  /// Business state drives this; the button never infers it from [onPressed].
  final bool loading;

  final MainAxisAlignment contentAlignment;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if ((style == NeoButtonVariant.primary ||
            style == NeoButtonVariant.secondary) &&
        AppPalette.of(context).brightness == Brightness.dark) {
      final theme = NeoButtonTheme.of(context);
      final visual = style == NeoButtonVariant.primary
          ? SkillsButtonTheme.darkPrimaryStyle
          : SkillsButtonTheme.darkSecondaryFor(theme.palette);
      final spec = theme.specFor(
        height == null ? size : _buttonSizeForHeight(height!),
      );
      return _DarkPrimarySurface(
        style: visual,
        onPressed: loading ? null : onPressed,
        semanticsLabel: semanticsLabel ?? label,
        height: spec.height,
        radius: spec.radiusFor(theme.radiusRatio),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spec.horizontalPadding),
          child: Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: contentAlignment,
            children: [
              if (loading) ...[
                CupertinoActivityIndicator(
                  radius: theme.spinnerRadius,
                  color: visual.foregroundColor,
                ),
                SizedBox(width: theme.contentSpacing),
              ] else if (icon != null) ...[
                Icon(icon, size: spec.iconSize, color: visual.foregroundColor),
                SizedBox(width: theme.contentSpacing),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: spec.fontSize,
                    fontWeight: FontWeight.w600,
                    color: visual.foregroundColor,
                  ).merge(textStyle),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final button = NeoButton(
      label,
      icon: icon,
      variant: style,
      size: height == null ? size : _buttonSizeForHeight(height!),
      textStyle: textStyle,
      fullWidth: fullWidth,
      loading: loading,
      contentAlignment: contentAlignment,
      semanticsLabel: semanticsLabel,
      // Preserve the old command-button contract: business state owns loading.
      // Some VoidCallbacks invoke async dialogs, which must not keep the
      // button's internal spinner alive until the dialog closes.
      onPressed: onPressed == null
          ? null
          : () {
              onPressed!();
            },
    );
    if (!loading) return button;
    // NeoButton deliberately keeps a loading button at full opacity; this App
    // wants the busy button to read as unavailable too, so dim it here with the
    // same opacity a disabled button uses.
    return Opacity(
      opacity: NeoButtonTheme.of(context).disabledOpacity,
      child: button,
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.style = NeoButtonVariant.secondary,
    this.buttonSize = NeoButtonSize.small,
    this.size,
    this.iconSize,
    this.foregroundColor,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final NeoButtonVariant style;
  final NeoButtonSize buttonSize;
  final double? size;
  final double? iconSize;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: tooltip,
    child:
        (style == NeoButtonVariant.primary ||
                style == NeoButtonVariant.secondary) &&
            AppPalette.of(context).brightness == Brightness.dark
        ? _DarkPrimarySurface(
            style: style == NeoButtonVariant.primary
                ? SkillsButtonTheme.darkPrimaryStyle
                : SkillsButtonTheme.darkSecondaryStyle,
            onPressed: onPressed,
            semanticsLabel: tooltip,
            height: size ?? _buttonDiameter(buttonSize),
            radius: (size ?? _buttonDiameter(buttonSize)) / 2,
            circular: true,
            child: Center(
              child: Icon(
                icon,
                size: iconSize ?? 15,
                color:
                    foregroundColor ??
                    (style == NeoButtonVariant.primary
                        ? SkillsButtonTheme.darkPrimaryStyle.foregroundColor
                        : SkillsButtonTheme.darkSecondaryStyle.foregroundColor),
              ),
            ),
          )
        : NeoIconButton(
            icon: icon,
            semanticsLabel: tooltip,
            variant: style,
            diameter: size ?? _buttonDiameter(buttonSize),
            iconSize: iconSize,
            tint: foregroundColor,
            onPressed: onPressed,
          ),
  );
}

class _DarkPrimarySurface extends StatefulWidget {
  const _DarkPrimarySurface({
    required this.style,
    required this.onPressed,
    required this.semanticsLabel,
    required this.height,
    required this.radius,
    required this.child,
    this.circular = false,
  });
  final VoidCallback? onPressed;
  final NeoButtonVisualStyle style;
  final String semanticsLabel;
  final double height;
  final double radius;
  final Widget child;
  final bool circular;

  @override
  State<_DarkPrimarySurface> createState() => _DarkPrimarySurfaceState();
}

class _DarkPrimarySurfaceState extends State<_DarkPrimarySurface> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.style;
    final style = base.withHover(hovered ? 1 : 0).withPress(pressed ? 1 : 0);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() {
        hovered = false;
        pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => pressed = true),
        onPointerUp: (_) => setState(() => pressed = false),
        onPointerCancel: (_) => setState(() => pressed = false),
        child: NeoPressable(
          onPressed: widget.onPressed,
          semanticsLabel: widget.semanticsLabel,
          child: NeoSurface(
            style: style,
            borderRadius: widget.radius,
            shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
            child: SizedBox(
              height: widget.height,
              width: widget.circular ? widget.height : null,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

NeoButtonSize _buttonSizeForHeight(double height) {
  if (height <= 26) return NeoButtonSize.small;
  if (height <= 30) return NeoButtonSize.medium;
  return NeoButtonSize.large;
}

double _buttonDiameter(NeoButtonSize size) => switch (size) {
  NeoButtonSize.small => 26,
  NeoButtonSize.medium => 30,
  NeoButtonSize.large => 36,
};

class AppMorphingMenuOption extends StatefulWidget {
  const AppMorphingMenuOption({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.leading,
    this.subtitle,
    this.accessory,
    super.key,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final Widget? leading;

  /// A small control right after the label, such as an "open folder" button.
  /// It receives its own taps, so the option is not chosen through it.
  final Widget? accessory;
  final VoidCallback onPressed;

  @override
  State<AppMorphingMenuOption> createState() => _AppMorphingMenuOptionState();
}

class _AppMorphingMenuOptionState extends State<AppMorphingMenuOption> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final emphasized = widget.selected || _hovered || _focused;
    final colors = AppPalette.of(context);
    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          container: true,
          button: true,
          selected: widget.selected,
          enabled: true,
          label: widget.label,
          onTap: widget.onPressed,
          child: ExcludeSemantics(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              pressedOpacity: 0.72,
              onPressed: widget.onPressed,
              child: Container(
                height: widget.subtitle == null ? 38 : 54,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: AppCorners.smooth(
                  color: emphasized ? colors.surfaceMuted : colors.transparent,
                  radius: 9,
                  side: _focused
                      ? BorderSide(color: colors.textSecondary)
                      : BorderSide.none,
                ),
                child: Row(
                  children: [
                    if (widget.leading case final leading?) ...[
                      SizedBox.square(
                        dimension: 18,
                        child: Center(child: leading),
                      ),
                      const SizedBox(width: 9),
                    ],
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(child: _label(colors)),
                          if (widget.accessory case final accessory?) ...[
                            const SizedBox(width: 6),
                            accessory,
                          ],
                        ],
                      ),
                    ),
                    if (widget.selected) ...[
                      const SizedBox(width: 8),
                      Icon(
                        LucideIcons.check,
                        size: 15,
                        color: colors.textPrimary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(AppPalette colors) => Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.control.copyWith(color: colors.textPrimary),
      ),
      if (widget.subtitle case final subtitle?)
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
    ],
  );
}

/// A hairline between groups of [AppMorphingMenuOption]s.
class AppMorphingMenuDivider extends StatelessWidget {
  const AppMorphingMenuDivider({super.key});

  /// The vertical space it takes, for menus that size themselves.
  static const height = 9.0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: SizedBox(
      width: double.infinity,
      height: 1,
      child: ColoredBox(color: AppPalette.of(context).divider),
    ),
  );
}
