import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';

import 'custom_agent_editor_dialog.dart';

Future<void> showAgentManagementDialog(BuildContext context) =>
    AppDialogMotion.show<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AgentManagementDialog(),
    );

class AgentManagementDialog extends ConsumerStatefulWidget {
  const AgentManagementDialog({super.key});
  @override
  ConsumerState<AgentManagementDialog> createState() =>
      _AgentManagementDialogState();
}

class _AgentManagementDialogState extends ConsumerState<AgentManagementDialog> {
  bool _choosingBuiltIn = false;
  String _query = '';

  Future<void> _edit([CustomAgentSettings? agent]) async {
    final result = await AppDialogMotion.show<CustomAgentSettings>(
      context: context,
      builder: (_) => CustomAgentEditorDialog(agent: agent),
    );
    if (result != null && mounted) {
      await ref
          .read(appSettingsViewModelProvider.notifier)
          .saveCustomAgent(result);
    }
  }

  Future<void> _remove(WorkspaceAgentInfo agent) async {
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
    final vm = ref.read(appSettingsViewModelProvider.notifier);
    if (agent.isBuiltIn) {
      await vm.setBuiltInAgentMembership(agent.id, false);
    } else {
      await vm.deleteCustomAgent(agent.id);
    }
  }

  Future<void> _include(String agentId) async {
    final saved = await ref
        .read(appSettingsViewModelProvider.notifier)
        .setBuiltInAgentMembership(agentId, true);
    if (saved && mounted) {
      setState(() {
        _choosingBuiltIn = false;
        _query = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final disabled = busy || loading || failed;
    final agents = [...?catalog.value]
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    final ids = members.value ?? const <String>{};
    final visible = agents
        .where(
          (a) => _choosingBuiltIn
              ? a.isBuiltIn &&
                    !ids.contains(a.id) &&
                    a.displayName.toLowerCase().contains(_query.toLowerCase())
              : ids.contains(a.id),
        )
        .toList();
    void close() => Navigator.of(context).pop();
    return PopScope(
      canPop: !busy,
      child: AppDialogScaffold(
        key: const Key('agent-management-dialog'),
        width: AppDialogWidths.wide,
        onEscape: busy ? null : close,
        header: AppDialogHeader(
          icon: LucideIcons.bot,
          titleKey: const Key('agent-management-title'),
          title: _choosingBuiltIn
              ? context.l10n.agentsAddBuiltInTitle
              : context.l10n.agentsManage,
          subtitle: _choosingBuiltIn
              ? context.l10n.agentsAddBuiltInSubtitle
              : context.l10n.agentsManageSubtitle,
          actions: [
            appDialogCloseButton(
              context,
              key: const Key('agent-management-close'),
              onPressed: busy ? null : close,
            ),
          ],
        ),
        sections: [
          if (_choosingBuiltIn)
            AppDialogSection(
              child: CupertinoSearchTextField(
                key: const Key('agent-catalog-search'),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          AppDialogSection(
            title: _choosingBuiltIn
                ? null
                : context.l10n.agentsManagedListTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (busy || loading) const CupertinoActivityIndicator(),
                if (failed)
                  AppButton(
                    label: context.l10n.commonRetry,
                    onPressed: busy
                        ? null
                        : () {
                            ref
                                .read(
                                  activationCatalogRevisionProvider.notifier,
                                )
                                .refresh();
                            if (settings.errorCode == 'settings_load_failed') {
                              ref
                                  .read(appSettingsViewModelProvider.notifier)
                                  .load();
                            }
                          },
                  ),
                if (settings.errorCode != null &&
                    settings.errorCode != 'settings_load_failed')
                  Text(
                    context.l10n.settingsAgentReloadFailed,
                    style: AppTypography.of(context).body
                        .copyWith(color: AppPalette.of(context).danger),
                  ),
                if (!loading && !failed && visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.l10n.agentsEmpty,
                      style: AppTypography.of(context).bodyMuted,
                    ),
                  ),

                for (final agent in visible)
                  Padding(
                    key: Key('managed-agent-${agent.id}'),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        AgentLogo(agentId: agent.id, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                agent.displayName,
                                style: AppTypography.of(context).subtitle,
                              ),
                              Text(
                                agent.detected
                                    ? context.l10n.agentsDetected
                                    : context.l10n.workspaceNotDetected,
                                style: AppTypography.of(context).caption,
                              ),
                            ],
                          ),
                        ),
                        if (_choosingBuiltIn)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: disabled ? null : () => _include(agent.id),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  context.l10n.agentsAddAction,
                                  style: AppTypography.of(context).control,
                                ),
                                const SizedBox(width: 4),
                                AppIconButton(
                                  key: Key('include-agent-${agent.id}'),
                                  icon: LucideIcons.plus,
                                  tooltip: context.l10n.settingsAddAgent,
                                  style: NeoButtonVariant.ghost,
                                  onPressed: disabled
                                      ? null
                                      : () => _include(agent.id),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          if (!agent.isBuiltIn)
                            AppIconButton(
                              key: Key('manage-edit-agent-${agent.id}'),
                              icon: LucideIcons.pencil,
                              tooltip: context.l10n.settingsEditAgent,
                              onPressed: disabled
                                  ? null
                                  : () => _edit(
                                      settings.settings.customAgents.firstWhere(
                                        (a) => a.id == agent.id,
                                      ),
                                    ),
                            ),
                          AppIconButton(
                            key: Key('exclude-agent-${agent.id}'),
                            icon: LucideIcons.trash2,
                            tooltip: context.l10n.agentsRemoveTitle,
                            foregroundColor: AppPalette.of(context).danger,
                            style: NeoButtonVariant.ghost,
                            onPressed: disabled ? null : () => _remove(agent),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        footer: AppDialogFooter(
          leading: _choosingBuiltIn
              ? AppIconButton(
                  key: const Key('agent-catalog-back'),
                  icon: LucideIcons.chevronLeft,
                  tooltip: context.l10n.commonBack,
                  style: NeoButtonVariant.ghost,
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _choosingBuiltIn = false;
                          _query = '';
                        }),
                )
              : Text(
                  context.l10n.agentsManagedCount(visible.length),
                  style: AppTypography.of(context).caption,
                ),
          actions: [
            if (!_choosingBuiltIn)
              MorphingMenuButton(
                key: const Key('agent-management-add'),
                label: context.l10n.settingsAddAgent,
                icon: LucideIcons.plus,
                enabled: !disabled,
                enableDragResize: false,
                expandedWidth: 220,
                expandedHeight: 120,
                contentBuilder: (_, close) => Column(
                  children: [
                    AppMorphingMenuOption(
                      key: const Key('agent-add-built-in'),
                      label: context.l10n.agentsBuiltIn,
                      selected: false,
                      onPressed: () {
                        setState(() => _choosingBuiltIn = true);
                      },
                    ),
                    AppMorphingMenuOption(
                      key: const Key('agent-add-custom'),
                      label: context.l10n.settingsCustomAgents,
                      selected: false,
                      onPressed: () {
                        close();
                        _edit();
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
