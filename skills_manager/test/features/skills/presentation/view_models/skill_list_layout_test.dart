import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';

void main() {
  late SharedPreferencesAsyncPlatform? originalPlatform;
  late SharedPreferencesAsync preferences;
  late SkillListLayoutStore store;

  setUpAll(() {
    originalPlatform = SharedPreferencesAsyncPlatform.instance;
  });
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    store = SkillListLayoutStore(preferences: preferences);
  });
  tearDownAll(() {
    SharedPreferencesAsyncPlatform.instance = originalPlatform;
  });

  test('defaults to cards and persists the selected layout', () async {
    expect(await store.read(), SkillListLayout.cards);

    await store.write(SkillListLayout.list);

    expect(await store.read(), SkillListLayout.list);
  });

  test('invalid saved layout falls back to cards', () async {
    await preferences.setString(SkillListLayoutStore.preferenceKey, 'unknown');

    expect(await store.read(), SkillListLayout.cards);
  });

  test('starts from the preloaded layout and saves new choices', () async {
    final container = ProviderContainer(
      overrides: [
        skillListLayoutStoreProvider.overrideWithValue(store),
        initialSkillListLayoutProvider.overrideWithValue(SkillListLayout.list),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(skillListLayoutProvider), SkillListLayout.list);

    container
        .read(skillListLayoutProvider.notifier)
        .select(SkillListLayout.cards);
    await pumpEventQueue();

    expect(container.read(skillListLayoutProvider), SkillListLayout.cards);
    expect(await store.read(), SkillListLayout.cards);
  });

  test('storage failures keep the in-memory selection usable', () async {
    store = SkillListLayoutStore(preferences: _FailingPreferences());
    expect(await store.read(), SkillListLayout.cards);
    final container = ProviderContainer(
      overrides: [skillListLayoutStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    container
        .read(skillListLayoutProvider.notifier)
        .select(SkillListLayout.list);
    await pumpEventQueue();

    expect(container.read(skillListLayoutProvider), SkillListLayout.list);
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
