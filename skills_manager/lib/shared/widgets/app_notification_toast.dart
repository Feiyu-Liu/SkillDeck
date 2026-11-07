import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_progress_bar.dart';

class AppNotificationToast extends StatefulWidget {
  const AppNotificationToast({
    required this.content,
    this.onClose,
    this.onPause,
    this.onResume,
    super.key,
  });

  final AppNotificationContent content;
  final VoidCallback? onClose;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  State<AppNotificationToast> createState() => _AppNotificationToastState();
}

class _AppNotificationToastState extends State<AppNotificationToast> {
  // Once expanded, the toast stays until it is closed, so the details do
  // not vanish while being read.
  var _expanded = false;

  void _expand() {
    setState(() => _expanded = true);
    widget.onPause?.call();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final onClose = widget.onClose;
    final appearance = _appearance(content.severity, AppPalette.of(context));
    final detail = _expanded ? content.detail : null;
    return Semantics(
      container: true,
      liveRegion: true,
      label: detail == null ? content.message : '${content.message}\n$detail',
      child: MouseRegion(
        onEnter: (_) => widget.onPause?.call(),
        onExit: (_) {
          if (!_expanded) widget.onResume?.call();
        },
        child: Container(
          key: const Key('app-notification-toast'),
          width: 360,
          margin: const EdgeInsets.only(top: AppSizes.dragRegionHeight + 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.panel),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: AppCorners.smooth(
                  color: AppPalette.of(context).white.withValues(alpha: 0.86),
                  radius: AppRadii.panel,
                  side: BorderSide(
                    color: AppPalette.of(context).ink.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                  shadows: AppShadows.of(context).contentPanel,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 8, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _NotificationIcon(
                        appearance: appearance,
                        running: content.taskRunning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              content.message,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.of(context).caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppPalette.of(context).textPrimary,
                                height: 1.2,
                              ),
                            ),
                            if (detail != null)
                              Column(
                                key: const Key('app-notification-detail'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // One paragraph per item, spaced apart so
                                  // wrapped paths do not run together.
                                  for (final line in detail.split('\n')) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      line,
                                      style: AppTypography.of(context).caption
                                          .copyWith(
                                            color: AppPalette.of(context)
                                                .bodyContent,
                                            height: 1.35,
                                          ),
                                    ),
                                  ],
                                ],
                              )
                            else if (content.detailLabel case final label?) ...[
                              const SizedBox(height: 5),
                              _DetailsLink(label: label, onTap: _expand),
                            ],
                            if (content.taskRunning &&
                                content.progress != null) ...[
                              const SizedBox(height: 9),
                              AppProgressBar(
                                key: const Key(
                                  'app-notification-task-progress',
                                ),
                                progress: content.progress!.fraction,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (content.copyText case final copyText?) ...[
                        const SizedBox(width: 4),
                        AppIconButton(
                          key: const Key('app-notification-copy'),
                          icon: LucideIcons.copy,
                          tooltip: CupertinoLocalizations.of(context)
                              .copyButtonLabel,
                          style: NeoButtonVariant.ghost,
                          foregroundColor: AppPalette.of(context).textSecondary,
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: copyText)),
                        ),
                      ],
                      if (onClose != null) ...[
                        const SizedBox(width: 4),
                        AppIconButton(
                          key: const Key('app-notification-close'),
                          icon: LucideIcons.x,
                          tooltip: CupertinoLocalizations.of(context)
                              .modalBarrierDismissLabel,
                          style: NeoButtonVariant.ghost,
                          foregroundColor: AppPalette.of(context).textSecondary,
                          onPressed: onClose,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _NotificationAppearance _appearance(
    AppNotificationSeverity severity,
    AppPalette colors,
  ) => switch (severity) {
    AppNotificationSeverity.success => _NotificationAppearance(
      icon: LucideIcons.circleCheck,
      accent: colors.success,
    ),
    AppNotificationSeverity.info => _NotificationAppearance(
      icon: LucideIcons.info,
      accent: colors.info,
    ),
    AppNotificationSeverity.warning => _NotificationAppearance(
      icon: LucideIcons.triangleAlert,
      accent: colors.warning,
    ),
    AppNotificationSeverity.error => _NotificationAppearance(
      icon: LucideIcons.circleAlert,
      accent: colors.danger,
    ),
  };
}

/// Flush with the message above it, unlike a padded button.
class _DetailsLink extends StatelessWidget {
  const _DetailsLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const Key('app-notification-show-details'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.of(context).caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppPalette.of(context).textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              LucideIcons.chevronDown,
              size: 13,
              color: AppPalette.of(context).textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.appearance, required this.running});

  final _NotificationAppearance appearance;
  final bool running;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: appearance.accent.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: running
          ? CupertinoActivityIndicator(
              key: const Key('app-notification-task-spinner'),
              radius: 7,
              color: appearance.accent,
            )
          : Icon(appearance.icon, size: 15, color: appearance.accent),
    );
  }
}

final class _NotificationAppearance {
  const _NotificationAppearance({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;
}
