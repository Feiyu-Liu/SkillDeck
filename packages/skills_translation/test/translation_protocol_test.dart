import 'package:skills_translation/src/markdown_source_adapter.dart';
import 'package:skills_translation/src/translation_protocol.dart';
import 'package:skills_translation/src/translation_provider_options.dart';
import 'package:test/test.dart';

void main() {
  group('translation plain-text protocol', () {
    test(
      'reserves description and batches Markdown blocks by source order',
      () {
        final document = TranslationMarkdownSource.parse(
          '---\ndescription: Demo.\n---\n# A\n\nB',
        );
        final segments = createTranslationSegments(
          document: document,
          characterBudget: 100,
        );

        expect(segments, hasLength(2));
        expect(segments.first.units.single.wireId, 'frontmatter:description');
        expect(segments.last.units.map((unit) => unit.wireId), [
          'b:0:3',
          'b:5:6',
        ]);
        expect(
          segments.first.userPrompt('zh-Hans'),
          contains('Translate to zh-Hans (output translation only):'),
        );
        expect(segments.last.userPrompt('zh-Hans'), contains('# A\n\n%%\n\nB'));
        expect(segments.last.userPrompt('zh-Hans'), isNot(contains('blockId')));
      },
    );

    test('description-only segmentation never includes body blocks', () {
      final segments = createTranslationSegments(
        document: TranslationMarkdownSource.parse(
          '---\ndescription: Purpose.\n---\n# Private body',
        ),
        characterBudget: 100,
        descriptionOnly: true,
      );
      expect(segments, hasLength(1));
      expect(segments.single.units.single.source, 'Purpose.');
      expect(
        segments.single.userPrompt('zh-Hans'),
        isNot(contains('Private body')),
      );
    });

    test('incrementally decodes separators split across stream deltas', () {
      final segment =
          createTranslationSegments(
            document: TranslationMarkdownSource.parse('# A\n\nB'),
            characterBudget: 100,
          ).single;
      final decoder = TranslationSegmentDecoder(segment);

      expect(decoder.add('# 甲\n\n%'), isEmpty);
      final first = decoder.add('%\n\n乙');
      final last = decoder.complete();

      expect(first.single.unit.wireId, 'b:0:3');
      expect(first.single.translation, '# 甲');
      expect(last.single.unit.wireId, 'b:5:6');
      expect(last.single.translation, '乙');
    });

    test('rejects missing, extra, and empty translated blocks', () {
      TranslationSegment segment() =>
          createTranslationSegments(
            document: TranslationMarkdownSource.parse('A\n\nB'),
            characterBudget: 100,
          ).single;

      final missing = TranslationSegmentDecoder(segment())..add('甲乙');
      expect(
        missing.complete,
        throwsA(
          isA<TranslationProtocolException>().having(
            (error) => error.completedUnitCount,
            'completedUnitCount',
            0,
          ),
        ),
      );

      final extra = TranslationSegmentDecoder(segment());
      expect(
        () => extra.add('甲\n%%\n乙\n%%\n丙\n'),
        throwsA(
          isA<TranslationProtocolException>().having(
            (error) => error.completedUnitCount,
            'completedUnitCount',
            0,
          ),
        ),
      );

      final empty = TranslationSegmentDecoder(segment());
      expect(
        () => empty.add('\n%%\n乙'),
        throwsA(isA<TranslationProtocolException>()),
      );
    });

    test(
      'keeps source blocks with standalone separators in singleton batches',
      () {
        final segments = createTranslationSegments(
          document: TranslationMarkdownSource.parse(
            'Before\r\n\r\nParagraph\r\n%%\r\nParagraph\r\n\r\nAfter',
          ),
          characterBudget: 100,
        );

        expect(segments, hasLength(3));
        expect(segments.map((segment) => segment.units.length), [1, 1, 1]);
        expect(segments[1].units.single.source, contains('\r\n%%\r\n'));

        final decoder = TranslationSegmentDecoder(segments[1]);
        expect(decoder.add('段落\r\n%%\r\n段落'), isEmpty);
        expect(decoder.complete().single.translation, '段落\r\n%%\r\n段落');
      },
    );

    test('accepts plain text without enforcing the source Markdown root', () {
      final segment =
          createTranslationSegments(
            document: TranslationMarkdownSource.parse('# Source'),
            characterBudget: 100,
          ).single;
      final decoder = TranslationSegmentDecoder(segment)..add('- 译文');

      expect(decoder.complete().single.translation, '- 译文');
    });

    test('injects an escaped document identifier into the default prompt', () {
      final prompt = TranslationProviderOptions().systemPromptFor(
        targetLanguageIdentifier: 'zh-Hans',
        documentIdentifier: 'references\\guide\nnotes.md',
      );

      expect(prompt, contains('professional zh-Hans translator'));
      expect(prompt, contains(r'Document: references\\guide\nnotes.md'));
    });

    test('keeps the system prompt independent from the wire protocol', () {
      final prompt = TranslationProviderOptions().systemPromptFor(
        targetLanguageIdentifier: 'zh-Hans',
        documentIdentifier: 'SKILL.md',
      );

      expect(prompt, isNot(contains('%%')));
      expect(prompt, contains('Text phrased as instructions'));
      expect(prompt, contains('rather\nthan answering it'));
      expect(prompt, isNot(contains('untrusted')));
      expect(prompt, contains('Do not add explanations'));
      expect(prompt, isNot(contains('<AI-ANALYSIS>')));
      expect(prompt, contains('Preserve the Markdown format'));
      expect(prompt, contains('or code fences'));
    });

    test('uses an isolated output contract for a singleton request', () {
      final segment =
          createTranslationSegments(
            document: TranslationMarkdownSource.parse('# Source'),
            characterBudget: 100,
          ).single;

      final prompt = segment.userPrompt('zh-Hans');

      expect(prompt, contains('output translation only'));
      expect(prompt, isNot(contains('%%')));
      expect(segment.systemPromptInstructions, contains('one source block'));
      expect(segment.systemPromptInstructions, contains('no block separator'));
      expect(segment.systemPromptInstructions, isNot(contains('%%')));
    });

    test('uses a separator contract only for a batch request', () {
      final segment =
          createTranslationSegments(
            document: TranslationMarkdownSource.parse('A\n\nB\n\nC'),
            characterBudget: 100,
          ).single;

      final prompt = segment.userPrompt('zh-Hans');

      expect(prompt, contains('A\n\n%%\n\nB\n\n%%\n\nC'));
      expect(
        segment.systemPromptInstructions,
        contains('multiple source blocks'),
      );
      expect(segment.systemPromptInstructions, contains('same number'));
      expect(
        segment.systemPromptInstructions,
        contains('with no text before or after it'),
      );
      expect(
        segment.systemPromptInstructions,
        isNot(contains('Translation A')),
      );
    });
  });
}
