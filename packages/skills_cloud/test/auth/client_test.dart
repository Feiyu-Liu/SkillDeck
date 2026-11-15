import 'dart:async';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

Matcher cloudError(CloudErrorCode code) =>
    isA<CloudException>().having((error) => error.code, 'code', code);

void main() {
  test('auth transitions reject old identity requests and old 401 cannot clear new login', () async {
    final f = AuthFixture();
    addTearDown(f.auth.close);
    await f.login();
    final oldResponse = Completer<CloudResponse>(),
        startGate = Completer<void>();
    f.transport.handler = (request, credential, _) async {
      if (request.path == '/v1/devices') return oldResponse.future;
      if (request.path == '/v1/auth/handoff/start') await startGate.future;
      return f.transport.normal(request, credential);
    };
    final old = f.auth.listDevices();
    final oldCheck = expectLater(
      old,
      throwsA(cloudError(CloudErrorCode.cancelled)),
    );
    await Future<void>.delayed(Duration.zero);
    final newLogin = f.login();
    expect(f.auth.currentSession, isNull);
    await expectLater(
      f.auth.listDevices(),
      throwsA(cloudError(CloudErrorCode.operationInProgress)),
    );
    startGate.complete();
    await newLogin;
    oldResponse.complete(failure('unauthorized'));
    await oldCheck;
    expect(f.auth.currentSession?.deviceId, 'device-2');
    expect(f.store.value?.session.deviceId, 'device-2');
    f.transport.handler = null;
    final readGate = Completer<void>();
    f.store.readDelay = readGate;
    final restore = f.auth.restore();
    await expectLater(
      f.auth.listDevices(),
      throwsA(cloudError(CloudErrorCode.operationInProgress)),
    );
    readGate.complete();
    expect((await restore)?.deviceId, 'device-2');
  });
  test(
    'login timeout is distinct from cancellation and closes its listener',
    () async {
      final f = AuthFixture();
      addTearDown(f.auth.close);
      f.completeCallback = false;
      await expectLater(
        f.login(timeout: const Duration(milliseconds: 30)),
        throwsA(cloudError(CloudErrorCode.timeout)),
      );
      expect(f.auth.currentSession, isNull);
      expect(f.store.value, isNull);
    },
  );
  test('service cannot redirect the browser to another origin or expose unknown protocol errors', () async {
    final f = AuthFixture();
    addTearDown(f.auth.close);
    f.transport.handler = (_, _, _) async => ok({
      'transactionId': randomCloudToken(),
      'loginURL': 'https://evil.invalid/v1/auth/handoff/bind?token=secret',
    });
    await expectLater(
      f.login(),
      throwsA(cloudError(CloudErrorCode.invalidResponse)),
    );
    expect(f.launches, 0);
    expect(f.store.value, isNull);
    f.transport.handler = (_, _, _) async => CloudResponse(
      statusCode: 500,
      body: {
        'protocolVersion': 1,
        'error': {'code': 'PRIVATE_REMOTE_ERROR', 'retryable': true},
      },
    );
    await expectLater(
      f.login(),
      throwsA(cloudError(CloudErrorCode.unavailable)),
    );
  });
  test('real loopback login verifies actor before atomic secure write and safe state', () async {
    final f = AuthFixture();
    addTearDown(f.auth.close);
    final session = await f.login();
    expect(session.accountId, 'account');
    expect(f.auth.currentSession, same(session));
    expect(f.store.value?.session.deviceId, session.deviceId);
    expect(f.transport.requests.map((request) => request.path), [
      '/v1/auth/handoff/start',
      '/v1/auth/handoff/exchange',
      '/v1/session',
    ]);
    expect(f.store.mutations, ['write-start', 'write-complete']);
    for (final value in [
      session,
      f.store.value!,
      f.store.value!.credential,
      f.transport.requests[1],
    ]) {
      expect(value.toString(), isNot(contains('fixture-token')));
    }
    final devices = await f.auth.listDevices();
    expect(devices.single.name, 'Test Mac');
    expect(await f.auth.revokeDevice('different-device'), isTrue);
    expect(f.auth.currentSession, isNotNull);
    expect(await f.auth.revokeDevice(session.deviceId), isTrue);
    expect(f.auth.currentSession, isNull);
    expect(f.store.value, isNull);
  });

  test('exchange rejection, actor mismatch and secure write failure never publish login', () async {
    for (final scenario in ['exchange', 'mismatch', 'store']) {
      final f = AuthFixture();
      addTearDown(f.auth.close);
      f.transport.rejectExchange = scenario == 'exchange';
      f.transport.mismatchedDevice = scenario == 'mismatch';
      f.store.failWrite = scenario == 'store';
      await expectLater(
        f.login(),
        throwsA(
          cloudError(
            scenario == 'exchange'
                ? CloudErrorCode.unauthorized
                : scenario == 'store'
                ? CloudErrorCode.secureStorage
                : CloudErrorCode.invalidResponse,
          ),
        ),
      );
      expect(f.auth.currentSession, isNull);
      expect(f.store.value, isNull);
    }
  });

  test('restore revalidates binding; network errors preserve secure record; revoked clears it', () async {
    final f = AuthFixture();
    addTearDown(f.auth.close);
    await f.login();
    final restored = CloudAuthClient(
      transport: f.transport,
      secureStore: f.store,
      launchBrowser: (_) async {},
    );
    addTearDown(restored.close);
    expect((await restored.restore())?.deviceId, 'device-1');
    f.transport.handler = (_, _, _) async =>
        throw StateError('PRIVATE_NETWORK_ERROR');
    await expectLater(
      restored.restore(),
      throwsA(cloudError(CloudErrorCode.unavailable)),
    );
    expect(f.store.value, isNotNull);
    f.transport.handler = null;
    f.transport.rejectVerify = true;
    expect(await restored.restore(), isNull);
    expect(f.store.value, isNull);
    expect(await restored.restore(), isNull);
  });

  test('logout serializes after a delayed secure write and old cleanup cannot clear new login', () async {
    final f = AuthFixture();
    addTearDown(f.auth.close);
    final gate = Completer<void>(), started = Completer<void>();
    f.store.writeDelay = gate;
    f.store.writeStarted = started;
    final old = f.login();
    final oldExpectation = expectLater(
      old,
      throwsA(cloudError(CloudErrorCode.cancelled)),
    );
    await started.future;
    expect(f.auth.currentSession, isNull);
    final logout = f.auth.logoutCredentials();
    expect(f.store.mutations, ['write-start']);
    final newer = f.login();
    gate.complete();
    await oldExpectation;
    await logout;
    final session = await newer;
    expect(session.deviceId, 'device-2');
    expect(f.store.value?.session.deviceId, 'device-2');
    expect(f.store.mutations.last, 'write-complete');
  });

  test('late unauthorized request after logout/new login cannot clear newer credentials', () async {
    final f = AuthFixture();
    addTearDown(f.auth.close);
    await f.login();
    final pending = Completer<CloudResponse>();
    f.transport.handler = (request, credential, _) =>
        request.path == '/v1/devices'
        ? pending.future
        : f.transport.normal(request, credential);
    final old = f.auth.listDevices();
    final oldExpectation = expectLater(
      old,
      throwsA(cloudError(CloudErrorCode.cancelled)),
    );
    await Future<void>.delayed(Duration.zero);
    await f.auth.logoutCredentials();
    await f.login();
    pending.complete(failure('unauthorized'));
    await oldExpectation;
    expect(f.auth.currentSession?.deviceId, 'device-2');
    expect(f.store.value?.session.deviceId, 'device-2');
  });

  test('browser launch failure and cancellation close login without persisting credentials', () async {
    final f = AuthFixture();
    addTearDown(f.auth.close);
    f.failLaunch = true;
    await expectLater(
      f.login(),
      throwsA(cloudError(CloudErrorCode.browserLaunch)),
    );
    f.failLaunch = false;
    f.completeCallback = false;
    final cancellation = CloudCancellation();
    final pending = f.login(cancellation: cancellation);
    final check = expectLater(
      pending,
      throwsA(cloudError(CloudErrorCode.cancelled)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    cancellation.cancel();
    await check;
    expect(f.store.value, isNull);
    await expectLater(
      f.login(cancellation: cancellation),
      throwsA(cloudError(CloudErrorCode.cancelled)),
    );
  });

  test('secure read and clear failures are sanitized and logout always stops requests', () async {
    final f = AuthFixture();
    addTearDown(f.auth.close);
    f.store.failRead = true;
    await expectLater(
      f.auth.restore(),
      throwsA(cloudError(CloudErrorCode.secureStorage)),
    );
    f.store.failRead = false;
    await f.login();
    f.store.failClear = true;
    await expectLater(
      f.auth.logoutCredentials(),
      throwsA(cloudError(CloudErrorCode.secureStorage)),
    );
    expect(f.auth.currentSession, isNull);
    await expectLater(
      f.auth.listDevices(),
      throwsA(cloudError(CloudErrorCode.unauthorized)),
    );
  });

  test('secure record codec and all wrappers redact credentials and reject unknown versions', () {
    final record = SecureSessionRecord(
      credential: CloudCredential('secret-token'),
      serviceOrigin: Uri.parse('https://cloud.example.invalid'),
      session: const CloudSession(
        accountId: 'account',
        deviceId: 'device',
        sessionId: 'session',
      ),
    );
    final decoded = SecureSessionRecord.fromSecureJson(record.toSecureJson());
    expect(decoded.credential.token, 'secret-token');
    expect(decoded.toString(), isNot(contains('secret-token')));
    expect(
      () => SecureSessionRecord.fromSecureJson({'version': 2}),
      throwsA(cloudError(CloudErrorCode.secureStorage)),
    );
    expect(
      () => CloudCredential('token\r\nheader'),
      throwsA(isA<CloudException>()),
    );
  });
}
