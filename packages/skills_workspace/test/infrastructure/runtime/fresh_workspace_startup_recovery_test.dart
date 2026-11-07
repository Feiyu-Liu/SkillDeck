import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_service.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/runtime/fresh_workspace_startup_recovery.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/platform/filesystem/control_plane_backup_durability.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late WorkspaceLayout layout;
  late WorkspaceDatabase probeDatabase;
  late ControlPlaneBackupService backup;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('fresh-workspace-');
    layout = WorkspaceLayout(path.join(temporary.path, 'workspace'));
    await Directory(layout.rootPath).create(recursive: true);
    await File(layout.runtimeOwnershipLockPath).writeAsString('ownership');
    await File(layout.operationWriterLockPath).writeAsString('writer');
    probeDatabase = WorkspaceDatabase.forFile(File(layout.databasePath));
    backup = ControlPlaneBackupService(
      database: probeDatabase,
      durability: PlatformControlPlaneBackupDurability(
        PlatformDurableWorkspaceFilesystem(),
      ),
      paths: ControlPlaneBackupPaths(
        workspaceRoot: layout.rootPath,
        primaryDatabasePath: layout.databasePath,
        backupRoot: layout.controlPlaneBackupsRoot,
        eligibilityPath: layout.backupEligibilityPath,
      ),
    );
  });

  tearDown(() async {
    await probeDatabase.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('creates schema v3 only for a genuinely empty Workspace', () async {
    var initializations = 0;
    final recovery = FreshWorkspaceStartupRecovery(
      layout: layout,
      establishedRecovery: backup,
      initializeEmptyControlPlane: () async {
        initializations += 1;
        return probeDatabase.liveIdentity();
      },
      abandonInitializedControlPlane: probeDatabase.close,
    );

    final result = await recovery.recoverPrimaryForStartup();

    expect(result, isA<ControlPlanePrimaryReady>());
    expect(initializations, 1);
    expect(await File(layout.databasePath).exists(), isTrue);
    expect(await File(layout.backupEligibilityPath).exists(), isTrue);
  });

  test('never reinitializes an established Workspace', () async {
    await probeDatabase.liveIdentity();
    await backup.initializeSteadyEligibility();
    var initializations = 0;
    final recovery = FreshWorkspaceStartupRecovery(
      layout: layout,
      establishedRecovery: backup,
      initializeEmptyControlPlane: () async {
        initializations += 1;
        return const ControlPlaneIdentity(
          schemaVersion: 1,
          repositoryRevision: 0,
          destructionEpoch: 0,
        );
      },
      abandonInitializedControlPlane: probeDatabase.close,
    );

    final result = await recovery.recoverPrimaryForStartup();

    expect(result, isA<ControlPlanePrimaryReady>());
    expect(initializations, 0);
  });

  test('missing authority in a non-empty root fails closed', () async {
    await File(
      path.join(layout.rootPath, 'orphaned-artifact'),
    ).writeAsString('x');
    var initializations = 0;
    final recovery = FreshWorkspaceStartupRecovery(
      layout: layout,
      establishedRecovery: backup,
      initializeEmptyControlPlane: () async {
        initializations += 1;
        return const ControlPlaneIdentity(
          schemaVersion: 1,
          repositoryRevision: 0,
          destructionEpoch: 0,
        );
      },
      abandonInitializedControlPlane: probeDatabase.close,
    );

    final result = await recovery.recoverPrimaryForStartup();

    expect(
      result,
      isA<ControlPlaneStartupBlocked>().having(
        (value) => value.code,
        'code',
        ControlPlaneBackupFailureCode.invalidEligibilityFence,
      ),
    );
    expect(initializations, 0);
    expect(await File(layout.databasePath).exists(), isFalse);
  });
}
