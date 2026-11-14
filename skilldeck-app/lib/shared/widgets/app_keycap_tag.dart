import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:next_ui/next_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';

import 'package:skills_manager/shared/theme/app_palette.dart';

/// A personal-tag keycap with the App's appearance-specific colors.
class AppKeycapTag extends StatelessWidget {
  const AppKeycapTag(this.text, {required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (AppPalette.of(context).brightness == Brightness.light) {
      return CapsuleTag(text, variant: CapsuleTagVariant.keycap, color: color);
    }
    const lightBorder = Color(0xFFDCDCE3);
    const darkBase = Color(0xFF18181A);
    final stroke = Color.lerp(color, lightBorder, 0.52)!;
    final shadow = Color.lerp(color, lightBorder, 0.28)!;
    final label = Color.lerp(color, const Color(0xFF171717), 0.24)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 2,
            left: 0,
            right: 0,
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: Color.lerp(shadow, CupertinoColors.black, 0.70),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(stroke, darkBase, 0.70)!,
                  Color.lerp(stroke, darkBase, 0.78)!,
                ],
              ),
              shape: SmoothRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                smoothness: 0.8,
                side: BorderSide(color: Color.lerp(stroke, darkBase, 0.50)!),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 1,
                  left: 3,
                  right: 3,
                  child: Container(height: 1, color: const Color(0x14FFFFFF)),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color.lerp(label, CupertinoColors.white, 0.62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
