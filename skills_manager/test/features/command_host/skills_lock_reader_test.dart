import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/features/command_host/data/skill_selector_resolver.dart';
import 'package:skills_manager/features/command_host/data/skills_lock_reader.dart';

void main() {
  late Directory home;
  late File file;
  late FileSkillsLockReader reader;
  final unavailable = throwsA(
    isA<SkillSelectionFailure>()
        .having((e) => e.code, 'code', 'lockUnavailable')
        .having((e) => e.details, 'details', isEmpty),
  );

  setUp(() async {
    home = await Directory.systemTemp.createTemp('skilldeck-lock-test-');
    file = File(p.join(home.path, '.agents', '.skill-lock.json'));
    await file.parent.create();
    reader = FileSkillsLockReader(homePath: home.path);
  });
  tearDown(() => home.delete(recursive: true));

  Map<String, Object?> valid() => {
    'version': 3,
    'skills': {
      'alpha': {
        'sourceUrl': 'https://user:secret@github.com/org/repo',
        'skillPath': 'skills/alpha/SKILL.md',
        'sourceType': 'github',
      },
      'beta': {
        'sourceUrl': 'https://example.test/beta',
        'skillPath': 'SKILL.md',
        'sourceType': 'mintlify',
      },
    },
  };

  test(
    'v3 retains unsupported hints, strips userinfo, and never writes',
    () async {
      final content = jsonEncode(valid());
      await file.writeAsString(content);
      final lock = await reader.read();
      expect(lock['alpha'], (
        sourceUrl: 'https://github.com/org/repo',
        skillPath: 'skills/alpha/SKILL.md',
        sourceType: 'github',
      ));
      expect(lock['beta']!.sourceType, 'mintlify');
      expect(await file.readAsString(), content);
    },
  );

  test('missing file, directory, and symlink are unavailable', () async {
    await expectLater(reader.read(), unavailable);
    await Directory(file.path).create();
    await expectLater(reader.read(), unavailable);
    await Directory(file.path).delete();
    final target = File(p.join(home.path, 'target'));
    await target.writeAsString(jsonEncode(valid()));
    await Link(file.path).create(target.path);
    await expectLater(reader.read(), unavailable);
  });

  test('strict schema and malformed JSON return only a stable code', () async {
    for (final json in [
      'secret non JSON',
      '[]',
      'null',
      jsonEncode({...valid(), 'version': 2}),
      jsonEncode({...valid(), 'version': 3.0}),
      jsonEncode({'version': 3}),
      jsonEncode({'version': 3, 'skills': []}),
      jsonEncode({
        'version': 3,
        'skills': {'alpha': []},
      }),
      for (final key in ['sourceUrl', 'skillPath', 'sourceType'])
        jsonEncode({
          'version': 3,
          'skills': {
            'alpha': {
              'sourceUrl': 'org/repo',
              'skillPath': 'SKILL.md',
              'sourceType': 'github',
            }..remove(key),
          },
        }),
      jsonEncode({
        'version': 3,
        'skills': {
          'alpha': {
            'sourceUrl': 1,
            'skillPath': 'SKILL.md',
            'sourceType': 'github',
          },
        },
      }),
    ]) {
      await file.writeAsString(json);
      await expectLater(reader.read(), unavailable);
    }
  });

  test('default 4 MiB bound rejects before parsing', () async {
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate((4 << 20) + 1);
    await handle.close();
    await expectLater(reader.read(), unavailable);
  });

  test('byte limit accepts exact bound and rejects one byte below', () async {
    final content = jsonEncode(valid());
    await file.writeAsString(content);
    final bytes = utf8.encode(content).length;
    expect(
      await FileSkillsLockReader(homePath: home.path, maxBytes: bytes).read(),
      hasLength(2),
    );
    await expectLater(
      FileSkillsLockReader(homePath: home.path, maxBytes: bytes - 1).read(),
      unavailable,
    );
  });
}
