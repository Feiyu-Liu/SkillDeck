import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_source_transport.dart';
import 'package:test/test.dart';

void main() {
  test(
    'fetches a bare source and exports recursive blobs without checkout',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'skills-workspace-git-source-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final sourceDirectory = Directory(path.join(root.path, 'source'));
      final destination = path.join(root.path, 'acquired.git');
      final hooks = Directory(path.join(root.path, 'disabled-hooks'));
      await sourceDirectory.create();
      await hooks.create();
      await Directory(path.join(sourceDirectory.path, 'docs')).create();
      await File(
        path.join(sourceDirectory.path, 'SKILL.md'),
      ).writeAsString('---\nname: demo\ndescription: Demo skill\n---\n');
      await File(
        path.join(sourceDirectory.path, 'docs', 'binary.bin'),
      ).writeAsBytes(const <int>[0, 1, 255]);
      await File(
        path.join(sourceDirectory.path, 'run.sh'),
      ).writeAsString('#!/bin/sh\nexit 0\n');

      await _git(sourceDirectory.path, const <String>['init']);
      await _git(sourceDirectory.path, const <String>[
        'config',
        'user.email',
        'skills-workspace@example.invalid',
      ]);
      await _git(sourceDirectory.path, const <String>[
        'config',
        'user.name',
        'Skills Workspace Test',
      ]);
      await _git(sourceDirectory.path, const <String>['add', '.']);
      await _git(sourceDirectory.path, const <String>[
        'update-index',
        '--chmod=+x',
        'run.sh',
      ]);
      final linkTarget = File(path.join(sourceDirectory.path, '.link-target'));
      await linkTarget.writeAsString('docs');
      final linkObject = await _gitOutput(sourceDirectory.path, const <String>[
        'hash-object',
        '-w',
        '.link-target',
      ]);
      await linkTarget.delete();
      await _git(sourceDirectory.path, <String>[
        'update-index',
        '--add',
        '--cacheinfo',
        '120000,$linkObject,docs-link',
      ]);
      await _git(sourceDirectory.path, const <String>[
        'commit',
        '-m',
        'fixture',
      ]);

      final transport = SystemGitSourceTransport();
      final fetched = await transport.fetchBare(
        GitSourceDescriptor(locator: sourceDirectory.path),
        repositoryPath: destination,
        disabledHooksPath: hooks.path,
        cancellation: const _NeverCancellation(),
      );
      expect(fetched, isA<GitTransportSuccess<GitBareSource>>());
      final bare = fetched.valueOrNull!;
      expect(
        await Directory(path.join(destination, 'objects')).exists(),
        isTrue,
      );
      expect(await Directory(path.join(destination, '.git')).exists(), isFalse);

      final listed = await transport.listTree(
        bare,
        repositorySubpath: '',
        cancellation: const _NeverCancellation(),
      );
      final entries = listed.valueOrNull!;
      expect(entries.map((entry) => entry.relativePath), <String>[
        'SKILL.md',
        'docs-link',
        'docs/binary.bin',
        'run.sh',
      ]);
      expect(
        entries
            .singleWhere((entry) => entry.relativePath == 'run.sh')
            .executable,
        isTrue,
      );
      expect(
        entries.singleWhere((entry) => entry.relativePath == 'docs-link').kind,
        GitTreeEntryKind.symbolicLink,
      );

      final bytesByPath = <String, BytesBuilder>{};
      final streamed = await transport.streamBlobs(
        bare,
        requests: [
          for (final entry in entries)
            GitBlobRequest(
              objectId: entry.objectId,
              relativePath: entry.relativePath,
            ),
        ],
        onChunk: (chunk) async {
          bytesByPath
              .putIfAbsent(chunk.request.relativePath, BytesBuilder.new)
              .add(chunk.bytes);
        },
        cancellation: const _NeverCancellation(),
      );
      expect(streamed, isA<GitTransportSuccess<void>>());
      expect(bytesByPath['docs/binary.bin']!.takeBytes(), const <int>[
        0,
        1,
        255,
      ]);
      expect(
        String.fromCharCodes(bytesByPath['SKILL.md']!.takeBytes()),
        contains('name: demo'),
      );
      expect(
        String.fromCharCodes(bytesByPath['docs-link']!.takeBytes()),
        'docs',
      );

      await transport.dispose(bare);
      expect(await Directory(destination).exists(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('rejects Git links without streaming commit objects', () async {
    final root = await Directory.systemTemp.createTemp(
      'skills-workspace-gitlink-source-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final sourceDirectory = Directory(path.join(root.path, 'source'));
    final destination = path.join(root.path, 'acquired.git');
    final hooks = Directory(path.join(root.path, 'disabled-hooks'));
    await sourceDirectory.create();
    await hooks.create();
    await File(
      path.join(sourceDirectory.path, 'SKILL.md'),
    ).writeAsString('---\nname: demo\ndescription: Demo skill\n---\n');
    await _initializeRepository(sourceDirectory.path);
    await _git(sourceDirectory.path, const <String>['add', '.']);
    await _git(sourceDirectory.path, const <String>['commit', '-m', 'base']);
    final commit = await _gitOutput(sourceDirectory.path, const <String>[
      'rev-parse',
      'HEAD',
    ]);
    await _git(sourceDirectory.path, <String>[
      'update-index',
      '--add',
      '--cacheinfo',
      '160000,$commit,submodule',
    ]);
    await _git(sourceDirectory.path, const <String>['commit', '-m', 'gitlink']);

    final transport = SystemGitSourceTransport();
    final fetched = await transport.fetchBare(
      GitSourceDescriptor(locator: sourceDirectory.path),
      repositoryPath: destination,
      disabledHooksPath: hooks.path,
      cancellation: const _NeverCancellation(),
    );
    final listed = await transport.listTree(
      fetched.valueOrNull!,
      repositorySubpath: '',
      cancellation: const _NeverCancellation(),
    );

    expect(listed.failureOrNull, isNull);
    expect(
      listed.valueOrNull!.any(
        (entry) => entry.kind == GitTreeEntryKind.gitlink,
      ),
      isTrue,
    );
    await transport.dispose(fetched.valueOrNull!);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

Future<void> _initializeRepository(String workingDirectory) async {
  await _git(workingDirectory, const <String>['init']);
  await _git(workingDirectory, const <String>[
    'config',
    'user.email',
    'skills-workspace@example.invalid',
  ]);
  await _git(workingDirectory, const <String>[
    'config',
    'user.name',
    'Skills Workspace Test',
  ]);
}

Future<void> _git(String workingDirectory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );
  if (result.exitCode != 0) {
    throw StateError('Git fixture command failed.');
  }
}

Future<String> _gitOutput(
  String workingDirectory,
  List<String> arguments,
) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );
  if (result.exitCode != 0) {
    throw StateError('Git fixture command failed.');
  }
  return (result.stdout as String).trim();
}

final class _NeverCancellation implements GitCancellationSignal {
  const _NeverCancellation();

  static final Future<void> _never = Completer<void>().future;

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => _never;
}
