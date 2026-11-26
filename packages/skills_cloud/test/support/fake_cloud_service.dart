import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skills_cloud/skills_cloud.dart';

const productionOrigin = 'https://cloud.skilldeck.cc';
const sessionToken = 'session-token-7f3a';
const deviceCodeValue = 'device-code-91c2';
const userCodeValue = 'WDJBMJHT';
const accountEmail = 'person@example.com';

final origin = CloudServiceOrigin.parse(productionOrigin);
final device = CloudDevice(
  name: 'Studio Mac',
  platform: CloudDevicePlatform.macos,
);

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

http.Response oauthError(String code) => jsonResponse({
  'error': code,
  'error_description': 'server text that must not surface',
}, 400);

Map<String, Object?> deviceCodeBody({
  Object? interval = 5,
  Object? expiresIn = 600,
  Object? verificationUri = '$productionOrigin/device',
  Object? verificationUriComplete =
      '$productionOrigin/device?user_code=$userCodeValue',
}) => {
  'device_code': deviceCodeValue,
  'user_code': userCodeValue,
  'verification_uri': verificationUri,
  'verification_uri_complete': verificationUriComplete,
  'expires_in': expiresIn,
  'interval': ?interval,
};

final tokenBody = {
  'access_token': sessionToken,
  'token_type': 'Bearer',
  'expires_in': 604800,
  'scope': '',
};

final sessionBody = {
  'session': {'expiresAt': '2026-12-26T00:00:00.000Z', 'token': 'ignored'},
  'user': {'id': 'account-1', 'email': accountEmail, 'name': 'Person'},
};

/// A reply the fake service gives: a response, or a thrown network failure.
typedef Reply = FutureOr<http.Response> Function(http.Request request);

http.Response networkFailure(http.Request request) =>
    throw http.ClientException('connection refused', request.url);

/// A MockClient that follows the v0 contract's paths and records requests.
final class FakeCloudService {
  FakeCloudService({this._elapsed});

  final Duration Function()? _elapsed;
  final requests = <http.Request>[];
  final requestTimes = <Duration>[];

  Reply deviceCode = (_) => jsonResponse(deviceCodeBody());

  /// Replies for successive polls; the last one repeats.
  List<Reply> tokenReplies = [(_) => jsonResponse(tokenBody)];
  int _polls = 0;

  Reply session = (_) => jsonResponse(sessionBody);
  Reply signOut = (_) => jsonResponse({'success': true});

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (_elapsed case final elapsed?) requestTimes.add(elapsed());
    switch ((request.method, request.url.path)) {
      case ('POST', '/api/auth/device/code'):
        return deviceCode(request);
      case ('POST', '/api/auth/device/token'):
        final index = _polls < tokenReplies.length
            ? _polls
            : tokenReplies.length - 1;
        _polls++;
        return tokenReplies[index](request);
      case ('GET', '/api/auth/get-session'):
        return session(request);
      case ('POST', '/api/auth/sign-out'):
        return signOut(request);
    }
    return http.Response('not found', 404);
  });

  Iterable<http.Request> on(String path) =>
      requests.where((request) => request.url.path == path);

  CloudSignIn signIn(CloudSessionStore store) => CloudSignIn(
    client: client,
    origin: origin,
    store: store,
    elapsed: _elapsed,
  );
}
