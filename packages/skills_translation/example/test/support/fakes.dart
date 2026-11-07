import 'dart:async';

import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation_example/application/translation_demo_config.dart';
import 'package:skills_translation_example/infrastructure/markdown_document_loader.dart';
import 'package:skills_translation_example/infrastructure/translation_demo_repository.dart';

final class FakeTranslationDemoRepository implements TranslationDemoRepository {
  ControlledTranslationJob nextJob = ControlledTranslationJob();
  TranslationDemoConfig? lastConfig;
  SourceDocument? lastSourceDocument;
  var startCount = 0;

  @override
  TranslationJob start({
    required TranslationDemoConfig config,
    required SourceDocument sourceDocument,
  }) {
    startCount += 1;
    lastConfig = config;
    lastSourceDocument = sourceDocument;
    nextJob.sourceDocument = sourceDocument;
    return nextJob;
  }
}

final class ControlledTranslationJob implements TranslationJob {
  SourceDocument? sourceDocument;
  final StreamController<TranslationDraft> _drafts =
      StreamController<TranslationDraft>.broadcast();
  final Completer<TranslationJobOutcome> _result =
      Completer<TranslationJobOutcome>();
  var cancelCount = 0;

  @override
  Stream<TranslationDraft> get drafts => _drafts.stream;

  @override
  Future<TranslationJobOutcome> get result => _result.future;

  void addDraft(String content) {
    final source = sourceDocument!.content;
    final closingFrontmatter =
        source.startsWith('---\n') ? source.indexOf('\n---\n', 4) : -1;
    final bodyOffset = closingFrontmatter < 0 ? 0 : closingFrontmatter + 5;
    final sourceStart = source.indexOf('#', bodyOffset);
    final sourceLineEnd = source.indexOf('\n', sourceStart);
    final start = sourceStart - bodyOffset;
    final end =
        (sourceLineEnd < 0 ? source.length : sourceLineEnd) - bodyOffset;
    _drafts.add(
      TranslationDraft(
        translatedBlocks: {MarkdownBlockId(start, end): content},
        translatedDescription: null,
        completedBlockCount: 1,
        totalBlockCount: 1,
      ),
    );
  }

  Future<void> complete(TranslationJobOutcome outcome) async {
    if (_result.isCompleted) return;
    await _drafts.close();
    _result.complete(outcome);
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    await complete(const TranslationJobCancellation());
  }
}

final class FakeMarkdownDocumentLoader implements MarkdownDocumentLoader {
  LoadedMarkdownDocument? document;
  Object? error;
  var pickCount = 0;

  @override
  Future<LoadedMarkdownDocument?> pick() async {
    pickCount += 1;
    final error = this.error;
    if (error != null) throw error;
    return document;
  }
}
