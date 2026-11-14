import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

class AppResizableSidebar extends StatefulWidget {
  const AppResizableSidebar({
    required this.sidebarBuilder,
    required this.child,
    this.foregroundBuilder,
    this.onProgressChanged,
    this.onCollapsedChanged,
    this.initiallyCollapsed = false,
    super.key,
  });

  final Widget Function(BuildContext context, double width, double progress)
  sidebarBuilder;
  final Widget child;
  final Widget Function(
    BuildContext context,
    double sidebarWidth,
    double viewportWidth,
  )?
  foregroundBuilder;

  /// Reports the collapse progress, 0 for the icon rail and 1 for the full
  /// sidebar, whenever the width changes. Never called during build.
  final ValueChanged<double>? onProgressChanged;

  /// Reports once per drag release whether the sidebar settled collapsed or
  /// expanded, so callers can persist the choice without writing on every
  /// animation frame.
  final ValueChanged<bool>? onCollapsedChanged;

  /// The width the sidebar starts at before any drag. Read once in
  /// `initState`.
  final bool initiallyCollapsed;

  @override
  State<AppResizableSidebar> createState() => _AppResizableSidebarState();
}

class _AppResizableSidebarState extends State<AppResizableSidebar>
    with SingleTickerProviderStateMixin {
  late double _width;
  late final AnimationController _snapController;
  double _snapStartWidth = 0;
  double _snapTargetWidth = 0;

  @override
  void initState() {
    super.initState();
    _width = widget.initiallyCollapsed
        ? AppSizes.sidebarCollapsedWidth
        : AppSizes.sidebarExpandedWidth;
    _snapController = AnimationController(
      vsync: this,
      duration: AppMotion.sidebarSnapDuration,
    )..addListener(_handleSnapTick);
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  double get _progress =>
      ((_width - AppSizes.sidebarCollapsedWidth) /
              (AppSizes.sidebarExpandedWidth - AppSizes.sidebarCollapsedWidth))
          .clamp(0.0, 1.0);

  void _handleSnapTick() {
    if (!mounted) return;
    final easedValue = Curves.easeOutQuart.transform(_snapController.value);
    _setWidth(
      _snapStartWidth + ((_snapTargetWidth - _snapStartWidth) * easedValue),
    );
  }

  void _setWidth(double value) {
    final next = value
        .clamp(AppSizes.sidebarCollapsedWidth, AppSizes.sidebarExpandedWidth)
        .toDouble();
    if (next == _width) return;
    setState(() => _width = next);
    widget.onProgressChanged?.call(_progress);
  }

  void _handleDragStart(DragStartDetails details) {
    _snapController.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _setWidth(_width + details.delta.dx);
  }

  void _snapToNearestWidth() {
    final midpoint =
        (AppSizes.sidebarCollapsedWidth + AppSizes.sidebarExpandedWidth) / 2;
    _snapStartWidth = _width;
    final collapsed = _width < midpoint;
    _snapTargetWidth = collapsed
        ? AppSizes.sidebarCollapsedWidth
        : AppSizes.sidebarExpandedWidth;
    _snapController.forward(from: 0);
    widget.onCollapsedChanged?.call(collapsed);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                widget.sidebarBuilder(context, _width, _progress),
                Expanded(child: widget.child),
              ],
            ),
            if (widget.foregroundBuilder case final builder?)
              builder(context, _width, viewportWidth),
            Positioned(
              top: 0,
              bottom: 0,
              left: _width,
              width: AppSizes.sidebarResizeHandleHitWidth,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                opaque: true,
                hitTestBehavior: HitTestBehavior.opaque,
                child: GestureDetector(
                  key: const Key('app-sidebar-resize-handle'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: _handleDragStart,
                  onHorizontalDragUpdate: _handleDragUpdate,
                  onHorizontalDragEnd: (_) => _snapToNearestWidth(),
                  onHorizontalDragCancel: _snapToNearestWidth,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
