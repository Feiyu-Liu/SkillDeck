import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/self_update/presentation/widgets/self_update_action.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// The update status row and its check button in About SkillDeck.
class SelfUpdateSettings extends ConsumerWidget {
  const SelfUpdateSettings({required this.installBlocked, super.key});

  final bool installBlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configuration = ref.watch(appUpdateConfigurationProvider);
    final coordinator = ref.watch(appUpdateCoordinatorProvider);
    final l10n = context.l10n;
    return SettingsGroup(
      key: const Key('self-update-settings'),
      label: l10n.settingsUpdatesGroup,
      children: [
        configuration.when(
          data: (value) => value == null || coordinator == null
              ? SettingsRow(
                  leading: _StatusIcon(
                    icon: LucideIcons.circleDashed,
                    color: AppPalette.of(context).textMuted,
                  ),
                  title: l10n.settingsAutomaticUpdates,
                  descriptionWidget: Text(
                    l10n.settingsAppUpdateUnconfigured,
                    key: const Key('self-update-unconfigured'),
                    style: AppTypography.of(context).caption,
                  ),
                )
              : ListenableBuilder(
                  listenable: coordinator,
                  builder: (context, _) => _ConfiguredUpdateRow(
                    coordinator: coordinator,
                    installBlocked: installBlocked,
                  ),
                ),
          error: (_, _) => SettingsRow(
            leading: _StatusIcon(
              icon: LucideIcons.circleX,
              color: AppPalette.of(context).danger,
            ),
            title: l10n.settingsAutomaticUpdates,
            descriptionWidget: Text(
              l10n.settingsAppUpdateInvalid,
              key: const Key('self-update-invalid'),
              style: AppTypography.of(context).caption
                  .copyWith(color: AppPalette.of(context).danger),
            ),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: CupertinoActivityIndicator(),
          ),
        ),
        if (installBlocked) SettingsFootnote(l10n.settingsAppUpdateBusy),
      ],
    );
  }
}

class _ConfiguredUpdateRow extends ConsumerWidget {
  const _ConfiguredUpdateRow({
    required this.coordinator,
    required this.installBlocked,
  });

  final AppUpdateCoordinator coordinator;
  final bool installBlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = coordinator.state;
    final busy = state is AppUpdateChecking;
    return SettingsRow(
      leading: busy
          ? const CupertinoActivityIndicator(radius: 8)
          : _StatusIcon(
              icon: switch (state) {
                AppUpdateAvailable() ||
                AppUpdateDownloaded() => LucideIcons.circleArrowUp,
                AppUpdateFailed() => LucideIcons.circleX,
                _ => LucideIcons.circleCheck,
              },
              color: switch (state) {
                AppUpdateAvailable() ||
                AppUpdateDownloaded() => AppPalette.of(context).info,
                AppUpdateFailed() => AppPalette.of(context).danger,
                _ => AppPalette.of(context).success,
              },
            ),
      title: context.l10n.settingsAutomaticUpdates,
      descriptionWidget: Text(
        _statusText(context, state),
        key: const Key('self-update-status'),
        style: AppTypography.of(context).caption,
      ),
      trailing: AppButton(
        key: const Key('self-update-check'),
        label: state is AppUpdateAvailable || state is AppUpdateDownloaded
            ? context.l10n.sidebarAppUpdateDownloaded
            : context.l10n.settingsAppUpdateCheck,
        icon: LucideIcons.refreshCw,
        onPressed: busy || installBlocked
            ? null
            : () => unawaited(
                openNativeUpdateDialog(
                  context,
                  ref,
                  coordinator,
                  blocked: installBlocked,
                ),
              ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: AppSizes.iconMd - 1, color: color);
}

String _statusText(BuildContext context, AppUpdateState state) =>
    switch (state) {
      AppUpdateIdle() => context.l10n.settingsAppUpdateReady,
      AppUpdateChecking() => context.l10n.settingsAppUpdateChecking,
      AppUpdateAvailable(:final version) =>
        version == null
            ? context.l10n.settingsAppUpdateAvailableGeneric
            : context.l10n.settingsAppUpdateAvailable(version),
      AppUpdateDownloaded() => context.l10n.settingsAppUpdateDownloaded,
      AppUpdateFailed() => context.l10n.settingsAppUpdateFailed,
    };
