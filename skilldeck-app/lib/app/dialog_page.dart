import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:skills_manager/shared/theme/app_palette.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';

final class DialogPage<T> extends Page<T> {
  const DialogPage({
    required this.child,
    required this.barrierDismissible,
    super.key,
  });

  final Widget child;
  final bool barrierDismissible;

  @override
  Route<T> createRoute(BuildContext context) => AppDialogMotion.route<T>(
    barrierColor: AppPalette.of(context).modalScrim,
    settings: this,
    barrierDismissible: barrierDismissible,
    builder: (_) => child,
  );
}
