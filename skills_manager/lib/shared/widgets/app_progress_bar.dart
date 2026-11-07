import 'package:flutter/cupertino.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

class AppProgressBar extends StatelessWidget {
  const AppProgressBar({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.clamp(0, 1).toDouble();
    return Semantics(
      value: '${(fraction * 100).round()}%',
      child: SizedBox(
        height: 5,
        child: DecoratedBox(
          decoration: AppCorners.smooth(
            color: AppPalette.of(context).ink.withValues(alpha: 0.08),
            radius: AppRadii.pill,
          ),
          child: ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value,
                child: child,
              ),
              child: DecoratedBox(
                key: const Key('app-progress-bar-fill'),
                decoration: AppCorners.smooth(
                  color: AppPalette.of(context).info,
                  radius: AppRadii.pill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
