import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';

class CustomAgentEditorDialog extends ConsumerStatefulWidget {
  const CustomAgentEditorDialog({this.agent, this.platform, super.key});
  final CustomAgentSettings? agent;
  final AppDesktopPlatform? platform;
  @override
  ConsumerState<CustomAgentEditorDialog> createState() =>
      _CustomAgentEditorDialogState();
}

class _CustomAgentEditorDialogState
    extends ConsumerState<CustomAgentEditorDialog> {
  late final TextEditingController _name;
  late String _icon;
  late final AppDesktopPlatform _platform;
  late final ({
    TextEditingController global,
    TextEditingController project,
    TextEditingController globalDiscovery,
    TextEditingController projectDiscovery,
  })
  _fields;
  bool _advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    final agent = widget.agent;
    _name = TextEditingController(text: agent?.displayName ?? '');
    _icon = agent?.iconName ?? 'bot';
    _platform = widget.platform ?? _currentDesktopPlatform();
    final settings = agent?.platforms[_platform];
    _fields = (
      global: TextEditingController(text: settings?.globalSkillsPath ?? ''),
      project: TextEditingController(text: settings?.projectSkillsPath ?? ''),
      globalDiscovery: TextEditingController(
        text: settings?.globalDiscoverySkillsPaths.join('\n') ?? '',
      ),
      projectDiscovery: TextEditingController(
        text: settings?.projectDiscoverySkillsPaths.join('\n') ?? '',
      ),
    );
    _advancedExpanded =
        _fields.globalDiscovery.text.isNotEmpty ||
        _fields.projectDiscovery.text.isNotEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    _fields.global.dispose();
    _fields.project.dispose();
    _fields.globalDiscovery.dispose();
    _fields.projectDiscovery.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) => AppDialogScaffold(
    width: AppDialogWidths.wide,
    onEscape: _close,
    header: AppDialogHeader(
      icon: LucideIcons.wandSparkles,
      title: widget.agent == null
          ? context.l10n.settingsAddAgent
          : context.l10n.settingsEditAgent,
      subtitle: context.l10n.customAgentEditorSubtitle,
      actions: [appDialogCloseButton(context, onPressed: _close)],
    ),
    sections: [
      AppDialogSection(
        title: context.l10n.customAgentBasicTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              context.l10n.settingsAgentName,
              _name,
              fieldKey: const Key('custom-agent-name'),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsAgentIcon,
              style: AppTypography.of(context).body
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final name in const [
                  'bot',
                  'terminal',
                  'sparkles',
                  'brainCircuit',
                  'braces',
                  'cpu',
                  'wandSparkles',
                ])
                  _iconChoice(name),
              ],
            ),
          ],
        ),
      ),
      AppDialogSection(
        title: context.l10n.customAgentSkillsFoldersTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              context.l10n.settingsAgentPathGlobal,
              _fields.global,
              fieldKey: Key('custom-agent-${_platform.name}-global'),
              suffix: AppIconButton(
                key: const Key('custom-agent-choose-global-directory'),
                icon: LucideIcons.folderOpen,
                tooltip: context.l10n.settingsAgentChooseGlobalDirectory,
                style: NeoButtonVariant.ghost,
                onPressed: _pickGlobalDirectory,
              ),
            ),
            const SizedBox(height: 10),
            _field(
              context.l10n.settingsAgentPathProject,
              _fields.project,
              fieldKey: Key('custom-agent-${_platform.name}-project'),
            ),
          ],
        ),
      ),
      AppDialogSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                key: const Key('custom-agent-advanced-toggle'),
                label: _advancedExpanded
                    ? context.l10n.settingsAgentAdvancedHide
                    : context.l10n.settingsAgentAdvancedShow,
                icon: _advancedExpanded
                    ? LucideIcons.chevronUp
                    : LucideIcons.chevronDown,
                style: NeoButtonVariant.ghost,
                onPressed: () =>
                    setState(() => _advancedExpanded = !_advancedExpanded),
              ),
            ),
            AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _advancedExpanded
                  ? Padding(
                      key: const Key('custom-agent-advanced-fields'),
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _field(
                            context.l10n.settingsAgentDiscoveryPathsGlobal,
                            _fields.globalDiscovery,
                            fieldKey: Key(
                              'custom-agent-${_platform.name}-global-discovery',
                            ),
                            maxLines: 3,
                            helper:
                                context.l10n.settingsAgentDiscoveryPathsHint,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            context.l10n.settingsAgentDiscoveryPathsProject,
                            _fields.projectDiscovery,
                            fieldKey: Key(
                              'custom-agent-${_platform.name}-project-discovery',
                            ),
                            maxLines: 3,
                            helper:
                                context.l10n.settingsAgentDiscoveryPathsHint,
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    ],
    footer: AppDialogFooter(
      actions: [
        AppButton(label: context.l10n.commonCancel, onPressed: _close),
        AppButton(
          key: const Key('custom-agent-save'),
          label: context.l10n.settingsSaveAgent,
          icon: LucideIcons.save,
          style: NeoButtonVariant.primary,
          onPressed: _save,
        ),
      ],
    ),
  );

  Widget _iconChoice(String name) => GestureDetector(
    onTap: () => setState(() => _icon = name),
    child: Container(
      width: 38,
      height: 38,
      decoration: AppCorners.smooth(
        color: _icon == name
            ? AppPalette.of(context).ink
            : AppPalette.of(context).surfaceMuted,
        radius: 10,
      ),
      alignment: Alignment.center,
      child: Icon(
        AgentLogo.iconFor(name),
        size: 19,
        color: _icon == name
            ? AppPalette.of(context).white
            : AppPalette.of(context).bodyContent,
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    Key? fieldKey,
    int maxLines = 1,
    String? helper,
    Widget? suffix,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: AppTypography.of(context).body
            .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 5),
      CupertinoTextField(
        key: fieldKey,
        controller: controller,
        minLines: maxLines,
        maxLines: maxLines,
        suffix: suffix,
        suffixMode: OverlayVisibilityMode.always,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppPalette.of(context).surfaceMuted,
          border: Border.all(color: AppPalette.of(context).border),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        style: AppTypography.of(context).body,
      ),
      if (helper != null) ...[
        const SizedBox(height: 5),
        Text(helper, style: AppTypography.of(context).caption),
      ],
    ],
  );

  Future<void> _pickGlobalDirectory() async {
    final current = _fields.global.text.trim();
    final path = await ref
        .read(directoryPickerProvider)
        .pickDirectory(initialDirectory: current.isEmpty ? null : current);
    if (path != null && mounted) _fields.global.text = path;
  }

  void _save() {
    final id =
        widget.agent?.id ??
        'custom-${_slug(_name.text)}-${_shortHash(_name.text, _platform, _fields)}';
    final platforms = Map<AppDesktopPlatform, CustomAgentPlatformSettings>.of(
      widget.agent?.platforms ?? const {},
    );
    final global = _fields.global.text.trim();
    final project = _fields.project.text.trim();
    try {
      if (global.isEmpty && project.isEmpty) {
        throw const FormatException('Current platform needs a skill path.');
      }
      platforms[_platform] = CustomAgentPlatformSettings(
        globalSkillsPath: global.isEmpty ? null : global,
        projectSkillsPath: project.isEmpty ? null : project,
        globalDiscoverySkillsPaths: _paths(_fields.globalDiscovery.text),
        projectDiscoverySkillsPaths: _paths(_fields.projectDiscovery.text),
      );
      final agent = CustomAgentSettings(
        id: id,
        displayName: _name.text.trim(),
        iconName: _icon,
        platforms: platforms,
      );
      agent.validate();
      Navigator.of(context).pop(agent);
    } on Object {
      showAppConfirmDialog(
        context: context,
        icon: LucideIcons.triangleAlert,
        tone: AppDialogTone.warning,
        title: context.l10n.customAgentInvalidPathTitle,
        message: context.l10n.settingsAgentInvalidPath,
        confirmLabel: context.l10n.commonDone,
        showCancel: false,
      );
    }
  }
}

String _slug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'agent' : slug;
}

String _shortHash(
  String name,
  AppDesktopPlatform platform,
  ({
    TextEditingController global,
    TextEditingController project,
    TextEditingController globalDiscovery,
    TextEditingController projectDiscovery,
  })
  fields,
) {
  var hash = 0xcbf29ce484222325;
  final input = StringBuffer(name)
    ..write('|')
    ..write(platform.name)
    ..write('|')
    ..write(fields.global.text.trim())
    ..write('|')
    ..write(fields.project.text.trim())
    ..write('|')
    ..write(_paths(fields.globalDiscovery.text).join('\n'))
    ..write('|')
    ..write(_paths(fields.projectDiscovery.text).join('\n'));
  for (final unit in input.toString().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0').substring(0, 8);
}

AppDesktopPlatform _currentDesktopPlatform() => switch (defaultTargetPlatform) {
  TargetPlatform.macOS => AppDesktopPlatform.macos,
  TargetPlatform.windows => AppDesktopPlatform.windows,
  TargetPlatform.linux => AppDesktopPlatform.linux,
  _ => throw UnsupportedError('Custom Agents require a desktop platform.'),
};

List<String> _paths(String value) {
  final seen = <String>{};
  return List.unmodifiable([
    for (final line in value.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty && seen.add(line.trim())) line.trim(),
  ]);
}
