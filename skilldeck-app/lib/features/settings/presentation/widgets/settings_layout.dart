import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// Title and one-line explanation at the top of a Settings section.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    required this.title,
    this.description,
    super.key,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: AppTypography.of(context).title),
      if (description case final description?) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(description, style: AppTypography.of(context).bodyMuted),
      ],
    ],
  );
}

/// A labelled card of [children], separated by hairline dividers.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    required this.children,
    this.label,
    this.trailing,
    super.key,
  });

  final String? label;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null || trailing != null) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                label ?? '',
                style: _settingsGroupLabelStyle.copyWith(
                  color: AppPalette.of(context).textSecondary,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      DecoratedBox(
        decoration: AppCorners.smooth(
          color: AppPalette.of(context).surfaceSubtle,
          radius: AppRadii.lg,
          side: BorderSide(color: AppPalette.of(context).border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, child) in children.indexed) ...[
                if (index > 0)
                  SizedBox(
                    height: 1,
                    child: ColoredBox(color: AppPalette.of(context).border),
                  ),
                child,
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

const _settingsGroupLabelStyle = TextStyle(
  fontFamily: AppFonts.ui,
  fontFamilyFallback: AppFonts.fallback,
  fontSize: 11.5,
  fontWeight: FontWeight.w600,
);

/// One row of a [SettingsGroup]: a title with an optional description on the
/// left and the control that changes it on the right.
///
/// When the control would leave the title less than
/// [_minimumTextWidth], it moves under the title instead of squeezing it.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    this.description,
    this.descriptionWidget,
    this.leading,
    this.trailing,
    this.below,
    super.key,
  }) : assert(description == null || descriptionWidget == null);

  final String title;
  final String? description;

  /// A description that needs its own key or style.
  final Widget? descriptionWidget;
  final Widget? leading;
  final Widget? trailing;

  /// Content that spans the row under the title, such as a progress bar.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final description =
        descriptionWidget ??
        switch (this.description) {
          final text? => Text(text, style: AppTypography.of(context).caption),
          null => null,
        };
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: _settingsRowTitleStyle.copyWith(
            color: AppPalette.of(context).textPrimary,
          ),
        ),
        if (description != null) ...[const SizedBox(height: 3), description],
        if (below case final below?) ...[
          const SizedBox(height: AppSpacing.sm),
          below,
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 14,
      ),
      child: Row(
        children: [
          if (leading case final leading?) ...[
            leading,
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: switch (trailing) {
              final trailing? => SettingsTrailingLayout(
                children: [text, trailing],
              ),
              null => text,
            },
          ),
        ],
      ),
    );
  }
}

const _minimumTextWidth = 200.0;
const _trailingGap = AppSpacing.xl;
const _stackedGap = AppSpacing.md;

/// Places its second child to the right of the first when both fit, and under
/// it otherwise. The first child always takes the remaining width.
class SettingsTrailingLayout extends MultiChildRenderObjectWidget {
  const SettingsTrailingLayout({required super.children, super.key})
    : assert(children.length == 2);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAdaptiveTrailing();
}

class _AdaptiveTrailingParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAdaptiveTrailing extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AdaptiveTrailingParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _AdaptiveTrailingParentData
        > {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AdaptiveTrailingParentData) {
      child.parentData = _AdaptiveTrailingParentData();
    }
  }

  RenderBox get _main => firstChild!;
  RenderBox get _trailing => lastChild!;

  bool _sideBySide(double maxWidth) =>
      _trailing.getMaxIntrinsicWidth(double.infinity) +
          _trailingGap +
          _minimumTextWidth <=
      maxWidth;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _main.getMinIntrinsicWidth(height),
    _trailing.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _main.getMaxIntrinsicWidth(height) +
      _trailingGap +
      _trailing.getMaxIntrinsicWidth(height);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  void performLayout() => size = _layout(constraints, dry: false);

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final maxWidth = constraints.maxWidth;
    Size measure(RenderBox child, BoxConstraints childConstraints) => dry
        ? child.getDryLayout(childConstraints)
        : (child..layout(childConstraints, parentUsesSize: true)).size;

    if (_sideBySide(maxWidth)) {
      final trailing = measure(
        _trailing,
        BoxConstraints(maxWidth: maxWidth - _trailingGap - _minimumTextWidth),
      );
      final mainWidth = maxWidth - _trailingGap - trailing.width;
      final main = measure(_main, BoxConstraints.tightFor(width: mainWidth));
      final height = math.max(main.height, trailing.height);
      if (!dry) {
        _offset(_main, Offset(0, (height - main.height) / 2));
        _offset(
          _trailing,
          Offset(maxWidth - trailing.width, (height - trailing.height) / 2),
        );
      }
      return constraints.constrain(Size(maxWidth, height));
    }
    final main = measure(_main, BoxConstraints.tightFor(width: maxWidth));
    final trailing = measure(_trailing, BoxConstraints(maxWidth: maxWidth));
    if (!dry) {
      _offset(_main, Offset.zero);
      _offset(_trailing, Offset(0, main.height + _stackedGap));
    }
    return constraints.constrain(
      Size(maxWidth, main.height + _stackedGap + trailing.height),
    );
  }

  void _offset(RenderBox child, Offset offset) =>
      (child.parentData! as _AdaptiveTrailingParentData).offset = offset;

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

const _settingsRowTitleStyle = TextStyle(
  fontFamily: AppFonts.ui,
  fontFamilyFallback: AppFonts.fallback,
  fontSize: 13,
  fontWeight: FontWeight.w500,
);

/// A muted note at the bottom of a [SettingsGroup].
class SettingsFootnote extends StatelessWidget {
  const SettingsFootnote(this.text, {this.icon, super.key});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: 10,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon case final icon?) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: AppSizes.iconXs,
              color: AppPalette.of(context).textMuted,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(child: Text(text, style: AppTypography.of(context).caption)),
      ],
    ),
  );
}

/// A labelled group of [SettingsNavItem]s in the Settings section list.
class SettingsNavGroup extends StatelessWidget {
  const SettingsNavGroup({
    required this.label,
    required this.children,
    super.key,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            bottom: AppSpacing.xs,
          ),
          child: Text(
            label,
            style: _settingsGroupLabelStyle.copyWith(
              color: AppPalette.of(context).textSecondary,
            ),
          ),
        ),
        for (final child in children)
          Padding(padding: const EdgeInsets.only(top: 2), child: child),
      ],
    ),
  );
}

/// A flat Settings navigation entry. The selected entry sits on a muted fill.
class SettingsNavItem extends StatefulWidget {
  const SettingsNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<SettingsNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final foreground = selected
        ? AppPalette.of(context).textPrimary
        : AppPalette.of(context).bodyContent;
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: AppSizes.navItemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: AppCorners.smooth(
              color: selected
                  ? AppPalette.of(context).surfaceMuted
                  : _hovered
                  ? AppPalette.of(context).surfaceSubtle
                  : AppPalette.of(context).surfaceTransparent,
              radius: AppRadii.control,
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: AppSizes.iconMd - 1,
                  color: selected
                      ? AppPalette.of(context).textPrimary
                      : AppPalette.of(context).textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (selected
                                ? AppTypography.of(context).navigationSelected
                                : AppTypography.of(context).navigation)
                            .copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
