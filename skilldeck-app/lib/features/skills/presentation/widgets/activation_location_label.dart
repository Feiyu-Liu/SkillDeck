import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';

import 'agent_logo.dart';

String activationAgentGroupTitle(
  BuildContext context,
  ActivationLocationGroup group,
) => group.shared
    ? context.l10n.activationUniversalAgents
    : group.names.isEmpty
    ? context.l10n.activationUnknownAgent
    : group.names;

class AgentActivationSwitch extends StatelessWidget {
  const AgentActivationSwitch({
    required this.on,
    required this.label,
    this.onChanged,
    super.key,
  });
  final bool on;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    toggled: on,
    enabled: onChanged != null,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onChanged == null ? null : () => onChanged!(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        width: 42,
        height: 24,
        padding: const EdgeInsets.all(3),
        decoration: AppCorners.smooth(
          color: on
              ? AppPalette.of(context).ink
              : AppPalette.of(context).controlInactive,
          radius: 12,
        ),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppPalette.of(context).onPrimary,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(dimension: 18),
        ),
      ),
    ),
  );
}

/// Shared identity used by acquisition, detail settings and activation dialogs.
class AgentActivationGroupLabel extends StatelessWidget {
  const AgentActivationGroupLabel({required this.group, super.key});
  final ActivationLocationGroup group;

  @override
  Widget build(BuildContext context) {
    final agents = group.visibleAgents;
    return Row(
      children: [
        if (group.shared && agents.isNotEmpty)
          AppTooltip(
            message: agents.map((t) => t.displayName).join(', '),
            maxWidth: 420,
            maxLines: null,
            child: _SharedAgentLogos(
              agentIds: agents.map((t) => t.agentId).toSet().toList(),
            ),
          )
        else if (group.shared || group.names.isEmpty)
          Icon(LucideIcons.bot, size: 22, color: AppPalette.of(context).ink)
        else
          AgentLogo(agentId: group.first.agentId, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activationAgentGroupTitle(context, group),
                style: AppTypography.of(context).subtitle,
              ),
              const SizedBox(height: 3),
              AppTooltip(
                message: group.location,
                maxWidth: 420,
                maxLines: null,
                child: Text(
                  group.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.of(context).mono
                      .copyWith(color: AppPalette.of(context).textSecondary),
                ),
              ),
              if (group.memberIds != null && !group.canActivate) ...[
                const SizedBox(height: 3),
                Text(
                  context.l10n.agentsOutsideRoster,
                  style: AppTypography.of(context).caption,
                ),
              ] else if (!group.detected) ...[
                const SizedBox(height: 3),
                Text(
                  context.l10n.workspaceNotDetected,
                  style: AppTypography.of(context).sectionLabel
                      .copyWith(color: AppPalette.of(context).textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The Agents sharing one location, each logo at the size a single Agent's
/// row uses, with a count for any beyond the first few.
class _SharedAgentLogos extends StatelessWidget {
  const _SharedAgentLogos({required this.agentIds});

  static const _maxVisible = 3;

  final List<String> agentIds;

  @override
  Widget build(BuildContext context) {
    final hidden = agentIds.length - _maxVisible;
    return Row(
      key: const Key('shared-agent-logos'),
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        for (final agentId in agentIds.take(_maxVisible))
          AgentLogo(agentId: agentId, size: 22),
        if (hidden > 0)
          Text(
            '+$hidden',
            style: AppTypography.of(context).caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppPalette.of(context).textSecondary,
            ),
          ),
      ],
    );
  }
}
