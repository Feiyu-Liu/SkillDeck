import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/infrastructure/project_roots/file_system_project_root_path.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  const adapter = FileSystemProjectRootPath();

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-project-root-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('canonicalizes an existing directory without modifying it', () async {
    final root = Directory(path.join(temporaryDirectory.path, 'project'));
    await root.create();
    final sentinel = File(path.join(root.path, 'sentinel'));
    await sentinel.writeAsString('preserve');
    final before = await root.list().map((entry) => entry.path).toList();

    final canonical = await adapter.canonicalizeExistingDirectory(root.path);

    expect(canonical, path.normalize(await root.resolveSymbolicLinks()));
    expect(await sentinel.readAsString(), 'preserve');
    expect(await root.list().map((entry) => entry.path).toList(), before);
  });

  test('symlink aliases canonicalize to the same physical directory', () async {
    if (Platform.isWindows) {
      return;
    }
    final root = Directory(path.join(temporaryDirectory.path, 'project'));
    await root.create();
    final alias = path.join(temporaryDirectory.path, 'alias');
    await Link(alias).create(root.path);

    expect(
      await adapter.canonicalizeExistingDirectory(alias),
      await adapter.canonicalizeExistingDirectory(root.path),
    );
  });

  test('relative, missing, and file paths are rejected', () async {
    final file = File(path.join(temporaryDirectory.path, 'file'));
    await file.writeAsString('file');

    expect(await adapter.canonicalizeExistingDirectory('relative'), isNull);
    expect(
      await adapter.canonicalizeExistingDirectory(
        path.join(temporaryDirectory.path, 'missing'),
      ),
      isNull,
    );
    expect(await adapter.canonicalizeExistingDirectory(file.path), isNull);
  });
}
