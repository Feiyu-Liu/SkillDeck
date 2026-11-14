import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/l10n/app_failure_l10n.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

enum AppFailureViewVariant { centered, banner }

/// Shared presentation for expected failures that remain in the current UI.
///
/// Recovery is deliberately supplied by the owning page. This keeps the
/// component reusable without guessing whether replaying an operation is safe.
final class AppFailureView extends StatelessWidget {
  const AppFailureView({
    required this.failure,
    required this.variant,
    this.title,
    this.actionLabel,
    this.actionKey,
    this.actionIcon,
    this.onAction,
    this.onDismiss,
    this.busy = false,
    super.key,
  });

  final AppFailure failure;
  final AppFailureViewVariant variant;
  final String? title;
  final String? actionLabel;
  final Key? actionKey;

  /// Overrides the recovery-derived icon. Needed when the page's action is not
  /// a retry — a refresh glyph on a "Go to Settings" button reads as one.
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final bool busy;

  @override
  Widget build(BuildContext context) => switch (variant) {
    AppFailureViewVariant.centered => _buildCentered(context),
    AppFailureViewVariant.banner => _buildBanner(context),
  };

  Widget _buildCentered(BuildContext context) {
    final message = localizeAppFailure(context.l10n, failure);
    final resolvedActionLabel =
        actionLabel ??
        localizeAppFailureRecoveryAction(context.l10n, failure.recoveryPolicy);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Semantics(
            container: true,
            liveRegion: true,
            label: message,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.circleAlert,
                  size: 34,
                  color: AppPalette.of(context).danger,
                ),
                const SizedBox(height: 16),
                if (title case final title?) ...[
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypography.of(context).title,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.of(context).bodyMuted
                      .copyWith(height: 1.5),
                ),
                if (resolvedActionLabel != null && onAction != null) ...[
                  const SizedBox(height: 20),
                  AppButton(
                    key: actionKey,
                    label: resolvedActionLabel,
                    icon: actionIcon ?? _actionIcon(failure.recoveryPolicy),
                    style: NeoButtonVariant.primary,
                    onPressed: busy ? null : onAction,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(BuildContext context) {
    final message = localizeAppFailure(context.l10n, failure);
    final resolvedActionLabel =
        actionLabel ??
        localizeAppFailureRecoveryAction(context.l10n, failure.recoveryPolicy);
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: AppCorners.smooth(
          color: AppPalette.of(context).dangerSoft,
          radius: AppRadii.control,
          side: BorderSide(color: AppPalette.of(context).danger),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 17,
              color: AppPalette.of(context).danger,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title case final title?) ...[
                    Text(
                      title,
                      style: AppTypography.of(context).body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppPalette.of(context).textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    message,
                    style: AppTypography.of(context).control.copyWith(
                      fontWeight: title == null
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: AppPalette.of(context).bodyContent,
                      height: title == null ? null : 1.5,
                    ),
                  ),
                ],
              ),
            ),
            if (resolvedActionLabel != null && onAction != null) ...[
              const SizedBox(width: 10),
              AppButton(
                key: actionKey,
                label: resolvedActionLabel,
                icon: actionIcon ?? _actionIcon(failure.recoveryPolicy),
                size: NeoButtonSize.small,
                style: NeoButtonVariant.secondary,
                onPressed: busy ? null : onAction,
              ),
            ],
            if (onDismiss != null) ...[
              const SizedBox(width: 4),
              AppIconButton(
                icon: LucideIcons.x,
                tooltip: context.l10n.commonClose,
                style: NeoButtonVariant.ghost,
                foregroundColor: AppPalette.of(context).textSecondary,
                onPressed: busy ? null : onDismiss,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

IconData _actionIcon(AppRecoveryPolicy policy) => switch (policy) {
  AppRecoveryPolicy.retryExplicitly => LucideIcons.refreshCw,
  AppRecoveryPolicy.refresh => LucideIcons.refreshCw,
  AppRecoveryPolicy.refreshThenReview => LucideIcons.refreshCw,
  // A page may provide a safe explicit action even when the typed policy is
  // none (for example, retrying repository initialization).
  AppRecoveryPolicy.none => LucideIcons.refreshCw,
};
