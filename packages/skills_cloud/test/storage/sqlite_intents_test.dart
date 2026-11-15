import 'dart:io';
import 'dart:isolate';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

const actor = CloudSession(
  accountId: 'account',
  deviceId: 'new-device',
  sessionId: 'session',
);
final origin = Uri.parse('https://cloud.example.invalid');
CloudStoredOperation record({
  int version = 1,
  DateTime? originTime,
  Map<String, Object?>? payload,
}) => CloudStoredOperation(
  key: CloudOperationKey(
    accountId: actor.accountId,
    deviceId: actor.deviceId,
    operationId: 'operation',
  ),
  version: version,
  family: 'metadata',
  originUtc: originTime ?? DateTime.utc(2026, 11, 15),
  lastObservedUtc: DateTime.utc(2026, 11, 15, 1),
  phases: {
    '/v1/sync/metadata':
        payload ??
        {
          'operationId': 'operation',
          'kind': 'tagCreate',
          'name': 'private note',
        },
  },
);
void _compete(List<Object> args) async {
  final reply = args[2] as SendPort;
  SqliteCloudDatabase? database;
  try {
    database = SqliteCloudDatabase.open(
      path: args[0] as String,
      serviceOrigin: Uri.parse(args[1] as String),
    );
    final changed = await database
        .forWorkspace('workspace-a')
        .compareAndSet(expectedVersion: null, next: record());
    reply.send({'ok': true, 'changed': changed});
  } catch (_) {
    reply.send({'ok': false});
  } finally {
    database?.close();
  }
}

Future<Map<String, Object?>> compete(String path) async {
  final reply = ReceivePort();
  await Isolate.spawn(_compete, <Object>[
    path,
    origin.toString(),
    reply.sendPort,
  ]);
  final result = await reply.first;
  reply.close();
  return result! as Map<String, Object?>;
}

void main() {
  late Directory directory;
  late String path;
  late SqliteCloudDatabase database;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('skilldeck-cloud-cas-');
    path = '${directory.path}/cloud.sqlite';
    database = SqliteCloudDatabase.open(path: path, serviceOrigin: origin);
  });
  tearDown(() async {
    database.close();
    await directory.delete(recursive: true);
  });
  test('new database is not ready; only explicit new-device and Workspace reconcile establish scope', () async {
    final store = database.forWorkspace('workspace-a');
    expect(await database.hasDeviceScope(actor), isFalse);
    expect(
      await store.hasAuthoritativeScope(
        accountId: actor.accountId,
        deviceId: actor.deviceId,
      ),
      isFalse,
    );
    await database.initializeNewDeviceScope(actor);
    expect(await database.hasDeviceScope(actor), isTrue);
    expect(
      await store.hasAuthoritativeScope(
        accountId: actor.accountId,
        deviceId: actor.deviceId,
      ),
      isFalse,
    );
    await database.markWorkspaceReconciled(
      session: actor,
      workspaceScopeId: 'workspace-a',
    );
    expect(
      await store.hasAuthoritativeScope(
        accountId: actor.accountId,
        deviceId: actor.deviceId,
      ),
      isTrue,
    );
    expect(
      await store.compareAndSet(expectedVersion: null, next: record()),
      isTrue,
    );
    database.close();
    database = SqliteCloudDatabase.open(path: path, serviceOrigin: origin);
    expect(
      (await database.forWorkspace('workspace-a').readOperation(record().key))
          ?.originUtc,
      DateTime.utc(2026, 11, 15),
    );
    expect(
      await database
          .forWorkspace('workspace-b')
          .hasAuthoritativeScope(
            accountId: actor.accountId,
            deviceId: actor.deviceId,
          ),
      isFalse,
    );
  });
  test('eight actual SQLite connections compete in separate isolates with one CAS winner', () async {
    await database.initializeNewDeviceScope(actor);
    await database.markWorkspaceReconciled(
      session: actor,
      workspaceScopeId: 'workspace-a',
    );
    database.close();
    final results = await Future.wait(List.generate(8, (_) => compete(path)));
    expect(results.every((value) => value['ok'] == true), isTrue);
    expect(results.where((value) => value['changed'] == true), hasLength(1));
    database = SqliteCloudDatabase.open(path: path, serviceOrigin: origin);
    expect(
      (await database.forWorkspace('workspace-a').readOperation(record().key))
          ?.version,
      1,
    );
  });
  test(
    'CAS refuses origin extension, changed payload and revoked local authority',
    () async {
      await database.initializeNewDeviceScope(actor);
      await database.markWorkspaceReconciled(
        session: actor,
        workspaceScopeId: 'workspace-a',
      );
      final store = database.forWorkspace('workspace-a');
      expect(
        await store.compareAndSet(expectedVersion: null, next: record()),
        isTrue,
      );
      expect(
        await store.compareAndSet(
          expectedVersion: 1,
          next: record(version: 2, originTime: DateTime.utc(2026, 11, 15, 1)),
        ),
        isFalse,
      );
      expect(
        await store.compareAndSet(
          expectedVersion: 1,
          next: record(
            version: 2,
            payload: {
              'operationId': 'operation',
              'kind': 'tagCreate',
              'name': 'changed',
            },
          ),
        ),
        isFalse,
      );
      await database.requireWorkspaceReconciliation(
        session: actor,
        workspaceScopeId: 'workspace-a',
      );
      expect(
        await store.compareAndSet(expectedVersion: 1, next: record(version: 2)),
        isFalse,
      );
      expect((await store.readOperation(record().key))?.version, 1);
    },
  );
  test('restored old session with a lost database remains unready; origins cannot share scopes', () async {
    await database.initializeNewDeviceScope(actor);
    await database.markWorkspaceReconciled(
      session: actor,
      workspaceScopeId: 'workspace-a',
    );
    final other = SqliteCloudDatabase.open(
      path: path,
      serviceOrigin: Uri.parse('https://other.example.invalid'),
    );
    addTearDown(other.close);
    expect(await other.hasDeviceScope(actor), isFalse);
    database.close();
    other.close();
    await File(path).delete();
    database = SqliteCloudDatabase.open(path: path, serviceOrigin: origin);
    expect(await database.hasDeviceScope(actor), isFalse);
    expect(
      await database
          .forWorkspace('workspace-a')
          .compareAndSet(expectedVersion: null, next: record()),
      isFalse,
    );
  });
  test(
    'account operation origins cannot restart in another device or Workspace',
    () async {
      const otherActor = CloudSession(
        accountId: 'account',
        deviceId: 'other-device',
        sessionId: 'other-session',
      );
      for (final session in [actor, otherActor]) {
        await database.initializeNewDeviceScope(session);
        for (final workspace in ['workspace-a', 'workspace-b']) {
          await database.markWorkspaceReconciled(
            session: session,
            workspaceScopeId: workspace,
          );
        }
      }
      final first = database.forWorkspace('workspace-a'),
          other = database.forWorkspace('workspace-b');
      expect(
        await first.compareAndSet(expectedVersion: null, next: record()),
        isTrue,
      );
      await expectLater(
        other.readOperation(record().key),
        throwsA(isA<CloudException>()),
      );
      final key = CloudOperationKey(
        accountId: 'account',
        deviceId: 'other-device',
        operationId: 'operation',
      );
      await expectLater(
        first.readOperation(key),
        throwsA(isA<CloudException>()),
      );
      await expectLater(
        other.compareAndSet(
          expectedVersion: null,
          next: record(originTime: DateTime.utc(2026, 11, 16)),
        ),
        throwsA(isA<CloudException>()),
      );
      expect(
        (await first.readOperation(record().key))?.originUtc,
        DateTime.utc(2026, 11, 15),
      );
    },
  );
}
