import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/presentation/views/custom_agent_editor_dialog.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';

/// Built-in Agents the App manages, and the custom Agents defined on this
/// device.
class AgentsSettings extends ConsumerStatefulWidget {
  const AgentsSettings({required this.showSectionHeader, super.key});

  final bool showSectionHeader;

  @override
  ConsumerState<AgentsSettings> createState() => _AgentsSettingsState();
}

class _AgentsSettingsState extends ConsumerState<AgentsSettings> {
  bool _showAllBuiltIn = false;

  Future<void> _setMembership(WorkspaceAgentInfo agent, bool member) async {
    if (!member) {
      final confirmed = await showAppConfirmDialog(
        context: context,
        icon: LucideIcons.userMinus,
        tone: AppDialogTone.info,
        title: context.l10n.agentsRemoveTitle,
        message: context.l10n.agentsRemoveDescription,
        confirmLabel: context.l10n.agentsRemoveAction,
        confirmIcon: LucideIcons.userMinus,
      );
      if (confirmed != true || !mounted) return;
    }
    await ref
        .read(appSettingsViewModelProvider.notifier)
        .setBuiltInAgentMembership(agent.id, member);
  }

  Future<void> _editAgent([CustomAgentSettings? agent]) async {
    final result = await AppDialogMotion.show<CustomAgentSettings>(
      context: context,
      builder: (_) => CustomAgentEditorDialog(agent: agent),
    );
    if (result == null || !mounted) return;
    final saved = await ref
        .read(appSettingsViewModelProvider.notifier)
        .saveCustomAgent(result);
    if (!saved && mounted) {
      ref
          .read(appNotificationControllerProvider.notifier)
          .warning(AppNotificationMessage.completedWithWarnings);
    }
  }

  Future<void> _deleteAgent(CustomAgentSettings agent) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      icon: LucideIcons.userMinus,
      tone: AppDialogTone.info,
      title: context.l10n.settingsDeleteAgent,
      message: context.l10n.settingsAgentDeleteConfirm,
      confirmLabel: context.l10n.agentsRemoveAction,
      confirmIcon: LucideIcons.userMinus,
    );
    if (confirmed == true && mounted) {
      await ref
          .read(appSettingsViewModelProvider.notifier)
          .deleteCustomAgent(agent.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(appSettingsViewModelProvider);
    final catalog = ref.watch(deviceAgentCatalogProvider);
    final members = ref.watch(deviceAgentMembersProvider);
    final operations = ref.watch(skillOperationsViewModelProvider);
    final busy =
        settings.isBusy ||
        operations.operation.running ||
        operations.busyActivations.isNotEmpty;
    final loading = catalog.isLoading || members.isLoading;
    final failed = catalog.hasError || members.hasError;
    final ids = members.value ?? const <String>{};
    final builtIn = [...?catalog.value?.where((agent) => agent.isBuiltIn)]
      ..sort((a, b) {
        final membership = (ids.contains(b.id) ? 1 : 0).compareTo(
          ids.contains(a.id) ? 1 : 0,
        );
        if (membership != 0) return membership;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    final memberCount = builtIn.where((agent) => ids.contains(agent.id)).length;
    final visibleBuiltIn = _showAllBuiltIn || memberCount == 0
        ? builtIn
        : builtIn.take(memberCount).toList();
    final customAgents = settings.settings.customAgents;
    final disabled = busy || loading || failed;
    return Column(
      key: const Key('agents-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showSectionHeader) ...[
          SettingsSectionHeader(
            title: l10n.settingsAgentsTitle,
            description: l10n.settingsAgentsDescription,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (settings.errorCode != null &&
            settings.errorCode != 'settings_load_failed') ...[
          Text(
            settings.errorCode == 'settings_agent_id_conflict'
                ? l10n.settingsAgentInvalidPath
                : l10n.settingsAgentReloadFailed,
            key: const Key('settings-agents-error'),
            style: AppTypography.of(context).body
                .copyWith(color: AppPalette.of(context).danger),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        SettingsGroup(
          label: l10n.agentsBuiltIn,
          children: [
            if (loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CupertinoActivityIndicator(),
              )
            else if (failed)
              SettingsRow(
                title: l10n.settingsAgentReloadFailed,
                trailing: AppButton(
                  key: const Key('settings-agents-retry'),
                  label: l10n.commonRetry,
                  icon: LucideIcons.refreshCw,
                  onPressed: busy
                      ? null
                      : () {
                          ref
                              .read(activationCatalogRevisionProvider.notifier)
                              .refresh();
                          if (settings.errorCode == 'settings_load_failed') {
                            unawaited(
                              ref
                                  .read(appSettingsViewModelProvider.notifier)
                                  .load(),
                            );
                          }
                        },
                ),
              )
            else if (builtIn.isEmpty)
              SettingsFootnote(l10n.agentsEmpty)
            else ...[
              for (final agent in visibleBuiltIn)
                SettingsRow(
                  key: Key('managed-agent-${agent.id}'),
                  leading: _AgentBadge(child: AgentLogo(agentId: agent.id)),
                  title: agent.displayName,
                  description: agent.detected
                      ? l10n.agentsDetected
                      : l10n.workspaceNotDetected,
                  trailing: CupertinoSwitch(
                    key: Key('agent-membership-${agent.id}'),
                    value: ids.contains(agent.id),
                    activeTrackColor: AppPalette.of(context).success,
                    onChanged: disabled
                        ? null
                        : (value) => unawaited(_setMembership(agent, value)),
                  ),
                ),
              if (memberCount > 0 && memberCount < builtIn.length)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Center(
                    child: AppButton(
                      key: const Key('settings-agents-show-all'),
                      label: _showAllBuiltIn
                          ? l10n.agentsShowFewer
                          : l10n.agentsShowAll(builtIn.length),
                      icon: _showAllBuiltIn
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      style: NeoButtonVariant.ghost,
                      onPressed: () =>
                          setState(() => _showAllBuiltIn = !_showAllBuiltIn),
                    ),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          label: l10n.settingsCustomAgents,
          trailing: AppButton(
            key: const Key('settings-add-agent'),
            label: l10n.settingsAddAgent,
            icon: LucideIcons.plus,
            onPressed: disabled ? null : () => unawaited(_editAgent()),
          ),
          children: [
            if (customAgents.isEmpty)
              SettingsFootnote(
                l10n.settingsAgentNoCustom,
                key: const Key('settings-custom-agents-empty'),
              )
            else
              for (final agent in customAgents)
                _CustomAgentRow(
                  agent: agent,
                  enabled: !disabled,
                  onEdit: () => unawaited(_editAgent(agent)),
                  onDelete: () => unawaited(_deleteAgent(agent)),
                ),
          ],
        ),
      ],
    );
  }
}

class _AgentBadge extends StatelessWidget {
  const _AgentBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: AppCorners.smooth(
      color: AppPalette.of(context).agentChip,
      radius: AppRadii.sm,
      side: BorderSide(color: AppPalette.of(context).border),
    ),
    child: child,
  );
}

class _CustomAgentRow extends StatelessWidget {
  const _CustomAgentRow({
    required this.agent,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomAgentSettings agent;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    key: Key('custom-agent-${agent.id}'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.md,
    ),
    child: Row(
      children: [
        _AgentBadge(
          child: Icon(
            AgentLogo.iconFor(agent.iconName),
            size: AppSizes.iconMd,
            color: AppPalette.of(context).bodyContent,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agent.displayName,
                style: AppTypography.of(context).body.copyWith(
                  color: AppPalette.of(context).textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                agent.platforms.values
                    .map((p) => p.globalSkillsPath ?? p.projectSkillsPath ?? '')
                    .where((path) => path.isNotEmpty)
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.of(context).mono.copyWith(
                  color: AppPalette.of(context).textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        AppIconButton(
          key: Key('edit-agent-${agent.id}'),
          icon: LucideIcons.pencil,
          tooltip: context.l10n.settingsEditAgent,
          style: NeoButtonVariant.ghost,
          onPressed: enabled ? onEdit : null,
        ),
        AppIconButton(
          key: Key('delete-agent-${agent.id}'),
          icon: LucideIcons.trash2,
          tooltip: context.l10n.settingsDeleteAgent,
          style: NeoButtonVariant.ghost,
          foregroundColor: AppPalette.of(context).danger,
          onPressed: enabled ? onDelete : null,
        ),
      ],
    ),
  );
}
