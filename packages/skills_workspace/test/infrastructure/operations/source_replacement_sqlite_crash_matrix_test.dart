import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_process.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

import '../../support/operations/destructive_sqlite_crash_harness.dart';
import '../../support/process/direct_dart_process.dart';

void main() {
  for (final crashPoint in DestructiveSqliteCrashPoint.values) {
    test(
      'real SQLite Source Replacement recovers at ${crashPoint.name}',
      () async {
        final workspace = await Directory.systemTemp.createTemp(
          'skills-workspace-source-replacement-crash-',
        );
        addTearDown(() async {
          await _deleteWorkspace(workspace);
        });

        await _forceCrash(workspace.path, crashPoint);
        final crashed = await inspectSourceReplacementSqliteCrashState(
          workspace.path,
        );
        _expectCrashBoundary(crashed, crashPoint);
        await _expectCrashFilesystemBoundary(workspace.path, crashPoint);

        final startup = await recoverDestructiveSqliteCrash(workspace.path);
        expect(startup, isNot(isA<ControlPlaneStartupBlocked>()));
        await _expectRecoveredState(workspace.path, crashPoint);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  test(
    'corrupt primary restores only the verified post-replacement lineage',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'skills-workspace-source-replacement-same-epoch-',
      );
      addTearDown(() async {
        await _deleteWorkspace(workspace);
      });
      await _forceCrash(
        workspace.path,
        DestructiveSqliteCrashPoint.afterBusinessCommitBeforeBackup,
      );
      await recoverDestructiveSqliteCrash(workspace.path);

      final restored = await corruptPrimaryAndRestoreSameEpoch(workspace.path);

      expect(
        restored,
        isA<ControlPlanePrimaryRestored>()
            .having(
              (value) => value.identity.destructionEpoch,
              'destructionEpoch',
              1,
            )
            .having(
              (value) => value.identity.repositoryRevision,
              'repositoryRevision',
              1,
            ),
      );
      await _expectReplacementControlPlane(workspace.path);
      expect(
        await Directory(
          path.join(workspace.path, 'control-plane-backups', '0'),
        ).exists(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

Future<void> _expectCrashFilesystemBoundary(
  String workspaceRoot,
  DestructiveSqliteCrashPoint point,
) async {
  final layout = WorkspaceLayout(workspaceRoot);
  final preCommit = _isPreCommit(point);
  final expectedMaterialization = preCommit ? 'old' : 'new';
  expect(
    await File(
      path.join(layout.repositoryCopyPath('reviewer'), 'SKILL.md'),
    ).readAsString(),
    expectedMaterialization,
  );
  expect(
    await File(
      path.join(layout.rootPath, 'agent-skills', 'reviewer', 'SKILL.md'),
    ).readAsString(),
    expectedMaterialization,
  );
  expect(
    await Directory(
      layout.revisionStorePath(ManagedSkillId(destructiveCrashSkillId)),
    ).exists(),
    isTrue,
  );
  expect(
    await Directory(
      layout.revisionBundlePath(ManagedSkillId(destructiveCrashSkillId)),
    ).exists(),
    isTrue,
  );
}

Future<void> _forceCrash(
  String workspaceRoot,
  DestructiveSqliteCrashPoint crashPoint,
) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    directDartScriptArguments(
      'test/support/operations/source_replacement_sqlite_crash_helper.dart',
      <String>[workspaceRoot, crashPoint.name],
    ),
    workingDirectory: Directory.current.path,
    environment: Platform.environment,
    includeParentEnvironment: false,
    runInShell: false,
  );
  final stderr = StringBuffer();
  final stdout = StringBuffer();
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .listen(stderr.write);
  final stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .listen(stdout.write);
  try {
    final reached = await Future.any<bool>(<Future<bool>>[
      waitForDestructiveCrashMarker(
        workspaceRoot,
        crashPoint,
      ).then((_) => true),
      process.exitCode.then((_) => false),
    ]);
    if (!reached) {
      throw StateError(
        'Crash helper exited before ${crashPoint.name}. '
        'stdout=$stdout stderr=$stderr',
      );
    }
    await _terminateCrashHelper(process);
  } finally {
    try {
      if (await _stillRunning(process)) {
        await _terminateCrashHelper(process);
      }
    } finally {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    }
  }
}

Future<void> _terminateCrashHelper(Process process) async {
  await PlatformGitProcessTreeTerminator.current().terminate(process.pid);
  await process.exitCode.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
}

Future<bool> _stillRunning(Process process) async {
  try {
    await process.exitCode.timeout(const Duration(milliseconds: 1));
    return false;
  } on TimeoutException {
    return true;
  }
}

void _expectCrashBoundary(
  SourceReplacementSqliteCrashState state,
  DestructiveSqliteCrashPoint point,
) {
  final preCommit = _isPreCommit(point);
  expect(state.repositoryRevision, preCommit ? 0 : 1);
  expect(state.destructionEpoch, preCommit ? 0 : 1);
  _expectBusinessState(state, replacementCommitted: !preCommit);
  expect(state.personalTagCount, 1);
  expect(state.skillTagAssignmentCount, 1);
  expect(state.activationCount, 1);
  expect(state.activationAgentCount, 1);
  switch (point) {
    case DestructiveSqliteCrashPoint.beforeBarrierPublication:
      expect(state.epochZeroBackupExists, isTrue);
      expect(state.journalPhase, OperationJournalPhase.prepared);
      expect(state.eligibility, isA<SteadyBackupEligibility>());
      expect(state.epochOneBackupExists, isFalse);
    case DestructiveSqliteCrashPoint.afterBarrierBeforeBusinessCommit:
      expect(state.epochZeroBackupExists, isTrue);
      expect(state.journalPhase, OperationJournalPhase.prepared);
      expect(state.eligibility, isA<ArmedBackupEligibility>());
      expect(state.epochOneBackupExists, isFalse);
    case DestructiveSqliteCrashPoint.afterBusinessCommitBeforeBackup:
      expect(state.epochZeroBackupExists, isTrue);
      expect(state.journalPhase, OperationJournalPhase.committed);
      expect(state.eligibility, isA<ArmedBackupEligibility>());
      expect(state.epochOneBackupExists, isFalse);
    case DestructiveSqliteCrashPoint.afterNewBackupBeforeSteadyFence:
      expect(state.epochZeroBackupExists, isTrue);
      expect(state.journalPhase, OperationJournalPhase.finalizing);
      expect(state.eligibility, isA<ArmedBackupEligibility>());
      expect(state.epochOneBackupExists, isTrue);
    case DestructiveSqliteCrashPoint.beforeJournalCompletion:
      expect(state.journalPhase, OperationJournalPhase.finalizing);
      expect(
        state.eligibility,
        isA<SteadyBackupEligibility>().having(
          (value) => value.destructionEpoch,
          'destructionEpoch',
          1,
        ),
      );
      expect(state.epochZeroBackupExists, isFalse);
      expect(state.epochOneBackupExists, isTrue);
  }
}

Future<void> _expectRecoveredState(
  String workspaceRoot,
  DestructiveSqliteCrashPoint point,
) async {
  final replacementCommitted = !_isPreCommit(point);
  final layout = WorkspaceLayout(workspaceRoot);
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  try {
    final metadata = await database.workspaceMetadata.select().getSingle();
    expect(metadata.repositoryRevision, replacementCommitted ? 1 : 0);
    expect(metadata.destructionEpoch, replacementCommitted ? 1 : 0);
    expect(await database.operationJournals.select().get(), isEmpty);
    expect(await database.managedSkills.select().get(), hasLength(1));
    final userData = await database.skillUserData.select().getSingle();
    expect(userData.favorite, isTrue);
    expect(userData.note, 'Important');
    expect(await database.personalTags.select().get(), hasLength(1));
    expect(await database.skillTagAssignments.select().get(), hasLength(1));
    expect(await database.activationLocations.select().get(), hasLength(1));
    expect(await database.activationAgents.select().get(), hasLength(1));
    final subjects = await database.operationSubjects.select().get();
    expect(subjects, hasLength(1));
    expect(
      subjects.single.sourceLineageId,
      replacementCommitted
          ? sourceReplacementCrashLineageId
          : destructiveCrashLineageId,
    );

    final expectedBytes = replacementCommitted ? 'new' : 'old';
    expect(
      await File(
        path.join(layout.repositoryCopyPath('reviewer'), 'SKILL.md'),
      ).readAsString(),
      expectedBytes,
    );
    expect(
      await File(
        path.join(layout.rootPath, 'agent-skills', 'reviewer', 'SKILL.md'),
      ).readAsString(),
      expectedBytes,
    );

    final store = Directory(
      layout.revisionStorePath(ManagedSkillId(destructiveCrashSkillId)),
    );
    final bundle = Directory(
      layout.revisionBundlePath(ManagedSkillId(destructiveCrashSkillId)),
    );
    expect(await store.exists(), isTrue);
    expect(await bundle.exists(), isTrue);

    expect(
      await Directory(path.join(layout.controlPlaneBackupsRoot, '0')).exists(),
      !replacementCommitted,
    );
    expect(
      await Directory(
        path.join(layout.controlPlaneBackupsRoot, '1', '1'),
      ).exists(),
      replacementCommitted,
    );
  } finally {
    await database.close();
  }
}

Future<void> _expectReplacementControlPlane(String workspaceRoot) async {
  final state = await inspectSourceReplacementSqliteCrashState(workspaceRoot);
  expect(state.repositoryRevision, 1);
  expect(state.destructionEpoch, 1);
  _expectBusinessState(state, replacementCommitted: true);
  expect(state.personalTagCount, 1);
  expect(state.skillTagAssignmentCount, 1);
  expect(state.activationCount, 1);
  expect(state.activationAgentCount, 1);
}

void _expectBusinessState(
  SourceReplacementSqliteCrashState state, {
  required bool replacementCommitted,
}) {
  final expectedLineage = replacementCommitted
      ? sourceReplacementCrashLineageId
      : destructiveCrashLineageId;
  final expectedObject = replacementCommitted
      ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
      : 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  expect(state.activeSourceLineageId, expectedLineage);
  expect(state.sourceLineageIds, [expectedLineage]);
  expect(state.sourcePayloads, [
    replacementCommitted
        ? '{"path":"/skills/reviewer-new"}'
        : '{"path":"/skills/reviewer"}',
  ]);
  expect(state.selectedSourceLineageId, expectedLineage);
  expect(state.upstreamObjectId, expectedObject);
  expect(state.effectiveObjectId, expectedObject);
  expect(state.favorite, isTrue);
  expect(state.note, 'Important');
  expect(state.operationSubjectLineageIds, [
    if (!replacementCommitted) destructiveCrashLineageId,
  ]);
}

bool _isPreCommit(DestructiveSqliteCrashPoint point) =>
    point == DestructiveSqliteCrashPoint.beforeBarrierPublication ||
    point == DestructiveSqliteCrashPoint.afterBarrierBeforeBusinessCommit;

Future<void> _deleteWorkspace(Directory workspace) async {
  if (!await workspace.exists()) return;
  try {
    await workspace.delete(recursive: true);
  } on FileSystemException {
    final result = Platform.isWindows
        ? await Process.run('attrib', <String>[
            '-R',
            path.join(workspace.path, '*'),
            '/S',
            '/D',
          ])
        : await Process.run('chmod', <String>['-R', 'u+w', workspace.path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Failed to make crash-test workspace writable.',
        workspace.path,
      );
    }
    await workspace.delete(recursive: true);
  }
}
