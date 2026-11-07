import 'dart:convert';
import 'dart:io';

import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_recovery_bundle.dart';
import 'package:test/test.dart';

void main() {
  test('builds the fixed Upstream and Effective graph topology', () async {
    final fixture = await _RevisionFixture.create();
    try {
      final baseTree = fixture.writeTree(<SkillContentEntry>[
        _text('SKILL.md', '# Base\n'),
        _text('docs/guide.md', 'same rename bytes\n'),
        _text('removed.md', 'removed only from the local revision\n'),
        _text('script.sh', '#!/bin/sh\n'),
      ]);
      final root = fixture.commit(
        tree: baseTree,
        parents: const [],
        kind: RevisionCommitKind.initial,
      );

      final localTree = fixture.writeTree(<SkillContentEntry>[
        _text('SKILL.md', '# Base\n'),
        _text('docs/manual.md', 'same rename bytes\n'),
        _text('personal.md', 'local only\n'),
        _text('asset.bin', '\u0000\u0001binary'),
        _text('script.sh', '#!/bin/sh\n'),
      ]);
      final local = fixture.commit(
        tree: localTree,
        parents: <RevisionObjectId>[root],
        kind: RevisionCommitKind.localPublish,
      );

      final incomingTree = fixture.writeTree(<SkillContentEntry>[
        _text('SKILL.md', '# Upstream\n'),
        _text('docs/guide.md', 'same rename bytes\n'),
        _text('script.sh', '#!/bin/sh\n', executable: true),
      ]);
      final incoming = fixture.commit(
        tree: incomingTree,
        parents: <RevisionObjectId>[root],
        kind: RevisionCommitKind.upstream,
      );

      final merge = fixture.engine.merge(
        repositoryPath: fixture.repositoryPath,
        previousUpstream: root,
        currentEffective: local,
        incomingUpstream: incoming,
      );
      expect(merge, isA<RevisionMergeClean>());
      final mergedTree = (merge as RevisionMergeClean).tree;
      final materializedMergedTree = fixture.engine.readTree(
        fixture.repositoryPath,
        mergedTree,
      );
      expect(
        materializedMergedTree.files.map((file) => file.relativePath),
        containsAll(<String>['SKILL.md', 'personal.md', 'script.sh']),
      );
      final effective = fixture.commit(
        tree: mergedTree,
        parents: <RevisionObjectId>[local, incoming],
        kind: RevisionCommitKind.effectiveUpdate,
      );

      fixture.engine.verifyCommit(
        repositoryPath: fixture.repositoryPath,
        commit: effective,
        expected: RevisionCommitRequest(
          tree: mergedTree,
          parents: <RevisionObjectId>[local, incoming],
          kind: RevisionCommitKind.effectiveUpdate,
        ),
      );
      expect(
        fixture.engine.isAncestor(
          repositoryPath: fixture.repositoryPath,
          ancestor: root,
          descendant: effective,
        ),
        isTrue,
      );
      expect(
        fixture.engine.isAncestor(
          repositoryPath: fixture.repositoryPath,
          ancestor: local,
          descendant: effective,
        ),
        isTrue,
      );
      expect(
        fixture.engine.isAncestor(
          repositoryPath: fixture.repositoryPath,
          ancestor: incoming,
          descendant: effective,
        ),
        isTrue,
      );

      final materialized = fixture.engine.readTree(
        fixture.repositoryPath,
        effective,
      );
      expect(
        materialized.files.map((file) => file.relativePath),
        containsAll(<String>[
          'SKILL.md',
          'asset.bin',
          'docs/manual.md',
          'personal.md',
          'script.sh',
        ]),
      );
      expect(
        materialized.files
            .singleWhere((file) => file.relativePath == 'SKILL.md')
            .bytes,
        utf8.encode('# Upstream\n'),
      );
      expect(
        materialized.files
            .singleWhere((file) => file.relativePath == 'script.sh')
            .isExecutable,
        isTrue,
      );

      final localChanges = fixture.engine.diff(
        repositoryPath: fixture.repositoryPath,
        oldCommit: root,
        newCommit: local,
      );
      expect(
        localChanges,
        contains(
          isA<RevisionChange>()
              .having(
                (change) => change.kind,
                'kind',
                RevisionChangeKind.renamed,
              )
              .having((change) => change.oldPath, 'oldPath', 'docs/guide.md')
              .having((change) => change.newPath, 'newPath', 'docs/manual.md'),
        ),
      );
      final deletedChange = localChanges.singleWhere(
        (change) => change.kind == RevisionChangeKind.deleted,
      );
      expect(deletedChange.oldPath, 'removed.md');
      expect(deletedChange.newPath, 'removed.md');
      expect(deletedChange.oldExecutable, isFalse);
      expect(deletedChange.newExecutable, isFalse);
      expect(deletedChange.binary, isFalse);
      expect(
        localChanges,
        contains(
          isA<RevisionChange>()
              .having((change) => change.newPath, 'newPath', 'asset.bin')
              .having((change) => change.binary, 'binary', isTrue),
        ),
      );
      final upstreamChanges = fixture.engine.diff(
        repositoryPath: fixture.repositoryPath,
        oldCommit: root,
        newCommit: incoming,
      );
      expect(
        upstreamChanges,
        contains(
          isA<RevisionChange>()
              .having((change) => change.newPath, 'path', 'script.sh')
              .having(
                (change) => change.oldExecutable,
                'oldExecutable',
                isFalse,
              )
              .having(
                (change) => change.newExecutable,
                'newExecutable',
                isTrue,
              ),
        ),
      );
    } finally {
      await fixture.dispose();
    }
  });

  test('returns typed paths for a content conflict', () async {
    final fixture = await _RevisionFixture.create();
    try {
      final base = fixture.writeTree(<SkillContentEntry>[
        _text('SKILL.md', '# Base\n'),
      ]);
      final root = fixture.commit(
        tree: base,
        parents: const [],
        kind: RevisionCommitKind.initial,
      );
      final current = fixture.commit(
        tree: fixture.writeTree(<SkillContentEntry>[
          _text('SKILL.md', '# Local\n'),
        ]),
        parents: <RevisionObjectId>[root],
        kind: RevisionCommitKind.localPublish,
      );
      final incoming = fixture.commit(
        tree: fixture.writeTree(<SkillContentEntry>[
          _text('SKILL.md', '# Incoming\n'),
        ]),
        parents: <RevisionObjectId>[root],
        kind: RevisionCommitKind.upstream,
      );

      final result = fixture.engine.merge(
        repositoryPath: fixture.repositoryPath,
        previousUpstream: root,
        currentEffective: current,
        incomingUpstream: incoming,
      );

      expect(result, isA<RevisionMergeConflicted>());
      final conflicted = result as RevisionMergeConflicted;
      final conflict = conflicted.conflicts.single;
      expect(conflict.ancestorPath, 'SKILL.md');
      expect(conflict.currentPath, 'SKILL.md');
      expect(conflict.incomingPath, 'SKILL.md');
      final candidate = fixture.engine.readTree(
        fixture.repositoryPath,
        conflicted.tree,
      );
      expect(candidate.files.single.bytes, utf8.encode('# Local\n'));
    } finally {
      await fixture.dispose();
    }
  });

  test('creates, verifies and restores an exact recovery pack', () async {
    final fixture = await _RevisionFixture.create();
    try {
      final baseTree = fixture.writeTree(<SkillContentEntry>[
        _text('SKILL.md', '# Base\n'),
      ]);
      final root = fixture.commit(
        tree: baseTree,
        parents: const [],
        kind: RevisionCommitKind.initial,
      );
      final publishedTree = fixture.writeTree(<SkillContentEntry>[
        _text('SKILL.md', '# Customized\n'),
        _text('notes.md', 'kept only in local history\n'),
      ]);
      final published = fixture.commit(
        tree: publishedTree,
        parents: <RevisionObjectId>[root],
        kind: RevisionCommitKind.localPublish,
      );
      final unreachableTree = fixture.writeTree(<SkillContentEntry>[
        _text('discarded.md', 'must not enter the recovery pack\n'),
      ]);
      final unreachable = fixture.commit(
        tree: unreachableTree,
        parents: const <RevisionObjectId>[],
        kind: RevisionCommitKind.initial,
      );
      final bundleDirectory = Directory('${fixture.root.path}/bundle')
        ..createSync();

      fixture.engine.createRecoveryPack(
        repositoryPath: fixture.repositoryPath,
        bundleStagingPath: bundleDirectory.path,
        retainedRoots: <RevisionObjectId>[root, published],
      );
      final packFile = File('${bundleDirectory.path}/objects.pack');
      final indexFile = File('${bundleDirectory.path}/objects.idx');
      expect(packFile.existsSync(), isTrue);
      expect(indexFile.existsSync(), isTrue);

      const codec = RevisionRecoveryBundleCodec();
      final manifest = codec.createManifest(
        sourceLineageId: 'lineage-1',
        currentUpstream: root,
        currentEffective: published,
        retainedPublishedRoots: <RevisionObjectId>[published, root, published],
        packBytes: packFile.readAsBytesSync(),
        indexBytes: indexFile.readAsBytesSync(),
      );
      final manifestBytes = codec.encodeManifest(manifest);
      final fenceBytes = codec.createCompletionFence(manifestBytes);
      expect(
        codec
            .verify(
              manifestBytes: manifestBytes,
              completionFenceBytes: fenceBytes,
              packBytes: packFile.readAsBytesSync(),
              indexBytes: indexFile.readAsBytesSync(),
            )
            .retainedPublishedRoots,
        <RevisionObjectId>[root, published]
          ..sort((left, right) => left.value.compareTo(right.value)),
      );

      for (var attempt = 1; attempt <= 2; attempt += 1) {
        final restoredPath = '${fixture.root.path}/restored-$attempt.git';
        fixture.engine.restoreRecoveryPack(
          stagedRepositoryPath: restoredPath,
          packPath: packFile.path,
          indexPath: indexFile.path,
          retainedRoots: <RevisionObjectId>[root, published],
        );
        fixture.engine.verifyStore(restoredPath);
        final restored = fixture.engine.readTree(restoredPath, published);
        expect(restored.files.map((file) => file.relativePath), <String>[
          'SKILL.md',
          'notes.md',
        ]);
        fixture.engine.verifyCommit(
          repositoryPath: restoredPath,
          commit: root,
          expected: RevisionCommitRequest(
            tree: baseTree,
            parents: const [],
            kind: RevisionCommitKind.initial,
          ),
        );
        expect(
          () => fixture.engine.readTree(restoredPath, unreachable),
          throwsA(_nativeCode(RevisionNativeFailureCode.objectFailure)),
          reason: 'an unreachable commit must not enter the exact pack',
        );
      }

      final missing = RevisionObjectId('f' * 40);
      expect(
        () => fixture.engine.restoreRecoveryPack(
          stagedRepositoryPath: '${fixture.root.path}/missing-object.git',
          packPath: packFile.path,
          indexPath: indexFile.path,
          retainedRoots: <RevisionObjectId>[root, published, missing],
        ),
        throwsA(_nativeCode(RevisionNativeFailureCode.bundleFailure)),
      );

      final tamperedPack = File('${fixture.root.path}/tampered.pack');
      final tamperedBytes = packFile.readAsBytesSync();
      tamperedBytes[tamperedBytes.length ~/ 2] ^= 0xff;
      tamperedPack.writeAsBytesSync(tamperedBytes);
      expect(
        () => codec.verify(
          manifestBytes: manifestBytes,
          completionFenceBytes: fenceBytes,
          packBytes: tamperedBytes,
          indexBytes: indexFile.readAsBytesSync(),
        ),
        throwsA(
          isA<RevisionRecoveryBundleException>().having(
            (error) => error.reason,
            'reason',
            RevisionRecoveryBundleFailureReason.packDigestMismatch,
          ),
        ),
      );
      expect(
        () => fixture.engine.restoreRecoveryPack(
          stagedRepositoryPath: '${fixture.root.path}/tampered.git',
          packPath: tamperedPack.path,
          indexPath: indexFile.path,
          retainedRoots: <RevisionObjectId>[root, published],
        ),
        throwsA(_nativeCode(RevisionNativeFailureCode.bundleFailure)),
      );

      final tamperedIndexBytes = indexFile.readAsBytesSync();
      tamperedIndexBytes[tamperedIndexBytes.length ~/ 2] ^= 0xff;
      expect(
        () => codec.verify(
          manifestBytes: manifestBytes,
          completionFenceBytes: fenceBytes,
          packBytes: packFile.readAsBytesSync(),
          indexBytes: tamperedIndexBytes,
        ),
        throwsA(
          isA<RevisionRecoveryBundleException>().having(
            (error) => error.reason,
            'reason',
            RevisionRecoveryBundleFailureReason.indexDigestMismatch,
          ),
        ),
      );
    } finally {
      await fixture.dispose();
    }
  });
}

SkillContentEntry _text(String path, String text, {bool executable = false}) =>
    SkillContentEntry.file(
      path: path,
      bytes: utf8.encode(text),
      isExecutable: executable,
    );

final class _RevisionFixture {
  _RevisionFixture._({
    required this.root,
    required this.repositoryPath,
    required this.engine,
  });

  final Directory root;
  final String repositoryPath;
  final RevisionNativeEngine engine;

  static Future<_RevisionFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'skills-workspace-history-',
    );
    final repositoryPath = '${root.path}/store.git';
    final engine = RevisionNativeEngine.open();
    engine.createStore(repositoryPath);
    return _RevisionFixture._(
      root: root,
      repositoryPath: repositoryPath,
      engine: engine,
    );
  }

  RevisionObjectId writeTree(List<SkillContentEntry> entries) {
    final tree = const SkillContentNormalizer().normalize(entries).valueOrNull!;
    return engine.writeTree(repositoryPath, tree);
  }

  RevisionObjectId commit({
    required RevisionObjectId tree,
    required List<RevisionObjectId> parents,
    required RevisionCommitKind kind,
  }) => engine.createCommit(
    repositoryPath: repositoryPath,
    request: RevisionCommitRequest(tree: tree, parents: parents, kind: kind),
  );

  Future<void> dispose() async {
    engine.close();
    await root.delete(recursive: true);
  }
}

Matcher _nativeCode(RevisionNativeFailureCode code) =>
    isA<RevisionNativeException>().having((error) => error.code, 'code', code);
