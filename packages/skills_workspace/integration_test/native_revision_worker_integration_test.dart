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
