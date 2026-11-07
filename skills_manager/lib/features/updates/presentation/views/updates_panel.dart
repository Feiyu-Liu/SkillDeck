import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/l10n/workspace_operation_l10n.dart';
import 'package:skills_manager/shared/scrolling/app_scroll_controller.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_page_content.dart';
import 'package:skills_manager/shared/widgets/app_page_template.dart';
import 'package:skills_manager/shared/widgets/app_sidebar.dart';
import 'package:skills_manager/shared/widgets/app_operation_feedback.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/features/updates/presentation/view_models/updates_view_model.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';

class UpdatesPanel extends ConsumerStatefulWidget {
  const UpdatesPanel({super.key});

  @override
  ConsumerState<UpdatesPanel> createState() => _UpdatesPanelState();
}

class _UpdatesPanelState extends ConsumerState<UpdatesPanel> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = AppScrollControllers.create(debugLabel: 'updates');
    // Opening the page is not a request to refresh. This renders whatever the
    // shared store already holds and starts a sweep — or attaches to one
    // already running — only when no in-session result exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(updatesViewModelProvider.notifier).ensureChecked());
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(updatesViewModelProvider);
    final updates = ref.watch(skillUpdateStatusProvider);
    final viewModel = ref.read(updatesViewModelProvider.notifier);
    final workspace = ref.watch(workspaceSnapshotProvider).value;
    final skills = _orderedByUrgency(
      workspace?.skills ?? const <WorkspaceSkill>[],
      updates,
    );
    final canUpdateAny = skills.any(
      (skill) =>
          updates.stateOf(skill.id).updateAvailable &&
          !skill.integrity.mutationBlocked,
    );
    final busy = state.busy || updates.sweeping;
    final copy = _operationCopy(
      l10n,
      state,
      workspace?.skills ?? const <WorkspaceSkill>[],
      commandLineBusy: ref.watch(commandLineBusyProvider),
    );
    return AppPageTemplate(
      controller: _scrollController,
      scrollViewKey: const Key('updates-page-scroll'),
      blurKey: const Key('updates-top-blur'),
      headerKey: const Key('updates-header-column'),
      breadcrumbKey: const Key('updates-breadcrumb'),
      breadcrumb: l10n.updatesBreadcrumb,
      breadcrumbIcon: NavSection.updates.icon,
      title: l10n.updatesTitle,
      titleKey: const Key('updates-page-title'),
      commandTrailing: MyButtonGroup(
        spacing: AppSpacing.sm,
        children: [
          AppIconButton(
            key: const Key('updates-check'),
            icon: LucideIcons.refreshCw,
            tooltip: l10n.updatesCheckAgain,
            size: AppSizes.pageCommandBarHeight,
            iconSize: AppSizes.iconMd,
            onPressed: busy ? null : () => unawaited(viewModel.checkAgain()),
          ),
          AppIconButton(
            key: const Key('updates-update-all'),
            icon: LucideIcons.arrowDownToLine,
            tooltip: l10n.updatesUpdateAll,
            size: AppSizes.pageCommandBarHeight,
            iconSize: AppSizes.iconMd,
            style: NeoButtonVariant.primary,
            onPressed: busy || !canUpdateAny
                ? null
                : () => unawaited(viewModel.updateAll()),
          ),
        ],
      ),
      slivers: [
        // The package batch reports completed Skills over the requested total.
        if (updates.sweeping)
          AppPageSliverContent(
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppOperationFeedback(
                  key: const Key('updates-check-progress'),
                  label: l10n.updatesCheckProgress(
                    updates.sweepCompleted,
                    updates.sweepTotal,
                  ),
                  progress: updates.sweepFraction,
                  warnings: [
                    for (final warning in updates.warnings)
                      localizeWorkspaceWarning(l10n, warning),
                  ],
                  running: true,
                  cancelLabel: l10n.commonCancel,
                  onCancel: () => unawaited(viewModel.cancelChecking()),
                ),
              ),
            ),
          ),
        if (state.operation.running || state.operation.warnings.isNotEmpty)
          AppPageSliverContent(
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppOperationFeedback(
                  label: copy.label,
                  detail: copy.detail,
                  progress: state.operation.progress?.fraction,
                  warnings: [
                    for (final warning in state.operation.warnings)
                      localizeWorkspaceWarning(l10n, warning),
                  ],
                  running: state.operation.running,
                  cancelLabel: l10n.commonCancel,
                  onCancel: state.operation.running
                      ? () => unawaited(viewModel.cancelOperation())
                      : null,
                ),
              ),
            ),
          ),
        if (skills.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppPageContent(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.circleCheck,
                      size: 30,
                      color: AppPalette.of(context).controlInactive,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      l10n.updatesEmpty,
                      style: AppTypography.of(context).bodyMuted
                          .copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          AppPageSliverContent(
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index.isOdd) {
                  return SizedBox(
                    height: 1,
                    child: ColoredBox(color: AppPalette.of(context).border),
                  );
                }
                final skill = skills[index ~/ 2];
                return _UpdateRow(
                  updateState: updates.stateOf(skill.id),
                  slotKey: skill.slotKey,
                  busy: busy,
                  hasCandidate: skill.updateCandidate != null,
                  mutationBlocked: skill.integrity.mutationBlocked,
                  onCheck: () => unawaited(viewModel.checkOne(skill.id)),
                  onUpdate: () => unawaited(viewModel.updateOne(skill.id)),
                  onAbandonCandidate: () =>
                      unawaited(viewModel.abandonCandidate(skill.id)),
                );
              }, childCount: (skills.length * 2) - 1),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ],
    );
  }
}

/// Orders the page so the Skills that need a decision come first.
///
/// The Snapshot hands Skills back in Workspace order, which interleaves the few
/// actionable rows among the many that are already current. Ties resolve on Slot
/// Key so equal-urgency rows keep a stable order across re-checks.
typedef _OperationCopy = ({String label, String? detail});

/// Names a running update by the Skills it was started for. The package's
/// current item is an opaque identifier, so it is resolved to a Slot Key —
/// the name the rows below use — and never shown raw.
_OperationCopy _operationCopy(
  AppLocalizations l10n,
  UpdatesState state,
  List<WorkspaceSkill> skills, {
  required bool commandLineBusy,
}) {
  final progress = state.operation.progress;
  final targets = state.updatingSkillIds;
  if (progress == null) return (label: '', detail: null);
  if (!state.operation.running || targets.isEmpty) {
    return (
      label: localizeWorkspacePhase(
        l10n,
        progress.phase,
        commandLineBusy: commandLineBusy,
      ),
      detail: null,
    );
  }
  String? slotKeyOf(String? id) => id == null
      ? null
      : skills.where((skill) => skill.id.value == id).firstOrNull?.slotKey;
  // Updating starts by fetching the new revision from the Source; "inspecting"
  // reads as a re-check to someone who has just pressed Update.
  final phase = progress.phase == WorkspaceOperationPhase.inspecting
      ? l10n.updatesFetchingSource
      : localizeWorkspacePhase(
          l10n,
          progress.phase,
          commandLineBusy: commandLineBusy,
        );
  if (targets.length == 1) {
    final slotKey = slotKeyOf(targets.single.value);
    return (
      label: slotKey == null
          ? l10n.updatesUpdatingSkills(1)
          : l10n.updatesUpdatingSkill(slotKey),
      detail: phase,
    );
  }
  final current = slotKeyOf(progress.currentItem);
  return (
    label: l10n.updatesUpdatingSkills(targets.length),
    detail: current == null
        ? phase
        : l10n.updatesUpdatingDetail(current, phase),
  );
}

List<WorkspaceSkill> _orderedByUrgency(
  List<WorkspaceSkill> skills,
  SkillUpdateStatus updates,
) {
  final ordered = [...skills];
  ordered.sort((a, b) {
    final byUrgency = _urgencyRank(
      a,
      updates.stateOf(a.id),
    ).compareTo(_urgencyRank(b, updates.stateOf(b.id)));
    return byUrgency != 0 ? byUrgency : a.slotKey.compareTo(b.slotKey);
  });
  return ordered;
}

/// Ranks one row by how much it is waiting on the user, lowest first.
///
/// Integrity recovery outranks everything because it blocks mutation outright,
/// and the transient check states sink below settled ones so a sweep does not
/// park unresolved rows above the answers the user came for. A Source that
/// cannot be updated at all sinks to the very bottom: nothing the user does on
/// this page will ever change that row.
int _urgencyRank(WorkspaceSkill skill, SkillUpdateState state) {
  if (skill.integrity.mutationBlocked) return 0;
  return switch (state) {
    SkillUpdateChecked(:final report) => switch (report.status) {
      WorkspaceUpdateStatus.resolutionRequired => 1,
      WorkspaceUpdateStatus.updateAvailable => 2,
      WorkspaceUpdateStatus.sourceUnavailable => 4,
      WorkspaceUpdateStatus.current => 5,
      WorkspaceUpdateStatus.updateUnsupported => 8,
    },
    SkillUpdateCheckFailed() => 3,
    SkillUpdateChecking() => 6,
    SkillUpdateNotChecked() => 7,
  };
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({
    required this.updateState,
    required this.slotKey,
    required this.busy,
    required this.hasCandidate,
    required this.mutationBlocked,
    required this.onCheck,
    required this.onUpdate,
    required this.onAbandonCandidate,
  });

  final SkillUpdateState updateState;
  final String slotKey;
  final bool busy;
  final bool hasCandidate;
  final bool mutationBlocked;
  final VoidCallback onCheck;
  final VoidCallback onUpdate;
  final VoidCallback onAbandonCandidate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = updateState.report?.status;
    final (label, color, icon) = mutationBlocked
        ? (
            l10n.updatesIntegrityRecovery,
            AppPalette.of(context).danger,
            LucideIcons.triangleAlert,
          )
        : switch (updateState) {
            SkillUpdateNotChecked() => (
              l10n.updatesNotChecked,
              AppPalette.of(context).textSecondary,
              LucideIcons.circleDashed,
            ),
            SkillUpdateChecking() => (
              l10n.updatesChecking,
              AppPalette.of(context).textSecondary,
              LucideIcons.refreshCw,
            ),
            // A failed check stays distinct from a Source that was reached and
            // reported unavailable: the two mean different things to the user.
            SkillUpdateCheckFailed() => (
              l10n.updatesCheckFailed,
              AppPalette.of(context).warning,
              LucideIcons.circleAlert,
            ),
            SkillUpdateChecked() => switch (status!) {
              WorkspaceUpdateStatus.current => (
                l10n.updatesCurrent,
                AppPalette.of(context).success,
                LucideIcons.circleCheck,
              ),
              WorkspaceUpdateStatus.updateAvailable => (
                l10n.updatesAvailable,
                AppPalette.of(context).ink,
                LucideIcons.download,
              ),
              WorkspaceUpdateStatus.sourceUnavailable => (
                switch (updateState.report?.failureReason) {
                  WorkspaceUpdateCheckFailureReason.timedOut =>
                    l10n.updatesTimedOut,
                  WorkspaceUpdateCheckFailureReason.authenticationRequired =>
                    l10n.errorAuthenticationRequired,
                  WorkspaceUpdateCheckFailureReason.gitUnavailable =>
                    l10n.errorGitUnavailable,
                  WorkspaceUpdateCheckFailureReason.developerToolsRequired =>
                    l10n.errorDeveloperToolsRequired,
                  WorkspaceUpdateCheckFailureReason.gitFailed =>
                    l10n.errorGitFailed,
                  WorkspaceUpdateCheckFailureReason.ioFailure => l10n.errorIo,
                  WorkspaceUpdateCheckFailureReason.sourceUnavailable ||
                  null => l10n.updatesUnavailable,
                },
                AppPalette.of(context).warning,
                LucideIcons.cloudOff,
              ),
              WorkspaceUpdateStatus.updateUnsupported => (
                l10n.updatesUnsupported,
                AppPalette.of(context).textSecondary,
                LucideIcons.ban,
              ),
              WorkspaceUpdateStatus.resolutionRequired => (
                hasCandidate
                    ? l10n.updatesCandidateResolutionRequired
                    : l10n.updatesResolutionRequired,
                AppPalette.of(context).warning,
                LucideIcons.triangleAlert,
              ),
            },
          };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slotKey,
                  style: AppTypography.of(context).subtitle
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(label, style: AppTypography.of(context).bodyMuted),
              ],
            ),
          ),
          if (status == WorkspaceUpdateStatus.updateAvailable)
            AppButton(
              key: Key('updates-update-$slotKey'),
              label: l10n.updatesUpdate,
              icon: LucideIcons.download,
              size: NeoButtonSize.small,
              onPressed: busy || mutationBlocked ? null : onUpdate,
            )
          else if (status == WorkspaceUpdateStatus.resolutionRequired &&
              hasCandidate)
            AppButton(
              key: Key('updates-abandon-candidate-$slotKey'),
              label: l10n.updatesAbandonCandidate,
              icon: LucideIcons.undo2,
              size: NeoButtonSize.small,
              onPressed: busy || mutationBlocked ? null : onAbandonCandidate,
            )
          else if (updateState is SkillUpdateNotChecked ||
              updateState is SkillUpdateCheckFailed)
            AppButton(
              key: Key('updates-check-$slotKey'),
              label: l10n.updatesCheckOne,
              icon: LucideIcons.refreshCw,
              size: NeoButtonSize.small,
              onPressed: busy ? null : onCheck,
            ),
        ],
      ),
    );
  }
}
