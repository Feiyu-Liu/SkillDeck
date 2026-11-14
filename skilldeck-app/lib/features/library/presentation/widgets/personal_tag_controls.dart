import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:skills_manager/features/library/personal_tag_palette.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/app_failure_l10n.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_keycap_tag.dart';

/// A Personal Tag drawn as a keycap in the tag's palette color.
class PersonalTagChip extends StatelessWidget {
  const PersonalTagChip(this.tag, {this.compact = false, super.key});

  static const maxChipWidth = 160.0;

  final WorkspacePersonalTag tag;

  /// Shrinks the chip to sit beside body text on cards and rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // The keycap never ellipsizes its label, so cap long names by clipping
    // rather than letting them overflow a card's single tag line.
    final chip = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxChipWidth),
      child: UnconstrainedBox(
        constrainedAxis: Axis.vertical,
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.hardEdge,
        child: AppKeycapTag(tag.name, color: personalTagColor(tag.color)),
      ),
    );
    if (!compact) return chip;
    // Same scale as the source-kind tag so chips match the surrounding text.
    return Align(
      widthFactor: 0.85,
      heightFactor: 0.85,
      alignment: Alignment.centerLeft,
      child: Transform.scale(
        scale: 0.85,
        alignment: Alignment.centerLeft,
        child: chip,
      ),
    );
  }
}

/// A one-line tag strip that shows the first few tags and counts the rest.
class PersonalTagStrip extends StatelessWidget {
  const PersonalTagStrip({required this.tags, this.maxVisible = 2, super.key});

  final List<WorkspacePersonalTag> tags;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final visible = tags.take(maxVisible).toList();
    final hidden = tags.length - visible.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tag in visible)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: PersonalTagChip(tag, compact: true),
            ),
          ),
        if (hidden > 0)
          Text('+$hidden', style: AppTypography.of(context).caption),
      ],
    );
  }
}

/// Resolves a Skill's tag ids against the Snapshot, dropping unknown ids.
List<WorkspacePersonalTag> personalTagsFor(
  Iterable<String> tagIds,
  List<WorkspacePersonalTag> tags,
) {
  final byId = {for (final tag in tags) tag.id: tag};
  return [for (final id in tagIds) ?byId[id]]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// An inline name editor that keeps a failed submission's error beneath it.
class PersonalTagNameField extends StatefulWidget {
  const PersonalTagNameField({
    required this.onSubmit,
    required this.onCancel,
    this.initialValue = '',
    this.cancelOnBlur = true,
    super.key,
  });

  final String initialValue;

  /// Whether losing focus cancels; editors with sibling controls keep it.
  final bool cancelOnBlur;
  final Future<AppFailure?> Function(String name) onSubmit;
  final VoidCallback onCancel;

  @override
  State<PersonalTagNameField> createState() => _PersonalTagNameFieldState();
}

class _PersonalTagNameFieldState extends State<PersonalTagNameField> {
  late final _controller = TextEditingController(text: widget.initialValue)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );
  final _focusNode = FocusNode();
  AppFailure? _failure;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (widget.cancelOnBlur &&
          !_focusNode.hasFocus &&
          !_submitting &&
          _failure == null) {
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return widget.onCancel();
    setState(() => _submitting = true);
    final failure = await widget.onSubmit(name);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _failure = failure;
    });
    if (failure != null) _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoTextField(
            key: const Key('personal-tag-name-field'),
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            enabled: !_submitting,
            placeholder: context.l10n.tagsNamePlaceholder,
            style: AppTypography.of(context).control,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppPalette.of(context).surface,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(
                color: failure == null
                    ? AppPalette.of(context).border
                    : AppPalette.of(context).danger,
              ),
            ),
            onChanged: (_) {
              if (_failure != null) setState(() => _failure = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          if (failure != null)
            Padding(
              key: const Key('personal-tag-name-error'),
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                localizeAppFailure(context.l10n, failure),
                style: AppTypography.of(context).caption
                    .copyWith(color: AppPalette.of(context).danger),
              ),
            ),
        ],
      ),
    );
  }
}
