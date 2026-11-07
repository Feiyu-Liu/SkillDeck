// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';
import 'package:skills_workspace_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop Flutter host loads and invokes the embedded engine', (
    tester,
  ) async {
    final status = await tester.runAsync(verifyNativePackageLoading);
    await tester.pumpWidget(
      SkillsWorkspaceExample(status: Future<String>.value(status)),
    );
    await tester.pump();

    expect(status, 'Native revision engine ready · libgit2 1.9.7');
    expect(find.textContaining('libgit2 1.9.7'), findsOneWidget);
  });

  testWidgets('desktop engine commits, merges, conflicts, and restores packs', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    try {
      final base = fixture.commit(
        files: <SkillContentEntry>[
          _text('SKILL.md', '# Base\n'),
          _text('script.sh', '#!/bin/sh\n'),
        ],
        parents: const [],
        kind: RevisionCommitKind.initial,
      );
      final local = fixture.commit(
        files: <SkillContentEntry>[
          _text('SKILL.md', '# Local\n'),
          _text('script.sh', '#!/bin/sh\n'),
          _text('notes.md', 'private customization\n'),
        ],
        parents: <RevisionObjectId>[base.commit],
        kind: RevisionCommitKind.localPublish,
      );
      final incoming = fixture.commit(
        files: <SkillContentEntry>[
          _text('SKILL.md', '# Base\n'),
          _text('script.sh', '#!/bin/sh\n', executable: true),
          _text('upstream.md', 'new upstream bytes\n'),
        ],
        parents: <RevisionObjectId>[base.commit],
        kind: RevisionCommitKind.upstream,
      );

      final merge = fixture.engine.merge(
        repositoryPath: fixture.repositoryPath,
        previousUpstream: base.commit,
        currentEffective: local.commit,
        incomingUpstream: incoming.commit,
      );
      expect(merge, isA<RevisionMergeClean>());
      final merged = merge as RevisionMergeClean;
      final effective = fixture.engine.createCommit(
        repositoryPath: fixture.repositoryPath,
        request: RevisionCommitRequest(
          tree: merged.tree,
          parents: <RevisionObjectId>[local.commit, incoming.commit],
          kind: RevisionCommitKind.effectiveUpdate,
        ),
      );
      final materialized = fixture.engine.readTree(
        fixture.repositoryPath,
        effective,
      );
      expect(materialized.files.map((file) => file.relativePath), <String>[
        'SKILL.md',
        'notes.md',
        'script.sh',
        'upstream.md',
      ]);
      expect(
        materialized.files
            .singleWhere((file) => file.relativePath == 'script.sh')
            .isExecutable,
        isTrue,
      );

      final conflicting = fixture.commit(
        files: <SkillContentEntry>[
          _text('SKILL.md', '# Incoming conflict\n'),
          _text('script.sh', '#!/bin/sh\n'),
        ],
        parents: <RevisionObjectId>[base.commit],
        kind: RevisionCommitKind.upstream,
      );
      expect(
        fixture.engine.merge(
          repositoryPath: fixture.repositoryPath,
          previousUpstream: base.commit,
          currentEffective: local.commit,
          incomingUpstream: conflicting.commit,
        ),
        isA<RevisionMergeConflicted>(),
      );

      final bundle = Directory('${fixture.root.path}/bundle')..createSync();
      fixture.engine.createRecoveryPack(
        repositoryPath: fixture.repositoryPath,
        bundleStagingPath: bundle.path,
        retainedRoots: <RevisionObjectId>[base.commit, effective],
      );
      final restoredPath = '${fixture.root.path}/restored.git';
      fixture.engine.restoreRecoveryPack(
        stagedRepositoryPath: restoredPath,
        packPath: '${bundle.path}/objects.pack',
        indexPath: '${bundle.path}/objects.idx',
        retainedRoots: <RevisionObjectId>[base.commit, effective],
      );
      fixture.engine.verifyStore(restoredPath);
      expect(
        fixture.engine.readTree(restoredPath, effective).contentHash,
        materialized.contentHash,
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

final class _Commit {
  const _Commit({required this.tree, required this.commit});

  final RevisionObjectId tree;
  final RevisionObjectId commit;
}

final class _Fixture {
  _Fixture._(this.root, this.repositoryPath, this.engine);

  final Directory root;
  final String repositoryPath;
  final RevisionNativeEngine engine;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'skills-workspace-desktop-integration-',
    );
    final repositoryPath = '${root.path}/store.git';
    final engine = RevisionNativeEngine.open();
    engine.createStore(repositoryPath);
    return _Fixture._(root, repositoryPath, engine);
  }

  _Commit commit({
    required List<SkillContentEntry> files,
    required List<RevisionObjectId> parents,
    required RevisionCommitKind kind,
  }) {
    final tree = const SkillContentNormalizer().normalize(files).valueOrNull!;
    final treeId = engine.writeTree(repositoryPath, tree);
    final commit = engine.createCommit(
      repositoryPath: repositoryPath,
      request: RevisionCommitRequest(
        tree: treeId,
        parents: parents,
        kind: kind,
      ),
    );
    return _Commit(tree: treeId, commit: commit);
  }

  Future<void> dispose() async {
    engine.close();
    await root.delete(recursive: true);
  }
}
