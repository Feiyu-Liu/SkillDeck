import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/data/secure_cloud_session_store.dart';

void main() {
  final origin = CloudServiceOrigin.parse('https://cloud.example');
  final otherOrigin = CloudServiceOrigin.parse('https://other.example');
  const storage = FlutterSecureStorage();
  const store = SecureCloudSessionStore(storage: storage);
  final account = CloudAccount(
    id: 'fixture-id',
    email: 'account@example.test',
    sessionExpiresAt: DateTime.utc(2027),
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('stores only the session fields under an origin-specific key', () async {
    await store.write(
      StoredCloudSession(
        origin: origin,
        token: 'fixture-token',
        account: account,
      ),
    );
    final content = await storage.readAll();
    expect(content.keys.single, endsWith(origin.toString()));
    expect(jsonDecode(content.values.single), {
      'origin': origin.toString(),
      'token': 'fixture-token',
      'account': {
        'id': account.id,
        'email': account.email,
        'sessionExpiresAt': account.sessionExpiresAt.toIso8601String(),
      },
    });
    final restored = await store.read(origin);
    expect(restored?.origin, origin);
    expect(restored?.token, 'fixture-token');
    expect(restored?.account?.id, account.id);
    expect(restored?.account?.email, account.email);
    expect(restored?.account?.sessionExpiresAt, account.sessionExpiresAt);
    expect(await store.read(otherOrigin), isNull);

    await store.delete(origin);
    expect(await storage.readAll(), isEmpty);
  });

  test(
    'restores a token-only session and rejects an origin mismatch',
    () async {
      await store.write(
        StoredCloudSession(origin: origin, token: 'fixture-token'),
      );
      final restored = await store.read(origin);
      expect(restored?.token, 'fixture-token');
      expect(restored?.account, isNull);

      final key = (await storage.readAll()).keys.single;
      await storage.write(
        key: key,
        value: jsonEncode({'origin': otherOrigin.toString(), 'token': 'other'}),
      );
      expect(await store.read(origin), isNull);
    },
  );
}
