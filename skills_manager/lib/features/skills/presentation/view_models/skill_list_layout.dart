import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the Installed and Favorites pages lay out their Skills.
enum SkillListLayout { list, cards }

final class SkillListLayoutStore {
  SkillListLayoutStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'agent_skills.skill_list_layout';
  static const defaultLayout = SkillListLayout.cards;

  final SharedPreferencesAsync _preferences;

  Future<SkillListLayout> read() async {
    try {
      final value = await _preferences.getString(preferenceKey);
      return SkillListLayout.values.firstWhere(
        (layout) => layout.name == value,
        orElse: () => defaultLayout,
      );
    } on Object {
      // Layout is a presentation preference. A storage failure should not
      // prevent the catalog from rendering or show an operation error.
      return defaultLayout;
    }
  }

  Future<void> write(SkillListLayout layout) =>
      _preferences.setString(preferenceKey, layout.name);
}

final skillListLayoutStoreProvider = Provider<SkillListLayoutStore>(
  (ref) => SkillListLayoutStore(),
);

/// The stored layout, read before the first frame so a restored choice never
/// flashes the default first.
final initialSkillListLayoutProvider = Provider<SkillListLayout>(
  (ref) => SkillListLayoutStore.defaultLayout,
);

/// One layout preference, chosen in Appearance settings and shared by the
/// Installed and Favorites pages.
final skillListLayoutProvider =
    NotifierProvider<SkillListLayoutController, SkillListLayout>(
      SkillListLayoutController.new,
    );

final class SkillListLayoutController extends Notifier<SkillListLayout> {
  Future<void> _pendingWrite = Future<void>.value();

  @override
  SkillListLayout build() => ref.read(initialSkillListLayoutProvider);

  void select(SkillListLayout layout) {
    state = layout;
    final store = ref.read(skillListLayoutStoreProvider);
    // Serialize rapid selections so the last choice is also the last write.
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await store.write(layout);
      } on Object {
        // The in-memory choice remains authoritative for the current session.
      }
    });
    unawaited(_pendingWrite);
  }
}
