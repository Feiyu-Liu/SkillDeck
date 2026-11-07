import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late String primaryPath;
  late WorkspaceDatabase database;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-control-plane-db-',
    );
    primaryPath = path.join(temporary.path, 'workspace.sqlite');
    database = WorkspaceDatabase.forFile(File(primaryPath));
    await database.select(database.workspaceMetadata).getSingle();
  });

  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  test('reports live relational identity', () async {
    final identity = await database.liveIdentity();

    expect(identity.schemaVersion, workspaceDatabaseSchemaVersion);
    expect(identity.repositoryRevision, 0);
    expect(identity.destructionEpoch, 0);
  });

  test('VACUUM INTO creates an independently verified full backup', () async {
    final backupPath = path.join(temporary.path, 'backup.sqlite');

    await database.vacuumInto(backupPath);
    final result = await database.probeDatabase(
      backupPath,
      integrityLevel: ControlPlaneIntegrityLevel.full,
    );

    expect(result, isA<ControlPlaneHealthy>());
    expect(
      (result as ControlPlaneHealthy).identity,
      await database.liveIdentity(),
    );
    await expectLater(
      database.vacuumInto(backupPath),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('probe does not create a missing database', () async {
    final missing = path.join(temporary.path, 'missing.sqlite');

    final result = await database.probeDatabase(
      missing,
      integrityLevel: ControlPlaneIntegrityLevel.quick,
    );

    expect(
      result,
      isA<ControlPlaneUnusable>().having(
        (value) => value.reason,
        'reason',
        ControlPlaneProbeFailureReason.missing,
      ),
    );
    expect(await File(missing).exists(), isFalse);
  });

  test('database paths reject an existing non-file entry', () async {
    final directoryPath = path.join(temporary.path, 'not-a-database');
    await Directory(directoryPath).create();

    await expectLater(
      database.vacuumInto(directoryPath),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      await database.probeDatabase(
        directoryPath,
        integrityLevel: ControlPlaneIntegrityLevel.quick,
      ),
      isA<ControlPlaneUnusable>().having(
        (value) => value.reason,
        'reason',
        ControlPlaneProbeFailureReason.cannotOpen,
      ),
    );
  });

  test(
    'probe rejects a schema version mismatch without migrating it',
    () async {
      final backupPath = path.join(temporary.path, 'wrong-schema.sqlite');
      await database.vacuumInto(backupPath);
      final raw = sqlite.sqlite3.open(backupPath);
      raw.execute('PRAGMA user_version = 99');
      raw.close();

      final result = await database.probeDatabase(
        backupPath,
        integrityLevel: ControlPlaneIntegrityLevel.quick,
      );

      expect(
        result,
        isA<ControlPlaneUnusable>().having(
          (value) => value.reason,
          'reason',
          ControlPlaneProbeFailureReason.schemaMismatch,
        ),
      );
      final reopened = sqlite.sqlite3.open(backupPath);
      expect(reopened.userVersion, 99);
      reopened.close();
    },
  );

  test('probe rejects foreign-key violations', () async {
    final backupPath = path.join(temporary.path, 'foreign-key.sqlite');
    await database.vacuumInto(backupPath);
    final raw = sqlite.sqlite3.open(backupPath);
    raw.execute('PRAGMA foreign_keys = OFF');
    raw.execute(
      "INSERT INTO activation_agents "
      "(activation_location_id, agent_id) VALUES ('missing', 'claude')",
    );
    raw.close();

    final result = await database.probeDatabase(
      backupPath,
      integrityLevel: ControlPlaneIntegrityLevel.full,
    );

    expect(
      result,
      isA<ControlPlaneUnusable>().having(
        (value) => value.reason,
        'reason',
        ControlPlaneProbeFailureReason.foreignKeyCheckFailed,
      ),
    );
  });

  test('probe rejects unreadable SQLite bytes', () async {
    final corruptPath = path.join(temporary.path, 'corrupt.sqlite');
    await File(corruptPath).writeAsString('not a sqlite database');

    final result = await database.probeDatabase(
      corruptPath,
      integrityLevel: ControlPlaneIntegrityLevel.quick,
    );

    expect(
      result,
      isA<ControlPlaneUnusable>().having(
        (value) => value.reason,
        'reason',
        anyOf(
          ControlPlaneProbeFailureReason.cannotOpen,
          ControlPlaneProbeFailureReason.integrityCheckFailed,
        ),
      ),
    );
  });
}
