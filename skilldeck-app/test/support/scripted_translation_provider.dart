import 'dart:async';

import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_translation/skills_translation.dart';

/// A Provider factory whose Jobs finish with [outcome], recording what each
/// Job was asked to translate and with which key.
final class ScriptedTranslationProviderFactory
    implements AppTranslationProviderFactory {
  ScriptedTranslationProviderFactory({this.outcome});

  /// The outcome every Job reports. Null completes with a translation of the
  /// requested document.
  TranslationJobOutcome? outcome;

  /// When set, Jobs stay pending until this completes.
  Completer<void>? gate;

  final apiKeys = <String?>[];
  final profiles = <TranslationProviderProfile>[];
  final documents = <SourceDocument>[];

  @override
  TranslationProvider create({
    required TranslationProviderProfile profile,
    required String? apiKey,
  }) {
    apiKeys.add(apiKey);
    profiles.add(profile);
    return _ScriptedProvider(this);
  }
}

final class _ScriptedProvider implements TranslationProvider {
  _ScriptedProvider(this._factory);

  final ScriptedTranslationProviderFactory _factory;

  @override
  TranslationJob start({
    required SourceDocument sourceDocument,
    required TargetLanguage targetLanguage,
    TranslationScope scope = TranslationScope.fullDocument,
  }) {
    _factory.documents.add(sourceDocument);
    return _ScriptedJob(() async {
      await _factory.gate?.future;
      return _factory.outcome ??
          CompletedTranslation(
            slotKey: sourceDocument.slotKey,
            contentHash: sourceDocument.contentHash,
            documentIdentifier: sourceDocument.documentIdentifier,
            targetLanguage: targetLanguage,
            translatedContent: '你好。',
            provenance: TranslationProvenance(providerIdentifier: 'scripted'),
          );
    });
  }
}

final class _ScriptedJob implements TranslationJob {
  _ScriptedJob(Future<TranslationJobOutcome> Function() run) {
    unawaited(
      run().then((outcome) {
        if (!_result.isCompleted) _result.complete(outcome);
      }),
    );
  }

  final _result = Completer<TranslationJobOutcome>();

  @override
  Stream<TranslationDraft> get drafts => const Stream.empty();

  @override
  Future<TranslationJobOutcome> get result => _result.future;

  @override
  Future<void> cancel() async {
    if (!_result.isCompleted) {
      _result.complete(const TranslationJobCancellation());
    }
  }
}
