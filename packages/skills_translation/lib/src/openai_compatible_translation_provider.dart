import 'dart:async';
import 'dart:convert';

import 'package:llm_dart_openai/llm_dart_openai.dart';
import 'package:llm_dart_transport/llm_dart_transport.dart';

import 'llm_translation_provider.dart';
import 'llm_transport.dart';
import 'provider_validation.dart';
import 'translation_provider_options.dart';

/// The OpenAI-compatible HTTP protocol used for text generation.
enum OpenAICompatibleProtocol {
  /// The legacy `/chat/completions` protocol supported by most gateways.
  chatCompletions,

  /// The `/responses` protocol used by current OpenAI models and gateways.
  responses,
}

/// Translates Markdown through an OpenAI-compatible text-generation endpoint.
final class OpenAICompatibleTranslationProvider extends LlmTranslationProvider {
  /// Creates an adapter for an OpenAI-compatible API Base URI.
  factory OpenAICompatibleTranslationProvider({
    required Uri apiBaseUri,
    required String modelIdentifier,
    String? apiKey,
    String providerIdentifier = 'openai-compatible',
    OpenAICompatibleProtocol protocol =
        OpenAICompatibleProtocol.chatCompletions,
    TranslationProviderOptions? options,
  }) {
    final baseUrl = validateApiBaseUri(apiBaseUri);
    final validatedModel = validateModelIdentifier(modelIdentifier);
    final validatedProvider = validateProviderIdentifier(providerIdentifier);
    final normalizedApiKey = apiKey?.trim() ?? '';
    final transport = _OpenAIJsonFallbackTransport(
      createTranslationTransport(),
      omitAuthorization: normalizedApiKey.isEmpty,
      protocol: protocol,
      reasoningEnabled: options?.reasoningEnabled ?? false,
    );
    final model = switch (protocol) {
      OpenAICompatibleProtocol.chatCompletions => openai(
        apiKey: normalizedApiKey,
        baseUrl: baseUrl,
        profile: OpenAICompatibleProfile(
          providerId: validatedProvider,
          defaultBaseUrl: baseUrl,
        ),
        transport: transport,
      ).languageModel(validatedModel),
      OpenAICompatibleProtocol.responses => openai(
        apiKey: normalizedApiKey,
        baseUrl: baseUrl,
        profile: OpenAIProfile(
          providerId: validatedProvider,
          defaultBaseUrl: baseUrl,
        ),
        transport: transport,
      ).languageModel(
        validatedModel,
        settings: const OpenAIChatModelSettings(useResponsesApi: true),
      ),
    };
    return OpenAICompatibleTranslationProvider._(
      languageModel: model,
      providerIdentifier: validatedProvider,
      modelIdentifier: validatedModel,
      options: options ?? TranslationProviderOptions(),
    );
  }

  OpenAICompatibleTranslationProvider._({
    required super.languageModel,
    required super.providerIdentifier,
    required super.modelIdentifier,
    required super.options,
  });
}

/// Adapts compatible servers that ignore `stream: true` and return one JSON
/// Chat Completions response, without issuing a second HTTP request.
final class _OpenAIJsonFallbackTransport implements TransportClient {
  const _OpenAIJsonFallbackTransport(
    this._delegate, {
    required bool omitAuthorization,
    required OpenAICompatibleProtocol protocol,
    required bool reasoningEnabled,
  }) : _omitAuthorization = omitAuthorization,
       _protocol = protocol,
       _reasoningEnabled = reasoningEnabled;

  final TransportClient _delegate;
  final bool _omitAuthorization;
  final OpenAICompatibleProtocol _protocol;
  final bool _reasoningEnabled;

  @override
  Future<TransportResponse> send(TransportRequest request) =>
      _delegate.send(_prepare(request));

  @override
  Future<StreamingTransportResponse> sendStream(
    TransportRequest request,
  ) async {
    final prepared = _prepare(request);
    final response = await _delegate.sendStream(prepared);
    final contentType = _header(response.headers, 'content-type');
    if (contentType == null ||
        !contentType.toLowerCase().contains('application/json')) {
      return response;
    }

    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
    }
    try {
      final json = jsonDecode(utf8.decode(bytes));
      final body = _asJsonObject(json);
      final encoded = switch (_protocol) {
        OpenAICompatibleProtocol.chatCompletions => _chatCompletionsJsonAsSse(
          body,
        ),
        OpenAICompatibleProtocol.responses => _responsesJsonAsSse(body),
      };
      return response.copyWith(
        headers: {...response.headers, 'content-type': 'text/event-stream'},
        stream: Stream.value(encoded),
      );
    } catch (_) {
      throw TransportResponseFormatException(
        'The OpenAI-compatible endpoint returned invalid JSON.',
        uri: prepared.uri,
      );
    }
  }

  TransportRequest _prepare(TransportRequest request) {
    var prepared = request;
    final body = request.body;
    if (!_reasoningEnabled && body is Map<String, Object?>) {
      final json = Map<String, Object?>.from(body);
      switch (_protocol) {
        case OpenAICompatibleProtocol.chatCompletions:
          json['reasoning_effort'] = 'none';
        case OpenAICompatibleProtocol.responses:
          json['reasoning'] = const <String, Object?>{'effort': 'none'};
      }
      prepared = prepared.copyWith(body: json);
    }
    if (_omitAuthorization) {
      prepared = prepared.copyWith(
        headers: {
          for (final entry in prepared.headers.entries)
            if (entry.key.toLowerCase() != 'authorization')
              entry.key: entry.value,
        },
      );
    }
    return prepared;
  }
}

List<int> _chatCompletionsJsonAsSse(Map<String, Object?> body) {
  final choices = body['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) {
    throw const FormatException('Missing choices.');
  }
  final choice = Map<String, Object?>.from(choices.first as Map);
  final message = choice['message'];
  if (message is! Map) {
    throw const FormatException('Missing message.');
  }
  final messageJson = Map<String, Object?>.from(message);
  final text = _messageText(messageJson['content']);
  if (text == null) {
    throw const FormatException('Missing message content.');
  }

  final id = body['id']?.toString() ?? 'translation-response';
  final model = body['model']?.toString();
  final created = body['created'];
  final finishReason = choice['finish_reason']?.toString() ?? 'stop';
  final firstChunk = <String, Object?>{
    'id': id,
    'object': 'chat.completion.chunk',
    if (created != null) 'created': created,
    if (model != null) 'model': model,
    'choices': [
      {
        'index': 0,
        'delta': {'role': 'assistant', 'content': text},
        'finish_reason': null,
      },
    ],
  };
  final finalChunk = <String, Object?>{
    'id': id,
    'object': 'chat.completion.chunk',
    if (created != null) 'created': created,
    if (model != null) 'model': model,
    'choices': [
      {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': finishReason},
    ],
    if (body['usage'] != null) 'usage': body['usage'],
  };
  return utf8.encode(
    'data: ${jsonEncode(firstChunk)}\n\n'
    'data: ${jsonEncode(finalChunk)}\n\n'
    'data: [DONE]\n\n',
  );
}

List<int> _responsesJsonAsSse(Map<String, Object?> body) {
  final output = body['output'];
  if (output is! List) {
    throw const FormatException('Missing response output.');
  }

  Map<String, Object?>? message;
  var contentIndex = 0;
  final text = StringBuffer();
  for (final item in output) {
    if (item is! Map || item['type'] != 'message') {
      continue;
    }
    final candidate = Map<String, Object?>.from(item);
    final content = candidate['content'];
    if (content is! List) {
      continue;
    }
    for (var index = 0; index < content.length; index += 1) {
      final part = content[index];
      if (part is Map &&
          part['type'] == 'output_text' &&
          part['text'] is String) {
        message ??= candidate;
        contentIndex = index;
        text.write(part['text'] as String);
      }
    }
  }
  if (message == null || text.toString().trim().isEmpty) {
    throw const FormatException('Missing response output text.');
  }

  final responseId = body['id']?.toString() ?? 'translation-response';
  final messageId = message['id']?.toString() ?? 'translation-message';
  final completedResponse = <String, Object?>{
    ...body,
    'id': responseId,
    'status': body['status'] ?? 'completed',
  };
  final events = <Map<String, Object?>>[
    {
      'type': 'response.created',
      'response': {
        'id': responseId,
        if (body['model'] != null) 'model': body['model'],
        if (body['created_at'] != null) 'created_at': body['created_at'],
        'status': 'in_progress',
      },
    },
    {
      'type': 'response.output_item.added',
      'output_index': 0,
      'item': {
        'id': messageId,
        'type': 'message',
        'status': 'in_progress',
        'role': 'assistant',
        'content': <Object?>[],
      },
    },
    {
      'type': 'response.output_text.delta',
      'item_id': messageId,
      'output_index': 0,
      'content_index': contentIndex,
      'delta': text.toString(),
    },
    {
      'type': 'response.output_text.done',
      'item_id': messageId,
      'output_index': 0,
      'content_index': contentIndex,
      'text': text.toString(),
    },
    {'type': 'response.completed', 'response': completedResponse},
  ];
  return utf8.encode(
    '${events.map((event) => 'data: ${jsonEncode(event)}').join('\n\n')}\n\n',
  );
}

String? _header(Map<String, String> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name) {
      return entry.value;
    }
  }
  return null;
}

Map<String, Object?> _asJsonObject(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected a JSON object.');
  }
  return Map<String, Object?>.from(value);
}

String? _messageText(Object? content) {
  if (content is String) {
    return content;
  }
  if (content is! List) {
    return null;
  }
  final buffer = StringBuffer();
  for (final item in content) {
    if (item is Map && item['type'] == 'text' && item['text'] is String) {
      buffer.write(item['text']);
    }
  }
  return buffer.isEmpty ? null : buffer.toString();
}
