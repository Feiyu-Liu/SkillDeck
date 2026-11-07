import 'package:skills_translation/skills_translation.dart';
import 'package:test/test.dart';

import 'support/controlled_translation_provider.dart';

void main() {
  group('translation value models', () {
    test('preserves opaque source identity and validates Draft progress', () {
      final source = SourceDocument(
        slotKey: 'Review_Pull-Requests',
        contentHash: 'ABC123',
        documentIdentifier: 'references/review.md',
        content: '# Review pull requests',
      );
      final draft = TranslationDraft(
        translatedBlocks: {const MarkdownBlockId(0, 22): '# 审查拉取请求'},
        translatedDescription: '审查拉取请求',
        completedBlockCount: 2,
        totalBlockCount: 3,
      );

      expect(source.slotKey, 'Review_Pull-Requests');
      expect(source.contentHash, 'ABC123');
      expect(
        () => draft.translatedBlocks[const MarkdownBlockId(2, 3)] = 'x',
        throwsUnsupportedError,
      );
      expect(draft.completedBlockCount, 2);
      expect(
        () => TranslationDraft(
          translatedBlocks: const {},
          translatedDescription: null,
          completedBlockCount: 0,
          totalBlockCount: 1,
        ),
        throwsArgumentError,
      );
    });

    test(
      'implements Draft value equality without exposing content in toString',
      () {
        TranslationDraft draft() => TranslationDraft(
          translatedBlocks: {const MarkdownBlockId(0, 1): '私密译文'},
          translatedDescription: null,
          completedBlockCount: 1,
          totalBlockCount: 2,
        );

        expect(draft(), draft());
        expect(draft().hashCode, draft().hashCode);
        expect(draft().toString(), isNot(contains('私密译文')));
      },
    );

    test('applies non-SKILL Drafts in full-document coordinates', () {
      const content = '''---
description: Guide
---
# Body''';
      final source = SourceDocument(
        slotKey: 'demo',
        contentHash: 'hash',
        documentIdentifier: 'references/guide.md',
        content: content,
      );
      final blockId =
          parseTranslationDisplayDocument(
            documentIdentifier: source.documentIdentifier,
            content: content,
          ).blocks.last.id;
      final draft = TranslationDraft(
        translatedBlocks: {blockId: '# 正文'},
        translatedDescription: '指南',
        completedBlockCount: 2,
        totalBlockCount: 2,
      );

      expect(draft.applyTo(source), '''---
description: "指南"
---
# 正文''');
    });
  });

  group('TranslationProvider contract', () {
    late ControlledTranslationProvider provider;
    late SourceDocument sourceDocument;
    late TargetLanguage targetLanguage;

    setUp(() {
      provider = ControlledTranslationProvider();
      sourceDocument = SourceDocument(
        slotKey: 'review-pull-requests',
        contentHash: 'abc123',
        documentIdentifier: 'SKILL.md',
        content: '# Review pull requests',
      );
      targetLanguage = TargetLanguage('zh-Hans');
    });

    test(
      'streams cumulative replacements before one terminal result',
      () async {
        final job = provider.start(
          sourceDocument: sourceDocument,
          targetLanguage: targetLanguage,
        );
        final drafts = <TranslationDraft>[];
        var streamClosed = false;
        final subscription = job.drafts.listen(
          drafts.add,
          onDone: () => streamClosed = true,
        );
        final first = TranslationDraft(
          translatedBlocks: {const MarkdownBlockId(0, 22): '# 审查拉取请求'},
          translatedDescription: null,
          completedBlockCount: 1,
          totalBlockCount: 1,
        );

        provider.lastJob.emitDraft(first);
        await provider.lastJob.succeed(
          translatedContent: '# 审查拉取请求',
          provenance: TranslationProvenance(
            providerIdentifier: 'test-provider',
          ),
        );

        expect(drafts, [first]);
        expect(streamClosed, isTrue);
        expect(await job.result, isA<CompletedTranslation>());
        await subscription.cancel();
      },
    );

    test(
      'failure and cancellation discard Drafts as durable outcomes',
      () async {
        final failed = provider.start(
          sourceDocument: sourceDocument,
          targetLanguage: targetLanguage,
        );
        provider.lastJob.emitDraft(
          TranslationDraft(
            translatedBlocks: {const MarkdownBlockId(0, 22): '# 临时'},
            translatedDescription: null,
            completedBlockCount: 1,
            totalBlockCount: 1,
          ),
        );
        await provider.lastJob.fail('Provider unavailable');
        expect(await failed.result, isA<TranslationFailure>());

        final cancelled = provider.start(
          sourceDocument: sourceDocument,
          targetLanguage: targetLanguage,
        );
        await Future.wait([cancelled.cancel(), cancelled.cancel()]);
        expect(await cancelled.result, const TranslationJobCancellation());
      },
    );
  });
}
