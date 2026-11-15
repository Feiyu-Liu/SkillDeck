import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/data/cloud_gateway.dart';
import 'package:skills_manager/features/cloud/cloud_configuration.dart';
import 'package:skills_manager/features/cloud/data/secure_cloud_session_store.dart';

final class MemoryValues implements CloudSecureValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

final class Listener implements CloudLoginListener {
  Listener(this.state);
  final String state;
  @override
  Uri get redirectUri => Uri.parse('http://127.0.0.1:49152/callback');
  @override
  Future<CloudLoginCode> get result async =>
      CloudLoginCode(code: List.filled(43, 'c').join(), state: state);
  @override
  Future<void> cancel() async {}
}

final class Backend implements CloudTransport {
  @override
  final Uri baseUri = Uri.parse('https://cloud.example.invalid');
  final paths = <String>[];
  @override
  Future<CloudResponse> request(
    CloudRequest request, {
    CloudCredential? credential,
    CloudCancellation? cancellation,
  }) async {
    paths.add(request.path);
    cancellation?.throwIfCancelled();
    final Map<String, Object?> data;
    switch (request.path) {
      case '/v1/auth/handoff/start':
        final id = List.filled(43, 't').join(),
            binding = List.filled(43, 'b').join();
        data = {
          'transactionId': id,
          'loginURL':
              '$baseUri/v1/auth/handoff/bind?transactionId=$id&browserToken=$binding',
          'expiresInSeconds': 600,
        };
      case '/v1/auth/handoff/exchange':
        data = {
          'token': 'fixture-new-token',
          'deviceId': 'new-device',
          'expiresAt': DateTime.utc(2027).millisecondsSinceEpoch,
        };
      case '/v1/session':
        final fresh = credential?.token == 'fixture-new-token';
        data = {
          'accountId': 'account',
          'deviceId': fresh ? 'new-device' : 'old-device',
          'sessionId': fresh ? 'new-session' : 'old-session',
        };
      case '/v1/devices':
        data = {
          'devices': [
            {
              'id': 'old-device',
              'name': 'Old Mac',
              'platform': 'macos',
              'createdAt': 1000,
              'lastSeenAt': 2000,
              'revokedAt': null,
            },
          ],
        };
      case '/v1/devices/revoke':
        data = {'pending': false};
      default:
        data = {};
    }
    return CloudResponse(
      statusCode: 200,
      body: {'protocolVersion': 1, 'data': data},
    );
  }

  @override
  void close() {}
}

void main() {
  test('a corrupt Cloud database does not block authenticated account/device management', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'skilldeck-cloud-corrupt-factory-',
    );
    final backend = Backend();
    final values = MemoryValues();
    final store = SecureCloudSessionStore(
      serviceOrigin: backend.baseUri,
      values: values,
    );
    await store.write(
      SecureSessionRecord(
        serviceOrigin: backend.baseUri,
        credential: CloudCredential('fixture-old-token'),
        session: const CloudSession(
          accountId: 'account',
          deviceId: 'old-device',
          sessionId: 'old-session',
        ),
      ),
    );
    final hash = sha256.convert(utf8.encode(backend.baseUri.origin)).toString();
    final file = File(
      '${temporary.path}/agent_skills/cloud/$hash/cloud.sqlite3',
    );
    await file.parent.create(recursive: true);
    final badBytes = utf8.encode('CORRUPT-CLOUD-DATABASE-RETAIN');
    await file.writeAsBytes(badBytes);
    final auth = CloudAuthClient(
      transport: backend,
      secureStore: store,
      launchBrowser: (_) async {},
    );
    final gateway = await createCloudGateway(
      CloudConfiguration(enabled: true, baseUri: backend.baseUri),
      supportDirectory: () async => temporary,
      authFactory: (_) => auth,
    );
    addTearDown(() async {
      await gateway.close();
      await temporary.delete(recursive: true);
    });
    expect(
      (await gateway.restore(CloudCancellation()))?.deviceId,
      'old-device',
    );
    expect(gateway.needsReconciliation, isTrue);
    expect((await gateway.devices()).single.name, 'Old Mac');
    expect(await gateway.revoke('another-device'), isFalse);
    await gateway.logoutCredentials();
    expect(values.values, isEmpty);
    expect(await file.readAsBytes(), badBytes);
    expect(backend.paths.any((path) => path.startsWith('/v1/sync')), isFalse);
  });
  test('restoring an old secure session after database loss never initializes scope; new sign-in does', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'skilldeck-app-cloud-scope-',
    );
    final path = '${temporary.path}/cloud.sqlite3';
    final backend = Backend();
    final values = MemoryValues();
    final store = SecureCloudSessionStore(
      serviceOrigin: backend.baseUri,
      values: values,
    );
    const old = CloudSession(
      accountId: 'account',
      deviceId: 'old-device',
      sessionId: 'old-session',
    );
    await store.write(
      SecureSessionRecord(
        serviceOrigin: backend.baseUri,
        credential: CloudCredential('fixture-old-token'),
        session: old,
      ),
    );
    final database = await BackgroundSqliteCloudDatabase.open(
      path: path,
      serviceOrigin: backend.baseUri,
    );
    final auth = CloudAuthClient(
      transport: backend,
      secureStore: store,
      launchBrowser: (_) async {},
      listenerFactory: ({
        required state,
        required timeout,
        required cancellation,
      }) async => Listener(state),
    );
    final gateway = RealAppCloudGateway(
      auth: auth,
      database: database,
      deviceName: 'Test Mac',
      platform: 'macos',
    );
    addTearDown(() async {
      await gateway.close();
      await temporary.delete(recursive: true);
    });
    expect(
      (await gateway.restore(CloudCancellation()))?.deviceId,
      'old-device',
    );
    expect(gateway.needsReconciliation, isTrue);
    expect(await database.hasDeviceScope(old), isFalse);
    final session = await gateway.signIn(CloudCancellation());
    expect(session.deviceId, 'new-device');
    expect(await database.hasDeviceScope(session), isTrue);
    expect(gateway.needsReconciliation, isFalse);
    expect(
      await database
          .forWorkspace('unreconciled-workspace')
          .hasAuthoritativeScope(
            accountId: session.accountId,
            deviceId: session.deviceId,
          ),
      isFalse,
    );
    expect(backend.paths.any((path) => path.startsWith('/v1/sync')), isFalse);
    final raw = String.fromCharCodes(await File(path).readAsBytes());
    expect(raw, isNot(contains('fixture-old-token')));
    expect(raw, isNot(contains('fixture-new-token')));
    await gateway.logoutCredentials();
    expect(values.values, isEmpty);
    expect(
      await database.hasDeviceScope(session),
      isTrue,
      reason: 'Credential logout preserves Cloud synchronization records',
    );
  });
}
