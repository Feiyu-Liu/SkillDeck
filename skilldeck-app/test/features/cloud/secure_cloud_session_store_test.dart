import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/data/secure_cloud_session_store.dart';

final class Values implements CloudSecureValueStore {
  final entries = <String, String>{'agent_skills.translation.fixture': 'keep'};
  int reads = 0, writes = 0, deletes = 0;
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    reads++;
    if (fail) throw StateError('PRIVATE_PLUGIN_ERROR');
    return entries[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (fail) throw StateError('PRIVATE_PLUGIN_ERROR');
    entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    if (fail) throw StateError('PRIVATE_PLUGIN_ERROR');
    entries.remove(key);
  }
}

void main() {
  final origin = Uri.parse('https://cloud.example.invalid');
  SecureSessionRecord record(Uri origin) => SecureSessionRecord(
    serviceOrigin: origin,
    credential: CloudCredential('fixture-secret-token'),
    session: const CloudSession(
      accountId: 'account',
      deviceId: 'device',
      sessionId: 'session',
    ),
  );
  test('whole record is one origin-namespaced secure value and clearing preserves other credentials', () async {
    final values = Values();
    final store = SecureCloudSessionStore(
      serviceOrigin: origin,
      values: values,
    );
    expect(values.reads, 0);
    expect(values.writes, 0);
    await store.write(record(origin));
    expect(values.writes, 1);
    final key = values.entries.keys.singleWhere(
      (key) => key.startsWith('agent_skills.cloud.session.'),
    );
    final Object? json = jsonDecode(values.entries[key]!);
    expect(json, isA<Map<String, Object?>>());
    expect((json! as Map<String, Object?>)['serviceOrigin'], origin.origin);
    expect((await store.read())?.credential.token, 'fixture-secret-token');
    expect(store.toString(), isNot(contains('fixture-secret-token')));
    final other = SecureCloudSessionStore(
      serviceOrigin: Uri.parse('https://other.example.invalid'),
      values: values,
    );
    expect(await other.read(), isNull);
    await store.clear();
    expect(values.entries, {'agent_skills.translation.fixture': 'keep'});
  });
  test('wrong origin, corrupted values and plugin failures fail without raw diagnostics', () async {
    final values = Values();
    final store = SecureCloudSessionStore(
      serviceOrigin: origin,
      values: values,
    );
    await expectLater(
      store.write(record(Uri.parse('https://other.example.invalid'))),
      throwsA(isA<CloudException>()),
    );
    expect(values.writes, 0);
    await store.write(record(origin));
    final key = values.entries.keys.singleWhere(
      (key) => key.startsWith('agent_skills.cloud.session.'),
    );
    values.entries[key] = 'PRIVATE_INVALID_JSON';
    await expectLater(
      store.read(),
      throwsA(
        isA<CloudException>().having(
          (error) => error.code,
          'code',
          CloudErrorCode.secureStorage,
        ),
      ),
    );
    values.fail = true;
    for (final operation in [
      store.read,
      () => store.write(record(origin)),
      store.clear,
    ]) {
      try {
        await operation();
        fail('Expected secure storage failure');
      } on CloudException catch (error) {
        expect(error.toString(), isNot(contains('PRIVATE_PLUGIN_ERROR')));
      }
    }
  });
}
