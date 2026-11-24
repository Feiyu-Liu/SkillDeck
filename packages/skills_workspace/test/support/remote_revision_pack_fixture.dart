import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

import 'drift_facade_fixture.dart';

/// Builds incoming commits outside the serving Workspace's Revision Store.
final class RemoteRevisionPackFixture {
  RemoteRevisionPackFixture._(this.base, this._donorStore);

  final RevisionPackExport base;
  final String _donorStore;

  static Future<RemoteRevisionPackFixture> create(
    DriftFacadeFixture fixture,
  ) async {
    final base = await driftSuccess(
      fixture.repository.exportRevisionPack(
        ExportRevisionPackRequest(
          managedSkillId: fixture.managedSkillId,
          destinationPath: path.join(fixture.exportDirectory, 'base.pack'),
        ),
      ),
    );
    final store = WorkspaceLayout(
      fixture.workspacePath,
    ).revisionStorePath(fixture.managedSkillId);
    final donor = path.join(fixture.temporaryRoot.path, 'donor.git');
    await _gitText(donor, ['init', '--bare', '--object-format=sha1']);
    await File(
      path.join(donor, 'objects', 'info', 'alternates'),
    ).writeAsString('${path.join(store, 'objects')}\n');
    return RemoteRevisionPackFixture._(base, donor);
  }

  Future<({RevisionId revision, String packPath})> incoming({
    RevisionId? parent,
    required Map<String, String> files,
  }) async {
    final anchor = parent ?? base.effective;
    await _gitText(_donorStore, ['read-tree', anchor.value]);
    for (final entry in files.entries) {
      final blob = await _gitText(_donorStore, [
        'hash-object',
        '-w',
        '--stdin',
      ], entry.value);
      await _gitText(_donorStore, [
        'update-index',
        '--add',
        '--cacheinfo',
        '100644,$blob,${entry.key}',
      ]);
    }
    final tree = await _gitText(_donorStore, ['write-tree']);
    final revision = RevisionId(
      await _gitText(_donorStore, [
        'commit-tree',
        tree,
        '-p',
        anchor.value,
      ], 'Remote revision\n'),
    );
    final pack = File(
      path.join(path.dirname(_donorStore), '${revision.value}.pack'),
    );
    await pack.writeAsBytes(
      await _runGit(_donorStore, [
        'pack-objects',
        '--revs',
        '--stdout',
      ], '${revision.value}\n'),
    );
    return (revision: revision, packPath: pack.path);
  }
}

Future<String> _gitText(
  String store,
  List<String> args, [
  String? input,
]) async => utf8.decode(await _runGit(store, args, input)).trim();

Future<List<int>> _runGit(
  String store,
  List<String> args, [
  String? input,
]) async {
  final process = await Process.start(
    'git',
    ['--git-dir=$store', ...args],
    environment: {
      'GIT_AUTHOR_NAME': 'Remote Pack Fixture',
      'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
      'GIT_COMMITTER_NAME': 'Remote Pack Fixture',
      'GIT_COMMITTER_EMAIL': 'fixture@example.invalid',
    },
  );
  final output = process.stdout.expand((chunk) => chunk).toList();
  final errors = process.stderr.drain<void>();
  if (input != null) process.stdin.write(input);
  await process.stdin.close();
  await errors;
  expect(await process.exitCode, 0, reason: 'Git ${args.first} failed');
  return output;
}
