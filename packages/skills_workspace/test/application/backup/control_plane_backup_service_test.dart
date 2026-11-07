import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/backup/control_plane_backup_codec.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_service.dart';
import 'package:skills_workspace/src/application/ports/control_plane_backup_ports.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/platform/filesystem/control_plane_backup_durability.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late WorkspaceLayout layout;
  late _FakeControlPlaneDatabase database;
  late PlatformControlPlaneBackupDurability platformDurability;
  late ControlPlaneBackupService service;
  var timestamp = 0;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-control-plane-backup-',
    );
    layout = WorkspaceLayout(temporary.path);
    database = _FakeControlPlaneDatabase(
      primaryPath: layout.databasePath,
      identity: const ControlPlaneIdentity(
        schemaVersion: 1,
        repositoryRevision: 1,
        destructionEpoch: 0,
      ),
    );
    await database.writePrimary();
    platformDurability = PlatformControlPlaneBackupDurability(
      PlatformDurableWorkspaceFilesystem(),
    );
    service = _service(
      database: database,
      durability: platformDurability,
      layout: layout,
      clock: () => ++timestamp,
    );
    await service.initializeSteadyEligibility();
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('publishes canonical revision paths and retains latest three', () async {
    for (var revision = 1; revision <= 4; revision += 1) {
      database.identity = ControlPlaneIdentity(
        schemaVersion: 1,
        repositoryRevision: revision,
        destructionEpoch: 0,
      );
      await database.writePrimary();
      await service.createBackup();
    }

    final backups = await service.verifiedBackupsForEpoch(0);
    expect(
      backups.map((backup) => backup.manifest.identity.repositoryRevision),
      [4, 3, 2],
    );
    expect(backups.map((backup) => path.basename(backup.directoryPath)), [
      '4',
      '3',
      '2',
    ]);
    expect(
      Directory(
        layout.controlPlaneBackupPath(
          destructionEpoch: 0,
          repositoryRevision: RepositoryRevision(1),
        ),
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'corrupt and incomplete backup generations are never eligible',
    () async {
      await service.createBackup();
      final backupDirectory = layout.controlPlaneBackupPath(
        destructionEpoch: 0,
        repositoryRevision: RepositoryRevision(1),
      );
      await File(
        path.join(backupDirectory, 'manifest.json'),
      ).writeAsString('corrupt');
      final incomplete = Directory(
        path.join(layout.controlPlaneBackupsRoot, '0', '2'),
      );
      await incomplete.create(recursive: true);
      await File(
        path.join(incomplete.path, 'workspace.sqlite'),
      ).writeAsString('incomplete');

      expect(await service.verifiedBackupsForEpoch(0), isEmpty);
    },
  );

  test(
    'restores the highest verified revision from the steady epoch',
    () async {
      for (var revision = 1; revision <= 3; revision += 1) {
        database.identity = ControlPlaneIdentity(
          schemaVersion: 1,
          repositoryRevision: revision,
          destructionEpoch: 0,
        );
        await database.writePrimary();
        await service.createBackup();
      }
      final newestDatabase = File(
        path.join(
          layout.controlPlaneBackupPath(
            destructionEpoch: 0,
            repositoryRevision: RepositoryRevision(3),
          ),
          'workspace.sqlite',
        ),
      );
      await newestDatabase.writeAsString('corrupt');
      await File(layout.databasePath).writeAsString('corrupt-primary');
      await File('${layout.databasePath}-wal').writeAsString('stale-wal');
      await File('${layout.databasePath}-shm').writeAsString('stale-shm');

      final result = await service.recoverPrimaryForStartup();

      expect(result, isA<ControlPlanePrimaryRestored>());
      expect(
        (result as ControlPlanePrimaryRestored).identity.repositoryRevision,
        2,
      );
      expect(
        (await database.probeDatabase(
                  layout.databasePath,
                  integrityLevel: ControlPlaneIntegrityLevel.full,
                )
                as ControlPlaneHealthy)
            .identity
            .repositoryRevision,
        2,
      );
      expect(File('${layout.databasePath}-wal').existsSync(), isFalse);
      expect(File('${layout.databasePath}-shm').existsSync(), isFalse);
    },
  );

  test(
    'invalid eligibility fence blocks startup even with a primary',
    () async {
      await File(layout.backupEligibilityPath).writeAsString('invalid');

      final result = await service.recoverPrimaryForStartup();

      expect(
        result,
        isA<ControlPlaneStartupBlocked>().having(
          (value) => value.code,
          'code',
          ControlPlaneBackupFailureCode.invalidEligibilityFence,
        ),
      );
    },
  );

  test(
    'armed barrier requires Journal proof and fails closed on corruption',
    () async {
      await service.createBackup();
      await service.armDestructiveBarrier(
        operationId: 'remove-1',
        expectedIdentity: database.identity,
      );

      expect(
        await service.recoverPrimaryForStartup(),
        isA<ControlPlaneArmedBarrierNeedsResolution>(),
      );
      await File(layout.databasePath).writeAsString('corrupt-primary');
      final blocked = await service.recoverPrimaryForStartup();
      expect(
        blocked,
        isA<ControlPlaneStartupBlocked>().having(
          (value) => value.code,
          'code',
          ControlPlaneBackupFailureCode.destructiveBarrierArmed,
        ),
      );
    },
  );

  test('proven pre-commit rollback restores the prior steady fence', () async {
    await service.createBackup();
    await service.armDestructiveBarrier(
      operationId: 'replace-1',
      expectedIdentity: database.identity,
    );

    final steady = await service.restoreSteadyAfterProvenRollback(
      operationId: 'replace-1',
    );

    expect(steady.destructionEpoch, 0);
    expect(steady.establishedAtRepositoryRevision, 0);
    expect(
      await service.recoverPrimaryForStartup(),
      isA<ControlPlanePrimaryReady>(),
    );
  });

  test(
    'pre-commit rollback retains steady when armed publication never landed',
    () async {
      await service.createBackup();

      final steady = await service.restoreSteadyAfterProvenRollback(
        operationId: 'remove-before-barrier-publication',
      );

      expect(steady.destructionEpoch, 0);
      expect(steady.establishedAtRepositoryRevision, 0);
      expect(
        await service.recoverPrimaryForStartup(),
        isA<ControlPlanePrimaryReady>(),
      );
    },
  );

  test(
    'post-commit finalization resumes after the steady-fence boundary',
    () async {
      await service.createBackup();
      await service.armDestructiveBarrier(
        operationId: 'remove-1',
        expectedIdentity: database.identity,
      );
      database.identity = const ControlPlaneIdentity(
        schemaVersion: 1,
        repositoryRevision: 2,
        destructionEpoch: 1,
      );
      await database.writePrimary();
      final faulting = _FailOldEpochRemovalOnce(
        delegate: platformDurability,
        oldEpochPath: path.join(layout.controlPlaneBackupsRoot, '0'),
      );
      final faultingService = _service(
        database: database,
        durability: faulting,
        layout: layout,
        clock: () => ++timestamp,
      );

      await expectLater(
        faultingService.completeCommittedDestruction(operationId: 'remove-1'),
        throwsA(isA<FileSystemException>()),
      );
      final eligibility = const ControlPlaneBackupCodec().decodeEligibility(
        await File(layout.backupEligibilityPath).readAsBytes(),
      );
      expect(eligibility, isA<SteadyBackupEligibility>());
      expect(Directory(faulting.oldEpochPath).existsSync(), isTrue);

      final resumed = await faultingService.completeCommittedDestruction(
        operationId: 'remove-1',
      );

      expect(resumed.manifest.identity.destructionEpoch, 1);
      expect(Directory(faulting.oldEpochPath).existsSync(), isFalse);
    },
  );

  test(
    'ordinary backup creation is rejected while destruction is armed',
    () async {
      await service.armDestructiveBarrier(
        operationId: 'remove-1',
        expectedIdentity: database.identity,
      );

      await expectLater(
        service.createBackup(),
        throwsA(
          isA<ControlPlaneBackupException>().having(
            (error) => error.code,
            'code',
            ControlPlaneBackupFailureCode.eligibilityMismatch,
          ),
        ),
      );
    },
  );
}

ControlPlaneBackupService _service({
  required _FakeControlPlaneDatabase database,
  required ControlPlaneBackupDurabilityPort durability,
  required WorkspaceLayout layout,
  required ControlPlaneClock clock,
}) => ControlPlaneBackupService(
  database: database,
  durability: durability,
  paths: ControlPlaneBackupPaths(
    workspaceRoot: layout.rootPath,
    primaryDatabasePath: layout.databasePath,
    backupRoot: layout.controlPlaneBackupsRoot,
    eligibilityPath: layout.backupEligibilityPath,
  ),
  clock: clock,
);

final class _FakeControlPlaneDatabase
    implements ControlPlaneBackupDatabasePort {
  _FakeControlPlaneDatabase({
    required this.primaryPath,
    required this.identity,
  });

  final String primaryPath;
  ControlPlaneIdentity identity;

  Future<void> writePrimary() => _writeDatabase(primaryPath, identity);

  @override
  Future<ControlPlaneIdentity> liveIdentity() async => identity;

  @override
  Future<void> vacuumInto(String destinationPath) async {
    if (await File(destinationPath).exists()) {
      throw StateError('VACUUM INTO destination already exists.');
    }
    await _writeDatabase(destinationPath, identity);
  }

  @override
  Future<ControlPlaneProbeResult> probeDatabase(
    String databasePath, {
    required ControlPlaneIntegrityLevel integrityLevel,
  }) async {
    final file = File(databasePath);
    if (!await file.exists()) {
      return const ControlPlaneUnusable(ControlPlaneProbeFailureReason.missing);
    }
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, Object?>) throw const FormatException();
      final probed = ControlPlaneIdentity(
        schemaVersion: value['schemaVersion']! as int,
        repositoryRevision: value['repositoryRevision']! as int,
        destructionEpoch: value['destructionEpoch']! as int,
      );
      if (probed.schemaVersion != 1) {
        return const ControlPlaneUnusable(
          ControlPlaneProbeFailureReason.schemaMismatch,
        );
      }
      return ControlPlaneHealthy(probed);
    } on Object {
      return const ControlPlaneUnusable(
        ControlPlaneProbeFailureReason.integrityCheckFailed,
      );
    }
  }
}

Future<void> _writeDatabase(
  String targetPath,
  ControlPlaneIdentity identity,
) async {
  await Directory(path.dirname(targetPath)).create(recursive: true);
  await File(targetPath).writeAsString(
    jsonEncode(<String, Object>{
      'schemaVersion': identity.schemaVersion,
      'repositoryRevision': identity.repositoryRevision,
      'destructionEpoch': identity.destructionEpoch,
    }),
    flush: true,
  );
}

final class _FailOldEpochRemovalOnce
    implements ControlPlaneBackupDurabilityPort {
  _FailOldEpochRemovalOnce({
    required this.delegate,
    required this.oldEpochPath,
  });

  final ControlPlaneBackupDurabilityPort delegate;
  final String oldEpochPath;
  bool _shouldFail = true;

  @override
  Future<void> removeOwnedPath({
    required String targetPath,
    required String ownerRoot,
  }) {
    if (_shouldFail &&
        path.equals(path.normalize(targetPath), path.normalize(oldEpochPath))) {
      _shouldFail = false;
      throw FileSystemException(
        'Injected old-epoch cleanup failure.',
        targetPath,
      );
    }
    return delegate.removeOwnedPath(
      targetPath: targetPath,
      ownerRoot: ownerRoot,
    );
  }

  @override
  Future<void> copyDurableFile({
    required String sourcePath,
    required String destinationPath,
  }) => delegate.copyDurableFile(
    sourcePath: sourcePath,
    destinationPath: destinationPath,
  );

  @override
  Future<String> createSiblingStagingPath(
    String destinationPath, {
    required ControlPlaneStagingKind kind,
  }) => delegate.createSiblingStagingPath(destinationPath, kind: kind);

  @override
  Future<bool> exists(String targetPath) => delegate.exists(targetPath);

  @override
  Future<int> fileSize(String filePath) => delegate.fileSize(filePath);

  @override
  Future<List<String>> listChildDirectories(String parentPath) =>
      delegate.listChildDirectories(parentPath);

  @override
  Future<void> publish({
    required String candidatePath,
    required String destinationPath,
    required ControlPlaneStagingKind kind,
    required ControlPlanePathVerifier verify,
  }) => delegate.publish(
    candidatePath: candidatePath,
    destinationPath: destinationPath,
    kind: kind,
    verify: verify,
  );

  @override
  Future<List<int>> readFile(String filePath) => delegate.readFile(filePath);

  @override
  Future<String> sha256File(String filePath) => delegate.sha256File(filePath);

  @override
  Future<void> writeDurableFile(String filePath, List<int> bytes) =>
      delegate.writeDurableFile(filePath, bytes);
}
