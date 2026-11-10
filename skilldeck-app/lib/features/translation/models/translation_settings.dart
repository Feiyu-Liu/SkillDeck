enum AppTranslationProviderKind { openAICompatible, anthropic }

enum AppOpenAIProtocol { chatCompletions, responses }

final class TranslationProviderProfile {
  const TranslationProviderProfile({
    required this.provider,
    required this.endpoint,
    required this.model,
    required this.targetLanguage,
    this.credentialId,
    this.protocol = AppOpenAIProtocol.responses,
    this.segmentCharacterBudget = 4000,
    this.maxConcurrentSegments = 3,
    this.maxOutputTokens,
    this.reasoningEnabled = false,
  });

  factory TranslationProviderProfile.defaults() =>
      const TranslationProviderProfile(
        provider: AppTranslationProviderKind.openAICompatible,
        endpoint: 'https://api.openai.com/v1',
        model: 'gpt-5.4-mini',
        targetLanguage: 'zh-Hans',
      );

  final AppTranslationProviderKind provider;
  final String endpoint;
  final String model;
  final String targetLanguage;
  final String? credentialId;
  final AppOpenAIProtocol protocol;
  final int segmentCharacterBudget;
  final int maxConcurrentSegments;
  final int? maxOutputTokens;
  final bool reasoningEnabled;

  Uri get endpointUri => Uri.parse(endpoint);

  String get endpointHost => endpointUri.host;

  bool get hasCredential => credentialId != null;

  TranslationProviderProfile copyWith({
    AppTranslationProviderKind? provider,
    String? endpoint,
    String? model,
    String? targetLanguage,
    Object? credentialId = _unset,
    AppOpenAIProtocol? protocol,
    int? segmentCharacterBudget,
    int? maxConcurrentSegments,
    Object? maxOutputTokens = _unset,
    bool? reasoningEnabled,
  }) => TranslationProviderProfile(
    provider: provider ?? this.provider,
    endpoint: endpoint ?? this.endpoint,
    model: model ?? this.model,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    credentialId: identical(credentialId, _unset)
        ? this.credentialId
        : credentialId as String?,
    protocol: protocol ?? this.protocol,
    segmentCharacterBudget:
        segmentCharacterBudget ?? this.segmentCharacterBudget,
    maxConcurrentSegments: maxConcurrentSegments ?? this.maxConcurrentSegments,
    maxOutputTokens: identical(maxOutputTokens, _unset)
        ? this.maxOutputTokens
        : maxOutputTokens as int?,
    reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
  );

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'endpoint': endpoint,
    'model': model,
    'targetLanguage': targetLanguage,
    if (credentialId != null) 'credentialId': credentialId,
    'protocol': protocol.name,
    'segmentCharacterBudget': segmentCharacterBudget,
    'maxConcurrentSegments': maxConcurrentSegments,
    'maxOutputTokens': maxOutputTokens,
    'reasoningEnabled': reasoningEnabled,
  };

  factory TranslationProviderProfile.fromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, String key, T fallback) {
      final raw = json[key];
      return values.where((value) => value.name == raw).firstOrNull ?? fallback;
    }

    final defaults = TranslationProviderProfile.defaults();
    final model = _string(json, 'model', defaults.model);
    final profile = TranslationProviderProfile(
      provider: enumValue(
        AppTranslationProviderKind.values,
        'provider',
        defaults.provider,
      ),
      endpoint: _string(json, 'endpoint', defaults.endpoint),
      model: model == 'gpt-5-mini' ? defaults.model : model,
      targetLanguage: _string(json, 'targetLanguage', defaults.targetLanguage),
      credentialId: _nullableString(json, 'credentialId'),
      protocol: enumValue(
        AppOpenAIProtocol.values,
        'protocol',
        defaults.protocol,
      ),
      segmentCharacterBudget: _positiveInt(
        json,
        'segmentCharacterBudget',
        defaults.segmentCharacterBudget,
      ),
      maxConcurrentSegments: _positiveInt(
        json,
        'maxConcurrentSegments',
        defaults.maxConcurrentSegments,
      ),
      maxOutputTokens: _nullablePositiveInt(json, 'maxOutputTokens'),
      reasoningEnabled: json['reasoningEnabled'] is bool
          ? json['reasoningEnabled']! as bool
          : defaults.reasoningEnabled,
    );
    profile.validate();
    return profile;
  }

  void validate() {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'The Provider Endpoint must be an HTTP(S) URI without credentials.',
      );
    }
    if (model.trim().isEmpty || targetLanguage.trim().isEmpty) {
      throw const FormatException('Model and Target Language are required.');
    }
    if (segmentCharacterBudget <= 0 || maxConcurrentSegments <= 0) {
      throw const FormatException('Advanced limits must be positive.');
    }
    if (maxOutputTokens case final value? when value <= 0) {
      throw const FormatException('Max Output Tokens must be positive.');
    }
  }
}

final class AppTranslationSettings {
  const AppTranslationSettings({
    required this.version,
    required this.activeProfile,
    this.isConfigured = true,
  });

  factory AppTranslationSettings.defaults() => AppTranslationSettings(
    version: currentVersion,
    activeProfile: TranslationProviderProfile.defaults(),
    isConfigured: false,
  );

  static const currentVersion = 1;

  final int version;
  final TranslationProviderProfile activeProfile;

  // Derived from the presence of saved settings, never persisted separately.
  final bool isConfigured;

  Map<String, Object?> toJson() => {
    'version': version,
    'translation': {'activeProfile': activeProfile.toJson()},
  };

  factory AppTranslationSettings.fromJson(Map<String, Object?> json) {
    if (json['version'] != currentVersion) {
      throw const FormatException('Unsupported settings version.');
    }
    final translation = _object(json, 'translation');
    return AppTranslationSettings(
      version: currentVersion,
      activeProfile: TranslationProviderProfile.fromJson(
        _object(translation, 'activeProfile'),
      ),
    );
  }
}

const _unset = Object();

Map<String, Object?> _object(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key must be an object.');
  return Map<String, Object?>.from(value);
}

String _string(Map<String, Object?> json, String key, String fallback) {
  final value = json[key];
  return value is String && value.trim().isNotEmpty ? value : fallback;
}

String? _nullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String && value.trim().isNotEmpty ? value : null;
}

int _positiveInt(Map<String, Object?> json, String key, int fallback) {
  final value = json[key];
  return value is int && value > 0 ? value : fallback;
}

int? _nullablePositiveInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int && value > 0) return value;
  throw FormatException('$key must be null or a positive integer.');
}
