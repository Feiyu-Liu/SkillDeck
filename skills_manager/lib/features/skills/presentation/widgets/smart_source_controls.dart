import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/command_host/data/command_line_distribution.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_distribution_providers.dart';
import 'package:skills_manager/features/settings/presentation/settings_section.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/presentation/widgets/source_form_controls.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_cupertino_controls.dart';

/// The "smart" half of the Add Skill Source step: one box that accepts a
/// repository, an `npx skills add` command, a URL, or a folder path, plus the
/// result card shown after the Source was checked.
///
/// These widgets are presentational. The ViewModel owns detection, parsing,
/// and the fallback between Source kinds; the dialog maps that state onto the
/// props here.

/// Which kind of input the user is choosing: one box that detects the Source
/// kind, or the explicit per-kind form.
enum AcquisitionInputModeOption { smart, typed }

/// Two-segment switch between the smart box and the per-kind form, drawn with
/// the same segmented control as Settings.
class AcquisitionInputModeSwitch extends StatelessWidget {
  const AcquisitionInputModeSwitch({
    required this.mode,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final AcquisitionInputModeOption mode;
  final ValueChanged<AcquisitionInputModeOption> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Hug the two segments even when the parent stretches its children.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppSegmentedControl<AcquisitionInputModeOption>(
        value: mode,
        enabled: enabled,
        onChanged: onChanged,
        segments: {
          AcquisitionInputModeOption.smart: l10n.acquisitionInputModeSmart,
          AcquisitionInputModeOption.typed: l10n.acquisitionInputModeTyped,
        },
        segmentKeys: const {
          AcquisitionInputModeOption.smart: Key('input-mode-smart'),
          AcquisitionInputModeOption.typed: Key('input-mode-typed'),
        },
      ),
    );
  }
}

/// The single smart input box. [showPicker] puts the folder picker on the
/// right, otherwise a clear button appears once there is text.
class SmartSourceField extends ConsumerStatefulWidget {
  const SmartSourceField({
    required this.inputKey,
    required this.value,
    required this.onChanged,
    required this.enabled,
    required this.showPicker,
    this.onSubmitted,
    super.key,
  });

  final Key inputKey;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool showPicker;
  final ValueChanged<String>? onSubmitted;

  @override
  ConsumerState<SmartSourceField> createState() => _SmartSourceFieldState();
}

class _SmartSourceFieldState extends ConsumerState<SmartSourceField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant SmartSourceField oldWidget) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: AppCorners.smooth(
            color: AppPalette.of(context).white,
            radius: 8,
            side: BorderSide(color: AppPalette.of(context).borderStrong),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CupertinoTextFormFieldRow(
                  key: widget.inputKey,
                  controller: _controller,
                  onChanged: widget.onChanged,
                  onFieldSubmitted: widget.onSubmitted,
                  enabled: widget.enabled,
                  padding: EdgeInsets.zero,
                  maxLines: 3,
                  minLines: 1,
                  style: AppTypography.of(context).mono,
                  placeholder: l10n.acquisitionSmartHint,
                  placeholderStyle: AppTypography.of(context).mono
                      .copyWith(color: AppPalette.of(context).textSecondary),
                  decoration: null,
                ),
              ),
              if (widget.showPicker)
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
                )
              else
                AppIconButton(
                  key: const Key('clear-source-input'),
                  icon: LucideIcons.x,
                  tooltip: l10n.acquisitionClearInput,
                  style: NeoButtonVariant.ghost,
                  onPressed: widget.enabled ? () => widget.onChanged('') : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sits beside the input mode switch: a button that morphs into a card. Once
/// the command line and the bundled skilldeck Agent Skill are ready, the card
/// holds a prompt the user can hand to an Agent; until then it lists what is
/// missing and points at Settings.
class SmartSourceAgentPrompt extends ConsumerStatefulWidget {
  const SmartSourceAgentPrompt({super.key});

  @override
  ConsumerState<SmartSourceAgentPrompt> createState() =>
      _SmartSourceAgentPromptState();
}

class _SmartSourceAgentPromptState
    extends ConsumerState<SmartSourceAgentPrompt> {
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String prompt) async {
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() {
      _copiedTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copiedTimer = null);
      });
    });
  }

  void _openCommandLineSettings(VoidCallback close) {
    close();
    // Resolve the router before popping: afterwards this context is
    // deactivated and cannot look one up.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(settingsLocation(SettingsSection.commandLine));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The skilldeck Skill calls the CLI by its absolute path, so PATH setup
    // does not matter here; the stable CLI copy and an active Skill do.
    final toolReady =
        ref.watch(commandLineToolProvider).value?.status ==
        CommandLineToolStatus.ready;
    final skill = ref.watch(skillDeckAgentSkillProvider);
    final skillReady = skill.installed && skill.activeAgentIds.isNotEmpty;
    final ready = toolReady && skillReady;
    return MorphingMenuButton(
      key: const Key('agent-install-prompt-toggle'),
      icon: LucideIcons.bot,
      label: l10n.acquisitionAgentPromptTitle,
      enableDragResize: false,
      direction: MorphingMenuDirection.down,
      alignment: MorphingMenuAlignment.end,
      expandedWidth: _AgentPromptCard.width,
      expandedHeight: _AgentPromptCard.heightFor(context, ready: ready),
      contentBuilder: (menuContext, close) => ready
          ? _AgentPromptCard(
              prompt: l10n.acquisitionAgentPrompt,
              copied: _copiedTimer != null,
              onCopy: () => _copy(l10n.acquisitionAgentPrompt),
            )
          : _AgentSetupCard(
              toolReady: toolReady,
              skillReady: skillReady,
              onOpenSettings: () => _openCommandLineSettings(close),
            ),
    );
  }
}

/// Shared measurements for the two pages of the Agent install card.
abstract final class _AgentCardMetrics {
  static const width = 440.0;
  // Added to the menu's own panel padding.
  static const padding = EdgeInsets.fromLTRB(8, 6, 8, 4);
  // One rhythm: 12 between the blocks of content, 16 above the actions.
  static const gap = 12.0;
  static const actionsGap = 16.0;
  static const actionsHeight = 30.0;
  static final headingStyle = AppTypography.subtitle.copyWith(height: 1.4);

  /// Everything but the page's own content: padding, actions, and rounding
  /// slack so no line is cut by a fraction of a pixel.
  static double frame(BuildContext context) =>
      MorphingMenuButtonTheme.of(context).style.panelPadding.vertical +
      padding.vertical +
      actionsGap +
      actionsHeight +
      2;

  static double innerWidth(BuildContext context) =>
      width -
      MorphingMenuButtonTheme.of(context).style.panelPadding.horizontal -
      padding.horizontal;

  static double measure(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth, {
    int? maxLines,
  }) => (TextPainter(
    maxLines: maxLines,
    ellipsis: maxLines == null ? null : '…',
    // Text merges the ambient style the same way.
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth)).height;

  static Widget layout({
    required Key key,
    required List<Widget> content,
    required Widget action,
  }) => SingleChildScrollView(
    key: key,
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...content,
        const SizedBox(height: actionsGap),
        SizedBox(
          height: actionsHeight,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: action,
          ),
        ),
      ],
    ),
  );
}

class _AgentPromptCard extends StatelessWidget {
  const _AgentPromptCard({
    required this.prompt,
    required this.copied,
    required this.onCopy,
  });

  static const width = _AgentCardMetrics.width;
  static const _leadStyle = AppTypography.body;
  static const _promptPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );
  // The card previews the prompt; Copy always takes the whole text.
  static const _promptLines = 2;
  static final _promptStyle = AppTypography.mono.copyWith(
    fontSize: 12,
    height: 1.6,
  );

  final String prompt;
  final bool copied;
  final VoidCallback onCopy;

  /// The menu needs a fixed panel height, so the text is measured up front.
  static double heightFor(BuildContext context, {required bool ready}) {
    if (!ready) return _AgentSetupCard.height(context);
    final l10n = context.l10n;
    final inner = _AgentCardMetrics.innerWidth(context);
    return _AgentCardMetrics.frame(context) +
        _AgentCardMetrics.measure(
          context,
          l10n.acquisitionAgentPromptHint,
          _leadStyle,
          inner,
        ) +
        _AgentCardMetrics.gap +
        _AgentCardMetrics.measure(
          context,
          l10n.acquisitionAgentPrompt,
          _promptStyle,
          inner - _promptPadding.horizontal,
          maxLines: _promptLines,
        ) +
        _promptPadding.vertical;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _AgentCardMetrics.layout(
      key: const Key('agent-install-prompt-card'),
      content: [
        Text(
          l10n.acquisitionAgentPromptHint,
          style: _leadStyle.copyWith(color: AppPalette.of(context).bodyContent),
        ),
        const SizedBox(height: _AgentCardMetrics.gap),
        Container(
          key: const Key('agent-install-prompt'),
          padding: _promptPadding,
          decoration: AppCorners.smooth(
            color: AppPalette.of(context).surfaceMuted,
            radius: 8,
          ),
          child: Text(
            prompt,
            style: _promptStyle.copyWith(
              color: AppPalette.of(context).textSecondary,
            ),
            maxLines: _promptLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      action: AppButton(
        key: const Key('copy-agent-install-prompt'),
        label: copied
            ? l10n.acquisitionAgentPromptCopied
            : l10n.acquisitionAgentPromptCopy,
        icon: copied ? LucideIcons.check : LucideIcons.copy,
        style: NeoButtonVariant.primary,
        size: NeoButtonSize.small,
        onPressed: onCopy,
      ),
    );
  }
}

/// What the card shows until the Agent route works: the two setup steps and
/// a way to Settings › Command Line, where both are done.
class _AgentSetupCard extends StatelessWidget {
  const _AgentSetupCard({
    required this.toolReady,
    required this.skillReady,
    required this.onOpenSettings,
  });

  static final _bodyStyle = AppTypography.caption.copyWith(height: 1.5);
  static const _itemHeight = 24.0;
  static const _itemGap = 4.0;

  final bool toolReady;
  final bool skillReady;
  final VoidCallback onOpenSettings;

  static double height(BuildContext context) {
    final l10n = context.l10n;
    final inner = _AgentCardMetrics.innerWidth(context);
    return _AgentCardMetrics.frame(context) +
        _AgentCardMetrics.measure(
          context,
          l10n.acquisitionAgentSetupTitle,
          _AgentCardMetrics.headingStyle,
          inner,
        ) +
        6 +
        _AgentCardMetrics.measure(
          context,
          l10n.acquisitionAgentSetupBody,
          _bodyStyle,
          inner,
        ) +
        _AgentCardMetrics.gap +
        _itemHeight * 2 +
        _itemGap;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _AgentCardMetrics.layout(
      key: const Key('agent-install-setup'),
      content: [
        Text(
          l10n.acquisitionAgentSetupTitle,
          style: _AgentCardMetrics.headingStyle.copyWith(
            color: AppPalette.of(context).textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.acquisitionAgentSetupBody,
          style: _bodyStyle.copyWith(
            color: AppPalette.of(context).textSecondary,
          ),
        ),
        const SizedBox(height: _AgentCardMetrics.gap),
        _SetupItem(
          key: const Key('agent-install-setup-tool'),
          label: l10n.acquisitionAgentSetupTool,
          done: toolReady,
        ),
        const SizedBox(height: _itemGap),
        _SetupItem(
          key: const Key('agent-install-setup-skill'),
          label: l10n.acquisitionAgentSetupSkill,
          done: skillReady,
        ),
      ],
      action: AppButton(
        key: const Key('agent-install-prompt-settings'),
        label: l10n.acquisitionAgentPromptOpenSettings,
        icon: LucideIcons.settings,
        style: NeoButtonVariant.primary,
        size: NeoButtonSize.small,
        onPressed: onOpenSettings,
      ),
    );
  }
}

class _SetupItem extends StatelessWidget {
  const _SetupItem({required this.label, required this.done, super.key});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _AgentSetupCard._itemHeight,
    child: Row(
      children: [
        Icon(
          done ? LucideIcons.circleCheck : LucideIcons.circle,
          size: 16,
          color: done
              ? AppPalette.of(context).success
              : AppPalette.of(context).textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.of(context).body.copyWith(
              color: done
                  ? AppPalette.of(context).textSecondary
                  : AppPalette.of(context).bodyContent,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MonoChip extends StatelessWidget {
  const _MonoChip({required this.text, this.outlined = false});

  final String text;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: AppCorners.smooth(
      color: outlined
          ? AppPalette.of(context).white
          : AppPalette.of(context).surfaceMuted,
      radius: 6,
      side: outlined
          ? BorderSide(color: AppPalette.of(context).border)
          : BorderSide.none,
    ),
    child: Text(text, style: AppTypography.of(context).mono),
  );
}

/// The collapsible "Advanced options" row that hides the Git ref and subpath
/// fields in smart mode.
class SmartSourceAdvancedDisclosure extends StatelessWidget {
  const SmartSourceAdvancedDisclosure({
    required this.expanded,
    required this.onToggle,
    required this.child,
    super.key,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: const Key('smart-advanced-toggle'),
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Icon(
                expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                size: 14,
                color: AppPalette.of(context).textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.acquisitionAdvancedOptions,
                style: AppTypography.of(context).control
                    .copyWith(color: AppPalette.of(context).bodyContent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.acquisitionAdvancedOptionsHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.of(context).caption
                      .copyWith(color: AppPalette.of(context).textSecondary),
                ),
              ),
            ],
          ),
        ),
        if (expanded) ...[const SizedBox(height: 12), child],
      ],
    );
  }
}

/// What a successful check found, shown on the Source step in smart mode
/// before the user continues to candidate selection.
class SmartSourceResultCard extends StatelessWidget {
  const SmartSourceResultCard({
    required this.kind,
    required this.locator,
    required this.candidateCount,
    this.preselectedNames = const [],
    this.scopeGlobalPreselected = false,
    this.preselectedAgentNames = const [],
    this.unmatchedSkillNames = const [],
    this.ignoredFlags = const [],
    super.key,
  });

  final SkillSourceKind kind;
  final String locator;
  final int candidateCount;
  final List<String> preselectedNames;
  final bool scopeGlobalPreselected;
  final List<String> preselectedAgentNames;
  final List<String> unmatchedSkillNames;
  final List<String> ignoredFlags;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kindLabel = switch (kind) {
      SkillSourceKind.local => l10n.acquisitionLocalFolder,
      SkillSourceKind.git => l10n.acquisitionGitRepository,
      SkillSourceKind.wellKnown => l10n.acquisitionWebSourceUrl,
    };
    final notes = <String>[
      if (scopeGlobalPreselected) l10n.acquisitionPreselectedScopeGlobal,
      if (preselectedAgentNames.isNotEmpty)
        l10n.acquisitionPreselectedAgents(preselectedAgentNames.join(', ')),
      if (unmatchedSkillNames.isNotEmpty)
        l10n.acquisitionUnmatchedSkills(unmatchedSkillNames.join(', ')),
      if (ignoredFlags.isNotEmpty)
        l10n.acquisitionIgnoredFlags(ignoredFlags.join(' ')),
    ];
    return Container(
      key: const Key('smart-source-result'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SourceKindBadge(type: kind),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.acquisitionDetectedKind(
                        kindLabel,
                        candidateCount,
                        candidateCount == 1 ? '' : 's',
                      ),
                      style: AppTypography.of(context).body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppPalette.of(context).ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      locator,
                      style: AppTypography.of(context).mono.copyWith(
                        color: AppPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (preselectedNames.isNotEmpty || notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preselectedNames.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l10n.acquisitionPreselectedSkills,
                          style: AppTypography.of(context).caption.copyWith(
                            color: AppPalette.of(context).textSecondary,
                          ),
                        ),
                        for (final name in preselectedNames)
                          _MonoChip(text: name, outlined: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.acquisitionPreselectedSkillsNote,
                      style: AppTypography.of(context).caption.copyWith(
                        color: AppPalette.of(context).textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                  for (final note in notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        note,
                        style: AppTypography.of(context).caption.copyWith(
                          color: AppPalette.of(context).textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
