import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation_example/app.dart';
import 'package:skills_translation_example/application/translation_demo_controller.dart';
import 'package:skills_translation_example/application/translation_demo_state.dart';
import 'package:skills_translation_example/infrastructure/markdown_document_loader.dart';

import 'support/fakes.dart';

void main() {
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition,
    String Function() diagnostics,
  ) async {
    for (var attempt = 0; attempt < 20 && !condition(); attempt += 1) {
      await tester.pump();
    }
    expect(condition(), isTrue, reason: diagnostics());
    await tester.pump();
  }

  Future<
      ({
        TranslationDemoController controller,
        FakeTranslationDemoRepository repository,
        FakeMarkdownDocumentLoader loader,
      })> pumpExample(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeTranslationDemoRepository();
    final loader = FakeMarkdownDocumentLoader();
    final controller = TranslationDemoController(
      repository: repository,
      documentLoader: loader,
    );
    await tester.pumpWidget(
      SkillsTranslationExampleApp(controller: controller),
    );
    return (
      controller: controller,
      repository: repository,
      loader: loader,
    );
  }

  testWidgets('shows the editable sample and memory-only Provider controls',
      (tester) async {
    await pumpExample(tester);

    expect(find.text('skills_translation'), findsOneWidget);
    expect(find.byKey(const ValueKey('source_editor')), findsOneWidget);
    expect(find.text('Responses'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    final apiBaseField = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('api_base_field')),
    );
    expect(apiBaseField.controller?.text, 'http://100.127.216.82:11434/v1');
    final apiKeyField = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('api_key_field')),
    );
    expect(apiKeyField.obscureText, isTrue);
    expect(apiKeyField.placeholder, 'Kept in memory only');
    final maxOutputTokensField = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('max_output_tokens_field')),
    );
    expect(maxOutputTokensField.controller?.text, isEmpty);
    expect(maxOutputTokensField.placeholder, 'Provider default');
    final segmentCharacterBudgetField = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('segment_character_budget_field')),
    );
    expect(segmentCharacterBudgetField.controller?.text, '2000');
    expect(segmentCharacterBudgetField.keyboardType, TextInputType.number);
    expect(find.text('Segment concurrency'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Reasoning'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoSwitch>(
            find.byKey(const ValueKey('reasoning_switch')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('toggles reasoning and disables the switch while busy',
      (tester) async {
    final harness = await pumpExample(tester);
    final reasoningSwitch = find.byKey(const ValueKey('reasoning_switch'));

    await tester.tap(reasoningSwitch);
    await tester.pump();
    expect(harness.controller.state.config.reasoningEnabled, isTrue);
    expect(find.text('Enabled'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('model_field')),
      'gpt-example',
    );
    await tester.tap(find.byKey(const ValueKey('translate_button')));
    await tester.pump();

    expect(
      tester.widget<CupertinoSwitch>(reasoningSwitch).onChanged,
      isNull,
    );
  });

  testWidgets('edits the optional Max Output Tokens field', (tester) async {
    final harness = await pumpExample(tester);

    await tester.enterText(
      find.byKey(const ValueKey('max_output_tokens_field')),
      '16384',
    );
    await tester.pump();

    expect(harness.controller.state.config.maxOutputTokensText, '16384');
  });

  testWidgets('edits the Segment Character Budget field', (tester) async {
    final harness = await pumpExample(tester);

    await tester.enterText(
      find.byKey(const ValueKey('segment_character_budget_field')),
      '2048',
    );
    await tester.pump();

    expect(
      harness.controller.state.config.segmentCharacterBudgetText,
      '2048',
    );
  });

  testWidgets('steps concurrency from 1 to 8 and disables it while busy',
      (tester) async {
    final harness = await pumpExample(tester);
    final decrease = find.byKey(
      const ValueKey('decrease_concurrency_button'),
    );
    final increase = find.byKey(
      const ValueKey('increase_concurrency_button'),
    );

    for (var value = 3; value < 8; value += 1) {
      await tester.tap(increase);
      await tester.pump();
    }
    expect(harness.controller.state.config.maxConcurrentSegments, 8);
    expect(tester.widget<CupertinoButton>(increase).onPressed, isNull);

    for (var value = 8; value > 1; value -= 1) {
      await tester.tap(decrease);
      await tester.pump();
    }
    expect(harness.controller.state.config.maxConcurrentSegments, 1);
    expect(tester.widget<CupertinoButton>(decrease).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('model_field')),
      'gpt-example',
    );
    await tester.tap(find.byKey(const ValueKey('translate_button')));
    await tester.pump();

    expect(tester.widget<CupertinoButton>(increase).onPressed, isNull);
    expect(tester.widget<CupertinoButton>(decrease).onPressed, isNull);
  });

  testWidgets('switches to Anthropic without retaining OpenAI credentials',
      (tester) async {
    final harness = await pumpExample(tester);
    await tester.enterText(
      find.byKey(const ValueKey('model_field')),
      'gpt-example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('api_key_field')),
      'secret',
    );

    await tester.tap(find.text('Anthropic'));
    await tester.pump();

    expect(find.byKey(const ValueKey('protocol_selector')), findsNothing);
    expect(
      harness.controller.state.config.apiBaseUri,
      'https://api.anthropic.com/v1',
    );
    expect(harness.controller.state.config.modelIdentifier, isEmpty);
    expect(harness.controller.state.config.apiKey, isEmpty);
  });

  testWidgets('loads Markdown through the injected document loader',
      (tester) async {
    final harness = await pumpExample(tester);
    harness.loader.document = const LoadedMarkdownDocument(
      path: '/tmp/demo-skill/SKILL.md',
      content: '# Opened Skill',
    );

    await tester.tap(find.byKey(const ValueKey('open_markdown_button')));
    await tester.pump();

    final editor = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('source_editor')),
    );
    expect(editor.controller?.text, '# Opened Skill');
    expect(find.text('SKILL.md'), findsOneWidget);
  });

  testWidgets('renders streaming Drafts and completed provenance',
      (tester) async {
    final harness = await pumpExample(tester);
    await tester.enterText(
      find.byKey(const ValueKey('model_field')),
      'gpt-example',
    );

    await tester.tap(find.byKey(const ValueKey('translate_button')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('cancel_translation_button')),
      findsOneWidget,
    );

    harness.repository.nextJob.addDraft('# 流式草稿');
    await tester.pump();
    var output = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('translation_output')),
    );
    expect(output.controller?.text, contains('# 流式草稿'));
    expect(
        output.controller?.text, startsWith('---\nname: translation-example'));

    final source = harness.repository.lastSourceDocument!;
    await harness.repository.nextJob.complete(
      CompletedTranslation(
        slotKey: source.slotKey,
        contentHash: source.contentHash,
        documentIdentifier: source.documentIdentifier,
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: '# 翻译完成',
        provenance: TranslationProvenance(
          providerIdentifier: 'openai-compatible',
          modelIdentifier: 'gpt-example',
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => harness.controller.state.phase == TranslationDemoPhase.completed,
      () => 'phase: ${harness.controller.state.phase}',
    );

    output = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('translation_output')),
    );
    expect(output.controller?.text, '# 翻译完成');
    expect(find.text('openai-compatible · gpt-example'), findsOneWidget);
    expect(find.text('Translation completed.'), findsOneWidget);
  });

  testWidgets('cancels an active Translation Job', (tester) async {
    final harness = await pumpExample(tester);
    await tester.enterText(
      find.byKey(const ValueKey('model_field')),
      'gpt-example',
    );
    await tester.tap(find.byKey(const ValueKey('translate_button')));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('cancel_translation_button')),
    );
    await pumpUntil(
      tester,
      () => harness.controller.state.phase == TranslationDemoPhase.cancelled,
      () => 'phase: ${harness.controller.state.phase}',
    );

    expect(harness.repository.nextJob.cancelCount, 1);
    expect(find.text('Translation cancelled.'), findsOneWidget);
    expect(find.byKey(const ValueKey('translate_button')), findsOneWidget);
  });
}
