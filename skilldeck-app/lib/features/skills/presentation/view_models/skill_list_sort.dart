import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';

enum SkillListPage { installed, favorites }

enum SkillListSortMode {
  nameAscending,
  nameDescending,
  recentlyAdded,
  oldestAdded,
}

extension SkillListSortModeStorage on SkillListSortMode {
  String get storageValue => name;

  static SkillListSortMode? fromStorage(String? value) {
    if (value == null) return null;
    for (final mode in SkillListSortMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return null;
  }
}

final skillListSortProvider =
    NotifierProvider<
      SkillListSortController,
      Map<SkillListPage, SkillListSortMode>
    >(SkillListSortController.new);

final class SkillListSortController
    extends Notifier<Map<SkillListPage, SkillListSortMode>> {
  static const _preferenceKeyPrefix = 'agent_skills.skill_list_sort.';

  SharedPreferencesAsync? _preferences;
  final Set<SkillListPage> _locallySelected = <SkillListPage>{};

  @override
  Map<SkillListPage, SkillListSortMode> build() {
    for (final page in SkillListPage.values) {
      unawaited(_restore(page));
    }
    return const {
      SkillListPage.installed: SkillListSortMode.nameAscending,
      SkillListPage.favorites: SkillListSortMode.nameAscending,
    };
  }

  SkillListSortMode forPage(SkillListPage page) =>
      state[page] ?? SkillListSortMode.nameAscending;

  void select(SkillListPage page, SkillListSortMode mode) {
    _locallySelected.add(page);
    state = {...state, page: mode};
    unawaited(_persist(page, mode));
  }

  Future<void> _restore(SkillListPage page) async {
    try {
      final value = await (_preferences ??= SharedPreferencesAsync()).getString(
        _keyFor(page),
      );
      if (!ref.mounted || _locallySelected.contains(page)) return;
      final mode = SkillListSortModeStorage.fromStorage(value);
      if (mode == null) return;
      state = {...state, page: mode};
    } on Object {
      // Sorting is a presentation preference. A storage failure should not
      // prevent the catalog from rendering or show an operation error.
    }
  }

  Future<void> _persist(SkillListPage page, SkillListSortMode mode) async {
    try {
      await (_preferences ??= SharedPreferencesAsync()).setString(
        _keyFor(page),
        mode.storageValue,
      );
    } on Object {
      // The in-memory choice remains authoritative for the current session.
    }
  }

  String _keyFor(SkillListPage page) => '$_preferenceKeyPrefix${page.name}';
}

int compareInstalledSkills(
  InstalledSkill left,
  InstalledSkill right,
  SkillListSortMode mode,
) {
  switch (mode) {
    case SkillListSortMode.nameAscending:
      return _compareByName(left, right);
    case SkillListSortMode.nameDescending:
      return _compareByName(right, left);
    case SkillListSortMode.recentlyAdded:
      return _compareByAddedAt(left, right, descending: true);
    case SkillListSortMode.oldestAdded:
      return _compareByAddedAt(left, right, descending: false);
  }
}

int _compareByName(InstalledSkill left, InstalledSkill right) {
  final byName = left.displayName.toLowerCase().compareTo(
    right.displayName.toLowerCase(),
  );
  return byName == 0 ? left.slotKey.compareTo(right.slotKey) : byName;
}

int _compareByAddedAt(
  InstalledSkill left,
  InstalledSkill right, {
  required bool descending,
}) {
  final leftAt = left.currentRevision?.acquiredAt;
  final rightAt = right.currentRevision?.acquiredAt;
  if (leftAt == null && rightAt != null) return 1;
  if (leftAt != null && rightAt == null) return -1;
  if (leftAt != null && rightAt != null) {
    final byDate = leftAt.compareTo(rightAt);
    if (byDate != 0) return descending ? -byDate : byDate;
  }
  return _compareByName(left, right);
}
