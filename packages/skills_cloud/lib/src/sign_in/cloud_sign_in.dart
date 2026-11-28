import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;

import 'cloud_device.dart';
import 'cloud_service_origin.dart';
import 'cloud_session_store.dart';

/// Why a sign-in or session call failed. Carries no server text.
enum CloudFailureCode {
  /// The service answered in a way the API contract does not allow.
  protocol,

  /// The service could not be reached.
  network,

  /// The service answered with a server error.
  server,
}

/// The result of [CloudSignIn.start].
sealed class CloudSignInStart {
  const CloudSignInStart();
}

/// A device code the person has yet to approve on the web.
final class PendingSignIn extends CloudSignInStart {
  PendingSignIn._({
    required this._owner,
    required this._deviceCode,
    required this._interval,
    required this._deadline,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresIn,
  });

  final CloudSignIn _owner;
  final String _deviceCode;
  final Duration _interval;
  final Duration _deadline;
  final _cancelled = Completer<void>();
  bool _completing = false;

  /// The code the person checks on the approval page.
  final String userCode;

  /// The approval page, on the service origin.
  final Uri verificationUri;

  /// The approval page with [userCode] filled in. Open this one.
  final Uri verificationUriComplete;

  /// How long the codes were valid when the service issued them.
  final Duration expiresIn;

  /// Ends [CloudSignIn.complete] with [CloudSignInCancelled] at once.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// [CloudSignIn.start] could not obtain a device code.
final class CloudSignInStartFailed extends CloudSignInStart {
  const CloudSignInStartFailed(this.code);

  final CloudFailureCode code;
}

/// The result of [CloudSignIn.complete].
sealed class CloudSignInResult {
  const CloudSignInResult();
}

/// The Device is signed in, and its Cloud Session is stored.
final class CloudSignInSucceeded extends CloudSignInResult {
  const CloudSignInSucceeded(this.account);

  final CloudAccount account;
}

/// The person denied this Device on the approval page.
final class CloudSignInDenied extends CloudSignInResult {
  const CloudSignInDenied();
}

/// The codes expired before the person approved the Device.
final class CloudSignInExpired extends CloudSignInResult {
  const CloudSignInExpired();
}

/// [PendingSignIn.cancel] was called.
final class CloudSignInCancelled extends CloudSignInResult {
  const CloudSignInCancelled();
}

final class CloudSignInFailed extends CloudSignInResult {
  const CloudSignInFailed(this.code);

  final CloudFailureCode code;
}

/// The result of [CloudSignIn.currentSession].
sealed class CloudSessionStatus {
  const CloudSessionStatus();
}

final class CloudSignedIn extends CloudSessionStatus {
  const CloudSignedIn(this.account);

  final CloudAccount account;
}

/// There is no live Cloud Session for this origin. Any stored token is gone.
final class CloudSignInRequired extends CloudSessionStatus {
  const CloudSignInRequired();
}

/// The session could not be checked. The stored token is kept.
final class CloudSessionUnavailable extends CloudSessionStatus {
  const CloudSessionUnavailable(this.code, {this.account});

  final CloudFailureCode code;

  /// The last verified account, if stored. The session is not verified now.
  final CloudAccount? account;
}

/// Opens an App-provided system web authentication window.
abstract interface class CloudWebAuthenticator {
  /// Returns the callback URL, or null when the person cancels.
  Future<Uri?> authenticate(Uri url, {required String callbackScheme});
}

/// Sign-in against one service origin.
///
/// See `cloud-api-contract-v0.md`. The Cloud Session token is sent only in
/// the `Authorization` header to [origin], and device codes only in request
/// bodies.
final class CloudSignIn {
  CloudSignIn({
    required this._client,
    required this.origin,
    required this._store,
    Duration Function()? elapsed,
  }) : _elapsed = elapsed ?? _startClock();

  static const clientId = 'skilldeck-desktop';
  static const _deviceCodeGrant =
      'urn:ietf:params:oauth:grant-type:device_code';
  static const _defaultInterval = Duration(seconds: 5);
  static const _minimumInterval = Duration(seconds: 1);
  static const _slowDownStep = Duration(seconds: 5);

  final CloudServiceOrigin origin;
  final http.Client _client;
  final CloudSessionStore _store;
  final Duration Function() _elapsed;

  bool _browserSignInRunning = false;

  /// Signs in through the App's system authentication window.
  Future<CloudSignInResult> signInWithBrowser(
    CloudDevice device,
    CloudWebAuthenticator authenticator,
  ) async {
    if (_browserSignInRunning) {
      throw StateError('A browser sign-in is already running.');
    }
    _browserSignInRunning = true;
    try {
      final random = Random.secure();
      String nonce() => base64Url
          .encode(List<int>.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final verifier = nonce();
      final state = nonce();
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');
      const callbackScheme = 'cc.skilldeck.signin';
      const redirectUri = '$callbackScheme:/callback';
      final callback = await authenticator.authenticate(
        origin
            .resolve('/app/sign-in')
            .replace(
              queryParameters: {
                'client_id': clientId,
                'redirect_uri': redirectUri,
                'response_type': 'code',
                'code_challenge': challenge,
                'code_challenge_method': 'S256',
                'state': state,
                'device_name': device.name,
                'device_platform': device.platform.wireName,
              },
            ),
        callbackScheme: callbackScheme,
      );
      if (callback == null) return const CloudSignInCancelled();
      final params = callback.queryParametersAll;
      if (callback.scheme != callbackScheme ||
          callback.hasAuthority ||
          callback.path != '/callback' ||
          callback.hasFragment ||
          params.values.any((values) => values.length != 1) ||
          params['state']?.single != state) {
        return const CloudSignInFailed(CloudFailureCode.protocol);
      }
      final error = params['error']?.single;
      final code = params['code']?.single;
      if (error != null) {
        return error == 'access_denied' && code == null
            ? const CloudSignInDenied()
            : const CloudSignInFailed(CloudFailureCode.protocol);
      }
      if (code == null || code.isEmpty) {
        return const CloudSignInFailed(CloudFailureCode.protocol);
      }
      final reply = await _send(
        () => _client.post(
          origin.resolve('/app/token'),
          headers: const {'Accept': 'application/json'},
          body: {
            'grant_type': 'authorization_code',
            'code': code,
            'code_verifier': verifier,
            'client_id': clientId,
            'redirect_uri': redirectUri,
          },
        ),
      );
      return switch (reply) {
        _NetworkFailure() => const CloudSignInFailed(CloudFailureCode.network),
        _Response(:final response) when response.statusCode == 200 =>
          await _finishSignIn(null, response),
        _Response(:final response) => CloudSignInFailed(
          _statusFailure(response.statusCode),
        ),
      };
    } on Object {
      // Platform failures can contain the callback and must not escape.
      return const CloudSignInFailed(CloudFailureCode.protocol);
    } finally {
      _browserSignInRunning = false;
    }
  }

  /// Requests a device code for clients without a web authentication window.
  Future<CloudSignInStart> start(CloudDevice device) async {
    final reply = await _send(
      () => _client.post(
        origin.resolve('/api/auth/device/code'),
        headers: const {'Accept': 'application/json'},
        body: {
          'client_id': clientId,
          'device_name': device.name,
          'device_platform': device.platform.wireName,
        },
      ),
    );
    final issuedAt = _elapsed();
    switch (reply) {
      case _NetworkFailure():
        return const CloudSignInStartFailed(CloudFailureCode.network);
      case _Response(:final response) when response.statusCode != 200:
        return CloudSignInStartFailed(_statusFailure(response.statusCode));
      case _Response(:final response):
        final pending = _parseDeviceCode(response, issuedAt);
        return pending ??
            const CloudSignInStartFailed(CloudFailureCode.protocol);
    }
  }

  /// Polls until [pending] is approved, denied, expired, or cancelled.
  ///
  /// Only [CloudSignInSucceeded] writes the session store. Call it once per
  /// [PendingSignIn].
  Future<CloudSignInResult> complete(PendingSignIn pending) async {
    if (!identical(pending._owner, this)) {
      throw ArgumentError.value(
        pending,
        'pending',
        'belongs to another client',
      );
    }
    if (pending._completing) {
      throw StateError('This sign-in is already being completed.');
    }
    pending._completing = true;

    var interval = pending._interval;
    while (true) {
      final remaining = pending._deadline - _elapsed();
      if (remaining <= Duration.zero) return const CloudSignInExpired();
      if (interval >= remaining) {
        // The next poll would come after the codes expire.
        return await _wait(remaining, pending)
            ? const CloudSignInExpired()
            : const CloudSignInCancelled();
      }
      if (!await _wait(interval, pending)) return const CloudSignInCancelled();

      final reply = await _unlessCancelled(
        pending,
        _send(
          () => _client.post(
            origin.resolve('/api/auth/device/token'),
            headers: const {'Accept': 'application/json'},
            body: {
              'grant_type': _deviceCodeGrant,
              'device_code': pending._deviceCode,
              'client_id': clientId,
            },
          ),
        ),
      );
      switch (reply) {
        case null:
          return const CloudSignInCancelled();
        case _NetworkFailure():
          continue;
        case _Response(:final response)
            when response.statusCode >= 500 || response.statusCode == 429:
          // Server errors and rate limits mean "try again later".
          continue;
        case _Response(:final response) when response.statusCode == 200:
          return _finishSignIn(pending, response);
        case _Response(:final response) when response.statusCode == 400:
          switch (_errorCode(response)) {
            case 'authorization_pending':
              continue;
            case 'slow_down':
              interval += _slowDownStep;
              continue;
            case 'access_denied':
              return const CloudSignInDenied();
            case 'expired_token':
              return const CloudSignInExpired();
            default:
              return const CloudSignInFailed(CloudFailureCode.protocol);
          }
        case _Response():
          return const CloudSignInFailed(CloudFailureCode.protocol);
      }
    }
  }

  /// Checks the stored Cloud Session with the service.
  Future<CloudSessionStatus> currentSession() async {
    final stored = await _readOwnSession();
    if (stored == null) return const CloudSignInRequired();
    switch (await _readAccount(stored.token)) {
      case _AccountFound(:final account):
        final previous = stored.account;
        if (previous?.id != account.id ||
            previous?.email != account.email ||
            previous?.sessionExpiresAt != account.sessionExpiresAt) {
          await _store.write(
            StoredCloudSession(
              origin: origin,
              token: stored.token,
              account: account,
            ),
          );
        }
        return CloudSignedIn(account);
      case _SessionEnded():
        await _store.delete(origin);
        return const CloudSignInRequired();
      case _AccountUnreadable(:final code):
        return CloudSessionUnavailable(code, account: stored.account);
    }
  }

  /// Ends this Device's Cloud Session and deletes the stored token.
  ///
  /// The token is deleted whatever the service answers. A failed request is
  /// not retried.
  Future<void> signOut() async {
    try {
      final stored = await _readOwnSession();
      if (stored != null) {
        await _send(
          () => _client.post(
            origin.resolve('/api/auth/sign-out'),
            headers: {
              ..._authorization(stored.token),
              'Content-Type': 'application/json',
            },
            body: '{}',
          ),
        );
      }
    } finally {
      await _store.delete(origin);
    }
  }

  PendingSignIn? _parseDeviceCode(http.Response response, Duration issuedAt) {
    final body = _decodeObject(response);
    if (body == null) return null;
    final deviceCode = body['device_code'];
    final userCode = body['user_code'];
    final verificationUri = _ownedUri(body['verification_uri']);
    final verificationUriComplete = _ownedUri(
      body['verification_uri_complete'],
    );
    final expiresIn = body['expires_in'];
    final interval = body['interval'];
    if (deviceCode is! String ||
        deviceCode.isEmpty ||
        userCode is! String ||
        userCode.isEmpty ||
        verificationUri == null ||
        verificationUriComplete == null ||
        expiresIn is! int ||
        expiresIn <= 0 ||
        (interval != null && (interval is! int || interval < 0))) {
      return null;
    }
    final lifetime = Duration(seconds: expiresIn);
    final pollInterval = interval == null
        ? _defaultInterval
        : _max(Duration(seconds: interval as int), _minimumInterval);
    return PendingSignIn._(
      owner: this,
      deviceCode: deviceCode,
      interval: pollInterval,
      deadline: issuedAt + lifetime,
      userCode: userCode,
      verificationUri: verificationUri,
      verificationUriComplete: verificationUriComplete,
      expiresIn: lifetime,
    );
  }

  Future<CloudSignInResult> _finishSignIn(
    PendingSignIn? pending,
    http.Response response,
  ) async {
    final body = _decodeObject(response);
    final token = body?['access_token'];
    final tokenType = body?['token_type'];
    if (token is! String ||
        token.isEmpty ||
        tokenType is! String ||
        tokenType.toLowerCase() != 'bearer') {
      return const CloudSignInFailed(CloudFailureCode.protocol);
    }
    final read = pending == null
        ? await _readAccount(token)
        : await _unlessCancelled(pending, _readAccount(token));
    if (read == null || (pending?._cancelled.isCompleted ?? false)) {
      return const CloudSignInCancelled();
    }
    switch (read) {
      case _AccountFound(:final account):
        await _store.write(
          StoredCloudSession(origin: origin, token: token, account: account),
        );
        return CloudSignInSucceeded(account);
      case _SessionEnded():
        return const CloudSignInFailed(CloudFailureCode.protocol);
      case _AccountUnreadable(:final code):
        return CloudSignInFailed(code);
    }
  }

  Future<_AccountRead> _readAccount(String token) async {
    final reply = await _send(
      () => _client.get(
        origin.resolve('/api/auth/get-session'),
        headers: {..._authorization(token), 'Accept': 'application/json'},
      ),
    );
    switch (reply) {
      case _NetworkFailure():
        return const _AccountUnreadable(CloudFailureCode.network);
      case _Response(:final response) when response.statusCode == 401:
        return const _SessionEnded();
      case _Response(:final response) when response.statusCode != 200:
        return _AccountUnreadable(_statusFailure(response.statusCode));
      case _Response(:final response):
        final Object? body;
        try {
          body = jsonDecode(utf8.decode(response.bodyBytes));
        } on FormatException {
          return const _AccountUnreadable(CloudFailureCode.protocol);
        }
        if (body == null) return const _SessionEnded();
        final account = _parseAccount(body);
        return account == null
            ? const _AccountUnreadable(CloudFailureCode.protocol)
            : _AccountFound(account);
    }
  }

  static CloudAccount? _parseAccount(Object body) {
    if (body is! Map<String, Object?>) return null;
    final user = body['user'];
    final session = body['session'];
    if (user is! Map<String, Object?> || session is! Map<String, Object?>) {
      return null;
    }
    final id = user['id'];
    final email = user['email'];
    final expiresAt = session['expiresAt'];
    final expiry = expiresAt is String ? DateTime.tryParse(expiresAt) : null;
    if (id is! String || id.isEmpty || email is! String || expiry == null) {
      return null;
    }
    return CloudAccount(id: id, email: email, sessionExpiresAt: expiry);
  }

  Future<StoredCloudSession?> _readOwnSession() async {
    final stored = await _store.read(origin);
    // A token is only ever sent to the origin that issued it.
    if (stored == null || stored.origin != origin) return null;
    return stored;
  }

  Uri? _ownedUri(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    return uri != null && origin.owns(uri) ? uri : null;
  }

  /// Completes with true after [duration], or false once [pending] is
  /// cancelled.
  Future<bool> _wait(Duration duration, PendingSignIn pending) {
    if (pending._cancelled.isCompleted) return Future.value(false);
    final done = Completer<bool>();
    final timer = Timer(duration, () {
      if (!done.isCompleted) done.complete(true);
    });
    pending._cancelled.future.then((_) {
      timer.cancel();
      if (!done.isCompleted) done.complete(false);
    });
    return done.future;
  }

  /// Completes with [work]'s value, or null as soon as [pending] is cancelled.
  static Future<T?> _unlessCancelled<T extends Object>(
    PendingSignIn pending,
    Future<T> work,
  ) {
    if (pending._cancelled.isCompleted) return Future.value(null);
    return Future.any<T?>([work, pending._cancelled.future.then((_) => null)]);
  }

  static Future<_Reply> _send(Future<http.Response> Function() request) async {
    try {
      return _Response(await request());
    } on Exception {
      // Includes ClientException and socket failures. Their text may hold
      // the URL, so it is dropped.
      return const _NetworkFailure();
    }
  }

  static Map<String, Object?>? _decodeObject(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body is Map<String, Object?> ? body : null;
    } on FormatException {
      return null;
    }
  }

  static String? _errorCode(http.Response response) {
    final error = _decodeObject(response)?['error'];
    return error is String ? error : null;
  }

  static Map<String, String> _authorization(String token) => {
    'Authorization': 'Bearer $token',
  };

  /// HTTP 429 means "try again later", like a server error (contract v0).
  static CloudFailureCode _statusFailure(int status) =>
      status >= 500 || status == 429
      ? CloudFailureCode.server
      : CloudFailureCode.protocol;

  static Duration _max(Duration a, Duration b) => a > b ? a : b;

  static Duration Function() _startClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}

sealed class _Reply {
  const _Reply();
}

final class _Response extends _Reply {
  const _Response(this.response);

  final http.Response response;
}

final class _NetworkFailure extends _Reply {
  const _NetworkFailure();
}

sealed class _AccountRead {
  const _AccountRead();
}

final class _AccountFound extends _AccountRead {
  const _AccountFound(this.account);

  final CloudAccount account;
}

final class _SessionEnded extends _AccountRead {
  const _SessionEnded();
}

final class _AccountUnreadable extends _AccountRead {
  const _AccountUnreadable(this.code);

  final CloudFailureCode code;
}
