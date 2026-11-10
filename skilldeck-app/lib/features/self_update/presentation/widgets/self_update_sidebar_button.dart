import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

class SelfUpdateSidebarButton extends ConsumerWidget {
  const SelfUpdateSidebarButton({this.rail = false, super.key});

  /// Whether the sidebar is collapsed to its icon rail, where the prompt keeps
  /// its place as an icon-only control instead of disappearing.
  final bool rail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.watch(appUpdateCoordinatorProvider);
    if (coordinator == null) return const SizedBox.shrink();
    final installBlocked =
        ref.watch(appSettingsViewModelProvider).isBusy ||
        ref.watch(workspaceFinalizationCoordinatorProvider).isRecovering;
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        if (!coordinator.hasUpdatePrompt) return const SizedBox.shrink();
        final state = coordinator.state;
        final busy = state is AppUpdateChecking;
        final enabled = !busy && !installBlocked;
        final label = _label(context, state);
        final icon = switch (state) {
          AppUpdateChecking() => const CupertinoActivityIndicator(
            key: Key('nav-item-self-update-progress'),
            radius: AppSizes.iconMd / 2,
          ),
          // A failed check is not good news, so it stays neutral.
          AppUpdateFailed() => Icon(
            LucideIcons.refreshCw,
            size: AppSizes.iconMd,
            color: AppPalette.of(context).textPrimary,
          ),
          // Downward arrows already mean Skill updates (the Updates nav item
          // and panel); the app upgrade points up, in the success tint, so the
          // two stay distinct when the rail strips both down to bare icons.
          _ => Icon(
            LucideIcons.circleFadingArrowUp,
            size: AppSizes.iconMd,
            color: AppPalette.of(context).success,
          ),
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          // The rail hides the visible label, so the button announces it.
          child: Semantics(
            container: true,
            button: true,
            enabled: enabled,
            label: label,
            child: ExcludeSemantics(
              child: CupertinoButton(
                key: const Key('nav-item-self-update'),
                onPressed: enabled
                    ? () => unawaited(
                        coordinator.openUpdateDialog(blocked: installBlocked),
                      )
                    : null,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                pressedOpacity: 0.7,
                child: Container(
                  height: AppSizes.navItemHeight,
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: rail ? 0 : AppSpacing.md,
                  ),
                  decoration: AppCorners.smooth(
                    color: AppPalette.of(context).surfaceMuted,
                    radius: AppRadii.control,
                  ),
                  child: Row(
                    mainAxisAlignment: rail
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      icon,
                      if (!rail) ...[
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.of(context).navigationSelected,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Short action labels sized for the sidebar; the settings section keeps the
// full status sentences.
String _label(BuildContext context, AppUpdateState state) => switch (state) {
  AppUpdateChecking() => context.l10n.sidebarAppUpdateChecking,
  AppUpdateAvailable() => context.l10n.sidebarAppUpdateAvailable,
  AppUpdateDownloaded() => context.l10n.sidebarAppUpdateDownloaded,
  AppUpdateFailed() => context.l10n.sidebarAppUpdateFailed,
  // Unreachable while hasUpdatePrompt gates the button.
  AppUpdateIdle() => context.l10n.sidebarAppUpdateAvailable,
};
