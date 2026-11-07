import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The outcome of the most recent Skills validation, kept so Maintenance can
/// say when the Workspace was last checked and what that check found.
final class WorkspaceValidationRecord {
  const WorkspaceValidationRecord({
    required this.completedAt,
    required this.failed,
    this.checkedSkillCount = 0,
    this.repairedArtifactCount = 0,
    this.driftedSkillCount = 0,
    this.failedSkillCount = 0,
  });

  final DateTime completedAt;

  /// Whether the validation itself failed rather than reporting results.
  final bool failed;
  final int checkedSkillCount;
  final int repairedArtifactCount;
  final int driftedSkillCount;
  final int failedSkillCount;

  Map<String, Object?> toJson() => {
    'completedAt': completedAt.toUtc().toIso8601String(),
    'failed': failed,
    'checked': checkedSkillCount,
    'repaired': repairedArtifactCount,
    'drifted': driftedSkillCount,
    'failedSkills': failedSkillCount,
  };

  static WorkspaceValidationRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final completedAt = DateTime.tryParse('${value['completedAt']}');
    final failed = value['failed'];
    if (completedAt == null || failed is! bool) return null;
    int count(String key) => switch (value[key]) {
      final int count when count >= 0 => count,
      _ => 0,
    };
    return WorkspaceValidationRecord(
      completedAt: completedAt.toUtc(),
      failed: failed,
      checkedSkillCount: count('checked'),
      repairedArtifactCount: count('repaired'),
      driftedSkillCount: count('drifted'),
      failedSkillCount: count('failedSkills'),
    );
  }
}

abstract interface class WorkspaceValidationHistoryStore {
  Future<WorkspaceValidationRecord?> readLast();

  Future<void> writeLast(WorkspaceValidationRecord record);
}

final class SharedPreferencesWorkspaceValidationHistoryStore
    implements WorkspaceValidationHistoryStore {
  SharedPreferencesWorkspaceValidationHistoryStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'agent_skills.settings.last_validation';

  final SharedPreferencesAsync _preferences;

  @override
  Future<WorkspaceValidationRecord?> readLast() async {
    final contents = await _preferences.getString(preferenceKey);
    if (contents == null) return null;
    try {
      return WorkspaceValidationRecord.fromJson(jsonDecode(contents));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeLast(WorkspaceValidationRecord record) =>
      _preferences.setString(preferenceKey, jsonEncode(record.toJson()));
}

final class InMemoryWorkspaceValidationHistoryStore
    implements WorkspaceValidationHistoryStore {
  InMemoryWorkspaceValidationHistoryStore([this._value]);

  WorkspaceValidationRecord? _value;

  @override
  Future<WorkspaceValidationRecord?> readLast() async => _value;

  @override
  Future<void> writeLast(WorkspaceValidationRecord record) async =>
      _value = record;
}
