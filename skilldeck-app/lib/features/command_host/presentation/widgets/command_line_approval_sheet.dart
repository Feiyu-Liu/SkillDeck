import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/app/app_router.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';

import '../../data/command_approval.dart';
import '../../data/skill_json.dart';
import '../command_line_approval.dart';

/// Opens the approval sheet whenever the Command Host presents a new
/// request, and brings the window forward without taking focus. Call from
/// the shell's build so it lives as long as the App's routes.
void listenForCommandLineApprovals(WidgetRef ref) {
  ref.listen(commandLineApprovalProvider, (previous, next) {
    if (next == null || previous?.id == next.id) return;
    unawaited(ref.read(commandLineApprovalAttentionProvider)());
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    // The App's standard modal; only Deny or Confirm may close it.
    unawaited(
      AppDialogMotion.show<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const CommandLineApprovalSheet(),
      ),
    );
  });
}

/// Asks the user to approve a destructive command-line request.
///
/// The disclosure is derived from the live Snapshot, so it always describes
/// what confirming would do now. Confirming submits that Snapshot's revision.
/// The sheet closes itself when the request ends, whether by a decision here,
/// expiry, or a cancel from the command line.
class CommandLineApprovalSheet extends ConsumerWidget {
  const CommandLineApprovalSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(commandLineApprovalProvider, (_, next) {
      if (next == null && context.mounted) Navigator.of(context).pop();
    });
    final request = ref.watch(commandLineApprovalProvider);
    final snapshot = ref.watch(workspaceSnapshotProvider).value;
    if (request == null || snapshot == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final controller = ref.read(commandLineApprovalProvider.notifier);
    final agentNames = {
      for (final agent
          in ref.watch(deviceAgentCatalogProvider).value ??
              const <WorkspaceAgentInfo>[])
        agent.id: agent.displayName,
    };
    final revision = snapshot.revision;

    final String title;
    final String confirmLabel;
    final String warning;
    var confirmIcon = LucideIcons.trash2;
    final List<Widget> targets;
    switch (request.subject) {
      case CommandApprovalRemoveSkills(:final skillIds):
        title = l10n.commandLineApprovalRemoveTitle(skillIds.length);
        confirmLabel = l10n.commandLineApprovalConfirmRemove(skillIds.length);
        warning = l10n.commandLineApprovalRemoveWarning;
        targets = [
          for (final id in skillIds)
            _Target(
              name: snapshot.findSkillById(WorkspaceSkillId(id))?.slotKey ?? id,
              effect: _removeEffect(
                context,
                snapshot.findSkillById(WorkspaceSkillId(id)),
                agentNames,
              ),
            ),
        ];
      case CommandApprovalDeleteTag(:final tagId):
        final tag = snapshot.findPersonalTag(tagId);
        final count = snapshot.skills
            .where((skill) => skill.personalTagIds.contains(tagId))
            .length;
        title = l10n.commandLineApprovalDeleteTagTitle(tag?.name ?? tagId);
        confirmLabel = l10n.commandLineApprovalConfirmDeleteTag;
        warning = l10n.commandLineApprovalTagWarning(count);
        targets = const [];
      case CommandApprovalReplaceSource(:final items):
        title = l10n.commandLineApprovalReplaceSourceTitle(items.length);
        confirmLabel = l10n.commandLineApprovalConfirmReplaceSource;
        confirmIcon = LucideIcons.arrowLeftRight;
        // ADR-0080: replacement deletes the former lineage for good.
        warning = l10n.commandLineApprovalReplaceSourceWarning;
        targets = [
          for (final item in items)
            _replaceSourceTarget(
              context,
              item,
              snapshot.findSkillById(WorkspaceSkillId(item.skillId)),
            ),
        ];
    }

    return AppConfirmDialog(
      key: const Key('command-line-approval'),
      width: AppDialogWidths.confirm,
      icon: LucideIcons.terminal,
      tone: AppDialogTone.danger,
      title: title,
      message: l10n.commandLineApprovalSubtitle,
      onEscape: controller.deny,
      sections: [
        if (targets.isNotEmpty)
          AppDialogSection(
            title: request.subject is CommandApprovalRemoveSkills
                ? l10n.commandLineApprovalRemoveSection
                : l10n.commandLineApprovalReplaceSection,
            child: Column(
              key: const Key('command-line-approval-targets'),
              children: [
                for (final (index, target) in targets.indexed) ...[
                  if (index > 0)
                    SizedBox(
                      height: 1,
                      child: ColoredBox(color: AppPalette.of(context).border),
                    ),
                  target,
                ],
              ],
            ),
          ),
        AppDialogSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (request.staleReview) ...[
                AppDialogNote(
                  key: const Key('command-line-approval-stale'),
                  icon: LucideIcons.refreshCw,
                  tone: AppDialogTone.info,
                  text: l10n.commandLineApprovalStale,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              AppDialogNote(tone: AppDialogTone.warning, text: warning),
            ],
          ),
        ),
      ],
      actions: [
        AppButton(
          key: const Key('command-line-approval-deny'),
          label: l10n.commandLineApprovalDeny,
          style: NeoButtonVariant.secondary,
          size: NeoButtonSize.large,
          fullWidth: true,
          onPressed: controller.deny,
        ),
        AppButton(
          key: const Key('command-line-approval-confirm'),
          label: confirmLabel,
          icon: confirmIcon,
          style: NeoButtonVariant.danger,
          size: NeoButtonSize.large,
          fullWidth: true,
          onPressed: () => controller.approve(reviewedRevision: revision),
        ),
      ],
    );
  }

  String _removeEffect(
    BuildContext context,
    WorkspaceSkill? skill,
    Map<String, String> agentNames,
  ) {
    final l10n = context.l10n;
    if (skill == null) return l10n.commandLineApprovalSkillGone;
    final agents = {
      for (final activation in skill.activations)
        for (final id in activation.agentIds) agentNames[id] ?? id,
    };
    final effect = agents.isEmpty
        ? l10n.commandLineApprovalNotActivated
        : l10n.commandLineApprovalActivatedIn(agents.join(', '));
    return skill.draft?.isDirty ?? false
        ? '$effect · ${l10n.commandLineApprovalUnpublishedDraft}'
        : effect;
  }

  /// The Skill and the Source it will follow. The old Source is not shown:
  /// the warning says what replacement discards, and the row stays one line.
  Widget _replaceSourceTarget(
    BuildContext context,
    CommandApprovalReplaceSourceItem item,
    WorkspaceSkill? skill,
  ) {
    if (skill == null) {
      return _Target(
        name: item.candidateDeclaredName,
        effect: context.l10n.commandLineApprovalSkillGone,
      );
    }
    final (icon, label) = commandLineSourceLabel(item.source);
    return _ReplaceSourceRow(name: skill.slotKey, icon: icon, source: label);
  }
}

/// A short, credential-free name for a Source: `owner/repo` on GitHub,
/// `host/path` on other Git hosts, the folder name for a local Source.
(IconData, String) commandLineSourceLabel(SkillSourceInput source) {
  final locator = stripLocatorUserinfo(source.locator);
  switch (source.kind) {
    case WorkspaceSourceKind.local:
    case WorkspaceSourceKind.adoptedSnapshot:
      final parts = locator
          .split(RegExp(r'[/\\]'))
          .where((part) => part.isNotEmpty);
      return (LucideIcons.folder, parts.isEmpty ? locator : parts.last);
    case WorkspaceSourceKind.git:
    case WorkspaceSourceKind.wellKnown:
      var short = locator
          .replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '')
          .replaceFirstMapped(
            RegExp(r'^[^@/]+@([^:/]+):'),
            (match) => '${match[1]}/',
          )
          .replaceFirst(RegExp(r'/+$'), '')
          .replaceFirst(RegExp(r'\.git$'), '');
      if (short.startsWith('github.com/')) {
        short = short.substring('github.com/'.length);
      }
      return (
        source.kind == WorkspaceSourceKind.git
            ? LucideIcons.gitBranch
            : LucideIcons.globe,
        short,
      );
  }
}

class _ReplaceSourceRow extends StatelessWidget {
  const _ReplaceSourceRow({
    required this.name,
    required this.icon,
    required this.source,
  });

  final String name;
  final IconData icon;
  final String source;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.of(context).control
                .copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Icon(
          LucideIcons.arrowRight,
          size: 13,
          color: AppPalette.of(context).textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Icon(icon, size: 13, color: AppPalette.of(context).bodyContent),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            source,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.of(context).caption.copyWith(
              fontWeight: FontWeight.w400,
              color: AppPalette.of(context).bodyContent,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Target extends StatelessWidget {
  const _Target({required this.name, required this.effect});

  final String name;
  final String effect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(LucideIcons.package, size: 16, color: AppPalette.of(context).ink),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: AppTypography.of(context).control
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                effect,
                style: AppTypography.of(context).caption
                    .copyWith(fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
