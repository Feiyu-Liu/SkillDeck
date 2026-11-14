import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/settings/data/workspace_validation_history_store.dart';
import 'package:skills_manager/features/settings/presentation/view_models/workspace_validation_view_model.dart';
import 'package:skills_manager/features/settings/presentation/widgets/environment_check_settings.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_progress_bar.dart';

/// Skills validation and the environment check, both started by the user.
class MaintenanceSettings extends StatelessWidget {
  const MaintenanceSettings({required this.showSectionHeader, super.key});

  final bool showSectionHeader;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('maintenance-settings'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showSectionHeader) ...[
        SettingsSectionHeader(
          title: context.l10n.settingsMaintenanceTitle,
          description: context.l10n.settingsMaintenanceDescription,
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
      const _WorkspaceValidationGroup(),
      const SizedBox(height: AppSpacing.xl),
      const EnvironmentCheckSettings(),
    ],
  );
}

class _WorkspaceValidationGroup extends ConsumerWidget {
  const _WorkspaceValidationGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(workspaceValidationViewModelProvider);
    final viewModel = ref.read(workspaceValidationViewModelProvider.notifier);
    final last = state.last;
    final total = state.total;
    return SettingsGroup(
      key: const Key('workspace-validation-settings'),
      label: l10n.settingsSkillsGroup,
      children: [
        SettingsRow(
          leading: state.running
              ? const CupertinoActivityIndicator(radius: 8)
              : Icon(
                  _statusIcon(last),
                  size: AppSizes.iconMd - 1,
                  color: _statusColor(last, AppPalette.of(context)),
                ),
          title: state.running
              ? l10n.settingsValidateWorkspaceRunning
              : l10n.settingsValidateWorkspace,
          descriptionWidget: state.running
              ? null
              : Text(
                  _statusText(context, last),
                  key: const Key('workspace-validation-status'),
                  style: AppTypography.of(context).caption,
                ),
          below: state.running
              ? Row(
                  children: [
                    Expanded(
                      child: AppProgressBar(
                        key: const Key('workspace-validation-progress'),
                        progress: total == null || total == 0
                            ? 0
                            : state.completed / total,
                      ),
                    ),
                    if (total != null) ...[
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        '${state.completed} / $total',
                        style: AppTypography.of(context).mono.copyWith(
                          color: AppPalette.of(context).textSecondary,
                        ),
                      ),
                    ],
                  ],
                )
              : null,
          trailing: state.running
              ? AppButton(
                  key: const Key('settings-validate-workspace-cancel'),
                  label: l10n.commonCancel,
                  icon: LucideIcons.x,
                  style: NeoButtonVariant.ghost,
                  onPressed: () => unawaited(viewModel.cancel()),
                )
              : AppButton(
                  key: const Key('settings-validate-workspace'),
                  label: l10n.settingsValidateNow,
                  icon: LucideIcons.shieldCheck,
                  onPressed: () => unawaited(viewModel.validate()),
                ),
        ),
      ],
    );
  }
}

IconData _statusIcon(WorkspaceValidationRecord? last) => switch (last) {
  null => LucideIcons.shieldCheck,
  WorkspaceValidationRecord(failed: true) => LucideIcons.circleX,
  WorkspaceValidationRecord(failedSkillCount: > 0) ||
  WorkspaceValidationRecord(driftedSkillCount: > 0) => LucideIcons.circleAlert,
  _ => LucideIcons.circleCheck,
};

Color _statusColor(WorkspaceValidationRecord? last, AppPalette colors) =>
    switch (last) {
      null => colors.textMuted,
      WorkspaceValidationRecord(failed: true) => colors.danger,
      WorkspaceValidationRecord(failedSkillCount: > 0) ||
      WorkspaceValidationRecord(driftedSkillCount: > 0) => colors.warning,
      _ => colors.success,
    };

String _statusText(BuildContext context, WorkspaceValidationRecord? last) {
  final l10n = context.l10n;
  if (last == null) return l10n.settingsValidateWorkspaceDescription;
  final time = formatSettingsTimestamp(last.completedAt);
  if (last.failed) return l10n.settingsValidationLastFailed(time);
  return l10n.settingsValidationLastRun(
    time,
    l10n.settingsValidateWorkspaceSummary(
      last.checkedSkillCount,
      last.repairedArtifactCount,
      last.driftedSkillCount,
      last.failedSkillCount,
    ),
  );
}

/// Formats [value] in local time as `yyyy-MM-dd HH:mm`, which reads the same
/// in both interface languages.
String formatSettingsTimestamp(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
