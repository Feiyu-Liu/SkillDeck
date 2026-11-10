import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';

final class SkillSourceInputModeStore {
  SkillSourceInputModeStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  static const preferenceKey = 'agent_skills.acquisition_input_mode';
  static const defaultMode = SkillSourceInputMode.smart;

  SharedPreferencesAsync? _preferences;

  // Resolved on first use so a host without a preferences platform (widget
  // tests, a broken plugin) fails inside the callers' try/catch instead of
  // while the provider is being built.
  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  Future<SkillSourceInputMode> read() async {
    try {
      final value = await _store.getString(preferenceKey);
      return SkillSourceInputMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => defaultMode,
      );
    } on Object {
      // Input mode is a presentation preference. A storage failure should not
      // prevent acquisition or show an operation error.
      return defaultMode;
    }
  }

  Future<void> write(SkillSourceInputMode mode) =>
      _store.setString(preferenceKey, mode.name);
}

final skillSourceInputModeStoreProvider = Provider<SkillSourceInputModeStore>(
  (ref) => SkillSourceInputModeStore(),
);

/// The stored mode, read before the first frame.
final initialSkillSourceInputModeProvider = Provider<SkillSourceInputMode>(
  (ref) => SkillSourceInputModeStore.defaultMode,
);

/// The input mode shared by acquisition dialogs.
final skillSourceInputModeProvider =
    NotifierProvider<SkillSourceInputModeController, SkillSourceInputMode>(
      SkillSourceInputModeController.new,
    );

final class SkillSourceInputModeController
    extends Notifier<SkillSourceInputMode> {
  Future<void> _pendingWrite = Future<void>.value();

  @override
  SkillSourceInputMode build() => ref.read(initialSkillSourceInputModeProvider);

  void select(SkillSourceInputMode mode) {
    state = mode;
    final store = ref.read(skillSourceInputModeStoreProvider);
    // Serialize rapid selections so the last choice is also the last write.
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await store.write(mode);
      } on Object {
        // The in-memory choice remains authoritative for the current session.
      }
    });
    unawaited(_pendingWrite);
  }
}
