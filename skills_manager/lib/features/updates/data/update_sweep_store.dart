import 'package:shared_preferences/shared_preferences.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';

/// Compatibility abstraction for the last full update sweep timestamp.
///
/// Production now stores the timestamp and per-Skill reports in the Workspace
/// update cache. The preference-backed implementation remains for tests and
/// one-time migration of installations created before that cache existed.
abstract interface class UpdateSweepStore {
  Future<DateTime?> readLastSweepAt();

  Future<void> writeLastSweepAt(DateTime value);
}

final class RepositoryUpdateSweepStore implements UpdateSweepStore {
  RepositoryUpdateSweepStore(this._store, {SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SkillsUpdateCheckStore _store;
  final SharedPreferencesAsync _preferences;
  var _legacyMigrationAttempted = false;

  @override
  Future<DateTime?> readLastSweepAt() async {
    final current = (await _store.readUpdateCache()).lastFullSweepAt;
    if (current != null || _legacyMigrationAttempted) return current;
    _legacyMigrationAttempted = true;

    final raw = await _preferences.getString(
      SharedPreferencesUpdateSweepStore.preferenceKey,
    );
    final legacy = raw == null ? null : DateTime.tryParse(raw)?.toUtc();
    if (legacy == null) return null;
    await _store.writeLastFullUpdateSweepAt(legacy);
    await _preferences.remove(SharedPreferencesUpdateSweepStore.preferenceKey);
    return legacy;
  }

  @override
  Future<void> writeLastSweepAt(DateTime value) =>
      _store.writeLastFullUpdateSweepAt(value);
}

final class SharedPreferencesUpdateSweepStore implements UpdateSweepStore {
  SharedPreferencesUpdateSweepStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'agent_skills.updates.last_full_sweep_at';

  final SharedPreferencesAsync _preferences;

  @override
  Future<DateTime?> readLastSweepAt() async {
    final contents = await _preferences.getString(preferenceKey);
    if (contents == null) return null;
    return DateTime.tryParse(contents)?.toUtc();
  }

  @override
  Future<void> writeLastSweepAt(DateTime value) =>
      _preferences.setString(preferenceKey, value.toUtc().toIso8601String());
}

/// An in-memory store for tests and for hosts without shared preferences.
final class InMemoryUpdateSweepStore implements UpdateSweepStore {
  InMemoryUpdateSweepStore([this._value]);

  DateTime? _value;

  @override
  Future<DateTime?> readLastSweepAt() async => _value;

  @override
  Future<void> writeLastSweepAt(DateTime value) async => _value = value.toUtc();
}
