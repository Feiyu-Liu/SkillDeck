import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/platform/file_location_opener.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';

Future<bool> showActivationTakeoverDialog({
  required BuildContext context,
  required WorkspaceActivationTakeoverDraft draft,
  required String agentName,
}) async {
  if (!context.mounted) return false;
  return await AppDialogMotion.show<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ActivationTakeoverDialog(
          targets: draft.targets,
          agentName: agentName,
          installing: false,
        ),
      ) ??
      false;
}

Future<bool> showInstallTakeoverDialog({
  required BuildContext context,
  required WorkspaceInstallTakeoverDraft draft,
  required String agentName,
}) async {
  if (!context.mounted) return false;
  return await AppDialogMotion.show<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ActivationTakeoverDialog(
          targets: draft.targets,
          agentName: agentName,
          installing: true,
        ),
      ) ??
      false;
}

class _ActivationTakeoverDialog extends ConsumerWidget {
  const _ActivationTakeoverDialog({
    required this.targets,
    required this.agentName,
    required this.installing,
  });

  final List<WorkspaceOccupiedActivationTarget> targets;
  final String agentName;
  final bool installing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void cancel() => Navigator.of(context).pop(false);
    return AppConfirmDialog(
      key: const Key('activation-takeover-dialog'),
      width: AppDialogWidths.standard,
      icon: LucideIcons.replace,
      tone: AppDialogTone.danger,
      title: context.l10n.workspaceTakeoverTitle,
      message: installing
          ? context.l10n.workspaceInstallTakeoverDescription(agentName)
          : context.l10n.workspaceTakeoverDescription(agentName),
      onEscape: cancel,
      sections: [
        AppDialogSection(
          title: context.l10n.workspaceTakeoverTargets,
          child: Column(
            children: [
              for (final (index, target) in targets.indexed) ...[
                if (index > 0) const SizedBox(height: 20),
                _ActivationTakeoverTargetDetails(
                  target: target,
                  onOpenLocation: () => unawaited(_openLocation(ref, target)),
                ),
              ],
            ],
          ),
        ),
        AppDialogSection(
          child: AppDialogNote(
            tone: AppDialogTone.info,
            text: context.l10n.workspaceTakeoverWarning,
          ),
        ),
      ],
      actions: [
        AppButton(
          label: context.l10n.commonCancel,
          style: NeoButtonVariant.secondary,
          size: NeoButtonSize.large,
          fullWidth: true,
          onPressed: cancel,
        ),
        AppButton(
          key: const Key('activation-takeover-confirm'),
          label: installing
              ? context.l10n.workspaceInstallTakeoverConfirm
              : context.l10n.workspaceTakeoverConfirm,
          icon: LucideIcons.replace,
          style: NeoButtonVariant.danger,
          size: NeoButtonSize.large,
          fullWidth: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  Future<void> _openLocation(
    WidgetRef ref,
    WorkspaceOccupiedActivationTarget target,
  ) async {
    final opened = await ref
        .read(fileLocationOpenerProvider)
        .reveal(target.targetPath);
    if (!opened) {
      ref
          .read(appNotificationControllerProvider.notifier)
          .error(AppNotificationMessage.openLocationFailed);
    }
  }
}

class _ActivationTakeoverTargetDetails extends StatelessWidget {
  const _ActivationTakeoverTargetDetails({
    required this.target,
    required this.onOpenLocation,
  });

  final WorkspaceOccupiedActivationTarget target;
  final VoidCallback onOpenLocation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _TakeoverDetailRow(
              label: context.l10n.workspaceTakeoverPath,
              value: target.targetPath,
              monospace: true,
            ),
          ),
          const SizedBox(width: 8),
          AppIconButton(
            key: Key('activation-takeover-open-location-${target.targetPath}'),
            icon: LucideIcons.folderOpen,
            tooltip: context.l10n.workspaceTakeoverOpenLocation,
            style: NeoButtonVariant.ghost,
            onPressed: onOpenLocation,
          ),
        ],
      ),
      const SizedBox(height: 10),
      _TakeoverDetailRow(
        label: context.l10n.workspaceTakeoverType,
        value: _occupancyLabel(context, target.kind),
      ),
      const SizedBox(height: 10),
      _TakeoverDetailRow(
        label: context.l10n.workspaceTakeoverContent,
        value: _contentLabel(context, target.contentRelation),
        color:
            target.contentRelation ==
                WorkspaceActivationContentRelation.differsFromCurrentRevision
            ? AppPalette.of(context).warningStrong
            : null,
      ),
    ],
  );

  String _occupancyLabel(
    BuildContext context,
    WorkspaceActivationTargetOccupancyKind kind,
  ) => switch (kind) {
    WorkspaceActivationTargetOccupancyKind.skillDirectory =>
      context.l10n.workspaceTakeoverSkillDirectory,
    WorkspaceActivationTargetOccupancyKind.skillSymbolicLink =>
      context.l10n.workspaceTakeoverSkillSymbolicLink,
    WorkspaceActivationTargetOccupancyKind.file =>
      context.l10n.workspaceTakeoverFile,
    WorkspaceActivationTargetOccupancyKind.invalidDirectory =>
      context.l10n.workspaceTakeoverInvalidDirectory,
    WorkspaceActivationTargetOccupancyKind.brokenSymbolicLink =>
      context.l10n.workspaceTakeoverBrokenSymbolicLink,
  };

  String _contentLabel(
    BuildContext context,
    WorkspaceActivationContentRelation relation,
  ) => switch (relation) {
    WorkspaceActivationContentRelation.matchesCurrentRevision =>
      context.l10n.workspaceActivateAlreadyActive,
    WorkspaceActivationContentRelation.differsFromCurrentRevision =>
      context.l10n.workspaceTakeoverContentDifferent,
    WorkspaceActivationContentRelation.indeterminate =>
      context.l10n.workspaceTakeoverContentUnknown,
  };
}

class _TakeoverDetailRow extends StatelessWidget {
  const _TakeoverDetailRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.color,
  });

  final String label;
  final String value;
  final bool monospace;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 100,
        child: Text(label, style: AppTypography.of(context).bodyMuted),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              (monospace
                      ? AppTypography.of(context).mono
                      : AppTypography.of(context).body)
                  .copyWith(color: color),
        ),
      ),
    ],
  );
}
