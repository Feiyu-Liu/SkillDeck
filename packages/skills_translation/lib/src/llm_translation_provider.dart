import 'dart:async';
import 'dart:convert';

import 'package:flutter_md/flutter_md.dart';
import 'package:llm_dart_provider/llm_dart_provider.dart';

import 'markdown_source_adapter.dart';
import 'models.dart';
import 'translation_protocol.dart';
import 'translation_provider.dart';
import 'translation_provider_options.dart';

/// Package-internal base that owns the shared llm_dart Job runtime.
abstract base class LlmTranslationProvider implements TranslationProvider {
  /// Creates the shared runtime around a package-private SDK model.
  LlmTranslationProvider({
    required LanguageModel languageModel,
    required String providerIdentifier,
    required String modelIdentifier,
    required TranslationProviderOptions options,
  }) : _languageModel = languageModel,
       _providerIdentifier = providerIdentifier,
       _modelIdentifier = modelIdentifier,
       _options = options;

  final LanguageModel _languageModel;
  final String _providerIdentifier;
  final String _modelIdentifier;
  final TranslationProviderOptions _options;

  @override
  TranslationJob start({
    required SourceDocument sourceDocument,
    required TargetLanguage targetLanguage,
    TranslationScope scope = TranslationScope.fullDocument,
  }) => _LlmTranslationJob(
    languageModel: _languageModel,
    providerIdentifier: _providerIdentifier,
    modelIdentifier: _modelIdentifier,
    options: _options,
    sourceDocument: sourceDocument,
    targetLanguage: targetLanguage,
    scope: scope,
  );
}

final class _LlmTranslationJob implements TranslationJob {
  _LlmTranslationJob({
    required this.languageModel,
    required this.providerIdentifier,
    required this.modelIdentifier,
    required this.options,
    required this.sourceDocument,
    required this.targetLanguage,
    required this.scope,
  }) {
    scheduleMicrotask(_run);
  }

  final LanguageModel languageModel;
  final String providerIdentifier;
  final String modelIdentifier;
  final TranslationProviderOptions options;
  final SourceDocument sourceDocument;
  final TargetLanguage targetLanguage;
  final TranslationScope scope;
  final ProviderCancellation _providerCancellation = ProviderCancellation();
  final StreamController<TranslationDraft> _draftController =
      StreamController<TranslationDraft>.broadcast(sync: true);
  final Completer<TranslationJobOutcome> _result =
      Completer<TranslationJobOutcome>();
  final Map<MarkdownBlockId, String> _translatedBlocks = {};
  Future<void>? _cancellation;
  bool _cancelRequested = false;
  bool _terminal = false;
  _JobTermination? _termination;
  String? _translatedDescription;
  TranslationDraft? _lastEmittedDraft;
  var _totalUnitCount = 0;

  @override
  Stream<TranslationDraft> get drafts => _draftController.stream;

  @override
  Future<TranslationJobOutcome> get result => _result.future;

  @override
  Future<void> cancel() {
    if (_terminal) return Future<void>.value();
    return _cancellation ??= _cancelAndWait();
  }

  Future<void> _cancelAndWait() async {
    _cancelRequested = true;
    _recordCancellation();
    _providerCancellation.cancel('translation-job-cancelled');
    await result;
  }

  Future<void> _run() async {
    try {
      final document = TranslationMarkdownSource.parse(
        sourceDocument.content,
        documentIdentifier: sourceDocument.documentIdentifier,
      );
      if (scope == TranslationScope.descriptionOnly &&
          (sourceDocument.documentIdentifier != 'SKILL.md' ||
              document.descriptionSource == null)) {
        throw const _SafeTranslationException(
          TranslationFailureCode.invalidConfiguration,
          'The selected document has no translatable Skill description.',
        );
      }
      final segments = createTranslationSegments(
        document: document,
        characterBudget: options.segmentCharacterBudget,
        descriptionOnly: scope == TranslationScope.descriptionOnly,
      );
      _totalUnitCount = segments.fold(
        0,
        (count, segment) => count + segment.units.length,
      );
      var nextSegmentIndex = 0;

      TranslationSegment? claimNextSegment() {
        if (_termination != null || nextSegmentIndex >= segments.length) {
          return null;
        }
        return segments[nextSegmentIndex++];
      }

      Future<void> runWorker() async {
        while (true) {
          final segment = claimNextSegment();
          if (segment == null) return;
          try {
            await _translateSegment(
              segment,
              onBlock: (block) {
                if (_termination != null) return;
                final markdownBlockId = block.unit.markdownBlockId;
                if (markdownBlockId == null) {
                  _translatedDescription = block.translation;
                } else {
                  _translatedBlocks[markdownBlockId] = block.translation;
                }
                _emitDraft();
              },
            );
          } on _JobCancelled {
            _recordCancellation();
            return;
          } on _SafeTranslationException catch (error) {
            _recordFailure(error);
            return;
          } catch (_) {
            _recordFailure(
              const _SafeTranslationException(
                TranslationFailureCode.unknown,
                'The translation could not be completed.',
              ),
            );
            return;
          }
        }
      }

      final workerCount =
          segments.length < options.maxConcurrentSegments
              ? segments.length
              : options.maxConcurrentSegments;
      await Future.wait([
        for (var index = 0; index < workerCount; index += 1) runWorker(),
      ]);

      final termination = _termination;
      if (termination != null) {
        await _finish(termination.outcome);
        return;
      }
      if (_completedUnitCount != _totalUnitCount) {
        throw const _SafeTranslationException(
          TranslationFailureCode.invalidResponse,
          'The translation provider returned an invalid response.',
        );
      }
      await _finish(
        CompletedTranslation(
          slotKey: sourceDocument.slotKey,
          contentHash: sourceDocument.contentHash,
          documentIdentifier: sourceDocument.documentIdentifier,
          targetLanguage: targetLanguage,
          scope: scope,
          translatedContent:
              scope == TranslationScope.descriptionOnly
                  ? _translatedDescription!
                  : document.applyReplacements(
                    translatedBlocks: _translatedBlocks,
                    translatedDescription: _translatedDescription,
                  ),
          provenance: TranslationProvenance(
            providerIdentifier: providerIdentifier,
            modelIdentifier: modelIdentifier,
          ),
        ),
      );
    } on _JobCancelled {
      _recordCancellation();
      await _finish(_termination!.outcome);
    } on _SafeTranslationException catch (error) {
      _recordFailure(error);
      await _finish(_termination!.outcome);
    } catch (_) {
      _recordFailure(
        const _SafeTranslationException(
          TranslationFailureCode.unknown,
          'The translation could not be completed.',
        ),
      );
      await _finish(_termination!.outcome);
    }
  }

  int get _completedUnitCount =>
      _translatedBlocks.length + (_translatedDescription == null ? 0 : 1);

  Future<void> _translateSegment(
    TranslationSegment segment, {
    required void Function(DecodedTranslationBlock block) onBlock,
  }) async {
    try {
      await _requestSegment(segment, onBlock: onBlock);
      return;
    } on _RetryableSegmentException catch (error) {
      if (segment.units.length == 1) {
        throw _SafeTranslationException(
          TranslationFailureCode.invalidResponse,
          error.reason,
        );
      }

      for (
        var index = error.completedUnitCount;
        index < segment.units.length;
        index += 1
      ) {
        final fallback = TranslationSegment(
          id: '${segment.id}-fallback-${index + 1}',
          units: List<TranslationUnit>.unmodifiable([segment.units[index]]),
        );
        try {
          await _requestSegment(fallback, onBlock: onBlock);
        } on _RetryableSegmentException catch (fallbackError) {
          throw _SafeTranslationException(
            TranslationFailureCode.invalidResponse,
            fallbackError.reason,
          );
        }
      }
    }
  }

  Future<void> _requestSegment(
    TranslationSegment segment, {
    required void Function(DecodedTranslationBlock block) onBlock,
  }) async {
    final decoder = TranslationSegmentDecoder(segment);
    var finished = false;
    final request = GenerateTextRequest(
      prompt: [
        SystemPromptMessage.text(
          '${options.systemPromptFor(targetLanguageIdentifier: targetLanguage.identifier, documentIdentifier: sourceDocument.documentIdentifier)}\n\n${segment.systemPromptInstructions}',
        ),
        UserPromptMessage.text(segment.userPrompt(targetLanguage.identifier)),
      ],
      options: GenerateTextOptions(
        maxOutputTokens: options.maxOutputTokens,
        temperature: options.temperature,
        reasoning:
            options.reasoningEnabled
                ? const GenerateTextReasoningOptions.enabled()
                : const GenerateTextReasoningOptions.disabled(),
      ),
      callOptions: CallOptions(
        timeout: options.inactivityTimeout,
        maxRetries: 0,
        cancellation: _providerCancellation,
      ),
    );

    try {
      await for (final event in languageModel.doStream(request)) {
        _throwIfCancelled();
        switch (event) {
          case TextDeltaEvent(:final delta):
            for (final block in decoder.add(delta)) {
              onBlock(block);
            }
          case FinishEvent(:final finishReason):
            finished = true;
            _validateFinishReason(
              finishReason,
              completedUnitCount: decoder.decodedUnitCount,
            );
          case ErrorEvent(:final error):
            throw _failureFromModelError(error);
          default:
            break;
        }
      }
      _throwIfCancelled();
      if (!finished) {
        throw TranslationProtocolException(
          completedUnitCount: decoder.decodedUnitCount,
        );
      }
      for (final block in decoder.complete()) {
        onBlock(block);
      }
    } on ProviderCancelledException {
      throw const _JobCancelled();
    } on TranslationProtocolException catch (error) {
      throw _RetryableSegmentException(
        'The translation provider returned an invalid response.',
        completedUnitCount: error.completedUnitCount,
      );
    } on FormatException {
      throw const _SafeTranslationException(
        TranslationFailureCode.invalidResponse,
        'The translation provider returned an invalid response.',
      );
    } on TypeError {
      throw const _SafeTranslationException(
        TranslationFailureCode.invalidResponse,
        'The translation provider returned an invalid response.',
      );
    } on _SafeTranslationException {
      rethrow;
    } on _RetryableSegmentException {
      rethrow;
    } catch (_) {
      if (_cancelRequested) throw const _JobCancelled();
      throw const _SafeTranslationException(
        TranslationFailureCode.unknown,
        'The translation provider returned an unexpected failure.',
      );
    }
  }

  void _validateFinishReason(
    FinishReason reason, {
    required int completedUnitCount,
  }) {
    switch (reason) {
      case FinishReason.stop || FinishReason.other:
        return;
      case FinishReason.maxTokens:
        throw _RetryableSegmentException(
          'The translation response exceeded the configured output limit.',
          completedUnitCount: completedUnitCount,
        );
      case FinishReason.contentFilter:
        throw const _SafeTranslationException(
          TranslationFailureCode.requestRejected,
          'The translation request was rejected by the provider.',
        );
      case FinishReason.aborted:
        if (_cancelRequested) throw const _JobCancelled();
        throw const _SafeTranslationException(
          TranslationFailureCode.providerUnavailable,
          'The translation provider aborted the request.',
        );
      case FinishReason.toolCalls || FinishReason.error:
        throw const _SafeTranslationException(
          TranslationFailureCode.invalidResponse,
          'The translation provider returned an invalid response.',
        );
    }
  }

  void _emitDraft() {
    if (_terminal || _termination != null || _completedUnitCount == 0) return;
    final draft = TranslationDraft(
      translatedBlocks: _translatedBlocks,
      translatedDescription: _translatedDescription,
      completedBlockCount: _completedUnitCount,
      totalBlockCount: _totalUnitCount,
    );
    if (draft == _lastEmittedDraft) return;
    _lastEmittedDraft = draft;
    _draftController.add(draft);
  }

  void _recordFailure(_SafeTranslationException error) {
    _termination ??= _JobFailure(
      TranslationFailure(
        code: error.code,
        reason: error.reason,
        providerErrorCode: error.providerErrorCode,
        providerErrorMessage: error.providerErrorMessage,
      ),
    );
  }

  void _recordCancellation() {
    _termination ??= const _JobCancellation();
  }

  void _throwIfCancelled() {
    if (_cancelRequested || _providerCancellation.isCancelled) {
      throw const _JobCancelled();
    }
  }

  Future<void> _finish(TranslationJobOutcome outcome) async {
    if (_terminal) return;
    _terminal = true;
    await _draftController.close();
    _result.complete(outcome);
  }
}

sealed class _JobTermination {
  const _JobTermination();

  TranslationJobOutcome get outcome;
}

final class _JobFailure extends _JobTermination {
  const _JobFailure(this.failure);

  final TranslationFailure failure;

  @override
  TranslationJobOutcome get outcome => failure;
}

final class _JobCancellation extends _JobTermination {
  const _JobCancellation();

  @override
  TranslationJobOutcome get outcome => const TranslationJobCancellation();
}

_SafeTranslationException _failureFromModelError(ModelError error) {
  final providerFields = _providerErrorFields(error);
  final statusCode = error.statusCode;
  if (statusCode == 401) {
    return _SafeTranslationException(
      TranslationFailureCode.authenticationFailed,
      'The translation provider rejected the configured credentials.',
      providerErrorCode: providerFields.$1,
      providerErrorMessage: providerFields.$2,
    );
  }
  if (statusCode == 403) {
    return _SafeTranslationException(
      TranslationFailureCode.accessDenied,
      'The translation provider denied access to this request.',
      providerErrorCode: providerFields.$1,
      providerErrorMessage: providerFields.$2,
    );
  }
  if (statusCode == 429) {
    return _SafeTranslationException(
      TranslationFailureCode.rateLimited,
      'The translation provider is rate limiting requests.',
      providerErrorCode: providerFields.$1,
      providerErrorMessage: providerFields.$2,
    );
  }
  if (statusCode != null && statusCode >= 400 && statusCode < 500) {
    return _SafeTranslationException(
      TranslationFailureCode.requestRejected,
      'The translation provider rejected the request.',
      providerErrorCode: providerFields.$1,
      providerErrorMessage: providerFields.$2,
    );
  }
  if (statusCode != null && statusCode >= 500) {
    return _SafeTranslationException(
      TranslationFailureCode.providerUnavailable,
      'The translation provider is unavailable.',
      providerErrorCode: providerFields.$1,
      providerErrorMessage: providerFields.$2,
    );
  }
  final mapped = switch (error.code) {
    'transport-timeout' => const _SafeTranslationException(
      TranslationFailureCode.timedOut,
      'The translation request timed out.',
    ),
    'transport-network' => const _SafeTranslationException(
      TranslationFailureCode.networkUnavailable,
      'The translation provider could not be reached.',
    ),
    'transport-cancelled' => const _JobCancelled(),
    'transport-response-format' => const _SafeTranslationException(
      TranslationFailureCode.invalidResponse,
      'The translation provider returned an invalid response.',
    ),
    _ => const _SafeTranslationException(
      TranslationFailureCode.unknown,
      'The translation provider returned an unexpected failure.',
    ),
  };
  return mapped is _JobCancelled
      ? mapped
      : _SafeTranslationException(
        mapped.code,
        mapped.reason,
        providerErrorCode: providerFields.$1,
        providerErrorMessage: providerFields.$2,
      );
}

(String?, String?) _providerErrorFields(ModelError error) {
  final details = error.details;
  final body = details is Map ? details['responseBody'] : null;
  Object? decoded = body;
  if (body is String) {
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return (null, null);
    }
  }
  if (decoded is! Map || decoded['error'] is! Map) {
    if (error.kind != ModelErrorKind.provider || details is! Map) {
      return (null, null);
    }
    return _errorFields(details);
  }
  return _errorFields(decoded['error'] as Map<Object?, Object?>);
}

(String?, String?) _errorFields(Map<Object?, Object?> fields) {
  final rawCode = fields['code'] ?? fields['type'];
  final rawMessage = fields['message'];
  return (
    switch (rawCode) {
      String() when rawCode.isNotEmpty => rawCode,
      num() => rawCode.toString(),
      _ => null,
    },
    rawMessage is String && rawMessage.isNotEmpty ? rawMessage : null,
  );
}

class _SafeTranslationException implements Exception {
  const _SafeTranslationException(
    this.code,
    this.reason, {
    this.providerErrorCode,
    this.providerErrorMessage,
  });

  final TranslationFailureCode code;
  final String reason;
  final String? providerErrorCode;
  final String? providerErrorMessage;
}

final class _RetryableSegmentException implements Exception {
  const _RetryableSegmentException(
    this.reason, {
    required this.completedUnitCount,
  });

  final String reason;
  final int completedUnitCount;
}

final class _JobCancelled extends _SafeTranslationException {
  const _JobCancelled()
    : super(
        TranslationFailureCode.unknown,
        'The translation job was cancelled.',
      );
}
