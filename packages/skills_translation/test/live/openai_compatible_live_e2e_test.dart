import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:skills_translation/skills_translation.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final environment = Platform.environment;
  final apiKey = environment['SKILLS_TRANSLATION_E2E_API_KEY']?.trim() ?? '';
  final apiBaseUri = environment['SKILLS_TRANSLATION_E2E_API_BASE_URI'];
  final modelIdentifier = environment['SKILLS_TRANSLATION_E2E_MODEL'];
  final skillPath = environment['SKILLS_TRANSLATION_E2E_SKILL_PATH'];
  final missingConfiguration = <String>[
    if (apiBaseUri == null || apiBaseUri.trim().isEmpty)
      'SKILLS_TRANSLATION_E2E_API_BASE_URI',
    if (modelIdentifier == null || modelIdentifier.trim().isEmpty)
      'SKILLS_TRANSLATION_E2E_MODEL',
    if (skillPath == null || skillPath.trim().isEmpty)
      'SKILLS_TRANSLATION_E2E_SKILL_PATH',
  ];
  final maxOutputTokensText =
      environment['SKILLS_TRANSLATION_E2E_MAX_OUTPUT_TOKENS']?.trim();
  final maxOutputTokens =
      maxOutputTokensText == null || maxOutputTokensText.isEmpty
          ? null
          : int.parse(maxOutputTokensText);
  final segmentCharacterBudgetText =
      environment['SKILLS_TRANSLATION_E2E_SEGMENT_CHARACTER_BUDGET']?.trim();
  final segmentCharacterBudget =
      segmentCharacterBudgetText == null || segmentCharacterBudgetText.isEmpty
          ? 2000
          : int.parse(segmentCharacterBudgetText);
  final maxConcurrentSegmentsText =
      environment['SKILLS_TRANSLATION_E2E_MAX_CONCURRENT_SEGMENTS']?.trim();
  final maxConcurrentSegments =
      maxConcurrentSegmentsText == null || maxConcurrentSegmentsText.isEmpty
          ? 1
          : int.parse(maxConcurrentSegmentsText);
  final protocol = switch (environment['SKILLS_TRANSLATION_E2E_PROTOCOL']
      ?.trim()
      .toLowerCase()) {
    'chat' => OpenAICompatibleProtocol.chatCompletions,
    _ => OpenAICompatibleProtocol.responses,
  };
  final reasoningEnabled =
      switch (environment['SKILLS_TRANSLATION_E2E_REASONING_ENABLED']
          ?.trim()
          .toLowerCase()) {
        '1' || 'true' || 'yes' => true,
        _ => false,
      };

  test(
    'translates a real Skill through a live OpenAI-compatible endpoint',
    () async {
      final sourceFile = File(skillPath!);
      expect(
        await sourceFile.exists(),
        isTrue,
        reason: 'The configured real Skill file must exist.',
      );
      final source = await sourceFile.readAsString();
      final sourceFrontmatter = _frontmatter(source);
      expect(sourceFrontmatter, isNotNull);
      final parsedSourceFrontmatter = loadYaml(sourceFrontmatter!) as YamlMap;
      expect(parsedSourceFrontmatter['name'], isA<String>());
      final skillName = parsedSourceFrontmatter['name'] as String;
      final sourceCodeBlocks = _fencedCodeBlocks(source);

      final provider = OpenAICompatibleTranslationProvider(
        apiBaseUri: Uri.parse(apiBaseUri!),
        modelIdentifier: modelIdentifier!,
        apiKey: apiKey,
        providerIdentifier: 'live-openai-compatible-e2e',
        protocol: protocol,
        options: TranslationProviderOptions(
          inactivityTimeout: const Duration(minutes: 3),
          segmentCharacterBudget: segmentCharacterBudget,
          maxConcurrentSegments: maxConcurrentSegments,
          maxOutputTokens: maxOutputTokens,
          temperature: null,
          reasoningEnabled: reasoningEnabled,
        ),
      );
      final sourceDocument = SourceDocument(
        slotKey: 'live-e2e-$skillName',
        contentHash: sha256.convert(utf8.encode(source)).toString(),
        documentIdentifier: 'SKILL.md',
        content: source,
      );
      final job = provider.start(
        sourceDocument: sourceDocument,
        targetLanguage: TargetLanguage('zh-Hans'),
      );
      var draftCount = 0;
      final drafts = job.drafts.listen((_) => draftCount += 1);

      final outcome = await job.result;
      await drafts.cancel();

      if (outcome case TranslationFailure(:final code, :final reason)) {
        fail('Live translation failed safely: ${code.name}: $reason');
      }
      if (outcome is TranslationJobCancellation) {
        fail('Live translation was unexpectedly cancelled.');
      }
      expect(outcome, isA<CompletedTranslation>());
      final completed = outcome as CompletedTranslation;
      final outputPath =
          environment['SKILLS_TRANSLATION_E2E_OUTPUT_PATH']?.trim();
      if (outputPath != null && outputPath.isNotEmpty) {
        await File(outputPath).writeAsString(completed.translatedContent);
      }
      expect(completed.slotKey, sourceDocument.slotKey);
      expect(completed.contentHash, sourceDocument.contentHash);
      expect(completed.documentIdentifier, sourceDocument.documentIdentifier);
      expect(completed.targetLanguage, TargetLanguage('zh-Hans'));
      expect(
        completed.provenance.providerIdentifier,
        'live-openai-compatible-e2e',
      );
      expect(completed.provenance.modelIdentifier, modelIdentifier);
      expect(draftCount, greaterThan(0));
      expect(completed.translatedContent, contains(RegExp(r'[\u3400-\u9fff]')));
      expect(completed.translatedContent, startsWith('---\n'));
      final translatedFrontmatter = _frontmatter(completed.translatedContent);
      expect(translatedFrontmatter, isNotNull);
      final parsedFrontmatter = loadYaml(translatedFrontmatter!) as YamlMap;
      expect(parsedFrontmatter['name'], skillName);
      expect(parsedFrontmatter['description'], isA<String>());
      expect(
        parsedFrontmatter['description'] as String,
        contains(RegExp(r'[\u3400-\u9fff]')),
      );
      expect(
        _fencedCodeBlocks(completed.translatedContent),
        sourceCodeBlocks,
        reason: 'Fenced code blocks must be preserved byte-for-byte.',
      );
      expect(completed.translatedContent, isNot(contains('BEGIN MARKDOWN')));
      expect(completed.translatedContent, isNot(contains('END MARKDOWN')));
      if (!source.contains('%%')) {
        expect(
          completed.translatedContent,
          isNot(contains('%%')),
          reason: 'Provider wire separators must not leak into the document.',
        );
      }
      expect(
        completed.translatedContent,
        isNot(
          matches(
            RegExp(
              r'<\s*/?\s*(?:think|analysis|ai-analysis)\b',
              caseSensitive: false,
            ),
          ),
        ),
        reason: 'Provider analysis must never appear in translated content.',
      );

      // This contains no credential, Source content, or Provider response.
      // ignore: avoid_print
      print(
        'Live translation completed: '
        '$draftCount drafts, ${source.length} source characters, '
        '${completed.translatedContent.length} translated characters.',
      );
    },
    skip:
        missingConfiguration.isEmpty
            ? false
            : 'Live E2E requires: ${missingConfiguration.join(', ')}.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

String? _frontmatter(String markdown) => RegExp(
  r'^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)',
).firstMatch(markdown)?.group(1);

List<String> _fencedCodeBlocks(String markdown) =>
    RegExp(
      r'^```[^\n]*\n[\s\S]*?^```[ \t]*$',
      multiLine: true,
    ).allMatches(markdown).map((match) => match.group(0)!).toList();
