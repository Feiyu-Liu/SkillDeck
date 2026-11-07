import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';

abstract interface class AppSettingsStore {
  Future<AppSettings?> read();
  Future<void> write(AppSettings settings);
  Future<AppSettingsStoreSnapshot> captureSnapshot();
  Future<void> restore(AppSettingsStoreSnapshot snapshot);
}

/// Exact durable state of the Settings preference key.
///
/// A missing key is different from serializing default settings, so rollback
/// restores the raw preference snapshot rather than a decoded model.
final class AppSettingsStoreSnapshot {
  const AppSettingsStoreSnapshot.missing() : rawValue = null;

  const AppSettingsStoreSnapshot.withValue(this.rawValue)
    : assert(rawValue != null);

  final String? rawValue;

  bool get isMissing => rawValue == null;
}

final class SharedPreferencesAppSettingsStore implements AppSettingsStore {
  SharedPreferencesAppSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'agent_skills.app.settings';
  final SharedPreferencesAsync _preferences;

  @override
  Future<AppSettings?> read() async {
    final raw = await _preferences.getString(preferenceKey);
    if (raw == null) return null;
    return AppSettings.decode(raw);
  }

  @override
  Future<void> write(AppSettings settings) =>
      _preferences.setString(preferenceKey, jsonEncode(settings.toJson()));

  @override
  Future<AppSettingsStoreSnapshot> captureSnapshot() async {
    final raw = await _preferences.getString(preferenceKey);
    return raw == null
        ? const AppSettingsStoreSnapshot.missing()
        : AppSettingsStoreSnapshot.withValue(raw);
  }

  @override
  Future<void> restore(AppSettingsStoreSnapshot snapshot) => snapshot.isMissing
      ? _preferences.remove(preferenceKey)
      : _preferences.setString(preferenceKey, snapshot.rawValue!);
}
