import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

class AppTooltip extends StatefulWidget {
  const AppTooltip({
    required this.message,
    required this.child,
    this.content,
    this.waitDuration = const Duration(milliseconds: 500),
    this.maxWidth = 240,
    this.maxLines = 2,
    this.offset = const Offset(0, 8),
    super.key,
  });

  final String? message;
  final Widget child;

  /// Rich tooltip body drawn in place of [message], which then only needs to
  /// say the same thing in words.
  final Widget? content;
  final Duration waitDuration;
  final double maxWidth;
  final int? maxLines;
  final Offset offset;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  final _controller = OverlayPortalController();
  Timer? _timer;

  bool get _hasMessage =>
      widget.content != null || (widget.message?.isNotEmpty ?? false);

  @override
  void didUpdateWidget(covariant AppTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasMessage) _hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showLater() {
    if (!_hasMessage) return;
    _timer?.cancel();
    _timer = Timer(widget.waitDuration, () {
      if (mounted) _controller.show();
    });
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _controller.hide();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _showLater(),
    onExit: (_) => _hide(),
    child: Listener(
      onPointerDown: (_) => _hide(),
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _controller,
        overlayChildBuilder: (context, info) {
          final rect = MatrixUtils.transformRect(
            info.childPaintTransform,
            Offset.zero & info.childSize,
          );
          final right = (info.overlaySize.width - rect.right).clamp(
            8.0,
            info.overlaySize.width - 8,
          );
          final width = (info.overlaySize.width - right - 8).clamp(
            0.0,
            widget.maxWidth,
          );
          return Positioned(
            key: const ValueKey<String>('app-tooltip-positioned'),
            right: right,
            top: rect.bottom + widget.offset.dy,
            child: Transform.translate(
              offset: Offset(widget.offset.dx, 0),
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey<String>('app-tooltip-surface'),
                  constraints: BoxConstraints(maxWidth: width),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: AppCorners.smooth(
                    color: AppPalette.of(context).tooltipBackground,
                    radius: 6,
                  ),
                  child:
                      widget.content ??
                      Text(
                        widget.message!,
                        maxLines: widget.maxLines,
                        overflow: widget.maxLines == null
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: AppTypography.of(context).caption.copyWith(
                          color: AppPalette.of(context).tooltipForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                ),
              ),
            ),
          );
        },
        child: widget.child,
      ),
    ),
  );
}
