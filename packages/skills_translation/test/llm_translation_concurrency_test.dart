import 'dart:async';

import 'package:llm_dart_provider/llm_dart_provider.dart';
import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation/src/llm_translation_provider.dart';
import 'package:test/test.dart';

void main() {
  group('LlmTranslationProvider plain-text block protocol', () {
    test('batches blocks and emits completed delimited translations', () async {
      final model = _ControlledLanguageModel();
      final job = _provider(model, characterBudget: 10).start(
        sourceDocument: _source('A\n\nB'),
        targetLanguage: TargetLanguage('zh-Hans'),
      );
      final drafts = <TranslationDraft>[];
      final subscription = job.drafts.listen(drafts.add);
      addTearDown(subscription.cancel);

      await model.waitForRequestCount(1);
      final request = model.requests.single;
      expect(request.userText, contains('A\n\n%%\n\nB'));
      expect(request.request.options.responseFormat, isNull);

      request.addRawDelta('甲\n%%\n');
      await _eventQueue();
      expect(drafts.single.translatedBlocks, {
        const MarkdownBlockId(0, 1): '甲',
      });
      request.addRawDelta('乙');
      await request.finish();

      final outcome = await job.result;
      expect((outcome as CompletedTranslation).translatedContent, '甲\n\n乙');
      expect(drafts.last.completedBlockCount, 2);
      expect(drafts.last.totalBlockCount, 2);
    });

    test('publishes cumulative out-of-source-order completions', () async {
      final model = _ControlledLanguageModel();
      final job = _provider(
        model,
        characterBudget: 1,
        maxConcurrentSegments: 3,
      ).start(
        sourceDocument: _source('A\n\nB\n\nC\n\nD'),
        targetLanguage: TargetLanguage('zh-Hans'),
      );
      final drafts = <TranslationDraft>[];
      final subscription = job.drafts.listen(drafts.add);
      addTearDown(subscription.cancel);

      await model.waitForRequestCount(3);
      await model.requests[2].complete('丙');
      await model.waitForRequestCount(4);
      expect(drafts.single.translatedBlocks, {
        const MarkdownBlockId(6, 7): '丙',
      });

      await model.requests[3].complete('丁');
      await model.requests[1].complete('乙');
      await model.requests[0].complete('甲');

      final outcome = await job.result;
      expect(
        (outcome as CompletedTranslation).translatedContent,
        '甲\n\n乙\n\n丙\n\n丁',
      );
      expect(model.peakActiveRequests, 3);
    });

    test('retries an invalid batch as ordered singleton requests', () async {
      final model = _ControlledLanguageModel();
      final job = _provider(model, characterBudget: 10).start(
        sourceDocument: _source('A\n\nB'),
        targetLanguage: TargetLanguage('zh-Hans'),
      );

      await model.waitForRequestCount(1);
      await model.requests[0].complete('合并译文');

      await model.waitForRequestCount(2);
      expect(model.requests[1].userText, contains('\n\nA'));
      await model.requests[1].complete('甲');

      await model.waitForRequestCount(3);
      expect(model.requests[2].userText, contains('\n\nB'));
      await model.requests[2].complete('乙');

      final outcome = await job.result;
      expect((outcome as CompletedTranslation).translatedContent, '甲\n\n乙');
      expect(model.peakActiveRequests, 1);
    });

    test(
      'keeps a completed prefix when max tokens triggers fallback',
      () async {
        final model = _ControlledLanguageModel();
        final job = _provider(model, characterBudget: 10).start(
          sourceDocument: _source('A\n\nB'),
          targetLanguage: TargetLanguage('zh-Hans'),
        );
        final drafts = <TranslationDraft>[];
        final subscription = job.drafts.listen(drafts.add);
        addTearDown(subscription.cancel);

        await model.waitForRequestCount(1);
        model.requests[0].addRawDelta('甲\n%%\n');
        await _eventQueue();
        expect(drafts.single.completedBlockCount, 1);
        await model.requests[0].finish(reason: FinishReason.maxTokens);

        await model.waitForRequestCount(2);
        expect(model.requests[1].userText, isNot(contains('%%')));
        await model.requests[1].complete('乙');

        final outcome = await job.result;
        expect((outcome as CompletedTranslation).translatedContent, '甲\n\n乙');
        expect(model.requests, hasLength(2));
      },
    );

    test('fails safely when a singleton translation remains invalid', () async {
      final model = _ControlledLanguageModel();
      final job = _provider(model, characterBudget: 10).start(
        sourceDocument: _source('A'),
        targetLanguage: TargetLanguage('zh-Hans'),
      );

      await model.waitForRequestCount(1);
      await model.requests.single.complete('   ');

      final outcome = await job.result;
      expect(outcome, isA<TranslationFailure>());
      expect(
        (outcome as TranslationFailure).code,
        TranslationFailureCode.invalidResponse,
      );
    });

    test('cancels every in-flight request and starts no queued work', () async {
      final model = _ControlledLanguageModel();
      final job = _provider(
        model,
        characterBudget: 1,
        maxConcurrentSegments: 2,
      ).start(
        sourceDocument: _source('A\n\nB\n\nC'),
        targetLanguage: TargetLanguage('zh-Hans'),
      );

      await model.waitForRequestCount(2);
      await job.cancel();

      expect(await job.result, const TranslationJobCancellation());
      expect(model.requests, hasLength(2));
      expect(model.requests.every((request) => request.wasCancelled), isTrue);
    });
  });
}

_ControlledProvider _provider(
  _ControlledLanguageModel model, {
  required int characterBudget,
  int maxConcurrentSegments = 1,
}) => _ControlledProvider(
  model: model,
  options: TranslationProviderOptions(
    segmentCharacterBudget: characterBudget,
    maxConcurrentSegments: maxConcurrentSegments,
  ),
);

SourceDocument _source(String content) => SourceDocument(
  slotKey: 'concurrency-test',
  contentHash: 'content-hash',
  documentIdentifier: 'SKILL.md',
  content: content,
);

Future<void> _eventQueue() => Future<void>.delayed(Duration.zero);

final class _ControlledProvider extends LlmTranslationProvider {
  _ControlledProvider({
    required _ControlledLanguageModel model,
    required super.options,
  }) : super(
         languageModel: model,
         providerIdentifier: 'controlled',
         modelIdentifier: 'controlled-model',
       );
}

final class _ControlledLanguageModel implements LanguageModel {
  final List<_ControlledRequest> requests = [];
  final Map<int, Completer<void>> _requestCountWaiters = {};
  var _activeRequests = 0;
  var peakActiveRequests = 0;

  @override
  String get providerId => 'controlled';

  @override
  String get modelId => 'controlled-model';

  @override
  Future<GenerateTextResult> doGenerate(GenerateTextRequest request) =>
      throw UnsupportedError('Only streaming is used by this test model.');

  @override
  Stream<LanguageModelStreamEvent> doStream(GenerateTextRequest request) {
    late final _ControlledRequest controlled;
    controlled = _ControlledRequest(
      request: request,
      onInactive: () => _activeRequests -= 1,
    );
    requests.add(controlled);
    _activeRequests += 1;
    if (_activeRequests > peakActiveRequests) {
      peakActiveRequests = _activeRequests;
    }
    for (final entry in _requestCountWaiters.entries.toList()) {
      if (requests.length >= entry.key && !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
    return controlled.stream;
  }

  Future<void> waitForRequestCount(int count) {
    if (requests.length >= count) return Future<void>.value();
    return _requestCountWaiters.putIfAbsent(count, Completer<void>.new).future;
  }
}

final class _ControlledRequest {
  _ControlledRequest({
    required this.request,
    required void Function() onInactive,
  }) : _onInactive = onInactive,
       _controller = StreamController<LanguageModelStreamEvent>() {
    _controller.onCancel = _becomeInactive;
    unawaited(
      request.callOptions.cancellation!.whenCancelled.then((reason) async {
        if (_closed) return;
        wasCancelled = true;
        _closed = true;
        _controller.addError(ProviderCancelledException(reason));
        await _controller.close();
      }),
    );
  }

  final GenerateTextRequest request;
  final StreamController<LanguageModelStreamEvent> _controller;
  final void Function() _onInactive;
  var _closed = false;
  var _inactiveNotified = false;
  var wasCancelled = false;

  Stream<LanguageModelStreamEvent> get stream => _controller.stream;

  String get userText {
    final message = request.prompt.last as UserPromptMessage;
    return (message.parts.single as TextPromptPart).text;
  }

  void addRawDelta(String value) {
    if (_closed) return;
    _controller.add(const TextStartEvent(id: 'text'));
    _controller.add(TextDeltaEvent(id: 'text', delta: value));
  }

  Future<void> complete(String translation) async {
    addRawDelta(translation);
    await finish();
  }

  Future<void> finish({FinishReason reason = FinishReason.stop}) async {
    if (_closed) return;
    _controller.add(const TextEndEvent(id: 'text'));
    _controller.add(FinishEvent(finishReason: reason));
    _closed = true;
    await _controller.close();
  }

  void _becomeInactive() {
    if (_inactiveNotified) return;
    _inactiveNotified = true;
    _onInactive();
  }
}
