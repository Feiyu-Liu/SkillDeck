// Keep the SDK library for the example's Flutter 3.29 compatibility floor.
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;
import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation_example/application/translation_demo_config.dart';
import 'package:skills_translation_example/application/translation_demo_controller.dart';
import 'package:skills_translation_example/application/translation_demo_state.dart';

const Color _surface = Color(0xFFFFFFFF);
const Color _border = Color(0x1A1A1A1A);
const Color _secondaryText = Color(0xFF6E6E73);
const Color _editorBackground = Color(0xFFF7F7F8);

final class TranslationDemoScreen extends StatefulWidget {
  const TranslationDemoScreen({
    required this.controller,
    super.key,
  });

  final TranslationDemoController controller;

  @override
  State<TranslationDemoScreen> createState() => _TranslationDemoScreenState();
}

final class _TranslationDemoScreenState extends State<TranslationDemoScreen> {
  late final TextEditingController _apiBaseController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _targetLanguageController;
  late final TextEditingController _segmentCharacterBudgetController;
  late final TextEditingController _maxOutputTokensController;
  late final TextEditingController _sourceController;
  late final TextEditingController _outputController;
  var _showApiKey = false;

  @override
  void initState() {
    super.initState();
    final state = widget.controller.state;
    _apiBaseController = TextEditingController(text: state.config.apiBaseUri);
    _modelController = TextEditingController(
      text: state.config.modelIdentifier,
    );
    _apiKeyController = TextEditingController(text: state.config.apiKey);
    _targetLanguageController = TextEditingController(
      text: state.config.targetLanguage,
    );
    _segmentCharacterBudgetController = TextEditingController(
      text: state.config.segmentCharacterBudgetText,
    );
    _maxOutputTokensController = TextEditingController(
      text: state.config.maxOutputTokensText,
    );
    _sourceController = TextEditingController(text: state.sourceContent);
    _outputController = TextEditingController(text: state.translatedContent);
    widget.controller.addListener(_synchronizeControllers);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_synchronizeControllers);
    _apiBaseController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    _targetLanguageController.dispose();
    _segmentCharacterBudgetController.dispose();
    _maxOutputTokensController.dispose();
    _sourceController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  void _synchronizeControllers() {
    final state = widget.controller.state;
    _replaceTextIfChanged(_apiBaseController, state.config.apiBaseUri);
    _replaceTextIfChanged(_modelController, state.config.modelIdentifier);
    _replaceTextIfChanged(_apiKeyController, state.config.apiKey);
    _replaceTextIfChanged(
      _targetLanguageController,
      state.config.targetLanguage,
    );
    _replaceTextIfChanged(
      _segmentCharacterBudgetController,
      state.config.segmentCharacterBudgetText,
    );
    _replaceTextIfChanged(
      _maxOutputTokensController,
      state.config.maxOutputTokensText,
    );
    _replaceTextIfChanged(_sourceController, state.sourceContent);
    _replaceTextIfChanged(_outputController, state.translatedContent);
  }

  void _replaceTextIfChanged(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final state = widget.controller.state;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _PageHeader(),
                    const SizedBox(height: 16),
                    _ConfigurationCard(
                      state: state,
                      controller: widget.controller,
                      apiBaseController: _apiBaseController,
                      modelController: _modelController,
                      apiKeyController: _apiKeyController,
                      targetLanguageController: _targetLanguageController,
                      segmentCharacterBudgetController:
                          _segmentCharacterBudgetController,
                      maxOutputTokensController: _maxOutputTokensController,
                      showApiKey: _showApiKey,
                      onToggleApiKey: () {
                        setState(() => _showApiKey = !_showApiKey);
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final source = _SourcePanel(
                            state: state,
                            controller: widget.controller,
                            textController: _sourceController,
                          );
                          final output = _OutputPanel(
                            state: state,
                            textController: _outputController,
                          );
                          if (constraints.maxWidth >= 880) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: source),
                                const SizedBox(width: 16),
                                Expanded(child: output),
                              ],
                            );
                          }
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                SizedBox(height: 320, child: source),
                                const SizedBox(height: 16),
                                SizedBox(height: 320, child: output),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
}

final class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'skills_translation',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Translate Markdown through a real Provider and inspect cumulative streaming Drafts.',
            style: TextStyle(color: _secondaryText, fontSize: 13),
          ),
        ],
      );
}

final class _ConfigurationCard extends StatelessWidget {
  const _ConfigurationCard({
    required this.state,
    required this.controller,
    required this.apiBaseController,
    required this.modelController,
    required this.apiKeyController,
    required this.targetLanguageController,
    required this.segmentCharacterBudgetController,
    required this.maxOutputTokensController,
    required this.showApiKey,
    required this.onToggleApiKey,
  });

  final TranslationDemoState state;
  final TranslationDemoController controller;
  final TextEditingController apiBaseController;
  final TextEditingController modelController;
  final TextEditingController apiKeyController;
  final TextEditingController targetLanguageController;
  final TextEditingController segmentCharacterBudgetController;
  final TextEditingController maxOutputTokensController;
  final bool showApiKey;
  final VoidCallback onToggleApiKey;

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                _FieldGroup(
                  label: 'Provider',
                  width: 330,
                  child:
                      CupertinoSlidingSegmentedControl<TranslationDemoProvider>(
                    key: const ValueKey('provider_selector'),
                    groupValue: state.config.provider,
                    onValueChanged: (value) {
                      if (!state.isBusy && value != null) {
                        controller.setProvider(value);
                      }
                    },
                    children: const {
                      TranslationDemoProvider.openAICompatible: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('OpenAI compatible'),
                      ),
                      TranslationDemoProvider.anthropic: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Anthropic'),
                      ),
                    },
                  ),
                ),
                if (state.config.provider ==
                    TranslationDemoProvider.openAICompatible)
                  _FieldGroup(
                    label: 'OpenAI protocol',
                    width: 250,
                    child: CupertinoSlidingSegmentedControl<
                        OpenAICompatibleProtocol>(
                      key: const ValueKey('protocol_selector'),
                      groupValue: state.config.protocol,
                      onValueChanged: (value) {
                        if (!state.isBusy && value != null) {
                          controller.setProtocol(value);
                        }
                      },
                      children: const {
                        OpenAICompatibleProtocol.responses: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Responses'),
                        ),
                        OpenAICompatibleProtocol.chatCompletions: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Chat'),
                        ),
                      },
                    ),
                  ),
                _FieldGroup(
                  label: 'API Base URI',
                  width: 330,
                  child: _TextField(
                    fieldKey: const ValueKey('api_base_field'),
                    controller: apiBaseController,
                    enabled: !state.isBusy,
                    placeholder: 'https://api.example.com/v1',
                    onChanged: controller.setApiBaseUri,
                  ),
                ),
                _FieldGroup(
                  label: 'Model',
                  width: 250,
                  child: _TextField(
                    fieldKey: const ValueKey('model_field'),
                    controller: modelController,
                    enabled: !state.isBusy,
                    placeholder: 'model-id',
                    onChanged: controller.setModelIdentifier,
                  ),
                ),
                _FieldGroup(
                  label:
                      state.config.provider == TranslationDemoProvider.anthropic
                          ? 'API Key (required)'
                          : 'API Key (optional for local gateways)',
                  width: 330,
                  child: _TextField(
                    fieldKey: const ValueKey('api_key_field'),
                    controller: apiKeyController,
                    enabled: !state.isBusy,
                    placeholder: 'Kept in memory only',
                    obscureText: !showApiKey,
                    onChanged: controller.setApiKey,
                    suffix: CupertinoButton(
                      key: const ValueKey('toggle_api_key_visibility'),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      onPressed: onToggleApiKey,
                      child: Icon(
                        showApiKey
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                        size: 17,
                      ),
                    ),
                  ),
                ),
                _FieldGroup(
                  label: 'Target language',
                  width: 180,
                  child: _TextField(
                    fieldKey: const ValueKey('target_language_field'),
                    controller: targetLanguageController,
                    enabled: !state.isBusy,
                    placeholder: 'zh-Hans',
                    onChanged: controller.setTargetLanguage,
                  ),
                ),
                _FieldGroup(
                  label: 'Segment Character Budget',
                  width: 220,
                  child: _TextField(
                    fieldKey: const ValueKey('segment_character_budget_field'),
                    controller: segmentCharacterBudgetController,
                    enabled: !state.isBusy,
                    placeholder: '2000',
                    keyboardType: TextInputType.number,
                    onChanged: controller.setSegmentCharacterBudget,
                  ),
                ),
                _FieldGroup(
                  label: 'Max Output Tokens (optional)',
                  width: 200,
                  child: _TextField(
                    fieldKey: const ValueKey('max_output_tokens_field'),
                    controller: maxOutputTokensController,
                    enabled: !state.isBusy,
                    placeholder: 'Provider default',
                    keyboardType: TextInputType.number,
                    onChanged: controller.setMaxOutputTokens,
                  ),
                ),
                _FieldGroup(
                  label: 'Segment concurrency',
                  width: 180,
                  child: _ConcurrencyStepper(
                    value: state.config.maxConcurrentSegments,
                    enabled: !state.isBusy,
                    onChanged: controller.setMaxConcurrentSegments,
                  ),
                ),
                _FieldGroup(
                  label: 'Reasoning',
                  width: 180,
                  child: _ReasoningToggle(
                    value: state.config.reasoningEnabled,
                    enabled: !state.isBusy,
                    onChanged: controller.setReasoningEnabled,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatusLine(state: state),
                ),
                const SizedBox(width: 12),
                if (state.canCancel)
                  CupertinoButton(
                    key: const ValueKey('cancel_translation_button'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    color: CupertinoColors.systemRed,
                    onPressed: controller.cancel,
                    child: const Text('Cancel'),
                  )
                else
                  CupertinoButton.filled(
                    key: const ValueKey('translate_button'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 9,
                    ),
                    onPressed: state.isBusy ? null : controller.translate,
                    child: const Text('Translate'),
                  ),
              ],
            ),
          ],
        ),
      );
}

final class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});

  final TranslationDemoState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state.phase) {
      TranslationDemoPhase.completed => CupertinoColors.systemGreen,
      TranslationDemoPhase.failed => CupertinoColors.systemRed,
      TranslationDemoPhase.cancelled => CupertinoColors.systemOrange,
      TranslationDemoPhase.translating ||
      TranslationDemoPhase.cancelling ||
      TranslationDemoPhase.loadingSource =>
        CupertinoColors.activeBlue,
      _ => CupertinoColors.systemGrey,
    };
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            state.statusMessage ?? '',
            key: const ValueKey('status_message'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _secondaryText, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

final class _ConcurrencyStepper extends StatelessWidget {
  const _ConcurrencyStepper({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        decoration: BoxDecoration(
          color: _editorBackground,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _stepButton(
              key: const ValueKey('decrease_concurrency_button'),
              icon: CupertinoIcons.minus,
              onPressed:
                  enabled && value > 1 ? () => onChanged(value - 1) : null,
            ),
            Expanded(
              child: Text(
                '$value',
                key: const ValueKey('concurrency_value'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _stepButton(
              key: const ValueKey('increase_concurrency_button'),
              icon: CupertinoIcons.plus,
              onPressed:
                  enabled && value < 8 ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      );

  Widget _stepButton({
    required Key key,
    required IconData icon,
    required VoidCallback? onPressed,
  }) =>
      SizedBox(
        width: 36,
        height: 36,
        child: CupertinoButton(
          key: key,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Icon(icon, size: 15),
        ),
      );
}

final class _ReasoningToggle extends StatelessWidget {
  const _ReasoningToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _editorBackground,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ? 'Enabled' : 'Disabled',
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Transform.scale(
              scale: 0.78,
              child: CupertinoSwitch(
                key: const ValueKey('reasoning_switch'),
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ],
        ),
      );
}

final class _SourcePanel extends StatelessWidget {
  const _SourcePanel({
    required this.state,
    required this.controller,
    required this.textController,
  });

  final TranslationDemoState state;
  final TranslationDemoController controller;
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Source Markdown',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state.sourcePath == null
                        ? 'Built-in editable sample'
                        : p.basename(state.sourcePath!),
                    key: const ValueKey('source_label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ),
                CupertinoButton(
                  key: const ValueKey('open_markdown_button'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  onPressed: state.isBusy ? null : controller.loadMarkdown,
                  child: const Row(
                    children: [
                      Icon(CupertinoIcons.folder_open, size: 16),
                      SizedBox(width: 6),
                      Text('Open .md'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: CupertinoTextField(
                key: const ValueKey('source_editor'),
                controller: textController,
                enabled: !state.isBusy,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _editorBackground,
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(10),
                ),
                style: const TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 13,
                  height: 1.45,
                  fontFamily: 'monospace',
                ),
                onChanged: controller.setSourceContent,
              ),
            ),
          ],
        ),
      );
}

final class _OutputPanel extends StatelessWidget {
  const _OutputPanel({
    required this.state,
    required this.textController,
  });

  final TranslationDemoState state;
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
    final provenance = state.provenance;
    final provenanceText = provenance == null
        ? 'Cumulative Draft appears here'
        : [
            provenance.providerIdentifier,
            if (provenance.modelIdentifier != null) provenance.modelIdentifier!,
          ].join(' · ');
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Translated Markdown',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  provenanceText,
                  key: const ValueKey('provenance_label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: _secondaryText,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: CupertinoTextField(
              key: const ValueKey('translation_output'),
              controller: textController,
              readOnly: true,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              placeholder: 'No translation yet.',
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _editorBackground,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(10),
              ),
              style: const TextStyle(
                color: Color(0xFF333333),
                fontSize: 13,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _FieldGroup extends StatelessWidget {
  const _FieldGroup({
    required this.label,
    required this.width,
    required this.child,
  });

  final String label;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _secondaryText,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            child,
          ],
        ),
      );
}

final class _TextField extends StatelessWidget {
  const _TextField({
    required this.fieldKey,
    required this.controller,
    required this.enabled,
    required this.placeholder,
    required this.onChanged,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final bool enabled;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => CupertinoTextField(
        key: fieldKey,
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        placeholder: placeholder,
        suffix: suffix,
        keyboardType: keyboardType,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: _editorBackground,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(9),
        ),
        style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 13),
        placeholderStyle: const TextStyle(
          color: Color(0xFF9A9A9E),
          fontSize: 13,
        ),
        onChanged: onChanged,
      );
}

final class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: _surface,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      );
}
