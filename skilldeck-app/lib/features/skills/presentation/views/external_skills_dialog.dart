import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo.dart';
import 'package:skills_manager/features/skills/presentation/view_models/external_skills_view_model.dart';
import 'package:skills_manager/l10n/app_failure_l10n.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/l10n/workspace_operation_l10n.dart';
import 'package:skills_manager/shared/platform/file_location_opener.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_operation_feedback.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';

class ExternalSkillsDialog extends ConsumerStatefulWidget {
  const ExternalSkillsDialog({super.key});

  @override
  ConsumerState<ExternalSkillsDialog> createState() =>
      _ExternalSkillsDialogState();
}

class _ExternalSkillsDialogState extends ConsumerState<ExternalSkillsDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Always scan on open. The launch-time scan can be hours old, and the
      // Agents keep writing to their folders, so adopting from it fails as
      // stale. The previous list stays visible while the new scan runs.
      final state = ref.read(externalSkillsViewModelProvider);
      if (!state.busy) {
        unawaited(ref.read(externalSkillsViewModelProvider.notifier).scan());
      }
    });
  }

  /// Whether the user opened the full list to pick Skills one by one.
  bool _choosing = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(externalSkillsViewModelProvider);
    final viewModel = ref.read(externalSkillsViewModelProvider.notifier);
    return PopScope(
      // A scan only reads folders, so closing never waits for it.
      canPop: !state.adopting,
      child: AppDialogScaffold(
        key: const Key('external-skills-dialog'),
        width: AppDialogWidths.standard,
        onEscape: state.adopting ? null : context.pop,
        header: _Header(
          state: state,
          viewModel: viewModel,
          onClose: context.pop,
        ),
        sections: [
          _Body(
            state: state,
            viewModel: viewModel,
            choosing: _choosing,
            onChoose: () => setState(() => _choosing = true),
          ),
        ],
        footer: _Footer(
          state: state,
          viewModel: viewModel,
          choosing: _choosing,
          onChoosingChanged: (value) => setState(() => _choosing = value),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.viewModel,
    required this.onClose,
  });

  final ExternalSkillsState state;
  final ExternalSkillsViewModel viewModel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final count = state.unmanagedSlotCount;
    final reviewing =
        count > 0 &&
        (state.status == ExternalSkillsStatus.ready ||
            state.status == ExternalSkillsStatus.confirming ||
            state.status == ExternalSkillsStatus.scanning);
    return AppDialogHeader(
      icon: LucideIcons.folderSearch,
      title: reviewing
          ? context.l10n.externalSkillsFoundTitle(count)
          : context.l10n.externalSkillsTitle,
      titleKey: const Key('external-skills-title'),
      subtitle: context.l10n.externalSkillsDescription,
      actions: [
        // The scan runs in the background: its only sign is here, and the
        // review below stays usable.
        if (state.scanning)
          const SizedBox.square(
            key: Key('external-skills-scanning-indicator'),
            dimension: 34,
            child: Center(child: CupertinoActivityIndicator(radius: 7)),
          )
        else if (!state.adopting)
          AppIconButton(
            key: const Key('external-skills-rescan'),
            icon: LucideIcons.refreshCw,
            tooltip: context.l10n.externalSkillsRescan,
            style: NeoButtonVariant.ghost,
            onPressed: () => unawaited(viewModel.scan()),
          ),
        appDialogCloseButton(
          context,
          key: const Key('external-skills-close'),
          onPressed: state.adopting ? null : onClose,
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.viewModel,
    required this.choosing,
    required this.onChoose,
  });

  final ExternalSkillsState state;
  final ExternalSkillsViewModel viewModel;
  final bool choosing;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    if (state.status == ExternalSkillsStatus.scanning &&
        state.discovery == null) {
      return AppDialogSection(
        child: _CenteredState(
          stateKey: const Key('external-skills-scanning'),
          icon: const CupertinoActivityIndicator(radius: 10),
          title: context.l10n.externalSkillsScanning,
        ),
      );
    }
    if (state.status == ExternalSkillsStatus.adopting) {
      return AppDialogSection(
        child: _AdoptingState(state: state, viewModel: viewModel),
      );
    }
    if (state.status == ExternalSkillsStatus.success) {
      return AppDialogSection(
        child: _TerminalState(
          stateKey: const Key('external-skills-success'),
          icon: LucideIcons.circleCheck,
          color: AppPalette.of(context).success,
          title: context.l10n.externalSkillsSuccess,
          message: context.l10n.externalSkillsCompletedCount(
            state.completedSlotKeys.length,
            state.adoptionTotal,
          ),
        ),
      );
    }
    if (state.status == ExternalSkillsStatus.cancelled) {
      return AppDialogSection(
        child: _TerminalState(
          stateKey: const Key('external-skills-cancelled'),
          icon: LucideIcons.circleStop,
          color: AppPalette.of(context).textSecondary,
          title: context.l10n.externalSkillsCancelled,
          message: context.l10n.externalSkillsCompletedCount(
            state.completedSlotKeys.length,
            state.adoptionTotal,
          ),
        ),
      );
    }
    if (state.scanFailed) {
      if (state.failure case final failure?) {
        return AppDialogSection(
          child: AppFailureView(
            key: const Key('external-skills-failure'),
            failure: failure,
            variant: AppFailureViewVariant.centered,
            title: context.l10n.externalSkillsScanFailed,
            onAction: () => unawaited(viewModel.scan()),
          ),
        );
      }
      return AppDialogSection(
        child: _TerminalState(
          stateKey: const Key('external-skills-failure'),
          icon: LucideIcons.circleAlert,
          color: AppPalette.of(context).danger,
          title: context.l10n.externalSkillsScanFailed,
          message: state.failure == null
              ? context.l10n.errorUnknown
              : localizeAppFailure(context.l10n, state.failure!),
        ),
      );
    }
    if (state.status == ExternalSkillsStatus.partial ||
        (state.status == ExternalSkillsStatus.failure &&
            state.failedAdoptions.length > 1)) {
      final partial = state.status == ExternalSkillsStatus.partial;
      return AppDialogSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TerminalState(
              stateKey: partial
                  ? const Key('external-skills-partial')
                  : const Key('external-skills-failure'),
              icon: partial
                  ? LucideIcons.triangleAlert
                  : LucideIcons.circleAlert,
              color: partial
                  ? AppPalette.of(context).warning
                  : AppPalette.of(context).danger,
              title: partial
                  ? context.l10n.externalSkillsPartial
                  : context.l10n.externalSkillsAdoptionFailed,
              message: context.l10n.externalSkillsCompletedCount(
                state.completedSlotKeys.length,
                state.adoptionTotal,
              ),
            ),
            if (state.failedAdoptions.isNotEmpty) ...[
              const SizedBox(height: 16),
              _FailedAdoptionList(failures: state.failedAdoptions),
            ],
          ],
        ),
      );
    }
    if (state.status == ExternalSkillsStatus.failure) {
      if (state.failure case final failure?) {
        return AppDialogSection(
          child: AppFailureView(
            key: const Key('external-skills-failure'),
            failure: failure,
            variant: AppFailureViewVariant.centered,
            title: context.l10n.externalSkillsAdoptionFailed,
            onAction: () => unawaited(viewModel.scan()),
          ),
        );
      }
      return AppDialogSection(
        child: _TerminalState(
          stateKey: const Key('external-skills-failure'),
          icon: LucideIcons.circleAlert,
          color: AppPalette.of(context).danger,
          title: context.l10n.externalSkillsAdoptionFailed,
          message: state.failure == null
              ? context.l10n.errorUnknown
              : localizeAppFailure(context.l10n, state.failure!),
        ),
      );
    }

    final discovery = state.discovery;
    if (discovery == null || discovery.isEmpty) {
      return AppDialogSection(
        child: _CenteredState(
          stateKey: const Key('external-skills-empty'),
          icon: Icon(
            LucideIcons.circleCheck,
            size: 24,
            color: AppPalette.of(context).success,
          ),
          title: context.l10n.externalSkillsEmpty,
          detail: context.l10n.externalSkillsEmptyDescription,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.rescannedAfterChange && !state.scanning) ...[
          AppDialogSection(
            child: _RescannedNotice(
              message: context.l10n.externalSkillsRescanned,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (choosing)
          _ChooseList(state: state, discovery: discovery, viewModel: viewModel)
        else
          _Overview(
            state: state,
            discovery: discovery,
            viewModel: viewModel,
            onChoose: onChoose,
          ),
      ],
    );
  }
}

/// The review at a glance: totals, then only the choices the user has to
/// make. Skills that can move as they are stay one row away.
class _Overview extends StatelessWidget {
  const _Overview({
    required this.state,
    required this.discovery,
    required this.viewModel,
    required this.onChoose,
  });

  final ExternalSkillsState state;
  final ExternalSkillsDiscovery discovery;
  final ExternalSkillsViewModel viewModel;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final candidates = _sortedCandidates(discovery);
    final conflicts = _sortedConflicts(discovery);
    return Column(
      key: const Key('external-skills-ready'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogSection(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Container(
            key: const Key('external-summary'),
            child: Row(
              children: [
                for (final (index, tile) in [
                  _SummaryTile(
                    key: const Key('external-summary-total'),
                    icon: LucideIcons.folderSearch,
                    color: AppPalette.of(context).textSecondary,
                    label: l10n.externalSkillsSummaryTotal,
                    count: discovery.uniqueSlotCount,
                  ),
                  _SummaryTile(
                    key: const Key('external-summary-ready'),
                    icon: LucideIcons.circleCheck,
                    color: AppPalette.of(context).success,
                    label: l10n.externalSkillsSummaryReady,
                    count: candidates.length,
                  ),
                  _SummaryTile(
                    key: const Key('external-summary-conflicts'),
                    icon: LucideIcons.gitCompare,
                    color: AppPalette.of(context).warning,
                    label: l10n.externalSkillsSummaryConflicts,
                    count: conflicts.length,
                  ),
                ].indexed) ...[
                  if (index > 0)
                    SizedBox(
                      width: 1,
                      height: 36,
                      child: ColoredBox(color: AppPalette.of(context).border),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: index == 0 ? 0 : 16,
                        end: 16,
                      ),
                      child: tile,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (conflicts.isNotEmpty)
          AppDialogSection(
            title: l10n.externalSkillsDecideTitle,
            subtitle: l10n.externalSkillsDecideSubtitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                for (final conflict in conflicts)
                  _ConflictRow(
                    conflict: conflict,
                    state: state,
                    viewModel: viewModel,
                  ),
              ],
            ),
          ),
        if (candidates.isNotEmpty)
          _ReadyDisclosure(
            candidates: candidates,
            afterConflicts: conflicts.isNotEmpty,
            onTap: onChoose,
          ),
      ],
    );
  }
}

/// Every Skill with its own checkbox, for unchecking some before taking over.
class _ChooseList extends StatelessWidget {
  const _ChooseList({
    required this.state,
    required this.discovery,
    required this.viewModel,
  });

  final ExternalSkillsState state;
  final ExternalSkillsDiscovery discovery;
  final ExternalSkillsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final candidates = _sortedCandidates(discovery);
    final conflicts = _sortedConflicts(discovery);
    // A conflict joins "select all" only once it has a chosen version.
    final selectable = {
      for (final candidate in candidates) candidate.slotKey,
      for (final conflict in conflicts)
        if (conflict.locations.contains(
          state.authoritativeLocations[conflict.slotKey],
        ))
          conflict.slotKey,
    };
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every(state.selectedSlotKeys.contains);
    return AppDialogSection(
      child: _Bordered(
        key: const Key('external-skills-list'),
        children: [
          ColoredBox(
            color: AppPalette.of(context).surfaceSubtle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  CupertinoCheckbox(
                    key: const Key('external-select-all'),
                    value: allSelected,
                    onChanged: state.adopting
                        ? null
                        : (value) {
                            for (final slotKey in selectable) {
                              viewModel.setSelected(
                                slotKey,
                                selected: value ?? false,
                              );
                            }
                          },
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.externalSkillsSelectAll,
                      style: AppTypography.of(context).caption
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    l10n.externalSkillsAgentsColumn,
                    style: AppTypography.of(context).caption
                        .copyWith(fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
          for (final conflict in conflicts)
            _ConflictRow(
              conflict: conflict,
              state: state,
              viewModel: viewModel,
              selectable: true,
            ),
          for (final candidate in candidates)
            _CandidateRow(
              candidate: candidate,
              selected: state.selectedSlotKeys.contains(candidate.slotKey),
              onChanged: state.adopting
                  ? null
                  : (selected) => viewModel.setSelected(
                      candidate.slotKey,
                      selected: selected,
                    ),
            ),
        ],
      ),
    );
  }
}

List<ExternalSkillCandidate> _sortedCandidates(
  ExternalSkillsDiscovery discovery,
) =>
    [...discovery.candidates]
      ..sort((left, right) => left.slotKey.compareTo(right.slotKey));

List<ExternalSkillConflict> _sortedConflicts(
  ExternalSkillsDiscovery discovery,
) =>
    [...discovery.conflicts]
      ..sort((left, right) => left.slotKey.compareTo(right.slotKey));

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.of(context).caption
                  .copyWith(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        context.l10n.externalSkillsSummaryCount(count),
        style: AppTypography.of(context).subtitle
            .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

/// Rows separated by hairlines inside one outlined table, so the header
/// band reads as part of the list rather than floating above it.
class _Bordered extends StatelessWidget {
  const _Bordered({required this.children, super.key});

  final List<Widget> children;

  static const _radius = 10.0;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: AppCorners.smooth(
      color: AppPalette.of(context).surface,
      radius: _radius,
    ),
    // The outline sits on top so the header band cannot paint over it.
    foregroundDecoration: AppCorners.smooth(
      radius: _radius,
      side: BorderSide(color: AppPalette.of(context).border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0)
            SizedBox(
              height: 1,
              child: ColoredBox(color: AppPalette.of(context).border),
            ),
          child,
        ],
      ],
    ),
  );
}

class _ConflictRow extends ConsumerWidget {
  const _ConflictRow({
    required this.conflict,
    required this.state,
    required this.viewModel,
    this.selectable = false,
  });

  final ExternalSkillConflict conflict;
  final ExternalSkillsState state;
  final ExternalSkillsViewModel viewModel;
  final bool selectable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      key: Key('external-conflict-${conflict.slotKey}'),
      // In the overview the rows sit flush with the section title; in the
      // choose list they share the inset of the checkbox rows around them.
      padding: selectable
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 9)
          : EdgeInsets.zero,
      child: Row(
        children: [
          if (selectable) ...[
            CupertinoCheckbox(
              key: Key('external-select-${conflict.slotKey}'),
              value: state.selectedSlotKeys.contains(conflict.slotKey),
              onChanged: state.adopting
                  ? null
                  : (value) => viewModel.setSelected(
                      conflict.slotKey,
                      selected: value ?? false,
                    ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conflict.slotKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.of(context).control.copyWith(
                    color: AppPalette.of(context).ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.externalSkillsConflictCopies(
                    conflict.locations.length,
                  ),
                  style: AppTypography.of(context).caption
                      .copyWith(fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _VersionPicker(
            conflict: conflict,
            authority: state.authoritativeLocations[conflict.slotKey],
            enabled: !state.adopting,
            onSelected: (location) =>
                viewModel.selectAuthority(conflict.slotKey, location),
          ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.selected,
    required this.onChanged,
  });

  final ExternalSkillCandidate candidate;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    key: Key('external-candidate-${candidate.slotKey}'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: Row(
      children: [
        CupertinoCheckbox(
          key: Key('external-select-${candidate.slotKey}'),
          value: selected,
          onChanged: onChanged == null
              ? null
              : (value) => onChanged!(value ?? false),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                candidate.declaredName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.of(context).control.copyWith(
                  color: AppPalette.of(context).ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (candidate.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  candidate.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.of(context).caption
                      .copyWith(fontWeight: FontWeight.w400),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        AgentLogoStack(agentIds: candidate.agentIds, logoSize: 22, overlap: 6),
      ],
    ),
  );
}

/// "12 more can be taken over directly", opening the full list.
class _ReadyDisclosure extends StatelessWidget {
  const _ReadyDisclosure({
    required this.candidates,
    required this.afterConflicts,
    required this.onTap,
  });

  final List<ExternalSkillCandidate> candidates;
  final bool afterConflicts;
  final VoidCallback onTap;

  static const _previewCount = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final names = candidates
        .take(_previewCount)
        .map((candidate) => candidate.slotKey)
        .join(l10n.externalSkillsNameSeparator);
    return AppDialogSection(
      title: afterConflicts
          ? l10n.externalSkillsRestTitle(candidates.length)
          : l10n.externalSkillsReadyTitle(candidates.length),
      trailing: CupertinoButton(
        key: const Key('external-skills-view-all'),
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        pressedOpacity: 0.72,
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.externalSkillsViewAll,
              style: AppTypography.of(context).caption,
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 14,
              color: AppPalette.of(context).textSecondary,
            ),
          ],
        ),
      ),
      child: Text(
        candidates.length > _previewCount
            ? l10n.externalSkillsNamesMore(names)
            : names,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.of(context).caption,
      ),
    );
  }
}

/// Picks which copy of a conflicting Skill to keep, by Agent, in the App's
/// standard pop-up card. Each option can reveal its folder.
class _VersionPicker extends ConsumerWidget {
  const _VersionPicker({
    required this.conflict,
    required this.authority,
    required this.enabled,
    required this.onSelected,
  });

  final ExternalSkillConflict conflict;
  final String? authority;
  final bool enabled;
  final ValueChanged<String> onSelected;

  static const _menuWidth = 240.0;
  static const _minWidth = 140.0;
  static const _headerHeight = 26.0;
  static const _optionHeight = 38.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final agents =
        ref.watch(deviceAgentCatalogProvider).value ??
        const <WorkspaceAgentInfo>[];
    final locations = [...conflict.locations]..sort();
    final selected = locations.contains(authority) ? authority : null;
    String nameOf(String location) => _locationAgentName(
      l10n,
      agents,
      location,
      conflict.agentIdsByLocation[location] ?? const [],
    );
    String? sharedBy(String location) {
      final ids = conflict.agentIdsByLocation[location] ?? const [];
      return _isSharedFolder(ids)
          ? l10n.externalSkillsSharedBy(ids.length)
          : null;
    }

    Widget logoOf(String location, double size) {
      final ids = conflict.agentIdsByLocation[location] ?? const [];
      return ids.length == 1 && ids.single != universalAgentId
          ? AgentLogo(agentId: ids.single, size: size)
          : Icon(
              LucideIcons.folder,
              size: size - 2,
              color: AppPalette.of(context).bodyContent,
            );
    }

    final label = selected == null
        ? l10n.externalSkillsChooseVersion
        : nameOf(selected);
    final base = SkillsButtonTheme.morphingMenuFor(context).style;
    final style = base.copyWith(
      buttonHeight: 30,
      minButtonWidth: 30,
      collapsedRadius: 9,
      triggerPadding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: AppTypography.of(context).control.copyWith(
        color: AppPalette.of(context).ink,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      // An unchosen version is flagged by its warning icon alone; the
      // trigger stays white like every other button.
    );
    final width =
        (TextPainter.computeWidth(
                  text: TextSpan(text: label, style: style.textStyle),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                ) +
                54)
            // A shared minimum keeps the pickers one column wide down the list.
            .clamp(_minWidth, 200.0)
            .toDouble();
    return IgnorePointer(
      ignoring: !enabled,
      child: SizedBox(
        width: width,
        child: MorphingMenuButton(
          key: Key('external-version-${conflict.slotKey}'),
          leading: selected == null
              ? Icon(
                  LucideIcons.gitCompare,
                  size: 14,
                  color: AppPalette.of(context).warning,
                )
              : logoOf(selected, 16),
          label: label,
          semanticsLabel: label,
          enableDragResize: false,
          direction: MorphingMenuDirection.down,
          alignment: MorphingMenuAlignment.end,
          expandedWidth: _menuWidth,
          expandedHeight:
              (_headerHeight +
                      locations.fold<double>(
                        0,
                        (sum, location) =>
                            sum +
                            (sharedBy(location) == null ? _optionHeight : 54),
                      ) +
                      12)
                  .clamp(76.0, 320.0)
                  .toDouble(),
          style: style,
          contentBuilder: (menuContext, close) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _headerHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.externalSkillsVersionMenuTitle,
                        style: AppTypography.of(context).caption.copyWith(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                for (final location in locations)
                  AppMorphingMenuOption(
                    key: Key(
                      'external-authority-${conflict.slotKey}-$location',
                    ),
                    label: nameOf(location),
                    subtitle: sharedBy(location),
                    selected: location == selected,
                    leading: logoOf(location, 18),
                    accessory: _OpenFolderButton(
                      key: Key('external-open-${conflict.slotKey}-$location'),
                      location: location,
                    ),
                    onPressed: () {
                      onSelected(location);
                      close();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the Skill's folder in the file manager, without choosing it.
class _OpenFolderButton extends ConsumerWidget {
  const _OpenFolderButton({required this.location, super.key});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppIconButton(
    icon: LucideIcons.folderOpen,
    tooltip: context.l10n.externalSkillsOpenFolder,
    style: NeoButtonVariant.ghost,
    size: 22,
    iconSize: 13,
    // Revealing SKILL.md opens the Skill's own folder with it selected.
    onPressed: () => unawaited(
      ref.read(fileLocationOpenerProvider).reveal(p.join(location, 'SKILL.md')),
    ),
  );
}

/// The Agents that read [location], by name; a folder name when unknown.
String _locationAgentName(
  AppLocalizations l10n,
  List<WorkspaceAgentInfo> agents,
  String location,
  List<String> agentIds,
) {
  if (agentIds.isEmpty) {
    return p.basename(p.dirname(p.dirname(location)));
  }
  // A folder many Agents read, such as ~/.agents/skills, is one copy, not
  // one per Agent.
  if (_isSharedFolder(agentIds)) return l10n.externalSkillsSharedFolder;
  return {
    for (final id in agentIds)
      id == universalAgentId
          ? l10n.activationUniversalAgents
          : agents.where((agent) => agent.id == id).firstOrNull?.displayName ??
                id,
  }.join(', ');
}

class _AdoptingState extends ConsumerWidget {
  const _AdoptingState({required this.state, required this.viewModel});

  final ExternalSkillsState state;
  final ExternalSkillsViewModel viewModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operation = state.operation;
    final completed = state.completedSlotKeys.length;
    return Column(
      key: const Key('external-skills-adopting'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.externalSkillsAdopting,
          style: AppTypography.of(context).subtitle,
        ),
        const SizedBox(height: 12),
        AppOperationFeedback(
          label: operation.progress == null
              ? context.l10n.externalSkillsCompletedCount(
                  completed,
                  state.adoptionTotal,
                )
              : localizeWorkspacePhase(
                  context.l10n,
                  operation.progress!.phase,
                  commandLineBusy: ref.watch(commandLineBusyProvider),
                ),
          detail: state.activeSlotKey,
          progress: state.adoptionTotal == 0
              ? null
              : completed / state.adoptionTotal,
          warnings: [
            for (final warning in operation.warnings)
              localizeWorkspaceWarning(context.l10n, warning),
          ],
          running: true,
          cancelLabel: context.l10n.commonCancel,
          onCancel: () => unawaited(viewModel.cancelOperation()),
        ),
      ],
    );
  }
}

class _TerminalState extends StatelessWidget {
  const _TerminalState({
    required this.stateKey,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final Key stateKey;
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: stateKey,
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.of(context).subtitle,
        ),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.of(context).bodyMuted,
        ),
      ],
    );
  }
}

/// The Skills of a batch that could not be adopted, each with its reason.
/// They stay in the review, so Retry brings them back.
class _FailedAdoptionList extends StatelessWidget {
  const _FailedAdoptionList({required this.failures});

  final List<ExternalSkillAdoptionFailure> failures;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const Key('external-skills-failed-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.externalSkillsFailedTitle(failures.length),
          style: AppTypography.of(context).control
              .copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _Bordered(
          children: [
            for (final failure in failures)
              Padding(
                key: Key('external-skills-failed-${failure.slotKey}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failure.name,
                      style: AppTypography.of(context).body
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      localizeAppFailure(l10n, failure.failure),
                      style: AppTypography.of(context).bodyMuted,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.stateKey,
    required this.icon,
    required this.title,
    this.detail,
  });

  final Key stateKey;
  final Widget icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: stateKey,
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          icon,
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.of(context).body
                .copyWith(fontWeight: FontWeight.w600),
          ),
          if (detail != null) ...[
            const SizedBox(height: 5),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: AppTypography.of(context).bodyMuted,
            ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.state,
    required this.viewModel,
    required this.choosing,
    required this.onChoosingChanged,
  });

  final ExternalSkillsState state;
  final ExternalSkillsViewModel viewModel;
  final bool choosing;
  final ValueChanged<bool> onChoosingChanged;

  @override
  Widget build(BuildContext context) {
    if (state.status == ExternalSkillsStatus.adopting) {
      return const SizedBox.shrink();
    }
    final terminal =
        state.status == ExternalSkillsStatus.success ||
        state.status == ExternalSkillsStatus.cancelled ||
        state.status == ExternalSkillsStatus.partial ||
        state.status == ExternalSkillsStatus.failure;
    final discovery = state.discovery;
    if (!terminal && (discovery == null || discovery.isEmpty)) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final selected = state.selectedSlotKeys.length;
    return LayoutBuilder(
      builder: (context, constraints) => AppDialogFooter(
        leading: !terminal && choosing
            ? AppButton(
                key: const Key('external-skills-back'),
                label: l10n.commonBack,
                icon: LucideIcons.chevronLeft,
                style: NeoButtonVariant.ghost,
                onPressed: () => onChoosingChanged(false),
              )
            : null,
        actions: [
          ConstrainedBox(
            // Reserve the footer padding/gaps and enough room for Back plus
            // the shared footer's spacer; the actions can wrap independently.
            constraints: BoxConstraints(
              maxWidth:
                  constraints.maxWidth - (!terminal && choosing ? 210 : 50),
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: [
                if (terminal) ...[
                  if (state.status != ExternalSkillsStatus.success)
                    AppButton(
                      key: const Key('external-skills-retry'),
                      // Matches the failure's own action, such as checking
                      // the folders again after the user fixes them.
                      label: switch (state.failure) {
                        final failure? =>
                          localizeAppFailureRecoveryAction(
                                l10n,
                                failure.recoveryPolicy,
                              ) ??
                              l10n.commonRetry,
                        null => l10n.commonRetry,
                      },
                      icon: LucideIcons.refreshCw,
                      onPressed: () => unawaited(viewModel.scan()),
                    ),
                  AppButton(
                    key: const Key('external-skills-done'),
                    label: l10n.commonDone,
                    style: NeoButtonVariant.primary,
                    onPressed: context.pop,
                  ),
                ] else ...[
                  if (!choosing)
                    AppButton(
                      key: const Key('external-skills-choose'),
                      label: l10n.externalSkillsChooseIndividually,
                      onPressed: () => onChoosingChanged(true),
                    ),
                  // Taking over is the confirmation: the review above already
                  // names every Skill and, for a conflict, the chosen copy. It
                  // needs the latest content, so only this waits for a scan.
                  AppButton(
                    key: const Key('external-skills-adopt'),
                    label: state.scanning
                        ? l10n.externalSkillsVerifying
                        : selected > 0 && selected == state.unmanagedSlotCount
                        ? l10n.externalSkillsAdoptAll(selected)
                        : l10n.externalSkillsAdoptCount(selected),
                    icon: LucideIcons.folderInput,
                    style: NeoButtonVariant.primary,
                    loading: state.scanning,
                    onPressed: state.canConfirm && !state.scanning
                        ? () => unawaited(viewModel.adoptSelected())
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Explains why the review came back after the user confirmed it.
class _RescannedNotice extends StatelessWidget {
  const _RescannedNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('external-skills-rescanned'),
      child: AppDialogNote(
        tone: AppDialogTone.warning,
        icon: LucideIcons.refreshCw,
        text: message,
      ),
    );
  }
}

bool _isSharedFolder(List<String> agentIds) =>
    agentIds.length > 1 || agentIds.contains(universalAgentId);
