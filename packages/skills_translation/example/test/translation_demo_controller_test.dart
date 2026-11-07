import 'package:flutter_test/flutter_test.dart';
import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation_example/application/translation_demo_config.dart';
import 'package:skills_translation_example/application/translation_demo_controller.dart';
import 'package:skills_translation_example/application/translation_demo_state.dart';
import 'package:skills_translation_example/infrastructure/markdown_document_loader.dart';

import 'support/fakes.dart';

void main() {
  group('buildDemoSourceDocument', () {
    test('derives stable demo identity from an opened Markdown file', () {
      final document = buildDemoSourceDocument(
        content: 'hello',
        sourcePath: '/tmp/my-skill/references/guide.md',
      );

      expect(document.slotKey, 'references');
      expect(document.documentIdentifier, 'guide.md');
      expect(
        document.contentHash,
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
      expect(document.content, 'hello');
    });

    test('uses the editor identity when there is no source path', () {
      final document = buildDemoSourceDocument(
        content: '# Hello',
        sourcePath: null,
      );

      expect(document.slotKey, 'example-editor');
      expect(document.documentIdentifier, 'SKILL.md');
    });
  });

  group('TranslationDemoController', () {
    late FakeTranslationDemoRepository repository;
    late FakeMarkdownDocumentLoader loader;
    late TranslationDemoController controller;

    setUp(() {
      repository = FakeTranslationDemoRepository();
      loader = FakeMarkdownDocumentLoader();
      controller = TranslationDemoController(
        repository: repository,
        documentLoader: loader,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('switching Provider clears Provider-specific credentials', () {
      controller.setModelIdentifier('gpt-example');
      controller.setApiKey('secret');
      controller.setProvider(TranslationDemoProvider.anthropic);

      expect(
        controller.state.config.provider,
        TranslationDemoProvider.anthropic,
      );
      expect(
        controller.state.config.apiBaseUri,
        'https://api.anthropic.com/v1',
      );
      expect(controller.state.config.modelIdentifier, isEmpty);
      expect(controller.state.config.apiKey, isEmpty);
      expect(controller.state.config.targetLanguage, 'zh-Hans');
      expect(controller.state.config.segmentCharacterBudgetText, '2000');
      expect(controller.state.config.maxConcurrentSegments, 3);
      expect(controller.state.config.reasoningEnabled, isFalse);

      controller.setReasoningEnabled(true);

      controller.setProvider(TranslationDemoProvider.openAICompatible);
      expect(
        controller.state.config.apiBaseUri,
        'http://100.127.216.82:11434/v1',
      );
      expect(controller.state.config.reasoningEnabled, isTrue);
    });

    test('updates reasoning and locks it while busy', () async {
      controller.setReasoningEnabled(true);
      expect(controller.state.config.reasoningEnabled, isTrue);

      controller.setModelIdentifier('gpt-example');
      final running = controller.translate();
      controller.setReasoningEnabled(false);
      expect(controller.state.config.reasoningEnabled, isTrue);

      await controller.cancel();
      await running;
    });

    test('updates concurrency within the demo range and locks it while busy',
        () async {
      controller.setMaxConcurrentSegments(8);
      controller.setMaxConcurrentSegments(9);
      expect(controller.state.config.maxConcurrentSegments, 8);

      controller.setModelIdentifier('gpt-example');
      final running = controller.translate();
      controller.setMaxConcurrentSegments(2);
      expect(controller.state.config.maxConcurrentSegments, 8);

      await controller.cancel();
      await running;
    });

    test('loads a selected Markdown file into the editable source', () async {
      loader.document = const LoadedMarkdownDocument(
        path: '/tmp/example-skill/SKILL.md',
        content: '# Loaded',
      );

      await controller.loadMarkdown();

      expect(controller.state.sourcePath, '/tmp/example-skill/SKILL.md');
      expect(controller.state.sourceContent, '# Loaded');
      expect(controller.state.phase, TranslationDemoPhase.idle);
      expect(controller.state.statusMessage, 'Loaded SKILL.md.');
    });

    test('does not start Anthropic without an API key', () async {
      controller.setProvider(TranslationDemoProvider.anthropic);
      controller.setModelIdentifier('claude-example');

      await controller.translate();

      expect(repository.startCount, 0);
      expect(controller.state.phase, TranslationDemoPhase.failed);
      expect(
        controller.state.statusMessage,
        'Anthropic Messages requires an API key.',
      );
    });

    test('rejects API Base URIs that contain user information', () async {
      controller.setModelIdentifier('gpt-example');
      controller.setApiBaseUri('https://user:secret@example.com/v1');

      await controller.translate();

      expect(repository.startCount, 0);
      expect(controller.state.phase, TranslationDemoPhase.failed);
      expect(
        controller.state.statusMessage,
        'Enter an HTTP(S) API Base URI without credentials.',
      );
    });

    test('validates optional Max Output Tokens before starting a Job',
        () async {
      controller.setModelIdentifier('gpt-example');
      controller.setMaxOutputTokens('0');

      await controller.translate();

      expect(repository.startCount, 0);
      expect(controller.state.phase, TranslationDemoPhase.failed);
      expect(
        controller.state.statusMessage,
        'Max Output Tokens must be a positive integer or left blank.',
      );

      controller.setMaxOutputTokens('16384');
      final running = controller.translate();
      expect(repository.lastConfig?.maxOutputTokensText, '16384');
      await controller.cancel();
      await running;
    });

    test('validates Segment Character Budget before starting a Job', () async {
      controller.setModelIdentifier('gpt-example');
      controller.setSegmentCharacterBudget('0');

      await controller.translate();

      expect(repository.startCount, 0);
      expect(controller.state.phase, TranslationDemoPhase.failed);
      expect(
        controller.state.statusMessage,
        'Segment Character Budget must be a positive integer.',
      );

      controller.setSegmentCharacterBudget('2048');
      final running = controller.translate();
      expect(repository.lastConfig?.segmentCharacterBudgetText, '2048');
      await controller.cancel();
      await running;
    });

    test('publishes cumulative Drafts and the Completed Translation', () async {
      controller.setModelIdentifier('gpt-example');

      final running = controller.translate();
      repository.nextJob.addDraft('# 已翻译');
      await Future<void>.value();

      expect(repository.startCount, 1);
      expect(
        repository.lastConfig?.protocol,
        OpenAICompatibleProtocol.responses,
      );
      expect(controller.state.translatedContent, contains('# 已翻译'));
      expect(
        controller.state.translatedContent,
        contains('description: A small Markdown document'),
      );

      await repository.nextJob.complete(
        CompletedTranslation(
          slotKey: repository.lastSourceDocument!.slotKey,
          contentHash: repository.lastSourceDocument!.contentHash,
          documentIdentifier: repository.lastSourceDocument!.documentIdentifier,
          targetLanguage: TargetLanguage('zh-Hans'),
          translatedContent: '# 完成',
          provenance: TranslationProvenance(
            providerIdentifier: 'openai-compatible',
            modelIdentifier: 'gpt-example',
          ),
        ),
      );
      await running;

      expect(controller.state.phase, TranslationDemoPhase.completed);
      expect(controller.state.translatedContent, '# 完成');
      expect(
        controller.state.provenance?.providerIdentifier,
        'openai-compatible',
      );
    });

    test('presents a typed sanitized Translation Failure', () async {
      controller.setModelIdentifier('gpt-example');
      final running = controller.translate();
      repository.nextJob.addDraft('# 将被丢弃的草稿');
      await Future<void>.value();

      await repository.nextJob.complete(
        TranslationFailure(
          code: TranslationFailureCode.rateLimited,
          reason: 'The Provider is rate limiting requests.',
        ),
      );
      await running;

      expect(controller.state.phase, TranslationDemoPhase.failed);
      expect(
        controller.state.statusMessage,
        'rateLimited: The Provider is rate limiting requests.',
      );
      expect(controller.state.provenance, isNull);
      expect(
        controller.state.translatedContent,
        repository.lastSourceDocument!.content,
      );
    });

    test('cancels the active Job and exposes a distinct cancelled state',
        () async {
      controller.setModelIdentifier('gpt-example');
      final running = controller.translate();

      await controller.cancel();
      await running;

      expect(repository.nextJob.cancelCount, 1);
      expect(controller.state.phase, TranslationDemoPhase.cancelled);
      expect(controller.state.statusMessage, 'Translation cancelled.');
    });
  });
}
