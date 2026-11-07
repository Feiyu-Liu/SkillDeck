import 'package:shared_preferences/shared_preferences.dart';

/// The App version that last launched, so each version's news shows once.
final class WhatsNewStore {
  WhatsNewStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'agent_skills.app.last_seen_version';

  final SharedPreferencesAsync _preferences;

  Future<String?> readLastSeenVersion() async {
    try {
      return await _preferences.getString(preferenceKey);
    } on Object {
      return null;
    }
  }

  Future<void> writeLastSeenVersion(String version) async {
    try {
      await _preferences.setString(preferenceKey, version);
    } on Object {
      // Optional: at worst the news shows again on the next launch.
    }
  }
}
