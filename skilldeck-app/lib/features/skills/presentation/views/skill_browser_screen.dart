import 'package:skills_manager/features/skills/presentation/widgets/repository_group_transition.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/library/personal_tag_providers.dart';
import 'package:skills_manager/features/library/presentation/widgets/personal_tag_controls.dart';
import 'package:skills_manager/features/library/presentation/widgets/personal_tag_filter_panel.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_location_label.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:skills_manager/features/skills/presentation/widgets/skill_scope_menu.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/navigation/app_routes.dart';
import 'package:skills_manager/shared/scrolling/app_scroll_controller.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_page_content.dart';
import 'package:skills_manager/shared/widgets/app_page_template.dart';
import 'package:skills_manager/shared/widgets/app_sidebar.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_acquisition_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/external_skills_view_model.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/installed_agent_filter.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_grouping.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_repository_groups.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_sort.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_takeover_dialog.dart';
import 'package:skills_manager/features/translation/presentation/view_models/skill_translation_view_model.dart';

class SkillBrowserScreen extends ConsumerWidget {
  const SkillBrowserScreen({this.favoritesOnly = false, super.key});

  final bool favoritesOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(skillDescriptionPreloadProvider, (_, _) {});
    final l10n = context.l10n;
    final catalog = ref.watch(skillBrowserCatalogProvider);
    final externalSkillsState = ref.watch(externalSkillsViewModelProvider);
    final viewModel = ref.read(skillBrowserViewModelProvider.notifier);
    final acquisitionViewModel = ref.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    final searchQuery = ref.watch(skillSearchQueryProvider);
    final sortPage = favoritesOnly
        ? SkillListPage.favorites
        : SkillListPage.installed;
    final sortMode = ref.watch(
      skillListSortProvider.select(
        (state) => state[sortPage] ?? SkillListSortMode.nameAscending,
      ),
    );
    final layout = ref.watch(skillListLayoutProvider);
    final groupingMode =
        ref.watch(skillListGroupingProvider)[sortPage] ??
        SkillListGroupingMode.none;
    final folds = ref.watch(skillListGroupFoldsProvider)[sortPage];
    final collapsedGroups =
        (searchQuery.isEmpty ? folds?.browsing : folds?.searching) ??
        const <String>{};
    final scopeFilter = ref.watch(installedScopeFilterProvider);
    final projectRootFilter = ref.watch(installedProjectRootFilterProvider);
    final locationFilter = ref.watch(installedLocationFilterProvider);
    final tagFilter = ref.watch(personalTagFilterProvider);
    final query = searchQuery.toLowerCase();
    final filteredSkills =
        catalog.skills.where((skill) {
          final matchesLocation = matchesInstalledSelection(
            skill,
            scope: scopeFilter,
            projectRootId: projectRootFilter,
            filter: locationFilter,
          );
          final matchesQuery =
              searchQuery.isEmpty ||
              skill.displayName.toLowerCase().contains(query) ||
              skill.description.toLowerCase().contains(query);
          return matchesLocation &&
              matchesQuery &&
              (!favoritesOnly || skill.isFavorite) &&
              tagFilter.every(skill.personalTagIds.contains);
        }).toList()..sort(
          (left, right) => compareInstalledSkills(left, right, sortMode),
        );

    return switch (catalog.status) {
      CatalogStatus.loading => _LoadingBody(
        layout: layout,
        favoritesOnly: favoritesOnly,
      ),
      CatalogStatus.failure =>
        catalog.failure == null
            ? _ErrorState(
                stateKey: const Key('browser-failure'),
                icon: LucideIcons.circleAlert,
                title: l10n.browserRepositoryUnavailable,
                message: l10n.browserRepositoryUnavailableMessage,
              )
            : AppFailureView(
                key: const Key('browser-failure'),
                failure: catalog.failure!,
                variant: AppFailureViewVariant.centered,
                title: l10n.browserRepositoryUnavailable,
                actionKey: const Key('retry-open'),
                actionLabel: l10n.commonRetry,
                onAction: () => unawaited(viewModel.load()),
              ),
      CatalogStatus.unsupported => _ErrorState(
        stateKey: Key('browser-unsupported'),
        icon: LucideIcons.monitor,
        title: l10n.browserDesktopRequired,
        message: l10n.browserDesktopRequiredMessage,
      ),
      CatalogStatus.ready when catalog.skills.isEmpty && !favoritesOnly =>
        _EmptyState(
          unmanagedSlotCount: externalSkillsState.unmanagedSlotCount,
          onAdd: acquisitionViewModel.isAvailable
              ? () => context.pushNamed(AppRouteNames.addSkill)
              : null,
          onDiscover: () =>
              context.pushNamed(AppRouteNames.discoverExternalSkills),
        ),
      _ => _ReadyBody(
        viewModel: viewModel,
        filteredSkills: filteredSkills,
        searchQuery: searchQuery,
        sortMode: sortMode,
        onSortSelected: (mode) =>
            ref.read(skillListSortProvider.notifier).select(sortPage, mode),
        layout: layout,
        groupingMode: groupingMode,
        collapsedGroups: collapsedGroups,
        onGroupToggled: (key) => ref
            .read(skillListGroupFoldsProvider.notifier)
            .toggle(sortPage, key, searching: searchQuery.isNotEmpty),
        onGroupingSelected: (mode) =>
            ref.read(skillListGroupingProvider.notifier).select(sortPage, mode),
        onSearchChanged: (value) {
          if (value != searchQuery) {
            ref.read(skillListGroupFoldsProvider.notifier).searchChanged();
          }
          ref.read(skillSearchQueryProvider.notifier).setQuery(value);
        },
        onSkillTapped: (skillId) => context.pushNamed(
          AppRouteNames.skillDetail,
          pathParameters: {'skillId': skillId.value},
        ),
        onRefresh: () => unawaited(_refreshAndScan(ref, viewModel)),
        onAddFromSource: acquisitionViewModel.isAvailable
            ? () => context.pushNamed(AppRouteNames.addSkill)
            : null,
        onDiscoverExternalSkills: () =>
            context.pushNamed(AppRouteNames.discoverExternalSkills),
        refreshScanMode: _refreshScanMode(catalog, externalSkillsState),
        unmanagedSlotCount: externalSkillsState.unmanagedSlotCount,
        favoritesOnly: favoritesOnly,
      ),
    };
  }

  _InstalledRefreshScanMode _refreshScanMode(
    SkillBrowserCatalogState catalog,
    ExternalSkillsState externalSkillsState,
  ) {
    if (catalog.refreshing ||
        externalSkillsState.status == ExternalSkillsStatus.idle ||
        externalSkillsState.scanning ||
        externalSkillsState.adopting) {
      return _InstalledRefreshScanMode.scanning;
    }
    if (externalSkillsState.scanFailed) {
      return _InstalledRefreshScanMode.refresh;
    }
    if (externalSkillsState.discovery != null &&
        externalSkillsState.unmanagedSlotCount > 0) {
      return _InstalledRefreshScanMode.manage;
    }
    return _InstalledRefreshScanMode.refresh;
  }

  Future<void> _refreshAndScan(
    WidgetRef ref,
    SkillBrowserViewModel viewModel,
  ) async {
    await viewModel.refresh();
    await ref.read(externalSkillsViewModelProvider.notifier).scan();
  }
}

class _ReadyBody extends StatefulWidget {
  const _ReadyBody({
    required this.viewModel,
    required this.filteredSkills,
    required this.searchQuery,
    required this.sortMode,
    required this.onSortSelected,
    required this.groupingMode,
    required this.onGroupingSelected,
    required this.collapsedGroups,
    required this.onGroupToggled,
    required this.layout,
    required this.onSearchChanged,
    required this.onSkillTapped,
    required this.onRefresh,
    required this.refreshScanMode,
    required this.unmanagedSlotCount,
    required this.favoritesOnly,
    required this.onDiscoverExternalSkills,
    this.onAddFromSource,
  });

  final SkillBrowserViewModel viewModel;
  final List<InstalledSkill> filteredSkills;
  final String searchQuery;
  final SkillListSortMode sortMode;
  final ValueChanged<SkillListSortMode> onSortSelected;
  final SkillListGroupingMode groupingMode;
  final ValueChanged<SkillListGroupingMode> onGroupingSelected;
  final Set<String> collapsedGroups;
  final ValueChanged<String> onGroupToggled;
  final SkillListLayout layout;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<WorkspaceSkillId> onSkillTapped;
  final VoidCallback onRefresh;
  final VoidCallback? onAddFromSource;
  final VoidCallback onDiscoverExternalSkills;
  final _InstalledRefreshScanMode refreshScanMode;
  final int unmanagedSlotCount;
  final bool favoritesOnly;

  @override
  State<_ReadyBody> createState() => _ReadyBodyState();
}

class _ReadyBodyState extends State<_ReadyBody> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = AppScrollControllers.create(
      debugLabel: 'installed-skills',
    );
  }

  @override
  void didUpdateWidget(covariant _ReadyBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupingMode != widget.groupingMode &&
        _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filteredSkills = widget.filteredSkills;
    final searchQuery = widget.searchQuery;

    return AppPageTemplate(
      controller: _scrollController,
      scrollViewKey: const Key('skill-list'),
      blurKey: const Key('installed-top-blur'),
      headerKey: const Key('installed-header-column'),
      breadcrumbKey: const Key('installed-breadcrumb'),
      titleKey: const Key('installed-title'),
      breadcrumb: l10n.commonSectionBreadcrumb,
      breadcrumbIcon: widget.favoritesOnly
          ? NavSection.favorites.icon
          : NavSection.installed.icon,
      title: widget.favoritesOnly ? l10n.navFavorites : l10n.browserInstalled,
      commandTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: _InstalledRefreshScanAction(
              mode: widget.favoritesOnly
                  ? _InstalledRefreshScanMode.refresh
                  : widget.refreshScanMode,
              unmanagedSlotCount: widget.unmanagedSlotCount,
              onRefresh: widget.onRefresh,
              onManage: widget.onDiscoverExternalSkills,
            ),
          ),
          if (!widget.favoritesOnly && widget.onAddFromSource != null) ...[
            const SizedBox(width: AppSpacing.sm),
            _AddFromSourceButton(
              buttonKey: const Key('add-skills'),
              onPressed: widget.onAddFromSource!,
            ),
          ],
        ],
      ),
      slivers: [
        AppPageSliverContent(
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: _FilterBar(
                searchQuery: searchQuery,
                onSearchChanged: widget.onSearchChanged,
                sortMode: widget.sortMode,
                onSortSelected: widget.onSortSelected,
                groupingMode: widget.groupingMode,
                onGroupingSelected: widget.onGroupingSelected,
              ),
            ),
          ),
        ),
        if (filteredSkills.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Consumer(
                builder: (context, ref, _) {
                  if (ref.watch(personalTagFilterProvider).isNotEmpty) {
                    return _TagFilterEmptyState(
                      onClear: ref
                          .read(personalTagFilterProvider.notifier)
                          .clear,
                    );
                  }
                  return Text(
                    widget.favoritesOnly
                        ? l10n.browserFavoritesEmpty
                        : searchQuery.isEmpty
                        ? l10n.browserNoSkillsYet
                        : l10n.browserNoMatches(searchQuery),
                    style: AppTypography.of(context).bodyMuted,
                  );
                },
              ),
            ),
          )
        else ...[
          if (widget.groupingMode == SkillListGroupingMode.none)
            AppPageSliverContent(
              sliver: _memberSliver(
                filteredSkills,
                gridKey: const Key('skill-card-grid'),
              ),
            )
          else
            for (final group in groupSkillsByRepository(filteredSkills)) ...[
              AppPageSliverContent(
                key: ValueKey('repository-header-sliver-${group.identity.key}'),
                sliver: SliverToBoxAdapter(
                  child: _RepositoryGroupHeader(
                    group: group,
                    collapsed: widget.collapsedGroups.contains(
                      group.identity.key,
                    ),
                    onPressed: () => widget.onGroupToggled(group.identity.key),
                  ),
                ),
              ),
              AppPageSliverContent(
                key: ValueKey(
                  'repository-members-sliver-${group.identity.key}',
                ),
                sliver: RepositoryGroupTransition(
                  collapsed: widget.collapsedGroups.contains(
                    group.identity.key,
                  ),
                  searchQuery: widget.searchQuery,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.only(top: 8),
                    sliver: _memberSliver(
                      group.skills,
                      gridKey: ValueKey(
                        'skill-card-grid-${group.identity.key}',
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                key: ValueKey('repository-gap-${group.identity.key}'),
                child: const SizedBox(height: 18),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ],
    );
  }

  Widget _memberSliver(List<InstalledSkill> skills, {required Key gridKey}) =>
      switch (widget.layout) {
        SkillListLayout.list => SliverList(
          key: gridKey,
          delegate: SliverChildBuilderDelegate((context, index) {
            final skill = skills[index];
            return Padding(
              key: ValueKey('skill-member-${skill.slotKey}'),
              padding: EdgeInsets.only(top: index == 0 ? 0 : _SkillRow.gap),
              child: _SkillRow(
                skill: skill,
                onTap: () => widget.onSkillTapped(skill.id),
              ),
            );
          }, childCount: skills.length),
        ),
        SkillListLayout.cards => SliverGrid(
          key: gridKey,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _SkillCard.maxWidth,
            mainAxisExtent: _SkillCard.height,
            mainAxisSpacing: _SkillCard.gap,
            crossAxisSpacing: _SkillCard.gap,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final skill = skills[index];
            return _SkillCard(
              key: ValueKey('skill-member-${skill.slotKey}'),
              skill: skill,
              onTap: () => widget.onSkillTapped(skill.id),
            );
          }, childCount: skills.length),
        ),
      };
}

class _RepositoryGroupHeader extends StatelessWidget {
  const _RepositoryGroupHeader({
    required this.group,
    required this.collapsed,
    required this.onPressed,
  });

  final SkillRepositoryGroup group;
  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final identity = group.identity;
    final l10n = context.l10n;
    final title = switch (identity.bucket) {
      SkillRepositoryBucket.repository => identity.title,
      SkillRepositoryBucket.local => l10n.browserLocalSources,
      SkillRepositoryBucket.web => l10n.browserWebSources,
      SkillRepositoryBucket.unknown => l10n.browserUnknownSources,
    };
    final palette = AppPalette.of(context);
    final typography = AppTypography.of(context);
    final count = Text(
      l10n.browserGroupSkillCount(group.skills.length),
      style: typography.caption,
    );
    return Semantics(
      expanded: !collapsed,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): onPressed,
          const SingleActivator(LogicalKeyboardKey.space): onPressed,
        },
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppGhostButton(
            key: ValueKey('repository-group-${identity.key}'),
            onPressed: onPressed,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 500;
                final titleWidget = AppTooltip(
                  message: identity.tooltip ?? title,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.subtitle,
                  ),
                );
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 350),
                      curve: Curves.easeOutQuart,
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: palette.bodyContent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      switch (identity.bucket) {
                        SkillRepositoryBucket.repository =>
                          identity.key.startsWith('git:local:')
                              ? LucideIcons.folderGit2
                              : LucideIcons.gitBranch,
                        SkillRepositoryBucket.local => LucideIcons.folder,
                        SkillRepositoryBucket.web => LucideIcons.link,
                        SkillRepositoryBucket.unknown => LucideIcons.circleHelp,
                      },
                      size: 16,
                      color: palette.bodyContent,
                    ),
                    const SizedBox(width: 8),
                    if (compact)
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [titleWidget, count],
                        ),
                      )
                    else ...[
                      Flexible(child: titleWidget),
                      const SizedBox(width: 10),
                      count,
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A list item: the same card as the grid's, stretched to a full-width strip
/// that fits a two-line description and wraps its Personal Tags.
class _SkillRow extends ConsumerWidget {
  const _SkillRow({required this.skill, required this.onTap});

  static const gap = 10.0;

  final InstalledSkill skill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedGroup = ref.watch(selectedInstalledAgentGroupProvider);
    return _SkillCardFrame(
      key: Key('skill-${skill.slotKey}'),
      skillId: skill.id.value,
      onTap: onTap,
      // A strip is several cards wide, so it grows by a similar few points.
      liftScale: 0.006,
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            skill.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.of(context).subtitle,
                          ),
                        ),
                        _SkillStatusIcons(skill: skill),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _SkillDescription(skill: skill, maxLines: 2),
                    _SkillTags(skill: skill, wrap: true),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (selectedGroup == null)
                _ActivationBadge(skill: skill)
              else
                _RowActivationSwitch(skill: skill, group: selectedGroup),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillCard extends ConsumerWidget {
  const _SkillCard({required this.skill, required this.onTap, super.key});

  // The grid keeps three columns until the content area is about 614
  // points wide (it was 734), so two columns no longer stretch into very
  // wide cards. In a full-width window the cards are unchanged.
  static const maxWidth = 300.0;
  static const height = 150.0;
  static const gap = 14.0;

  final InstalledSkill skill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedGroup = ref.watch(selectedInstalledAgentGroupProvider);
    return _SkillCardFrame(
      key: Key('skill-${skill.slotKey}'),
      skillId: skill.id.value,
      onTap: onTap,
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      skill.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.of(context).subtitle,
                    ),
                  ),
                  _SkillStatusIcons(skill: skill),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: _SkillDescription(skill: skill, maxLines: 3)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SkillTags(skill: skill),
                    ),
                  ),
                  selectedGroup == null
                      ? _ActivationBadge(skill: skill)
                      : _RowActivationSwitch(
                          skill: skill,
                          group: selectedGroup,
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card's frame. It lifts while hovered, and lifts the same way while the
/// command line works on its Skill, with a drifting colored glow in place of
/// the gray shadow.
class _SkillCardFrame extends ConsumerStatefulWidget {
  const _SkillCardFrame({
    required this.skillId,
    required this.onTap,
    required this.child,
    this.liftScale = 0.02,
    super.key,
  });

  /// `WorkspaceSkillId.value`.
  final String skillId;
  final VoidCallback onTap;

  /// How much larger the card grows when fully lifted.
  final double liftScale;
  final Widget child;

  @override
  ConsumerState<_SkillCardFrame> createState() => _SkillCardFrameState();
}

class _SkillCardFrameState extends ConsumerState<_SkillCardFrame>
    with TickerProviderStateMixin {
  // The light spreads out from behind the card's edge as the card lifts,
  // and fades in place as it leaves. It always finishes arriving first, so a
  // Skill the command line finishes in a few milliseconds still shows.
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..addStatusListener(_onArriveStatus);
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..addStatusListener(_onLeaveStatus);
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  // A press settles a lifted card halfway back. It always finishes settling
  // before it lifts again, so a quick click still shows.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 200),
  )..addStatusListener(_onPressStatus);
  bool _working = false;
  bool _hovered = false;
  bool _held = false;
  // A pointer that went down on a control inside the card, such as the
  // activation switch, which presses that control and not the card.
  int? _controlPointer;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      commandLineActivityProvider.select(
        (activity) =>
            activity?.itemFor(widget.skillId)?.status ==
            CommandLineItemStatus.running,
      ),
      (_, working) => _setWorking(working),
      fireImmediately: true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _syncDrift();
  }

  @override
  void dispose() {
    _arrive.dispose();
    _leave.dispose();
    _drift.dispose();
    _press.dispose();
    super.dispose();
  }

  // Pointer events rather than the tap's onTapDown, which a click shorter
  // than the press timeout only delivers on release.
  void _pressDown(PointerDownEvent event) {
    if (event.pointer == _controlPointer) return;
    if (event.buttons & kPrimaryButton == 0) return;
    _held = true;
    _press.forward();
  }

  void _pressUp(PointerEvent event) {
    if (event.pointer == _controlPointer) _controlPointer = null;
    if (!_held) return;
    _held = false;
    if (_press.isCompleted) _press.reverse();
  }

  void _onPressStatus(AnimationStatus status) {
    if (status.isCompleted && !_held) _press.reverse();
  }

  bool get _glowing => !_arrive.isDismissed;

  void _setWorking(bool working) {
    _working = working;
    if (working) {
      if (_leave.value > 0) {
        // Called back mid-departure: arrive again from what is still lit.
        _arrive.value = 1 - _leave.value;
        _leave.value = 0;
      }
      _arrive.forward();
      _syncDrift();
    } else {
      _leaveIfDone();
    }
  }

  void _leaveIfDone() {
    if (!_working && _arrive.isCompleted) _leave.forward();
  }

  void _onArriveStatus(AnimationStatus status) {
    if (status.isCompleted) _leaveIfDone();
  }

  void _onLeaveStatus(AnimationStatus status) {
    if (!status.isCompleted) return;
    _arrive.value = 0;
    _leave.value = 0;
    _syncDrift();
  }

  /// The glow drifts only while it shows, and never with reduced motion.
  void _syncDrift() {
    final drift = !_still && _glowing;
    if (drift && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!drift && _drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _pressDown,
    onPointerUp: _pressUp,
    onPointerCancel: _pressUp,
    child: GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _hovered ? 1 : 0),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          builder: (context, hover, child) => AnimatedBuilder(
            animation: Listenable.merge([_arrive, _leave, _drift, _press]),
            builder: (context, child) {
              final arrived = Curves.easeOutQuart.transform(_arrive.value);
              final left = _leave.value;
              // Light shows before it has spread, so the edge catches it first.
              final opacity =
                  const Interval(
                    0,
                    0.45,
                    curve: Curves.easeOut,
                  ).transform(_arrive.value) *
                  (1 - Curves.easeOutCubic.transform(left));
              final reach = _still ? 1.0 : arrived;
              final glow = arrived * (1 - Curves.easeOutCubic.transform(left));
              final press = Curves.easeOutCubic.transform(_press.value);
              // Pressed, the card stays lifted, shadow and all, but settles
              // halfway back to its resting size.
              final lift = math.max(math.max(hover, glow), press);
              final shade = math.max(hover, press) * (1 - glow);
              final grow = math.max(hover, glow) * (1 - press) + 0.5 * press;
              return Transform.scale(
                scale: 1 + widget.liftScale * grow,
                child: DecoratedBox(
                  decoration: AppCorners.smooth(
                    // White at rest; a hovered card fades to a faint gray toward
                    // its bottom edge, where the shadow falls.
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppPalette.of(context).white,
                        Color.lerp(
                          AppPalette.of(context).white,
                          AppPalette.of(context).surfaceMuted,
                          shade,
                        )!,
                      ],
                    ),
                    radius: AppRadii.dialog,
                    side: BorderSide(
                      color: Color.lerp(
                        AppPalette.of(context).border,
                        AppPalette.of(context).borderStrong,
                        lift,
                      )!,
                    ),
                    // The glow takes over from the gray shadow as it fades in.
                    shadows: [
                      if (shade > 0)
                        ...?BoxShadow.lerpList(
                          null,
                          AppShadows.of(context).hoveredCard,
                          shade,
                        ),
                      ...AppShadows.commandLineGlow(
                        opacity: opacity,
                        reach: reach,
                        turn: _drift.value,
                      ),
                    ],
                  ),
                  child: child,
                ),
              );
            },
            child: child,
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

/// Keeps a press on a control inside a Skill card from also pressing the
/// card. The control sees the pointer first, so it can claim it before the
/// card does.
class _CardControl extends StatelessWidget {
  const _CardControl({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) =>
        context
                .findAncestorStateOfType<_SkillCardFrameState>()
                ?._controlPointer =
            event.pointer,
    child: child,
  );
}

/// The Skill's Personal Tags: wrapped beneath a row's description, or a single
/// strip on a card, whose fixed height leaves room for only one line.
class _SkillTags extends ConsumerWidget {
  const _SkillTags({required this.skill, this.wrap = false});

  final InstalledSkill skill;
  final bool wrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (skill.personalTagIds.isEmpty) return const SizedBox.shrink();
    final tags = personalTagsFor(
      skill.personalTagIds,
      ref.watch(personalTagsProvider),
    );
    if (tags.isEmpty) return const SizedBox.shrink();
    if (!wrap) return PersonalTagStrip(tags: tags);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [for (final tag in tags) PersonalTagChip(tag, compact: true)],
      ),
    );
  }
}

class _TagFilterEmptyState extends StatelessWidget {
  const _TagFilterEmptyState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('browser-tag-filter-empty'),
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        context.l10n.tagsFilterEmpty,
        style: AppTypography.of(context).bodyMuted,
      ),
      const SizedBox(height: AppSpacing.md),
      AppButton(
        key: const Key('browser-clear-tag-filter'),
        label: context.l10n.tagsClearFilter,
        style: NeoButtonVariant.secondary,
        size: NeoButtonSize.small,
        onPressed: onClear,
      ),
    ],
  );
}

class _SkillDescription extends ConsumerWidget {
  const _SkillDescription({required this.skill, required this.maxLines});

  final InstalledSkill skill;
  final int maxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translatedDescription = switch (ref.watch(
      cachedSkillDescriptionProvider((
        slotKey: skill.slotKey,
        contentHash: skill.contentHash,
      )),
    )) {
      AsyncData(:final value) => value,
      _ => null,
    };
    return Text(
      translatedDescription ?? skill.description,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.of(context).control.copyWith(
        fontWeight: FontWeight.w400,
        color: AppPalette.of(context).textSecondary,
      ),
    );
  }
}

/// Same glyphs and colors as the detail page's favorite and update actions,
/// so the list previews those states.
class _SkillStatusIcons extends ConsumerWidget {
  const _SkillStatusIcons({required this.skill});

  final InstalledSkill skill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateAvailable = ref.watch(
      skillUpdateStatusProvider.select(
        (status) => status.stateOf(skill.id).updateAvailable,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (skill.isFavorite)
          _SkillStatusIcon(
            key: Key('skill-favorite-${skill.slotKey}'),
            icon: LucideIcons.star,
            color: AppPalette.of(context).warning,
            label: context.l10n.navFavorites,
          ),
        if (updateAvailable)
          _SkillStatusIcon(
            key: Key('skill-update-available-${skill.slotKey}'),
            icon: LucideIcons.circleArrowUp,
            color: AppPalette.of(context).success,
            label: context.l10n.workspaceUpdateAvailableAction,
          ),
      ],
    );
  }
}

class _SkillStatusIcon extends StatelessWidget {
  const _SkillStatusIcon({
    required this.icon,
    required this.color,
    required this.label,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
  }
}

class _RowActivationSwitch extends ConsumerWidget {
  const _RowActivationSwitch({required this.skill, required this.group});

  final InstalledSkill skill;
  final ActivationLocationGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = skill.activations.any(
      (activation) =>
          activationLocationKey(
            activation.scope,
            activation.projectRootId,
            activation.location,
          ) ==
          group.key,
    );
    final busy = ref.watch(
      skillOperationsViewModelProvider.select(
        (state) => state.isActivationBusy(skill.id, group.location),
      ),
    );
    if (busy) {
      return SizedBox.square(
        dimension: 24,
        child: CupertinoActivityIndicator(
          radius: 8,
          color: AppPalette.of(context).ink,
        ),
      );
    }

    final membership = ref.watch(deviceAgentMembersProvider);
    final unresolved = !group.canActivate;
    return _CardControl(
      child: AgentActivationSwitch(
        key: Key('skill-activation-toggle-${skill.slotKey}'),
        on: active,
        label:
            '${skill.displayName} ${activationAgentGroupTitle(context, group)}',
        onChanged:
            (unresolved && !active) ||
                membership.isLoading ||
                membership.hasError
            ? null
            : (value) => ref
                  .read(skillOperationsViewModelProvider.notifier)
                  .setActivation(
                    skillId: skill.id,
                    target: group.first,
                    agentIds: group.requestAgentIds,
                    active: value,
                    onTakeoverRequired: (draft) => showActivationTakeoverDialog(
                      context: context,
                      draft: draft,
                      agentName: activationAgentGroupTitle(context, group),
                    ),
                  ),
      ),
    );
  }
}

class _ActivationBadge extends ConsumerWidget {
  const _ActivationBadge({required this.skill});

  final InstalledSkill skill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selectedGroup = ref.watch(selectedInstalledAgentGroupProvider);
    final groups = selectedGroup == null
        ? ref.watch(installedAgentGroupsProvider)
        : [selectedGroup];
    final scope = ref.watch(installedScopeFilterProvider);
    final projectRootId = ref.watch(installedProjectRootFilterProvider);
    // The badge counts the same activation locations the current Scope offers.
    final reach = activationReachInScope(
      skill,
      groups: groups,
      scope: scope,
      projectRootId: projectRootId,
    );
    final isInactive = skillScopeState(skill).isInactive;
    if (reach.total == 0 && !isInactive) return const SizedBox.shrink();

    final active = activeGroupsInScope(
      skill,
      groups: groups,
      scope: scope,
      projectRootId: projectRootId,
    );
    final off = isInactive || reach.enabled == 0;
    final color = off
        ? AppPalette.of(context).textFaint
        : reach.enabled == reach.total
        ? AppPalette.of(context).textPrimary
        : AppPalette.of(context).bodyContent;
    final summary = isInactive
        ? l10n.browserInactive
        : l10n.browserActiveRatio(reach.enabled, reach.total);
    return AppTooltip(
      key: ValueKey('activation-badge-${skill.slotKey}'),
      message: summary,
      maxLines: null,
      content: active.isEmpty
          ? null
          : _ActiveAgentsTooltip(summary: summary, groups: active),
      child: Semantics(
        label: summary,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                off ? LucideIcons.botOff : LucideIcons.bot,
                size: 16,
                color: color,
              ),
              if (reach.total > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '${reach.enabled}/${reach.total}',
                  style: AppTypography.of(context).mono.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lists the Agents behind each occupied location under the badge summary.
class _ActiveAgentsTooltip extends StatelessWidget {
  const _ActiveAgentsTooltip({required this.summary, required this.groups});

  final String summary;
  final List<ActivationLocationGroup> groups;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.of(context).caption
        .copyWith(color: AppPalette.of(context).tooltipForeground);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary,
          style: style.copyWith(
            color: AppPalette.of(context).tooltipForeground
                .withValues(alpha: 0.7),
          ),
        ),
        for (final group in groups)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Brand marks are drawn for light surfaces, so give each a
                // white plate on the dark tooltip.
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: AppCorners.smooth(
                    color: AppPalette.of(context).agentChip,
                    radius: 6,
                  ),
                  child: group.shared || group.first.agentId.isEmpty
                      ? Icon(
                          LucideIcons.bot,
                          size: 14,
                          color: AppPalette.of(context).bodyContent,
                        )
                      : AgentLogo(agentId: group.first.agentId, size: 14),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    activationAgentGroupTitle(context, group),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AddSkillsButton extends StatelessWidget {
  const _AddSkillsButton({required this.buttonKey, required this.onTap});

  final Key buttonKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppButton(
      key: buttonKey,
      label: l10n.browserAddSkills,
      icon: LucideIcons.plus,
      style: NeoButtonVariant.primary,
      height: AppSizes.pageCommandBarHeight,
      onPressed: onTap,
    );
  }
}

class _AddFromSourceButton extends StatelessWidget {
  const _AddFromSourceButton({
    required this.buttonKey,
    required this.onPressed,
  });

  final Key buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      key: buttonKey,
      icon: LucideIcons.plus,
      tooltip: context.l10n.browserAddSkills,
      style: NeoButtonVariant.primary,
      size: AppSizes.pageCommandBarHeight,
      iconSize: AppSizes.iconLg,
      onPressed: onPressed,
    );
  }
}

enum _InstalledRefreshScanMode { scanning, refresh, manage }

class _InstalledRefreshScanAction extends StatelessWidget {
  const _InstalledRefreshScanAction({
    required this.mode,
    required this.unmanagedSlotCount,
    required this.onRefresh,
    required this.onManage,
  });

  static const _buttonKey = Key('installed-refresh-scan-action');
  static const _buttonChromeWidth = 54.0;
  static const _managementButtonMaxWidth = 260.0;
  static const _labelStyle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );

  final _InstalledRefreshScanMode mode;
  final int unmanagedSlotCount;
  final VoidCallback onRefresh;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      _InstalledRefreshScanMode.scanning => _iconButton(
        context,
        icon: LucideIcons.scanSearch,
        tooltip: context.l10n.externalSkillsScanning,
        onPressed: null,
      ),
      _InstalledRefreshScanMode.refresh => _iconButton(
        context,
        icon: LucideIcons.refreshCw,
        tooltip: context.l10n.browserRefreshRepository,
        onPressed: onRefresh,
      ),
      _InstalledRefreshScanMode.manage => _managementButton(context),
    };
  }

  Widget _iconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return AppIconButton(
      key: _buttonKey,
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      style: NeoButtonVariant.secondary,
      size: AppSizes.pageCommandBarHeight,
      iconSize: AppSizes.iconMd,
    );
  }

  Widget _managementButton(BuildContext context) {
    final fullLabel = context.l10n.browserUnmanagedSkillsFound(
      unmanagedSlotCount,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: const TextSpan(style: _labelStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..text = TextSpan(text: fullLabel, style: _labelStyle);
        textPainter.layout();
        final preferredWidth = textPainter.width + _buttonChromeWidth;
        textPainter.dispose();
        final availableWidth = constraints.maxWidth.isFinite
            ? math.min(constraints.maxWidth, _managementButtonMaxWidth)
            : _managementButtonMaxWidth;
        if (MediaQuery.sizeOf(context).width < 600) {
          return _iconButton(
            context,
            icon: LucideIcons.scanSearch,
            tooltip: fullLabel,
            onPressed: onManage,
          );
        }
        final buttonWidth = math.min(preferredWidth, availableWidth);

        return Semantics(
          button: true,
          enabled: true,
          label: fullLabel,
          onTap: onManage,
          child: ExcludeSemantics(
            child: SizedBox(
              width: buttonWidth,
              child: AppButton(
                key: _buttonKey,
                label: fullLabel,
                icon: LucideIcons.scanSearch,
                style: NeoButtonVariant.secondary,
                height: AppSizes.pageCommandBarHeight,
                textStyle: _labelStyle,
                onPressed: onManage,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sortMode,
    required this.onSortSelected,
    required this.groupingMode,
    required this.onGroupingSelected,
  });

  static const _scopeMenuMaxWidth = 320.0;
  static const _compactScopeMenuMaxWidth = 120.0;
  static const _searchWidth = 220.0;
  static const _compactSearchWidth = 140.0;

  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final SkillListSortMode sortMode;
  final ValueChanged<SkillListSortMode> onSortSelected;
  final SkillListGroupingMode groupingMode;
  final ValueChanged<SkillListGroupingMode> onGroupingSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final condensed = constraints.maxWidth < 320;
        // Recreate compact triggers when crossing the breakpoint: their new
        // width must not animate with the previous, wider trigger padding.
        final scopeSelector = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: compact ? _compactScopeMenuMaxWidth : _scopeMenuMaxWidth,
          ),
          child: KeyedSubtree(
            key: ValueKey('scope-trigger-condensed-$condensed'),
            child: _ScopeMenuButton(iconOnly: condensed),
          ),
        );
        return SizedBox(
          key: const Key('installed-filter-row'),
          height: AppSizes.controlHeight,
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: KeyedSubtree(
                    key: ValueKey('agent-trigger-condensed-$condensed'),
                    child: _AgentMenuButton(iconOnly: condensed),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _SearchMenuButton(
                value: searchQuery,
                expandedWidth: compact ? _compactSearchWidth : _searchWidth,
                onChanged: onSearchChanged,
              ),
              const SizedBox(width: AppSpacing.sm),
              _SortMenuButton(
                compactTrigger: condensed,
                sortMode: sortMode,
                onSelected: onSortSelected,
                groupingMode: groupingMode,
                onGroupingSelected: onGroupingSelected,
              ),
              const SizedBox(width: AppSpacing.sm),
              scopeSelector,
            ],
          ),
        );
      },
    );
  }
}

class _SortMenuButton extends ConsumerWidget {
  const _SortMenuButton({
    required this.sortMode,
    required this.onSelected,
    required this.groupingMode,
    required this.onGroupingSelected,
    this.compactTrigger = false,
  });

  final bool compactTrigger;
  static const _menuWidth = 252.0;
  static const _maxTriggerTags = 2;
  static const _sortHeaderHeight = 26.0;
  static const _optionHeight = 38.0;
  // The card's own padding around its content.
  static const _panelInset = 22.0;

  final SkillListSortMode sortMode;
  final ValueChanged<SkillListSortMode> onSelected;
  final SkillListGroupingMode groupingMode;
  final ValueChanged<SkillListGroupingMode> onGroupingSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(personalTagsProvider);
    final selectedTags = personalTagsFor(
      ref.watch(personalTagFilterProvider),
      tags,
    );
    final filtering = selectedTags.isNotEmpty;
    final baseStyle = SkillsButtonTheme.morphingMenuFor(context).style;
    final menuStyle = baseStyle.copyWith(
      buttonHeight: AppSizes.controlHeight,
      collapsedRadius: AppSizes.controlHeight / 2,
      minButtonWidth: AppSizes.controlHeight,
      triggerPadding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: AppTypography.of(context).control.copyWith(fontSize: 12.5),
      collapsedBackgroundColor: filtering
          ? AppPalette.of(context).surfaceMuted
          : baseStyle.collapsedBackgroundColor,
      borderColor: filtering
          ? AppPalette.of(context).textPrimary
          : baseStyle.borderColor,
    );
    final sortHeight =
        _sortHeaderHeight + SkillListSortMode.values.length * _optionHeight;
    final hidden = selectedTags.length - _maxTriggerTags;

    return MorphingMenuButton(
      key: const Key('skill-sort-button'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_sortIcon(sortMode), size: 16),
          const SizedBox(width: 8),
          Container(width: 1, height: 14, color: AppPalette.of(context).border),
          const SizedBox(width: 8),
          if (!filtering || compactTrigger)
            Icon(
              LucideIcons.tag,
              size: 14,
              color: AppPalette.of(context).bodyContent,
            )
          else ...[
            for (final tag in selectedTags.take(_maxTriggerTags))
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: PersonalTagChip(tag, compact: true),
              ),
            if (hidden > 0)
              Text('+$hidden', style: AppTypography.of(context).caption),
          ],
        ],
      ),
      label: null,
      semanticsLabel: context.l10n.browserSortGroupingTags,
      enableDragResize: false,
      direction: MorphingMenuDirection.down,
      alignment: MorphingMenuAlignment.end,
      expandedWidth: _menuWidth,
      expandedHeight:
          _panelInset +
          sortHeight +
          9 +
          _sortHeaderHeight +
          2 * _optionHeight +
          PersonalTagFilterPanel.tagSectionHeight(tags.length),
      style: menuStyle,
      contentBuilder: (menuContext, close) => PersonalTagFilterPanel(
        fixedSectionsHeight:
            sortHeight + 9 + _sortHeaderHeight + 2 * _optionHeight,
        groupingSection: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _sortHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.browserGrouping,
                    style: AppTypography.of(context).sectionLabel,
                  ),
                ),
              ),
            ),
            for (final mode in SkillListGroupingMode.values)
              AppMorphingMenuOption(
                key: ValueKey('skill-grouping-option-${mode.name}'),
                label: mode == SkillListGroupingMode.none
                    ? context.l10n.browserGroupingNone
                    : context.l10n.browserGroupingRepository,
                leading: Icon(
                  mode == SkillListGroupingMode.none
                      ? LucideIcons.list
                      : LucideIcons.folderGit2,
                  size: 16,
                ),
                selected: mode == groupingMode,
                onPressed: () {
                  onGroupingSelected(mode);
                  close();
                },
              ),
          ],
        ),
        sortSection: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _sortHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.browserSort,
                    style: AppTypography.of(context).sectionLabel,
                  ),
                ),
              ),
            ),
            for (final mode in SkillListSortMode.values)
              AppMorphingMenuOption(
                key: ValueKey('skill-sort-option-${mode.name}'),
                label: _sortLabel(context, mode),
                leading: Icon(_sortIcon(mode), size: 16),
                selected: mode == sortMode,
                onPressed: () {
                  onSelected(mode);
                  close();
                },
              ),
          ],
        ),
      ),
    );
  }
}

String _sortLabel(BuildContext context, SkillListSortMode mode) =>
    switch (mode) {
      SkillListSortMode.nameAscending => context.l10n.browserSortNameAscending,
      SkillListSortMode.nameDescending =>
        context.l10n.browserSortNameDescending,
      SkillListSortMode.recentlyAdded => context.l10n.browserSortRecentlyAdded,
      SkillListSortMode.oldestAdded => context.l10n.browserSortOldestAdded,
    };

IconData _sortIcon(SkillListSortMode mode) => switch (mode) {
  SkillListSortMode.nameAscending => LucideIcons.arrowUpAZ,
  SkillListSortMode.nameDescending => LucideIcons.arrowUpZA,
  SkillListSortMode.recentlyAdded => LucideIcons.clockArrowUp,
  SkillListSortMode.oldestAdded => LucideIcons.clockArrowDown,
};

class _AgentMenuButton extends ConsumerWidget {
  const _AgentMenuButton({required this.iconOnly});

  static const _buttonChromeWidth = 46.0;
  static const _buttonMaxWidth = 164.0;
  static const _menuWidth = 280.0;

  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(installedLocationFilterProvider);
    final scopeFilter = ref.watch(installedScopeFilterProvider);
    // Inactive Skills reach no Agent, so an Agent filter has nothing to say.
    if (scopeFilter == InstalledScopeFilter.inactive) {
      return const SizedBox.shrink();
    }
    final scope = scopeFilter == InstalledScopeFilter.global
        ? WorkspaceScope.global
        : WorkspaceScope.project;
    final rootId = scope == WorkspaceScope.global
        ? null
        : ref.watch(installedProjectRootFilterProvider);
    final inspection = ref.watch(
      activationTargetsProvider((scope: scope, projectRootId: rootId)),
    );
    final groups = ref.watch(installedAgentGroupsProvider);
    final membership = ref.watch(deviceAgentMembersProvider);
    if (!membership.isLoading &&
        !membership.hasError &&
        !inspection.isLoading &&
        !inspection.hasError &&
        inspection.value is WorkspaceCompleted &&
        selected.kind == InstalledLocationFilterKind.location &&
        !groups.any((g) => g.key == selected.key)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted &&
            ref.read(installedLocationFilterProvider).key == selected.key &&
            !ref
                .read(installedAgentGroupsProvider)
                .any((g) => g.key == selected.key)) {
          ref
              .read(installedLocationFilterProvider.notifier)
              .select(const InstalledLocationFilter.all());
        }
      });
    }
    final selectedGroup = ref.watch(selectedInstalledAgentGroupProvider);
    final label = switch (selected.kind) {
      InstalledLocationFilterKind.all => context.l10n.browserAllAgents,
      InstalledLocationFilterKind.location =>
        selectedGroup == null
            ? context.l10n.activationUnknownAgent
            : activationAgentGroupTitle(context, selectedGroup),
    };
    final leading =
        selectedGroup == null ||
            selectedGroup.shared ||
            selectedGroup.first.agentId.isEmpty
        ? const Icon(LucideIcons.bot, size: 16)
        : AgentLogo(agentId: selectedGroup.first.agentId, size: 16);
    final menuStyle = SkillsButtonTheme.morphingMenuFor(context).style.copyWith(
      buttonHeight: AppSizes.controlHeight,
      minButtonWidth: AppSizes.controlHeight,
      triggerPadding: EdgeInsets.symmetric(horizontal: iconOnly ? 9 : 11),
      textStyle: AppTypography.of(context).control.copyWith(fontSize: 12.5),
    );
    final buttonWidth = iconOnly
        ? 34.0
        : (TextPainter.computeWidth(
                    text: TextSpan(text: label, style: menuStyle.textStyle),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  ) +
                  _buttonChromeWidth)
              .clamp(34.0, _buttonMaxWidth)
              .toDouble();
    return SizedBox(
      width: buttonWidth,
      child: MorphingMenuButton(
        key: const Key('agent-selector'),
        leading: leading,
        label: iconOnly ? null : label,
        semanticsLabel: label,
        enableDragResize: false,
        direction: MorphingMenuDirection.down,
        expandedWidth: _menuWidth,
        expandedHeight:
            (groups.length * 38 + 74 + AppMorphingMenuDivider.height)
                .clamp(74, 320)
                .toDouble(),
        style: menuStyle,
        contentBuilder: (menuContext, close) => SingleChildScrollView(
          child: Column(
            children: [
              AppMorphingMenuOption(
                key: const Key('agent-option-all'),
                label: context.l10n.browserAllAgents,
                selected: selected.kind == InstalledLocationFilterKind.all,
                leading: const Icon(LucideIcons.bot, size: 16),
                onPressed: () {
                  ref
                      .read(installedLocationFilterProvider.notifier)
                      .select(const InstalledLocationFilter.all());
                  close();
                },
              ),
              const AppMorphingMenuDivider(),
              for (final group in groups)
                AppMorphingMenuOption(
                  key: ValueKey(group.key),
                  label: activationAgentGroupTitle(context, group),
                  selected: selected.key == group.key,
                  leading: group.shared || group.first.agentId.isEmpty
                      ? const Icon(LucideIcons.bot, size: 16)
                      : AgentLogo(agentId: group.first.agentId, size: 16),
                  onPressed: () {
                    ref
                        .read(installedLocationFilterProvider.notifier)
                        .select(InstalledLocationFilter.location(group.key));
                    close();
                  },
                ),
              if (inspection.hasError ||
                  inspection.value is WorkspaceFailed ||
                  membership.hasError)
                AppMorphingMenuOption(
                  label: context.l10n.commonRetry,
                  selected: false,
                  onPressed: () => ref
                      .read(activationCatalogRevisionProvider.notifier)
                      .refresh(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScopeMenuButton extends ConsumerWidget {
  const _ScopeMenuButton({required this.iconOnly});
  final bool iconOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(installedScopeFilterProvider);
    final rootId = ref.watch(installedProjectRootFilterProvider);
    return SkillScopeMenu(
      compact: true,
      collapsedRadius: AppSizes.controlHeight / 2,
      selection: switch (selected) {
        InstalledScopeFilter.inactive => const InactiveSkillScope(),
        InstalledScopeFilter.project when rootId != null => ProjectSkillScope(
          rootId,
        ),
        _ => const GlobalSkillScope(),
      },
      projectRoots: ref.watch(skillBrowserCatalogProvider).projectRoots,
      includeInactive: true,
      iconOnly: iconOnly,
      onManageProjects: () => context.pushNamed(AppRouteNames.projectRoots),
      onSelected: (value) {
        if (value case ProjectSkillScope(:final rootId)) {
          ref.read(installedProjectRootFilterProvider.notifier).select(rootId);
        }
        ref.read(installedScopeFilterProvider.notifier).select(switch (value) {
          GlobalSkillScope() => InstalledScopeFilter.global,
          ProjectSkillScope() => InstalledScopeFilter.project,
          InactiveSkillScope() => InstalledScopeFilter.inactive,
        });
        if (value is! ProjectSkillScope) {
          ref.read(installedProjectRootFilterProvider.notifier).select(null);
        }
      },
    );
  }
}

/// A round search button that grows in place into a search field. While a
/// query is active the collapsed button shows it, so the filter stays visible.
class _SearchMenuButton extends StatefulWidget {
  const _SearchMenuButton({
    required this.value,
    required this.expandedWidth,
    required this.onChanged,
  });

  static const _maxLabelWidth = 140.0;

  final String value;
  final double expandedWidth;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchMenuButton> createState() => _SearchMenuButtonState();
}

class _SearchMenuButtonState extends State<_SearchMenuButton> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SearchMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final searching = widget.value.isNotEmpty;
    final baseStyle = SkillsButtonTheme.morphingMenuFor(context).style;
    final style = baseStyle.copyWith(
      buttonHeight: AppSizes.controlHeight,
      minButtonWidth: AppSizes.controlHeight,
      collapsedRadius: AppSizes.controlHeight / 2,
      expandedRadius: AppSizes.controlHeight / 2,
      expandedShadow: baseStyle.collapsedShadow,
      // The theme's glyph centred in a controlHeight circle.
      triggerPadding: EdgeInsets.symmetric(
        horizontal: (AppSizes.controlHeight - baseStyle.iconSize) / 2,
      ),
      // The field's search glyph sits where the button's was, so the icon
      // stays put while the field opens to its left.
      panelPadding: EdgeInsets.only(
        left: 14,
        right: (AppSizes.controlHeight - baseStyle.iconSize) / 2,
      ),
      textStyle: AppTypography.of(context).control.copyWith(fontSize: 12.5),
      collapsedBackgroundColor: searching
          ? AppPalette.of(context).surfaceMuted
          : baseStyle.collapsedBackgroundColor,
      borderColor: searching
          ? AppPalette.of(context).textPrimary
          : baseStyle.borderColor,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: _SearchMenuButton._maxLabelWidth,
      ),
      child: MorphingMenuButton(
        key: const Key('installed-search-control'),
        icon: LucideIcons.search,
        label: searching ? widget.value : null,
        semanticsLabel: l10n.browserSearchSkills,
        tooltip: l10n.browserSearchSkills,
        enableDragResize: false,
        direction: MorphingMenuDirection.inPlace,
        alignment: MorphingMenuAlignment.end,
        expandedWidth: widget.expandedWidth,
        style: style,
        contentBuilder: (menuContext, close) => CupertinoTextField(
          key: const Key('installed-search-field'),
          controller: _controller,
          autofocus: true,
          onChanged: widget.onChanged,
          onSubmitted: (_) => close(),
          padding: EdgeInsets.zero,
          // The glyph and the clear button share the trailing slot: the glyph
          // while the field is empty, the clear button once there is text.
          suffix: Padding(
            padding: EdgeInsets.only(left: AppSpacing.sm),
            child: Icon(
              LucideIcons.search,
              size: 15,
              color: AppPalette.of(context).textSecondary,
            ),
          ),
          suffixMode: OverlayVisibilityMode.notEditing,
          clearButtonMode: OverlayVisibilityMode.editing,
          style: AppTypography.of(context).control.copyWith(
            fontWeight: FontWeight.w400,
            color: AppPalette.of(context).ink,
          ),
          placeholder: l10n.browserSearchSkills,
          placeholderStyle: AppTypography.of(context).control.copyWith(
            fontWeight: FontWeight.w400,
            color: AppPalette.of(context).textSecondary,
          ),
          decoration: null,
        ),
      ),
    );
  }
}

/// The page while the catalog first loads: the header, then gray stand-ins
/// for the filter bar and for Skills in the chosen layout, with a light
/// sweeping across them.
class _LoadingBody extends StatefulWidget {
  const _LoadingBody({required this.layout, required this.favoritesOnly});

  static const _cardCount = 9;
  static const _rowCount = 6;

  final SkillListLayout layout;
  final bool favoritesOnly;

  @override
  State<_LoadingBody> createState() => _LoadingBodyState();
}

class _LoadingBodyState extends State<_LoadingBody> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = AppScrollControllers.create(
      debugLabel: 'installed-skills-loading',
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return KeyedSubtree(
      key: const Key('browser-loading'),
      child: AppPageTemplate(
        controller: _scrollController,
        breadcrumb: l10n.commonSectionBreadcrumb,
        breadcrumbIcon: widget.favoritesOnly
            ? NavSection.favorites.icon
            : NavSection.installed.icon,
        title: widget.favoritesOnly ? l10n.navFavorites : l10n.browserInstalled,
        slivers: [
          const AppPageSliverContent(
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.lg),
                child: _FilterBarSkeleton(),
              ),
            ),
          ),
          AppPageSliverContent(
            sliver: switch (widget.layout) {
              SkillListLayout.list => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: EdgeInsets.only(
                      top: index == 0 ? 0 : _SkillRow.gap,
                    ),
                    child: _SkillRowSkeleton(index: index),
                  ),
                  childCount: _LoadingBody._rowCount,
                ),
              ),
              SkillListLayout.cards => SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _SkillCard.maxWidth,
                  mainAxisExtent: _SkillCard.height,
                  mainAxisSpacing: _SkillCard.gap,
                  crossAxisSpacing: _SkillCard.gap,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _SkillCardSkeleton(index: index),
                  childCount: _LoadingBody._cardCount,
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// The Agent menu on the left; search, sort with tags, and Scope on the
/// right, at the sizes of the real controls.
class _FilterBarSkeleton extends StatelessWidget {
  const _FilterBarSkeleton();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: AppSizes.controlHeight,
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _SkeletonBone(
              width: 108,
              height: AppSizes.controlHeight,
              radius: AppRadii.lg,
            ),
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        _SkeletonBone(
          width: AppSizes.controlHeight,
          height: AppSizes.controlHeight,
          radius: AppRadii.pill,
        ),
        SizedBox(width: AppSpacing.sm),
        _SkeletonBone(
          width: 62,
          height: AppSizes.controlHeight,
          radius: AppRadii.pill,
        ),
        SizedBox(width: AppSpacing.sm),
        _SkeletonBone(
          width: 66,
          height: AppSizes.controlHeight,
          radius: AppRadii.pill,
        ),
      ],
    ),
  );
}

/// Title widths vary from Skill to Skill so the stand-ins read as a list
/// rather than one repeated card.
const _skeletonTitleWidths = [0.5, 0.68, 0.42, 0.6, 0.36, 0.56];

class _SkillRowSkeleton extends StatelessWidget {
  const _SkillRowSkeleton({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => _SkeletonFrame(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonBone(
          widthFactor:
              _skeletonTitleWidths[index % _skeletonTitleWidths.length] * 0.6,
          height: 14,
        ),
        const SizedBox(height: 10),
        const _SkeletonBone(widthFactor: 0.9, height: 10),
        const SizedBox(height: 8),
        const _SkeletonBone(widthFactor: 0.6, height: 10),
      ],
    ),
  );
}

class _SkillCardSkeleton extends StatelessWidget {
  const _SkillCardSkeleton({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => _SkeletonFrame(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonBone(
          widthFactor:
              _skeletonTitleWidths[index % _skeletonTitleWidths.length],
          height: 14,
        ),
        const SizedBox(height: 14),
        const _SkeletonBone(height: 10),
        const SizedBox(height: 8),
        const _SkeletonBone(height: 10),
        const SizedBox(height: 8),
        const _SkeletonBone(widthFactor: 0.7, height: 10),
        const Spacer(),
        const _SkeletonBone(width: 44, height: 18, radius: AppRadii.xs),
      ],
    ),
  );
}

/// A Skill card's resting frame around stand-ins. The light sweeps across
/// the whole card, clipped to its corners: the package's gradient grays
/// slightly where it fades, so a smaller sweep would show its edge. The
/// border is drawn above the light so it stays as crisp as a real card's.
class _SkeletonFrame extends StatelessWidget {
  const _SkeletonFrame({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final background = AppCorners.smooth(
      color: AppPalette.of(context).white,
      radius: AppRadii.dialog,
    );
    return DecoratedBox(
      decoration: background,
      position: DecorationPosition.background,
      child: DecoratedBox(
        decoration: AppCorners.smooth(
          radius: AppRadii.dialog,
          side: BorderSide(color: AppPalette.of(context).border),
        ),
        position: DecorationPosition.foreground,
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: background.shape),
          child: Shimmer(
            // Every stand-in starts together, so the sweeps stay in step.
            enabled: !MediaQuery.disableAnimationsOf(context),
            duration: const Duration(milliseconds: 1600),
            colorOpacity: 0.8,
            direction: const ShimmerDirection.fromLeftToRight(),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBone extends StatelessWidget {
  const _SkeletonBone({
    this.width,
    this.widthFactor,
    required this.height,
    this.radius = AppRadii.xs,
  });

  final double? width;
  final double? widthFactor;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bone = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppPalette.of(context).surfacePressed,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (width != null) return bone;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor ?? 1,
      child: bone,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    this.onAdd,
    required this.onDiscover,
    this.unmanagedSlotCount = 0,
  });

  final VoidCallback? onAdd;
  final VoidCallback onDiscover;

  /// Skills the launch scan found in Agent folders. Most people arrive with
  /// some already, and taking those over is the shortest way to a first
  /// managed Skill, so it becomes the primary action.
  final int unmanagedSlotCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasExisting = unmanagedSlotCount > 0;
    return Center(
      key: const Key('browser-empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.arrowDownToLine,
            size: 40,
            color: AppPalette.of(context).controlInactive,
          ),
          const SizedBox(height: 20),
          Text(l10n.browserNoSkillsYet, style: AppTypography.of(context).title),
          const SizedBox(height: 8),
          Text(
            hasExisting
                ? l10n.browserEmptyExistingDescription(unmanagedSlotCount)
                : l10n.browserEmptyDescription,
            key: const Key('browser-empty-description'),
            textAlign: TextAlign.center,
            style: AppTypography.of(context).bodyMuted.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          MyButtonGroup(
            children: [
              if (hasExisting)
                AppButton(
                  key: const Key('empty-discover-skills'),
                  label: l10n.browserTakeOverExistingSkills,
                  icon: LucideIcons.scanSearch,
                  style: NeoButtonVariant.primary,
                  height: AppSizes.pageCommandBarHeight,
                  onPressed: onDiscover,
                ),
              if (onAdd != null)
                hasExisting
                    ? AppButton(
                        key: const Key('empty-add-skills'),
                        label: l10n.browserAddSkills,
                        icon: LucideIcons.plus,
                        height: AppSizes.pageCommandBarHeight,
                        onPressed: onAdd,
                      )
                    : _AddSkillsButton(
                        buttonKey: const Key('empty-add-skills'),
                        onTap: onAdd!,
                      ),
              if (!hasExisting)
                AppButton(
                  key: const Key('empty-discover-skills'),
                  label: l10n.browserDiscoverExistingSkills,
                  icon: LucideIcons.scanSearch,
                  height: AppSizes.pageCommandBarHeight,
                  onPressed: onDiscover,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    this.stateKey,
    required this.icon,
    required this.title,
    required this.message,
  });

  final Key? stateKey;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: stateKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: AppPalette.of(context).textSecondary),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.of(context).title,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.of(context).bodyMuted
                    .copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
