import 'dart:io';

import 'package:path/path.dart' as path;

/// A local Git repository built with system Git for transport tests.
///
/// The default content covers every entry kind a Source may contain: a
/// regular file, an executable, a binary file, and a symbolic link, beneath a
/// `skills/demo` selection, plus a `feature` branch with distinct content.
final class GitSourceFixture {
  GitSourceFixture._(this.root, this.workingDirectory);

  final Directory root;
  final Directory workingDirectory;

  String get workingPath => workingDirectory.path;

  static const skillBody = '---\nname: demo\ndescription: Demo skill\n---\n';
  static const featureBody =
      '---\nname: demo\ndescription: Feature skill\n---\n';
  static const binaryBytes = <int>[0, 1, 255];

  static Future<GitSourceFixture> create({String name = 'source'}) async {
    final root = await Directory.systemTemp.createTemp(
      'skills-workspace-git-fixture-',
    );
    final working = Directory(path.join(root.path, name));
    await working.create(recursive: true);
    final fixture = GitSourceFixture._(root, working);
    await fixture._populate();
    return fixture;
  }

  Future<void> _populate() async {
    final skill = Directory(path.join(workingPath, 'skills', 'demo'));
    await Directory(path.join(skill.path, 'docs')).create(recursive: true);
    await File(path.join(skill.path, 'SKILL.md')).writeAsString(skillBody);
    await File(
      path.join(skill.path, 'docs', 'binary.bin'),
    ).writeAsBytes(binaryBytes);
    await File(
      path.join(skill.path, 'run.sh'),
    ).writeAsString('#!/bin/sh\nexit 0\n');
    await File(path.join(workingPath, 'README.md')).writeAsString('fixture\n');

    await git(const <String>['init', '--initial-branch=main']);
    await git(const <String>[
      'config',
      'user.email',
      'skills-workspace@example.invalid',
    ]);
    await git(const <String>['config', 'user.name', 'Skills Workspace Test']);
    await git(const <String>['add', '.']);
    await git(const <String>[
      'update-index',
      '--chmod=+x',
      'skills/demo/run.sh',
    ]);
    final linkObject = await hashObject('docs');
    await git(<String>[
      'update-index',
      '--add',
      '--cacheinfo',
      '120000,$linkObject,skills/demo/docs-link',
    ]);
    await git(const <String>['commit', '-m', 'fixture']);

    await git(const <String>['checkout', '-b', 'feature']);
    await File(
      path.join(workingPath, 'skills', 'demo', 'SKILL.md'),
    ).writeAsString(featureBody);
    await git(const <String>['commit', '-am', 'feature']);
    await git(const <String>['checkout', 'main']);
  }

  /// Adds a commit on `main` that places a gitlink at `skills/demo/vendor`.
  Future<void> addGitlink() async {
    final head = await revParse('HEAD');
    await git(<String>[
      'update-index',
      '--add',
      '--cacheinfo',
      '160000,$head,skills/demo/vendor',
    ]);
    await git(const <String>['commit', '-m', 'gitlink']);
  }

  Future<String> revParse(String revision) =>
      gitOutput(<String>['rev-parse', revision]);

  Future<String> hashObject(String content) async {
    final file = File(path.join(root.path, '.object'));
    await file.writeAsString(content);
    try {
      return await gitOutput(<String>['hash-object', '-w', file.path]);
    } finally {
      await file.delete();
    }
  }

  Future<void> git(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: workingPath,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw StateError('Git fixture command failed: ${arguments.first}.');
    }
  }

  Future<String> gitOutput(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: workingPath,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw StateError('Git fixture command failed: ${arguments.first}.');
    }
    return (result.stdout as String).trim();
  }

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}
