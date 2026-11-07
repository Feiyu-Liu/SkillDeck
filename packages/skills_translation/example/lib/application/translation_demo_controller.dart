import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation_example/application/translation_demo_config.dart';
import 'package:skills_translation_example/application/translation_demo_state.dart';
import 'package:skills_translation_example/infrastructure/markdown_document_loader.dart';
import 'package:skills_translation_example/infrastructure/translation_demo_repository.dart';

final class TranslationDemoController extends ChangeNotifier {
  TranslationDemoController({
    required TranslationDemoRepository repository,
    required MarkdownDocumentLoader documentLoader,
  })  : _repository = repository,
        _documentLoader = documentLoader;

  final TranslationDemoRepository _repository;
  final MarkdownDocumentLoader _documentLoader;

  TranslationDemoState _state = TranslationDemoState.initial();
  TranslationJob? _activeJob;
  StreamSubscription<TranslationDraft>? _draftSubscription;
  var _jobSequence = 0;
  var _disposed = false;

  TranslationDemoState get state => _state;

  void setProvider(TranslationDemoProvider provider) {
    if (_state.isBusy || provider == _state.config.provider) return;
    _emit(
      _state.copyWith(
        config: _state.config.switchedTo(provider),
        translatedContent: '',
        phase: TranslationDemoPhase.idle,
        statusMessage: 'Provider changed. Enter its model and API key.',
        provenance: null,
      ),
    );
  }

  void setProtocol(OpenAICompatibleProtocol protocol) {
    if (_state.isBusy || protocol == _state.config.protocol) return;
    _emit(
      _state.copyWith(
        config: _state.config.copyWith(protocol: protocol),
        translatedContent: '',
        phase: TranslationDemoPhase.idle,
        statusMessage: 'Protocol changed. Ready for a new translation.',
        provenance: null,
      ),
    );
  }

  void setApiBaseUri(String value) => _updateConfig(
        _state.config.copyWith(apiBaseUri: value),
      );

  void setModelIdentifier(String value) => _updateConfig(
        _state.config.copyWith(modelIdentifier: value),
      );

  void setApiKey(String value) => _updateConfig(
        _state.config.copyWith(apiKey: value),
      );

  void setTargetLanguage(String value) => _updateConfig(
        _state.config.copyWith(targetLanguage: value),
      );

  void setSegmentCharacterBudget(String value) => _updateConfig(
        _state.config.copyWith(segmentCharacterBudgetText: value),
      );

  void setMaxConcurrentSegments(int value) {
    if (value < 1 || value > 8) return;
    _updateConfig(_state.config.copyWith(maxConcurrentSegments: value));
  }

  void setMaxOutputTokens(String value) => _updateConfig(
        _state.config.copyWith(maxOutputTokensText: value),
      );

  void setReasoningEnabled(bool value) => _updateConfig(
        _state.config.copyWith(reasoningEnabled: value),
      );

  void setSourceContent(String value) {
    if (_state.isBusy || value == _state.sourceContent) return;
    _emit(
      _state.copyWith(
        sourceContent: value,
        translatedContent: '',
        phase: TranslationDemoPhase.idle,
        statusMessage: 'Source changed. Ready for a new translation.',
        provenance: null,
      ),
    );
  }

  Future<void> loadMarkdown() async {
    if (_state.isBusy) return;
    _emit(
      _state.copyWith(
        phase: TranslationDemoPhase.loadingSource,
        statusMessage: 'Choose a Markdown file…',
      ),
    );
    try {
      final document = await _documentLoader.pick();
      if (document == null) {
        _emit(
          _state.copyWith(
            phase: TranslationDemoPhase.idle,
            statusMessage: 'File selection cancelled.',
          ),
        );
        return;
      }
      if (document.content.trim().isEmpty) {
        _emit(
          _state.copyWith(
            phase: TranslationDemoPhase.failed,
            statusMessage: 'The selected Markdown file is empty.',
          ),
        );
        return;
      }
      _emit(
        _state.copyWith(
          sourceContent: document.content,
          sourcePath: document.path,
          translatedContent: '',
          phase: TranslationDemoPhase.idle,
          statusMessage: 'Loaded ${p.basename(document.path)}.',
          provenance: null,
        ),
      );
    } on MarkdownDocumentLoadException catch (error) {
      _emit(
        _state.copyWith(
          phase: TranslationDemoPhase.failed,
          statusMessage: error.message,
        ),
      );
    } on Object {
      _emit(
        _state.copyWith(
          phase: TranslationDemoPhase.failed,
          statusMessage: 'The selected Markdown file could not be read.',
        ),
      );
    }
  }

  Future<void> translate() async {
    if (_state.isBusy) return;
    final validationMessage = _validate();
    if (validationMessage != null) {
      _emit(
        _state.copyWith(
          phase: TranslationDemoPhase.failed,
          statusMessage: validationMessage,
        ),
      );
      return;
    }

    final sequence = ++_jobSequence;
    final sourceDocument = buildDemoSourceDocument(
      content: _state.sourceContent,
      sourcePath: _state.sourcePath,
    );
    TranslationJob job;
    try {
      job = _repository.start(
        config: _state.config,
        sourceDocument: sourceDocument,
      );
    } on Object {
      _emit(
        _state.copyWith(
          phase: TranslationDemoPhase.failed,
          statusMessage: 'The Provider configuration is invalid.',
        ),
      );
      return;
    }

    _activeJob = job;
    _emit(
      _state.copyWith(
        translatedContent: '',
        phase: TranslationDemoPhase.translating,
        statusMessage: 'Translating…',
        provenance: null,
      ),
    );
    _draftSubscription = job.drafts.listen((draft) {
      if (sequence != _jobSequence || _disposed) return;
      _emit(
        _state.copyWith(translatedContent: draft.applyTo(sourceDocument)),
      );
    });

    final outcome = await job.result;
    if (sequence != _jobSequence || _disposed) return;
    // TranslationJob guarantees that its Draft stream closes before result.
    // Do not await a second cancellation at the terminal boundary.
    _draftSubscription = null;
    _activeJob = null;
    switch (outcome) {
      case CompletedTranslation():
        _emit(
          _state.copyWith(
            translatedContent: outcome.translatedContent,
            phase: TranslationDemoPhase.completed,
            statusMessage: 'Translation completed.',
            provenance: outcome.provenance,
          ),
        );
      case TranslationFailure():
        _emit(
          _state.copyWith(
            translatedContent: _state.sourceContent,
            phase: TranslationDemoPhase.failed,
            statusMessage: '${outcome.code.name}: ${outcome.reason}',
            provenance: null,
          ),
        );
      case TranslationJobCancellation():
        _emit(
          _state.copyWith(
            translatedContent: _state.sourceContent,
            phase: TranslationDemoPhase.cancelled,
            statusMessage: 'Translation cancelled.',
            provenance: null,
          ),
        );
    }
  }

  Future<void> cancel() async {
    final job = _activeJob;
    if (job == null || !_state.canCancel) return;
    _emit(
      _state.copyWith(
        phase: TranslationDemoPhase.cancelling,
        statusMessage: 'Cancelling…',
      ),
    );
    await job.cancel();
  }

  void _updateConfig(TranslationDemoConfig config) {
    if (_state.isBusy) return;
    _emit(
      _state.copyWith(
        config: config,
        translatedContent: '',
        phase: TranslationDemoPhase.idle,
        statusMessage: 'Configuration changed. Ready to translate.',
        provenance: null,
      ),
    );
  }

  String? _validate() {
    if (_state.sourceContent.trim().isEmpty) {
      return 'Enter or open a Markdown document.';
    }
    if (_state.config.modelIdentifier.trim().isEmpty) {
      return 'Enter a model identifier.';
    }
    if (_state.config.targetLanguage.trim().isEmpty) {
      return 'Enter a target language identifier.';
    }
    final segmentCharacterBudget = int.tryParse(
      _state.config.segmentCharacterBudgetText.trim(),
    );
    if (segmentCharacterBudget == null || segmentCharacterBudget <= 0) {
      return 'Segment Character Budget must be a positive integer.';
    }
    final maxOutputTokensText = _state.config.maxOutputTokensText.trim();
    if (maxOutputTokensText.isNotEmpty) {
      final maxOutputTokens = int.tryParse(maxOutputTokensText);
      if (maxOutputTokens == null || maxOutputTokens <= 0) {
        return 'Max Output Tokens must be a positive integer or left blank.';
      }
    }
    final uri = Uri.tryParse(_state.config.apiBaseUri.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return 'Enter an HTTP(S) API Base URI without credentials.';
    }
    if (_state.config.provider == TranslationDemoProvider.anthropic &&
        _state.config.apiKey.trim().isEmpty) {
      return 'Anthropic Messages requires an API key.';
    }
    return null;
  }

  void _emit(TranslationDemoState nextState) {
    if (_disposed) return;
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _jobSequence += 1;
    final job = _activeJob;
    final subscription = _draftSubscription;
    _activeJob = null;
    _draftSubscription = null;
    if (job != null) unawaited(job.cancel());
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }
}

@visibleForTesting
SourceDocument buildDemoSourceDocument({
  required String content,
  required String? sourcePath,
}) {
  final hasFilePath = sourcePath != null && sourcePath.trim().isNotEmpty;
  final documentIdentifier = hasFilePath ? p.basename(sourcePath) : 'SKILL.md';
  final parentName = hasFilePath ? p.basename(p.dirname(sourcePath)) : '';
  return SourceDocument(
    slotKey: parentName.trim().isEmpty ? 'example-editor' : parentName,
    contentHash: sha256.convert(utf8.encode(content)).toString(),
    documentIdentifier:
        documentIdentifier.trim().isEmpty ? 'SKILL.md' : documentIdentifier,
    content: content,
  );
}
