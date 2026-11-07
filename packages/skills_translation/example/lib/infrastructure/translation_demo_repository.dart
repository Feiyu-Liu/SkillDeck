import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation_example/application/translation_demo_config.dart';

abstract interface class TranslationDemoRepository {
  TranslationJob start({
    required TranslationDemoConfig config,
    required SourceDocument sourceDocument,
  });
}

final class LlmTranslationDemoRepository implements TranslationDemoRepository {
  const LlmTranslationDemoRepository();

  @override
  TranslationJob start({
    required TranslationDemoConfig config,
    required SourceDocument sourceDocument,
  }) {
    final apiBaseUri = Uri.parse(config.apiBaseUri.trim());
    final modelIdentifier = config.modelIdentifier.trim();
    final apiKey = config.apiKey.trim();
    final segmentCharacterBudget =
        int.parse(config.segmentCharacterBudgetText.trim());
    final maxOutputTokensText = config.maxOutputTokensText.trim();
    final maxOutputTokens =
        maxOutputTokensText.isEmpty ? null : int.parse(maxOutputTokensText);
    final provider = switch (config.provider) {
      TranslationDemoProvider.openAICompatible =>
        OpenAICompatibleTranslationProvider(
          apiBaseUri: apiBaseUri,
          modelIdentifier: modelIdentifier,
          apiKey: apiKey,
          protocol: config.protocol,
          options: TranslationProviderOptions(
            segmentCharacterBudget: segmentCharacterBudget,
            maxConcurrentSegments: config.maxConcurrentSegments,
            maxOutputTokens: maxOutputTokens,
            temperature: null,
            reasoningEnabled: config.reasoningEnabled,
          ),
        ),
      TranslationDemoProvider.anthropic => AnthropicMessagesTranslationProvider(
          apiBaseUri: apiBaseUri,
          modelIdentifier: modelIdentifier,
          apiKey: apiKey,
          options: TranslationProviderOptions(
            segmentCharacterBudget: segmentCharacterBudget,
            maxConcurrentSegments: config.maxConcurrentSegments,
            maxOutputTokens: maxOutputTokens,
            reasoningEnabled: config.reasoningEnabled,
          ),
        ),
    };
    return provider.start(
      sourceDocument: sourceDocument,
      targetLanguage: TargetLanguage(config.targetLanguage.trim()),
    );
  }
}
