import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/draft_snapshot_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/composition/revision_worker_task_executor.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('supports more than eight sequential worker lifecycles', () async {
    for (var index = 0; index < 16; index += 1) {
      final worker = await _startWorker();
      await worker.status();
      await worker.close();
    }
  });

  test(
    'starts once, acknowledges status, and shuts down idempotently',
    () async {
      final worker = await _startWorker();

      expect(worker.isRunning, isTrue);
      expect(
        await worker.status(),
        const RevisionEngineStatus(
          protocolVersion: revisionWorkerProtocolVersion,
        ),
      );

      await worker.close();
      await worker.close();

      expect(worker.isClosed, isTrue);
      await expectLater(
        worker.status(),
        throwsA(_hasCode(RevisionWorkerFailureCode.closed)),
      );
    },
  );

  test('close drains queued work and rejects new requests', () async {
    final worker = await _startWorker();
    final pending = worker.statusForTesting(
      delay: const Duration(milliseconds: 30),
    );

    expect(worker.pendingRequestCount, 1);
    final closing = worker.close();

    await expectLater(
      worker.status(),
      throwsA(_hasCode(RevisionWorkerFailureCode.closing)),
    );
    expect(
      await pending,
      const RevisionEngineStatus(
        protocolVersion: revisionWorkerProtocolVersion,
      ),
    );
    await closing;
    expect(worker.pendingRequestCount, 0);
  });

  test('maps an unexpected worker termination onto pending requests', () async {
    final worker = await _startWorker();
    final pending = worker.statusForTesting(delay: const Duration(seconds: 30));
    final expectation = expectLater(
      pending,
      throwsA(_hasCode(RevisionWorkerFailureCode.terminated)),
    );

    worker.terminateForTesting();

    await expectation;
    expect(worker.isClosed, isTrue);
    await worker.close();
  });

  test('maps an unhandled worker error without exposing diagnostics', () async {
    final worker = await _startWorker();

    await expectLater(
      worker.crashForTesting(),
      throwsA(_hasCode(RevisionWorkerFailureCode.workerFailed)),
    );
    expect(worker.isClosed, isTrue);
    await worker.close();
  });

  test('rejects a worker using an unsupported protocol version', () async {
    await expectLater(
      RevisionWorker.startForTesting(
        workerProtocolVersion: revisionWorkerProtocolVersion + 1,
      ),
      throwsA(_hasCode(RevisionWorkerFailureCode.protocolMismatch)),
    );
  });

  test('maps failure before startup acknowledgement', () async {
    await expectLater(
      RevisionWorker.startForTesting(failBeforeStartup: true),
      throwsA(_hasCode(RevisionWorkerFailureCode.startupFailed)),
    );
  });

  test('owns tree and commit work across the typed worker protocol', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-worker-history-',
    );
    final repositoryPath = '${temporaryDirectory.path}/store.git';
    final worker = await _startWorker();
    try {
      final tree = const SkillContentNormalizer().normalize(<SkillContentEntry>[
        SkillContentEntry.file(
          path: 'SKILL.md',
          bytes: utf8.encode('# Worker\n'),
        ),
        SkillContentEntry.file(
          path: 'bin/tool',
          bytes: const <int>[0, 1, 2],
          isExecutable: true,
        ),
      ]).valueOrNull!;
      await worker.createStore(repositoryPath);
      final treeOid = await worker.writeTree(repositoryPath, tree);
      final commitRequest = RevisionCommitRequest(
        tree: treeOid,
        parents: const [],
        kind: RevisionCommitKind.initial,
      );
      final commit = await worker.createCommit(repositoryPath, commitRequest);

      await worker.replaceRetentionRefs(repositoryPath, <RevisionRetentionRef>[
        RevisionRetentionRef(
          name: 'refs/skills-workspace/current/worker/effective',
          target: commit,
        ),
      ]);

      await worker.verifyCommit(repositoryPath, commit, commitRequest);
      final restored = await worker.readTree(repositoryPath, commit);
      expect(restored.contentHash, tree.contentHash);
      expect(restored.files, tree.files);
      expect(
        (await File(
          '$repositoryPath/refs/skills-workspace/current/worker/effective',
        ).readAsString()).trim(),
        commit.value,
      );
    } finally {
      await worker.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('owns normalization, filesystem scanning, and Draft capture', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-worker-content-',
    );
    final sourcePath = path.join(temporaryDirectory.path, 'source');
    final draftPath = path.join(temporaryDirectory.path, 'draft');
    final stagingPath = path.join(
      temporaryDirectory.path,
      'private',
      'snapshot',
    );
    await Directory(sourcePath).create();
    await Directory(draftPath).create();
    await File(path.join(sourcePath, 'SKILL.md')).writeAsString(
      '---\nname: worker-content\ndescription: Worker content\n---\n',
    );
    await File(path.join(draftPath, 'SKILL.md')).writeAsString(
      '---\nname: worker-draft\ndescription: Worker Draft\n---\n',
    );
    final worker = await _startWorker();
    try {
      final normalized = await worker.normalizeContent(
        <SkillContentEntry>[
          SkillContentEntry.file(
            path: 'SKILL.md',
            bytes: utf8.encode(
              '---\nname: worker-inline\ndescription: Worker inline\n---\n',
            ),
          ),
        ],
        maximumFileCount: maximumNormalizedSkillFileCount,
        maximumByteSize: maximumNormalizedSkillByteSize,
        isCancelled: () => false,
      );
      expect(normalized.failureOrNull, isNull);
      expect(normalized.valueOrNull!.files.single.relativePath, 'SKILL.md');

      final scanned = await worker.readFilesystemTree(
        sourcePath,
        gitMetadataDisposition: GitMetadataDisposition.reject,
        capturePosixExecutableIntent: false,
        executableIntentOverrides: const <String, bool>{},
        maximumFileCount: maximumNormalizedSkillFileCount,
        maximumByteSize: maximumNormalizedSkillByteSize,
        isCancelled: () => false,
      );
      expect(scanned.failureOrNull, isNull);
      expect(
        utf8.decode(scanned.valueOrNull!.files.single.bytes),
        '---\nname: worker-content\ndescription: Worker content\n---\n',
      );

      final captured = await worker.capture(
        DraftCaptureRequest(
          liveDraftPath: draftPath,
          stagingDestinationPath: stagingPath,
          capturePosixExecutableIntent: false,
        ),
      );
      expect(captured.failureOrNull, isNull);
      expect(captured.valueOrNull!.files.single.relativePath, 'SKILL.md');
      final draftTree = await worker.normalize(captured.valueOrNull!.files);
      expect(draftTree.failureOrNull, isNull);
      expect(
        await worker.readDeclaredName(draftTree.valueOrNull!),
        'worker-draft',
      );
      await worker.discardStaging(captured.valueOrNull!);
      expect(
        await Directory(captured.valueOrNull!.stagingPath).exists(),
        isFalse,
      );
    } finally {
      await worker.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('serializes content work on the one long-lived worker', () async {
    final worker = await _startWorker();
    try {
      final first = worker.statusForTesting(
        delay: const Duration(milliseconds: 30),
      );
      final second = worker.normalizeContent(
        <SkillContentEntry>[
          SkillContentEntry.file(path: 'SKILL.md', bytes: const <int>[1]),
        ],
        maximumFileCount: maximumNormalizedSkillFileCount,
        maximumByteSize: maximumNormalizedSkillByteSize,
        isCancelled: () => false,
      );

      expect(worker.pendingRequestCount, 2);
      expect((await first).protocolVersion, revisionWorkerProtocolVersion);
      expect((await second).valueOrNull?.files, hasLength(1));
      expect(worker.pendingRequestCount, 0);
    } finally {
      await worker.close();
    }
  });

  test('pre-cancelled content work never enters the worker queue', () async {
    final worker = await _startWorker();
    try {
      final result = await worker.normalizeContent(
        <SkillContentEntry>[
          SkillContentEntry.file(path: 'SKILL.md', bytes: const <int>[1]),
        ],
        maximumFileCount: maximumNormalizedSkillFileCount,
        maximumByteSize: maximumNormalizedSkillByteSize,
        isCancelled: () => true,
      );

      expect(result.failureOrNull?.code.name, 'cancelled');
      expect(worker.pendingRequestCount, 0);
    } finally {
      await worker.close();
    }
  });

  test('owns pack, index, and canonical Bundle manifest work', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-worker-bundle-',
    );
    final repositoryPath = path.join(temporaryDirectory.path, 'store.git');
    final bundlePath = path.join(temporaryDirectory.path, 'bundle');
    final worker = await _startWorker();
    try {
      final normalized = await worker.normalizeContent(
        <SkillContentEntry>[
          SkillContentEntry.file(
            path: 'SKILL.md',
            bytes: utf8.encode('# Bundle\n'),
          ),
        ],
        maximumFileCount: maximumNormalizedSkillFileCount,
        maximumByteSize: maximumNormalizedSkillByteSize,
        isCancelled: () => false,
      );
      await worker.createStore(repositoryPath);
      final tree = await worker.writeTree(
        repositoryPath,
        normalized.valueOrNull!,
      );
      final commit = await worker.createCommit(
        repositoryPath,
        RevisionCommitRequest(
          tree: tree,
          parents: const <RevisionObjectId>[],
          kind: RevisionCommitKind.initial,
        ),
      );
      await Directory(bundlePath).create();
      final lineage = SourceLineageReference(
        '123e4567-e89b-42d3-a456-426614174700',
      );

      await worker.buildRevisionBundleArtifacts(
        repositoryPath: repositoryPath,
        bundlePath: bundlePath,
        sourceLineage: lineage,
        currentUpstream: commit,
        currentEffective: commit,
        retainedRoots: <RevisionObjectId>[commit],
      );
      await worker.verifyRevisionBundleArtifacts(
        bundlePath: bundlePath,
        sourceLineage: lineage,
        currentUpstream: commit,
        currentEffective: commit,
        retainedRoots: <RevisionObjectId>[commit],
      );

      for (final name in const <String>[
        'objects.pack',
        'objects.idx',
        'manifest.json',
        'COMPLETE',
      ]) {
        expect(
          await File(path.join(bundlePath, name)).length(),
          greaterThan(0),
        );
      }
    } finally {
      await worker.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'owns canonical materialization-manifest encoding and SHA-256',
    () async {
      final worker = await _startWorker();
      try {
        final encoded = await worker.encodeCanonicalManifest(
          value: <String, Object?>{'z': 2, 'a': 1},
          schemaVersion: 7,
        );

        expect(utf8.decode(encoded.manifestBytes), '{"a":1,"z":2}');
        final fence =
            jsonDecode(utf8.decode(encoded.completionFenceBytes))
                as Map<String, Object?>;
        expect(fence['schema'], 7);
        expect(fence['manifestSha256'], hasLength(64));
      } finally {
        await worker.close();
      }
    },
  );

  test('maps native failures without returning repository paths', () async {
    const privatePath = '/private/customer/revision-store.git';
    final worker = await _startWorker();
    try {
      Object? failure;
      try {
        await worker.verifyStore(privatePath);
      } on Object catch (error) {
        failure = error;
      }

      expect(
        failure,
        isA<RevisionEngineException>().having(
          (error) => error.code,
          'code',
          RevisionEngineFailureCode.storeUnavailable,
        ),
      );
      expect(failure.toString(), isNot(contains(privatePath)));
    } finally {
      await worker.close();
    }
  });
}

Matcher _hasCode(RevisionWorkerFailureCode code) {
  return isA<RevisionWorkerException>().having(
    (error) => error.code,
    'code',
    code,
  );
}

Future<RevisionWorker> _startWorker() =>
    RevisionWorker.start(taskExecutor: executeComposedRevisionWorkerTask);
