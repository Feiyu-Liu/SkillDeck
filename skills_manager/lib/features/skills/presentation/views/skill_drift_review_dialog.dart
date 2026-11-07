import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_drift_review_view_model.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/l10n/workspace_operation_l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';
import 'package:skills_manager/shared/widgets/app_operation_feedback.dart';

/// Radio value of the restore option. Artifact identifiers never start with
/// `#`, so it cannot collide with a keep option.
const _restoreOption = '#restore';

class SkillDriftReviewDialog extends ConsumerStatefulWidget {
  const SkillDriftReviewDialog({required this.skillId, super.key});

  final WorkspaceSkillId skillId;

  @override
  ConsumerState<SkillDriftReviewDialog> createState() =>
      _SkillDriftReviewDialogState();
}

class _SkillDriftReviewDialogState
    extends ConsumerState<SkillDriftReviewDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(skillDriftReviewViewModelProvider(widget.skillId).notifier)
            .load(),
      );
    });
  }

  Future<void> _resolve(Future<bool> Function() action) async {
    final succeeded = await action();
    if (mounted && succeeded) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = skillDriftReviewViewModelProvider(widget.skillId);
    final state = ref.watch(provider);
    final viewModel = ref.read(provider.notifier);
    return PopScope(
      canPop: !state.isBusy,
      child: AppDialogScaffold(
        key: const Key('skill-drift-review-dialog'),
        width: AppDialogWidths.wide,
        onEscape: state.isBusy ? null : context.pop,
        header: _Header(busy: state.isBusy, onClose: context.pop),
        sections: [_Review(state: state, viewModel: viewModel)],
        footer: _Footer(
          state: state,
          onCancel: context.pop,
          onKeep: () => unawaited(_resolve(viewModel.keepExternal)),
          onRestore: () => unawaited(_resolve(viewModel.restoreManaged)),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.busy, required this.onClose});
  final bool busy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => AppDialogHeader(
    icon: LucideIcons.triangleAlert,
    tone: AppDialogTone.warning,
    title: context.l10n.skillDriftDialogTitle,
    subtitle: context.l10n.skillDriftReviewDescription,
    actions: [
      appDialogCloseButton(
        context,
        key: const Key('skill-drift-close'),
        onPressed: busy ? null : onClose,
      ),
    ],
  );
}

class _Review extends ConsumerWidget {
  const _Review({required this.state, required this.viewModel});
  final SkillDriftReviewState state;
  final SkillDriftReviewViewModel viewModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final review = state.review;
    final agents = ref.watch(deviceAgentCatalogProvider).value ?? const [];
    String locationName(WorkspaceDriftedArtifact artifact) {
      if (artifact.locationKind == WorkspaceDriftLocationKind.repositoryCopy) {
        return l10n.skillDriftLocationRepositoryCopy;
      }
      final names = artifact.agentIds
          .map(
            (id) => id == universalAgentId
                ? l10n.activationUniversalAgents
                : agents
                          .where((agent) => agent.id == id)
                          .firstOrNull
                          ?.displayName ??
                      l10n.activationUnknownAgent,
          )
          .toSet();
      return names.isEmpty
          ? l10n.skillDriftLocationAgentFolder
          : names.join(', ');
    }

    final artifacts = review?.artifacts ?? const <WorkspaceDriftedArtifact>[];
    final keepable = artifacts.where((artifact) => artifact.canKeepExternal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.status == SkillDriftReviewStatus.loading)
          const AppDialogSection(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CupertinoActivityIndicator(),
            ),
          ),
        if (state.status == SkillDriftReviewStatus.stale)
          AppDialogSection(
            child: Container(
              key: const Key('skill-drift-stale'),
              padding: const EdgeInsets.all(14),
              decoration: AppCorners.smooth(
                color: AppPalette.of(context).surfaceSubtle,
                radius: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.skillDriftStale,
                    style: AppTypography.of(context).body,
                  ),
                  const SizedBox(height: 10),
                  AppButton(
                    key: const Key('skill-drift-reload'),
                    label: l10n.skillDriftRefreshReview,
                    icon: LucideIcons.refreshCw,
                    onPressed: () => unawaited(viewModel.load(refresh: true)),
                  ),
                ],
              ),
            ),
          )
        else if (state.failure case final failure?) ...[
          AppDialogSection(
            child: AppFailureView(
              key: const Key('skill-drift-failure'),
              variant: AppFailureViewVariant.banner,
              failure: failure,
              onAction: review == null
                  ? () => unawaited(viewModel.load())
                  : null,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (review != null) ...[
          AppDialogSection(
            title: l10n.skillDriftWhatChanged,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (artifacts.isEmpty && review.missingArtifactCount == 0)
                  Text(
                    l10n.skillDriftNoChanges,
                    style: AppTypography.of(context).body,
                  ),
                for (final (index, artifact) in artifacts.indexed)
                  _ChangeRow(
                    artifact: artifact,
                    locationName: locationName(artifact),
                    divided: index > 0,
                    enabled: state.canReviewActions,
                    exportedPath: state.exportedPaths[artifact.artifactId],
                    onExport: () =>
                        unawaited(viewModel.export(artifact.artifactId)),
                  ),
                if (review.missingArtifactCount > 0)
                  Text(
                    l10n.skillDriftMissingArtifacts(
                      review.missingArtifactCount,
                    ),
                    style: AppTypography.of(context).caption,
                  ),
              ],
            ),
          ),
          if (artifacts.isNotEmpty)
            AppDialogSection(
              title: l10n.skillDriftHowToResolve,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RadioGroup<String>(
                    groupValue:
                        state.selectedArtifactId ??
                        (state.restoreSelected ? _restoreOption : null),
                    onChanged: (value) {
                      if (value == null) return;
                      if (value == _restoreOption) {
                        viewModel.selectRestore();
                      } else {
                        viewModel.select(value);
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final artifact in keepable)
                          _OptionCard(
                            key: Key(
                              'skill-drift-select-${artifact.artifactId}',
                            ),
                            value: artifact.artifactId,
                            selected:
                                state.selectedArtifactId == artifact.artifactId,
                            enabled: state.canReviewActions,
                            onSelected: () =>
                                viewModel.select(artifact.artifactId),
                            title: l10n.skillDriftKeepOption(
                              locationName(artifact),
                            ),
                            subtitle: artifact.targetPath,
                            monospaceSubtitle: true,
                            detail: Text(
                              l10n.skillDriftKeepOptionDetail,
                              style: AppTypography.of(context).caption.copyWith(
                                color: AppPalette.of(context).bodyContent,
                              ),
                            ),
                          ),
                        _OptionCard(
                          key: const Key('skill-drift-select-restore'),
                          value: _restoreOption,
                          selected: state.restoreSelected,
                          enabled: state.canReviewActions,
                          onSelected: viewModel.selectRestore,
                          title: l10n.skillDriftRestoreManaged,
                          subtitle: l10n.skillDriftRestoreOptionDetail,
                          detail: _RestoreWarning(
                            message: l10n.skillDriftRestoreWarning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (keepable.isEmpty)
                    Text(
                      l10n.skillDriftKeepUnavailable,
                      key: const Key('skill-drift-keep-unavailable'),
                      style: AppTypography.of(context).caption,
                    ),
                ],
              ),
            ),
        ],
        if (state.operation.running || state.operation.warnings.isNotEmpty) ...[
          const SizedBox(height: 14),
          AppDialogSection(
            child: AppOperationFeedback(
              label: localizeWorkspacePhase(
                l10n,
                commandLineBusy: ref.watch(commandLineBusyProvider),
                state.operation.progress?.phase ??
                    WorkspaceOperationPhase.preparing,
              ),
              cancelLabel: l10n.commonCancel,
              progress: state.operation.progress?.fraction,
              running: state.operation.running,
              onCancel: state.operation.running
                  ? () => unawaited(viewModel.cancelOperation())
                  : null,
              warnings: state.operation.warnings
                  .map((warning) => localizeWorkspaceWarning(l10n, warning))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

/// One drifted location: where it is, what happened there, and a way to save
/// its current bytes before anything overwrites them.
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.artifact,
    required this.locationName,
    required this.divided,
    required this.enabled,
    required this.exportedPath,
    required this.onExport,
  });
  final WorkspaceDriftedArtifact artifact;
  final String locationName;
  final bool divided;
  final bool enabled;
  final String? exportedPath;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final icon = switch (artifact.locationKind) {
      WorkspaceDriftLocationKind.repositoryCopy => LucideIcons.archive,
      WorkspaceDriftLocationKind.copyActivation => LucideIcons.folder,
      WorkspaceDriftLocationKind.symbolicLinkActivation => LucideIcons.link,
    };
    final change = switch (artifact.driftKind) {
      WorkspaceDriftKind.contentChanged => l10n.skillDriftContentChanged,
      WorkspaceDriftKind.wrongLinkTarget => l10n.skillDriftWrongLinkTarget,
      WorkspaceDriftKind.wrongEntryType =>
        artifact.locationKind ==
                WorkspaceDriftLocationKind.symbolicLinkActivation
            ? l10n.skillDriftLinkReplaced
            : l10n.skillDriftFolderReplaced,
    };
    return Container(
      key: Key('skill-drift-artifact-${artifact.artifactId}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: divided
          ? BoxDecoration(
              border: Border(
                top: BorderSide(color: AppPalette.of(context).border),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 16,
              color: AppPalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locationName,
                  style: AppTypography.of(context).body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppPalette.of(context).textPrimary,
                  ),
                ),
                if (artifact.locationKind !=
                        WorkspaceDriftLocationKind.repositoryCopy &&
                    artifact.targetPath != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    artifact.targetPath!,
                    style: AppTypography.of(context).mono.copyWith(
                      fontSize: 11.5,
                      color: AppPalette.of(context).textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  change,
                  style: AppTypography.of(context).caption
                      .copyWith(color: AppPalette.of(context).warningStrong),
                ),
                if (exportedPath case final path?) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          LucideIcons.circleCheck,
                          size: 13,
                          color: AppPalette.of(context).success,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          l10n.skillDriftExported(path),
                          key: Key(
                            'skill-drift-exported-${artifact.artifactId}',
                          ),
                          style: AppTypography.of(context).caption
                              .copyWith(color: AppPalette.of(context).success),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (artifact.canExport) ...[
            const SizedBox(width: 12),
            AppButton(
              key: Key('skill-drift-export-${artifact.artifactId}'),
              label: l10n.skillDriftExportAction,
              icon: LucideIcons.folderOutput,
              size: NeoButtonSize.small,
              onPressed: enabled ? onExport : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// A selectable resolution. The whole card is the hit target, and its
/// consequences are spelled out only once it is chosen.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.title,
    this.subtitle,
    this.monospaceSubtitle = false,
    this.detail,
    super.key,
  });
  final String value;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;
  final String title;
  final String? subtitle;
  final bool monospaceSubtitle;
  final Widget? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onSelected : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),

          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoRadio<String>(value: value, enabled: enabled),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.of(context).body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppPalette.of(context).textPrimary,
                      ),
                    ),
                    if (subtitle case final text?) ...[
                      const SizedBox(height: 2),
                      Text(
                        text,
                        style: monospaceSubtitle
                            ? AppTypography.of(context).mono.copyWith(
                                fontSize: 11.5,
                                color: AppPalette.of(context).textSecondary,
                              )
                            : AppTypography.of(context).caption,
                      ),
                    ],
                    if (selected && detail != null) ...[
                      const SizedBox(height: 8),
                      detail!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RestoreWarning extends StatelessWidget {
  const _RestoreWarning({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('skill-drift-restore-warning'),
    child: AppDialogNote(tone: AppDialogTone.warning, text: message),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.state,
    required this.onCancel,
    required this.onKeep,
    required this.onRestore,
  });
  final SkillDriftReviewState state;
  final VoidCallback onCancel;
  final VoidCallback onKeep;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final review = state.review;
    final hasDrift = review?.artifacts.isNotEmpty ?? false;
    final settled = review != null && !hasDrift;
    final nothingToRestore = settled && review.missingArtifactCount == 0;
    // One confirm button whose meaning follows the chosen option. Its key
    // names that meaning, so it is never both actions at once.
    final Widget confirm;
    if (settled) {
      confirm = AppButton(
        key: const Key('skill-drift-restore'),
        label: nothingToRestore
            ? l10n.commonDone
            : l10n.skillDriftRestoreMissing,
        style: NeoButtonVariant.primary,
        onPressed: state.canRestoreManaged ? onRestore : null,
      );
    } else if (state.restoreSelected) {
      confirm = AppButton(
        key: const Key('skill-drift-restore'),
        label: l10n.skillDriftRestoreManaged,
        style: NeoButtonVariant.danger,
        onPressed: state.canRestoreManaged ? onRestore : null,
      );
    } else if (state.selectedArtifactId != null) {
      confirm = AppButton(
        key: const Key('skill-drift-keep'),
        label: l10n.skillDriftKeepExternal,
        style: NeoButtonVariant.primary,
        onPressed: state.canKeepExternal ? onKeep : null,
      );
    } else {
      confirm = AppButton(
        key: const Key('skill-drift-confirm'),
        label: l10n.skillDriftChooseOption,
        style: NeoButtonVariant.primary,
        onPressed: null,
      );
    }
    return AppDialogFooter(
      actions: [
        Flexible(
          flex: 100,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 8,
            children: [
              if (!nothingToRestore)
                AppButton(
                  key: const Key('skill-drift-cancel'),
                  label: l10n.commonCancel,
                  onPressed: state.isBusy ? null : onCancel,
                ),
              confirm,
            ],
          ),
        ),
      ],
    );
  }
}
