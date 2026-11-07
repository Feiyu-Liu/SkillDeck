import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_service.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/platform/filesystem/control_plane_backup_durability.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';

void main() {
  test(
    'startup restores a verified backup after real SQLite WAL corruption',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'skills-workspace-wal-recovery-',
      );
      final layout = WorkspaceLayout(path.join(temporary.path, 'workspace'));
      WorkspaceDatabase? primary;
      WorkspaceDatabase? walSource;
      WorkspaceDatabase? probe;
      try {
        primary = WorkspaceDatabase.forFile(File(layout.databasePath));
        await primary.liveIdentity();
        final durability = PlatformControlPlaneBackupDurability(
          PlatformDurableWorkspaceFilesystem(),
        );
        final paths = ControlPlaneBackupPaths(
          workspaceRoot: layout.rootPath,
          primaryDatabasePath: layout.databasePath,
          backupRoot: layout.controlPlaneBackupsRoot,
          eligibilityPath: layout.backupEligibilityPath,
        );
        final backups = ControlPlaneBackupService(
          database: primary,
          durability: durability,
          paths: paths,
        );
        await backups.initializeSteadyEligibility();
        await backups.createBackup();
        await primary.close();
        primary = null;

        final sourcePath = path.join(temporary.path, 'wal-source.sqlite');
        walSource = WorkspaceDatabase.forFile(File(sourcePath));
        await walSource.liveIdentity();
        await walSource.transactionAtRevision(0, () async {});
        final sourceWal = File('$sourcePath-wal');
        final sourceShm = File('$sourcePath-shm');
        expect(await sourceWal.exists(), isTrue);
        expect(await sourceShm.exists(), isTrue);
        await File(sourcePath).copy(layout.databasePath);
        await sourceWal.copy('${layout.databasePath}-wal');
        await sourceShm.copy('${layout.databasePath}-shm');
        final walBytes = await File('${layout.databasePath}-wal').readAsBytes();
        expect(walBytes.length, greaterThan(160));
        walBytes[160] ^= 0xff;
        await File(
          '${layout.databasePath}-wal',
        ).writeAsBytes(walBytes, flush: true);
        await walSource.close();
        walSource = null;

        probe = WorkspaceDatabase.forFile(
          File(path.join(temporary.path, 'probe-anchor.sqlite')),
        );
        expect(
          await probe.probeDatabase(
            layout.databasePath,
            integrityLevel: ControlPlaneIntegrityLevel.quick,
          ),
          isA<ControlPlaneUnusable>(),
        );
        final recovery = ControlPlaneBackupService(
          database: probe,
          durability: durability,
          paths: paths,
        );

        final result = await recovery.recoverPrimaryForStartup();

        expect(result, isA<ControlPlanePrimaryRestored>());
        expect(
          (result as ControlPlanePrimaryRestored).identity.repositoryRevision,
          0,
        );
        expect(await File('${layout.databasePath}-wal').exists(), isFalse);
        expect(await File('${layout.databasePath}-shm').exists(), isFalse);
        expect(
          await probe.probeDatabase(
            layout.databasePath,
            integrityLevel: ControlPlaneIntegrityLevel.full,
          ),
          isA<ControlPlaneHealthy>(),
        );
      } finally {
        await primary?.close();
        await walSource?.close();
        await probe?.close();
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      }
    },
  );
}
