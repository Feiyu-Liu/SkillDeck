import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:skills_manager/features/translation/presentation/view_models/translation_scope_preference.dart';
import 'package:skills_translation/skills_translation.dart';

void main() {
  late SharedPreferencesAsyncPlatform? originalPlatform;
  late SharedPreferencesAsync preferences;
  late TranslationScopePreferenceStore store;

  setUpAll(() {
    originalPlatform = SharedPreferencesAsyncPlatform.instance;
  });
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    store = TranslationScopePreferenceStore(preferences: preferences);
  });
  tearDownAll(() {
    SharedPreferencesAsyncPlatform.instance = originalPlatform;
  });

  test(
    'defaults to full and persists the selected description scope',
    () async {
      expect(await store.read(), TranslationScope.fullDocument);

      await store.write(TranslationScope.descriptionOnly);

      expect(await store.read(), TranslationScope.descriptionOnly);
    },
  );

  test('invalid saved scope falls back to full', () async {
    await preferences.setString(
      TranslationScopePreferenceStore.preferenceKey,
      'unknown',
    );

    expect(await store.read(), TranslationScope.fullDocument);
  });

  test('storage failures keep the in-memory selection usable', () async {
    store = TranslationScopePreferenceStore(preferences: _FailingPreferences());
    expect(await store.read(), TranslationScope.fullDocument);
    final container = ProviderContainer(
      overrides: [
        translationScopePreferenceStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(translationScopePreferenceProvider.notifier)
        .select(TranslationScope.descriptionOnly);
    await pumpEventQueue();

    expect(
      container.read(translationScopePreferenceProvider),
      TranslationScope.descriptionOnly,
    );
  });
}

final class _FailingPreferences extends SharedPreferencesAsync {
  @override
  Future<String?> getString(String key) async =>
      throw StateError('read failed');

  @override
  Future<void> setString(String key, String value) async =>
      throw StateError('write failed');
}
