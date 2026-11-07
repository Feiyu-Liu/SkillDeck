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
    test('real SQLite Removal recovers at ${crashPoint.name}', () async {
      final workspace = await Directory.systemTemp.createTemp(
        'skills-workspace-destructive-crash-',
      );
      addTearDown(() async {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      });

      await _forceCrash(workspace.path, crashPoint);
      final crashed = await inspectDestructiveSqliteCrashState(workspace.path);
      _expectCrashBoundary(crashed, crashPoint);

      final startup = await recoverDestructiveSqliteCrash(workspace.path);
      expect(startup, isNot(isA<ControlPlaneStartupBlocked>()));
      await _expectRecoveredState(workspace.path, crashPoint);
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  test(
    'corrupt primary restores only the verified post-Removal epoch',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'skills-workspace-same-epoch-crash-',
      );
      addTearDown(() async {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
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
      await _expectRemovedControlPlane(workspace.path);
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

Future<void> _forceCrash(
  String workspaceRoot,
  DestructiveSqliteCrashPoint crashPoint,
) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    directDartScriptArguments(
      'test/support/operations/destructive_sqlite_crash_helper.dart',
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
  DestructiveSqliteCrashState state,
  DestructiveSqliteCrashPoint point,
) {
  final preCommit =
      point == DestructiveSqliteCrashPoint.beforeBarrierPublication ||
      point == DestructiveSqliteCrashPoint.afterBarrierBeforeBusinessCommit;
  expect(state.repositoryRevision, preCommit ? 0 : 1);
  expect(state.destructionEpoch, preCommit ? 0 : 1);
  expect(state.managedSkillCount, preCommit ? 1 : 0);
  expect(state.sourceLineageCount, preCommit ? 1 : 0);
  expect(state.personalTagCount, 1);
  expect(state.skillTagAssignmentCount, preCommit ? 1 : 0);
  expect(state.operationSubjectCount, preCommit ? 1 : 0);
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
  final preCommit =
      point == DestructiveSqliteCrashPoint.beforeBarrierPublication ||
      point == DestructiveSqliteCrashPoint.afterBarrierBeforeBusinessCommit;
  final layout = WorkspaceLayout(workspaceRoot);
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  try {
    final metadata = await database.workspaceMetadata.select().getSingle();
    expect(metadata.repositoryRevision, preCommit ? 0 : 1);
    expect(metadata.destructionEpoch, preCommit ? 0 : 1);
    expect(await database.operationJournals.select().get(), isEmpty);
    expect(await database.personalTags.select().get(), hasLength(1));
    if (preCommit) {
      expect(await database.managedSkills.select().get(), hasLength(1));
      expect(await database.sourceLineages.select().get(), hasLength(1));
      expect(await database.skillTagAssignments.select().get(), hasLength(1));
      expect(await database.operationSubjects.select().get(), hasLength(2));
      expect(
        await File(
          path.join(layout.repositoryCopyPath('reviewer'), 'SKILL.md'),
        ).readAsString(),
        'old',
      );
    } else {
      expect(await database.managedSkills.select().get(), isEmpty);
      expect(await database.sourceLineages.select().get(), isEmpty);
      expect(await database.skillTagAssignments.select().get(), isEmpty);
      expect(await database.operationSubjects.select().get(), isEmpty);
      expect(
        await Directory(layout.repositoryCopyPath('reviewer')).exists(),
        isFalse,
      );
      expect(
        await Directory(
          layout.revisionStorePath(ManagedSkillId(destructiveCrashSkillId)),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(
          layout.revisionBundlePath(ManagedSkillId(destructiveCrashSkillId)),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(
          path.join(layout.controlPlaneBackupsRoot, '0'),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(
          path.join(layout.controlPlaneBackupsRoot, '1', '1'),
        ).exists(),
        isTrue,
      );
    }
  } finally {
    await database.close();
  }
}

Future<void> _expectRemovedControlPlane(String workspaceRoot) async {
  final database = WorkspaceDatabase.forFile(
    File(path.join(workspaceRoot, 'workspace.sqlite')),
  );
  try {
    final identity = await database.liveIdentity();
    expect(identity.repositoryRevision, 1);
    expect(identity.destructionEpoch, 1);
    expect(await database.managedSkills.select().get(), isEmpty);
    expect(await database.sourceLineages.select().get(), isEmpty);
    expect(await database.operationSubjects.select().get(), isEmpty);
    expect(await database.personalTags.select().get(), hasLength(1));
  } finally {
    await database.close();
  }
}
