import 'dart:async';
import 'dart:math';

import 'package:skills_manager/features/translation/data/services/translation_credential_store.dart';
import 'package:skills_manager/features/translation/data/services/translation_settings_store.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_translation/skills_translation.dart';

abstract interface class AppTranslationProviderFactory {
  TranslationProvider create({
    required TranslationProviderProfile profile,
    required String? apiKey,
  });
}

final class PackageAppTranslationProviderFactory
    implements AppTranslationProviderFactory {
  const PackageAppTranslationProviderFactory();

  @override
  TranslationProvider create({
    required TranslationProviderProfile profile,
    required String? apiKey,
  }) {
    final options = TranslationProviderOptions(
      segmentCharacterBudget: profile.segmentCharacterBudget,
      maxConcurrentSegments: profile.maxConcurrentSegments,
      maxOutputTokens: profile.maxOutputTokens,
      temperature: null,
      reasoningEnabled: profile.reasoningEnabled,
    );
    return switch (profile.provider) {
      AppTranslationProviderKind.openAICompatible =>
        OpenAICompatibleTranslationProvider(
          apiBaseUri: profile.endpointUri,
          modelIdentifier: profile.model,
          apiKey: apiKey,
          protocol: switch (profile.protocol) {
            AppOpenAIProtocol.chatCompletions =>
              OpenAICompatibleProtocol.chatCompletions,
            AppOpenAIProtocol.responses => OpenAICompatibleProtocol.responses,
          },
          options: options,
        ),
      AppTranslationProviderKind.anthropic =>
        AnthropicMessagesTranslationProvider(
          apiBaseUri: profile.endpointUri,
          modelIdentifier: profile.model,
          apiKey: apiKey ?? '',
          options: options,
        ),
    };
  }
}

final class AppTranslationDraft {
  const AppTranslationDraft({
    this.translatedBlocks = const {},
    this.translatedDescription,
    this.completedBlockCount = 0,
    this.totalBlockCount = 0,
  });

  final Map<MarkdownBlockId, String> translatedBlocks;
  final String? translatedDescription;
  final int completedBlockCount;
  final int totalBlockCount;
}

abstract interface class AppTranslationSession {
  Stream<AppTranslationDraft> get drafts;

  Future<TranslationJobOutcome> get result;

  Future<void> cancel();
}

final class AppTranslationConfigurationException implements Exception {
  const AppTranslationConfigurationException(this.code);

  final String code;

  @override
  String toString() => 'AppTranslationConfigurationException($code)';
}

/// Whether a connection test reached the Provider and got a translation back.
final class AppTranslationConnectionResult {
  const AppTranslationConnectionResult.succeeded() : failureCode = null;

  const AppTranslationConnectionResult.failed(String this.failureCode);

  /// A configuration code such as `credential_required`, or the name of a
  /// [TranslationFailureCode]. Null when the test succeeded.
  final String? failureCode;

  bool get succeeded => failureCode == null;
}

const _connectionTestSlotKey = 'connection-test';

final class AppTranslationRepository {
  AppTranslationRepository({
    required TranslationSettingsStore settingsStore,
    required TranslationCredentialStore credentialStore,
    required TranslationCache cache,
    AppTranslationProviderFactory providerFactory =
        const PackageAppTranslationProviderFactory(),
    bool Function(String slotKey, String contentHash)? isCurrentContent,
    String? Function(String slotKey)? currentContentHash,
    void Function()? onCacheDeleted,
    Random? random,
  }) : _settingsStore = settingsStore,
       _credentialStore = credentialStore,
       _cache = cache,
       _providerFactory = providerFactory,
       _isCurrentContent = isCurrentContent,
       _currentContentHash = currentContentHash,
       _onCacheDeleted = onCacheDeleted,
       _random = random ?? Random.secure();

  final TranslationSettingsStore _settingsStore;
  final TranslationCredentialStore _credentialStore;
  final TranslationCache _cache;
  final AppTranslationProviderFactory _providerFactory;
  final bool Function(String, String)? _isCurrentContent;
  final String? Function(String)? _currentContentHash;
  final void Function()? _onCacheDeleted;
  final Random _random;
  var _profileSaveInFlight = false;

  Future<AppTranslationSettings> loadSettings() async {
    final json = await _settingsStore.read();
    return json == null
        ? AppTranslationSettings.defaults()
        : AppTranslationSettings.fromJson(json);
  }

  Future<AppTranslationSettings> saveProfile(
    TranslationProviderProfile profile, {
    String? replacementApiKey,
    bool clearCredential = false,
  }) async {
    if (_profileSaveInFlight) {
      throw const AppTranslationConfigurationException(
        'settings_save_in_progress',
      );
    }
    _profileSaveInFlight = true;
    try {
      return await _saveProfile(
        profile,
        replacementApiKey: replacementApiKey,
        clearCredential: clearCredential,
      );
    } finally {
      _profileSaveInFlight = false;
    }
  }

  Future<AppTranslationSettings> clearProfile() async {
    if (_profileSaveInFlight) {
      throw const AppTranslationConfigurationException(
        'settings_save_in_progress',
      );
    }
    _profileSaveInFlight = true;
    try {
      final previous = await loadSettings();
      await _settingsStore.delete();
      final credentialId = previous.isConfigured
          ? previous.activeProfile.credentialId
          : null;
      if (credentialId != null) {
        try {
          await _credentialStore.delete(credentialId);
        } on Object {
          // The settings no longer reference this credential. Cleanup is
          // best-effort for the same reason as credential rotation cleanup.
        }
      }
      return AppTranslationSettings.defaults();
    } finally {
      _profileSaveInFlight = false;
    }
  }

  Future<AppTranslationSettings> _saveProfile(
    TranslationProviderProfile profile, {
    String? replacementApiKey,
    bool clearCredential = false,
  }) async {
    profile.validate();
    if (clearCredential && replacementApiKey != null) {
      throw const AppTranslationConfigurationException(
        'credential_update_conflict',
      );
    }
    final previousCredentialId = profile.credentialId;
    String? newCredentialId;
    var publishedProfile = profile;
    final normalizedSecret = replacementApiKey?.trim();
    if (normalizedSecret != null && normalizedSecret.isNotEmpty) {
      newCredentialId = _newCredentialId();
      await _credentialStore.write(newCredentialId, normalizedSecret);
      publishedProfile = profile.copyWith(credentialId: newCredentialId);
    } else if (clearCredential) {
      publishedProfile = profile.copyWith(credentialId: null);
    }

    final settings = AppTranslationSettings(
      version: AppTranslationSettings.currentVersion,
      activeProfile: publishedProfile,
    );
    try {
      await _settingsStore.write(settings.toJson());
    } on Object {
      if (newCredentialId != null) {
        await _credentialStore.delete(newCredentialId);
      }
      rethrow;
    }

    if (previousCredentialId != null &&
        previousCredentialId != publishedProfile.credentialId) {
      try {
        await _credentialStore.delete(previousCredentialId);
      } on Object {
        // The new opaque reference is already atomically published. A stale
        // unreachable secret is safer than rolling settings back to ambiguity.
      }
    }
    return settings;
  }

  Future<CompletedTranslation?> readCached({
    required SourceDocument request,
    required String targetLanguage,
    TranslationScope scope = TranslationScope.fullDocument,
  }) => readCachedEntry(
    TranslationCacheKey(
      slotKey: request.slotKey,
      contentHash: request.contentHash,
      documentIdentifier: request.documentIdentifier,
      targetLanguage: TargetLanguage(targetLanguage),
      scope: scope,
    ),
  );

  Future<CompletedTranslation?> readCachedEntry(TranslationCacheKey key) =>
      _cache.read(key);

  Future<void> evictStale({
    required String slotKey,
    required String currentContentHash,
  }) => _cache.evictStale(
    slotKey: slotKey,
    currentContentHash: currentContentHash,
  );

  Future<AppTranslationSession> start({
    required SourceDocument request,
    required TranslationProviderProfile profile,
    TranslationScope scope = TranslationScope.fullDocument,
  }) async {
    if (!(await loadSettings()).isConfigured) {
      throw const AppTranslationConfigurationException(
        'provider_not_configured',
      );
    }
    profile.validate();
    if (scope == TranslationScope.descriptionOnly &&
        (request.documentIdentifier != 'SKILL.md' ||
            readTranslatableSkillDescription(request.content) == null)) {
      throw const AppTranslationConfigurationException(
        'description_unavailable',
      );
    }
    final credentialId = profile.credentialId;
    final apiKey = credentialId == null
        ? null
        : await _credentialStore.read(credentialId);
    if (credentialId != null && apiKey == null) {
      throw const AppTranslationConfigurationException(
        'credential_unavailable',
      );
    }
    if (profile.provider == AppTranslationProviderKind.anthropic &&
        (apiKey == null || apiKey.trim().isEmpty)) {
      throw const AppTranslationConfigurationException('credential_required');
    }
    final provider = _providerFactory.create(profile: profile, apiKey: apiKey);
    final job = provider.start(
      sourceDocument: request,
      targetLanguage: TargetLanguage(profile.targetLanguage),
      scope: scope,
    );
    return _PackageAppTranslationSession(
      job: job,
      cache: _cache,
      isCurrentContent: _isCurrentContent,
      currentContentHash: _currentContentHash,
    );
  }

  /// Translates a fixed sample sentence through [profile] to check that the
  /// Provider accepts the endpoint, model, and key before they are saved.
  ///
  /// The sample is the only content sent, and its result is never cached.
  /// [replacementApiKey] is used when it is not empty; otherwise the stored
  /// credential is used only when [useStoredCredential] is true.
  Future<AppTranslationConnectionResult> testConnection({
    required TranslationProviderProfile profile,
    String? replacementApiKey,
    bool useStoredCredential = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      profile.validate();
    } on Object {
      return const AppTranslationConnectionResult.failed(
        'invalid_configuration',
      );
    }
    final enteredKey = replacementApiKey?.trim() ?? '';
    String? apiKey = enteredKey.isEmpty ? null : enteredKey;
    if (apiKey == null && useStoredCredential) {
      if (profile.credentialId case final credentialId?) {
        apiKey = await _credentialStore.read(credentialId);
        if (apiKey == null) {
          return const AppTranslationConnectionResult.failed(
            'credential_unavailable',
          );
        }
      }
    }
    if (profile.provider == AppTranslationProviderKind.anthropic &&
        (apiKey == null || apiKey.trim().isEmpty)) {
      return const AppTranslationConnectionResult.failed('credential_required');
    }
    final TranslationJob job;
    try {
      job = _providerFactory
          .create(profile: profile, apiKey: apiKey)
          .start(
            sourceDocument: SourceDocument(
              slotKey: _connectionTestSlotKey,
              contentHash: _connectionTestSlotKey,
              documentIdentifier: 'connection-test.md',
              content: 'Hello.',
            ),
            targetLanguage: TargetLanguage(profile.targetLanguage),
          );
    } on Object {
      return const AppTranslationConnectionResult.failed(
        'invalid_configuration',
      );
    }
    final TranslationJobOutcome outcome;
    try {
      outcome = await job.result.timeout(timeout);
    } on TimeoutException {
      await job.cancel();
      return AppTranslationConnectionResult.failed(
        TranslationFailureCode.timedOut.name,
      );
    }
    return switch (outcome) {
      CompletedTranslation() =>
        const AppTranslationConnectionResult.succeeded(),
      TranslationFailure(:final code) => AppTranslationConnectionResult.failed(
        code.name,
      ),
      TranslationJobCancellation() => AppTranslationConnectionResult.failed(
        TranslationFailureCode.unknown.name,
      ),
    };
  }

  Future<void> clearCache() async {
    await _cache.clear();
    _onCacheDeleted?.call();
  }

  Future<void> deleteSlot({required String slotKey}) async {
    await _cache.deleteSlot(slotKey: slotKey);
    _onCacheDeleted?.call();
  }

  String _newCredentialId() {
    final bytes = List<int>.generate(20, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}

final class _PackageAppTranslationSession implements AppTranslationSession {
  _PackageAppTranslationSession({
    required TranslationJob job,
    required TranslationCache cache,
    required bool Function(String, String)? isCurrentContent,
    required String? Function(String)? currentContentHash,
  }) : _job = job,
       _cache = cache,
       _isCurrentContent = isCurrentContent,
       _currentContentHash = currentContentHash {
    _subscription = _job.drafts.listen((draft) {
      _drafts.add(
        AppTranslationDraft(
          translatedBlocks: draft.translatedBlocks,
          translatedDescription: draft.translatedDescription,
          completedBlockCount: draft.completedBlockCount,
          totalBlockCount: draft.totalBlockCount,
        ),
      );
    }, onDone: _drafts.close);
    _result = _complete();
  }

  final TranslationJob _job;
  final TranslationCache _cache;
  final bool Function(String, String)? _isCurrentContent;
  final String? Function(String)? _currentContentHash;
  final StreamController<AppTranslationDraft> _drafts =
      StreamController<AppTranslationDraft>(sync: true);
  late final StreamSubscription<TranslationDraft> _subscription;
  late final Future<TranslationJobOutcome> _result;

  @override
  Stream<AppTranslationDraft> get drafts => _drafts.stream;

  @override
  Future<TranslationJobOutcome> get result => _result;

  Future<TranslationJobOutcome> _complete() async {
    final outcome = await _job.result;
    if (outcome case final CompletedTranslation completed) {
      if (_isCurrentContent?.call(completed.slotKey, completed.contentHash) ==
          false) {
        return const TranslationJobCancellation();
      }
      await _cache.saveOrReplace(completed);
      if (_isCurrentContent?.call(completed.slotKey, completed.contentHash) ==
          false) {
        final currentHash = _currentContentHash?.call(completed.slotKey);
        if (currentHash == null) {
          await _cache.deleteSlot(slotKey: completed.slotKey);
        } else {
          await _cache.evictStale(
            slotKey: completed.slotKey,
            currentContentHash: currentHash,
          );
        }
        return const TranslationJobCancellation();
      }
    }
    return outcome;
  }

  @override
  Future<void> cancel() async {
    await _job.cancel();
    await _subscription.cancel();
    if (!_drafts.isClosed) await _drafts.close();
  }
}
