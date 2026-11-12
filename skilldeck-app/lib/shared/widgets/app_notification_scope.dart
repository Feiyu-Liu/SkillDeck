import 'package:flutter/widgets.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:toastification/toastification.dart';

class AppNotificationScope extends StatelessWidget {
  const AppNotificationScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      config: const ToastificationConfig(
        alignment: Alignment.topCenter,
        marginBuilder: _overlayMargin,
        itemWidth: 360,
        maxToastLimit: 3,
        animationDuration: Duration(milliseconds: 220),
        blockBackgroundInteraction: false,
      ),
      child: child,
    );
  }

  static EdgeInsetsGeometry _overlayMargin(
    BuildContext context,
    AlignmentGeometry alignment,
  ) => const ToastificationConfig()
      .marginBuilder(context, alignment)
      .add(
        // Avoid the desktop title bar once for the entire stack.
        const EdgeInsets.only(top: AppSizes.dragRegionHeight + 12),
      );
}
