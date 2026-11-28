import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import '../../support/fake_cloud_service.dart';

final class FakeAuthenticator implements CloudWebAuthenticator {
  FakeAuthenticator(this.reply);
  final FutureOr<Uri?> Function(Uri) reply;
  final urls = <Uri>[];
  @override
  Future<Uri?> authenticate(Uri url, {required String callbackScheme}) async {
    expect(callbackScheme, 'cc.skilldeck.signin');
    urls.add(url);
    return reply(url);
  }
}

Uri callback(
  Uri url, [
  Map<String, String> values = const {'code': 'secret-code'},
]) => Uri.parse(
  'cc.skilldeck.signin:/callback',
).replace(queryParameters: {'state': url.queryParameters['state']!, ...values});

void main() {
  test(
    'success uses fresh PKCE values and existing session finishing',
    () async {
      final service = FakeCloudService();
      final store = InMemoryCloudSessionStore();
      final signIn = service.signIn(store);
      final authenticator = FakeAuthenticator(callback);
      for (var attempt = 0; attempt < 2; attempt++) {
        expect(
          await signIn.signInWithBrowser(device, authenticator),
          isA<CloudSignInSucceeded>(),
        );
        final url = authenticator.urls.last;
        final form = service.on('/app/token').last.bodyFields;
        expect(url.origin, productionOrigin);
        expect(url.path, '/app/sign-in');
        expect(url.queryParameters, {
          'client_id': CloudSignIn.clientId,
          'redirect_uri': 'cc.skilldeck.signin:/callback',
          'response_type': 'code',
          'code_challenge': base64Url
              .encode(
                sha256.convert(ascii.encode(form['code_verifier']!)).bytes,
              )
              .replaceAll('=', ''),
          'code_challenge_method': 'S256',
          'state': url.queryParameters['state'],
          'device_name': device.name,
          'device_platform': 'macos',
        });
        expect(form['code_verifier'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
        expect(
          url.queryParameters['state'],
          matches(RegExp(r'^[A-Za-z0-9_-]{43}$')),
        );
        expect(form, {
          'grant_type': 'authorization_code',
          'code': 'secret-code',
          'code_verifier': form['code_verifier'],
          'client_id': CloudSignIn.clientId,
          'redirect_uri': 'cc.skilldeck.signin:/callback',
        });
        final stored = await store.read(origin);
        expect(stored?.token, sessionToken);
        expect(stored?.account?.email, accountEmail);
      }
      expect(
        authenticator.urls[0].queryParameters['state'],
        isNot(authenticator.urls[1].queryParameters['state']),
      );
      expect(
        service.on('/app/token').first.bodyFields['code_verifier'],
        isNot(service.on('/app/token').last.bodyFields['code_verifier']),
      );
    },
  );
  final invalid = <String, Uri? Function(Uri)>{
    'wrong state': (u) => callback(u, {'code': 'secret', 'state': 'wrong'}),
    'wrong scheme': (u) => callback(u).replace(scheme: 'https'),
    'wrong path': (u) => callback(u).replace(path: '/wrong'),
    'authority': (u) => callback(u).replace(host: 'evil.example'),
    'fragment': (u) => callback(u).replace(fragment: 'secret'),
    'missing code': (u) => callback(u, {}),
    'empty code': (u) => callback(u, {'code': ''}),
    'other error': (u) => callback(u, {'error': 'invalid_request'}),
    'code and error': (u) =>
        callback(u, {'error': 'access_denied', 'code': 'secret'}),
    'duplicate state': (u) => Uri.parse('${callback(u)}&state=other'),
    'duplicate code': (u) => Uri.parse('${callback(u)}&code=other'),
  };
  for (final entry in invalid.entries) {
    test('${entry.key} rejected before exchange', () async {
      final service = FakeCloudService();
      final store = InMemoryCloudSessionStore();
      final result = await service
          .signIn(store)
          .signInWithBrowser(device, FakeAuthenticator(entry.value));
      expect((result as CloudSignInFailed).code, CloudFailureCode.protocol);
      expect(service.requests, isEmpty);
      expect(await store.read(origin), isNull);
    });
  }
  test('cancel and denial send nothing', () async {
    final service = FakeCloudService();
    final signIn = service.signIn(InMemoryCloudSessionStore());
    expect(
      await signIn.signInWithBrowser(device, FakeAuthenticator((_) => null)),
      isA<CloudSignInCancelled>(),
    );
    expect(
      await signIn.signInWithBrowser(
        device,
        FakeAuthenticator((u) => callback(u, {'error': 'access_denied'})),
      ),
      isA<CloudSignInDenied>(),
    );
    expect(service.requests, isEmpty);
  });
  final failures = <String, (Reply, CloudFailureCode)>{
    'invalid grant': (
      (_) => oauthError('invalid_grant'),
      CloudFailureCode.protocol,
    ),
    'rate limited': ((_) => http.Response('', 429), CloudFailureCode.server),
    'server error': ((_) => http.Response('', 500), CloudFailureCode.server),
    'network': (networkFailure, CloudFailureCode.network),
    'malformed token': (
      (_) => jsonResponse({'access_token': ''}),
      CloudFailureCode.protocol,
    ),
  };
  for (final entry in failures.entries) {
    test('maps ${entry.key}', () async {
      final service = FakeCloudService()..appToken = entry.value.$1;
      final store = InMemoryCloudSessionStore();
      final result = await service
          .signIn(store)
          .signInWithBrowser(device, FakeAuthenticator(callback));
      expect((result as CloudSignInFailed).code, entry.value.$2);
      expect(await store.read(origin), isNull);
    });
  }
  test('concurrent attempt rejected; cancellation releases guard', () async {
    final signIn = FakeCloudService().signIn(InMemoryCloudSessionStore());
    final pending = Completer<Uri?>();
    final first = signIn.signInWithBrowser(
      device,
      FakeAuthenticator((_) => pending.future),
    );
    await expectLater(
      signIn.signInWithBrowser(device, FakeAuthenticator(callback)),
      throwsStateError,
    );
    pending.complete(null);
    expect(await first, isA<CloudSignInCancelled>());
    expect(
      await signIn.signInWithBrowser(device, FakeAuthenticator(callback)),
      isA<CloudSignInSucceeded>(),
    );
  });
  test('platform failures expose no credentials and release guard', () async {
    final service = FakeCloudService();
    final signIn = service.signIn(InMemoryCloudSessionStore());
    final authenticator = FakeAuthenticator(
      (url) => throw Exception('$url secret-code $sessionToken'),
    );
    final result = await signIn.signInWithBrowser(device, authenticator);
    expect(result, isA<CloudSignInFailed>());
    for (final secret in [
      authenticator.urls.single.toString(),
      'secret-code',
      sessionToken,
      authenticator.urls.single.queryParameters['state']!,
    ]) {
      expect(result.toString(), isNot(contains(secret)));
    }
    expect(service.requests, isEmpty);
    expect(
      await signIn.signInWithBrowser(device, FakeAuthenticator(callback)),
      isA<CloudSignInSucceeded>(),
    );
  });
  test(
    'an authenticator Error also cannot expose private callback data',
    () async {
      final service = FakeCloudService();
      final result = await service
          .signIn(InMemoryCloudSessionStore())
          .signInWithBrowser(
            device,
            FakeAuthenticator(
              (url) =>
                  throw ArgumentError.value(url, 'callback', 'secret-verifier'),
            ),
          );
      expect(result, isA<CloudSignInFailed>());
      expect(result.toString(), isNot(contains('secret-verifier')));
      expect(service.requests, isEmpty);
    },
  );
}
