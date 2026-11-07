import 'package:llm_dart_anthropic/llm_dart_anthropic.dart';
import 'llm_translation_provider.dart';
import 'llm_transport.dart';
import 'provider_validation.dart';
import 'translation_provider_options.dart';
import 'validation.dart';

/// Translates Markdown through Anthropic's native Messages API.
final class AnthropicMessagesTranslationProvider
    extends LlmTranslationProvider {
  /// Creates an adapter for Anthropic's native `/messages` protocol.
  factory AnthropicMessagesTranslationProvider({
    required String apiKey,
    required String modelIdentifier,
    Uri? apiBaseUri,
    String anthropicVersion = '2023-06-01',
    TranslationProviderOptions? options,
  }) {
    requireNonBlank(apiKey, 'apiKey');
    requireNonBlank(anthropicVersion, 'anthropicVersion');
    final baseUrl = validateApiBaseUri(
      apiBaseUri ?? Uri.parse('https://api.anthropic.com/v1'),
    );
    final validatedModel = validateModelIdentifier(modelIdentifier);
    final model = anthropic(
      apiKey: apiKey,
      baseUrl: baseUrl,
      transport: createTranslationTransport(),
    ).languageModel(
      validatedModel,
      settings: AnthropicChatModelSettings(anthropicVersion: anthropicVersion),
    );
    return AnthropicMessagesTranslationProvider._(
      languageModel: model,
      providerIdentifier: 'anthropic',
      modelIdentifier: validatedModel,
      options: options ?? TranslationProviderOptions(),
    );
  }

  AnthropicMessagesTranslationProvider._({
    required super.languageModel,
    required super.providerIdentifier,
    required super.modelIdentifier,
    required super.options,
  });
}
