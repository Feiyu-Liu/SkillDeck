import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_md/flutter_md.dart' show MarkdownSourceParser;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/data/services/translation_settings_store.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_translation/skills_translation.dart';

import '../../../../support/fake_app_translation_repository.dart';
import '../../../../support/scripted_translation_provider.dart';

void main() {
  test('cache reads never scan or evict another generation', () async {
    final cache = MemoryTranslationCache();
    final repository = fakeAppTranslationRepository(cache: cache);
    final key = TranslationCacheKey(
      slotKey: 'alpha',
      contentHash: 'current',
      documentIdentifier: 'SKILL.md',
      targetLanguage: TargetLanguage('zh-Hans'),
    );

    expect(await repository.readCachedEntry(key), isNull);
    expect(cache.readKeys, [key]);
    expect(cache.evictedGenerations, isEmpty);

    await repository.evictStale(
      slotKey: 'alpha',
      currentContentHash: 'current',
    );
    expect(cache.evictedGenerations, [('alpha', 'current')]);
  });

  test(
    'a translation completed after a revision change is not cached',
    () async {
      final provider = _ControlledProvider();
      final cache = MemoryTranslationCache();
      var currentHash = 'first';
      final repository = AppTranslationRepository(
        settingsStore: MemoryTranslationSettingsStore(
          value: AppTranslationSettings.defaults().toJson(),
        ),
        credentialStore: MemoryTranslationCredentialStore(),
        cache: cache,
        providerFactory: _ControlledFactory(provider),
        currentContentHash: (_) => currentHash,
        isCurrentContent: (_, hash) => hash == currentHash,
      );
      final session = await repository.start(
        request: SourceDocument(
          slotKey: 'alpha',
          contentHash: 'first',
          documentIdentifier: 'SKILL.md',
          content: '# Alpha',
        ),
        profile: (await repository.loadSettings()).activeProfile,
      );
      currentHash = 'second';
      provider.job!._result.complete(
        CompletedTranslation(
          slotKey: 'alpha',
          contentHash: 'first',
          documentIdentifier: 'SKILL.md',
          targetLanguage: TargetLanguage('zh-Hans'),
          translatedContent: '# Old',
          provenance: TranslationProvenance(providerIdentifier: 'controlled'),
        ),
      );

      expect(await session.result, isA<TranslationJobCancellation>());
      expect(cache.values, isEmpty);
    },
  );

  test('removes a translation if the revision changes during save', () async {
    final provider = _ControlledProvider();
    final cache = MemoryTranslationCache();
    var currentHash = 'first';
    cache.onSaved = (_) => currentHash = 'second';
    final repository = AppTranslationRepository(
      settingsStore: MemoryTranslationSettingsStore(
        value: AppTranslationSettings.defaults().toJson(),
      ),
      credentialStore: MemoryTranslationCredentialStore(),
      cache: cache,
      providerFactory: _ControlledFactory(provider),
      currentContentHash: (_) => currentHash,
      isCurrentContent: (_, hash) => hash == currentHash,
    );
    final session = await repository.start(
      request: SourceDocument(
        slotKey: 'alpha',
        contentHash: 'first',
        documentIdentifier: 'SKILL.md',
        content: '# Alpha',
      ),
      profile: (await repository.loadSettings()).activeProfile,
    );
    provider.job!._result.complete(
      CompletedTranslation(
        slotKey: 'alpha',
        contentHash: 'first',
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: '# Old',
        provenance: TranslationProvenance(providerIdentifier: 'controlled'),
      ),
    );

    expect(await session.result, isA<TranslationJobCancellation>());
    expect(cache.values, isEmpty);
    expect(cache.evictedGenerations, [('alpha', 'second')]);
  });

  test(
    'requires saved settings before creating a translation provider',
    () async {
      final store = MemoryTranslationSettingsStore();
      final provider = _ControlledProvider();
      final repository = fakeAppTranslationRepository(
        settingsStore: store,
        providerFactory: _ControlledFactory(provider),
      );
      final request = SourceDocument(
        slotKey: 'alpha',
        contentHash: 'hash',
        documentIdentifier: 'SKILL.md',
        content: '# Alpha',
      );
      final settings = await repository.loadSettings();
      expect(settings.isConfigured, isFalse);
      await expectLater(
        repository.start(request: request, profile: settings.activeProfile),
        throwsA(
          isA<AppTranslationConfigurationException>().having(
            (error) => error.code,
            'code',
            'provider_not_configured',
          ),
        ),
      );
      expect(provider.job, isNull);

      // Explicitly saved compatible endpoints can operate without an API key.
      final saved = await repository.saveProfile(
        settings.activeProfile.copyWith(endpoint: 'http://localhost:11434/v1'),
      );
      expect(saved.isConfigured, isTrue);
      final reloaded = await fakeAppTranslationRepository(settingsStore: store)
          .loadSettings();
      expect(reloaded.isConfigured, isTrue);
      final session = await repository.start(
        request: request,
        profile: reloaded.activeProfile,
      );
      expect(provider.job, isNotNull);
      await session.cancel();
    },
  );

  test('deletes one translation cache slot', () async {
    final cache = MemoryTranslationCache();
    final repository = fakeAppTranslationRepository(cache: cache);

    await repository.deleteSlot(slotKey: 'alpha');

    expect(cache.deletedSlotKeys, ['alpha']);
  });

  test('notifies the App after deleting slot or all cache data', () async {
    var invalidations = 0;
    final repository = AppTranslationRepository(
      settingsStore: MemoryTranslationSettingsStore(),
      credentialStore: MemoryTranslationCredentialStore(),
      cache: MemoryTranslationCache(),
      onCacheDeleted: () => invalidations++,
    );

    await repository.deleteSlot(slotKey: 'alpha');
    await repository.clearCache();

    expect(invalidations, 2);
  });

  group('AppTranslationRepository settings', () {
    test('loads legacy compatibility settings without writing them back', () {
      final legacy = AppTranslationSettings.defaults().toJson();
      final translation = legacy['translation']! as Map<String, Object?>;
      final profile = translation['activeProfile']! as Map<String, Object?>;
      profile['compatibilityMode'] = 'promptOnly';

      final decoded = AppTranslationSettings.fromJson(legacy);

      expect(decoded.activeProfile.segmentCharacterBudget, 4000);
      expect(decoded.toJson().toString(), isNot(contains('compatibilityMode')));
    });

    test('publishes only a versioned opaque credential reference', () async {
      final events = <String>[];
      final settingsStore = MemoryTranslationSettingsStore(events: events);
      final credentialStore = MemoryTranslationCredentialStore(events: events);
      final repository = fakeAppTranslationRepository(
        settingsStore: settingsStore,
        credentialStore: credentialStore,
      );

      final saved = await repository.saveProfile(
        TranslationProviderProfile.defaults(),
        replacementApiKey: 'top-secret',
      );

      final credentialId = saved.activeProfile.credentialId!;
      expect(credentialId, isNotEmpty);
      expect(credentialStore.values[credentialId], 'top-secret');
      final json = jsonEncode(settingsStore.value);
      expect(json, contains('"version":1'));
      expect(json, contains(credentialId));
      expect(json, isNot(contains('top-secret')));
      expect(events[0], 'credential.write:$credentialId');
      expect(events[1], 'settings.write');
    });

    test('clears the saved profile before deleting its credential', () async {
      final events = <String>[];
      final settingsStore = MemoryTranslationSettingsStore(events: events);
      final credentialStore = MemoryTranslationCredentialStore(events: events);
      final repository = fakeAppTranslationRepository(
        settingsStore: settingsStore,
        credentialStore: credentialStore,
      );
      final saved = await repository.saveProfile(
        TranslationProviderProfile.defaults(),
        replacementApiKey: 'top-secret',
      );
      events.clear();

      final cleared = await repository.clearProfile();

      expect(cleared.isConfigured, isFalse);
      expect(settingsStore.value, isNull);
      expect(credentialStore.values, isEmpty);
      expect(events, [
        'settings.delete',
        'credential.delete:${saved.activeProfile.credentialId}',
      ]);
    });

    test('writes new secret, publishes ref, then deletes old secret', () async {
      final events = <String>[];
      final settingsStore = MemoryTranslationSettingsStore(events: events);
      final credentialStore = MemoryTranslationCredentialStore(events: events)
        ..values['old-opaque-id'] = 'old-secret';
      final repository = AppTranslationRepository(
        settingsStore: settingsStore,
        credentialStore: credentialStore,
        cache: MemoryTranslationCache(),
        providerFactory: const _NeverProviderFactory(),
        random: Random(4),
      );

      final saved = await repository.saveProfile(
        TranslationProviderProfile.defaults().copyWith(
          credentialId: 'old-opaque-id',
        ),
        replacementApiKey: 'new-secret',
      );

      final newId = saved.activeProfile.credentialId!;
      expect(events, [
        'credential.write:$newId',
        'settings.write',
        'credential.delete:old-opaque-id',
      ]);
      expect(credentialStore.values['old-opaque-id'], isNull);
      expect(credentialStore.values[newId], 'new-secret');
    });

    test('removes new secret when settings publication fails', () async {
      final events = <String>[];
      final settingsStore = MemoryTranslationSettingsStore(events: events)
        ..writeError = StateError('publish failed');
      final credentialStore = MemoryTranslationCredentialStore(events: events)
        ..values['old-opaque-id'] = 'old-secret';
      final repository = AppTranslationRepository(
        settingsStore: settingsStore,
        credentialStore: credentialStore,
        cache: MemoryTranslationCache(),
        providerFactory: const _NeverProviderFactory(),
        random: Random(9),
      );

      await expectLater(
        repository.saveProfile(
          TranslationProviderProfile.defaults().copyWith(
            credentialId: 'old-opaque-id',
          ),
          replacementApiKey: 'new-secret',
        ),
        throwsA(isA<StateError>()),
      );

      expect(events[0], startsWith('credential.write:'));
      expect(events[1], 'settings.write');
      expect(events[2], startsWith('credential.delete:'));
      expect(credentialStore.values, {'old-opaque-id': 'old-secret'});
    });

    test('rejects overlapping credential rotations', () async {
      final settingsStore = _BlockingSettingsStore();
      final credentialStore = MemoryTranslationCredentialStore();
      final repository = AppTranslationRepository(
        settingsStore: settingsStore,
        credentialStore: credentialStore,
        cache: MemoryTranslationCache(),
        providerFactory: const _NeverProviderFactory(),
        random: Random(7),
      );

      final first = repository.saveProfile(
        TranslationProviderProfile.defaults(),
        replacementApiKey: 'first-secret',
      );
      await settingsStore.writeStarted.future;

      await expectLater(
        repository.saveProfile(
          TranslationProviderProfile.defaults(),
          replacementApiKey: 'second-secret',
        ),
        throwsA(
          isA<AppTranslationConfigurationException>().having(
            (error) => error.code,
            'code',
            'settings_save_in_progress',
          ),
        ),
      );
      settingsStore.allowWrite.complete();
      final saved = await first;

      expect(credentialStore.values, {
        saved.activeProfile.credentialId: 'first-secret',
      });
    });
  });

  group('SharedPreferencesTranslationSettingsStore', () {
    late SharedPreferencesAsyncPlatform? originalPlatform;
    late InMemorySharedPreferencesAsync platform;
    late SharedPreferencesAsync preferences;
    late SharedPreferencesTranslationSettingsStore store;

    setUpAll(() {
      originalPlatform = SharedPreferencesAsyncPlatform.instance;
    });

    setUp(() {
      platform = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = platform;
      preferences = SharedPreferencesAsync();
      store = SharedPreferencesTranslationSettingsStore(
        preferences: preferences,
      );
    });

    tearDownAll(() {
      SharedPreferencesAsyncPlatform.instance = originalPlatform;
    });

    test('returns null when no settings snapshot exists', () async {
      expect(await store.read(), isNull);
    });

    test('stores one versioned JSON snapshot and reads it back', () async {
      final settings = AppTranslationSettings.defaults().toJson();

      await store.write(settings);

      expect(await store.read(), settings);
      final stored = await preferences.getAll();
      expect(stored.keys, {
        SharedPreferencesTranslationSettingsStore.preferenceKey,
      });
      expect(
        jsonDecode(
          stored[SharedPreferencesTranslationSettingsStore.preferenceKey]!
              as String,
        ),
        settings,
      );
    });

    test('replaces the complete previous snapshot', () async {
      await store.write({'version': 1, 'generation': 1});
      await store.write({'version': 1, 'generation': 2});

      expect(await store.read(), {'version': 1, 'generation': 2});
      expect((await preferences.getAll()).length, 1);
    });

    test('deletes the saved settings snapshot', () async {
      await store.write(AppTranslationSettings.defaults().toJson());

      await store.delete();

      expect(await store.read(), isNull);
      expect(await preferences.getAll(), isEmpty);
    });

    test('rejects malformed or non-object snapshots', () async {
      await preferences.setString(
        SharedPreferencesTranslationSettingsStore.preferenceKey,
        '{not-json',
      );
      await expectLater(store.read(), throwsA(isA<FormatException>()));

      await preferences.setString(
        SharedPreferencesTranslationSettingsStore.preferenceKey,
        '[1, 2, 3]',
      );
      await expectLater(store.read(), throwsA(isA<FormatException>()));
    });
  });

  test('maps CRLF frontmatter Draft IDs onto the visible Markdown body', () async {
    const body = '# Alpha\r\n\r\nOriginal';
    const source =
        '---\r\nname: alpha\r\ndescription: Original description\r\n---\r\n$body';
    final blockId = const MarkdownSourceParser().parse(body).blocks.first.id;
    final provider = _ControlledProvider();
    final repository = AppTranslationRepository(
      settingsStore: MemoryTranslationSettingsStore(),
      credentialStore: MemoryTranslationCredentialStore(),
      cache: MemoryTranslationCache(),
      providerFactory: _ControlledFactory(provider),
    );
    await repository.saveProfile(TranslationProviderProfile.defaults());
    final session = await repository.start(
      request: SourceDocument(
        slotKey: 'alpha',
        contentHash: 'hash',
        documentIdentifier: 'SKILL.md',
        content: source,
      ),
      profile: TranslationProviderProfile.defaults(),
    );
    final draftFuture = session.drafts.first;

    provider.job!.emitDraft(
      TranslationDraft(
        translatedBlocks: {blockId: '# 阿尔法'},
        translatedDescription: '翻译描述',
        completedBlockCount: 2,
        totalBlockCount: 3,
      ),
    );
    final draft = await draftFuture;

    expect(draft.translatedBlocks, {blockId: '# 阿尔法'});
    expect(draft.translatedDescription, '翻译描述');
    await session.cancel();
  });

  group('testConnection', () {
    test('sends only a fixed sample and never caches the result', () async {
      final factory = ScriptedTranslationProviderFactory();
      final cache = MemoryTranslationCache();
      final repository = fakeAppTranslationRepository(
        cache: cache,
        providerFactory: factory,
      );

      final result = await repository.testConnection(
        profile: TranslationProviderProfile.defaults(),
        replacementApiKey: 'typed-key',
      );

      expect(result.succeeded, isTrue);
      expect(factory.apiKeys, ['typed-key']);
      expect(factory.documents.single.content, 'Hello.');
      expect(cache.values, isEmpty);
    });

    test('uses the stored credential only when asked to', () async {
      final factory = ScriptedTranslationProviderFactory();
      final credentialStore = MemoryTranslationCredentialStore();
      final repository = fakeAppTranslationRepository(
        settingsStore: MemoryTranslationSettingsStore(),
        credentialStore: credentialStore,
        providerFactory: factory,
      );
      final saved = await repository.saveProfile(
        TranslationProviderProfile.defaults(),
        replacementApiKey: 'stored-key',
      );
      final profile = saved.activeProfile;

      await repository.testConnection(
        profile: profile,
        useStoredCredential: true,
      );
      await repository.testConnection(profile: profile);

      expect(factory.apiKeys, ['stored-key', null]);
    });

    test('reports the Provider failure code', () async {
      final repository = fakeAppTranslationRepository(
        providerFactory: ScriptedTranslationProviderFactory(
          outcome: TranslationFailure(
            code: TranslationFailureCode.authenticationFailed,
            reason: 'Rejected key.',
          ),
        ),
      );

      final result = await repository.testConnection(
        profile: TranslationProviderProfile.defaults(),
        replacementApiKey: 'bad-key',
      );

      expect(result.succeeded, isFalse);
      expect(result.failureCode, 'authenticationFailed');
    });

    test('requires a key for Anthropic before contacting it', () async {
      final factory = ScriptedTranslationProviderFactory();
      final repository = fakeAppTranslationRepository(providerFactory: factory);

      final result = await repository.testConnection(
        profile: const TranslationProviderProfile(
          provider: AppTranslationProviderKind.anthropic,
          endpoint: 'https://api.anthropic.com/v1',
          model: 'claude-sonnet-4-5',
          targetLanguage: 'zh-Hans',
        ),
      );

      expect(result.failureCode, 'credential_required');
      expect(factory.documents, isEmpty);
    });

    test('cancels a test that outlives its timeout', () async {
      final factory = ScriptedTranslationProviderFactory()
        ..gate = Completer<void>();
      final repository = fakeAppTranslationRepository(providerFactory: factory);

      final result = await repository.testConnection(
        profile: TranslationProviderProfile.defaults(),
        timeout: const Duration(milliseconds: 10),
      );

      expect(result.failureCode, 'timedOut');
    });
  });
}

final class _NeverProviderFactory implements AppTranslationProviderFactory {
  const _NeverProviderFactory();

  @override
  create({required profile, required apiKey}) => throw StateError('not used');
}

final class _BlockingSettingsStore implements TranslationSettingsStore {
  final writeStarted = Completer<void>();
  final allowWrite = Completer<void>();
  Map<String, Object?>? value;

  @override
  Future<Map<String, Object?>?> read() async => value;

  @override
  Future<void> write(Map<String, Object?> value) async {
    writeStarted.complete();
    await allowWrite.future;
    this.value = value;
  }

  @override
  Future<void> delete() async => value = null;
}

final class _ControlledFactory implements AppTranslationProviderFactory {
  const _ControlledFactory(this.provider);

  final _ControlledProvider provider;

  @override
  TranslationProvider create({required profile, required apiKey}) => provider;
}

final class _ControlledProvider implements TranslationProvider {
  _ControlledJob? job;

  @override
  TranslationJob start({
    required SourceDocument sourceDocument,
    required TargetLanguage targetLanguage,
    TranslationScope scope = TranslationScope.fullDocument,
  }) => job = _ControlledJob();
}

final class _ControlledJob implements TranslationJob {
  final _drafts = StreamController<TranslationDraft>.broadcast(sync: true);
  final _result = Completer<TranslationJobOutcome>();

  @override
  Stream<TranslationDraft> get drafts => _drafts.stream;

  @override
  Future<TranslationJobOutcome> get result => _result.future;

  void emitDraft(TranslationDraft draft) => _drafts.add(draft);

  @override
  Future<void> cancel() async {
    if (!_drafts.isClosed) await _drafts.close();
    if (!_result.isCompleted) {
      _result.complete(const TranslationJobCancellation());
    }
  }
}
