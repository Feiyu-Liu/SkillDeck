import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class TranslationSettingsStore {
  Future<Map<String, Object?>?> read();

  Future<void> write(Map<String, Object?> value);

  Future<void> delete();
}

final class SharedPreferencesTranslationSettingsStore
    implements TranslationSettingsStore {
  SharedPreferencesTranslationSettingsStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'agent_skills.translation.settings';

  final SharedPreferencesAsync _preferences;

  @override
  Future<Map<String, Object?>?> read() async {
    final contents = await _preferences.getString(preferenceKey);
    if (contents == null) return null;
    final decoded = jsonDecode(contents);
    if (decoded is! Map) {
      throw const FormatException(
        'The persisted translation settings must contain an object.',
      );
    }
    return Map<String, Object?>.from(decoded);
  }

  @override
  Future<void> write(Map<String, Object?> value) =>
      _preferences.setString(preferenceKey, jsonEncode(value));

  @override
  Future<void> delete() => _preferences.remove(preferenceKey);
}
