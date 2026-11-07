import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/command_host/data/command_line_distribution.dart';
import 'package:skills_manager/features/command_host/data/command_line_path_link_service.dart';
import 'package:skills_manager/features/command_host/presentation/command_host_providers.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_distribution_providers.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/navigation/app_routes.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// Settings → Command Line: whether Agents can reach SkillDeck, where the CLI
/// lives, and the Agent Skill that teaches them to use it (ADR-0111).
class CommandLineSettings extends StatelessWidget {
  const CommandLineSettings({required this.showSectionHeader, super.key});

  final bool showSectionHeader;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('command-line-settings'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showSectionHeader) ...[
        SettingsSectionHeader(
          title: context.l10n.settingsCommandLineTitle,
          description: context.l10n.settingsCommandLineDescription,
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
      const _StatusGroup(),
      const SizedBox(height: AppSpacing.xl),
      const _ToolGroup(),
      const SizedBox(height: AppSpacing.xl),
      const _AgentSkillGroup(),
      const SizedBox(height: AppSpacing.xl),
      const _SafetyGroup(),
    ],
  );
}

class _StatusGroup extends ConsumerWidget {
  const _StatusGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final running = ref.watch(commandHostProvider).value != null;
    final version = ref.watch(commandHostAppVersionProvider).value ?? '';
    final color = running
        ? AppPalette.of(context).success
        : AppPalette.of(context).textSecondary;
    return SettingsGroup(
      label: l10n.commandLineStatusGroup,
      children: [
        SettingsRow(
          key: const Key('command-line-status'),
          title: l10n.commandLineStatusTitle,
          description: l10n.commandLineStatusDetail(version),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                running
                    ? l10n.commandLineStatusRunningBadge
                    : l10n.commandLineStatusStoppedBadge,
                style: AppTypography.of(context).caption
                    .copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolGroup extends ConsumerWidget {
  const _ToolGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tool = ref.watch(commandLineToolProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          label: l10n.commandLineToolGroup,
          children: [
            SettingsRow(
              title: l10n.commandLineToolLocation,
              description: switch (tool?.status) {
                CommandLineToolStatus.notBundled =>
                  l10n.commandLineToolNotBundled,
                CommandLineToolStatus.failed => l10n.commandLineToolFailed,
                _ => l10n.commandLineToolLocationDetail,
              },
            ),
            if (tool != null && tool.status != CommandLineToolStatus.notBundled)
              _CodeLine(
                key: const Key('command-line-tool-path'),
                text: tool.path,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SettingsGroup(
          children: [
            if (ref.watch(commandLinePathLinkServiceProvider) case final link?)
              _PathLinkRow(link: link)
            else ...[
              SettingsRow(
                title: l10n.commandLinePathTitle,
                description: Platform.isWindows
                    ? l10n.commandLinePathWindows
                    : l10n.commandLinePathDetail,
              ),
              if (!Platform.isWindows)
                const _CodeLine(
                  key: Key('command-line-path-line'),
                  text: _manualPathLine,
                ),
            ],
          ],
        ),
      ],
    );
  }
}

const _manualPathLine = r'export PATH="$HOME/.skilldeck/bin:$PATH"';

/// macOS: one click links `skilldeck` into /usr/local/bin; anything already
/// there is left alone and the manual PATH line is offered instead.
class _PathLinkRow extends ConsumerStatefulWidget {
  const _PathLinkRow({required this.link});

  final CommandLinePathLink link;

  @override
  ConsumerState<_PathLinkRow> createState() => _PathLinkRowState();
}

class _PathLinkRowState extends ConsumerState<_PathLinkRow> {
  var _busy = false;
  var _failed = false;

  Future<void> _run(
    Future<CommandLinePathLinkOutcome> Function() action,
  ) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final outcome = await action();
    if (!mounted) return;
    ref.invalidate(commandLinePathLinkProvider);
    setState(() {
      _busy = false;
      _failed = outcome == CommandLinePathLinkOutcome.failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(commandLinePathLinkProvider).value;
    final conflict = status == CommandLinePathLinkStatus.conflict;
    final installed = status == CommandLinePathLinkStatus.installed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          key: const Key('command-line-path-link'),
          title: l10n.commandLinePathLinkTitle,
          description: switch (status) {
            CommandLinePathLinkStatus.installed =>
              l10n.commandLinePathLinkInstalled(widget.link.linkPath),
            CommandLinePathLinkStatus.conflict =>
              l10n.commandLinePathLinkConflict,
            _ => l10n.commandLinePathLinkDetail,
          },
          trailing: status == null || conflict
              ? null
              : installed
              ? AppButton(
                  key: const Key('command-line-path-link-remove'),
                  label: l10n.commandLinePathLinkRemove,
                  size: NeoButtonSize.small,
                  onPressed: _busy
                      ? null
                      : () => unawaited(_run(widget.link.remove)),
                )
              : AppButton(
                  key: const Key('command-line-path-link-install'),
                  label: l10n.commandLinePathLinkInstall,
                  icon: LucideIcons.terminal,
                  style: NeoButtonVariant.primary,
                  size: NeoButtonSize.small,
                  onPressed: _busy
                      ? null
                      : () => unawaited(_run(widget.link.install)),
                ),
          below: _failed
              ? Text(
                  l10n.commandLinePathLinkFailed,
                  style: AppTypography.of(context).caption
                      .copyWith(color: AppPalette.of(context).danger),
                )
              : null,
        ),
        if (conflict) ...[
          SizedBox(
            height: 1,
            child: ColoredBox(color: AppPalette.of(context).border),
          ),
          const _CodeLine(
            key: Key('command-line-path-line'),
            text: _manualPathLine,
          ),
        ],
      ],
    );
  }
}

class _CodeLine extends StatelessWidget {
  const _CodeLine({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.sm, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: AppTypography.of(context).mono.copyWith(fontSize: 12),
          ),
        ),
        AppIconButton(
          icon: LucideIcons.copy,
          tooltip: CupertinoLocalizations.of(context).copyButtonLabel,
          style: NeoButtonVariant.ghost,
          foregroundColor: AppPalette.of(context).textSecondary,
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        ),
      ],
    ),
  );
}

class _AgentSkillGroup extends ConsumerStatefulWidget {
  const _AgentSkillGroup();

  @override
  ConsumerState<_AgentSkillGroup> createState() => _AgentSkillGroupState();
}

class _AgentSkillGroupState extends ConsumerState<_AgentSkillGroup> {
  var _installing = false;
  var _failed = false;

  // Every Agent set up on this device; with none, the Skill is only stored.
  Future<void> _install(Set<String> agentIds) async {
    setState(() {
      _installing = true;
      _failed = false;
    });
    final failure = await ref
        .read(skillDeckAgentSkillServiceProvider)
        .install(agentIds: agentIds);
    if (!mounted) return;
    setState(() {
      _installing = false;
      _failed = failure != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final skill = ref.watch(skillDeckAgentSkillProvider);
    final catalog =
        ref.watch(deviceAgentCatalogProvider).value ??
        const <WorkspaceAgentInfo>[];
    final members = ref.watch(deviceAgentMembersProvider).value ?? const {};
    final agentIds = {
      for (final agent in catalog)
        if (members.contains(agent.id)) agent.id,
    };

    final String description;
    if (!skill.installed) {
      description = l10n.commandLineAgentSkillNotInstalled;
    } else if (skill.activeAgentIds.isEmpty) {
      description = l10n.commandLineAgentSkillInactive;
    } else {
      description = l10n.commandLineAgentSkillActive;
    }

    return SettingsGroup(
      label: l10n.commandLineAgentSkillGroup,
      children: [
        SettingsRow(
          key: const Key('command-line-agent-skill'),
          title: l10n.commandLineAgentSkillTitle,
          description: description,
          trailing: skill.installed
              ? AppButton(
                  key: const Key('command-line-agent-skill-open'),
                  label: l10n.commandLineAgentSkillOpen,
                  icon: LucideIcons.arrowUpRight,
                  size: NeoButtonSize.small,
                  onPressed: () => context.pushNamed(
                    AppRouteNames.skillDetail,
                    pathParameters: {'skillId': skill.skillId!.value},
                  ),
                )
              : AppButton(
                  key: const Key('command-line-agent-skill-install'),
                  label: _installing
                      ? l10n.commandLineAgentSkillInstalling
                      : l10n.commandLineAgentSkillInstall,
                  icon: LucideIcons.download,
                  style: NeoButtonVariant.primary,
                  size: NeoButtonSize.small,
                  onPressed: _installing
                      ? null
                      : () => unawaited(_install(agentIds)),
                ),
          below: !skill.installed && _failed
              ? Text(
                  l10n.commandLineAgentSkillInstallFailed,
                  style: AppTypography.of(context).caption
                      .copyWith(color: AppPalette.of(context).danger),
                )
              : null,
        ),
      ],
    );
  }
}

class _SafetyGroup extends StatelessWidget {
  const _SafetyGroup();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsGroup(
      label: l10n.commandLineSafetyGroup,
      children: [
        SettingsRow(
          title: l10n.commandLineSafetyTitle,
          description: l10n.commandLineSafetyDetail,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.lock,
                size: 13,
                color: AppPalette.of(context).textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.commandLineSafetyAlwaysOn,
                style: AppTypography.of(context).caption.copyWith(
                  color: AppPalette.of(context).textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
