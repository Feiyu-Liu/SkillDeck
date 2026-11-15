import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  test('repository credentials are operation-bound, capped to ten minutes and redacted', () async {
    var now = DateTime.utc(2026, 11, 15);
    Map<String, Object?> value({
      Object? scope = 'read',
      int seconds = 600,
      String remote = 'https://git.example.invalid/repository.git',
    }) => {
      'operationId': 'transfer',
      'scope': scope,
      'lineageId': 'lineage',
      'generation': 1,
      'remote': remote,
      'token': 'ephemeral-secret',
      'expiresAt': now.add(Duration(seconds: seconds)).millisecondsSinceEpoch,
    };
    final lease = CloudTransferLease.fromJson(
      value(),
      policy: const CloudTransferRemotePolicy.httpsOnly(),
      clock: () => now,
    );
    expect(await lease.authorizationHeaders(), [
      'Authorization: Bearer ephemeral-secret',
    ]);
    expect(await lease.authorizationHeaders(), hasLength(1));
    expect(lease.toString(), isNot(contains('ephemeral-secret')));
    lease.invalidate();
    await expectLater(
      lease.authorizationHeaders(),
      throwsA(isA<CloudException>()),
    );
    for (final data in [
      value(scope: 'PRIVATE_UNKNOWN_SCOPE'),
      value(seconds: 0),
      value(seconds: 631),
      value(remote: 'https://user:password@git.example.invalid/repo'),
      value(remote: 'http://127.0.0.1:49152/repo'),
    ]) {
      expect(
        () => CloudTransferLease.fromJson(
          data,
          policy: const CloudTransferRemotePolicy.httpsOnly(),
          clock: () => now,
        ),
        throwsA(isA<CloudException>()),
      );
    }
    final rollback = CloudTransferLease.fromJson(
      value(),
      policy: const CloudTransferRemotePolicy.httpsOnly(),
      clock: () => now,
    );
    now = now.subtract(const Duration(seconds: 1));
    await expectLater(
      rollback.authorizationHeaders(),
      throwsA(isA<CloudException>()),
    );
  });
  test('test-only loopback policy allows exact numeric host with explicit unprivileged port', () {
    const policy = CloudTransferRemotePolicy.loopbackForTesting();
    expect(policy.parse('http://127.0.0.1:49152/git/repo').host, '127.0.0.1');
    for (final value in [
      'http://localhost:49152/git/repo',
      'http://127.0.0.2:49152/git/repo',
      'http://127.0.0.1/git/repo',
      'http://127.0.0.1:80/git/repo',
      'http://127.0.0.1:49152/git/repo?token=x',
    ]) {
      expect(() => policy.parse(value), throwsA(isA<CloudException>()));
    }
  });
  test('SDK transfer responses must match exact operation, access, lineage and generation', () async {
    final auth = AuthFixture();
    addTearDown(auth.auth.close);
    await auth.login();
    final now = DateTime.utc(2026, 11, 15);
    var mismatch = false;
    auth.transport.handler = (request, credential, _) async {
      final data = request.body!['data']! as Map<String, Object?>;
      return ok({
        ...data,
        'lineageId': mismatch ? 'different' : data['lineageId'],
        'remote': 'https://git.example.invalid/repo',
        'token': 'ephemeral-secret',
        'expiresAt': now
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
      });
    };
    final client = CloudSyncClient(
      auth: auth.auth,
      intents: MemoryIntents(),
      clock: () => now,
    );
    final lease = await client.lineageTransfer(
      operationId: 'read-transfer',
      lineageId: 'lineage',
      generation: 1,
      access: CloudTransferAccess.read,
    );
    expect(lease.lineageId, 'lineage');
    expect(lease.generation, 1);
    mismatch = true;
    await expectLater(
      client.lineageTransfer(
        operationId: 'read-transfer-new',
        lineageId: 'lineage',
        generation: 1,
        access: CloudTransferAccess.read,
      ),
      throwsA(isA<CloudException>()),
    );
  });
}
