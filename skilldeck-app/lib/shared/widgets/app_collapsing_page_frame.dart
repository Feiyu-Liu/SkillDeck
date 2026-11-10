import 'package:flutter/cupertino.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/shared/theme/app_palette.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_header.dart';

class AppCollapsingPageFrame extends StatelessWidget {
  const AppCollapsingPageFrame({
    required this.controller,
    required this.breadcrumb,
    required this.breadcrumbIcon,
    required this.title,
    required this.child,
    this.commandLeading,
    this.commandTrailing,
    this.titleActions,
    this.titleAccessory,
    this.pinnedContent,
    this.pinnedContentExtent = 0,
    this.bottomOverlay,
    this.bottomOverlayInset = 16,
    this.headerKey,
    this.breadcrumbKey,
    this.titleKey,
    this.titleSelectable = false,
    this.blurKey,
    super.key,
  });

  final ScrollController controller;
  final String breadcrumb;
  final IconData breadcrumbIcon;
  final String title;
  final Widget child;
  final Widget? commandLeading;
  final Widget? commandTrailing;
  final Widget? titleActions;
  final Widget? titleAccessory;
  final Widget? pinnedContent;
  final double pinnedContentExtent;
  final Widget? bottomOverlay;
  final double bottomOverlayInset;
  final Key? headerKey;
  final Key? breadcrumbKey;
  final Key? titleKey;
  final bool titleSelectable;
  final Key? blurKey;

  /// How far the top blur keeps fading below the collapsed header edge.
  ///
  /// This is the only part of the ramp the reader actually sees, so it governs
  /// how gradually content softens as it scrolls under the header. The shared
  /// ramp spends its shallow toe here, which is why it is much taller than the
  /// visible transition appears.
  static const blurFadeExtension = 80.0;

  /// Whether the top blur runs its shader.
  ///
  /// Widget tests render on the CPU, where the shader reblurs the whole page
  /// on every repaint and costs seconds per frame. `flutter_test_config.dart`
  /// turns it off; a test about the blur turns it back on.
  @visibleForTesting
  static bool blurEnabled = true;

  /// Vertical white veil composited over the blurred region.
  ///
  /// Blur alone only removes detail; it leaves contrast intact, so blurred
  /// dark text stays a high-contrast shape that pulls the eye. Worse, text is
  /// most distracting while it is still *barely* legible, because the reader
  /// keeps trying to resolve it.
  ///
  /// This veil drops contrast independently of the blur ramp. It is weighted
  /// to rise steeply across the band where the blur measures roughly 2-8
  /// sigma — enough to smear glyphs but not enough to destroy them — so text
  /// has already receded before it can become an attention magnet. The blur
  /// shader's own tint is left off (`surfaceTransparent`) because it couples
  /// to blur strength and would collapse exactly where it is needed most.
  static const _veilColors = <Color>[
    Color(0x9EFFFFFF),
    Color(0x99FFFFFF),
    Color(0x8CFFFFFF),
    Color(0x73FFFFFF),
    Color(0x52FFFFFF),
    Color(0x36FFFFFF),
    Color(0x1FFFFFFF),
    Color(0x0FFFFFFF),
    Color(0x05FFFFFF),
    Color(0x00FFFFFF),
  ];
  static const _veilStops = <double>[
    0,
    0.25,
    0.45,
    0.62,
    0.72,
    0.8,
    0.87,
    0.93,
    0.97,
    1,
  ];

  @override
  Widget build(BuildContext context) {
    final expandedExtent = AppCollapsingHeaderMetrics.expandedExtent(
      pinnedContent == null ? 0 : pinnedContentExtent,
    );
    final collapsedExtent = AppCollapsingHeaderMetrics.collapsedExtent(
      pinnedContent == null ? 0 : pinnedContentExtent,
    );
    final blurExtent = collapsedExtent + blurFadeExtension;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        if (blurEnabled)
          MyTopProgressiveBlur(
            key: blurKey,
            blurExtent: blurExtent,
            tintColor: AppPalette.of(context).surfaceTransparent,
            edgeGuardColor: AppPalette.of(context).surface,
            child: child,
          )
        else
          KeyedSubtree(key: blurKey, child: child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: blurExtent,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    for (final color in _veilColors)
                      AppPalette.of(context).surfaceVeil(color),
                  ],
                  stops: _veilStops,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: expandedExtent,
          child: AppCollapsingPageHeader(
            controller: controller,
            breadcrumb: breadcrumb,
            breadcrumbIcon: breadcrumbIcon,
            title: title,
            commandLeading: commandLeading,
            commandTrailing: commandTrailing,
            titleActions: titleActions,
            titleAccessory: titleAccessory,
            pinnedContent: pinnedContent,
            pinnedContentExtent: pinnedContentExtent,
            headerKey: headerKey,
            breadcrumbKey: breadcrumbKey,
            titleKey: titleKey,
            titleSelectable: titleSelectable,
          ),
        ),
        if (bottomOverlay case final overlay?)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomOverlayInset,
            child: Center(child: overlay),
          ),
      ],
    );
  }
}
