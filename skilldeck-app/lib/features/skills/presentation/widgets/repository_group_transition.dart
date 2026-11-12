import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// Collapses a lazy sliver upward beneath a temporary surface veil.
class RepositoryGroupTransition extends StatefulWidget {
  const RepositoryGroupTransition({
    required this.collapsed,
    required this.sliver,
    required this.searchQuery,
    super.key,
  });

  final bool collapsed;
  final Widget sliver;
  final String searchQuery;

  @override
  State<RepositoryGroupTransition> createState() =>
      _RepositoryGroupTransitionState();
}

class _RepositoryGroupTransitionState extends State<RepositoryGroupTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: widget.collapsed ? 0 : 1,
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = widget.collapsed ? 0 : 1;
  }

  @override
  void didUpdateWidget(RepositoryGroupTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.collapsed ? 0.0 : 1.0;
    if (_reduceMotion || oldWidget.searchQuery != widget.searchQuery) {
      _controller.value = target;
    } else if (oldWidget.collapsed != widget.collapsed) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutQuart,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.sliver,
    builder: (context, child) {
      if (_controller.value == 0) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      final progress = _controller.value;
      return SliverIgnorePointer(
        ignoring: _controller.isAnimating,
        sliver: _GroupReveal(
          progress: progress,
          veil: AppPalette.of(context).surface,
          child: child!,
        ),
      );
    },
  );
}

class _GroupReveal extends SingleChildRenderObjectWidget {
  const _GroupReveal({
    required this.progress,
    required this.veil,
    required super.child,
  });

  final double progress;
  final Color veil;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGroupReveal(progress, veil);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGroupReveal renderObject,
  ) {
    renderObject.update(progress, veil);
  }
}

/// Slides content by exactly the removed extent, keeping its trailing edge
/// attached to the following group. Cache the full extent during motion so a
/// lazy list is not laid out twice at distant offsets on every frame.
class _RenderGroupReveal extends RenderProxySliver {
  _RenderGroupReveal(this._progress, this._veil);

  double _progress;
  Color _veil;
  double? _fullExtent;
  double? _crossAxisExtent;

  void update(double progress, Color veil) {
    if (_progress == progress && _veil == veil) return;
    _progress = progress;
    _veil = veil;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    assert(constraints.axisDirection == AxisDirection.down);
    if (_progress == 1 ||
        _fullExtent == null ||
        _crossAxisExtent != constraints.crossAxisExtent) {
      child!.layout(constraints, parentUsesSize: true);
      final original = child!.geometry!;
      if (original.scrollOffsetCorrection != null) {
        geometry = original;
        return;
      }
      _fullExtent = original.scrollExtent;
      _crossAxisExtent = constraints.crossAxisExtent;
      if (_progress == 1) {
        geometry = original;
        return;
      }
    }
    final extent = _fullExtent! * _progress;
    final hidden = _fullExtent! - extent;
    child!.layout(
      constraints.copyWith(scrollOffset: constraints.scrollOffset + hidden),
      parentUsesSize: true,
    );
    final revealed = child!.geometry!;
    if (revealed.scrollOffsetCorrection != null) {
      geometry = revealed;
      return;
    }
    final paintExtent = math.min(
      revealed.paintExtent,
      calculatePaintOffset(constraints, from: 0, to: extent),
    );
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: paintExtent,
      layoutExtent: math.min(revealed.layoutExtent, paintExtent),
      maxPaintExtent: math.max(extent, paintExtent),
      cacheExtent: math.min(
        revealed.cacheExtent,
        calculateCacheOffset(constraints, from: 0, to: extent),
      ),
      hasVisualOverflow: true,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!geometry!.visible) return;
    // Only clip while folding. At rest, cards may paint their hover scale and
    // shadows beyond the group's layout bounds, just as in the ungrouped view.
    if (_progress == 1) {
      context.paintChild(child!, offset);
      return;
    }
    final bounds = Rect.fromLTWH(
      0,
      0,
      constraints.crossAxisExtent,
      geometry!.paintExtent,
    );
    context.pushClipRect(needsCompositing, offset, bounds, (context, offset) {
      context.paintChild(child!, offset);
      // Fade in quickly on collapse, clear gently at the end of expansion.
      final strength = ((1 - _progress) * 5).clamp(0.0, 1.0);
      if (strength == 0) return;
      final veilRect = Rect.fromLTWH(
        offset.dx,
        offset.dy,
        constraints.crossAxisExtent,
        math.min(48, geometry!.paintExtent),
      );
      context.canvas.drawRect(
        veilRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _veil.withValues(alpha: strength),
              _veil.withValues(alpha: strength * 0.65),
              _veil.withValues(alpha: 0),
            ],
            stops: const [0, 0.35, 1],
          ).createShader(veilRect),
      );
    });
  }
}
