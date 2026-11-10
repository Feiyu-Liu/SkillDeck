import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// The Source-describing form controls shared by every dialog that asks the
/// user where a Skill comes from.
///
/// Adding a Skill and replacing a Skill's Source ask for exactly the same
/// thing, so they must look and behave the same. These widgets are the single
/// definition of that form; a dialog supplies its own Keys and callbacks.

/// The icon tile that identifies one [SkillSourceKind] wherever a Source is
/// named: the kind cards, and the smart-mode result card.
class SourceKindBadge extends StatelessWidget {
  const SourceKindBadge({required this.type, this.size = 34, super.key});

  final SkillSourceKind type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final (icon, background, foreground) = switch (type) {
      SkillSourceKind.local => (
        LucideIcons.folderOpen,
        colors.localSourceSurface,
        colors.warning,
      ),
      SkillSourceKind.git => (
        LucideIcons.gitBranch,
        colors.surfaceMuted,
        colors.ink,
      ),
      SkillSourceKind.wellKnown => (
        LucideIcons.link,
        colors.webSourceSurface,
        colors.info,
      ),
    };
    return Container(
      width: size,
      height: size,
      decoration: AppCorners.smooth(color: background, radius: 8),
      child: Icon(icon, size: size / 2, color: foreground),
    );
  }
}

/// A selectable card naming one [SkillSourceKind]. [compact] stacks the badge
/// above the text so three cards fit in one row.
class SourceKindCard extends StatelessWidget {
  const SourceKindCard({
    required this.type,
    required this.selected,
    this.onTap,
    this.compact = false,
    this.radioStyle = false,
    super.key,
  });

  final SkillSourceKind type;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;
  final bool radioStyle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = switch (type) {
      SkillSourceKind.local => l10n.acquisitionLocalFolder,
      SkillSourceKind.git => l10n.acquisitionGitRepository,
      SkillSourceKind.wellKnown => l10n.acquisitionWebSourceUrl,
    };
    final sub = switch (type) {
      SkillSourceKind.local => l10n.acquisitionLocalFolderDescription,
      SkillSourceKind.git => l10n.acquisitionGitRepositoryDescription,
      SkillSourceKind.wellKnown => l10n.acquisitionWebSourceUrlDescription,
    };
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.of(context).body
              .copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: AppTypography.of(context).control.copyWith(
            fontWeight: FontWeight.w400,
            color: AppPalette.of(context).textSecondary,
          ),
        ),
      ],
    );
    final check = Icon(
      LucideIcons.circleCheck,
      size: 18,
      color: AppPalette.of(context).ink,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: radioStyle
            ? null
            : AppCorners.smooth(
                color: selected
                    ? AppPalette.of(context).surfaceSubtle
                    : AppPalette.of(context).white,
                radius: 10,
                side: BorderSide(
                  color: selected
                      ? AppPalette.of(context).ink
                      : AppPalette.of(context).border,
                  width: selected ? 1.5 : 1,
                ),
              ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SourceKindBadge(type: type),
                      if (selected) check,
                    ],
                  ),
                  const SizedBox(height: 8),
                  text,
                ],
              )
            : Row(
                children: [
                  SourceKindBadge(type: type),
                  const SizedBox(width: 10),
                  Expanded(child: text),
                  if (radioStyle)
                    Icon(
                      selected ? LucideIcons.circleDot : LucideIcons.circle,
                      size: 18,
                      color: selected
                          ? AppPalette.of(context).ink
                          : AppPalette.of(context).textSecondary,
                    )
                  else if (selected)
                    check,
                ],
              ),
      ),
    );
  }
}

/// A labelled single-line field for a secondary Source option (ref, subpath).
class SourceOptionField extends StatelessWidget {
  const SourceOptionField({
    required this.inputKey,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.onSubmitted,
    super.key,
  });

  final Key inputKey;
  final String label;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  /// Called when the user presses Enter in the field.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTypography.of(context).body
            .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: AppCorners.smooth(
          color: AppPalette.of(context).white,
          radius: 8,
          side: BorderSide(color: AppPalette.of(context).borderStrong),
        ),
        child: CupertinoTextFormFieldRow(
          key: inputKey,
          initialValue: value,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          enabled: enabled,
          padding: EdgeInsets.zero,
          style: AppTypography.of(context).mono,
          placeholder: hint,
          placeholderStyle: AppTypography.of(context).mono
              .copyWith(color: AppPalette.of(context).textSecondary),
          decoration: null,
        ),
      ),
    ],
  );
}

/// The primary locator field: path, repository URL, or Source URL.
///
/// The label, placeholder, and leading icon all follow [sourceType], and the
/// local kind additionally offers a directory picker.
class SourceLocatorField extends ConsumerStatefulWidget {
  const SourceLocatorField({
    required this.inputKey,
    required this.sourceType,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.onSubmitted,
    this.footnote,
    super.key,
  });

  final Key inputKey;
  final SkillSourceKind sourceType;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  /// Called when the user presses Enter in the field.
  final ValueChanged<String>? onSubmitted;

  /// Optional explanatory line rendered under the field.
  final String? footnote;

  @override
  ConsumerState<SourceLocatorField> createState() => _SourceLocatorFieldState();
}

class _SourceLocatorFieldState extends ConsumerState<SourceLocatorField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant SourceLocatorField oldWidget) {
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
    final (label, hint, icon) = switch (widget.sourceType) {
      SkillSourceKind.local => (
        l10n.acquisitionFolderPath,
        l10n.acquisitionFolderPathHint,
        LucideIcons.folder,
      ),
      SkillSourceKind.git => (
        l10n.acquisitionRepositoryUrl,
        l10n.acquisitionRepositoryUrlHint,
        LucideIcons.gitBranch,
      ),
      SkillSourceKind.wellKnown => (
        l10n.acquisitionSourceUrl,
        l10n.acquisitionSourceUrlHint,
        LucideIcons.link,
      ),
    };
    final footnote = widget.footnote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.of(context).body
              .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: AppCorners.smooth(
            color: AppPalette.of(context).white,
            radius: 8,
            side: BorderSide(color: AppPalette.of(context).borderStrong),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: AppPalette.of(context).textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoTextFormFieldRow(
                  key: widget.inputKey,
                  controller: _controller,
                  onChanged: widget.onChanged,
                  onFieldSubmitted: widget.onSubmitted,
                  enabled: widget.enabled,
                  padding: EdgeInsets.zero,
                  style: AppTypography.of(context).mono,
                  placeholder: hint,
                  placeholderStyle: AppTypography.of(context).mono
                      .copyWith(color: AppPalette.of(context).textSecondary),
                  decoration: null,
                ),
              ),
              if (widget.sourceType == SkillSourceKind.local)
                AppIconButton(
                  key: const Key('choose-source-directory'),
                  icon: LucideIcons.folderOpen,
                  tooltip: l10n.acquisitionLocalFolder,
                  style: NeoButtonVariant.ghost,
                  onPressed: widget.enabled
                      ? () async {
                          final path = await ref
                              .read(directoryPickerProvider)
                              .pickDirectory();
                          if (path != null) widget.onChanged(path);
                        }
                      : null,
                ),
            ],
          ),
        ),
        if (footnote != null) ...[
          const SizedBox(height: 8),
          Text(
            footnote,
            style: AppTypography.of(context).bodyMuted.copyWith(
              color: AppPalette.of(context).textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
