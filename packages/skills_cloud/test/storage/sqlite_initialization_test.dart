import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/src/storage/sqlite_schema.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  final origin = Uri.parse('https://cloud.example.invalid');
  test('foreign databases with application id zero are rejected without changing any file bytes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cloud-foreign-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    for (final version in [0, 1]) {
      final path = '${directory.path}/foreign-$version.sqlite';
      final db = sqlite3.open(path);
      db.execute('CREATE TABLE foreign_notes(value TEXT)');
      db.execute("INSERT INTO foreign_notes VALUES('keep')");
      db.userVersion = version;
      db.close();
      final before = sha256.convert(await File(path).readAsBytes());
      expect(
        () => SqliteCloudDatabase.open(path: path, serviceOrigin: origin),
        throwsA(isA<CloudException>()),
      );
      expect(
        sha256.convert(await File(path).readAsBytes()).toString(),
        before.toString(),
      );
    }
  });
  test('real SQLITE_FULL during schema creation rolls back all tables and stamps, then can recover', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    db.execute('PRAGMA max_page_count=4');
    expect(() => initializeCloudSchema(db), throwsA(isA<CloudException>()));
    expect(
      db.select(
        "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
      ),
      isEmpty,
    );
    expect(db.userVersion, 0);
    expect(db.select('PRAGMA application_id').single.values.single, 0);
    db.execute('PRAGMA max_page_count=1000');
    initializeCloudSchema(db);
    expect(db.userVersion, 2);
    expect(
      db.select('PRAGMA application_id').single.values.single,
      cloudApplicationId,
    );
    expect(
      db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      ),
      hasLength(17),
    );
  });
  test('identified marker with incomplete schema is rejected instead of silently creating tables', () async {
    final dir = await Directory.systemTemp.createTemp('cloud-incomplete-db-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/broken.sqlite';
    final db = sqlite3.open(path);
    db.userVersion = 1;
    db.execute('PRAGMA application_id=1396982577');
    db.close();
    final before = await File(path).readAsBytes();
    expect(
      () => SqliteCloudDatabase.open(path: path, serviceOrigin: origin),
      throwsA(isA<CloudException>()),
    );
    expect(await File(path).readAsBytes(), before);
  });
  test('background adapter leaves the caller event loop responsive while SQLite waits for a writer', () async {
    final dir = await Directory.systemTemp.createTemp('cloud-background-db-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/cloud.sqlite';
    final database = await BackgroundSqliteCloudDatabase.open(
      path: path,
      serviceOrigin: origin,
    );
    addTearDown(database.close);
    const session = CloudSession(
      accountId: 'account',
      deviceId: 'device',
      sessionId: 'session',
    );
    await database.initializeNewDeviceScope(session);
    await database.markWorkspaceReconciled(
      session: session,
      workspaceScopeId: 'workspace',
    );
    final writer = sqlite3.open(path);
    addTearDown(writer.close);
    writer.execute('BEGIN IMMEDIATE');
    final key = CloudOperationKey(
      accountId: 'account',
      deviceId: 'device',
      operationId: 'operation',
    );
    final pending = database
        .forWorkspace('workspace')
        .compareAndSet(
          expectedVersion: null,
          next: CloudStoredOperation(
            key: key,
            version: 1,
            family: 'metadata',
            originUtc: DateTime.utc(2026),
            lastObservedUtc: DateTime.utc(2026),
            phases: {
              '/v1/sync/metadata': {
                'operationId': 'operation',
                'kind': 'tagCreate',
                'name': 'tag',
              },
            },
          ),
        );
    var ticked = false;
    final timer = Timer(const Duration(milliseconds: 20), () => ticked = true);
    addTearDown(timer.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ticked, isTrue);
    writer.execute('ROLLBACK');
    expect(await pending, isTrue);
    expect(
      (await database.forWorkspace('workspace').readOperation(key))?.version,
      1,
    );
  });
}
