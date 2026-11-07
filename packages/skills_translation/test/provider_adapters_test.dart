import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:skills_translation/skills_translation.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('OpenAI-compatible plain-text output', () {
    test('sends plain Markdown blocks without a response schema', () async {
      final requests = <_RecordedRequest>[];
      final server = await _ProviderServer.start((request) async {
        final recorded = await _record(request);
        requests.add(recorded);
        await _sendOpenAiStream(
          request.response,
          _translatedPlainText(
            recorded,
            (source) => switch (source) {
              '# Title' => '# 标题',
              'Translate me.' => '翻译我。',
              _ => throw StateError('Unexpected source: $source'),
            },
          ),
        );
      });
      addTearDown(server.close);
      final provider = OpenAICompatibleTranslationProvider(
        apiBaseUri: server.apiBaseUri,
        modelIdentifier: 'test-model',
      );

      final outcome = await provider
          .start(
            sourceDocument: _source('# Title\n\nTranslate me.'),
            targetLanguage: TargetLanguage('zh-Hans'),
          )
          .result
          .timeout(const Duration(seconds: 5));

      expect(server.errors, isEmpty);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.json, isNot(contains('response_format')));
      expect(_translationSources(request), ['# Title', 'Translate me.']);
      expect(_systemPrompt(request), contains('Document: SKILL.md'));
      expect(_userPrompt(request), isNot(contains('blockId')));
      expect(_systemPrompt(request), contains('multiple source blocks'));
      expect(_systemPrompt(request), contains('standalone `%%` lines'));
      expect(
        (outcome as CompletedTranslation).translatedContent,
        '# 标题\n\n翻译我。',
      );
    });

    test('does not retry a rejected transport request', () async {
      var requestCount = 0;
      Map<String, Object?>? body;
      final server = await _ProviderServer.start((request) async {
        requestCount += 1;
        body = (await _record(request)).json;
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('private gateway failure');
        await request.response.close();
      });
      addTearDown(server.close);
      final provider = OpenAICompatibleTranslationProvider(
        apiBaseUri: server.apiBaseUri,
        modelIdentifier: 'legacy-model',
      );

      final outcome =
          await provider
              .start(
                sourceDocument: _source('Source'),
                targetLanguage: TargetLanguage('zh-Hans'),
              )
              .result;

      expect(requestCount, 1);
      expect(body, isNot(contains('response_format')));
      expect(outcome, isA<TranslationFailure>());
      expect(
        (outcome as TranslationFailure).code,
        TranslationFailureCode.requestRejected,
      );
    });

    test('carries only the original OpenAI error fields', () async {
      final server = await _ProviderServer.start((request) async {
        await _record(request);
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'error': {
                'code': 'invalid_api_key',
                'message': 'Key rejected: echoed-secret',
                'metadata': 'private-response-extra',
              },
              'debug': 'private-body-extra',
            }),
          );
        await request.response.close();
      });
      addTearDown(server.close);
      final provider = OpenAICompatibleTranslationProvider(
        apiBaseUri: server.apiBaseUri,
        modelIdentifier: 'test-model',
      );

      final outcome =
          await provider
              .start(
                sourceDocument: _source('# Source'),
                targetLanguage: TargetLanguage('zh-Hans'),
              )
              .result;

      final failure = outcome as TranslationFailure;
      expect(failure.code, TranslationFailureCode.authenticationFailed);
      expect(failure.providerErrorCode, 'invalid_api_key');
      expect(failure.providerErrorMessage, 'Key rejected: echoed-secret');
      expect(failure.reason, isNot(contains('echoed-secret')));
      expect('$failure', isNot(contains('private-response-extra')));
      expect('$failure', isNot(contains('private-body-extra')));
    });

    test('carries a Provider error event from the response stream', () async {
      final server = await _ProviderServer.start((request) async {
        await _record(request);
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: ${jsonEncode({
            'error': {'type': 'server_error', 'message': 'upstream echoed source'},
          })}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);
      final provider = OpenAICompatibleTranslationProvider(
        apiBaseUri: server.apiBaseUri,
        modelIdentifier: 'test-model',
      );

      final outcome =
          await provider
              .start(
                sourceDocument: _source('# Source'),
                targetLanguage: TargetLanguage('zh-Hans'),
              )
              .result;

      final failure = outcome as TranslationFailure;
      expect(failure.providerErrorCode, 'server_error');
      expect(failure.providerErrorMessage, 'upstream echoed source');
    });

    test('keeps malformed and unstructured response bodies private', () async {
      for (final body in ['not-json', '{"error":"raw-private"}']) {
        final server = await _ProviderServer.start((request) async {
          await _record(request);
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write(body);
          await request.response.close();
        });
        try {
          final provider = OpenAICompatibleTranslationProvider(
            apiBaseUri: server.apiBaseUri,
            modelIdentifier: 'test-model',
          );
          final outcome =
              await provider
                  .start(
                    sourceDocument: _source('# Source'),
                    targetLanguage: TargetLanguage('zh-Hans'),
                  )
                  .result;
          final failure = outcome as TranslationFailure;
          expect(failure.providerErrorCode, isNull);
          expect(failure.providerErrorMessage, isNull);
        } finally {
          await server.close();
        }
      }
    });

    test('preserves a numeric Provider code without a message', () async {
      final server = await _ProviderServer.start((request) async {
        await _record(request);
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'error': {'code': 1205},
            }),
          );
        await request.response.close();
      });
      addTearDown(server.close);
      final provider = OpenAICompatibleTranslationProvider(
        apiBaseUri: server.apiBaseUri,
        modelIdentifier: 'test-model',
      );

      final failure =
          (await provider
                  .start(
                    sourceDocument: _source('# Source'),
                    targetLanguage: TargetLanguage('zh-Hans'),
                  )
                  .result)
              as TranslationFailure;
      expect(failure.providerErrorCode, '1205');
      expect(failure.providerErrorMessage, isNull);
    });

    test(
      'keeps code and frontmatter metadata local, translating description',
      () async {
        final uploadedSources = <String>[];
        final server = await _ProviderServer.start((request) async {
          final recorded = await _record(request);
          uploadedSources.addAll(_translationSources(recorded));
          await _sendOpenAiStream(
            request.response,
            _translatedPlainText(recorded, (source) {
              if (source == 'Private description.') return '中文 "引号" \\ 路径';
              if (source == '# Body') return '# 正文';
              throw StateError('Unexpected source: $source');
            }),
          );
        });
        addTearDown(server.close);
        const code = '```dart\nconst secretCode = true;\n```';
        const source =
            '---\n'
            'name: review-skill\n'
            "description: 'Private description.'\n"
            'metadata: {internal: false}\n'
            '---\n\n'
            '# Body\n\n'
            '$code';
        final provider = OpenAICompatibleTranslationProvider(
          apiBaseUri: server.apiBaseUri,
          modelIdentifier: 'test-model',
        );

        final outcome =
            await provider
                .start(
                  sourceDocument: _source(source),
                  targetLanguage: TargetLanguage('zh-Hans'),
                )
                .result;

        expect(uploadedSources, ['Private description.', '# Body']);
        expect(uploadedSources.join(), isNot(contains('secretCode')));
        expect(uploadedSources.join(), isNot(contains('review-skill')));
        final translated = (outcome as CompletedTranslation).translatedContent;
        final yaml =
            loadYaml(translated.substring(4, translated.indexOf('\n---\n')))
                as YamlMap;
        expect(yaml['name'], 'review-skill');
        expect(yaml['description'], '中文 "引号" \\ 路径');
        expect(translated, endsWith('# 正文\n\n$code'));
      },
    );

    test('description-only uploads and returns only the description', () async {
      final uploadedSources = <String>[];
      final server = await _ProviderServer.start((request) async {
        final recorded = await _record(request);
        uploadedSources.addAll(_translationSources(recorded));
        await _sendOpenAiStream(request.response, '中文说明');
      });
      addTearDown(server.close);
      final provider = OpenAICompatibleTranslationProvider(
        apiBaseUri: server.apiBaseUri,
        modelIdentifier: 'test-model',
      );

      final result =
          await provider
              .start(
                sourceDocument: _source(
                  '---\ndescription: Purpose.\n---\n# Private body',
                ),
                targetLanguage: TargetLanguage('zh-Hans'),
                scope: TranslationScope.descriptionOnly,
              )
              .result;

      expect(uploadedSources, ['Purpose.']);
      expect(
        (result as CompletedTranslation).scope,
        TranslationScope.descriptionOnly,
      );
      expect(result.translatedContent, '中文说明');
    });

    test(
      'description-only rejects missing description without a request',
      () async {
        var requestCount = 0;
        final server = await _ProviderServer.start((request) async {
          requestCount += 1;
          await request.response.close();
        });
        addTearDown(server.close);
        final provider = OpenAICompatibleTranslationProvider(
          apiBaseUri: server.apiBaseUri,
          modelIdentifier: 'test-model',
        );

        final outcome =
            await provider
                .start(
                  sourceDocument: _source('# No description'),
                  targetLanguage: TargetLanguage('zh-Hans'),
                  scope: TranslationScope.descriptionOnly,
                )
                .result;

        expect(requestCount, 0);
        expect(
          (outcome as TranslationFailure).code,
          TranslationFailureCode.invalidConfiguration,
        );
      },
    );

    test('rejects empty output and sanitizes raw provider content', () async {
      final originalLevel = Logger.root.level;
      final logs = <String>[];
      Logger.root.level = Level.ALL;
      final logging = Logger.root.onRecord.listen((record) {
        logs.add(record.message);
      });
      addTearDown(() async {
        await logging.cancel();
        Logger.root.level = originalLevel;
      });
      final server = await _ProviderServer.start((request) async {
        await _record(request);
        await _sendOpenAiStream(request.response, '   ');
      });
      addTearDown(server.close);
      final provider = OpenAICompatibleTranslationProvider(
        apiBaseUri: server.apiBaseUri,
        modelIdentifier: 'test-model',
        apiKey: 'secret-key',
      );

      final outcome =
          await provider
              .start(
                sourceDocument: _source('# source-private'),
                targetLanguage: TargetLanguage('zh-Hans'),
              )
              .result;

      expect(outcome, isA<TranslationFailure>());
      final visible = '${(outcome as TranslationFailure).reason} $outcome';
      expect(visible, isNot(contains('raw-private-provider-output')));
      expect(visible, isNot(contains('source-private')));
      expect(visible, isNot(contains('secret-key')));
      expect(logs.join(), isNot(contains('raw-private-provider-output')));
    });
  });

  test(
    'Anthropic uses the same plain-text prompt without a response schema',
    () async {
      final requests = <_RecordedRequest>[];
      final server = await _ProviderServer.start((request) async {
        final recorded = await _record(request);
        requests.add(recorded);
        await _sendAnthropicStream(
          request.response,
          _translatedPlainText(recorded, (_) => '# 原生译文'),
        );
      });
      addTearDown(server.close);
      final provider = AnthropicMessagesTranslationProvider(
        apiKey: 'anthropic-secret-key',
        apiBaseUri: server.apiBaseUri,
        modelIdentifier: 'claude-test',
      );

      final outcome =
          await provider
              .start(
                sourceDocument: _source('# Source'),
                targetLanguage: TargetLanguage('zh-Hans'),
              )
              .result;

      expect(requests, hasLength(1));
      expect(requests.single.json, isNot(contains('response_format')));
      expect(_translationSources(requests.single), ['# Source']);
      expect(_systemPrompt(requests.single), isNot(contains('%%')));
      expect(_userPrompt(requests.single), isNot(contains('%%')));
      expect(_systemPrompt(requests.single), contains('one source block'));
      expect((outcome as CompletedTranslation).translatedContent, '# 原生译文');
    },
  );

  test('preserves the original Anthropic type and message', () async {
    final server = await _ProviderServer.start((request) async {
      await _record(request);
      request.response
        ..statusCode = HttpStatus.tooManyRequests
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'type': 'error',
            'error': {
              'type': 'rate_limit_error',
              'message': 'Capacity exceeded',
              'request_id': 'do-not-show',
            },
          }),
        );
      await request.response.close();
    });
    addTearDown(server.close);
    final provider = AnthropicMessagesTranslationProvider(
      apiKey: 'test-key',
      apiBaseUri: server.apiBaseUri,
      modelIdentifier: 'claude-test',
    );

    final outcome =
        await provider
            .start(
              sourceDocument: _source('# Source'),
              targetLanguage: TargetLanguage('zh-Hans'),
            )
            .result;

    final failure = outcome as TranslationFailure;
    expect(failure.code, TranslationFailureCode.rateLimited);
    expect(failure.providerErrorCode, 'rate_limit_error');
    expect(failure.providerErrorMessage, 'Capacity exceeded');
    expect('$failure', isNot(contains('do-not-show')));
  });
}

SourceDocument _source(String content) => SourceDocument(
  slotKey: 'translation-test',
  contentHash: 'content-hash',
  documentIdentifier: 'SKILL.md',
  content: content,
);

final class _RecordedRequest {
  const _RecordedRequest({required this.json});

  final Map<String, Object?> json;
}

Future<_RecordedRequest> _record(HttpRequest request) async {
  final decoded = jsonDecode(await utf8.decoder.bind(request).join());
  return _RecordedRequest(json: Map<String, Object?>.from(decoded as Map));
}

String _userPrompt(_RecordedRequest request) => _allStrings(
  request.json,
).singleWhere((value) => value.trimLeft().startsWith('Translate to '));

String _systemPrompt(_RecordedRequest request) => _allStrings(
  request.json,
).singleWhere((value) => value.contains('Rules:\n1. Output only'));

List<String> _translationSources(_RecordedRequest request) {
  final prompt = _userPrompt(request).trimLeft();
  final bodyStart = prompt.indexOf('\n\n');
  if (bodyStart < 0) throw const FormatException('Missing translation input.');
  return prompt
      .substring(bodyStart + 2)
      .trim()
      .split(RegExp(r'\r?\n\r?\n%%\r?\n\r?\n'));
}

Iterable<String> _allStrings(Object? value) sync* {
  if (value is String) {
    yield value;
  } else if (value is List) {
    for (final item in value) {
      yield* _allStrings(item);
    }
  } else if (value is Map) {
    for (final item in value.values) {
      yield* _allStrings(item);
    }
  }
}

String _translatedPlainText(
  _RecordedRequest request,
  String Function(String source) translate,
) => _translationSources(request).map(translate).join('\n\n%%\n\n');

Future<void> _sendOpenAiStream(HttpResponse response, String text) async {
  response.headers.contentType = ContentType(
    'text',
    'event-stream',
    charset: 'utf-8',
  );
  final split = text.length ~/ 2;
  for (final delta in [text.substring(0, split), text.substring(split)]) {
    response.write(
      'data: ${jsonEncode({
        'id': 'chatcmpl-test',
        'object': 'chat.completion.chunk',
        'created': 1,
        'model': 'test-model',
        'choices': [
          {
            'index': 0,
            'delta': {'role': 'assistant', 'content': delta},
            'finish_reason': null,
          },
        ],
      })}\n\n',
    );
  }
  response.write(
    'data: ${jsonEncode({
      'id': 'chatcmpl-test',
      'object': 'chat.completion.chunk',
      'created': 1,
      'model': 'test-model',
      'choices': [
        {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': 'stop'},
      ],
    })}\n\n'
    'data: [DONE]\n\n',
  );
  await response.close();
}

Future<void> _sendAnthropicStream(HttpResponse response, String text) async {
  response.headers.contentType = ContentType(
    'text',
    'event-stream',
    charset: 'utf-8',
  );
  void event(String name, Map<String, Object?> data) {
    response.write('event: $name\ndata: ${jsonEncode(data)}\n\n');
  }

  event('message_start', {
    'type': 'message_start',
    'message': {
      'id': 'msg-test',
      'type': 'message',
      'role': 'assistant',
      'content': <Object?>[],
      'model': 'claude-test',
      'stop_reason': null,
      'stop_sequence': null,
      'usage': {'input_tokens': 10, 'output_tokens': 0},
    },
  });
  event('content_block_start', {
    'type': 'content_block_start',
    'index': 0,
    'content_block': {'type': 'text', 'text': ''},
  });
  event('content_block_delta', {
    'type': 'content_block_delta',
    'index': 0,
    'delta': {'type': 'text_delta', 'text': text},
  });
  event('content_block_stop', {'type': 'content_block_stop', 'index': 0});
  event('message_delta', {
    'type': 'message_delta',
    'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
    'usage': {'output_tokens': 2},
  });
  event('message_stop', {'type': 'message_stop'});
  await response.close();
}

final class _ProviderServer {
  _ProviderServer._(this._server, this._subscription);

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _subscription;
  final List<Object> errors = [];

  Uri get apiBaseUri =>
      Uri.parse('http://${_server.address.address}:${_server.port}/v1');

  static Future<_ProviderServer> start(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late _ProviderServer result;
    final subscription = server.listen((request) {
      unawaited(result._dispatch(request, handler));
    });
    return result = _ProviderServer._(server, subscription);
  }

  Future<void> _dispatch(
    HttpRequest request,
    Future<void> Function(HttpRequest request) handler,
  ) async {
    try {
      await handler(request);
    } catch (error) {
      errors.add(error);
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    await _subscription.cancel();
  }
}
