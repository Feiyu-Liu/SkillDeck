import 'dart:async';

import 'package:skills_manager/features/skills/presentation/widgets/skill_source_link.dart';

import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/library/presentation/widgets/skill_tag_editor.dart';
import 'package:skills_manager/features/skills/presentation/widgets/skill_scope_menu.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/settings/presentation/views/agent_management_dialog.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_location_label.dart';

import 'dart:ui';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/l10n/workspace_operation_l10n.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/navigation/app_routes.dart';
import 'package:skills_manager/shared/scrolling/app_scroll_controller.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_frame.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_header.dart';
import 'package:skills_manager/shared/widgets/app_page_content.dart';
import 'package:skills_manager/shared/widgets/app_selection_area.dart';
import 'package:skills_manager/shared/widgets/app_sidebar.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';
import 'package:skills_manager/shared/widgets/app_operation_feedback.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_takeover_dialog.dart';
import 'package:skills_manager/features/skills/presentation/widgets/skill_document_browser_popover.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_manager/features/translation/presentation/view_models/skill_translation_view_model.dart';
import 'package:skills_manager/features/translation/presentation/view_models/translation_scope_preference.dart';
import 'package:skills_translation/skills_translation.dart';
import 'package:skills_manager/features/library/skill_library_providers.dart';

class SkillWorkspacePanel extends ConsumerStatefulWidget {
  const SkillWorkspacePanel({
    required this.skillId,
    this.openSettings = false,
    super.key,
  });

  final WorkspaceSkillId skillId;
  final bool openSettings;

  @override
  ConsumerState<SkillWorkspacePanel> createState() =>
      _SkillWorkspacePanelState();
}

class _SkillWorkspacePanelState extends ConsumerState<SkillWorkspacePanel> {
  String? _scheduledSelection;
  late ScrollController _previewScrollController;
  late ScrollController _settingsScrollController;
  WorkspaceSkillId? _validationStartedFor;

  @override
  void initState() {
    super.initState();
    _previewScrollController = AppScrollControllers.create(
      debugLabel: 'skill-preview',
    );
    _settingsScrollController = AppScrollControllers.create(
      debugLabel: 'skill-settings',
    );
    _validationStartedFor = null;
    if (widget.openSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(workspaceUiProvider.notifier)
              .selectTab(widget.skillId, WorkspaceTab.settings);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SkillWorkspacePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openSettings &&
        (!oldWidget.openSettings || widget.skillId != oldWidget.skillId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(workspaceUiProvider.notifier)
              .selectTab(widget.skillId, WorkspaceTab.settings);
        }
      });
    }
    if (widget.skillId == oldWidget.skillId) return;
    _previewScrollController.dispose();
    _settingsScrollController.dispose();
    _previewScrollController = AppScrollControllers.create(
      debugLabel: 'skill-preview',
    );
    _settingsScrollController = AppScrollControllers.create(
      debugLabel: 'skill-settings',
    );
    _validationStartedFor = null;
  }

  @override
  void dispose() {
    _previewScrollController.dispose();
    _settingsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(skillBrowserCatalogProvider);
    final browserState = ref.watch(skillBrowserViewModelProvider);
    final viewModel = ref.read(skillBrowserViewModelProvider.notifier);
    final skill = _skillForId(catalog.skills, widget.skillId);
    if (catalog.status != CatalogStatus.ready) {
      return Center(
        child: CupertinoActivityIndicator(color: AppPalette.of(context).ink),
      );
    }
    if (skill == null) return const _MissingSkillState();
    final selectionReady = browserState.selectedSkill?.id == skill.id;
    if (!selectionReady) {
      if (_scheduledSelection != skill.id.value) {
        _scheduledSelection = skill.id.value;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scheduledSelection = null;
          if (mounted) {
            unawaited(
              ref
                  .read(skillBrowserViewModelProvider.notifier)
                  .selectSkill(skill.id),
            );
          }
        });
      }
    }
    final workspaceUi = ref.watch(workspaceUiProvider).forSkill(skill.id);
    final operations = ref.watch(skillOperationsViewModelProvider);
    final operationsViewModel = ref.read(
      skillOperationsViewModelProvider.notifier,
    );
    final workspaceSkill = ref
        .watch(workspaceSkillByIdProvider(skill.id))
        .value;
    final mutationsBlocked = workspaceSkill?.integrity.mutationBlocked ?? false;
    if (selectionReady &&
        workspaceSkill?.integrity == WorkspaceSkillIntegrityStatus.unverified &&
        _validationStartedFor != skill.id) {
      _validationStartedFor = skill.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_validateInBackground(skill.id));
      });
    }
    final sourceDocument = selectionReady
        ? _sourceDocumentFor(browserState)
        : null;
    final translation = ref.watch(skillTranslationViewModelProvider);
    final visibleTranslation =
        sourceDocument != null && translation.request == sourceDocument
        ? translation
        : null;
    // The action button needs the full translation state; the rendered
    // document must fall back to the original while the reader is in
    // show-original mode, which keeps the cached translation untouched.
    final contentTranslation = (visibleTranslation?.showOriginal ?? false)
        ? null
        : visibleTranslation;
    final contentReady =
        sourceDocument != null &&
        translation.isCacheResolvedFor(sourceDocument);
    final translationViewModel = ref.read(
      skillTranslationViewModelProvider.notifier,
    );

    final activeScrollController = workspaceUi.tab == WorkspaceTab.preview
        ? _previewScrollController
        : _settingsScrollController;
    final detailActions = _DetailActions(
      operations: operations,
      // The shared store is the sole source of update state. Entering a detail
      // page renders the last known result and never starts a check.
      updateState: ref.watch(skillUpdateStatusProvider).stateOf(skill.id),
      mutationsBlocked: mutationsBlocked,
      driftPending:
          workspaceSkill?.integrity ==
          WorkspaceSkillIntegrityStatus.driftPending,
      onReviewDrift: () => unawaited(
        context.pushNamed(
          AppRouteNames.reviewSkillDrift,
          pathParameters: {'skillId': skill.id.value},
        ),
      ),
      onCheckUpdate: () => unawaited(operationsViewModel.checkUpdate(skill.id)),
      onUpdate: () => unawaited(operationsViewModel.update(skill.id)),
      onRemove: () => context.pushNamed(
        AppRouteNames.removeSkill,
        pathParameters: {'skillId': skill.id.value},
      ),
      onReplaceSource: () => context.pushNamed(
        AppRouteNames.replaceSource,
        pathParameters: {'skillId': skill.id.value},
      ),
      translation: visibleTranslation,
      onCancelTranslation: () => unawaited(translationViewModel.cancel()),
      // A settled translation on screen toggles straight back to the original
      // in one press. The card is only for work that uploads content.
      onShowOriginal: translationViewModel.showOriginalContent,
      onTranslate: (scope) => unawaited(translationViewModel.translate(scope)),
      onShowCachedTranslation: translationViewModel.showCachedTranslation,
      onDeleteTranslationCache: () =>
          unawaited(translationViewModel.deleteCachedTranslation()),
      favorite: skill.isFavorite,
      onToggleFavorite: () => unawaited(
        ref
            .read(skillLibraryCommandsProvider.notifier)
            .toggleFavorite(skillId: skill.id, isFavorite: skill.isFavorite),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return AppCollapsingPageFrame(
          key: const Key('skill-detail'),
          controller: activeScrollController,
          breadcrumb: context.l10n.workspaceBreadcrumb,
          breadcrumbIcon: NavSection.installed.icon,
          title: skill.displayName,
          titleAccessory: _SkillIntegrityLabel(
            status: workspaceSkill?.integrity,
          ),
          headerKey: const Key('skill-detail-header-column'),
          breadcrumbKey: const Key('skill-detail-breadcrumb'),
          titleKey: const Key('skill-detail-title'),
          titleSelectable: true,
          blurKey: const Key('skill-detail-top-blur'),
          commandLeading: AppIconButton(
            key: const Key('skill-detail-back'),
            icon: LucideIcons.arrowLeft,
            tooltip: context.l10n.workspaceBackToSkills,
            size: AppSizes.pageCommandBarHeight,
            iconSize: AppSizes.iconMd,
            foregroundColor: AppPalette.of(context).textPrimary,
            onPressed: context.pop,
          ),
          titleActions: detailActions,
          bottomOverlay: _SectionTabs(
            selected: workspaceUi.tab,
            onSelected: (tab) =>
                ref.read(workspaceUiProvider.notifier).selectTab(skill.id, tab),
          ),
          child: IndexedStack(
            index: workspaceUi.tab.index,
            children: [
              _WorkspaceScrollView(
                key: const Key('skill-preview-scroll'),
                controller: _previewScrollController,
                headerHeight: AppCollapsingHeaderMetrics.expandedHeight,
                child: _PreviewBody(
                  description:
                      contentTranslation?.request?.documentIdentifier ==
                          'SKILL.md'
                      ? contentTranslation?.translatedDescription ??
                            skill.description
                      : skill.description,
                  documents: selectionReady ? browserState.documents : const [],
                  documentCatalogStatus: selectionReady
                      ? browserState.documentCatalogStatus
                      : DocumentCatalogStatus.loading,
                  documentCatalogFailure: selectionReady
                      ? browserState.documentCatalogFailure
                      : null,
                  selectedDocumentPath: selectionReady
                      ? browserState.selectedDocumentPath ?? 'SKILL.md'
                      : 'SKILL.md',
                  documentStatus: selectionReady
                      ? browserState.documentStatus
                      : DocumentStatus.loading,
                  documentFailure: selectionReady
                      ? browserState.documentFailure
                      : null,
                  onRetryDocumentCatalog: viewModel.retryDocumentCatalog,
                  onSelectDocument: viewModel.selectDocument,
                  onRetryDocument: viewModel.retryDocument,
                  active: workspaceUi.tab == WorkspaceTab.preview,
                  sourceDocument: sourceDocument,
                  translation: contentTranslation,
                  contentReady: contentReady,
                  skillId: skill.id,
                  mutationsBlocked: mutationsBlocked,
                ),
              ),
              _WorkspaceScrollView(
                key: const Key('skill-settings-scroll'),
                controller: _settingsScrollController,
                headerHeight: AppCollapsingHeaderMetrics.expandedHeight,
                child: _ActivationsBody(
                  skill: skill,
                  isLocationBusy: (location) =>
                      operations.isActivationBusy(skill.id, location),
                  mutationsBlocked: mutationsBlocked,
                  onToggle: (group, value) => _setActivation(
                    operationsViewModel: operationsViewModel,
                    skill: skill,
                    group: group,
                    active: value,
                  ),
                  onToggleAll: (groups, value) => _setActivationAll(
                    operationsViewModel: operationsViewModel,
                    skill: skill,
                    groups: groups,
                    active: value,
                  ),
                  note: skill.note ?? '',
                  onSaveNote: (note) => unawaited(
                    ref
                        .read(skillLibraryCommandsProvider.notifier)
                        .saveNote(skillId: skill.id, note: note),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _validateInBackground(WorkspaceSkillId skillId) async {
    try {
      await ref
          .read(skillsWorkspaceRepositoryProvider)
          .validateWorkspace(skillIds: {skillId})
          .completed;
    } on Object {
      // The coordinator publishes the per-Skill failure state. A background
      // advisory check must never replace usable detail content with a toast.
    }
  }

  Future<void> _setActivation({
    required SkillOperationsViewModel operationsViewModel,
    required InstalledSkill skill,
    required ActivationLocationGroup group,
    required bool active,
  }) async {
    final target = group.first;
    await operationsViewModel.setActivation(
      skillId: skill.id,
      target: target,
      agentIds: group.requestAgentIds,
      active: active,
      onTakeoverRequired: (draft) => showActivationTakeoverDialog(
        context: context,
        draft: draft,
        agentName: activationAgentGroupTitle(context, group),
      ),
    );
  }

  // A single batched activate/deactivate call so every switch in the group
  // flips together, rather than looping one row at a time behind the
  // ViewModel's single-flight `operation.running` guard.
  Future<void> _setActivationAll({
    required SkillOperationsViewModel operationsViewModel,
    required InstalledSkill skill,
    required List<ActivationLocationGroup> groups,
    required bool active,
  }) async {
    if (groups.isEmpty) return;
    final target = groups.first.first;
    final agentIds = {for (final group in groups) ...group.requestAgentIds};
    final locations = {for (final group in groups) group.first.location};
    await operationsViewModel.setActivation(
      skillId: skill.id,
      target: target,
      agentIds: agentIds,
      locations: locations,
      active: active,
      onTakeoverRequired: (draft) {
        // Name only the Agents the draft actually contends for; listing the
        // whole batch would accuse Agents whose locations are vacant.
        final contended = draft.targets
            .map((target) => target.location)
            .toSet();
        final named = groups
            .where((group) => contended.contains(group.first.location))
            .map((group) => activationAgentGroupTitle(context, group));
        return showActivationTakeoverDialog(
          context: context,
          draft: draft,
          agentName:
              (named.isEmpty
                      ? groups.map(
                          (group) => activationAgentGroupTitle(context, group),
                        )
                      : named)
                  .join(', '),
        );
      },
    );
  }

  InstalledSkill? _skillForId(
    List<InstalledSkill> skills,
    WorkspaceSkillId skillId,
  ) {
    for (final skill in skills) {
      if (skill.id == skillId) return skill;
    }
    return null;
  }
}

SourceDocument? _sourceDocumentFor(SkillBrowserState browser) {
  final skill = browser.selectedSkill;
  final document = browser.document;
  final path = browser.selectedDocumentPath;
  final contentHash = browser.documentContentHash;
  if (skill == null ||
      document == null ||
      path == null ||
      contentHash == null) {
    return null;
  }
  return SourceDocument(
    slotKey: skill.slotKey,
    contentHash: contentHash,
    documentIdentifier: path,
    content: document,
  );
}

class _WorkspaceScrollView extends StatelessWidget {
  const _WorkspaceScrollView({
    required this.controller,
    required this.headerHeight,
    required this.child,
    super.key,
  });

  final ScrollController controller;
  final double headerHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
        SliverToBoxAdapter(child: AppPageContent(child: child)),
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.skill});

  final InstalledSkill skill;

  @override
  Widget build(BuildContext context) {
    final version = skill.contentHash.length >= 8
        ? skill.contentHash.substring(0, 8)
        : skill.contentHash;

    return _MetaBar(version: version, source: skill.source);
  }
}

class _SkillIntegrityLabel extends StatelessWidget {
  const _SkillIntegrityLabel({required this.status});

  final WorkspaceSkillIntegrityStatus? status;

  @override
  Widget build(BuildContext context) {
    // A pending drift is announced by the review action in the command row,
    // which names the state and opens its resolution in one control.
    final text = switch (status) {
      WorkspaceSkillIntegrityStatus.validating =>
        context.l10n.workspaceIntegrityValidating,
      WorkspaceSkillIntegrityStatus.repairFailed =>
        context.l10n.workspaceIntegrityRepairFailed,
      WorkspaceSkillIntegrityStatus.revisionStoreCorrupt =>
        context.l10n.workspaceIntegrityStoreCorrupt,
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    final blocked = status?.mutationBlocked ?? false;
    final color = blocked
        ? AppPalette.of(context).danger
        : AppPalette.of(context).textSecondary;
    final label = Text(
      text,
      key: const Key('skill-integrity-label'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.of(context).sectionLabel.copyWith(color: color),
    );
    if (!blocked) return label;
    return AppTooltip(
      message: context.l10n.workspaceIntegrityRecoveryMessage,
      child: label,
    );
  }
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.operations,
    required this.updateState,
    required this.mutationsBlocked,
    required this.driftPending,
    required this.onReviewDrift,
    required this.onCheckUpdate,
    required this.onUpdate,
    required this.onRemove,
    required this.onReplaceSource,
    required this.translation,
    required this.onCancelTranslation,
    required this.onShowOriginal,
    required this.onTranslate,
    required this.onShowCachedTranslation,
    required this.onDeleteTranslationCache,
    required this.favorite,
    required this.onToggleFavorite,
  });

  final SkillOperationsState operations;
  final SkillUpdateState updateState;
  final bool mutationsBlocked;
  final bool driftPending;
  final VoidCallback onReviewDrift;
  final VoidCallback onCheckUpdate;
  final VoidCallback onUpdate;
  final VoidCallback onRemove;
  final VoidCallback onReplaceSource;
  final SkillTranslationState? translation;
  final VoidCallback onCancelTranslation;
  final VoidCallback onShowOriginal;
  final void Function(TranslationScope) onTranslate;
  final void Function(TranslationScope) onShowCachedTranslation;
  final VoidCallback onDeleteTranslationCache;
  final bool favorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return MyButtonGroup(
      spacing: AppSpacing.sm,
      children: [
        if (driftPending)
          Flexible(
            child: _DriftReviewButton(
              label: l10n.skillDriftReviewAction,
              tooltip: l10n.skillDriftReviewTooltip,
              onPressed: onReviewDrift,
            ),
          ),
        // With a known available update the action widens into a labelled
        // pill that applies the update. In every other state -- including
        // notChecked, current, sourceUnavailable, updateUnsupported,
        // resolutionRequired, and checkFailed -- it keeps its icon form and
        // its function is *check for updates*, so the button can never read
        // as an upgrade that is not actually available.
        _UpdateActionButton(
          available: updateState.updateAvailable && !mutationsBlocked,
          checkTooltip: l10n.workspaceCheckForUpdate,
          updateLabel: l10n.workspaceUpdateAvailableAction,
          // `checking` is surfaced in a toast rather than by mutating the
          // action in place, so the button keeps its last known form and a
          // press during an in-flight check attaches to it.
          onCheckUpdate: operations.operation.running ? null : onCheckUpdate,
          onUpdate: operations.operation.running ? null : onUpdate,
        ),
        AppIconButton(
          key: const Key('remove-skill'),
          icon: LucideIcons.trash2,
          tooltip: l10n.workspaceRemoveSkill,
          foregroundColor: AppPalette.of(context).danger,
          buttonSize: NeoButtonSize.medium,
          onPressed: operations.operation.running ? null : onRemove,
        ),
        AppIconButton(
          key: const Key('replace-skill-source'),
          icon: LucideIcons.link2,
          tooltip: l10n.workspaceReplaceSource,
          buttonSize: NeoButtonSize.medium,
          onPressed: operations.operation.running ? null : onReplaceSource,
        ),
        _TranslationMenuButton(
          key: const Key('skill-language-button'),
          translation: translation,
          onCancel: onCancelTranslation,
          onShowOriginal: onShowOriginal,
          onTranslate: onTranslate,
          onShowCachedTranslation: onShowCachedTranslation,
          onDeleteCache: onDeleteTranslationCache,
        ),
        AppIconButton(
          key: const Key('favorite-skill'),
          icon: LucideIcons.star,
          tooltip: favorite ? l10n.workspaceUnfavorite : l10n.workspaceFavorite,
          buttonSize: NeoButtonSize.medium,
          // Keep the button surface identical in both states. Only the icon
          // communicates the favorite state, using the app's amber accent.
          foregroundColor: favorite
              ? AppPalette.of(context).warning
              : AppPalette.of(context).textSecondary,
          onPressed: mutationsBlocked ? null : onToggleFavorite,
        ),
      ],
    );
  }
}

class _MissingSkillState extends StatelessWidget {
  const _MissingSkillState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.workspaceSkillNotFound,
            style: AppTypography.of(context).bodyMuted,
          ),
          const SizedBox(height: 12),
          AppButton(
            style: NeoButtonVariant.primary,
            onPressed: context.pop,
            label: context.l10n.workspaceBackToSkills,
            icon: LucideIcons.arrowLeft,
          ),
        ],
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.description, required this.animate});

  final String description;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('skill-description-card'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 94),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: AppCorners.smooth(
        color: AppPalette.of(context).surfaceMuted,
        radius: AppRadii.dialog,
      ),
      alignment: Alignment.centerLeft,
      child: _description(context),
    );
  }

  Widget _description(BuildContext context) {
    final text = Text(
      description,
      key: ValueKey(description),
      style: AppTypography.of(context).body.copyWith(height: 1.5),
    );
    if (!animate || MediaQuery.disableAnimationsOf(context)) return text;
    return TweenAnimationBuilder<double>(
      key: ValueKey(description),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => Opacity(
        opacity: 0.72 + (0.28 * progress),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: 5 * (1 - progress),
            sigmaY: 5 * (1 - progress),
          ),
          child: child,
        ),
      ),
      child: text,
    );
  }
}

class _MetaBar extends StatelessWidget {
  const _MetaBar({required this.version, required this.source});

  final String version;
  final SkillSourceProvenance? source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: AppCorners.smooth(
        color: AppPalette.of(context).propertyCardBackground,
        radius: AppRadii.dialog,
      ),
      child: Row(
        children: [
          Expanded(
            child: _MetaCol(
              key: const Key('skill-source-meta'),
              label: context.l10n.workspaceSource,
              value: '',
              valueWidget: SkillSourceLinkValue(source: source),
              leading: source == null
                  ? null
                  : _SourceKindTag(kind: source!.kind),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _MetaCol(
              key: const Key('skill-version-meta'),
              label: context.l10n.workspaceVersion,
              value: version,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceKindTag extends StatelessWidget {
  const _SourceKindTag({required this.kind});

  final WorkspaceSourceKind kind;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (kind) {
      WorkspaceSourceKind.git => (
        context.l10n.sourceKindGit,
        LucideIcons.gitBranch,
      ),
      WorkspaceSourceKind.wellKnown => (
        context.l10n.sourceKindUrl,
        LucideIcons.link,
      ),
      WorkspaceSourceKind.local || WorkspaceSourceKind.adoptedSnapshot => (
        context.l10n.sourceKindLocal,
        LucideIcons.folderOpen,
      ),
    };
    return Align(
      widthFactor: 0.85,
      heightFactor: 0.85,
      alignment: Alignment.centerLeft,
      child: Transform.scale(
        scale: 0.85,
        alignment: Alignment.centerLeft,
        child: CapsuleTag(
          label,
          key: const Key('skill-source-kind-tag'),
          icon: icon,
        ),
      ),
    );
  }
}

class _MetaCol extends StatelessWidget {
  const _MetaCol({
    required this.label,
    required this.value,
    this.leading,
    this.valueWidget,
    super.key,
  });

  final String label;
  final String value;
  final Widget? leading;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.of(context).sectionLabel
              .copyWith(color: AppPalette.of(context).textSecondary),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            if (leading case final leading?) ...[
              leading,
              const SizedBox(width: 4),
            ],
            Expanded(
              child:
                  valueWidget ??
                  Text(
                    value,
                    style: AppTypography.of(context).mono.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppPalette.of(context).textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.selected, required this.onSelected});

  final WorkspaceTab selected;
  final ValueChanged<WorkspaceTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 124,
      height: 42,
      child: NeumorphicNavBar(
        key: const Key('skill-section-tabs'),
        selectedIndex: selected.index,
        onItemSelected: (index) => onSelected(WorkspaceTab.values[index]),
        height: 42,
        padding: const EdgeInsets.all(3),
        thumbInset: 4,
        smoothness: 0,
        iconSize: 14,
        labelFontSize: 0,
        labelSpacing: 0,
        items: [
          NeumorphicNavItem(
            label: context.l10n.workspacePreview,
            icon: LucideIcons.fileText,
          ),
          NeumorphicNavItem(
            label: context.l10n.workspaceSettings,
            icon: LucideIcons.settings,
          ),
        ],
      ),
    );
  }
}
// ── Preview tab body ──────────────────────────────────────────────────────────

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.description,
    required this.documents,
    required this.documentCatalogStatus,
    required this.documentCatalogFailure,
    required this.selectedDocumentPath,
    required this.documentStatus,
    required this.documentFailure,
    required this.onRetryDocumentCatalog,
    required this.onSelectDocument,
    required this.onRetryDocument,
    required this.active,
    required this.sourceDocument,
    required this.translation,
    required this.contentReady,
    required this.skillId,
    required this.mutationsBlocked,
  });

  final String description;
  final List<SkillDocumentEntry> documents;
  final DocumentCatalogStatus documentCatalogStatus;
  final AppFailure? documentCatalogFailure;
  final String selectedDocumentPath;
  final DocumentStatus documentStatus;
  final AppFailure? documentFailure;
  final Future<void> Function() onRetryDocumentCatalog;
  final Future<void> Function(String) onSelectDocument;
  final Future<void> Function() onRetryDocument;
  final bool active;
  final SourceDocument? sourceDocument;
  final SkillTranslationState? translation;
  final bool contentReady;
  final WorkspaceSkillId skillId;
  final bool mutationsBlocked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SkillDocumentBrowserPopover(
                active: active,
                documents: documents,
                catalogStatus: documentCatalogStatus,
                failure: documentCatalogFailure,
                selectedPath: selectedDocumentPath,
                onRetryCatalog: () => unawaited(onRetryDocumentCatalog()),
                onSelected: (relativePath) =>
                    unawaited(onSelectDocument(relativePath)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SkillTagEditor(
                  skillId: skillId,
                  enabled: !mutationsBlocked,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          switch (documentStatus) {
            DocumentStatus.none ||
            DocumentStatus.loading => const _PendingDocumentContent(),
            DocumentStatus.failure when documentFailure != null =>
              AppFailureView(
                key: const Key('document-failure'),
                failure: documentFailure!,
                variant: AppFailureViewVariant.centered,
                title: context.l10n.workspaceDocumentUnavailableNamed(
                  selectedDocumentPath,
                ),
                actionKey: const Key('retry-document'),
                onAction: () => unawaited(onRetryDocument()),
              ),
            DocumentStatus.failure => _PendingDocumentContent(
              key: const Key('document-failure'),
            ),
            DocumentStatus.ready when contentReady && sourceDocument != null =>
              _InitialContentReveal(
                sourceDocument: sourceDocument!,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DescriptionCard(
                      description: description,
                      animate:
                          translation?.phase ==
                              SkillTranslationPhase.translating &&
                          translation?.translatedDescription != null,
                    ),
                    const SizedBox(height: 16),
                    _MarkdownPreview(
                      sourceDocument: sourceDocument,
                      translation: translation,
                    ),
                  ],
                ),
              ),
            DocumentStatus.ready => const _PendingDocumentContent(),
          },
        ],
      ),
    );
  }
}

class _PendingDocumentContent extends StatelessWidget {
  const _PendingDocumentContent({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: Key('document-loading'), height: 160);
}

class _InitialContentReveal extends StatelessWidget {
  const _InitialContentReveal({
    required this.sourceDocument,
    required this.child,
  });

  final SourceDocument sourceDocument;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = RepaintBoundary(child: child);
    if (MediaQuery.disableAnimationsOf(context)) {
      return KeyedSubtree(
        key: const Key('skill-content-reveal'),
        child: content,
      );
    }
    return KeyedSubtree(
      key: const Key('skill-content-reveal'),
      child: TweenAnimationBuilder<double>(
        key: ValueKey((
          sourceDocument.slotKey,
          sourceDocument.contentHash,
          sourceDocument.documentIdentifier,
        )),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: content,
      ),
    );
  }
}

/// The detail page translate control.
///
/// It carries three states in one place. A running Job cancels on press and a
/// translation already on screen returns to the original on press, both without
/// a confirmation, because neither uploads anything. Only starting a
/// translation needs consent, and that is what the card asks for.
/// The Skill detail page's update action, as one control at two widths.
///
/// Checking for an update and applying one are the same affordance, so the
/// button keeps its identity and only changes shape: the icon circle grows
/// into a capsule and the label arrives with it. Swapping in a differently
/// styled button instead reads as the row losing a control and gaining
/// another one.
/// The amber capsule that both announces external changes and opens their
/// review. It shares the neighbouring buttons' height and capsule shape, and
/// folds into their circle when the command row cannot fit its label.
class _DriftReviewButton extends StatelessWidget {
  const _DriftReviewButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = NeoButtonTheme.of(context);
    final spec = theme.medium;
    const labelStyle = TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0);
    final expandedWidth =
        spec.horizontalPadding * 2 +
        spec.iconSize +
        theme.contentSpacing +
        _UpdateActionButton._measureLabel(
          context,
          label,
          labelStyle.copyWith(fontSize: spec.fontSize),
        );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < expandedWidth
          ? AppIconButton(
              key: const Key('skill-drift-review-action'),
              icon: LucideIcons.triangleAlert,
              tooltip: tooltip,
              buttonSize: NeoButtonSize.medium,
              foregroundColor: AppPalette.of(context).warningStrong,
              onPressed: onPressed,
            )
          : _capsule(theme, labelStyle),
    );
  }

  Widget _capsule(NeoButtonThemeData theme, TextStyle labelStyle) {
    return AppTooltip(
      message: tooltip,
      child: NeoButtonTheme(
        data: theme.copyWith(
          radiusRatio: 0.5,
          smoothness: 0,
          palette: theme.palette.copyWith(
            foreground: SkillsButtonTheme.warningForeground,
            hoverForeground: SkillsButtonTheme.warningForeground,
            card: SkillsButtonTheme.warningCard,
            hoverSurface: SkillsButtonTheme.warningHover,
            border: SkillsButtonTheme.warningBorder,
          ),
        ),
        child: AppButton(
          label: label,
          key: const Key('skill-drift-review-action'),
          icon: LucideIcons.triangleAlert,
          style: NeoButtonVariant.secondary,
          textStyle: labelStyle,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _UpdateActionButton extends StatelessWidget {
  const _UpdateActionButton({
    required this.available,
    required this.checkTooltip,
    required this.updateLabel,
    required this.onCheckUpdate,
    required this.onUpdate,
  });

  /// Whether an update is known to be available for this Skill.
  final bool available;
  final String checkTooltip;
  final String updateLabel;
  final VoidCallback? onCheckUpdate;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = NeoButtonTheme.of(context);
    final spec = theme.medium;
    // The collapsed form has to be the neighbouring icon buttons' circle, so
    // its width is its height and the glyph is centred by padding alone.
    final collapsedWidth = spec.height;
    final collapsedPadding = (collapsedWidth - spec.iconSize) / 2;
    final labelStyle = TextStyle(
      fontSize: spec.fontSize,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    final labelWidth = _measureLabel(context, updateLabel, labelStyle);
    final expandedWidth =
        spec.horizontalPadding * 2 +
        spec.iconSize +
        theme.contentSpacing +
        labelWidth;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: available ? 1 : 0),
      duration: AppMotion.controlMorphDuration,
      curve: Curves.easeOutQuart,
      builder: (context, progress, _) {
        // Width, padding and content gap all ride the same interpolation, so
        // the slot left for the label is exactly `progress` of its final
        // width at every frame: the row can neither overflow mid-morph nor
        // leave the settled label ellipsized.
        final button = NeoButtonTheme(
          data: theme.copyWith(
            // A half-height radius with no corner smoothing is precisely the
            // neighbouring circle while the button is collapsed, and a true
            // capsule at every width after that.
            radiusRatio: 0.5,
            smoothness: 0,
            contentSpacing: theme.contentSpacing * progress,
            medium: NeoButtonSizeSpec(
              height: spec.height,
              horizontalPadding: lerpDouble(
                collapsedPadding,
                spec.horizontalPadding,
                progress,
              )!,
              iconSize: spec.iconSize,
              fontSize: spec.fontSize,
            ),
            // The secondary variant takes both its glyph and its label from
            // the palette foreground, which is how the widened form keeps the
            // check button's green instead of inventing a second accent.
            palette: theme.palette.copyWith(
              foreground: NeoColor.constant(AppPalette.of(context).success),
              hoverForeground: NeoColor.constant(
                AppPalette.of(context).success,
              ),
            ),
          ),
          child: SizedBox(
            width: lerpDouble(collapsedWidth, expandedWidth, progress),
            child: AppButton(
              label: updateLabel,
              // The two keys are the two meanings of the control, and only
              // one of them is ever the button's function.
              key: available
                  ? const Key('update-skill-now')
                  : const Key('check-skill-update'),
              icon: LucideIcons.circleArrowUp,
              style: NeoButtonVariant.secondary,
              textStyle: labelStyle,
              semanticsLabel: available ? updateLabel : checkTooltip,
              fullWidth: true,
              onPressed: available ? onUpdate : onCheckUpdate,
            ),
          ),
        );
        // Collapsed there is no visible label to name the action; expanded
        // the label is the name, and a tooltip repeating it is noise.
        return available
            ? button
            : AppTooltip(message: checkTooltip, child: button);
      },
    );
  }

  /// Measures the settled label the way the button will lay it out.
  ///
  /// The expanded width is derived from this rather than from an intrinsic
  /// pass, because the button is given an explicit animated width and would
  /// otherwise ellipsize its own label at rest.
  static double _measureLabel(
    BuildContext context,
    String label,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    // Rounded up so sub-pixel disagreement with the real layout pass cannot
    // cost the label its last glyph.
    return width.ceilToDouble();
  }
}

class _TranslationMenuButton extends StatefulWidget {
  const _TranslationMenuButton({
    required this.translation,
    required this.onCancel,
    required this.onShowOriginal,
    required this.onTranslate,
    required this.onShowCachedTranslation,
    required this.onDeleteCache,
    super.key,
  });

  final SkillTranslationState? translation;
  final VoidCallback onCancel;
  final VoidCallback onShowOriginal;
  final void Function(TranslationScope) onTranslate;
  final void Function(TranslationScope) onShowCachedTranslation;
  final VoidCallback onDeleteCache;

  @override
  State<_TranslationMenuButton> createState() => _TranslationMenuButtonState();
}

class _TranslationMenuButtonState extends State<_TranslationMenuButton> {
  final _menu = MorphingMenuButtonController();

  void _handlePressed() {
    final translation = widget.translation;
    if (translation == null) return;
    if (translation.isBusy) {
      widget.onCancel();
      return;
    }
    if (translation.showsTranslation) {
      widget.onShowOriginal();
      return;
    }
    if (!translation.canTranslate) return;
    if (!translation.isProviderConfigured &&
        translation.cachedTranslations.isEmpty) {
      widget.onTranslate(TranslationScope.fullDocument);
      return;
    }
    _menu.open();
  }

  /// Runs [action] once the card is on its way out, so the press that confirms
  /// it never competes with the state change it causes.
  void _resolve(VoidCallback close, VoidCallback action) {
    close();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final translation = widget.translation;
    final busy = translation?.isBusy ?? false;
    // The filled trigger marks only the settled "the translation is on screen"
    // state. An in-flight Job keeps the default surface so the button still
    // reads as cancellable rather than as a finished translation.
    final showingTranslation =
        (translation?.showsTranslation ?? false) && !busy;
    return MorphingMenuButton(
      controller: _menu,
      icon: LucideIcons.languages,
      semanticsLabel: l10n.translationAction,
      tooltip: busy
          ? l10n.translationCancel
          : showingTranslation
          ? l10n.translationShowOriginal
          : l10n.translationAction,
      enabled:
          busy || showingTranslation || (translation?.canTranslate ?? false),
      // Every state answers the press itself; the card opens only from
      // `_handlePressed`, and only for the state that needs consent.
      onTriggerPressed: _handlePressed,
      enableDragResize: false,
      expandedWidth: 320,
      // Measured against the Chinese copy, whose CJK line height is the taller
      // of the two locales; the English card has a few points to spare.
      expandedHeight: translation?.canTranslateDescription == true ? 264 : 290,
      // The control sits at the trailing end of the header actions, so the card
      // hangs back under it instead of pushing past the page edge.
      alignment: MorphingMenuAlignment.end,
      style: SkillsButtonTheme.translationTriggerStyle(
        context,
        filled: showingTranslation,
      ),
      contentBuilder: (menuContext, close) {
        final profile = widget.translation?.profile;
        if (profile == null) return const SizedBox.shrink();
        return _TranslationConfirmationCard(
          profile: profile,
          translation: widget.translation!,
          onTranslate: (scope) =>
              _resolve(close, () => widget.onTranslate(scope)),
          onShowCached: (scope) =>
              _resolve(close, () => widget.onShowCachedTranslation(scope)),
          onDeleteCache: () => _resolve(close, widget.onDeleteCache),
        );
      },
    );
  }
}

/// The consent the App asks for before a Skill's text leaves the machine.
class _TranslationConfirmationCard extends ConsumerWidget {
  const _TranslationConfirmationCard({
    required this.profile,
    required this.translation,
    required this.onTranslate,
    required this.onShowCached,
    required this.onDeleteCache,
  });

  final TranslationProviderProfile profile;
  final SkillTranslationState translation;
  final void Function(TranslationScope) onTranslate;
  final void Function(TranslationScope) onShowCached;
  final VoidCallback onDeleteCache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final canTranslateDescription = translation.canTranslateDescription;
    final preferredScope = ref.watch(translationScopePreferenceProvider);
    final scope = canTranslateDescription
        ? preferredScope
        : TranslationScope.fullDocument;
    final cached = translation.hasCached(scope);
    return Column(
      key: const Key('translation-confirmation'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Everything above the actions scrolls rather than pushing them off the
        // card, so a long endpoint or a wrapped line cannot overflow it. Any
        // height the card has to spare collects above the actions instead of
        // opening a gap inside the content.
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.translationConfirmTitle,
                  style: AppTypography.of(context).subtitle,
                ),
                const SizedBox(height: AppSpacing.xs),
                // The card exists to get consent for text leaving the machine,
                // so it says so rather than leaving the rows to imply it.
                Text(
                  l10n.translationConfirmMessage,
                  style: AppTypography.of(context).caption,
                ),
                const SizedBox(height: AppSpacing.md),
                _TranslationDisclosure(
                  rows: [
                    (
                      label: l10n.translationConfirmProvider,
                      value:
                          profile.provider ==
                              AppTranslationProviderKind.openAICompatible
                          ? l10n.translationProviderOpenAIShort
                          : l10n.translationProviderAnthropicShort,
                      machine: false,
                    ),
                    (
                      label: l10n.translationConfirmEndpoint,
                      value: profile.endpointHost,
                      machine: true,
                    ),
                    (
                      label: l10n.translationConfirmTarget,
                      value: profile.targetLanguage,
                      machine: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Both scopes are named, so the full-Skill default reads as a
                // choice rather than as the absence of one.
                CupertinoSlidingSegmentedControl<TranslationScope>(
                  key: const Key('translation-scope-control'),
                  groupValue: scope,
                  disabledChildren: {
                    if (!canTranslateDescription)
                      TranslationScope.descriptionOnly,
                  },
                  children: {
                    TranslationScope.fullDocument: _TranslationScopeLabel(
                      key: const Key('translation-scope-full'),
                      label: l10n.translationScopeFullDocument,
                    ),
                    TranslationScope.descriptionOnly: _TranslationScopeLabel(
                      key: const Key('translation-scope-description'),
                      label: l10n.translationScopeDescription,
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) {
                      ref
                          .read(translationScopePreferenceProvider.notifier)
                          .select(value);
                    }
                  },
                ),
                if (!canTranslateDescription) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.translationDescriptionUnavailable,
                    style: AppTypography.of(context).caption,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            // Kept on the opposite edge from the confirming action so a
            // destructive cache purge can never be hit by momentum.
            // Icon-only: a labelled destructive button and the confirming
            // action together no longer fit this card's width.
            if (translation.cachedTranslations.isNotEmpty)
              AppIconButton(
                key: const Key('delete-translation-cache'),
                icon: LucideIcons.trash2,
                tooltip: l10n.translationDeleteCache,
                style: NeoButtonVariant.danger,
                buttonSize: NeoButtonSize.medium,
                onPressed: onDeleteCache,
              ),
            const Spacer(),
            AppButton(
              key: const Key('confirm-translation'),
              label: cached
                  ? l10n.translationShowCached
                  : l10n.translationAction,
              icon: LucideIcons.languages,
              style: NeoButtonVariant.primary,
              onPressed: () =>
                  cached ? onShowCached(scope) : onTranslate(scope),
            ),
          ],
        ),
      ],
    );
  }
}

typedef _DuplicateActivationConfirmation = ({
  bool confirmed,
  bool dontAskAgain,
});

Future<_DuplicateActivationConfirmation?>
_showProjectDuplicateActivationConfirmation(BuildContext context) async =>
    await AppDialogMotion.show<_DuplicateActivationConfirmation>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var dontAskAgain = false;
        void cancel() => Navigator.of(dialogContext).pop();
        return StatefulBuilder(
          builder: (context, setState) => AppConfirmDialog(
            key: const Key('project-duplicate-activation-dialog'),
            icon: LucideIcons.copy,
            tone: AppDialogTone.warning,
            title: context.l10n.workspaceDuplicateActivationTitle,
            message: context.l10n.workspaceDuplicateActivationMessage,
            onEscape: cancel,
            sections: [
              AppDialogSection(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    CupertinoCheckbox(
                      key: const Key('project-duplicate-activation-dont-ask'),
                      value: dontAskAgain,
                      onChanged: (value) =>
                          setState(() => dontAskAgain = value ?? false),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.workspaceDuplicateActivationDontAskAgain,
                        style: AppTypography.of(context).control,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            actions: [
              AppButton(
                key: const Key('project-duplicate-activation-cancel'),
                label: context.l10n.commonCancel,
                style: NeoButtonVariant.secondary,
                size: NeoButtonSize.large,
                fullWidth: true,
                onPressed: cancel,
              ),
              AppButton(
                key: const Key('project-duplicate-activation-confirm'),
                label: context.l10n.workspaceDuplicateActivationContinue,
                icon: LucideIcons.zap,
                style: NeoButtonVariant.primary,
                size: NeoButtonSize.large,
                fullWidth: true,
                onPressed: () =>
                    Navigator.of(dialogContext)
                        .pop((confirmed: true, dontAskAgain: dontAskAgain)),
              ),
            ],
          ),
        );
      },
    );

/// Where a translation request goes, as one inset block of label/value rows.
///
/// Labels are quieter than the values they introduce, and only values a person
/// would copy rather than read — a host, a language tag — are set in mono.
class _TranslationDisclosure extends StatelessWidget {
  const _TranslationDisclosure({required this.rows});

  final List<({String label, String value, bool machine})> rows;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: 10,
    ),
    decoration: AppCorners.smooth(
      color: AppPalette.of(context).surfaceMuted,
      radius: AppRadii.md,
    ),
    child: Table(
      // Sized to the longest label, so the values share one edge in either
      // locale instead of a fixed column that fits only one of them.
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final (index, row) in rows.indexed)
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  right: AppSpacing.md,
                  top: index == 0 ? 0 : 6,
                ),
                child: Text(
                  row.label,
                  style: AppTypography.of(context).caption,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 6),
                child: Text(
                  row.value,
                  style: row.machine
                      ? AppTypography.of(context).mono
                            .copyWith(color: AppPalette.of(context).textPrimary)
                      : AppTypography.of(context).control.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppPalette.of(context).textPrimary,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _TranslationScopeLabel extends StatelessWidget {
  const _TranslationScopeLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({
    required this.sourceDocument,
    required this.translation,
  });

  final SourceDocument? sourceDocument;
  final SkillTranslationState? translation;

  @override
  Widget build(BuildContext context) {
    final source = sourceDocument;
    if (source != null && translation?.translatedBlocks.isNotEmpty == true) {
      return AppSelectionArea(
        child: MarkdownWidget.contentReplacement(
          key: const Key('skill-markdown'),
          document: parseTranslationDisplayDocument(
            documentIdentifier: source.documentIdentifier,
            content: source.content,
          ),
          replacements: translation!.translatedBlocks,
          theme: AppMarkdownTheme.data(context),
        ),
      );
    }
    if (source == null) {
      return Center(
        key: Key('document-loading'),
        child: CupertinoActivityIndicator(color: AppPalette.of(context).ink),
      );
    }
    final markdown = parseTranslationDisplayDocument(
      documentIdentifier: source.documentIdentifier,
      content: translation?.activeScope == TranslationScope.fullDocument
          ? translation?.translatedContent ?? source.content
          : source.content,
    ).markdown;
    return AppSelectionArea(
      child: MarkdownWidget(
        key: const Key('skill-markdown'),
        markdown: markdown,
        theme: AppMarkdownTheme.data(context),
      ),
    );
  }
}

// ── Settings (activations) tab body ──────────────────────────────────────────

class _ActivationsBody extends ConsumerStatefulWidget {
  const _ActivationsBody({
    required this.skill,
    required this.isLocationBusy,
    required this.mutationsBlocked,
    required this.onToggle,
    required this.onToggleAll,
    required this.note,
    required this.onSaveNote,
  });
  final InstalledSkill skill;
  final bool Function(String location) isLocationBusy;
  final bool mutationsBlocked;
  final Future<void> Function(ActivationLocationGroup group, bool value)
  onToggle;
  final Future<void> Function(List<ActivationLocationGroup> groups, bool value)
  onToggleAll;
  final String note;
  final ValueChanged<String> onSaveNote;

  @override
  ConsumerState<_ActivationsBody> createState() => _ActivationsBodyState();
}

class _ActivationsBodyState extends ConsumerState<_ActivationsBody> {
  SkillScopeSelection _selection = const GlobalSkillScope();
  bool _duplicateActivationDialogOpen = false;

  @override
  void didUpdateWidget(covariant _ActivationsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.skill.id != widget.skill.id) {
      _selection = const GlobalSkillScope();
    }
  }

  @override
  Widget build(BuildContext context) {
    final roots = ref.watch(skillBrowserCatalogProvider).projectRoots;
    var selection = _selection;
    final selectedRootId = switch (selection) {
      ProjectSkillScope(:final rootId) => rootId,
      _ => null,
    };
    if (selectedRootId != null && !roots.any((r) => r.id == selectedRootId)) {
      selection = const GlobalSkillScope();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _selection is ProjectSkillScope &&
            !ref
                .read(skillBrowserCatalogProvider)
                .projectRoots
                .any((r) => r.id == (_selection as ProjectSkillScope).rootId)) {
          setState(() => _selection = const GlobalSkillScope());
        }
      });
    }
    final rootId = switch (selection) {
      ProjectSkillScope(:final rootId) => rootId,
      _ => null,
    };
    final scope = rootId == null
        ? WorkspaceScope.global
        : WorkspaceScope.project;
    final inspection = ref.watch(
      activationTargetsProvider((scope: scope, projectRootId: rootId)),
    );
    final members = ref.watch(deviceAgentMembersProvider);
    final loading = inspection.isLoading || members.isLoading;
    final failed =
        inspection.hasError ||
        members.hasError ||
        inspection.value is WorkspaceFailed;
    final targets = switch (inspection.value) {
      WorkspaceCompleted<List<WorkspaceActivationTarget>>(:final value) =>
        value,
      _ => const <WorkspaceActivationTarget>[],
    };
    final skill = widget.skill;
    final activations = skill.activations
        .where((a) => a.scope == scope && a.projectRootId == rootId)
        .toList();
    final groups = deviceActivationGroups(targets, members.value ?? const {});
    final activeKeys = {
      for (final a in activations)
        activationLocationKey(a.scope, a.projectRootId, a.location),
    };
    final enabledCount = groups.where((g) => activeKeys.contains(g.key)).length;
    final operationRunning = ref
        .watch(skillOperationsViewModelProvider)
        .operation
        .running;
    final mutationsAllowed =
        !widget.mutationsBlocked && !loading && !failed && !operationRunning;
    Widget row(ActivationLocationGroup group) => _ActivationGroupRow(
      group: group,
      activation: activations
          .where(
            (a) =>
                activationLocationKey(a.scope, a.projectRootId, a.location) ==
                group.key,
          )
          .firstOrNull,
      busy: widget.isLocationBusy(group.location),
      onToggle: !mutationsAllowed
          ? null
          : (value) {
              if (!value || group.canActivate) {
                unawaited(_handleToggle(group, value));
              }
            },
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailHeader(skill: skill),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Container(
                width: 20,
                height: 18,
                alignment: Alignment.center,
                decoration: AppCorners.smooth(
                  color: AppPalette.of(context).surfaceMuted,
                  radius: 5,
                ),
                child: Text(
                  '$enabledCount',
                  style: AppTypography.of(context).sectionLabel,
                ),
              ),
              const Spacer(),
              if (groups.isNotEmpty) ...[
                AgentActivationSwitch(
                  key: const Key('activation-toggle-all'),
                  on: enabledCount == groups.length,
                  label: context.l10n.activationAllAgentsToggle,
                  onChanged: !mutationsAllowed
                      ? null
                      : (value) => unawaited(_handleToggleAll(groups, value)),
                ),
                const SizedBox(width: 12),
              ],
              SkillScopeMenu(
                keyPrefix: 'detail-scope',
                selection: selection,
                projectRoots: roots,
                onSelected: (value) => setState(() => _selection = value),
                onManageProjects: () =>
                    context.pushNamed(AppRouteNames.projectRoots),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CupertinoActivityIndicator()),
            ),
          if (failed)
            AppButton(
              label: context.l10n.commonRetry,
              onPressed: () {
                ref.read(activationCatalogRevisionProvider.notifier).refresh();
                if (ref.read(appSettingsViewModelProvider).errorCode ==
                    'settings_load_failed') {
                  ref.read(appSettingsViewModelProvider.notifier).load();
                }
              },
            ),
          if (!loading && !failed && groups.isEmpty)
            Text(
              context.l10n.workspaceActivateNoTargets,
              style: AppTypography.of(context).bodyMuted,
            ),
          for (final group in groups) row(group),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.center,
            child: AppButton(
              key: const Key('detail-manage-agents'),
              label: context.l10n.agentsManage,
              icon: LucideIcons.settings2,
              style: NeoButtonVariant.primary,
              onPressed: () => showAgentManagementDialog(context),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.workspaceNotes,
                  style: AppTypography.of(context).sectionLabel,
                ),
                const SizedBox(height: 10),
                _SkillNoteEditor(
                  note: widget.note,
                  enabled: !widget.mutationsBlocked,
                  onSave: widget.onSaveNote,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Both the per-row and the master switch must clear the same project
  /// duplicate-activation confirmation; routing the master switch straight to
  /// the mutation would activate silently where a single row asks first. The
  /// master switch asks once for the whole batch rather than once per
  /// overlapping Agent.
  Future<bool> _confirmDuplicateActivation(
    Iterable<ActivationLocationGroup> groups,
    bool value,
  ) async {
    final currentSkill = ref
        .read(skillBrowserCatalogProvider)
        .skills
        .where((skill) => skill.id == widget.skill.id)
        .firstOrNull;
    final suppressConfirmation = ref
        .read(appSettingsViewModelProvider)
        .settings
        .suppressDuplicateActivationConfirmation;
    if (!value ||
        _selection is! ProjectSkillScope ||
        _duplicateActivationDialogOpen ||
        suppressConfirmation ||
        currentSkill == null ||
        !groups.any(
          (group) => hasGlobalActivationOverlap(
            skill: currentSkill,
            projectGroup: group,
          ),
        )) {
      return true;
    }
    _duplicateActivationDialogOpen = true;
    final confirmed = await _showProjectDuplicateActivationConfirmation(
      context,
    );
    _duplicateActivationDialogOpen = false;
    if (!mounted || confirmed?.confirmed != true) return false;
    if (confirmed!.dontAskAgain) {
      await ref
          .read(appSettingsViewModelProvider.notifier)
          .setSuppressDuplicateActivationConfirmation(true);
    }
    return mounted;
  }

  Future<void> _handleToggle(ActivationLocationGroup group, bool value) async {
    if (await _confirmDuplicateActivation([group], value)) {
      await widget.onToggle(group, value);
    }
  }

  Future<void> _handleToggleAll(
    List<ActivationLocationGroup> groups,
    bool value,
  ) async {
    if (await _confirmDuplicateActivation(groups, value)) {
      await widget.onToggleAll(groups, value);
    }
  }
}

class _SkillNoteEditor extends StatefulWidget {
  const _SkillNoteEditor({
    required this.note,
    required this.enabled,
    required this.onSave,
  });

  final String note;
  final bool enabled;
  final ValueChanged<String> onSave;

  @override
  State<_SkillNoteEditor> createState() => _SkillNoteEditorState();
}

class _SkillNoteEditorState extends State<_SkillNoteEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note);
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _SkillNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.note != widget.note) {
      _controller.text = widget.note;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) widget.onSave(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('skill-note-editor'),
    constraints: const BoxConstraints(minHeight: 60),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: AppCorners.smooth(
      color: AppPalette.of(context).white,
      radius: 10,
      side: BorderSide(color: AppPalette.of(context).border),
    ),
    child: CupertinoTextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      maxLines: 4,
      minLines: 2,
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(),
      placeholder: context.l10n.workspaceAddNote,
      style: AppTypography.of(context).control.copyWith(height: 1.4),
      onSubmitted: (_) => widget.onSave(_controller.text.trim()),
    ),
  );
}

class _ActivationGroupRow extends StatelessWidget {
  const _ActivationGroupRow({
    required this.group,
    required this.activation,
    required this.busy,
    required this.onToggle,
  });

  final ActivationLocationGroup group;
  final SkillActivationLocation? activation;
  final bool busy;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final target = group.first;
    final active = activation != null;

    return Container(
      key: Key(
        'activation-group-${target.scope.name}-'
        '${target.projectRootId ?? 'global'}-${target.location}',
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppPalette.of(context).border),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: AgentActivationGroupLabel(group: group)),
          const SizedBox(width: 12),
          _Pill(
            label: target.scope == WorkspaceScope.global
                ? context.l10n.commonGlobal
                : context.l10n.commonProject,
          ),
          const SizedBox(width: 8),
          if (activation != null)
            _Pill(
              label: activation!.mode == WorkspaceActivationMode.copy
                  ? 'copy'
                  : 'symlink',
              icon: activation!.mode == WorkspaceActivationMode.copy
                  ? LucideIcons.copy
                  : LucideIcons.link,
              outlined: true,
            ),
          const SizedBox(width: 14),
          if (busy)
            SizedBox.square(
              dimension: 24,
              child: CupertinoActivityIndicator(
                radius: 8,
                color: AppPalette.of(context).ink,
              ),
            )
          else
            AgentActivationSwitch(
              label:
                  '${activationAgentGroupTitle(context, group)} ${target.location}',
              key: Key(
                'activation-toggle-${target.scope.name}-'
                '${target.projectRootId ?? 'global'}-${target.location}',
              ),
              on: active,
              onChanged: onToggle,
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon, this.outlined = false});

  final String label;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: AppCorners.smooth(
        color: outlined
            ? AppPalette.of(context).transparent
            : AppPalette.of(context).surfaceMuted,
        radius: 6,
        side: outlined
            ? BorderSide(color: AppPalette.of(context).borderStrong)
            : BorderSide.none,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppPalette.of(context).textMuted),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: outlined
                ? AppTypography.of(context).mono
                      .copyWith(color: AppPalette.of(context).textMuted)
                : AppTypography.of(context).caption
                      .copyWith(color: AppPalette.of(context).bodyContent),
          ),
        ],
      ),
    );
  }
}

// ── Remove dialog ─────────────────────────────────────────────────────────────

class SkillRemoveDialog extends ConsumerStatefulWidget {
  const SkillRemoveDialog({required this.skill, super.key});

  final InstalledSkill skill;

  @override
  ConsumerState<SkillRemoveDialog> createState() => _SkillRemoveDialogState();
}

class _SkillRemoveDialogState extends ConsumerState<SkillRemoveDialog> {
  late int _reviewedRevision;
  var _busy = false;
  var _stale = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reviewedRevision = ref.read(skillBrowserCatalogProvider).revision;
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await ref
          .read(skillOperationsViewModelProvider.notifier)
          .remove(
            skillId: widget.skill.id,
            reviewedRevision: _reviewedRevision,
          );
      if (!mounted) return;
      switch (outcome) {
        case RemoveSkillOutcome.removed || RemoveSkillOutcome.pending:
          context.goNamed(AppRouteNames.installed);
        case RemoveSkillOutcome.stale:
          setState(() {
            _stale = true;
            _reviewedRevision = ref.read(skillBrowserCatalogProvider).revision;
          });
        case RemoveSkillOutcome.cancelled || RemoveSkillOutcome.failed:
          break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driftPending =
        ref
            .watch(workspaceSkillByIdProvider(widget.skill.id))
            .value
            ?.integrity ==
        WorkspaceSkillIntegrityStatus.driftPending;
    final operation = ref.watch(
      skillOperationsViewModelProvider.select((state) => state.operation),
    );
    final operationsViewModel = ref.read(
      skillOperationsViewModelProvider.notifier,
    );
    void cancel() {
      if (_busy) {
        unawaited(operationsViewModel.cancelOperation());
      } else {
        context.pop();
      }
    }

    return AppConfirmDialog(
      key: const Key('remove-skill-dialog'),
      icon: LucideIcons.trash2,
      tone: AppDialogTone.danger,
      title: context.l10n.workspaceRemoveNamedTitle(widget.skill.displayName),
      message: context.l10n.workspaceRemoveDetailedMessage,
      onEscape: _busy ? null : cancel,
      sections: [
        AppDialogSection(
          title: context.l10n.workspaceRemoveCleared,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ClearedItem(
                icon: LucideIcons.package,
                text: context.l10n.workspaceRemoveSlot(
                  widget.skill.displayName,
                ),
              ),
              const SizedBox(height: 8),
              _ClearedItem(
                icon: LucideIcons.plug,
                text: context.l10n.workspaceRemoveActivationCount(
                  widget.skill.activationCount,
                ),
              ),
              if (driftPending) ...[
                const SizedBox(height: 16),
                AppDialogNote(
                  key: const Key('remove-skill-drift-warning'),
                  tone: AppDialogTone.danger,
                  text: context.l10n.removeSkillDriftWarning,
                ),
              ],
            ],
          ),
        ),
        AppDialogSection(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.tag,
                    size: 13,
                    color: AppPalette.of(context).textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _stale
                          ? context.l10n.workspaceRemoveStale(_reviewedRevision)
                          : context.l10n.workspaceRemoveRevision(
                              _reviewedRevision,
                            ),
                      style: AppTypography.of(context).caption.copyWith(
                        color: AppPalette.of(context).textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: AppTypography.of(context).caption.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppPalette.of(context).danger,
                  ),
                ),
              ],
              if (operation.running || operation.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppOperationFeedback(
                  label: localizeWorkspacePhase(
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
                      ? () => unawaited(operationsViewModel.cancelOperation())
                      : null,
                ),
              ],
            ],
          ),
        ),
      ],
      actions: [
        AppButton(
          key: const Key('remove-cancel'),
          label: context.l10n.commonCancel,
          style: NeoButtonVariant.secondary,
          size: NeoButtonSize.large,
          fullWidth: true,
          onPressed: cancel,
        ),
        AppButton(
          key: const Key('remove-confirm'),
          label: _busy
              ? context.l10n.workspaceRemoving
              : _stale
              ? context.l10n.workspaceRemoveConfirmAgain
              : context.l10n.workspaceRemoveAction,
          icon: LucideIcons.trash2,
          style: NeoButtonVariant.danger,
          size: NeoButtonSize.large,
          fullWidth: true,
          onPressed: _busy ? null : () => unawaited(_remove()),
        ),
      ],
    );
  }
}

class RemoveSkillDialogRoute extends ConsumerWidget {
  const RemoveSkillDialogRoute({required this.skillId, super.key});

  final WorkspaceSkillId skillId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(skillBrowserCatalogProvider).skills;
    InstalledSkill? skill;
    for (final candidate in skills) {
      if (candidate.id == skillId) {
        skill = candidate;
        break;
      }
    }
    if (skill != null) return SkillRemoveDialog(skill: skill);
    return AppConfirmDialog(
      icon: LucideIcons.trash2,
      tone: AppDialogTone.danger,
      title: context.l10n.workspaceSkillNotFound,
      message: context.l10n.errorSkillNotFound,
      onEscape: context.pop,
      actions: [
        AppButton(
          label: context.l10n.commonClose,
          style: NeoButtonVariant.primary,
          size: NeoButtonSize.large,
          fullWidth: true,
          onPressed: context.pop,
        ),
      ],
    );
  }
}

class _ClearedItem extends StatelessWidget {
  const _ClearedItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppPalette.of(context).textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTypography.of(context).control.copyWith(
              fontWeight: FontWeight.w500,
              color: AppPalette.of(context).bodyContent,
            ),
          ),
        ),
      ],
    );
  }
}
