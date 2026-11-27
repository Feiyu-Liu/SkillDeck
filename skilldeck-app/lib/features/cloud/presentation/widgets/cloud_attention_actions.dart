import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/cloud/data/cloud_incoming_diff.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/models/workspace_review.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/platform/file_location_opener.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';
import 'package:skills_manager/shared/widgets/app_selection_area.dart';

enum _Action {
  publishDraft,
  discardDraft,
  reviewIncoming,
  reviewConflict,
  remove,
  keepDeviceOnly,
  acceptReplacement,
  replaceOccupied,
  exclude,
  stop,
  uploadAsNew,
}

enum _ConflictAction { current, incoming, publish }

class CloudAttentionActions extends ConsumerStatefulWidget {
  const CloudAttentionActions({required this.skillId, super.key});

  final WorkspaceSkillId skillId;

  @override
  ConsumerState<CloudAttentionActions> createState() =>
      _CloudAttentionActionsState();
}

class _CloudAttentionActionsState extends ConsumerState<CloudAttentionActions> {
  bool _busy = false;
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(cloudSyncRuntimeProvider);
    if (runtime == null) return const SizedBox.shrink();
    final snapshot = ref.watch(cloudSyncStateProvider).value;
    if (snapshot?.accountId != runtime.accountId) {
      return const SizedBox.shrink();
    }
    final attention = _attention(snapshot, widget.skillId.value);
    if (attention == null) return const SizedBox.shrink();
    final (reason, lineageId) = attention;
    final l10n = context.l10n;
    final actions = switch (reason) {
      AttentionReason.incomingDraft => [
        _Action.publishDraft,
        _Action.reviewIncoming,
        _Action.discardDraft,
      ],
      AttentionReason.syncMergeConflict => [_Action.reviewConflict],
      AttentionReason.removedWithDraft => [
        _Action.remove,
        _Action.keepDeviceOnly,
      ],
      AttentionReason.sourceReplacedWithLocalChanges => [
        _Action.acceptReplacement,
        _Action.keepDeviceOnly,
      ],
      AttentionReason.slotOccupied when lineageId != null => [
        _Action.replaceOccupied,
        _Action.exclude,
      ],
      AttentionReason.slotOccupied => <_Action>[],
      AttentionReason.tooLarge => [_Action.keepDeviceOnly, _Action.stop],
      AttentionReason.missingAfterReset => [
        _Action.remove,
        _Action.keepDeviceOnly,
        _Action.uploadAsNew,
      ],
    };
    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reason == AttentionReason.slotOccupied)
          Text(
            l10n.cloudOccupiedLocalSlot,
            style: AppTypography.of(context).caption,
          ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final action in actions)
              AppButton(
                key: Key('cloud-attention-${action.name}'),
                label: _label(l10n, action),
                size: NeoButtonSize.small,
                onPressed: _busy
                    ? null
                    : () => unawaited(_run(runtime, attention, action)),
              ),
          ],
        ),
        if (_failed)
          Text(
            l10n.cloudAttentionActionFailed,
            style: AppTypography.of(context).caption,
          ),
      ],
    );
  }

  Future<void> _run(
    CloudSyncRuntime runtime,
    (AttentionReason, String?) attention,
    _Action action,
  ) async {
    final skillId = widget.skillId;
    final (reason, lineageId) = attention;
    final l10n = context.l10n;
    final workspace = ref.read(skillsWorkspaceRepositoryProvider);
    final confirmedRevision = workspace.current?.revision;
    final confirmedLineageVersion = _observedVersion(skillId, lineageId);
    final message = switch (action) {
      _Action.discardDraft => l10n.cloudConfirmDiscardDraft,
      _Action.remove when reason == AttentionReason.removedWithDraft =>
        l10n.cloudConfirmRemoveDraft,
      _Action.remove => l10n.cloudConfirmRemoveSkill,
      _Action.acceptReplacement => l10n.cloudConfirmReplacement,
      _Action.replaceOccupied => l10n.cloudConfirmReplaceSlot,
      _ => null,
    };
    if (message != null) {
      final confirmed = await showAppConfirmDialog(
        context: context,
        icon: LucideIcons.triangleAlert,
        title: _label(l10n, action),
        message: message,
        tone: AppDialogTone.danger,
        confirmLabel: _label(l10n, action),
        confirmStyle: NeoButtonVariant.danger,
        confirmKey: const Key('cloud-attention-confirm'),
        cancelKey: const Key('cloud-attention-cancel'),
      );
      if (!confirmed || !mounted) return;
    }
    if (!_stillCurrent(runtime, skillId, attention)) return;
    final finalization = ref.read(
      workspaceFinalizationCoordinatorProvider.notifier,
    );
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (action == _Action.reviewIncoming) {
        final diff = await runtime.runAction(
          (reconciler) => readCloudIncomingDiff(
            reconciler: reconciler,
            workspace: workspace,
            skillId: skillId,
          ),
        );
        if (!mounted || !_stillCurrent(runtime, skillId, attention)) return;
        if (diff is WorkspaceRevisionPackDiff) {
          await _showIncomingDiff(context, diff);
        } else {
          setState(() => _failed = true);
        }
        return;
      }
      if (action == _Action.reviewConflict) {
        final inspected = await runtime.runAction(
          (_) => workspace.inspectUpdateCandidateResolution(skillId).completed,
        );
        if (!mounted || !_stillCurrent(runtime, skillId, attention)) return;
        final review = switch (inspected) {
          WorkspaceCompleted<WorkspaceUpdateCandidateReview?>(:final value) =>
            value,
          _ => null,
        };
        if (review == null) {
          setState(() => _failed = true);
          return;
        }
        final draftPath = ref
            .read(workspaceSkillByIdProvider(skillId))
            .value
            ?.draft
            ?.path;
        final opener = ref.read(fileLocationOpenerProvider);
        final choice = await _showConflictReview(
          context,
          review,
          openDraft: draftPath == null
              ? null
              : () => unawaited(opener.reveal(draftPath)),
        );
        if (choice == null || !_stillCurrent(runtime, skillId, attention)) {
          return;
        }
        final resolved = await runtime.runAction((reconciler) async {
          if (!_stillCurrent(runtime, skillId, attention)) return null;
          if (choice != _ConflictAction.publish) {
            final selected = await workspace
                .resolveUpdateCandidateConflicts(
                  review: review,
                  side: choice == _ConflictAction.current
                      ? WorkspaceUpdateCandidateSide.current
                      : WorkspaceUpdateCandidateSide.incoming,
                )
                .completed;
            switch (selected) {
              case WorkspaceFailed(:final failure):
                throw failure;
              case WorkspaceCommittedPending():
                finalization.register(selected);
              case WorkspaceCompleted():
                break;
            }
            return null;
          }
          final published = await workspace
              .publishUpdateCandidate(skillId)
              .completed;
          switch (published) {
            case WorkspaceFailed(:final failure):
              throw failure;
            case WorkspaceCommittedPending():
              finalization.register(published);
              return null;
            case WorkspaceCompleted():
              return reconciler.reconcileSkill(skillId.value);
          }
        });
        if (mounted && resolved is SyncNeedsAttention) {
          setState(() => _failed = true);
        }
        return;
      }
      final outcome = await runtime.runAction((reconciler) async {
        if (!_stillCurrent(runtime, skillId, attention)) return null;
        if (message != null &&
            (workspace.current?.revision != confirmedRevision ||
                _observedVersion(skillId, lineageId) !=
                    confirmedLineageVersion)) {
          throw const FormatException('cloud_confirmation_stale');
        }
        switch (action) {
          case _Action.reviewIncoming || _Action.reviewConflict:
            return null;
          case _Action.publishDraft || _Action.discardDraft:
            final completion = await (action == _Action.publishDraft
                ? workspace.publishDraft(skillId).completed
                : workspace.discardDraft(skillId).completed);
            switch (completion) {
              case WorkspaceFailed(:final failure):
                throw failure;
              case WorkspaceCommittedPending():
                finalization.register(completion);
                return null;
              case WorkspaceCompleted():
                break;
            }
            return reconciler.reconcileSkill(skillId.value);
          case _Action.remove when reason == AttentionReason.removedWithDraft:
            final completion = await workspace.discardDraft(skillId).completed;
            switch (completion) {
              case WorkspaceFailed(:final failure):
                throw failure;
              case WorkspaceCommittedPending():
                finalization.register(completion);
                return null;
              case WorkspaceCompleted():
                return reconciler.removeMissingLocally(skillId.value);
            }
          case _Action.remove:
            return reconciler.removeMissingLocally(skillId.value);
          case _Action.keepDeviceOnly:
            return reconciler.keepDeviceOnly(skillId.value);
          case _Action.acceptReplacement:
            return reconciler.acceptReplacement(skillId.value);
          case _Action.replaceOccupied:
            final remote = await reconciler.api.readLineage(lineageId!);
            if (remote is ApiSignInRequired) {
              return SyncAccountCondition(remote);
            }
            if (remote is! CloudApiSuccess<Lineage> ||
                remote.value.state != LineageState.live ||
                remote.value.head == null ||
                (confirmedLineageVersion != null &&
                    remote.value.version != confirmedLineageVersion)) {
              throw const FormatException('cloud_confirmation_stale');
            }
            final links = await reconciler.state.links();
            final linked = links
                .where((link) => link.lineageId == lineageId)
                .firstOrNull;
            if (linked != null && linked.managedSkillId != skillId.value) {
              if (confirmedRevision == null) {
                throw const FormatException('cloud_confirmation_stale');
              }
              // Removing the occupant is a local action. Disconnect any Cloud
              // link first so periodic reconciliation cannot remove it remotely.
              final occupant = links
                  .where((link) => link.managedSkillId == skillId.value)
                  .firstOrNull;
              if (occupant != null) {
                await reconciler.keepDeviceOnly(skillId.value);
              }
              final removed = await workspace
                  .remove(
                    skillIds: {skillId},
                    expectedRevision: confirmedRevision,
                  )
                  .completed;
              switch (removed) {
                case WorkspaceFailed(:final failure):
                  if (occupant != null) {
                    if (occupant.lineageId case final id?) {
                      await reconciler.state.setExcluded(id, false);
                    }
                    await reconciler.state.put(occupant);
                  }
                  throw failure;
                case WorkspaceCommittedPending():
                  finalization.register(
                    removed,
                    afterRecovery: () async {
                      await runtime.reconcileSkill(linked.managedSkillId);
                      return true;
                    },
                  );
                  return null;
                case WorkspaceCompleted():
                  return reconciler.reconcileSkill(linked.managedSkillId);
              }
            }
            return reconciler.replaceOccupied(lineageId, skillId.value);
          case _Action.exclude:
            await reconciler.exclude(lineageId!);
            return const SkillDeviceOnly();
          case _Action.stop:
            return reconciler.stopSyncing(skillId.value);
          case _Action.uploadAsNew:
            return reconciler.uploadAsNewLineage(skillId.value);
        }
      });
      if (mounted &&
          outcome is SyncNeedsAttention &&
          outcome.reason == reason) {
        setState(() => _failed = true);
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _stillCurrent(
    CloudSyncRuntime runtime,
    WorkspaceSkillId skillId,
    (AttentionReason, String?) attention,
  ) =>
      mounted &&
      widget.skillId == skillId &&
      identical(ref.read(cloudSyncRuntimeProvider), runtime) &&
      ref.read(cloudSyncStateProvider).value?.accountId == runtime.accountId &&
      _attention(ref.read(cloudSyncStateProvider).value, skillId.value) ==
          attention;

  int? _observedVersion(WorkspaceSkillId skillId, String? lineageId) {
    final links = ref.read(cloudSyncStateProvider).value?.links;
    if (links == null) return null;
    final link = lineageId == null
        ? links[skillId.value]
        : links.values.where((link) => link.lineageId == lineageId).firstOrNull;
    return link?.attentionAttempt?.version ?? link?.version;
  }
}

(AttentionReason, String?)? _attention(
  CloudSyncState? snapshot,
  String skillId,
) {
  if (snapshot == null || snapshot.applying.contains(skillId)) return null;
  final current = snapshot.skill(skillId).attention;
  if (current != null && current.reason != AttentionReason.slotOccupied) {
    return (current.reason, null);
  }
  for (final entry in snapshot.outcomes.entries) {
    final lineageId = snapshot.links[entry.key]?.lineageId ?? entry.key;
    if (snapshot.exclusions.contains(lineageId)) continue;
    if (snapshot.links[skillId]?.lineageId == lineageId) continue;
    if (entry.value
        case SyncNeedsAttention(
          reason: AttentionReason.slotOccupied,
          occupant: final occupant?,
        )
        when occupant == skillId) {
      return (AttentionReason.slotOccupied, lineageId);
    }
  }
  return null;
}

String _label(AppLocalizations l10n, _Action action) => switch (action) {
  _Action.publishDraft => l10n.cloudPublishDraft,
  _Action.discardDraft => l10n.cloudDiscardDraft,
  _Action.reviewIncoming => l10n.cloudReviewIncoming,
  _Action.reviewConflict => l10n.cloudReviewConflict,
  _Action.remove => l10n.cloudRemoveHere,
  _Action.keepDeviceOnly => l10n.cloudKeepDeviceOnly,
  _Action.acceptReplacement => l10n.cloudAcceptReplacement,
  _Action.replaceOccupied => l10n.cloudReplaceLocalSkill,
  _Action.exclude => l10n.cloudKeepAndHide,
  _Action.stop => l10n.cloudStopSyncingAction,
  _Action.uploadAsNew => l10n.cloudUploadAsNew,
};

Future<void> _showIncomingDiff(
  BuildContext context,
  WorkspaceRevisionPackDiff diff,
) => AppDialogMotion.show<void>(
  context: context,
  builder: (context) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    return AppDialogScaffold(
      width: 620,
      onEscape: () => Navigator.pop(context),
      header: AppDialogHeader(
        title: l10n.cloudReviewIncoming,
        icon: LucideIcons.fileDiff,
      ),
      sections: [
        if (diff.files.isEmpty)
          AppDialogSection(child: Text(l10n.cloudIncomingNoFileChanges)),
        for (final file in diff.files)
          AppDialogSection(
            title: file.previousPath == null
                ? file.path
                : '${file.previousPath} → ${file.path}',
            child: file.isBinary
                ? Text(l10n.cloudIncomingBinaryFile)
                : AppSelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '+${file.additions}  −${file.deletions}',
                          style: AppTypography.of(context).mono,
                        ),
                        for (final hunk in file.hunks) ...[
                          Text(
                            hunk.header,
                            style: AppTypography.of(context).mono,
                          ),
                          for (final line in hunk.lines)
                            Text(
                              switch (line.kind) {
                                WorkspaceDiffLineKind.addition =>
                                  '+ ${line.text}',
                                WorkspaceDiffLineKind.deletion =>
                                  '− ${line.text}',
                                WorkspaceDiffLineKind.context =>
                                  '  ${line.text}',
                              },
                              style: AppTypography.of(context).mono.copyWith(
                                color: switch (line.kind) {
                                  WorkspaceDiffLineKind.addition =>
                                    palette.success,
                                  WorkspaceDiffLineKind.deletion =>
                                    palette.danger,
                                  WorkspaceDiffLineKind.context =>
                                    palette.textSecondary,
                                },
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
      ],
      footer: AppDialogFooter(
        actions: [
          AppButton(
            label: l10n.commonClose,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  },
);

Future<_ConflictAction?> _showConflictReview(
  BuildContext context,
  WorkspaceUpdateCandidateReview review, {
  required VoidCallback? openDraft,
}) => AppDialogMotion.show<_ConflictAction>(
  context: context,
  builder: (context) {
    final l10n = context.l10n;
    return AppDialogScaffold(
      width: 560,
      onEscape: () => Navigator.pop(context),
      header: AppDialogHeader(
        title: l10n.cloudReviewConflict,
        subtitle: review.hasUnresolvedConflicts
            ? l10n.cloudConflictChooseVersion
            : l10n.cloudConflictReviewDraft,
        icon: LucideIcons.gitMerge,
      ),
      sections: [
        for (final path in review.summary.conflictPaths)
          AppDialogSection(
            child: Text(path, style: AppTypography.of(context).mono),
          ),
      ],
      footer: AppDialogFooter(
        equalWidth: true,
        actions: [
          AppButton(
            label: l10n.commonCancel,
            onPressed: () => Navigator.pop(context),
          ),
          if (review.hasUnresolvedConflicts) ...[
            AppButton(
              label: l10n.cloudConflictKeepThis,
              onPressed: () => Navigator.pop(context, _ConflictAction.current),
            ),
            AppButton(
              label: l10n.cloudConflictKeepOther,
              onPressed: () => Navigator.pop(context, _ConflictAction.incoming),
            ),
          ] else ...[
            if (openDraft != null)
              AppButton(label: l10n.cloudRevealDraft, onPressed: openDraft),
            AppButton(
              label: l10n.cloudPublishResolved,
              style: NeoButtonVariant.primary,
              onPressed: () => Navigator.pop(context, _ConflictAction.publish),
            ),
          ],
        ],
      ),
    );
  },
);
