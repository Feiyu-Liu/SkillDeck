import 'dart:async';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import '../auth/client_test.dart' show cloudError;
import '../support/fakes.dart';

void main() {
  late AuthFixture auth;
  late MemoryIntents intents;
  late CloudSyncClient client;
  late DateTime clock;
  setUp(() async {
    auth = AuthFixture();
    await auth.login();
    intents = MemoryIntents();
    clock = DateTime.utc(2026, 11, 15);
    client = CloudSyncClient(
      auth: auth.auth,
      intents: intents,
      clock: () => clock,
    );
  });
  tearDown(() => auth.auth.close());
  test(
    'fresh intent may stay offline for 48 hours before first send',
    () async {
      final intent = client.createIntent(
        operationId: 'offline',
        path: '/v1/sync/metadata',
        data: {'kind': 'tagCreate', 'name': 'offline'},
      );
      expect(intent.isFresh, isTrue);
      expect(intent.firstAttemptUtc, isNull);
      clock = clock.add(const Duration(hours: 48));
      await client.sendMutation(intent);
      expect(intents.values[intent.key]?.originUtc, clock);
      final count = auth.transport.requests.length;
      clock = clock.add(const Duration(hours: 24));
      await expectLater(
        client.sendMutation(intent),
        throwsA(cloudError(CloudErrorCode.needsReconciliation)),
      );
      expect(auth.transport.requests.length, count);
    },
  );
  test(
    'restored missing origin and reset scope never become fresh sends',
    () async {
      final fresh = client.createIntent(
        operationId: 'unknown',
        path: '/v1/sync/metadata',
        data: {'kind': 'tagCreate', 'name': 'unknown'},
      );
      final unknown = CloudMutationIntent.restored(
        key: fresh.key,
        path: fresh.path,
        data: fresh.data,
        firstAttemptUtc: null,
      );
      final count = auth.transport.requests.length;
      await expectLater(
        client.sendMutation(unknown),
        throwsA(cloudError(CloudErrorCode.needsReconciliation)),
      );
      intents.scopeReady = false;
      await expectLater(
        client.sendMutation(fresh),
        throwsA(cloudError(CloudErrorCode.needsReconciliation)),
      );
      expect(auth.transport.requests.length, count);
    },
  );
  int sent() => auth.transport.requests
      .where((request) => request.path.startsWith('/v1/sync'))
      .length;
  CloudMutationIntent mutation({
    String id = 'operation',
    String path = '/v1/sync/metadata',
    Map<String, Object?> data = const {
      'kind': 'fields',
      'patch': {'favorite': false, 'note': ''},
    },
  }) => client.createIntent(operationId: id, path: path, data: data);

  test('mutations persist origin before a single versioned request and preserve null/false/empty', () async {
    final intent = mutation(
      data: {
        'kind': 'fields',
        'patch': {'favorite': false, 'note': null},
      },
    );
    auth.transport.handler = (request, credential, _) async {
      if (request.path.startsWith('/v1/sync')) {
        expect(intents.values.containsKey(intent.key), isTrue);
      }
      return auth.transport.normal(request, credential);
    };
    await client.sendMutation(intent);
    final body = auth.transport.requests.last.body!;
    expect(body['protocolVersion'], 1);
    expect(body['requestId'], isA<String>());
    expect((body['data']! as Map<String, Object?>)['patch'], {
      'favorite': false,
      'note': null,
    });
    expect(intents.values[intent.key]?.originUtc, clock);
    expect(sent(), 1);
  });
  test('network errors never retry or choose a new operation ID', () async {
    final intent = mutation();
    auth.transport.handler = (_, _, _) async =>
        throw StateError('PRIVATE_REMOTE_ERROR');
    await expectLater(
      client.sendMutation(intent),
      throwsA(cloudError(CloudErrorCode.unavailable)),
    );
    expect(sent(), 1);
    clock = clock.add(const Duration(hours: 1));
    await expectLater(
      client.sendMutation(intent),
      throwsA(cloudError(CloudErrorCode.unavailable)),
    );
    expect(sent(), 2);
    final payloads = auth.transport.requests
        .where((request) => request.path == intent.path)
        .map((request) => request.body!['data']);
    expect(payloads.first, payloads.last);
    expect(intents.values[intent.key]?.originUtc, DateTime.utc(2026, 11, 15));
  });
  test(
    'exact 24-hour boundary rejects rebuilt intent without any network call',
    () async {
      await client.sendMutation(mutation());
      clock = clock.add(const Duration(hours: 24));
      final rebuilt = mutation();
      await expectLater(
        client.sendMutation(rebuilt),
        throwsA(cloudError(CloudErrorCode.needsReconciliation)),
      );
      expect(sent(), 1);
    },
  );
  test(
    'clock rollback, unknown origin and storage failure never send',
    () async {
      final intent = mutation();
      await client.sendMutation(intent);
      clock = clock.add(const Duration(hours: 2));
      await client.sendMutation(intent);
      clock = clock.subtract(const Duration(hours: 1));
      await expectLater(
        client.sendMutation(intent),
        throwsA(cloudError(CloudErrorCode.needsReconciliation)),
      );
      final prior = intents.values[intent.key]!;
      intents.values[intent.key] = CloudStoredOperation(
        key: prior.key,
        version: prior.version,
        family: prior.family,
        originUtc: null,
        lastObservedUtc: prior.lastObservedUtc,
        phases: prior.phases,
      );
      await expectLater(
        client.sendMutation(intent),
        throwsA(cloudError(CloudErrorCode.needsReconciliation)),
      );
      intents.failWrites = true;
      await expectLater(
        client.sendMutation(mutation(id: 'new')),
        throwsA(cloudError(CloudErrorCode.needsReconciliation)),
      );
      expect(sent(), 2);
    },
  );
  test('first commit must match a persisted preparation and its returned upload ID', () async {
    final unprepared = mutation(
      path: '/v1/sync/commits',
      data: {'uploadId': 'upload', 'baseCommitId': null},
    );
    await expectLater(
      client.sendMutation(unprepared),
      throwsA(cloudError(CloudErrorCode.needsReconciliation)),
    );
    final prepare = mutation(
      path: '/v1/sync/commits/prepare',
      data: {'commitId': 'commit'},
    );
    await client.sendMutation(prepare);
    expect(intents.values[prepare.key]?.uploadId, 'upload');
    final wrong = mutation(
      path: '/v1/sync/commits',
      data: {'uploadId': 'wrong', 'baseCommitId': null},
    );
    await expectLater(
      client.sendMutation(wrong),
      throwsA(cloudError(CloudErrorCode.needsReconciliation)),
    );
    await client.sendMutation(unprepared);
    expect(sent(), 2);
  });
  test('slow prepare then restart cannot restart the 24-hour clock for first commit', () async {
    final prepare = mutation(
      path: '/v1/sync/commits/prepare',
      data: {'commitId': 'commit'},
    );
    auth.transport.handler = (request, credential, _) async {
      final result = await auth.transport.normal(request, credential);
      if (request.path == prepare.path) {
        clock = clock.add(const Duration(hours: 25));
      }
      return result;
    };
    await client.sendMutation(prepare);
    client = CloudSyncClient(
      auth: auth.auth,
      intents: intents,
      clock: () => clock,
    );
    final lateCommit = mutation(
      path: '/v1/sync/commits',
      data: {'uploadId': 'upload', 'baseCommitId': null},
    );
    await expectLater(
      client.sendMutation(lateCommit),
      throwsA(cloudError(CloudErrorCode.needsReconciliation)),
    );
    expect(sent(), 1);
  });
  test(
    'same operation ID cannot change payload or cross business families',
    () async {
      await client.sendMutation(mutation());
      await expectLater(
        client.sendMutation(mutation(data: {'changed': true})),
        throwsA(cloudError(CloudErrorCode.operationConflict)),
      );
      await expectLater(
        client.sendMutation(
          mutation(path: '/v1/sync/commits', data: {'lineageId': 'lineage'}),
        ),
        throwsA(cloudError(CloudErrorCode.operationConflict)),
      );
      expect(sent(), 1);
    },
  );
  test('local CAS contention never retries HTTP and cancelled queue work does not send', () async {
    intents.alwaysContend = true;
    await expectLater(
      client.sendMutation(mutation()),
      throwsA(cloudError(CloudErrorCode.needsReconciliation)),
    );
    expect(sent(), 0);
    final cancellation = CloudCancellation()..cancel();
    await expectLater(
      client.sendMutation(mutation(), cancellation: cancellation),
      throwsA(cloudError(CloudErrorCode.cancelled)),
    );
    expect(sent(), 0);
  });
  test('account transition during durable CAS never sends old payload with new credentials', () async {
    final started = Completer<void>(), release = Completer<void>();
    intents.beforeWrite = () async {
      started.complete();
      await release.future;
    };
    final result = client.sendMutation(mutation());
    final check = expectLater(
      result,
      throwsA(
        anyOf(
          cloudError(CloudErrorCode.needsReconciliation),
          cloudError(CloudErrorCode.cancelled),
        ),
      ),
    );
    await started.future;
    await auth.auth.logoutCredentials();
    await auth.login();
    release.complete();
    await check;
    expect(sent(), 0);
    expect(auth.auth.currentSession?.deviceId, 'device-2');
  });
  test('versioned GETs preserve sequences above JS precision and snapshot tag-only pages', () async {
    final page = await client.changes(
      after: CloudSequence.parse('9007199254740993'),
    );
    expect(page.highWatermark.toJson(), '9223372036854775807');
    expect(auth.transport.requests.last.query, {
      'protocolVersion': '1',
      'after': '9007199254740993',
    });
    final first = await client.createSnapshot();
    final last = await client.snapshotPage(
      snapshotId: first.snapshotId,
      pageCursor: first.nextPageCursor!,
      highWatermark: first.highWatermark,
    );
    expect(last.complete, isTrue);
    expect(last.personalTags.single.name, 'Unassigned');
    await client.operationStatus('operation/with/slash');
    expect(auth.transport.requests.last.query['protocolVersion'], '1');
    expect(
      auth.transport.requests.last.path,
      endsWith('operation%2Fwith%2Fslash'),
    );
  });
  test('snapshot identity/high-watermark mismatch is rejected', () async {
    await expectLater(
      client.snapshotPage(
        snapshotId: 'snapshot',
        pageCursor: 'next',
        highWatermark: CloudSequence.parse('1'),
      ),
      throwsA(cloudError(CloudErrorCode.invalidResponse)),
    );
  });
}
