import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_link_opener.dart';
import 'package:skills_manager/features/skills/models/skill_source_link.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';
import 'package:next_ui/next_ui.dart';

class SkillSourceLinkValue extends ConsumerStatefulWidget {
  const SkillSourceLinkValue({required this.source, super.key});

  final SkillSourceProvenance? source;

  @override
  ConsumerState<SkillSourceLinkValue> createState() =>
      _SkillSourceLinkValueState();
}

class _SkillSourceLinkValueState extends ConsumerState<SkillSourceLinkValue> {
  bool _failed = false;
  bool _opening = false;

  @override
  void didUpdateWidget(covariant SkillSourceLinkValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _failed = false;
  }

  Future<void> _open(SkillSourceLink link) async {
    final sourceBeingOpened = widget.source;
    setState(() {
      _opening = true;
      _failed = false;
    });
    final opened = await ref.read(skillSourceLinkOpenerProvider).open(link);
    if (!mounted) return;
    setState(() {
      _opening = false;
      if (identical(widget.source, sourceBeingOpened)) _failed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    final link = SkillSourceLink.fromSource(widget.source);
    final style = AppTypography.of(context).mono.copyWith(
      fontWeight: FontWeight.w700,
      color: AppPalette.of(context).textPrimary,
    );
    final value = link.uri == null
        ? Text(
            link.label.isEmpty
                ? context.l10n.workspaceSourceUnavailable
                : link.label,
            style: style,
            overflow: TextOverflow.ellipsis,
          )
        : AppButton(
            key: const Key('skill-source-link'),
            label: link.label,
            semanticsLabel: context.l10n.workspaceOpenSource(link.label),
            textStyle: style.copyWith(decoration: TextDecoration.underline),
            style: NeoButtonVariant.ghost,
            contentAlignment: MainAxisAlignment.start,
            loading: _opening,
            onPressed: () {
              _open(link);
            },
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTooltip(
          message: link.uri == null
              ? context.l10n.workspaceSourceNotWebLink
              : link.label,
          maxWidth: 480,
          maxLines: null,
          child: value,
        ),
        if (_failed)
          Text(
            context.l10n.workspaceOpenSourceFailed,
            key: const Key('skill-source-link-failed'),
            style: AppTypography.of(context).caption
                .copyWith(color: AppPalette.of(context).danger),
          ),
      ],
    );
  }
}
