import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import '../../support/fake_cloud_service.dart';

const _second = Duration(seconds: 1);

void main() {
  group('start', () {
    test('posts the device fields as a form and returns the codes', () async {
      final service = FakeCloudService();
      final start = await service
          .signIn(InMemoryCloudSessionStore())
          .start(device);

      final pending = start as PendingSignIn;
      expect(pending.userCode, userCodeValue);
      expect(pending.verificationUri, Uri.parse('$productionOrigin/device'));
      expect(
        pending.verificationUriComplete,
        Uri.parse('$productionOrigin/device?user_code=$userCodeValue'),
      );
      expect(pending.expiresIn, const Duration(minutes: 10));

      final request = service.requests.single;
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('$productionOrigin/api/auth/device/code'));
      expect(
        request.headers['content-type'],
        startsWith('application/x-www-form-urlencoded'),
      );
      expect(request.bodyFields, {
        'client_id': 'skilldeck-desktop',
        'device_name': 'Studio Mac',
        'device_platform': 'macos',
      });
      expect(request.headers.containsKey('authorization'), isFalse);
    });

    final protocolCases = <String, Reply>{
      'a verification URI on another origin': (_) => jsonResponse(
        deviceCodeBody(verificationUri: 'https://elsewhere.example/device'),
      ),
      'a complete URI on another origin': (_) => jsonResponse(
        deviceCodeBody(
          verificationUriComplete: 'https://cloud.skilldeck.cc.evil/device',
        ),
      ),
      'a plain http verification URI': (_) => jsonResponse(
        deviceCodeBody(verificationUri: 'http://cloud.skilldeck.cc/device'),
      ),
      'a verification URI with userinfo': (_) => jsonResponse(
        deviceCodeBody(verificationUri: 'https://a@cloud.skilldeck.cc/device'),
      ),
      'a missing expiry': (_) => jsonResponse(deviceCodeBody(expiresIn: null)),
      'a string interval': (_) => jsonResponse(deviceCodeBody(interval: '5')),
      'a body that is not JSON': (_) => http.Response('<html>', 200),
      'invalid_client': (_) => oauthError('invalid_client'),
      'an unexpected status': (_) => http.Response('', 404),
    };
    for (final MapEntry(key: name, value: reply) in protocolCases.entries) {
      test('treats $name as a protocol failure', () async {
        final service = FakeCloudService()..deviceCode = reply;
        final start = await service
            .signIn(InMemoryCloudSessionStore())
            .start(device);
        expect(
          (start as CloudSignInStartFailed).code,
          CloudFailureCode.protocol,
        );
      });
    }

    test('reports a rate limit as a server failure', () async {
      final service = FakeCloudService()..deviceCode = (_) => _rateLimited();
      final start = await service
          .signIn(InMemoryCloudSessionStore())
          .start(device);
      expect((start as CloudSignInStartFailed).code, CloudFailureCode.server);
    });

    test('maps a server error and a network failure', () async {
      final server = FakeCloudService()
        ..deviceCode = (_) => http.Response('', 500);
      final network = FakeCloudService()..deviceCode = networkFailure;
      final store = InMemoryCloudSessionStore();
      expect(
        (await server.signIn(store).start(device) as CloudSignInStartFailed)
            .code,
        CloudFailureCode.server,
      );
      expect(
        (await network.signIn(store).start(device) as CloudSignInStartFailed)
            .code,
        CloudFailureCode.network,
      );
    });
  });

  group('complete', () {
    test('polls with the device code in the body, then reads the account', () {
      fakeAsync((time) {
        final service = FakeCloudService(elapsed: () => time.elapsed);
        final store = InMemoryCloudSessionStore();
        final result = _signIn(time, service, store);
        time.elapse(const Duration(seconds: 5));

        final poll = service.on('/api/auth/device/token').single;
        expect(poll.url, Uri.parse('$productionOrigin/api/auth/device/token'));
        expect(
          poll.headers['content-type'],
          startsWith('application/x-www-form-urlencoded'),
        );
        expect(poll.bodyFields, {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'device_code': deviceCodeValue,
          'client_id': 'skilldeck-desktop',
        });
        expect(poll.headers.containsKey('authorization'), isFalse);

        final read = service.on('/api/auth/get-session').single;
        expect(read.headers['authorization'], 'Bearer $sessionToken');

        final account = (result.value! as CloudSignInSucceeded).account;
        expect(account.id, 'account-1');
        expect(account.email, accountEmail);
        expect(account.sessionExpiresAt, DateTime.utc(2026, 12, 26));
        final stored = _stored(time, store);
        expect(stored?.token, sessionToken);
        expect(stored?.origin, origin);
        expect(stored?.account, same(account));
        _expectSecretsOnlyInBodiesAndHeaders(service);
      });
    });

    test('keeps the interval while pending and adds 5 s per slow_down', () {
      fakeAsync((time) {
        final service = FakeCloudService(elapsed: () => time.elapsed)
          ..tokenReplies = [
            (_) => oauthError('authorization_pending'),
            (_) => oauthError('slow_down'),
            (_) => oauthError('authorization_pending'),
            (_) => oauthError('slow_down'),
            (_) => jsonResponse(tokenBody),
          ];
        final result = _signIn(time, service, InMemoryCloudSessionStore());
        time.elapse(const Duration(minutes: 1));

        expect(_pollTimes(service), [
          const Duration(seconds: 5),
          const Duration(seconds: 10),
          const Duration(seconds: 20),
          const Duration(seconds: 30),
          const Duration(seconds: 45),
        ]);
        expect(result.value, isA<CloudSignInSucceeded>());
      });
    });

    test('defaults to a 5 s interval when the service sends none', () {
      fakeAsync((time) {
        final service = FakeCloudService(elapsed: () => time.elapsed)
          ..deviceCode = (_) => jsonResponse(deviceCodeBody(interval: null));
        _signIn(time, service, InMemoryCloudSessionStore());
        time.elapse(const Duration(seconds: 5) - _second);
        expect(service.on('/api/auth/device/token'), isEmpty);
        time.elapse(_second);
        expect(service.on('/api/auth/device/token'), hasLength(1));
      });
    });

    test('stops at expires_in and sends no poll after it', () {
      fakeAsync((time) {
        final service = FakeCloudService(elapsed: () => time.elapsed)
          ..deviceCode = ((_) => jsonResponse(deviceCodeBody(expiresIn: 12)))
          ..tokenReplies = [(_) => oauthError('authorization_pending')];
        final store = InMemoryCloudSessionStore();
        final result = _signIn(time, service, store);

        time.elapse(const Duration(seconds: 12) - _second);
        expect(result.value, isNull);
        time.elapse(_second);
        expect(result.value, isA<CloudSignInExpired>());
        time.elapse(const Duration(minutes: 5));
        expect(_pollTimes(service), [
          const Duration(seconds: 5),
          const Duration(seconds: 10),
        ]);
        expect(_stored(time, store), isNull);
      });
    });

    test('keeps polling through a connection failure, a 503, and a 429', () {
      fakeAsync((time) {
        final service = FakeCloudService(elapsed: () => time.elapsed)
          ..tokenReplies = [
            networkFailure,
            (_) => http.Response('', 503),
            (_) => _rateLimited(),
            (_) => jsonResponse(tokenBody),
          ];
        final result = _signIn(time, service, InMemoryCloudSessionStore());
        time.elapse(const Duration(seconds: 20));
        expect(_pollTimes(service), hasLength(4));
        expect(result.value, isA<CloudSignInSucceeded>());
      });
    });

    final stops = <String, Matcher>{
      'access_denied': isA<CloudSignInDenied>(),
      'expired_token': isA<CloudSignInExpired>(),
      'invalid_grant': isA<CloudSignInFailed>().having(
        (failure) => failure.code,
        'code',
        CloudFailureCode.protocol,
      ),
    };
    for (final MapEntry(key: code, value: matcher) in stops.entries) {
      test('$code ends the sign-in without writing the store', () {
        fakeAsync((time) {
          final service = FakeCloudService(elapsed: () => time.elapsed)
            ..tokenReplies = [(_) => oauthError(code)];
          final store = InMemoryCloudSessionStore();
          final result = _signIn(time, service, store);
          time.elapse(const Duration(minutes: 1));
          expect(result.value, matcher);
          expect(_pollTimes(service), hasLength(1));
          expect(_stored(time, store), isNull);
        });
      });
    }

    test('an unexpected token status or token type is a protocol failure', () {
      for (final reply in <Reply>[
        (_) => http.Response('', 403),
        (_) => jsonResponse({...tokenBody, 'token_type': 'mac'}),
        (_) => jsonResponse({...tokenBody, 'access_token': ''}),
      ]) {
        fakeAsync((time) {
          final service = FakeCloudService(elapsed: () => time.elapsed)
            ..tokenReplies = [reply];
          final store = InMemoryCloudSessionStore();
          final result = _signIn(time, service, store);
          time.elapse(const Duration(seconds: 5));
          expect(
            (result.value! as CloudSignInFailed).code,
            CloudFailureCode.protocol,
          );
          expect(_stored(time, store), isNull);
        });
      }
    });

    test('an account read failure after the token fails without storing', () {
      final cases = <Reply, CloudFailureCode>{
        (_) => http.Response('', 500): CloudFailureCode.server,
        networkFailure: CloudFailureCode.network,
        (_) => jsonResponse(null): CloudFailureCode.protocol,
        (_) => jsonResponse({'user': {}}): CloudFailureCode.protocol,
      };
      for (final MapEntry(key: reply, value: code) in cases.entries) {
        fakeAsync((time) {
          final service = FakeCloudService(elapsed: () => time.elapsed)
            ..session = reply;
          final store = InMemoryCloudSessionStore();
          final result = _signIn(time, service, store);
          time.elapse(const Duration(seconds: 5));
          expect((result.value! as CloudSignInFailed).code, code);
          expect(_stored(time, store), isNull);
        });
      }
    });

    test('cancel while waiting ends at once and sends nothing more', () {
      fakeAsync((time) {
        final service = FakeCloudService(elapsed: () => time.elapsed)
          ..tokenReplies = [(_) => oauthError('authorization_pending')];
        final store = InMemoryCloudSessionStore();
        late PendingSignIn pending;
        final result = _signIn(
          time,
          service,
          store,
          onPending: (value) => pending = value,
        );
        time.elapse(const Duration(seconds: 7));
        expect(_pollTimes(service), hasLength(1));

        pending.cancel();
        time.flushMicrotasks();
        expect(result.value, isA<CloudSignInCancelled>());
        expect(time.pendingTimers, isEmpty);
        time.elapse(const Duration(minutes: 10));
        expect(_pollTimes(service), hasLength(1));
        expect(_stored(time, store), isNull);
      });
    });

    test('cancel during a poll ignores its late success', () {
      fakeAsync((time) {
        final reply = Completer<http.Response>();
        final service = FakeCloudService(elapsed: () => time.elapsed)
          ..tokenReplies = [(_) => reply.future];
        final store = InMemoryCloudSessionStore();
        late PendingSignIn pending;
        final result = _signIn(
          time,
          service,
          store,
          onPending: (value) => pending = value,
        );
        time.elapse(const Duration(seconds: 5));
        expect(_pollTimes(service), hasLength(1));

        pending.cancel();
        time.flushMicrotasks();
        expect(result.value, isA<CloudSignInCancelled>());
        reply.complete(jsonResponse(tokenBody));
        time.elapse(const Duration(minutes: 1));
        expect(service.on('/api/auth/get-session'), isEmpty);
        expect(_stored(time, store), isNull);
      });
    });

    test('a pending sign-in can be completed once, by its own client', () {
      fakeAsync((time) {
        final service = FakeCloudService(elapsed: () => time.elapsed);
        final signIn = service.signIn(InMemoryCloudSessionStore());
        final other = service.signIn(InMemoryCloudSessionStore());
        PendingSignIn? pending;
        signIn.start(device).then((value) => pending = value as PendingSignIn);
        time.flushMicrotasks();

        expect(() => other.complete(pending!), throwsArgumentError);
        unawaited(signIn.complete(pending!));
        expect(() => signIn.complete(pending!), throwsStateError);
        pending!.cancel();
        time.flushMicrotasks();
      });
    });
  });
}

http.Response _rateLimited() => jsonResponse({
  'error': 'rate_limited',
  'error_description': 'rate_limited',
}, 429);

final class _Result {
  CloudSignInResult? value;
}

/// Starts and completes a sign-in, leaving time to the caller.
_Result _signIn(
  FakeAsync time,
  FakeCloudService service,
  CloudSessionStore store, {
  void Function(PendingSignIn)? onPending,
}) {
  final result = _Result();
  final signIn = service.signIn(store);
  signIn
      .start(device)
      .then((start) {
        final pending = start as PendingSignIn;
        onPending?.call(pending);
        return signIn.complete(pending);
      })
      .then((value) => result.value = value);
  time.flushMicrotasks();
  return result;
}

StoredCloudSession? _stored(FakeAsync time, CloudSessionStore store) {
  StoredCloudSession? stored;
  store.read(origin).then((value) => stored = value);
  time.flushMicrotasks();
  return stored;
}

List<Duration> _pollTimes(FakeCloudService service) => [
  for (final (index, request) in service.requests.indexed)
    if (request.url.path == '/api/auth/device/token')
      service.requestTimes[index],
];

void _expectSecretsOnlyInBodiesAndHeaders(FakeCloudService service) {
  for (final request in service.requests) {
    final url = request.url.toString();
    expect(url, isNot(contains(sessionToken)));
    expect(url, isNot(contains(deviceCodeValue)));
    expect(request.url.hasQuery, isFalse);
    expect(request.body, isNot(contains(sessionToken)));
  }
}
