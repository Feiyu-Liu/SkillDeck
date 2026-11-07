import 'package:skills_translation/skills_translation.dart';

enum TranslationDemoProvider {
  openAICompatible,
  anthropic,
}

final class TranslationDemoConfig {
  const TranslationDemoConfig({
    required this.provider,
    required this.apiBaseUri,
    required this.modelIdentifier,
    required this.apiKey,
    required this.protocol,
    required this.targetLanguage,
    required this.segmentCharacterBudgetText,
    required this.maxConcurrentSegments,
    required this.maxOutputTokensText,
    required this.reasoningEnabled,
  });

  factory TranslationDemoConfig.initial() => const TranslationDemoConfig(
        provider: TranslationDemoProvider.openAICompatible,
        apiBaseUri: 'http://100.127.216.82:11434/v1',
        modelIdentifier: '',
        apiKey: '',
        protocol: OpenAICompatibleProtocol.responses,
        targetLanguage: 'zh-Hans',
        segmentCharacterBudgetText: '2000',
        maxConcurrentSegments: 3,
        maxOutputTokensText: '',
        reasoningEnabled: false,
      );

  final TranslationDemoProvider provider;
  final String apiBaseUri;
  final String modelIdentifier;
  final String apiKey;
  final OpenAICompatibleProtocol protocol;
  final String targetLanguage;
  final String segmentCharacterBudgetText;
  final int maxConcurrentSegments;
  final String maxOutputTokensText;
  final bool reasoningEnabled;

  TranslationDemoConfig copyWith({
    TranslationDemoProvider? provider,
    String? apiBaseUri,
    String? modelIdentifier,
    String? apiKey,
    OpenAICompatibleProtocol? protocol,
    String? targetLanguage,
    String? segmentCharacterBudgetText,
    int? maxConcurrentSegments,
    String? maxOutputTokensText,
    bool? reasoningEnabled,
  }) =>
      TranslationDemoConfig(
        provider: provider ?? this.provider,
        apiBaseUri: apiBaseUri ?? this.apiBaseUri,
        modelIdentifier: modelIdentifier ?? this.modelIdentifier,
        apiKey: apiKey ?? this.apiKey,
        protocol: protocol ?? this.protocol,
        targetLanguage: targetLanguage ?? this.targetLanguage,
        segmentCharacterBudgetText:
            segmentCharacterBudgetText ?? this.segmentCharacterBudgetText,
        maxConcurrentSegments:
            maxConcurrentSegments ?? this.maxConcurrentSegments,
        maxOutputTokensText: maxOutputTokensText ?? this.maxOutputTokensText,
        reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
      );

  TranslationDemoConfig switchedTo(TranslationDemoProvider nextProvider) {
    if (nextProvider == provider) {
      return this;
    }
    return TranslationDemoConfig(
      provider: nextProvider,
      apiBaseUri: switch (nextProvider) {
        TranslationDemoProvider.openAICompatible =>
          'http://100.127.216.82:11434/v1',
        TranslationDemoProvider.anthropic => 'https://api.anthropic.com/v1',
      },
      modelIdentifier: '',
      apiKey: '',
      protocol: protocol,
      targetLanguage: targetLanguage,
      segmentCharacterBudgetText: segmentCharacterBudgetText,
      maxConcurrentSegments: maxConcurrentSegments,
      maxOutputTokensText: maxOutputTokensText,
      reasoningEnabled: reasoningEnabled,
    );
  }
}
