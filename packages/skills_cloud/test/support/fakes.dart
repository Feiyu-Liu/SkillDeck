import 'dart:async';
import 'dart:io';

import 'package:skills_cloud/skills_cloud.dart';

CloudResponse ok(Map<String, Object?> data) =>
    CloudResponse(statusCode: 200, body: {'protocolVersion': 1, 'data': data});
CloudResponse failure(String code, {int status = 401}) => CloudResponse(
  statusCode: status,
  body: {
    'protocolVersion': 1,
    'error': {'code': code, 'retryable': false},
  },
);

final class FakeTransport implements CloudTransport {
  FakeTransport();
  @override
  final Uri baseUri = Uri.parse('https://cloud.example.invalid');
  final List<CloudRequest> requests = [];
  Future<CloudResponse> Function(
    CloudRequest,
    CloudCredential?,
    CloudCancellation?,
  )?
  handler;
  Map<String, Object?>? loginStart;
  final Map<String, CloudSession> sessions = {};
  var tokenCounter = 0;
  var rejectExchange = false;
  var rejectVerify = false;
  var mismatchedDevice = false;
  bool closed = false;
  @override
  Future<CloudResponse> request(
    CloudRequest request, {
    CloudCredential? credential,
    CloudCancellation? cancellation,
  }) async {
    requests.add(request);
    cancellation?.throwIfCancelled();
    if (handler != null) return handler!(request, credential, cancellation);
    return normal(request, credential);
  }

  Future<CloudResponse> normal(
    CloudRequest request,
    CloudCredential? credential,
  ) async {
    if (request.path.endsWith('/release')) return ok({'released': true});
    switch (request.path) {
      case '/v1/auth/handoff/start':
        loginStart = request.body;
        final transaction = List.filled(43, 't').join();
        return ok({
          'transactionId': transaction,
          'loginURL':
              '$baseUri/v1/auth/handoff/bind?transactionId=$transaction&browserToken=${List.filled(43, 'b').join()}',
          'expiresInSeconds': 600,
        });
      case '/v1/auth/handoff/exchange':
        if (rejectExchange) return failure('unauthorized');
        if (cloudPKCEChallenge(request.body!['verifier']! as String) !=
                loginStart!['challenge'] ||
            request.body!['state'] != loginStart!['state']) {
          return failure('unauthorized');
        }
        final count = ++tokenCounter;
        final actor = CloudSession(
          accountId: 'account',
          deviceId: 'device-$count',
          sessionId: 'session-$count',
        );
        sessions['fixture-token-$count'] = actor;
        return ok({
          'token': 'fixture-token-$count',
          'deviceId': mismatchedDevice ? 'other' : actor.deviceId,
          'expiresAt': DateTime.utc(2027).millisecondsSinceEpoch,
        });
      case '/v1/session':
        final session = sessions[credential?.token];
        if (rejectVerify || session == null) return failure('unauthorized');
        return ok({
          'accountId': session.accountId,
          'deviceId': session.deviceId,
          'sessionId': session.sessionId,
        });
      case '/v1/devices':
        return ok({
          'devices': [
            {
              'id': 'device-1',
              'name': 'Test Mac',
              'platform': 'macos',
              'createdAt': 1000,
              'lastSeenAt': 2000,
              'revokedAt': null,
            },
          ],
        });
      case '/v1/devices/revoke':
        return ok({'pending': true});
      case '/v1/sync/commits/prepare':
        return ok({
          'uploadId': 'upload',
          'state': 'ready',
          'expiresAt': 999999,
        });
      case '/v1/sync/changes':
        return ok({
          'after': request.query['after'],
          'highWatermark': '9223372036854775807',
          'nextCursor': '9223372036854775807',
          'entries': [
            {
              'sequence': '9223372036854775807',
              'kind': 'personalTag',
              'lineageId': null,
              'generation': null,
              'payload': {
                'kind': 'tagDelete',
                'tagId': 'tag',
                'deletedAt': 1000,
              },
            },
          ],
        });
      case '/v1/sync/snapshots':
        return ok({
          'snapshotId': 'snapshot',
          'highWatermark': '9007199254740993',
          'pageCursor': null,
          'nextPageCursor': 'next',
          'complete': false,
          'items': <Object?>[],
          'personalTags': <Object?>[],
        });
      case '/v1/sync/snapshots/snapshot':
        return ok({
          'snapshotId': 'snapshot',
          'highWatermark': '9007199254740993',
          'pageCursor': request.query['pageCursor'],
          'nextPageCursor': null,
          'complete': true,
          'items': <Object?>[],
          'personalTags': [
            {
              'tagId': 'tag',
              'name': 'Unassigned',
              'color': null,
              'createdAt': 1000,
              'updatedAt': 1000,
            },
          ],
        });
      default:
        return ok({'accepted': true});
    }
  }

  @override
  void close() {
    closed = true;
  }
}

final class MemorySecureStore implements SecureSessionStore {
  SecureSessionRecord? value;
  bool failRead = false, failWrite = false, failClear = false;
  Completer<void>? writeDelay;
  Completer<void>? writeStarted;
  Completer<void>? readDelay;
  final List<String> mutations = [];
  @override
  Future<SecureSessionRecord?> read() async {
    final delay = readDelay;
    readDelay = null;
    await delay?.future;
    if (failRead) throw StateError('PRIVATE_STORAGE_ERROR');
    return value;
  }

  @override
  Future<void> write(SecureSessionRecord record) async {
    mutations.add('write-start');
    writeStarted?.complete();
    writeStarted = null;
    final delay = writeDelay;
    writeDelay = null;
    await delay?.future;
    if (failWrite) throw StateError('PRIVATE_STORAGE_ERROR');
    value = record;
    mutations.add('write-complete');
  }

  @override
  Future<void> clear() async {
    mutations.add('clear');
    if (failClear) throw StateError('PRIVATE_STORAGE_ERROR');
    value = null;
  }
}

final class MemoryIntents implements MutationIntentStore {
  bool scopeReady = true;
  @override
  Future<bool> hasAuthoritativeScope({
    required String accountId,
    required String deviceId,
  }) async => scopeReady;
  final Map<CloudOperationKey, CloudStoredOperation> values = {};
  bool failWrites = false, alwaysContend = false;
  Future<void> Function()? beforeWrite;
  @override
  Future<CloudStoredOperation?> readOperation(CloudOperationKey key) async =>
      values[key];
  @override
  Future<bool> compareAndSet({
    required int? expectedVersion,
    required CloudStoredOperation next,
  }) async {
    await beforeWrite?.call();
    if (failWrites) throw StateError('PRIVATE_QUEUE_ERROR');
    if (!scopeReady ||
        alwaysContend ||
        values[next.key]?.version != expectedVersion) {
      return false;
    }
    values[next.key] = next;
    return true;
  }
}

final class AuthFixture {
  AuthFixture() {
    auth = CloudAuthClient(
      transport: transport,
      secureStore: store,
      launchBrowser: (_) async {
        launches++;
        if (failLaunch) throw StateError('PRIVATE_BROWSER_ERROR');
        if (!completeCallback) return;
        final start = transport.loginStart!;
        final redirect = Uri.parse(start['redirect']! as String);
        final target = redirect.replace(
          queryParameters: {
            'code': List.filled(43, 'c').join(),
            'state': start['state']! as String,
          },
        );
        final client = HttpClient();
        try {
          final response = await (await client.getUrl(target)).close();
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
      },
    );
  }
  final FakeTransport transport = FakeTransport();
  final MemorySecureStore store = MemorySecureStore();
  late final CloudAuthClient auth;
  int launches = 0;
  bool failLaunch = false, completeCallback = true;
  Future<CloudSession> login({
    CloudCancellation? cancellation,
    Duration timeout = const Duration(seconds: 2),
  }) => auth.signIn(
    deviceName: 'Test Mac',
    platform: 'macos',
    timeout: timeout,
    cancellation: cancellation,
  );
}
