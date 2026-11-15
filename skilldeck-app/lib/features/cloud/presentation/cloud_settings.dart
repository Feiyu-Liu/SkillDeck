import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:next_ui/next_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

import '../cloud_providers.dart';
import '../sync/cloud_sync_session.dart';

class CloudSettings extends ConsumerWidget {
  const CloudSettings({required this.showSectionHeader, super.key});
  final bool showSectionHeader;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n,
        configuration = ref.watch(cloudConfigurationProvider);
    if (!configuration.configured) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSectionHeader) ...[
            SettingsSectionHeader(title: l10n.cloudSettingsTitle),
            const SizedBox(height: AppSpacing.xl),
          ],
          SettingsGroup(children: [SettingsRow(title: l10n.cloudUnavailable)]),
        ],
      );
    }
    final state = ref.watch(cloudSettingsControllerProvider),
        controller = ref.read(cloudSettingsControllerProvider.notifier);
    final connected = state.session != null;
    final waiting =
        state.activity == CloudSettingsActivity.signingIn ||
        state.activity == CloudSettingsActivity.restoring ||
        state.activity == CloudSettingsActivity.cancelling;
    return Column(
      key: const Key('cloud-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSectionHeader) ...[
          SettingsSectionHeader(
            title: l10n.cloudSettingsTitle,
            description: l10n.cloudSettingsDescription,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        SettingsGroup(
          label: l10n.cloudAccountGroup,
          children: [
            SettingsRow(
              title: connected ? l10n.cloudConnected : l10n.cloudDisconnected,
              description: switch (state.activity) {
                CloudSettingsActivity.signingIn => l10n.cloudWaitingForBrowser,
                CloudSettingsActivity.restoring => l10n.cloudRestoring,
                CloudSettingsActivity.cancelling => l10n.cloudCancelling,
                _ => connected ? state.deviceName : l10n.cloudSignInDescription,
              },
              trailing: waiting
                  ? AppButton(
                      key: const Key('cloud-cancel'),
                      label: l10n.commonCancel,
                      onPressed:
                          state.activity == CloudSettingsActivity.cancelling
                          ? null
                          : controller.cancel,
                    )
                  : connected
                  ? AppButton(
                      key: const Key('cloud-sign-out'),
                      label: l10n.cloudSignOut,
                      loading:
                          state.activity == CloudSettingsActivity.signingOut,
                      onPressed: state.busy
                          ? null
                          : () => unawaited(controller.signOut()),
                    )
                  : Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        AppButton(
                          key: const Key('cloud-sign-in'),
                          label: l10n.cloudSignIn,
                          style: NeoButtonVariant.primary,
                          onPressed: state.busy
                              ? null
                              : () => unawaited(controller.signIn()),
                        ),
                        AppButton(
                          key: const Key('cloud-restore'),
                          label: l10n.cloudRestore,
                          onPressed: state.busy
                              ? null
                              : () => unawaited(controller.restore()),
                        ),
                      ],
                    ),
            ),
            SettingsFootnote(l10n.cloudLoginDoesNotEnableSync),
            if (state.needsReconciliation)
              SettingsRow(title: l10n.cloudNeedsReconciliation),
          ],
        ),
        if (connected) ...[
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            label: l10n.cloudSyncGroup,
            children: [
              SettingsRow(
                title: state.sync == null
                    ? l10n.cloudSyncChoose
                    : state.sync!.enabled
                    ? l10n.cloudSyncEnabled
                    : l10n.cloudSyncPaused,
                description: state.sync == null
                    ? l10n.cloudSyncChooseDescription
                    : state.sync!.needsReconciliation
                    ? l10n.cloudNeedsReconciliation
                    : state.sync!.pendingReasons.contains(
                        CloudPendingReason.dirtyDraft,
                      )
                    ? l10n.cloudSyncDirty
                    : state.sync!.pendingReasons.contains(
                        CloudPendingReason.metadataConflict,
                      )
                    ? l10n.cloudSyncMetadataConflict
                    : state.sync!.backgroundError != null
                    ? l10n.cloudSyncRetryLater
                    : state.sync!.backgroundRunning
                    ? l10n.cloudSyncWorking
                    : state.sync!.pendingCount > 0
                    ? l10n.cloudSyncConflict
                    : l10n.cloudSyncReady,
                trailing: AppButton(
                  key: const Key('cloud-load-sync'),
                  label: l10n.cloudSyncChooseAction,
                  loading: state.activity == CloudSettingsActivity.loadingSync,
                  onPressed: state.busy || state.needsReconciliation
                      ? null
                      : () => unawaited(controller.loadSync()),
                ),
              ),
              if (state.sync?.enabled == true ||
                  state.activity == CloudSettingsActivity.syncing)
                SettingsRow(
                  title: l10n.cloudSyncNow,
                  trailing: Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      AppButton(
                        key: const Key('cloud-sync-now'),
                        label: l10n.cloudSyncNow,
                        style: NeoButtonVariant.primary,
                        loading:
                            state.activity == CloudSettingsActivity.syncing,
                        onPressed: state.busy
                            ? null
                            : () => unawaited(controller.syncNow()),
                      ),
                      AppButton(
                        key: const Key('cloud-stop-sync'),
                        label: l10n.cloudSyncStop,
                        onPressed:
                            state.busy &&
                                state.activity != CloudSettingsActivity.syncing
                            ? null
                            : () => unawaited(controller.stopSync()),
                      ),
                    ],
                  ),
                ),
              for (final choice
                  in state.sync?.choices ?? <AppCloudSkillChoice>[])
                SettingsRow(
                  key: Key(
                    'cloud-sync-choice-${choice.kind.name}-${choice.id}',
                  ),
                  title: choice.name,
                  description: !choice.supported
                      ? l10n.cloudSyncUnsupported
                      : choice.conflict
                      ? l10n.cloudSyncExisting
                      : choice.kind == AppCloudChoiceKind.local
                      ? l10n.cloudSyncFromDevice
                      : l10n.cloudSyncFromCloud,
                  trailing: AppButton(
                    label:
                        state.sync!.selectedIds.contains(choice.id) ||
                            state.draftChoices.contains(
                              '${choice.kind.name}:${choice.id}',
                            )
                        ? l10n.cloudSyncSelected
                        : l10n.cloudSyncSelect,
                    size: NeoButtonSize.small,
                    onPressed:
                        state.busy ||
                            state.sync!.enabled ||
                            state.sync!.selectedIds.isNotEmpty ||
                            !choice.supported ||
                            choice.conflict
                        ? null
                        : () => controller.toggleSyncChoice(choice),
                  ),
                ),
              if (state.draftChoices.isNotEmpty && state.sync?.enabled != true)
                SettingsRow(
                  title: l10n.cloudSyncEnableSelected,
                  trailing: AppButton(
                    key: const Key('cloud-confirm-selection'),
                    label: l10n.cloudSyncEnableSelected,
                    style: NeoButtonVariant.primary,
                    onPressed: state.busy
                        ? null
                        : () async {
                            final confirmed = await showAppConfirmDialog(
                              context: context,
                              icon: LucideIcons.cloud,
                              tone: AppDialogTone.info,
                              title: l10n.cloudSyncConfirmTitle,
                              message: l10n.cloudSyncConfirmDescription,
                              confirmLabel: l10n.cloudSyncConfirmAction,
                              confirmIcon: LucideIcons.cloud,
                            );
                            if (confirmed == true) {
                              await controller.enableSelectedSync();
                            }
                          },
                  ),
                ),
              if (state.sync?.enabled == false &&
                  state.sync!.selectedIds.isNotEmpty)
                SettingsRow(
                  title: l10n.cloudSyncPaused,
                  trailing: AppButton(
                    key: const Key('cloud-resume-sync'),
                    label: l10n.cloudSyncResume,
                    onPressed: state.busy
                        ? null
                        : () => unawaited(controller.resumeSync()),
                  ),
                ),
              SettingsFootnote(l10n.cloudSyncPauseDescription),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            label: l10n.cloudDevicesGroup,
            trailing: AppButton(
              key: const Key('cloud-refresh-devices'),
              label: l10n.cloudRefreshDevices,
              size: NeoButtonSize.small,
              loading: state.activity == CloudSettingsActivity.loadingDevices,
              onPressed: state.busy
                  ? null
                  : () => unawaited(controller.refreshDevices()),
            ),
            children: [
              if (state.devices.isEmpty)
                SettingsRow(title: l10n.cloudNoDevices),
              for (final device in state.devices)
                SettingsRow(
                  key: Key('cloud-device-${device.id}'),
                  title: device.name,
                  description: device.revokedAt != null
                      ? l10n.cloudAccessRevoked
                      : device.id == state.session!.deviceId
                      ? l10n.cloudThisDevice
                      : switch (device.platform) {
                          'macos' => 'macOS',
                          'windows' => 'Windows',
                          _ => 'Linux',
                        },
                  trailing: device.revokedAt != null
                      ? null
                      : AppButton(
                          key: Key('cloud-revoke-${device.id}'),
                          label: l10n.cloudRevokeDevice,
                          size: NeoButtonSize.small,
                          style: NeoButtonVariant.danger,
                          onPressed: state.busy
                              ? null
                              : () => unawaited(
                                  controller.revokeDevice(device.id),
                                ),
                        ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
