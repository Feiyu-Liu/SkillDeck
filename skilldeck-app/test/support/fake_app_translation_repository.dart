import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/data/services/translation_credential_store.dart';
import 'package:skills_manager/features/translation/data/services/translation_settings_store.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_translation/skills_translation.dart';

AppTranslationRepository fakeAppTranslationRepository({
  TranslationSettingsStore? settingsStore,
  TranslationCredentialStore? credentialStore,
  TranslationCache? cache,
  AppTranslationProviderFactory? providerFactory,
}) => AppTranslationRepository(
  // Most feature tests exercise an already configured translator. Pass an
  // empty store explicitly to exercise first-run behavior.
  settingsStore:
      settingsStore ??
      MemoryTranslationSettingsStore(
        value: AppTranslationSettings.defaults().toJson(),
      ),
  credentialStore: credentialStore ?? MemoryTranslationCredentialStore(),
  cache: cache ?? MemoryTranslationCache(),
  providerFactory: providerFactory ?? const _UnavailableProviderFactory(),
);

final class MemoryTranslationSettingsStore implements TranslationSettingsStore {
  Map<String, Object?>? value;
  Object? readError;
  Object? writeError;
  final List<String> events;

  MemoryTranslationSettingsStore({
    Map<String, Object?>? value,
    List<String>? events,
  }) : value = value == null ? null : _copy(value),
       events = events ?? [];

  @override
  Future<Map<String, Object?>?> read() async {
    final error = readError;
    if (error != null) throw error;
    return value == null ? null : _copy(value!);
  }

  @override
  Future<void> write(Map<String, Object?> value) async {
    events.add('settings.write');
    final error = writeError;
    if (error != null) throw error;
    this.value = _copy(value);
  }

  @override
  Future<void> delete() async {
    events.add('settings.delete');
    value = null;
  }
}

final class MemoryTranslationCredentialStore
    implements TranslationCredentialStore {
  final Map<String, String> values = {};
  final List<String> events;

  MemoryTranslationCredentialStore({List<String>? events})
    : events = events ?? [];

  @override
  Future<String?> read(String credentialId) async => values[credentialId];

  @override
  Future<void> write(String credentialId, String value) async {
    events.add('credential.write:$credentialId');
    values[credentialId] = value;
  }

  @override
  Future<void> delete(String credentialId) async {
    events.add('credential.delete:$credentialId');
    values.remove(credentialId);
  }
}

final class MemoryTranslationCache implements TranslationCache {
  final Map<TranslationCacheKey, CompletedTranslation> values = {};
  final List<String> deletedSlotKeys = [];
  final List<TranslationCacheKey> readKeys = [];
  final List<(String, String)> evictedGenerations = [];
  Future<CompletedTranslation?> Function(TranslationCacheKey)? readHandler;
  Object? readError;
  Object? saveError;
  Object? deleteSlotError;
  Object? evictError;
  void Function(CompletedTranslation)? onSaved;

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<void> deleteSlot({required String slotKey}) async {
    deletedSlotKeys.add(slotKey);
    final error = deleteSlotError;
    if (error != null) throw error;
    values.removeWhere((key, _) => key.slotKey == slotKey);
  }

  @override
  Future<void> evictStale({
    required String slotKey,
    required String currentContentHash,
  }) async {
    evictedGenerations.add((slotKey, currentContentHash));
    if (evictError case final error?) throw error;
    values.removeWhere(
      (key, _) =>
          key.slotKey == slotKey && key.contentHash != currentContentHash,
    );
  }

  @override
  Future<CompletedTranslation?> read(TranslationCacheKey key) async {
    readKeys.add(key);
    final error = readError;
    if (error != null) throw error;
    final handler = readHandler;
    return handler == null ? values[key] : handler(key);
  }

  @override
  Future<void> saveOrReplace(CompletedTranslation value) async {
    final error = saveError;
    if (error != null) throw error;
    final key = TranslationCacheKey(
      slotKey: value.slotKey,
      contentHash: value.contentHash,
      documentIdentifier: value.documentIdentifier,
      targetLanguage: value.targetLanguage,
      scope: value.scope,
    );
    values.removeWhere(
      (candidate, _) =>
          candidate.slotKey == key.slotKey &&
          candidate.contentHash == key.contentHash &&
          candidate.documentIdentifier == key.documentIdentifier &&
          candidate.targetLanguage == key.targetLanguage &&
          candidate.scope == key.scope,
    );
    values[key] = value;
    onSaved?.call(value);
  }
}

final class _UnavailableProviderFactory
    implements AppTranslationProviderFactory {
  const _UnavailableProviderFactory();

  @override
  TranslationProvider create({required profile, required apiKey}) =>
      throw StateError('No translation Provider was configured for this test.');
}

Map<String, Object?> _copy(Map<String, Object?> value) => {
  for (final entry in value.entries)
    entry.key: switch (entry.value) {
      Map<Object?, Object?> nested => _copy(Map<String, Object?>.from(nested)),
      _ => entry.value,
    },
};
