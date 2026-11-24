import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/composition/revision_worker_task_executor.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker.dart';
import 'package:test/test.dart';

void main() {
  test('real Revision worker merges from the best common ancestor', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-sync-merge-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final store = path.join(temporary.path, 'store.git');
    final worker = await RevisionWorker.start(
      taskExecutor: executeComposedRevisionWorkerTask,
    );
    addTearDown(worker.close);
    await worker.createStore(store);

    Future<RevisionObjectId> commit(
      Map<String, String> content, [
      RevisionObjectId? parent,
    ]) async {
      final normalized = await worker.normalizeContent(
        [
          SkillContentEntry.file(
            path: 'SKILL.md',
            bytes: utf8.encode(
              '---\nname: merge-skill\ndescription: Revision fixture\n---\n',
            ),
          ),
          for (final file in content.entries)
            SkillContentEntry.file(
              path: file.key,
              bytes: utf8.encode(file.value),
            ),
        ],
        maximumFileCount: maximumNormalizedSkillFileCount,
        maximumByteSize: maximumNormalizedSkillByteSize,
        isCancelled: () => false,
      );
      final tree = await worker.writeTree(store, normalized.valueOrNull!);
      return worker.createCommit(
        store,
        RevisionCommitRequest(
          tree: tree,
          parents: [?parent],
          kind: parent == null
              ? RevisionCommitKind.initial
              : RevisionCommitKind.localPublish,
        ),
      );
    }

    final root = await commit({});
    final base = await commit({'shared.md': 'second version\n'}, root);
    final local = await commit({
      'shared.md': 'local edit\n',
      'local.md': 'local file\n',
    }, base);
    final remoteIntermediate = await commit({
      'shared.md': 'second version\n',
      'remote.md': 'remote intermediate\n',
    }, base);
    final remote = await commit({
      'shared.md': 'second version\n',
      'remote.md': 'remote edit\n',
    }, remoteIntermediate);
    final unrelated = await commit({'unrelated.md': 'unrelated\n'});
    expect(await worker.mergeBase(store, local, remote), base);
    expect(await worker.mergeBase(store, local, unrelated), isNull);
    expect(
      () => worker.mergeBase(store, local, RevisionObjectId('0' * 40)),
      throwsA(isA<RevisionEngineException>()),
    );
    expect(
      () => worker.merge(
        repositoryPath: store,
        previousUpstream: base,
        currentEffective: local,
        incomingUpstream: remote,
      ),
      throwsA(isA<RevisionEngineException>()),
    );

    final merged =
        await worker.mergeSync(
              repositoryPath: store,
              base: base,
              local: local,
              remote: remote,
            )
            as RevisionMergeClean;
    final result = await worker.readTree(store, merged.tree);
    expect({
      for (final file in result.files)
        file.relativePath: utf8.decode(file.bytes),
    }, containsPair('shared.md', 'local edit\n'));
    expect(
      result.files.map((file) => file.relativePath),
      unorderedEquals(['SKILL.md', 'shared.md', 'local.md', 'remote.md']),
    );

    final conflicting = await commit({'shared.md': 'remote conflict\n'}, base);
    final conflict =
        await worker.mergeSync(
              repositoryPath: store,
              base: base,
              local: local,
              remote: conflicting,
            )
            as RevisionMergeConflicted;
    expect(conflict.conflicts.single.currentPath, 'shared.md');
    final candidateRequest = RevisionCommitRequest(
      tree: conflict.tree,
      parents: [local, conflicting],
      kind: RevisionCommitKind.syncCandidate,
    );
    final candidate = await worker.createCommit(store, candidateRequest);
    await worker.verifyCommit(store, candidate, candidateRequest);
    expect(await worker.readMergeParent(store, candidate), conflicting);
    expect(await worker.readMergeParent(store, local), isNull);
  });

  test(
    'real Revision worker persists and verifies a complete Bundle',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'skills-workspace-native-integration-',
      );
      final repositoryPath = path.join(temporary.path, 'store.git');
      final bundlePath = path.join(temporary.path, 'bundle');
      final worker = await RevisionWorker.start(
        taskExecutor: executeComposedRevisionWorkerTask,
      );
      try {
        final normalized = await worker.normalizeContent(
          <SkillContentEntry>[
            SkillContentEntry.file(
              path: 'SKILL.md',
              bytes: utf8.encode('''---
name: integration-skill
description: Real native integration fixture
---
# Integration Skill
'''),
            ),
            SkillContentEntry.file(
              path: 'bin/tool',
              bytes: const <int>[0, 1, 2, 3],
              isExecutable: true,
            ),
          ],
          maximumFileCount: maximumNormalizedSkillFileCount,
          maximumByteSize: maximumNormalizedSkillByteSize,
          isCancelled: () => false,
        );
        expect(normalized.failureOrNull, isNull);

        await worker.createStore(repositoryPath);
        final tree = await worker.writeTree(
          repositoryPath,
          normalized.valueOrNull!,
        );
        final commitRequest = RevisionCommitRequest(
          tree: tree,
          parents: const <RevisionObjectId>[],
          kind: RevisionCommitKind.initial,
        );
        final commit = await worker.createCommit(repositoryPath, commitRequest);
        await worker.verifyCommit(repositoryPath, commit, commitRequest);

        await Directory(bundlePath).create();
        await worker.buildRevisionBundleArtifacts(
          repositoryPath: repositoryPath,
          bundlePath: bundlePath,
          sourceLineage: SourceLineageReference(
            '123e4567-e89b-42d3-a456-426614174321',
          ),
          currentUpstream: commit,
          currentEffective: commit,
          retainedRoots: <RevisionObjectId>[commit],
        );
        await worker.verifyRevisionBundleArtifacts(
          bundlePath: bundlePath,
          sourceLineage: SourceLineageReference(
            '123e4567-e89b-42d3-a456-426614174321',
          ),
          currentUpstream: commit,
          currentEffective: commit,
          retainedRoots: <RevisionObjectId>[commit],
        );

        final restored = await worker.readTree(repositoryPath, commit);
        expect(restored.contentHash, normalized.valueOrNull!.contentHash);
        expect(restored.files, normalized.valueOrNull!.files);
        expect(
          await File(path.join(bundlePath, 'objects.pack')).length(),
          greaterThan(0),
        );
        expect(
          await File(path.join(bundlePath, 'objects.idx')).length(),
          greaterThan(0),
        );
        expect(
          await File(path.join(bundlePath, 'manifest.json')).length(),
          greaterThan(0),
        );
        expect(
          await File(path.join(bundlePath, 'COMPLETE')).length(),
          greaterThan(0),
        );
      } finally {
        await worker.close();
        await temporary.delete(recursive: true);
      }
    },
  );
}
