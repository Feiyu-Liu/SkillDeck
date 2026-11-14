import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_progress_bar.dart';

class AppOperationFeedback extends StatelessWidget {
  const AppOperationFeedback({
    required this.label,
    required this.cancelLabel,
    required this.warnings,
    this.detail,
    this.progress,
    this.running = false,
    this.onCancel,
    super.key,
  });

  final String label;
  final String cancelLabel;
  final String? detail;
  final double? progress;
  final List<String> warnings;
  final bool running;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('operation-feedback'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppCorners.smooth(
        color: AppPalette.of(context).propertyCardBackground,
        radius: AppRadii.md,
        side: BorderSide(color: AppPalette.of(context).border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (running)
                CupertinoActivityIndicator(
                  radius: 7,
                  color: AppPalette.of(context).ink,
                )
              else
                Icon(
                  LucideIcons.circleCheck,
                  size: 15,
                  color: AppPalette.of(context).success,
                ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(label, style: AppTypography.of(context).control),
              ),
              if (running && onCancel != null)
                AppButton(
                  key: const Key('operation-cancel'),
                  label: cancelLabel,
                  icon: LucideIcons.x,
                  size: NeoButtonSize.small,
                  onPressed: onCancel,
                ),
            ],
          ),
          if (detail case final value?) ...[
            const SizedBox(height: 5),
            Text(
              value,
              style: AppTypography.of(context).caption
                  .copyWith(fontWeight: FontWeight.w400),
            ),
          ],
          if (running && progress != null) ...[
            const SizedBox(height: 9),
            AppProgressBar(progress: progress!),
          ],
          for (final warning in warnings) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    LucideIcons.triangleAlert,
                    size: 14,
                    color: AppPalette.of(context).warning,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning,
                    style: AppTypography.of(context).caption
                        .copyWith(fontWeight: FontWeight.w400),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
