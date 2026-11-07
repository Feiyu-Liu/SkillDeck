import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_page_content.dart';
import 'package:skills_manager/shared/widgets/app_selection_area.dart';

abstract final class AppCollapsingHeaderMetrics {
  static const expandedHeight = 124.0;
  static const collapsedHeight = 58.0;
  static const collapseDistance = expandedHeight - collapsedHeight;
  static const pinnedBottomPadding = AppSpacing.lg;
  static const expandedTitleFontSize = 22.0;
  static const collapsedTitleFontSize = 15.0;

  static double expandedExtent(double pinnedContentExtent) =>
      expandedHeight + _pinnedExtra(pinnedContentExtent);

  static double collapsedExtent(double pinnedContentExtent) =>
      collapsedHeight + _pinnedExtra(pinnedContentExtent);

  static double _pinnedExtra(double pinnedContentExtent) =>
      pinnedContentExtent <= 0 ? 0 : pinnedContentExtent + pinnedBottomPadding;
}

class AppCollapsingPageHeader extends StatelessWidget {
  const AppCollapsingPageHeader({
    required this.controller,
    required this.breadcrumb,
    required this.breadcrumbIcon,
    required this.title,
    this.commandLeading,
    this.commandTrailing,
    this.titleActions,
    this.titleAccessory,
    this.pinnedContent,
    this.pinnedContentExtent = 0,
    this.headerKey,
    this.breadcrumbKey,
    this.titleKey,
    this.titleSelectable = false,
    super.key,
  }) : assert(
         pinnedContent != null || pinnedContentExtent == 0,
         'pinnedContentExtent requires pinnedContent.',
       );

  final ScrollController controller;
  final String breadcrumb;
  final IconData breadcrumbIcon;
  final String title;
  final Widget? commandLeading;
  final Widget? commandTrailing;
  final Widget? titleActions;
  final Widget? titleAccessory;
  final Widget? pinnedContent;
  final double pinnedContentExtent;
  final Key? headerKey;
  final Key? breadcrumbKey;
  final Key? titleKey;

  /// Lets the reader drag-select and copy the title text.
  ///
  /// Only the glyphs take pointer input, so scrolling over the rest of the
  /// title row still reaches the page content beneath the header.
  final bool titleSelectable;

  static const _titleOverscrollResistance = 0.35;
  static const _breadcrumbOverscrollResistance = 0.20;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return AppPageContent(
      contentKey: headerKey,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final offset = controller.positions.isEmpty
              ? 0.0
              : controller.positions.first.pixels;
          final rawProgress =
              (offset / AppCollapsingHeaderMetrics.collapseDistance).clamp(
                0.0,
                1.0,
              );
          final progress = disableAnimations
              ? (offset >= AppCollapsingHeaderMetrics.collapseDistance
                    ? 1.0
                    : 0.0)
              : rawProgress;
          final titleOverscrollOffset = disableAnimations || offset >= 0
              ? 0.0
              : -offset * _titleOverscrollResistance;
          final breadcrumbOverscrollOffset = disableAnimations || offset >= 0
              ? 0.0
              : -offset * _breadcrumbOverscrollResistance;
          return CustomMultiChildLayout(
            delegate: _AppPageHeaderLayoutDelegate(
              progress: progress,
              titleOverscrollOffset: titleOverscrollOffset,
              breadcrumbOverscrollOffset: breadcrumbOverscrollOffset,
              pinnedContentExtent: pinnedContentExtent,
            ),
            children: [
              if (commandLeading case final leading?)
                LayoutId(id: _HeaderSlot.leading, child: leading),
              if (commandTrailing case final trailing?)
                LayoutId(id: _HeaderSlot.trailing, child: trailing),
              if (titleActions case final actions?)
                LayoutId(id: _HeaderSlot.titleActions, child: actions),
              LayoutId(
                id: _HeaderSlot.breadcrumb,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 1 - progress,
                    child: Row(
                      key: breadcrumbKey,
                      children: [
                        Icon(
                          breadcrumbIcon,
                          size: 11,
                          color: AppPalette.of(context).textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            breadcrumb,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.of(context).control.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: AppPalette.of(context).textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              LayoutId(
                id: _HeaderSlot.title,
                child: _HeaderTitle(
                  title: title,
                  titleKey: titleKey,
                  selectable: titleSelectable,
                  fontSize:
                      AppCollapsingHeaderMetrics.expandedTitleFontSize -
                      ((AppCollapsingHeaderMetrics.expandedTitleFontSize -
                              AppCollapsingHeaderMetrics
                                  .collapsedTitleFontSize) *
                          progress),
                ),
              ),
              if (titleAccessory case final accessory?)
                LayoutId(id: _HeaderSlot.titleAccessory, child: accessory),
              if (pinnedContent case final content?)
                LayoutId(id: _HeaderSlot.pinnedContent, child: content),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({
    required this.title,
    required this.titleKey,
    required this.selectable,
    required this.fontSize,
  });

  final String title;
  final Key? titleKey;
  final bool selectable;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      key: titleKey,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.of(context).pageTitle.copyWith(fontSize: fontSize),
    );
    if (!selectable) return IgnorePointer(child: text);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppSelectionArea(
        child: MouseRegion(cursor: SystemMouseCursors.text, child: text),
      ),
    );
  }
}

enum _HeaderSlot {
  leading,
  trailing,
  titleActions,
  breadcrumb,
  title,
  titleAccessory,
  pinnedContent,
}

class _AppPageHeaderLayoutDelegate extends MultiChildLayoutDelegate {
  _AppPageHeaderLayoutDelegate({
    required this.progress,
    required this.titleOverscrollOffset,
    required this.breadcrumbOverscrollOffset,
    required this.pinnedContentExtent,
  });

  /// Must match [AppInsets.pageHeader] — a const expression cannot read
  /// an instance field, so the value is repeated rather than referenced.
  static const _controlsTop = 16.0;
  static const _expandedBreadcrumbTop = 58.0;
  static const _expandedTitleTop = 86.0;
  static const _leadingGap = 12.0;
  static const _trailingGap = 16.0;
  static const _titleActionsGap = 16.0;
  static const _titleAccessoryGap = 8.0;

  final double progress;
  final double titleOverscrollOffset;
  final double breadcrumbOverscrollOffset;
  final double pinnedContentExtent;

  @override
  void performLayout(Size size) {
    Size? leadingSize;
    if (hasChild(_HeaderSlot.leading)) {
      leadingSize = layoutChild(
        _HeaderSlot.leading,
        BoxConstraints.loose(size),
      );
      positionChild(_HeaderSlot.leading, const Offset(0, _controlsTop));
    }

    Size? trailingSize;
    if (hasChild(_HeaderSlot.trailing)) {
      trailingSize = layoutChild(
        _HeaderSlot.trailing,
        BoxConstraints.loose(size),
      );
      positionChild(
        _HeaderSlot.trailing,
        Offset(size.width - trailingSize.width, _controlsTop),
      );
    }

    Size? titleActionsSize;
    if (hasChild(_HeaderSlot.titleActions)) {
      titleActionsSize = layoutChild(
        _HeaderSlot.titleActions,
        BoxConstraints.loose(size),
      );
    }
    Size? titleAccessorySize;
    if (hasChild(_HeaderSlot.titleAccessory)) {
      titleAccessorySize = layoutChild(
        _HeaderSlot.titleAccessory,
        BoxConstraints.loose(size),
      );
    }

    final collapsedLeft = leadingSize == null
        ? 0.0
        : leadingSize.width + _leadingGap;
    final collapsedRight = trailingSize == null
        ? size.width
        : size.width - trailingSize.width - _trailingGap;
    final rowRight = _lerp(size.width, collapsedRight, progress);
    final titleActionsLeft = titleActionsSize == null
        ? rowRight
        : rowRight - titleActionsSize.width;
    final titleLeft = _lerp(0, collapsedLeft, progress);
    final titleRight = titleActionsSize == null
        ? rowRight
        : titleActionsLeft - _titleActionsGap;
    final titleWidth = math.max(
      0.0,
      titleRight -
          titleLeft -
          (titleAccessorySize == null
              ? 0
              : titleAccessorySize.width + _titleAccessoryGap),
    );
    final titleSize = layoutChild(
      _HeaderSlot.title,
      BoxConstraints.tightFor(width: titleWidth),
    );

    final expandedRowCenter =
        _expandedTitleTop +
        (AppCollapsingHeaderMetrics.expandedTitleFontSize *
            AppTypography.pageTitle.height! /
            2);
    final anchorHeight = math.max(
      leadingSize?.height ?? 0,
      trailingSize?.height ?? 0,
    );
    final collapsedRowCenter =
        _controlsTop +
        ((anchorHeight == 0 ? AppSizes.pageCommandBarHeight : anchorHeight) /
            2);
    final rowCenter =
        _lerp(expandedRowCenter, collapsedRowCenter, progress) +
        titleOverscrollOffset;
    positionChild(
      _HeaderSlot.title,
      Offset(titleLeft, rowCenter - (titleSize.height / 2)),
    );
    if (titleAccessorySize != null) {
      positionChild(
        _HeaderSlot.titleAccessory,
        Offset(
          titleLeft + titleSize.width + _titleAccessoryGap,
          rowCenter - (titleAccessorySize.height / 2),
        ),
      );
    }
    if (titleActionsSize != null) {
      positionChild(
        _HeaderSlot.titleActions,
        Offset(titleActionsLeft, rowCenter - (titleActionsSize.height / 2)),
      );
    }

    layoutChild(
      _HeaderSlot.breadcrumb,
      BoxConstraints.tightFor(width: size.width, height: 20),
    );
    positionChild(
      _HeaderSlot.breadcrumb,
      Offset(
        0,
        _expandedBreadcrumbTop - (24 * progress) + breadcrumbOverscrollOffset,
      ),
    );

    if (hasChild(_HeaderSlot.pinnedContent)) {
      layoutChild(
        _HeaderSlot.pinnedContent,
        BoxConstraints.tightFor(width: size.width, height: pinnedContentExtent),
      );
      positionChild(
        _HeaderSlot.pinnedContent,
        Offset(
          0,
          _lerp(
                AppCollapsingHeaderMetrics.expandedHeight,
                AppCollapsingHeaderMetrics.collapsedHeight,
                progress,
              ) +
              titleOverscrollOffset,
        ),
      );
    }
  }

  double _lerp(double start, double end, double t) =>
      start + ((end - start) * t);

  @override
  bool shouldRelayout(covariant _AppPageHeaderLayoutDelegate oldDelegate) =>
      progress != oldDelegate.progress ||
      titleOverscrollOffset != oldDelegate.titleOverscrollOffset ||
      breadcrumbOverscrollOffset != oldDelegate.breadcrumbOverscrollOffset ||
      pinnedContentExtent != oldDelegate.pinnedContentExtent;
}
