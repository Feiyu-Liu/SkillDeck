import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/database/source_descriptor_codec.dart';
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

  test('committed schema v5 matches the current Drift declaration', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(workspaceDatabaseSchemaVersion);
    final database = WorkspaceDatabase.forTesting(schema.newConnection());

    await database.validateDatabaseSchema(
      options: const ValidationOptions(validateDropped: true),
    );

    await database.close();
    schema.close();
  });

  test(
    'migrates v3 without changing existing sources and stores synced provenance',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(3);
      addTearDown(schema.close);
      final raw = schema.rawDatabase;
      const codec = SourceDescriptorCodec();
      final originalDescriptors = <SourceDescriptor>[
        LocalSourceDescriptor(locator: '/source/local'),
        GitSourceDescriptor(locator: 'https://example.test/repo.git'),
        WellKnownSourceDescriptor(locator: 'https://example.test/index.json'),
        AdoptedSnapshotSourceDescriptor(
          authoritativeLocation: '/source/adopted',
          contentHash: 'a' * 64,
        ),
      ];
      const skillId = '123e4567-e89b-42d3-a456-426614174000';
      String lineageId(int index) =>
          '123e4567-e89b-42d3-a456-42661417401$index';

      raw
        ..execute('PRAGMA foreign_keys = ON')
        ..execute('BEGIN')
        ..execute(
          'INSERT INTO managed_skills VALUES (?, ?, ?, ?, ?, ?, 0, 0)',
          [
            skillId,
            'example',
            'example',
            'Example',
            'Description',
            lineageId(0),
          ],
        );
      for (var index = 0; index <= originalDescriptors.length; index++) {
        raw.execute("INSERT INTO source_lineages VALUES (?, ?, 'sha1', 0)", [
          lineageId(index),
          skillId,
        ]);
        if (index == originalDescriptors.length) break;
        final encoded = codec.encode(originalDescriptors[index]);
        raw.execute('INSERT INTO skill_sources VALUES (?, ?, ?, ?)', [
          lineageId(index),
          encoded.kind,
          encoded.payloadSchemaVersion,
          ' ${encoded.payloadJson}\n',
        ]);
      }
      raw.execute('COMMIT');
      const readSources =
          'SELECT * FROM skill_sources ORDER BY source_lineage_id';
      final before = raw.select(readSources).map(Map.of).toList();
      final database = WorkspaceDatabase.forTesting(schema.newConnection());
      addTearDown(database.close);

      await verifier.migrateAndValidate(database, 4);

      expect(raw.select(readSources).map(Map.of).toList(), equals(before));
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      expect(raw.select('PRAGMA foreign_keys').single.values.single, 1);
      final synced = SyncedOriginSourceDescriptor(
        originSourceType: SyncedOriginSourceType.adoptedSnapshot,
        originDeviceLabel: 'Origin Mac',
        displayLabel: 'My Skills',
      );
      final encoded = codec.encode(synced);
      await database
          .into(database.skillSources)
          .insert(
            SkillSourcesCompanion.insert(
              sourceLineageId: lineageId(originalDescriptors.length),
              kind: encoded.kind,
              payloadSchemaVersion: encoded.payloadSchemaVersion,
              payloadJson: encoded.payloadJson,
            ),
          );
      final stored = await (database.select(
        database.skillSources,
      )..orderBy([(row) => OrderingTerm.asc(row.sourceLineageId)])).get();
      expect(
        stored.map(
          (row) => codec.decode(
            kind: row.kind,
            payloadSchemaVersion: row.payloadSchemaVersion,
            payloadJson: row.payloadJson,
          ),
        ),
        orderedEquals([...originalDescriptors, synced]),
      );
    },
  );

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
    expect(await database.committedChangeStamps.select().get(), isEmpty);

    await database.close();
    schema.close();
  });

  test(
    'v4 migration preserves the cursor and data and starts the feed empty',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(4);
      addTearDown(schema.close);
      final raw = schema.rawDatabase;
      raw
        ..execute('INSERT INTO workspace_metadata VALUES (1, 7, 0, 0, 0)')
        ..execute(
          "INSERT INTO personal_tags VALUES "
          "('123e4567-e89b-42d3-a456-426614174000', 'name', 'Name', NULL, 0, 0)",
        );
      final before = raw
          .select('SELECT * FROM personal_tags')
          .map(Map.of)
          .toList();
      final database = WorkspaceDatabase.forTesting(schema.newConnection());
      addTearDown(database.close);

      await verifier.migrateAndValidate(database, 5);

      expect(await database.committedChangeStamps.select().get(), isEmpty);
      expect(
        (await database.workspaceMetadata.select().getSingle())
            .repositoryRevision,
        7,
      );
      expect(
        raw.select('SELECT * FROM personal_tags').map(Map.of).toList(),
        before,
      );
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

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
