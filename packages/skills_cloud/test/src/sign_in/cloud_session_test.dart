import 'package:http/http.dart' as http;
import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import '../../support/fake_cloud_service.dart';

void main() {
  late FakeCloudService service;
  late InMemoryCloudSessionStore store;

  setUp(() async {
    service = FakeCloudService();
    store = InMemoryCloudSessionStore();
    await store.write(StoredCloudSession(origin: origin, token: sessionToken));
  });

  Future<String?> storedToken() async => (await store.read(origin))?.token;

  void expectTokenOnlyInHeader() {
    for (final request in service.requests) {
      expect(request.url.toString(), isNot(contains(sessionToken)));
      expect(request.body, isNot(contains(sessionToken)));
      expect(request.headers['authorization'], 'Bearer $sessionToken');
    }
  }

  group('currentSession', () {
    test('reports the account and keeps the token', () async {
      final status = await service.signIn(store).currentSession();

      final account = (status as CloudSignedIn).account;
      expect(account.id, 'account-1');
      expect(account.email, accountEmail);
      final request = service.requests.single;
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('$productionOrigin/api/auth/get-session'));
      expect(await storedToken(), sessionToken);
      expectTokenOnlyInHeader();
    });

    test('without a stored token requires sign-in and sends nothing', () async {
      await store.delete(origin);
      expect(
        await service.signIn(store).currentSession(),
        isA<CloudSignInRequired>(),
      );
      expect(service.requests, isEmpty);
    });

    for (final MapEntry(key: name, value: reply) in <String, Reply>{
      'a null session': (_) => jsonResponse(null),
      'a 401': (_) => http.Response('', 401),
    }.entries) {
      test('$name requires sign-in and deletes the token', () async {
        service.session = reply;
        expect(
          await service.signIn(store).currentSession(),
          isA<CloudSignInRequired>(),
        );
        expect(await storedToken(), isNull);
      });
    }

    for (final (name, reply, code) in <(String, Reply, CloudFailureCode)>[
      ('a connection failure', networkFailure, CloudFailureCode.network),
      ('a 503', (_) => http.Response('', 503), CloudFailureCode.server),
      (
        'a 429',
        (_) => jsonResponse({'error': 'rate_limited'}, 429),
        CloudFailureCode.server,
      ),
      (
        'a malformed body',
        (_) => jsonResponse({'user': 'x'}),
        CloudFailureCode.protocol,
      ),
      ('a 403', (_) => http.Response('', 403), CloudFailureCode.protocol),
      (
        'a body that is not JSON',
        (_) => http.Response('<html>', 200),
        CloudFailureCode.protocol,
      ),
    ]) {
      test('$name is unavailable and keeps the token', () async {
        service.session = reply;
        final status = await service.signIn(store).currentSession();
        expect((status as CloudSessionUnavailable).code, code);
        expect(await storedToken(), sessionToken);
      });
    }
  });

  group('signOut', () {
    for (final MapEntry(key: name, value: reply) in <String, Reply>{
      'a 200': (_) => jsonResponse({'success': true}),
      'a 500': (_) => http.Response('', 500),
      'a connection failure': networkFailure,
    }.entries) {
      test('deletes the token after $name, without retrying', () async {
        service.signOut = reply;
        await service.signIn(store).signOut();

        final request = service.requests.single;
        expect(request.method, 'POST');
        expect(request.url, Uri.parse('$productionOrigin/api/auth/sign-out'));
        expect(request.headers['content-type'], startsWith('application/json'));
        expect(request.body, '{}');
        expect(await storedToken(), isNull);
        expectTokenOnlyInHeader();
      });
    }

    test('without a stored token sends nothing', () async {
      await store.delete(origin);
      await service.signIn(store).signOut();
      expect(service.requests, isEmpty);
    });
  });

  group('origins', () {
    test('a token stored for staging is never sent to production', () async {
      await store.delete(origin);
      final staging = CloudServiceOrigin.parse(
        'https://cloud-staging.skilldeck.cc',
      );
      await store.write(StoredCloudSession(origin: staging, token: 'staging'));

      final signIn = service.signIn(store);
      expect(await signIn.currentSession(), isA<CloudSignInRequired>());
      await signIn.signOut();
      expect(service.requests, isEmpty);
      expect((await store.read(staging))?.token, 'staging');
    });

    test('a store that returns another origin\'s session is ignored', () async {
      final staging = CloudServiceOrigin.parse(
        'https://cloud-staging.skilldeck.cc',
      );
      final signIn = CloudSignIn(
        client: service.client,
        origin: origin,
        store: _MisroutingStore(
          StoredCloudSession(origin: staging, token: 'staging'),
        ),
      );
      expect(await signIn.currentSession(), isA<CloudSignInRequired>());
      await signIn.signOut();
      expect(service.requests, isEmpty);
    });
  });
}

/// Returns the same session for every origin.
final class _MisroutingStore implements CloudSessionStore {
  _MisroutingStore(this.session);

  final StoredCloudSession session;

  @override
  Future<StoredCloudSession?> read(CloudServiceOrigin origin) async => session;

  @override
  Future<void> write(StoredCloudSession session) async {}

  @override
  Future<void> delete(CloudServiceOrigin origin) async {}
}
