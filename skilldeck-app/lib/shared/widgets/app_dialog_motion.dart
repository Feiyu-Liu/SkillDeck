import 'package:cupertino_ui/cupertino_ui.dart';

import 'package:skills_manager/shared/theme/app_theme.dart';

abstract final class AppDialogMotion {
  static CupertinoModalPopupRoute<T> route<T>({
    required WidgetBuilder builder,
    required bool barrierDismissible,
    required Color barrierColor,
    RouteSettings? settings,
  }) {
    return CupertinoModalPopupRoute<T>(
      builder: builder,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      settings: settings,
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      route<T>(
        builder: builder,
        barrierDismissible: barrierDismissible,
        barrierColor: AppPalette.of(context).modalScrim,
      ),
    );
  }
}
