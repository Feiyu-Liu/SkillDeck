import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/library/personal_tag_palette.dart';
import 'package:skills_manager/features/library/personal_tag_providers.dart';
import 'package:skills_manager/features/library/presentation/widgets/personal_tag_controls.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// The sort card's content: [sortSection] above the Personal Tag filter.
///
/// Clicking a tag toggles it in the filter; right-clicking swaps the whole
/// card for that tag's editor. Management stays inside the card because the
/// card closes on any tap outside it, which a separate menu would be.
class PersonalTagFilterPanel extends ConsumerStatefulWidget {
  const PersonalTagFilterPanel({
    required this.sortSection,
    this.groupingSection,
    this.fixedSectionsHeight = 178,
    super.key,
  });

  static const _dividerHeight = 9.0;
  static const _headerHeight = 26.0;
  static const _rowHeight = 34.0;
  static const _hintHeight = 26.0;

  /// Rows shown before the tag list scrolls inside the card.
  static const maxVisibleRows = 8;

  /// The height the tag half needs below the sort section.
  static double tagSectionHeight(int tagCount) =>
      _dividerHeight +
      _headerHeight +
      tagCount.clamp(1, maxVisibleRows) * _rowHeight +
      _hintHeight;

  final Widget sortSection;
  final Widget? groupingSection;
  final double fixedSectionsHeight;

  @override
  ConsumerState<PersonalTagFilterPanel> createState() =>
      _PersonalTagFilterPanelState();
}

class _PersonalTagFilterPanelState
    extends ConsumerState<PersonalTagFilterPanel> {
  bool _creating = false;
  String? _editingId;

  PersonalTagCommands get _commands =>
      ref.read(personalTagCommandsProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tags = ref.watch(personalTagsProvider);
    final counts = ref.watch(personalTagCountsProvider);
    final selected = ref.watch(personalTagFilterProvider);
    final filter = ref.read(personalTagFilterProvider.notifier);

    final editing = tags.where((tag) => tag.id == _editingId).firstOrNull;
    if (editing != null) {
      return _PersonalTagEditor(
        key: ValueKey('personal-tag-editor-${editing.id}'),
        tag: editing,
        skillCount: counts[editing.id] ?? 0,
        onDone: () => setState(() => _editingId = null),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scrollWholePanel =
            constraints.maxHeight <
            widget.fixedSectionsHeight +
                PersonalTagFilterPanel.tagSectionHeight(1);
        final tagList = ListView(
          key: const Key('tag-filter-list'),
          shrinkWrap: scrollWholePanel,
          physics: scrollWholePanel
              ? const NeverScrollableScrollPhysics()
              : null,
          padding: EdgeInsets.zero,
          children: _tagRows(context, tags, counts, selected, filter),
        );
        final content = Column(
          mainAxisSize: scrollWholePanel ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.sortSection,
            if (widget.groupingSection != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: SizedBox(
                  height: 1,
                  child: ColoredBox(color: AppPalette.of(context).border),
                ),
              ),
              widget.groupingSection!,
            ],
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: SizedBox(
                height: 1,
                child: ColoredBox(color: AppPalette.of(context).border),
              ),
            ),
            SizedBox(
              height: PersonalTagFilterPanel._headerHeight,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.tagsFilterTitle,
                        style: AppTypography.of(context).sectionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selected.isNotEmpty)
                      CupertinoButton(
                        key: const Key('tag-filter-clear'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        minimumSize: Size.zero,
                        onPressed: filter.clear,
                        child: Text(
                          l10n.tagsClear,
                          style: AppTypography.of(context).caption,
                        ),
                      ),
                    AppIconButton(
                      key: const Key('tag-filter-create'),
                      icon: LucideIcons.plus,
                      tooltip: l10n.tagsCreate,
                      style: NeoButtonVariant.ghost,
                      size: 22,
                      iconSize: AppSizes.iconXs,
                      onPressed: () => setState(() => _creating = true),
                    ),
                  ],
                ),
              ),
            ),
            if (scrollWholePanel) tagList else Expanded(child: tagList),
            SizedBox(
              height: PersonalTagFilterPanel._hintHeight,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, top: 6),
                child: Text(
                  l10n.tagsManageHint,
                  style: AppTypography.of(context).caption
                      .copyWith(fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        );
        return scrollWholePanel
            ? SingleChildScrollView(
                key: const Key('skill-filter-panel-scroll'),
                child: content,
              )
            : content;
      },
    );
  }

  List<Widget> _tagRows(
    BuildContext context,
    List<WorkspacePersonalTag> tags,
    Map<String, int> counts,
    Set<String> selected,
    PersonalTagFilterController filter,
  ) {
    final l10n = context.l10n;
    return [
      if (_creating)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: PersonalTagNameField(
            onSubmit: (name) async {
              final failure = await _commands.create(name);
              if (failure == null && mounted) {
                setState(() => _creating = false);
              }
              return failure;
            },
            onCancel: () => setState(() => _creating = false),
          ),
        ),
      if (tags.isEmpty && !_creating)
        SizedBox(
          height: PersonalTagFilterPanel._rowHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.tagsNoneAssigned,
                style: AppTypography.of(context).bodyMuted,
              ),
            ),
          ),
        ),
      for (final tag in tags)
        _TagFilterRow(
          tag: tag,
          count: counts[tag.id] ?? 0,
          selected: selected.contains(tag.id),
          onTap: () => filter.toggle(tag.id),
          onSecondaryTap: () => setState(() {
            _creating = false;
            _editingId = tag.id;
          }),
        ),
    ];
  }
}

class _TagFilterRow extends StatefulWidget {
  const _TagFilterRow({
    required this.tag,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final WorkspacePersonalTag tag;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSecondaryTap;

  @override
  State<_TagFilterRow> createState() => _TagFilterRowState();
}

class _TagFilterRowState extends State<_TagFilterRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: widget.tag.name,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: ValueKey('tag-filter-${widget.tag.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTap: widget.onSecondaryTap,
          child: Container(
            height: PersonalTagFilterPanel._rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: AppCorners.smooth(
              color: _hovered
                  ? AppPalette.of(context).surfaceMuted
                  : AppPalette.of(context).transparent,
              radius: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PersonalTagChip(widget.tag),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${widget.count}',
                  style: AppTypography.of(context).mono.copyWith(
                    fontSize: 11,
                    color: selected
                        ? AppPalette.of(context).bodyContent
                        : AppPalette.of(context).textMuted,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 15,
                  child: selected
                      ? Icon(
                          LucideIcons.check,
                          size: 15,
                          color: AppPalette.of(context).textPrimary,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rename, recolor, and delete for one tag, filling the sort card.
class _PersonalTagEditor extends ConsumerStatefulWidget {
  const _PersonalTagEditor({
    required this.tag,
    required this.skillCount,
    required this.onDone,
    super.key,
  });

  final WorkspacePersonalTag tag;
  final int skillCount;
  final VoidCallback onDone;

  @override
  ConsumerState<_PersonalTagEditor> createState() => _PersonalTagEditorState();
}

class _PersonalTagEditorState extends ConsumerState<_PersonalTagEditor> {
  bool _confirmingDelete = false;

  PersonalTagCommands get _commands =>
      ref.read(personalTagCommandsProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tag = widget.tag;
    final current = tag.color?.toUpperCase() ?? personalTagPalette.first;
    return SingleChildScrollView(
      key: const Key('personal-tag-editor'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconButton(
                key: const Key('personal-tag-editor-back'),
                icon: LucideIcons.chevronLeft,
                tooltip: l10n.commonBack,
                style: NeoButtonVariant.ghost,
                size: 24,
                iconSize: AppSizes.iconXs,
                onPressed: widget.onDone,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.tagsEdit,
                style: AppTypography.of(context).sectionLabel,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PersonalTagNameField(
            initialValue: tag.name,
            cancelOnBlur: false,
            onSubmit: (name) async {
              if (name == tag.name) {
                widget.onDone();
                return null;
              }
              final failure = await _commands.rename(tag, name);
              if (failure == null) widget.onDone();
              return failure;
            },
            onCancel: widget.onDone,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (index, color) in personalTagPalette.indexed)
                Semantics(
                  button: true,
                  selected: color == current,
                  label: l10n.tagsColorSwatch(index + 1),
                  child: GestureDetector(
                    key: ValueKey('personal-tag-color-$color'),
                    onTap: () => unawaited(_commands.recolor(tag, color)),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: personalTagColor(color),
                          shape: BoxShape.circle,
                          border: color == current
                              ? Border.all(
                                  color: AppPalette.of(context).textPrimary,
                                  width: 2,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (!_confirmingDelete)
            AppMorphingMenuOption(
              key: const Key('personal-tag-delete'),
              label: l10n.tagsDelete,
              leading: Icon(
                LucideIcons.trash2,
                size: 16,
                color: AppPalette.of(context).danger,
              ),
              selected: false,
              onPressed: () => setState(() => _confirmingDelete = true),
            )
          else ...[
            Text(
              l10n.tagsDeleteTitle(tag.name),
              style: AppTypography.of(context).control.copyWith(
                color: AppPalette.of(context).textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.tagsDeleteMessage(widget.skillCount),
              style: AppTypography.of(context).caption,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: l10n.commonCancel,
                  size: NeoButtonSize.small,
                  onPressed: () => setState(() => _confirmingDelete = false),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppButton(
                  key: const Key('personal-tag-delete-confirm'),
                  label: l10n.tagsDelete,
                  size: NeoButtonSize.small,
                  style: NeoButtonVariant.danger,
                  onPressed: () {
                    unawaited(_commands.delete(tag.id));
                    widget.onDone();
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
