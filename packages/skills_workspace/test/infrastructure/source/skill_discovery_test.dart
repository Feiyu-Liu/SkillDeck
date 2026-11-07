// Portions derived from vercel-labs/skills (MIT), Copyright (c) 2026 Vercel, Inc. See THIRD_PARTY_NOTICES.md.
import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:skills_workspace/src/infrastructure/source/skill_discovery.dart';
import 'package:skills_workspace/src/infrastructure/source/frontmatter_parser.dart';
import 'package:skills_workspace/src/infrastructure/source/source_models.dart';
import 'package:skills_workspace/src/infrastructure/source/source_result.dart';
import 'package:test/test.dart';

void main() {
  final invalidCases = <String, String>{
    'not yaml': 'invalidFrontmatter',
    '---\nname: [unclosed\n---\n': 'invalidFrontmatter',
    '---\nname: demo\ndescription: never closed': 'invalidFrontmatter',
    '---\ndescription: demo\n---\n': 'missingName',
    '---\nname: 42\ndescription: demo\n---\n': 'missingName',
    '---\nname: demo\n---\n': 'missingDescription',
    '---\nname: demo\ndescription: [list]\n---\n': 'missingDescription',
    '---\nname: 代码审查\ndescription: demo\n---\n': 'unsupportedSkillName',
    '---\nname: con\ndescription: demo\n---\n': 'windowsReservedDeviceName',
  };
  for (final entry in invalidCases.entries) {
    test('reports discarded metadata ${entry.key}', () async {
      final root = await Directory.systemTemp.createTemp('discovery-drop-');
      addTearDown(() => root.delete(recursive: true));
      for (final name in ['z-last', 'a-first']) {
        final file = File(paths.join(root.path, name, 'SKILL.md'));
        await file.parent.create();
        await file.writeAsString(entry.key);
      }
      final result = await const SkillDiscovery().inspect(root.path);
      expect(result.failureOrNull?.code, SourceFailureCode.contentInvalid);
      expect(result.failureOrNull?.context, {
        'reason': entry.value,
        'path': 'a-first/SKILL.md',
        'droppedCount': 2,
      });
    });
  }
  test(
    'returns valid candidates alongside discarded metadata and ignores lowercase skill.md',
    () async {
      final root = await Directory.systemTemp.createTemp('discovery-mixed-');
      addTearDown(() => root.delete(recursive: true));
      await _writeSkill(paths.join(root.path, 'valid'), 'valid');
      final bad = File(paths.join(root.path, 'bad', 'SKILL.md'));
      await bad.parent.create();
      await bad.writeAsString('invalid');
      final lower = File(paths.join(root.path, 'lower', 'skill.md'));
      await lower.parent.create();
      await lower.writeAsString('---\nname: lower\ndescription: lower\n---\n');
      final result = await const SkillDiscovery().inspect(root.path);
      expect(result.valueOrNull!.candidates.map((c) => c.declaredName), [
        'valid',
      ]);
    },
  );
  test('accepts an unquoted colon in a plain description', () {
    final frontmatter = parseSkillFrontmatter('''
---
name: macos-signed-release
description: macOS signed release: build and sign
---
''');

    expect(frontmatter?.declaredName, 'macos-signed-release');
    expect(frontmatter?.description, 'macOS signed release: build and sign');
  });

  test('keeps required metadata validation strict', () {
    expect(
      parseSkillFrontmatter('''
---
name: valid
---
'''),
      isNull,
    );
    expect(
      parseSkillFrontmatter('''
---
name:
  nested: value
description: valid
---
'''),
      isNull,
    );
  });

  test('preserves quoted and block descriptions', () {
    final quoted = parseSkillFrontmatter('''
---
name: quoted
description: "a: quoted value"
---
''');
    final block = parseSkillFrontmatter('''
---
name: block
description: >-
  first line: value
  second line
---
''');

    expect(quoted?.description, 'a: quoted value');
    expect(block?.description, 'first line: value second line');
  });

  test('discovers priority and nested Skill roots deterministically', () async {
    final root = await Directory.systemTemp.createTemp('workspace-discovery-');
    addTearDown(() => root.delete(recursive: true));
    await _writeSkill(paths.join(root.path, 'skills', 'bravo'), 'bravo');
    await _writeSkill(
      paths.join(root.path, '.agents', 'skills', 'alpha'),
      'alpha',
    );

    final result = await const SkillDiscovery().inspect(root.path);

    expect(
      result.valueOrNull?.candidates.map((candidate) => candidate.declaredName),
      <String>['alpha', 'bravo'],
    );
  });

  test('filters internal Skills unless explicitly requested', () async {
    final root = await Directory.systemTemp.createTemp('workspace-discovery-');
    addTearDown(() => root.delete(recursive: true));
    await _writeSkill(
      paths.join(root.path, 'skills', 'internal'),
      'internal',
      internal: true,
    );

    final hidden = await const SkillDiscovery().inspect(root.path);
    final visible = await const SkillDiscovery().inspect(
      root.path,
      options: const SkillDiscoveryOptions(includeInternal: true),
    );

    expect(hidden.valueOrNull?.candidates, isEmpty);
    expect(visible.valueOrNull?.candidates, hasLength(1));
  });

  test('finds Skills a root-sourced marketplace plugin declares', () async {
    // Mirrors github.com/better-auth/skills: one Skill directly under the
    // root, five under a plugin folder the marketplace reaches with `./`.
    final root = await Directory.systemTemp.createTemp('discovery-plugin-');
    addTearDown(() => root.delete(recursive: true));
    Future<void> skill(String relative, String name) async {
      final file = File(paths.join(root.path, relative, 'SKILL.md'));
      await file.parent.create(recursive: true);
      await file.writeAsString('---\nname: $name\ndescription: demo\n---\n');
    }

    await skill('security', 'security-best-practices');
    for (final name in [
      'best-practices',
      'create-auth',
      'email-and-password',
      'organization',
      'two-factor',
    ]) {
      await skill(paths.join('better-auth', name), name);
    }
    final manifest = File(
      paths.join(root.path, '.claude-plugin', 'marketplace.json'),
    );
    await manifest.parent.create();
    await manifest.writeAsString(
      '{"plugins":[{"name":"auth-skills","source":"./",'
      '"skills":["./better-auth/create-auth","./better-auth/best-practices"]}]}',
    );

    final result = await const SkillDiscovery().inspect(root.path);
    final candidates = result.valueOrNull!.candidates;

    expect(candidates.map((candidate) => candidate.sourceRelativePath), [
      'better-auth/best-practices',
      'better-auth/create-auth',
      'better-auth/email-and-password',
      'better-auth/organization',
      'better-auth/two-factor',
      'security',
    ]);
    expect({
      for (final candidate in candidates)
        candidate.sourceRelativePath: candidate.pluginName,
    }, containsPair('better-auth/create-auth', 'auth-skills'));
  });

  test('rejects a traversal subpath', () async {
    final root = await Directory.systemTemp.createTemp('workspace-discovery-');
    addTearDown(() => root.delete(recursive: true));

    final result = await const SkillDiscovery().inspect(
      root.path,
      subpath: '../outside',
    );

    expect(result.failureOrNull?.code, SourceFailureCode.rejected);
  });
}

Future<void> _writeSkill(
  String directory,
  String name, {
  bool internal = false,
}) async {
  await Directory(directory).create(recursive: true);
  await File(paths.join(directory, 'SKILL.md')).writeAsString('''
---
name: $name
description: $name description
${internal ? 'metadata:\n  internal: true' : ''}
---
# $name
''');
}
