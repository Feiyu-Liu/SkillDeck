import 'package:flutter/widgets.dart';
import 'package:toastification/toastification.dart';

class AppNotificationScope extends StatelessWidget {
  const AppNotificationScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      config: const ToastificationConfig(
        alignment: Alignment.topCenter,
        itemWidth: 360,
        maxToastLimit: 3,
        animationDuration: Duration(milliseconds: 220),
        blockBackgroundInteraction: false,
      ),
      child: child,
    );
  }
}
