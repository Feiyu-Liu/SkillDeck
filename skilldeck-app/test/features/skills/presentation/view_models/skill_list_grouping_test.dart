import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_grouping.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_sort.dart';

void main() {
  final originalPlatform = SharedPreferencesAsyncPlatform.instance;
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = originalPlatform);

  test(
    'preloads independent page choices and invalid values default to none',
    () async {
      final preferences = SharedPreferencesAsync();
      final store = SkillListGroupingStore(preferences: preferences);
      await preferences.setString(
        SkillListGroupingStore.keyFor(SkillListPage.installed),
        'repository',
      );
      await preferences.setString(
        SkillListGroupingStore.keyFor(SkillListPage.favorites),
        'future-value',
      );
      final initial = await store.read();
      final container = ProviderContainer(
        overrides: [
          initialSkillListGroupingProvider.overrideWithValue(initial),
          skillListGroupingStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(skillListGroupingProvider), {
        SkillListPage.installed: SkillListGroupingMode.repository,
        SkillListPage.favorites: SkillListGroupingMode.none,
      });
      container
          .read(skillListGroupingProvider.notifier)
          .select(SkillListPage.favorites, SkillListGroupingMode.repository);
      await pumpEventQueue();
      expect(
        (await store.read()).values,
        everyElement(SkillListGroupingMode.repository),
      );
    },
  );
  test('storage failures fall back and retain in-memory choice', () async {
    final store = SkillListGroupingStore(preferences: _FailingPreferences());
    expect(
      (await store.read()).values,
      everyElement(SkillListGroupingMode.none),
    );
    final container = ProviderContainer(
      overrides: [skillListGroupingStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container
        .read(skillListGroupingProvider.notifier)
        .select(SkillListPage.installed, SkillListGroupingMode.repository);
    await pumpEventQueue();
    expect(
      container.read(skillListGroupingProvider)[SkillListPage.installed],
      SkillListGroupingMode.repository,
    );
  });
  test(
    'rapid selections serialize writes so the final selection wins',
    () async {
      final preferences = _DelayedPreferences();
      final container = ProviderContainer(
        overrides: [
          skillListGroupingStoreProvider.overrideWithValue(
            SkillListGroupingStore(preferences: preferences),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(skillListGroupingProvider.notifier);
      controller.select(
        SkillListPage.installed,
        SkillListGroupingMode.repository,
      );
      controller.select(SkillListPage.installed, SkillListGroupingMode.none);
      controller.select(
        SkillListPage.installed,
        SkillListGroupingMode.repository,
      );
      await pumpEventQueue();
      expect(preferences.pending, hasLength(1));
      for (var i = 0; i < 3; i++) {
        preferences.pending[i].complete();
        await pumpEventQueue();
      }
      expect(preferences.values, ['repository', 'none', 'repository']);
    },
  );
  test('folds are independent per page and search restores browsing folds', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(skillListGroupFoldsProvider.notifier);
    controller.toggle(SkillListPage.installed, 'repo', searching: false);
    controller.searchChanged();
    expect(
      container
          .read(skillListGroupFoldsProvider)[SkillListPage.installed]!
          .searching,
      isEmpty,
    );
    controller.toggle(SkillListPage.installed, 'repo', searching: true);
    controller.toggle(SkillListPage.favorites, 'other', searching: false);
    expect(
      container
          .read(skillListGroupFoldsProvider)[SkillListPage.installed]!
          .searching,
      {'repo'},
    );
    controller.searchChanged();
    final folds = container.read(skillListGroupFoldsProvider);
    expect(folds[SkillListPage.installed]!.browsing, {'repo'});
    expect(folds[SkillListPage.installed]!.searching, isEmpty);
    expect(folds[SkillListPage.favorites]!.browsing, {'other'});
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    expect(restarted.read(skillListGroupFoldsProvider), isEmpty);
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

final class _DelayedPreferences extends SharedPreferencesAsync {
  final pending = <Completer<void>>[];
  final values = <String>[];
  @override
  Future<void> setString(String key, String value) async {
    final done = Completer<void>();
    pending.add(done);
    await done.future;
    values.add(value);
  }
}
