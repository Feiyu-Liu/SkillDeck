import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';

abstract final class AppCorners {
  static const smoothness = 0.8;

  static ShapeDecoration smooth({
    Color? color,
    Gradient? gradient,
    required double radius,
    BorderSide side = BorderSide.none,
    List<BoxShadow>? shadows,
  }) {
    assert(color == null || gradient == null);
    return ShapeDecoration(
      color: color,
      gradient: gradient,
      shadows: shadows,
      shape: SmoothRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        smoothness: smoothness,
        side: side,
      ),
    );
  }

  static ShapeDecoration smoothCorners({
    Color? color,
    Gradient? gradient,
    required BorderRadius borderRadius,
    BorderSide side = BorderSide.none,
    List<BoxShadow>? shadows,
  }) {
    assert(color == null || gradient == null);
    return ShapeDecoration(
      color: color,
      gradient: gradient,
      shadows: shadows,
      shape: SmoothRectangleBorder(
        borderRadius: borderRadius,
        smoothness: smoothness,
        side: side,
      ),
    );
  }
}

class AppSmoothClip extends StatelessWidget {
  const AppSmoothClip({required this.radius, required this.child, super.key});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SmoothClipRRect(
      smoothness: AppCorners.smoothness,
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
  }
}
