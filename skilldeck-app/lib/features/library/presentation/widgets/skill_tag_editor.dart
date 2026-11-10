import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/library/personal_tag_providers.dart';
import 'package:skills_manager/features/library/presentation/widgets/personal_tag_controls.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/l10n/app_failure_l10n.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// A Skill's Personal Tags with removable chips and an add/create picker.
class SkillTagEditor extends ConsumerWidget {
  const SkillTagEditor({required this.skillId, this.enabled = true, super.key});

  final WorkspaceSkillId skillId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagIds =
        ref.watch(workspaceSkillByIdProvider(skillId)).value?.personalTagIds ??
        const <String>[];
    final tags = personalTagsFor(tagIds, ref.watch(personalTagsProvider));
    final commands = ref.read(personalTagCommandsProvider.notifier);
    return Wrap(
      key: const Key('skill-tag-editor'),
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in tags)
          if (enabled)
            _RemovableTag(
              tag: tag,
              onRemove: () =>
                  unawaited(commands.unassign(skillId: skillId, tagId: tag.id)),
            )
          else
            PersonalTagChip(tag),
        if (enabled)
          SizedBox(
            key: const Key('skill-tag-add'),
            width: AppSizes.controlHeight,
            child: MorphingMenuButton(
              icon: LucideIcons.plus,
              semanticsLabel: context.l10n.tagsAdd,
              tooltip: context.l10n.tagsAdd,
              enableDragResize: false,
              direction: MorphingMenuDirection.down,
              expandedWidth: 260,
              expandedHeight: 300,
              style: SkillsButtonTheme.morphingMenuFor(context).style.copyWith(
                buttonHeight: AppSizes.controlHeight,
                minButtonWidth: AppSizes.controlHeight,
                collapsedRadius: AppSizes.controlHeight / 2,
                triggerPadding: EdgeInsets.zero,
              ),
              contentBuilder: (_, _) => _SkillTagPicker(skillId: skillId),
            ),
          )
        else if (tags.isEmpty)
          Text(
            context.l10n.tagsNoneAssigned,
            style: AppTypography.of(context).bodyMuted,
          ),
      ],
    );
  }
}

/// A tag that leaves the Skill on right-click; assistive tech gets the same
/// removal as a named action.
class _RemovableTag extends StatelessWidget {
  const _RemovableTag({required this.tag, required this.onRemove});

  final WorkspacePersonalTag tag;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
    customSemanticsActions: {
      CustomSemanticsAction(label: context.l10n.tagsRemove(tag.name)): onRemove,
    },
    child: GestureDetector(
      key: ValueKey('skill-tag-${tag.id}'),
      onSecondaryTap: onRemove,
      child: PersonalTagChip(tag),
    ),
  );
}

class _SkillTagPicker extends ConsumerStatefulWidget {
  const _SkillTagPicker({required this.skillId});

  final WorkspaceSkillId skillId;

  @override
  ConsumerState<_SkillTagPicker> createState() => _SkillTagPickerState();
}

class _SkillTagPickerState extends ConsumerState<_SkillTagPicker> {
  final _query = TextEditingController();
  AppFailure? _failure;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  PersonalTagCommands get _commands =>
      ref.read(personalTagCommandsProvider.notifier);

  void _toggle(WorkspacePersonalTag tag, bool assigned) => unawaited(
    assigned
        ? _commands.unassign(skillId: widget.skillId, tagId: tag.id)
        : _commands.assign(skillId: widget.skillId, tagId: tag.id),
  );

  Future<void> _create(String name) async {
    final failure = await _commands.create(name, assignTo: widget.skillId);
    if (!mounted) return;
    setState(() => _failure = failure);
    if (failure == null) _query.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final assigned = {
      ...?ref
          .watch(workspaceSkillByIdProvider(widget.skillId))
          .value
          ?.personalTagIds,
    };
    final tags = ref.watch(personalTagsProvider);
    final query = _query.text.trim();
    final needle = query.toLowerCase();
    final matches = [
      for (final tag in tags)
        if (tag.name.toLowerCase().contains(needle)) tag,
    ];
    final canCreate =
        query.isNotEmpty &&
        !tags.any((tag) => tag.name.toLowerCase() == needle);
    final failure = _failure;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoTextField(
            key: const Key('skill-tag-search'),
            controller: _query,
            autofocus: true,
            placeholder: l10n.tagsSearchPlaceholder,
            style: AppTypography.of(context).control,
            prefix: Padding(
              padding: EdgeInsets.only(left: AppSpacing.sm),
              child: Icon(
                LucideIcons.search,
                size: AppSizes.iconXs,
                color: AppPalette.of(context).textMuted,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppPalette.of(context).surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            onChanged: (_) => setState(() => _failure = null),
            onSubmitted: (_) {
              if (canCreate) {
                unawaited(_create(query));
              } else if (matches.length == 1) {
                _toggle(matches.single, assigned.contains(matches.single.id));
              }
            },
          ),
          if (failure != null)
            Padding(
              key: const Key('skill-tag-error'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.xs,
                0,
              ),
              child: Text(
                localizeAppFailure(l10n, failure),
                style: AppTypography.of(context).caption
                    .copyWith(color: AppPalette.of(context).danger),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final tag in matches)
                  _TagOption(
                    key: ValueKey('skill-tag-option-${tag.id}'),
                    tag: tag,
                    selected: assigned.contains(tag.id),
                    onPressed: () => _toggle(tag, assigned.contains(tag.id)),
                  ),
                if (canCreate)
                  AppMorphingMenuOption(
                    key: const Key('skill-tag-create'),
                    label: l10n.tagsCreateNamed(query),
                    leading: const Icon(LucideIcons.plus, size: 16),
                    selected: false,
                    onPressed: () => unawaited(_create(query)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagOption extends StatefulWidget {
  const _TagOption({
    required this.tag,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final WorkspacePersonalTag tag;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_TagOption> createState() => _TagOptionState();
}

class _TagOptionState extends State<_TagOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: widget.selected,
    label: widget.tag.name,
    onTap: widget.onPressed,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          height: AppSizes.controlHeight,
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
              if (widget.selected)
                Icon(
                  LucideIcons.check,
                  size: 15,
                  color: AppPalette.of(context).textPrimary,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
