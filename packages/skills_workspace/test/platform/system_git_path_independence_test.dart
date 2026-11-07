import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('non-Git Source operations work with Git absent from PATH', () async {
    final emptyPath = await Directory.systemTemp.createTemp(
      'skills-workspace-empty-path-',
    );
    addTearDown(() async {
      if (await emptyPath.exists()) await emptyPath.delete(recursive: true);
    });
    final packageRoot = Directory.current.path;
    final fixture = path.join(
      packageRoot,
      'test',
      'fixtures',
      'non_git_without_system_git.dart',
    );
    final executable = path.join(
      emptyPath.path,
      Platform.isWindows ? 'non_git_fixture.exe' : 'non_git_fixture',
    );
    final compilerTemp = Directory(path.join(emptyPath.path, 'compiler-temp'));
    await compilerTemp.create();
    final compilation = await Process.run(
      Platform.resolvedExecutable,
      <String>['compile', 'exe', fixture, '-o', executable],
      workingDirectory: packageRoot,
      environment: <String, String>{
        ...Platform.environment,
        'TEMP': compilerTemp.path,
        'TMP': compilerTemp.path,
        'TMPDIR': compilerTemp.path,
      },
    );
    expect(
      compilation.exitCode,
      0,
      reason:
          'compile stdout: ${compilation.stdout}\n'
          'compile stderr: ${compilation.stderr}',
    );

    final result = await Process.run(
      executable,
      const <String>[],
      workingDirectory: packageRoot,
      environment: <String, String>{
        ...Platform.environment,
        'PATH': emptyPath.path,
      },
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
  });
}
