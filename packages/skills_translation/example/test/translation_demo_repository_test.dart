import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation_example/application/translation_demo_config.dart';
import 'package:skills_translation_example/infrastructure/translation_demo_repository.dart';

void main() {
  test(
    'OpenAI-compatible requests omit optional generation parameters by default',
    () async {
      final requestBody = Completer<Map<String, Object?>>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final json = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, Object?>;
        requestBody.complete(json);
        request.response.headers.contentType = ContentType.json;
        if (json.containsKey('max_output_tokens') ||
            json.containsKey('temperature')) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write(
            jsonEncode({'detail': 'Unsupported optional parameter'}),
          );
        } else {
          request.response.write(
            jsonEncode(
              _responsesBody(
                model: 'test-model',
                text: _translationContract(json, '# 译文'),
              ),
            ),
          );
        }
        await request.response.close();
      });

      final config = TranslationDemoConfig.initial().copyWith(
        apiBaseUri: 'http://${server.address.host}:${server.port}/v1',
        modelIdentifier: 'test-model',
      );
      final job = const LlmTranslationDemoRepository().start(
        config: config,
        sourceDocument: SourceDocument(
          slotKey: 'example',
          contentHash: 'hash',
          documentIdentifier: 'SKILL.md',
          content: '# Translate me',
        ),
      );

      final outcome = await job.result.timeout(const Duration(seconds: 5));
      final json = await requestBody.future;

      expect(json, isNot(contains('max_output_tokens')));
      expect(json, isNot(contains('temperature')));
      expect(
        json['reasoning'],
        const <String, Object?>{'effort': 'none'},
      );
      expect(outcome, isA<CompletedTranslation>());
      expect(
        (outcome as CompletedTranslation).translatedContent,
        '# 译文',
      );
    },
  );

  test('forwards Max Output Tokens when the optional field is set', () async {
    final requestBody = Completer<Map<String, Object?>>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final json = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, Object?>;
      requestBody.complete(json);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          _responsesBody(
            model: 'test-model',
            text: _translationContract(json, '# 译文'),
          ),
        ),
      );
      await request.response.close();
    });

    final config = TranslationDemoConfig.initial().copyWith(
      apiBaseUri: 'http://${server.address.host}:${server.port}/v1',
      modelIdentifier: 'test-model',
      maxOutputTokensText: '16384',
    );
    final job = const LlmTranslationDemoRepository().start(
      config: config,
      sourceDocument: SourceDocument(
        slotKey: 'example',
        contentHash: 'hash',
        documentIdentifier: 'SKILL.md',
        content: '# Translate me',
      ),
    );

    final outcome = await job.result.timeout(const Duration(seconds: 5));
    final json = await requestBody.future;

    expect(json['max_output_tokens'], 16384);
    expect(json, isNot(contains('temperature')));
    expect(outcome, isA<CompletedTranslation>());
  });

  test('uses Segment Character Budget to split Provider requests', () async {
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final json = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, Object?>;
      requestCount += 1;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          _responsesBody(
            model: 'test-model',
            text: _translationContract(json, '译文'),
          ),
        ),
      );
      await request.response.close();
    });

    final config = TranslationDemoConfig.initial().copyWith(
      apiBaseUri: 'http://${server.address.host}:${server.port}/v1',
      modelIdentifier: 'test-model',
      segmentCharacterBudgetText: '1',
      maxConcurrentSegments: 1,
    );
    final job = const LlmTranslationDemoRepository().start(
      config: config,
      sourceDocument: SourceDocument(
        slotKey: 'example',
        contentHash: 'hash',
        documentIdentifier: 'SKILL.md',
        content: 'A\n\nB',
      ),
    );

    final outcome = await job.result.timeout(const Duration(seconds: 5));

    expect(outcome, isA<CompletedTranslation>());
    expect(requestCount, 2);
  });

  test('omits forced reasoning control when reasoning is enabled', () async {
    final requestBody = Completer<Map<String, Object?>>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final json = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, Object?>;
      requestBody.complete(json);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          _responsesBody(
            model: 'test-model',
            text: _translationContract(json, '# 译文'),
          ),
        ),
      );
      await request.response.close();
    });

    final config = TranslationDemoConfig.initial().copyWith(
      apiBaseUri: 'http://${server.address.host}:${server.port}/v1',
      modelIdentifier: 'test-model',
      reasoningEnabled: true,
    );
    final job = const LlmTranslationDemoRepository().start(
      config: config,
      sourceDocument: SourceDocument(
        slotKey: 'example',
        contentHash: 'hash',
        documentIdentifier: 'SKILL.md',
        content: '# Translate me',
      ),
    );

    final outcome = await job.result.timeout(const Duration(seconds: 5));
    final json = await requestBody.future;

    expect(json, isNot(contains('reasoning')));
    expect(outcome, isA<CompletedTranslation>());
  });
}

String _translationContract(Map<String, Object?> request, String translation) {
  final prompt = _allStrings(request).singleWhere(
    (value) => value.trimLeft().startsWith('Translate to '),
  );
  final normalized = prompt.trimLeft();
  final bodyStart = normalized.indexOf('\n\n');
  if (bodyStart < 0) throw const FormatException('Missing translation input.');
  final sourceCount = normalized
      .substring(bodyStart + 2)
      .trim()
      .split(RegExp(r'\r?\n\r?\n%%\r?\n\r?\n'))
      .length;
  return List<String>.filled(sourceCount, translation).join('\n\n%%\n\n');
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

Map<String, Object?> _responsesBody({
  required String model,
  required String text,
}) =>
    {
      'id': 'response-example-test',
      'object': 'response',
      'created_at': 1,
      'status': 'completed',
      'model': model,
      'output': [
        {
          'id': 'message-example-test',
          'type': 'message',
          'status': 'completed',
          'role': 'assistant',
          'content': [
            {
              'type': 'output_text',
              'text': text,
              'annotations': <Object?>[],
            },
          ],
        },
      ],
      'usage': {
        'input_tokens': 1,
        'output_tokens': 1,
        'total_tokens': 2,
        'output_tokens_details': {'reasoning_tokens': 0},
      },
    };
