import 'dart:async';

import 'package:skills_translation/skills_translation.dart';

/// Test-only adapter used to exercise the public Translation contract.
final class ControlledTranslationProvider implements TranslationProvider {
  int _startCount = 0;
  SourceDocument? _lastSourceDocument;
  TargetLanguage? _lastTargetLanguage;
  ControlledTranslationJob? _lastJob;

  int get startCount => _startCount;
  SourceDocument? get lastSourceDocument => _lastSourceDocument;
  TargetLanguage? get lastTargetLanguage => _lastTargetLanguage;
  ControlledTranslationJob get lastJob => _lastJob!;

  @override
  TranslationJob start({
    required SourceDocument sourceDocument,
    required TargetLanguage targetLanguage,
    TranslationScope scope = TranslationScope.fullDocument,
  }) {
    _startCount += 1;
    _lastSourceDocument = sourceDocument;
    _lastTargetLanguage = targetLanguage;
    return _lastJob = ControlledTranslationJob(
      sourceDocument: sourceDocument,
      targetLanguage: targetLanguage,
      scope: scope,
    );
  }
}

/// Deterministically controlled test-only Translation Job.
final class ControlledTranslationJob implements TranslationJob {
  ControlledTranslationJob({
    required this.sourceDocument,
    required this.targetLanguage,
    required this.scope,
  });

  final SourceDocument sourceDocument;
  final TargetLanguage targetLanguage;
  final TranslationScope scope;
  final StreamController<TranslationDraft> _drafts =
      StreamController<TranslationDraft>.broadcast(sync: true);
  final Completer<TranslationJobOutcome> _result =
      Completer<TranslationJobOutcome>();
  Future<void>? _cancellation;
  bool _isTerminal = false;

  @override
  Stream<TranslationDraft> get drafts => _drafts.stream;

  @override
  Future<TranslationJobOutcome> get result => _result.future;

  @override
  Future<void> cancel() {
    if (_isTerminal) {
      return Future<void>.value();
    }
    return _cancellation ??= _finish(const TranslationJobCancellation());
  }

  void emitDraft(TranslationDraft draft) {
    if (_isTerminal) {
      throw StateError('A terminal Translation Job cannot emit a Draft.');
    }
    _drafts.add(draft);
  }

  Future<void> fail(String reason) => _finish(
    TranslationFailure(
      code: TranslationFailureCode.providerUnavailable,
      reason: reason,
    ),
  );

  Future<void> succeed({
    required String translatedContent,
    required TranslationProvenance provenance,
  }) => _finish(
    CompletedTranslation(
      slotKey: sourceDocument.slotKey,
      contentHash: sourceDocument.contentHash,
      documentIdentifier: sourceDocument.documentIdentifier,
      targetLanguage: targetLanguage,
      scope: scope,
      translatedContent: translatedContent,
      provenance: provenance,
    ),
  );

  Future<void> _finish(TranslationJobOutcome outcome) async {
    if (_isTerminal) {
      throw StateError('A terminal Translation Job cannot finish again.');
    }
    _isTerminal = true;
    await _drafts.close();
    _result.complete(outcome);
  }
}
