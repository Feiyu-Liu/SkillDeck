import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the App follows the system appearance or fixes light or dark.
enum AppearanceMode {
  system,
  light,
  dark;

  /// The brightness the App renders with, given the platform's own.
  Brightness resolve(Brightness platformBrightness) => switch (this) {
    AppearanceMode.system => platformBrightness,
    AppearanceMode.light => Brightness.light,
    AppearanceMode.dark => Brightness.dark,
  };
}

final class AppearanceModeStore {
  AppearanceModeStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'agent_skills.appearance_mode';
  static const defaultMode = AppearanceMode.system;

  final SharedPreferencesAsync _preferences;

  Future<AppearanceMode> read() async {
    try {
      final value = await _preferences.getString(preferenceKey);
      return AppearanceMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => defaultMode,
      );
    } on Object {
      // Appearance is a presentation preference. A storage failure should not
      // prevent the App from rendering or show an operation error.
      return defaultMode;
    }
  }

  Future<void> write(AppearanceMode mode) =>
      _preferences.setString(preferenceKey, mode.name);
}

final appearanceModeStoreProvider = Provider<AppearanceModeStore>(
  (ref) => AppearanceModeStore(),
);

/// The stored mode, read before the first frame so a fixed appearance never
/// flashes the system one first.
final initialAppearanceModeProvider = Provider<AppearanceMode>(
  (ref) => AppearanceModeStore.defaultMode,
);

/// The appearance chosen in Appearance settings.
final appearanceModeProvider =
    NotifierProvider<AppearanceModeController, AppearanceMode>(
      AppearanceModeController.new,
    );

final class AppearanceModeController extends Notifier<AppearanceMode> {
  Future<void> _pendingWrite = Future<void>.value();

  @override
  AppearanceMode build() => ref.read(initialAppearanceModeProvider);

  void select(AppearanceMode mode) {
    state = mode;
    final store = ref.read(appearanceModeStoreProvider);
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
