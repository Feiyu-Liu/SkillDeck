import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';
import 'package:skills_manager/features/skills/agent_root_ownership_coordinator.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';

final class CupertinoAgentRootOwnershipReviewPresenter
    implements AgentRootOwnershipReviewPresenter {
  const CupertinoAgentRootOwnershipReviewPresenter({
    required GlobalKey<NavigatorState> navigatorKey,
  }) : _navigatorKey = navigatorKey;

  final GlobalKey<NavigatorState> _navigatorKey;

  @override
  Future<Set<String>?> review(WorkspaceAgentRootOwnershipAudit audit) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return null;
    return AppDialogMotion.show<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AgentRootOwnershipReviewDialog(audit: audit),
    );
  }
}

final class _AgentRootOwnershipReviewDialog extends StatefulWidget {
  const _AgentRootOwnershipReviewDialog({required this.audit});

  final WorkspaceAgentRootOwnershipAudit audit;

  @override
  State<_AgentRootOwnershipReviewDialog> createState() =>
      _AgentRootOwnershipReviewDialogState();
}

final class _AgentRootOwnershipReviewDialogState
    extends State<_AgentRootOwnershipReviewDialog> {
  late final Set<String> _confirmedCustomRoots = <String>{};

  bool get _allCustomRootsConfirmed => widget.audit.repairableIssues
      .where((issue) => issue.requiresCustomAgentConfirmation)
      .every((issue) => _confirmedCustomRoots.contains(issue.rootPath));

  Set<String> get _reviewedRoots => {
    for (final issue in widget.audit.repairableIssues) issue.rootPath,
  };

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) => AppConfirmDialog(
    icon: LucideIcons.folderLock,
    tone: AppDialogTone.warning,
    title: context.l10n.ownershipRepairTitle,
    message: context.l10n.ownershipRepairMessage,
    onEscape: _cancel,
    sections: [
      AppDialogSection(
        child: AppDialogNote(
          tone: AppDialogTone.info,
          text: context.l10n.ownershipRepairSystemPrompt,
        ),
      ),
      AppDialogSection(
        title: context.l10n.ownershipRepairFoldersTitle,
        child: Column(
          children: widget.audit.repairableIssues.map(_buildIssue).toList(),
        ),
      ),
    ],
    actions: [
      AppButton(
        key: const Key('ownership-repair-cancel'),
        label: context.l10n.ownershipRepairCancel,
        style: NeoButtonVariant.secondary,
        size: NeoButtonSize.large,
        fullWidth: true,
        onPressed: _cancel,
      ),
      AppButton(
        key: const Key('ownership-repair-confirm'),
        label: context.l10n.ownershipRepairContinue,
        icon: LucideIcons.wrench,
        style: NeoButtonVariant.primary,
        size: NeoButtonSize.large,
        fullWidth: true,
        onPressed: _allCustomRootsConfirmed
            ? () => Navigator.of(context).pop(_reviewedRoots)
            : null,
      ),
    ],
  );

  Widget _buildIssue(WorkspaceAgentRootOwnershipIssue issue) {
    final custom = issue.requiresCustomAgentConfirmation;
    final selected = !custom || _confirmedCustomRoots.contains(issue.rootPath);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: custom
                ? CupertinoSwitch(
                    key: ValueKey<String>(
                      'ownership-custom-root-${issue.rootPath}',
                    ),
                    value: selected,
                    onChanged: (value) {
                      setState(() {
                        if (value) {
                          _confirmedCustomRoots.add(issue.rootPath);
                        } else {
                          _confirmedCustomRoots.remove(issue.rootPath);
                        }
                      });
                    },
                  )
                : Icon(
                    LucideIcons.circleCheck,
                    size: 16,
                    color: AppPalette.of(context).success,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  custom
                      ? context.l10n.ownershipRepairCustomAgent
                      : context.l10n.ownershipRepairBuiltInAgent,
                  style: AppTypography.of(context).body,
                ),
                const SizedBox(height: 2),
                Text(
                  issue.rootPath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.of(context).mono
                      .copyWith(color: AppPalette.of(context).textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
