import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

class AppCupertinoDialogSurface extends StatelessWidget {
  const AppCupertinoDialogSurface({
    required this.width,
    required this.child,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 40,
      vertical: 60,
    ),
    super.key,
  });

  final double width;
  final Widget child;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height - insetPadding.vertical;
    return Center(
      child: Padding(
        padding: insetPadding,
        child: CupertinoPopupSurface(
          isSurfacePainted: false,
          child: DecoratedBox(
            decoration: AppCorners.smooth(
              color: AppPalette.of(context).surfaceSubtle,
              radius: AppRadii.dialog,
              shadows: AppShadows.of(context).floatingControl,
            ),
            child: AppSmoothClip(
              radius: AppRadii.dialog,
              child: AnimatedSize(
                alignment: Alignment.topCenter,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: width,
                    maxHeight: maxHeight,
                  ),
                  child: ColoredBox(
                    color: AppPalette.of(context).surfaceSubtle,
                    child: SizedBox(width: width, child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact segmented control, sized to sit beside a label or above a form.
class AppSegmentedControl<T extends Object> extends StatelessWidget {
  const AppSegmentedControl({
    required this.value,
    required this.segments,
    required this.onChanged,
    this.segmentKeys = const {},
    this.enabled = true,
    super.key,
  });

  final T value;
  final Map<T, String> segments;
  final Map<T, Key> segmentKeys;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => CupertinoSlidingSegmentedControl<T>(
    groupValue: value,
    proportionalWidth: true,
    children: {
      for (final entry in segments.entries)
        entry.key: Padding(
          key: segmentKeys[entry.key],
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(entry.value, style: const TextStyle(fontSize: 13)),
        ),
    },
    onValueChanged: (selected) {
      if (enabled && selected != null) onChanged(selected);
    },
  );
}
