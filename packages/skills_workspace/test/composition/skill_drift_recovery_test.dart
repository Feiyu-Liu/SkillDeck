import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_operation_control_plane.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_recovery_bundle.dart';
import 'package:test/test.dart';

import '../support/operations/skill_drift_recovery_harness.dart';
import '../support/process/direct_dart_process.dart';

void main() {
  late Directory root;
  late WorkspaceLayout layout;
  late ManagedSkillId skillId;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('skill-drift-recovery-');
    layout = WorkspaceLayout(path.join(root.path, 'workspace'));
    skillId = await initializeSkillDriftRecovery(root.path);
  });
  tearDown(() async {
    if (!Platform.isWindows) {
      await Process.run('chmod', ['-R', 'u+w', root.path]);
    } else {
      await Process.run('attrib', [
        '-R',
        path.join(root.path, '*'),
        '/S',
        '/D',
      ]);
    }
    await root.delete(recursive: true);
  });

  test(
    'failure after replacement before BCP restores external bytes',
    () async {
      final result = await runSkillDriftRestoreRecovery(
        root: root.path,
        failBeforeCommit: true,
      );
      expect(result, isA<OperationRolledBack>());
      expect(
        await File(
          path.join(root.path, 'drift-before-commit-fault.marker'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          path.join(layout.repositoryCopyPath('recovery-sample'), 'SKILL.md'),
        ).readAsString(),
        skillDriftExternalBytes,
      );
      final database = WorkspaceDatabase.forFile(File(layout.databasePath));
      try {
        expect(
          (await database.workspaceMetadata.select().getSingle())
              .repositoryRevision,
          1,
        );
        final journals = await database.operationJournals.select().get();
        expect(
          journals.every((journal) => journal.phase == 'completed'),
          isTrue,
        );
      } finally {
        await database.close();
      }
      final repository = createSkillDriftRecoveryRepository(root.path);
      try {
        expect((await repository.open().completed).isSuccess, isTrue);
        expect(repository.snapshot.findSkill(skillId), isNotNull);
        expect(
          await File(
            path.join(layout.repositoryCopyPath('recovery-sample'), 'SKILL.md'),
          ).readAsString(),
          skillDriftExternalBytes,
        );
      } finally {
        await repository.close().completed;
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'process crash immediately after BCP rolls forward on first open',
    () async {
      final process = await Process.start(
        Platform.resolvedExecutable,
        directDartScriptArguments(
          'test/support/operations/skill_drift_recovery_crash_helper.dart',
          [root.path],
        ),
        workingDirectory: Directory.current.path,
      );
      // Drain output without exposing raw process diagnostics or Skill bytes.
      final stdout = process.stdout.drain<void>();
      final stderr = process.stderr.drain<void>();
      expect(await process.exitCode.timeout(const Duration(seconds: 60)), 71);
      await Future.wait([stdout, stderr]);
      final database = WorkspaceDatabase.forFile(File(layout.databasePath));
      try {
        final journaled = await DriftOperationControlPlane(
          database: database,
        ).loadRecoverableOperations();
        expect(journaled, hasLength(1));
        expect(journaled.single.phase, OperationJournalPhase.committed);
        expect(journaled.single.definition.record.kind, 'resolveSkillDrift');
        expect(
          (await database.workspaceMetadata.select().getSingle())
              .repositoryRevision,
          2,
        );
      } finally {
        await database.close();
      }
      final repository = createSkillDriftRecoveryRepository(root.path);
      try {
        final opened = await repository.open().completed;
        expect(
          opened.isSuccess,
          isTrue,
          reason: '${opened.failureOrNull?.code}',
        );
        expect(repository.snapshot.findSkill(skillId), isNotNull);
        expect(
          await File(
            path.join(layout.repositoryCopyPath('recovery-sample'), 'SKILL.md'),
          ).readAsString(),
          skillDriftOriginalBytes,
        );
        final history = await repository
            .inspectPublishedHistory(
              PublishedHistoryRequest(managedSkillId: skillId),
            )
            .completed;
        expect(history.isSuccess, isTrue);
        expect(history.valueOrNull?.revisions, hasLength(1));
      } finally {
        await repository.close().completed;
      }
      final reopenedDatabase = WorkspaceDatabase.forFile(
        File(layout.databasePath),
      );
      try {
        expect(
          await reopenedDatabase.operationJournals.select().get(),
          isEmpty,
        );
      } finally {
        await reopenedDatabase.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'keep failure before BCP preserves selection Bundle and clean Draft',
    () async {
      await ensureSkillDriftRecoveryCleanDraft(root.path, skillId);
      final beforeDatabase = WorkspaceDatabase.forFile(
        File(layout.databasePath),
      );
      late CurrentRevisionSelectionData beforeSelection;
      late DraftWorkspace beforeDraft;
      late int beforeRevision;
      try {
        beforeSelection = await beforeDatabase.currentRevisionSelection
            .select()
            .getSingle();
        beforeDraft = await beforeDatabase.draftWorkspaces.select().getSingle();
        beforeRevision =
            (await beforeDatabase.workspaceMetadata.select().getSingle())
                .repositoryRevision;
      } finally {
        await beforeDatabase.close();
      }
      final beforeBundle = await _bundleBytes(
        layout.revisionBundlePath(skillId),
      );
      final result = await runSkillDriftKeepRecovery(
        root: root.path,
        failBeforeCommit: true,
      );
      expect(result, isA<OperationRolledBack>());
      expect(
        await File(
          path.join(root.path, 'drift-before-commit-fault.marker'),
        ).exists(),
        isTrue,
      );
      expect(
        await _bundleBytes(layout.revisionBundlePath(skillId)),
        beforeBundle,
      );
      expect(
        await File(
          path.join(layout.repositoryCopyPath('recovery-sample'), 'SKILL.md'),
        ).readAsString(),
        skillDriftExternalBytes,
      );
      expect(
        await File(
          path.join(layout.draftPath(skillId), 'SKILL.md'),
        ).readAsString(),
        skillDriftOriginalBytes,
      );
      final afterDatabase = WorkspaceDatabase.forFile(
        File(layout.databasePath),
      );
      try {
        expect(
          await afterDatabase.currentRevisionSelection.select().getSingle(),
          beforeSelection,
        );
        expect(
          await afterDatabase.draftWorkspaces.select().getSingle(),
          beforeDraft,
        );
        expect(
          (await afterDatabase.workspaceMetadata.select().getSingle())
              .repositoryRevision,
          beforeRevision,
        );
      } finally {
        await afterDatabase.close();
      }
      final repository = createSkillDriftRecoveryRepository(root.path);
      try {
        expect((await repository.open().completed).isSuccess, isTrue);
        expect(repository.snapshot.findSkill(skillId)?.draft, isNotNull);
        final history = await repository
            .inspectPublishedHistory(
              PublishedHistoryRequest(managedSkillId: skillId),
            )
            .completed;
        expect(history.valueOrNull?.revisions, hasLength(1));
        expect(
          await File(
            path.join(layout.draftPath(skillId), 'SKILL.md'),
          ).readAsString(),
          skillDriftOriginalBytes,
        );
      } finally {
        await repository.close().completed;
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'keep crash after BCP rolls forward publication Bundle and Draft cleanup',
    () async {
      await ensureSkillDriftRecoveryCleanDraft(root.path, skillId);
      final beforeDatabase = WorkspaceDatabase.forFile(
        File(layout.databasePath),
      );
      late CurrentRevisionSelectionData beforeSelection;
      try {
        beforeSelection = await beforeDatabase.currentRevisionSelection
            .select()
            .getSingle();
      } finally {
        await beforeDatabase.close();
      }
      final beforeBundle = await _bundleBytes(
        layout.revisionBundlePath(skillId),
      );
      final process = await Process.start(
        Platform.resolvedExecutable,
        directDartScriptArguments(
          'test/support/operations/skill_drift_recovery_crash_helper.dart',
          [root.path, 'keep'],
        ),
        workingDirectory: Directory.current.path,
      );
      final stdout = process.stdout.drain<void>();
      final stderr = process.stderr.drain<void>();
      expect(await process.exitCode.timeout(const Duration(seconds: 60)), 71);
      await Future.wait([stdout, stderr]);
      final crashedDatabase = WorkspaceDatabase.forFile(
        File(layout.databasePath),
      );
      late CurrentRevisionSelectionData committedSelection;
      try {
        final journaled = await DriftOperationControlPlane(
          database: crashedDatabase,
        ).loadRecoverableOperations();
        expect(journaled, hasLength(1));
        expect(journaled.single.phase, OperationJournalPhase.committed);
        committedSelection = await crashedDatabase.currentRevisionSelection
            .select()
            .getSingle();
        expect(
          committedSelection.effectiveObjectId,
          isNot(beforeSelection.effectiveObjectId),
        );
        expect(
          committedSelection.upstreamObjectId,
          beforeSelection.upstreamObjectId,
        );
        expect(
          (await crashedDatabase.draftWorkspaces.select().getSingle())
              .baseObjectId,
          committedSelection.effectiveObjectId,
        );
        expect(await Directory(layout.draftPath(skillId)).exists(), isTrue);
      } finally {
        await crashedDatabase.close();
      }
      final repository = createSkillDriftRecoveryRepository(root.path);
      try {
        final opened = await repository.open().completed;
        expect(
          opened.isSuccess,
          isTrue,
          reason: '${opened.failureOrNull?.code}',
        );
        expect(repository.snapshot.findSkill(skillId)?.draft, isNull);
        expect(await Directory(layout.draftPath(skillId)).exists(), isFalse);
        expect(
          await File(
            path.join(layout.repositoryCopyPath('recovery-sample'), 'SKILL.md'),
          ).readAsString(),
          skillDriftExternalBytes,
        );
        final effective = await repository
            .readEffectiveFile(
              ReadEffectiveFileRequest(
                managedSkillId: skillId,
                relativePath: 'SKILL.md',
                expectedContentHash: repository.snapshot
                    .findSkill(skillId)!
                    .currentRevision
                    .contentHash,
              ),
            )
            .completed;
        expect(effective.isSuccess, isTrue);
        final history = await repository
            .inspectPublishedHistory(
              PublishedHistoryRequest(managedSkillId: skillId),
            )
            .completed;
        expect(history.valueOrNull?.revisions, hasLength(2));
        expect(
          history.valueOrNull?.revisions.first.kind,
          WorkspaceOperationKind.resolveSkillDrift,
        );
      } finally {
        await repository.close().completed;
      }
      expect(
        await _bundleBytes(layout.revisionBundlePath(skillId)),
        isNot(beforeBundle),
      );
      final bundlePath = layout.revisionBundlePath(skillId);
      final verifiedBundle = const RevisionRecoveryBundleCodec().verify(
        manifestBytes: await File(
          path.join(bundlePath, 'manifest.json'),
        ).readAsBytes(),
        completionFenceBytes: await File(
          path.join(bundlePath, 'COMPLETE'),
        ).readAsBytes(),
        packBytes: await File(
          path.join(bundlePath, 'objects.pack'),
        ).readAsBytes(),
        indexBytes: await File(
          path.join(bundlePath, 'objects.idx'),
        ).readAsBytes(),
      );
      expect(
        verifiedBundle.retainedPublishedRoots.map((id) => id.value),
        contains(committedSelection.effectiveObjectId),
      );
      expect(
        verifiedBundle.currentEffective.value,
        committedSelection.effectiveObjectId,
      );
      expect(
        verifiedBundle.currentUpstream.value,
        beforeSelection.upstreamObjectId,
      );
      final recoveredDatabase = WorkspaceDatabase.forFile(
        File(layout.databasePath),
      );
      try {
        expect(
          await recoveredDatabase.currentRevisionSelection.select().getSingle(),
          committedSelection,
        );
        expect(await recoveredDatabase.draftWorkspaces.select().get(), isEmpty);
        expect(
          await recoveredDatabase.operationJournals.select().get(),
          isEmpty,
        );
      } finally {
        await recoveredDatabase.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<Map<String, String>> _bundleBytes(String root) async {
  final hashes = <String, String>{};
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is File) {
      hashes[path.relative(entity.path, from: root)] = sha256
          .convert(await entity.readAsBytes())
          .toString();
    }
  }
  return hashes;
}
