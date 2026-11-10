import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/project_roots_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/l10n/workspace_operation_l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_operation_feedback.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';

class ProjectRootsDialog extends ConsumerWidget {
  const ProjectRootsDialog({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    if (ref.read(projectRootsViewModelProvider).busy) return;
    final path = await ref.read(directoryPickerProvider).pickDirectory();
    if (path == null || !context.mounted) return;
    await ref.read(projectRootsViewModelProvider.notifier).register(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roots = ref
        .watch(workspaceProjectRootsProvider)
        .when(
          data: (value) => value,
          error: (_, _) => const <SkillProjectRoot>[],
          loading: () => const <SkillProjectRoot>[],
        );
    final viewModel = ref.watch(projectRootsViewModelProvider);
    final operation = viewModel.operation;
    return AppDialogScaffold(
      key: const Key('project-roots-dialog'),
      width: AppDialogWidths.standard,
      onEscape: viewModel.busy ? null : context.pop,
      header: AppDialogHeader(
        icon: LucideIcons.folderGit2,
        title: context.l10n.projectRootsTitle,
        subtitle: context.l10n.projectRootsDescription,
        actions: [
          appDialogCloseButton(
            context,
            key: const Key('project-roots-close'),
            onPressed: viewModel.busy ? null : context.pop,
          ),
        ],
      ),
      sections: [
        AppDialogSection(
          title: context.l10n.projectRootsRegisteredTitle,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: AppCorners.smooth(
              color: AppPalette.of(context).surfaceMuted,
              radius: 5,
            ),
            child: Text(
              '${roots.length}',
              style: AppTypography.of(context).caption,
            ),
          ),
          child: roots.isEmpty
              ? Text(
                  context.l10n.projectRootsEmpty,
                  style: AppTypography.of(context).bodyMuted,
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: roots.length,
                  separatorBuilder: (_, _) => SizedBox(
                    height: 1,
                    child: ColoredBox(color: AppPalette.of(context).border),
                  ),
                  itemBuilder: (context, index) {
                    final root = roots[index];
                    return Padding(
                      key: Key('project-root-${root.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.folderGit2,
                            size: 17,
                            color: AppPalette.of(context).textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              root.path,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.of(context).mono,
                            ),
                          ),
                          AppIconButton(
                            key: Key('project-root-remove-${root.id}'),
                            icon: LucideIcons.trash2,
                            tooltip: context.l10n.projectRootsRemove,
                            foregroundColor: AppPalette.of(context).danger,
                            style: NeoButtonVariant.ghost,
                            onPressed: viewModel.busy
                                ? null
                                : () => unawaited(
                                    ref
                                        .read(
                                          projectRootsViewModelProvider
                                              .notifier,
                                        )
                                        .unregister(root.id),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (viewModel.failure case final failure?)
          AppDialogSection(
            child: AppFailureView(
              key: const Key('project-roots-error'),
              failure: failure,
              variant: AppFailureViewVariant.banner,
            ),
          ),
        if (operation.running || operation.warnings.isNotEmpty)
          AppDialogSection(
            child: AppOperationFeedback(
              label: operation.progress == null
                  ? context.l10n.projectRootsError
                  : localizeWorkspacePhase(
                      context.l10n,
                      operation.progress!.phase,
                      commandLineBusy: ref.watch(commandLineBusyProvider),
                    ),
              detail: operation.progress?.currentItem,
              progress: operation.progress?.fraction,
              warnings: [
                for (final warning in operation.warnings)
                  localizeWorkspaceWarning(context.l10n, warning),
              ],
              running: operation.running,
              cancelLabel: context.l10n.commonCancel,
              onCancel: operation.running
                  ? () => unawaited(
                      ref
                          .read(projectRootsViewModelProvider.notifier)
                          .cancelOperation(),
                    )
                  : null,
            ),
          ),
      ],
      footer: AppDialogFooter(
        leading: Text(
          context.l10n.projectRootsCount(roots.length),
          style: AppTypography.of(context).caption,
        ),
        actions: [
          AppButton(
            key: const Key('project-root-add'),
            label: context.l10n.projectRootsAdd,
            icon: LucideIcons.folderPlus,
            style: NeoButtonVariant.primary,
            onPressed: viewModel.busy
                ? null
                : () => unawaited(_add(context, ref)),
          ),
        ],
      ),
    );
  }
}
