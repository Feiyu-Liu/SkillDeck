import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:skills_workspace/src/infrastructure/source/plugin_manifest.dart';
import 'package:test/test.dart';

void main() {
  test('indexes contained plugin skill directories and groupings', () async {
    final root = await Directory.systemTemp.createTemp('workspace-manifest-');
    addTearDown(() => root.delete(recursive: true));
    final manifestDirectory = Directory(
      paths.join(root.path, '.claude-plugin'),
    );
    await manifestDirectory.create(recursive: true);
    await File(
      paths.join(manifestDirectory.path, 'plugin.json'),
    ).writeAsString('{"name":"Example Plugin","skills":["./skills/example"]}');

    final result = await readPluginManifestIndex(root.path);
    final index = result.valueOrNull!;

    expect(
      index.groupings[paths.normalize(
        paths.join(root.path, 'skills', 'example'),
      )],
      'Example Plugin',
    );
    expect(index.searchDirectories, contains(paths.join(root.path, 'skills')));
  });

  test('ignores manifest paths that escape the source', () async {
    final root = await Directory.systemTemp.createTemp('workspace-manifest-');
    addTearDown(() => root.delete(recursive: true));
    final manifestDirectory = Directory(
      paths.join(root.path, '.claude-plugin'),
    );
    await manifestDirectory.create(recursive: true);
    await File(
      paths.join(manifestDirectory.path, 'plugin.json'),
    ).writeAsString('{"name":"Plugin","skills":["./../outside"]}');

    final result = await readPluginManifestIndex(root.path);

    expect(result.valueOrNull?.groupings, isEmpty);
  });
  Future<Directory> manifestRoot(String file, String json) async {
    final root = await Directory.systemTemp.createTemp('workspace-manifest-');
    addTearDown(() => root.delete(recursive: true));
    final manifest = File(paths.join(root.path, '.claude-plugin', file));
    await manifest.parent.create(recursive: true);
    await manifest.writeAsString(json);
    return root;
  }

  test('accepts a marketplace plugin whose source is the root', () async {
    final root = await manifestRoot(
      'marketplace.json',
      '{"plugins":[{"name":"auth-skills","source":"./",'
          '"skills":["./better-auth/create-auth","./better-auth/best-practices/"]}]}',
    );

    final index = (await readPluginManifestIndex(root.path)).valueOrNull!;

    expect(index.searchDirectories, [
      paths.join(root.path, 'better-auth'),
      paths.join(root.path, 'skills'),
    ]);
    expect(
      index.groupings[paths.join(root.path, 'better-auth', 'create-auth')],
      'auth-skills',
    );
    expect(
      index.groupings[paths.join(root.path, 'better-auth', 'best-practices')],
      'auth-skills',
    );
  });

  test('never searches above the source for a root Skill path', () async {
    final root = await manifestRoot(
      'plugin.json',
      '{"name":"Root Skill","skills":["./"]}',
    );

    final index = (await readPluginManifestIndex(root.path)).valueOrNull!;

    expect(index.searchDirectories, [paths.join(root.path, 'skills')]);
    expect(index.groupings, isEmpty);
  });

  for (final invalid in ['.', './.', './/x', './a//b', './a/../b', './..']) {
    test('rejects the manifest path "$invalid"', () async {
      final root = await manifestRoot(
        'marketplace.json',
        '{"plugins":[{"name":"p","source":"$invalid","skills":["./x/y"]}]}',
      );

      final index = (await readPluginManifestIndex(root.path)).valueOrNull!;

      expect(index.searchDirectories, isEmpty);
      expect(index.groupings, isEmpty);
    });
  }
}
