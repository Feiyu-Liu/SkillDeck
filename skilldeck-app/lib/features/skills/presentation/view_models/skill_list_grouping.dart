import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_sort.dart';

enum SkillListGroupingMode { none, repository }

/// Presentation preferences loaded before the first frame, independently per page.
final class SkillListGroupingStore {
  SkillListGroupingStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  static String keyFor(SkillListPage page) =>
      'agent_skills.skill_list_grouping.${page.name}';
  final SharedPreferencesAsync? _preferences;

  Future<Map<SkillListPage, SkillListGroupingMode>> read() async {
    final result = <SkillListPage, SkillListGroupingMode>{};
    for (final page in SkillListPage.values) {
      try {
        final value = await (_preferences ?? SharedPreferencesAsync())
            .getString(keyFor(page));
        result[page] = SkillListGroupingMode.values.firstWhere(
          (mode) => mode.name == value,
          orElse: () => SkillListGroupingMode.none,
        );
      } on Object {
        result[page] = SkillListGroupingMode.none;
      }
    }
    return Map.unmodifiable(result);
  }

  Future<void> write(SkillListPage page, SkillListGroupingMode mode) =>
      (_preferences ?? SharedPreferencesAsync()).setString(
        keyFor(page),
        mode.name,
      );
}

final skillListGroupingStoreProvider = Provider<SkillListGroupingStore>(
  (ref) => SkillListGroupingStore(),
);
final initialSkillListGroupingProvider =
    Provider<Map<SkillListPage, SkillListGroupingMode>>((ref) => const {});
final skillListGroupingProvider =
    NotifierProvider<
      SkillListGroupingController,
      Map<SkillListPage, SkillListGroupingMode>
    >(SkillListGroupingController.new);

final class SkillListGroupingController
    extends Notifier<Map<SkillListPage, SkillListGroupingMode>> {
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Map<SkillListPage, SkillListGroupingMode> build() =>
      ref.read(initialSkillListGroupingProvider);

  void select(SkillListPage page, SkillListGroupingMode mode) {
    state = Map.unmodifiable({...state, page: mode});
    final store = ref.read(skillListGroupingStoreProvider);
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await store.write(page, mode);
      } on Object {
        // Keep the session's selection when preference storage is unavailable.
      }
    });
    unawaited(_pendingWrite);
  }
}

/// Session-only folds. Search uses separate folds and never edits browse folds.
final class SkillListGroupFolds {
  SkillListGroupFolds({
    Set<String> browsing = const {},
    Set<String> searching = const {},
  }) : browsing = Set.unmodifiable(browsing),
       searching = Set.unmodifiable(searching);

  final Set<String> browsing;
  final Set<String> searching;
}

final skillListGroupFoldsProvider =
    NotifierProvider<
      SkillListGroupFoldsController,
      Map<SkillListPage, SkillListGroupFolds>
    >(SkillListGroupFoldsController.new);

final class SkillListGroupFoldsController
    extends Notifier<Map<SkillListPage, SkillListGroupFolds>> {
  @override
  Map<SkillListPage, SkillListGroupFolds> build() => const {};

  void toggle(SkillListPage page, String key, {required bool searching}) {
    final folds = state[page] ?? SkillListGroupFolds();
    final changed = {...(searching ? folds.searching : folds.browsing)};
    if (!changed.remove(key)) changed.add(key);
    state = {
      ...state,
      page: SkillListGroupFolds(
        browsing: searching ? folds.browsing : changed,
        searching: searching ? changed : folds.searching,
      ),
    };
  }

  /// The search query is shared between pages; reset both search fold sets.
  void searchChanged() {
    state = {
      for (final entry in state.entries)
        entry.key: SkillListGroupFolds(browsing: entry.value.browsing),
    };
  }
}
