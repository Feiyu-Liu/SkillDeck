import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/cloud/presentation/widgets/cloud_note_review.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';

typedef _SkillStatus = ({
  CloudSkillSyncStatus status,
  SyncNeedsAttention? attention,
});

final class CloudSkillSyncMark extends ConsumerWidget {
  const CloudSkillSyncMark({required this.skillId, super.key});

  final WorkspaceSkillId skillId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(cloudSyncRuntimeProvider);
    if (runtime == null) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(
      cloudSyncStateProvider.select(
        (snapshot) => snapshot.value?.accountId == runtime.accountId
            ? (
                snapshot.value!.skill(skillId.value),
                snapshot.value!.metadataAttention[skillId.value]?.reason,
                snapshot.value!.metadataWaitingSkillIds.contains(skillId.value),
              )
            : null,
      ),
    );
    if (state == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final (content, metadata, metadataWaiting) = state;
    final (icon, color) = switch (content.status) {
      CloudSkillSyncStatus.deviceOnly => (
        LucideIcons.cloudOff,
        palette.textSecondary,
      ),
      CloudSkillSyncStatus.synced => (LucideIcons.cloudCheck, palette.success),
      CloudSkillSyncStatus.waiting => (LucideIcons.cloudUpload, palette.info),
      CloudSkillSyncStatus.applying => (LucideIcons.refreshCw, palette.info),
      CloudSkillSyncStatus.attention => (
        LucideIcons.triangleAlert,
        palette.warning,
      ),
    };
    Widget mark(IconData icon, Color color, String label) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: AppTooltip(
        message: label,
        child: Icon(
          icon,
          size: AppSizes.iconXs,
          color: color,
          semanticLabel: label,
        ),
      ),
    );
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark(icon, color, _label(l10n, content)),
        if (metadataWaiting)
          mark(LucideIcons.clock, palette.info, l10n.cloudMetadataWaiting),
        if (metadata != null)
          mark(
            LucideIcons.fileWarning,
            palette.warning,
            cloudNoteAttentionLabel(l10n, metadata),
          ),
      ],
    );
  }
}

final class CloudSkillSyncTile extends ConsumerStatefulWidget {
  const CloudSkillSyncTile({
    required this.skillId,
    required this.enabled,
    this.onEditNote,
    super.key,
  });

  final WorkspaceSkillId skillId;
  final bool enabled;
  final VoidCallback? onEditNote;

  @override
  ConsumerState<CloudSkillSyncTile> createState() => _CloudSkillSyncTileState();
}

final class _CloudSkillSyncTileState extends ConsumerState<CloudSkillSyncTile> {
  bool _changing = false;

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(cloudSyncRuntimeProvider);
    if (runtime == null) return const SizedBox.shrink();
    final state = ref.watch(cloudSyncStateProvider).value;
    if (state?.accountId != runtime.accountId) return const SizedBox.shrink();
    final id = widget.skillId.value;
    final status = state!.skill(id);
    final label = context.l10n.cloudSyncToggle;
    final metadata = state.metadataAttention[id];
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.of(context).sectionLabel),
                Text(
                  _label(context.l10n, status),
                  style: AppTypography.of(context).bodyMuted,
                ),
                if (state.metadataWaitingSkillIds.contains(id))
                  Text(
                    context.l10n.cloudMetadataWaiting,
                    style: AppTypography.of(context).bodyMuted,
                  ),
                if (metadata != null)
                  CloudNoteReviewAction(
                    skillId: id,
                    runtime: runtime,
                    attention: metadata,
                    onEditNote: widget.onEditNote,
                    enabled:
                        widget.enabled &&
                        state.notice != CloudSyncNotice.stopped,
                  ),
              ],
            ),
          ),
          Semantics(
            label: label,
            child: CupertinoSwitch(
              key: const Key('cloud-sync-toggle'),
              value: state.links.containsKey(id),
              onChanged:
                  widget.enabled &&
                      state.bootstrapCompleted &&
                      !_changing &&
                      status.status != CloudSkillSyncStatus.applying &&
                      state.notice != CloudSyncNotice.stopped
                  ? (enabled) => unawaited(_toggle(runtime, id, enabled))
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(
    CloudSyncRuntime runtime,
    String id,
    bool enabled,
  ) async {
    setState(() => _changing = true);
    try {
      await runtime.runAction(
        (sync) => enabled ? sync.startSyncing(id) : sync.stopSyncing(id),
      );
    } on Object {
      // Account switches and stable stop notices are surfaced by the runtime.
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }
}

String _label(AppLocalizations l10n, _SkillStatus state) =>
    switch (state.status) {
      CloudSkillSyncStatus.deviceOnly => l10n.cloudSyncDeviceOnly,
      CloudSkillSyncStatus.synced => l10n.cloudSyncSynced,
      CloudSkillSyncStatus.waiting => l10n.cloudSyncWaiting,
      CloudSkillSyncStatus.applying => l10n.cloudSyncApplying,
      CloudSkillSyncStatus.attention => switch (state.attention!.reason) {
        AttentionReason.incomingDraft => l10n.cloudSyncIncomingDraft,
        AttentionReason.syncMergeConflict => l10n.cloudSyncMergeConflict,
        AttentionReason.removedWithDraft => l10n.cloudSyncRemovedWithDraft,
        AttentionReason.tooLarge => l10n.cloudSyncTooLarge,
        AttentionReason.slotOccupied => l10n.cloudSyncSlotOccupied,
        AttentionReason.missingAfterReset => l10n.cloudSyncMissingAfterReset,
        AttentionReason.sourceReplacedWithLocalChanges =>
          l10n.cloudSyncSourceReplaced,
      },
    };
