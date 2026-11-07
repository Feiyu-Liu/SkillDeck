import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'skill_json.dart';
import 'skill_selector_resolver.dart';

typedef SkillsLockEntry = ({
  String sourceUrl,
  String skillPath,
  String sourceType,
});

abstract interface class SkillsLockReader {
  Future<Map<String, SkillsLockEntry>> read();
}

/// Reads hints only. Neither the lock nor its diagnostics enter Workspace state.
final class FileSkillsLockReader implements SkillsLockReader {
  FileSkillsLockReader({required String homePath, int maxBytes = 4 << 20})
    : _file = File(p.join(homePath, '.agents', '.skill-lock.json')),
      _maxBytes = maxBytes;

  final File _file;
  final int _maxBytes;

  @override
  Future<Map<String, SkillsLockEntry>> read() async {
    try {
      if (await FileSystemEntity.type(_file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException();
      }
      final stat = await _file.stat();
      if (stat.size > _maxBytes) throw const FormatException();
      final content = await _file.readAsString();
      if (utf8.encode(content).length > _maxBytes) {
        throw const FormatException();
      }
      final json = jsonDecode(content) as Map<String, Object?>;
      if (json['version'] is! int || json['version'] != 3) {
        throw const FormatException();
      }
      final skills = json['skills'] as Map<String, Object?>;
      return {
        for (final entry in skills.entries)
          entry.key: _entry(entry.value as Map<String, Object?>),
      };
    } on Object {
      throw const SkillSelectionFailure('lockUnavailable');
    }
  }

  SkillsLockEntry _entry(Map<String, Object?> entry) => (
    sourceUrl: stripLocatorUserinfo(entry['sourceUrl'] as String),
    skillPath: entry['skillPath'] as String,
    sourceType: entry['sourceType'] as String,
  );
}
