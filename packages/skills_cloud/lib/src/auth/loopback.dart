import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../cancellation.dart';
import '../errors.dart';

/// Generates an unguessable 256-bit value for state, PKCE or request identity.
String randomCloudToken() {
  final random = Random.secure();
  return base64Url
      .encode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

/// Derives an RFC 7636 S256 PKCE challenge.
String cloudPKCEChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

/// An ephemeral callback result containing no application session credential.
final class CloudLoginCode {
  /// Creates the code checked by a loopback listener.
  const CloudLoginCode({required this.code, required this.state});

  /// The one-use, short-lived handoff code.
  final String code;

  /// The exact initiating state.
  final String state;
  @override
  String toString() => 'CloudLoginCode([redacted])';
}

/// A local callback boundary that closes on success, cancellation or timeout.
abstract interface class CloudLoginListener {
  /// The exact HTTP loopback callback address.
  Uri get redirectUri;

  /// The validated callback result.
  Future<CloudLoginCode> get result;

  /// Closes the bound socket and cancels an unfinished callback.
  Future<void> cancel();
}

/// Binds only `127.0.0.1` on an OS-assigned ephemeral port.
final class LoopbackLoginListener implements CloudLoginListener {
  LoopbackLoginListener._(
    this._server,
    this._state,
    Duration timeout,
    CloudCancellation? cancellation,
  ) : _port = _server.port {
    _timer = Timer(timeout, () => _finishError(CloudErrorCode.timeout));
    _unlisten = cancellation?.listen(
      () => _finishError(CloudErrorCode.cancelled),
    );
    _subscription = _server.listen((request) {
      unawaited(_handle(request));
    }, onError: (Object _) => _finishError(CloudErrorCode.unavailable));
    // Callers can attach their result handler after opening the browser.
    unawaited(_result.future.then<void>((_) {}, onError: (Object _) {}));
  }

  /// Starts a bounded listener and rejects already-cancelled operations.
  static Future<LoopbackLoginListener> bind({
    required String state,
    Duration timeout = const Duration(minutes: 10),
    CloudCancellation? cancellation,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(state) ||
        timeout <= Duration.zero) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    cancellation?.throwIfCancelled();
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      if (cancellation?.isCancelled ?? false) {
        await server.close(force: true);
        throw const CloudException(CloudErrorCode.cancelled);
      }
      return LoopbackLoginListener._(server, state, timeout, cancellation);
    } on CloudException {
      rethrow;
    } catch (_) {
      throw const CloudException(CloudErrorCode.unavailable);
    }
  }

  final HttpServer _server;
  final int _port;
  final String _state;
  final Completer<CloudLoginCode> _result = Completer();
  late final Timer _timer;
  late final StreamSubscription<HttpRequest> _subscription;
  void Function()? _unlisten;
  bool _closed = false;

  @override
  Uri get redirectUri => Uri.parse('http://127.0.0.1:$_port/callback');
  @override
  Future<CloudLoginCode> get result => _result.future;

  Future<void> _handle(HttpRequest request) async {
    try {
      final uri = request.uri;
      final params = uri.queryParametersAll;
      final valid =
          !_closed &&
          request.method == 'GET' &&
          request.headers.value(HttpHeaders.hostHeader) ==
              '127.0.0.1:${_server.port}' &&
          uri.path == '/callback' &&
          params.length == 2 &&
          params['state']?.length == 1 &&
          params['state']?.single == _state &&
          params['code']?.length == 1 &&
          RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(params['code']!.single);
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.headers.set('referrer-policy', 'no-referrer');
      request.response.headers.contentType = ContentType.text;
      if (!valid) {
        request.response.statusCode = 400;
        request.response.write('Invalid callback.');
        await request.response.close();
        return;
      }
      _closed = true;
      _timer.cancel();
      _unlisten?.call();
      request.response.write(
        'Returned to SkillDeck. You may close this window.',
      );
      await request.response.close();
      await _server.close(force: true);
      if (!_result.isCompleted) {
        _result.complete(
          CloudLoginCode(code: params['code']!.single, state: _state),
        );
      }
    } catch (_) {
      _finishError(CloudErrorCode.unavailable);
    }
  }

  void _finishError(CloudErrorCode code) {
    if (_result.isCompleted) return;
    _closed = true;
    _timer.cancel();
    _unlisten?.call();
    unawaited(_server.close(force: true));
    _result.completeError(CloudException(code));
  }

  @override
  Future<void> cancel() async {
    _finishError(CloudErrorCode.cancelled);
    await _server.close(force: true);
    await _subscription.cancel();
  }
}
