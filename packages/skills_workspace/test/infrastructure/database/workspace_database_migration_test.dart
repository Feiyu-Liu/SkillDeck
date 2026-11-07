import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-migration-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'a newer unsupported schema fails closed without changing bytes',
    () async {
      final file = File('${temporaryDirectory.path}/newer.sqlite');
      final raw = sqlite3.open(file.path)
        ..execute('CREATE TABLE sentinel (value TEXT NOT NULL)')
        ..execute("INSERT INTO sentinel VALUES ('preserved')")
        ..userVersion = workspaceDatabaseSchemaVersion + 1;
      raw.close();

      final database = WorkspaceDatabase.forFile(file);
      await expectLater(
        database.workspaceMetadata.select().getSingle(),
        throwsA(anything),
      );
      await database.close();

      final reopened = sqlite3.open(file.path);
      expect(reopened.userVersion, workspaceDatabaseSchemaVersion + 1);
      expect(
        reopened.select('SELECT value FROM sentinel').single['value'],
        'preserved',
      );
      reopened.close();
    },
  );

  test('development schema v1 fails closed without migration', () async {
    final file = File('${temporaryDirectory.path}/schema-v1.sqlite');
    final raw = sqlite3.open(file.path)
      ..execute('CREATE TABLE sentinel (value TEXT NOT NULL)')
      ..execute("INSERT INTO sentinel VALUES ('preserved')")
      ..userVersion = 1;
    raw.close();

    final database = WorkspaceDatabase.forFile(file);
    await expectLater(
      database.customSelect('SELECT 1').getSingle(),
      throwsA(anything),
    );
    await database.close();

    final reopened = sqlite3.open(file.path);
    expect(reopened.userVersion, 1);
    expect(
      reopened.select('SELECT value FROM sentinel').single['value'],
      'preserved',
    );
    reopened.close();
  });

  test('committed schema v3 matches the current Drift declaration', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(workspaceDatabaseSchemaVersion);
    final database = WorkspaceDatabase.forTesting(schema.newConnection());

    await database.validateDatabaseSchema(
      options: const ValidationOptions(validateDropped: true),
    );

    await database.close();
    schema.close();
  });

  test('migrates schema v2 by adding the update cache tables', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(2);
    final database = WorkspaceDatabase.forTesting(schema.newConnection());

    await database.customSelect('SELECT 1').getSingle();

    expect(
      await database.select(database.skillUpdateCheckMetadata).getSingle(),
      isNot(equals(null)),
    );
    expect(
      await database.select(database.skillUpdateCheckRecords).get(),
      isEmpty,
    );

    await database.close();
    schema.close();
  });

  test(
    'a failed upgrade rolls back the entire migration transaction',
    () async {
      final file = File('${temporaryDirectory.path}/rollback.sqlite');
      final raw = sqlite3.open(file.path)
        ..execute('CREATE TABLE sentinel (value TEXT NOT NULL)')
        ..execute("INSERT INTO sentinel VALUES ('preserved')")
        ..userVersion = 1;
      raw.close();

      final database = WorkspaceDatabase.forTesting(
        NativeDatabase(file),
        schemaVersionOverride: 2,
        migrationOverride: MigrationStrategy(
          onUpgrade: (migrator, from, to) async {
            await databaseStatement(
              migrator,
              'CREATE TABLE migration_probe (value TEXT NOT NULL)',
            );
            throw StateError('injected migration failure');
          },
        ),
      );
      await expectLater(
        database.customSelect('SELECT 1').getSingle(),
        throwsA(anything),
      );
      await database.close();

      final reopened = sqlite3.open(file.path);
      expect(reopened.userVersion, 1);
      expect(
        reopened.select('SELECT value FROM sentinel').single['value'],
        'preserved',
      );
      expect(
        reopened.select(
          "SELECT name FROM sqlite_schema WHERE name = 'migration_probe'",
        ),
        isEmpty,
      );
      reopened.close();
    },
  );
}

Future<void> databaseStatement(Migrator migrator, String statement) =>
    migrator.database.customStatement(statement);
