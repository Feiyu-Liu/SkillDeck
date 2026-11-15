import 'dart:async';

import '../cancellation.dart';
import '../errors.dart';
import '../http/transport.dart';
import '../protocol/codec.dart';
import 'loopback.dart';
import 'models.dart';

/// Opens a validated service login URL in the system browser.
typedef LaunchCloudBrowser = Future<void> Function(Uri uri);

/// Constructs the ephemeral local callback boundary.
typedef CloudListenerFactory = Future<CloudLoginListener> Function({
  required String state,
  required Duration timeout,
  required CloudCancellation cancellation,
});

/// Coordinates browser login without exposing credentials as application state.
final class CloudAuthLease {
  CloudAuthLease._(this._owner, this._epoch, this.session);
  final CloudAuthClient _owner;
  final int _epoch;

  /// The safe identity captured for one logical operation.
  final CloudSession session;
  @override
  String toString() => 'CloudAuthLease([redacted])';
}

/// Coordinates browser login without exposing credentials as application state.
final class CloudAuthClient {
  /// Creates an auth client with explicit transport, browser and secure storage.
  CloudAuthClient({
    required this._transport,
    required SecureSessionStore secureStore,
    required this._launchBrowser,
    CloudListenerFactory? listenerFactory,
  }) : _store = secureStore,
       _listenerFactory =
           listenerFactory ??
           (({required state, required timeout, required cancellation}) =>
               LoopbackLoginListener.bind(
                 state: state,
                 timeout: timeout,
                 cancellation: cancellation,
               ));

  final CloudTransport _transport;
  final SecureSessionStore _store;
  final LaunchCloudBrowser _launchBrowser;
  final CloudListenerFactory _listenerFactory;
  Future<void> _storageTail = Future.value();
  SecureSessionRecord? _record;
  CloudCancellation? _login;
  final Set<CloudCancellation> _requests = {};
  int _epoch = 0;
  bool _closed = false;

  /// The verified safe identity, available only after secure persistence succeeds.
  CloudSession? get currentSession => _record?.session;

  /// Captures an opaque epoch-bound authorization lease before asynchronous work.
  CloudAuthLease captureLease() {
    if (_login != null) {
      throw const CloudException(CloudErrorCode.operationInProgress);
    }
    final record = _record;
    if (_closed || record == null) {
      throw const CloudException(CloudErrorCode.unauthorized);
    }
    return CloudAuthLease._(this, _epoch, record.session);
  }

  /// Rejects a result or request whose authentication transition has changed.
  void checkLease(CloudAuthLease lease) {
    final record = _record;
    if (!identical(lease._owner, this) ||
        lease._epoch != _epoch ||
        _login != null ||
        record == null ||
        record.session.accountId != lease.session.accountId ||
        record.session.deviceId != lease.session.deviceId ||
        record.session.sessionId != lease.session.sessionId) {
      throw const CloudException(CloudErrorCode.cancelled);
    }
  }

  void _beginTransition(CloudCancellation operation) {
    _login = operation;
    _record = null;
    for (final request in List.of(_requests)) {
      request.cancel();
    }
  }

  Future<T> _cancelable<T>(
    Future<T> Function() action,
    CloudCancellation operation,
  ) async {
    operation.throwIfCancelled();
    final stopped = Completer<T>();
    final unlisten = operation.listen(() {
      if (!stopped.isCompleted) {
        stopped.completeError(const CloudException(CloudErrorCode.cancelled));
      }
    });
    try {
      return await Future.any([action(), stopped.future]);
    } finally {
      unlisten();
    }
  }

  Future<T> _storage<T>(Future<T> Function() action) async {
    final prior = _storageTail;
    final released = Completer<void>();
    _storageTail = released.future;
    await prior;
    try {
      return await action();
    } finally {
      released.complete();
    }
  }

  void _check(int epoch, [CloudCancellation? cancellation]) {
    cancellation?.throwIfCancelled();
    if (_closed || epoch != _epoch) {
      throw const CloudException(CloudErrorCode.cancelled);
    }
  }

  Future<CloudResponse> _send(
    CloudRequest request, {
    CloudCredential? credential,
    CloudCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    try {
      return await _cancelable(
        () => _transport.request(
          request,
          credential: credential,
          cancellation: cancellation,
        ),
        cancellation ?? CloudCancellation(),
      );
    } on CloudException {
      rethrow;
    } catch (_) {
      throw const CloudException(CloudErrorCode.unavailable, retryable: true);
    }
  }

  /// Signs in through a real system browser and verifies the new device session.
  Future<CloudSession> signIn({
    required String deviceName,
    required String platform,
    Duration timeout = const Duration(minutes: 10),
    CloudCancellation? cancellation,
  }) async {
    if (_closed) throw const CloudException(CloudErrorCode.cancelled);
    if (_login != null) {
      throw const CloudException(CloudErrorCode.operationInProgress);
    }
    if (deviceName.isEmpty ||
        deviceName.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(deviceName) ||
        !['macos', 'windows', 'linux'].contains(platform) ||
        timeout <= Duration.zero) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    cancellation?.throwIfCancelled();
    final epoch = ++_epoch;
    final operation = CloudCancellation();
    _beginTransition(operation);
    final unlink = cancellation?.listen(operation.cancel);
    var timedOut = false;
    final deadline = Timer(timeout, () {
      timedOut = true;
      operation.cancel();
    });
    CloudLoginListener? listener;
    try {
      final state = randomCloudToken(), verifier = randomCloudToken();
      listener = await _listenerFactory(
        state: state,
        timeout: timeout,
        cancellation: operation,
      );
      _check(epoch, operation);
      final redirect = listener.redirectUri;
      if (redirect.scheme != 'http' ||
          redirect.host != '127.0.0.1' ||
          !redirect.hasPort ||
          redirect.port < 1024 ||
          redirect.path != '/callback' ||
          redirect.userInfo.isNotEmpty ||
          redirect.hasQuery ||
          redirect.hasFragment) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      final start = envelope(
        await _send(
          CloudRequest(
            method: 'POST',
            path: '/v1/auth/handoff/start',
            body: {
              'state': state,
              'challenge': cloudPKCEChallenge(verifier),
              'challengeMethod': 'S256',
              'redirect': redirect.toString(),
              'deviceName': deviceName,
              'platform': platform,
            },
          ),
          cancellation: operation,
        ),
      );
      _check(epoch, operation);
      final transaction = text(start['transactionId'], maximum: 43);
      final login = Uri.tryParse(text(start['loginURL']));
      if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(transaction) ||
          login == null ||
          login.scheme != 'https' ||
          login.origin != _transport.baseUri.origin ||
          login.userInfo.isNotEmpty ||
          login.hasFragment ||
          login.path != '/v1/auth/handoff/bind' ||
          login.queryParametersAll.length != 2 ||
          login.queryParametersAll['transactionId']?.length != 1 ||
          login.queryParameters['transactionId'] != transaction ||
          login.queryParametersAll['browserToken']?.length != 1 ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$')
              .hasMatch(login.queryParameters['browserToken'] ?? '')) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      try {
        await _cancelable(() => _launchBrowser(login), operation);
      } on CloudException {
        rethrow;
      } catch (_) {
        throw const CloudException(CloudErrorCode.browserLaunch);
      }
      _check(epoch, operation);
      final code = await listener.result;
      _check(epoch, operation);
      if (code.state != state ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(code.code)) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      final exchanged = envelope(
        await _send(
          CloudRequest(
            method: 'POST',
            path: '/v1/auth/handoff/exchange',
            body: {
              'code': code.code,
              'verifier': verifier,
              'state': state,
              'redirect': redirect.toString(),
            },
          ),
          cancellation: operation,
        ),
      );
      _check(epoch, operation);
      final credential = CloudCredential(text(exchanged['token']));
      final expectedDevice = identifier(exchanged['deviceId']);
      integer(exchanged['expiresAt'], minimum: 1);
      final session = await _verify(credential, operation);
      _check(epoch, operation);
      if (session.deviceId != expectedDevice) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      final record = SecureSessionRecord(
        credential: credential,
        session: session,
        serviceOrigin: Uri.parse(_transport.baseUri.origin),
      );
      await _storage(() async {
        _check(epoch, operation);
        try {
          await _store.write(record);
        } catch (_) {
          throw const CloudException(CloudErrorCode.secureStorage);
        }
        if (epoch != _epoch || operation.isCancelled || _closed) {
          // The gate prevents this cleanup from clearing a newer login.
          try {
            await _store.clear();
          } catch (_) {
            throw const CloudException(CloudErrorCode.secureStorage);
          }
          throw const CloudException(CloudErrorCode.cancelled);
        }
        _record = record;
      });
      return session;
    } on CloudException {
      if (timedOut) throw const CloudException(CloudErrorCode.timeout);
      rethrow;
    } finally {
      deadline.cancel();
      unlink?.call();
      await listener?.cancel();
      if (identical(_login, operation)) _login = null;
    }
  }

  Future<CloudSession> _verify(
    CloudCredential credential,
    CloudCancellation cancellation,
  ) async => CloudSession.fromJson(
    envelope(
      await _send(
        CloudRequest(method: 'GET', path: '/v1/session'),
        credential: credential,
        cancellation: cancellation,
      ),
    ),
  );

  /// Restores only after the server confirms the stored account/device binding.
  Future<CloudSession?> restore({CloudCancellation? cancellation}) async {
    if (_closed) throw const CloudException(CloudErrorCode.cancelled);
    if (_login != null) {
      throw const CloudException(CloudErrorCode.operationInProgress);
    }
    final epoch = ++_epoch, operation = CloudCancellation();
    _beginTransition(operation);
    final unlink = cancellation?.listen(operation.cancel);
    _requests.add(operation);
    try {
      final stored = await _storage(() async {
        _check(epoch, operation);
        try {
          return await _store.read();
        } catch (_) {
          throw const CloudException(CloudErrorCode.secureStorage);
        }
      });
      _check(epoch, operation);
      if (stored == null) {
        _record = null;
        return null;
      }
      if (stored.serviceOrigin.origin != _transport.baseUri.origin) {
        throw const CloudException(CloudErrorCode.invalidConfiguration);
      }
      try {
        final session = await _verify(stored.credential, operation);
        _check(epoch, operation);
        if (session.accountId != stored.session.accountId ||
            session.deviceId != stored.session.deviceId ||
            session.sessionId != stored.session.sessionId) {
          throw const CloudException(CloudErrorCode.invalidResponse);
        }
        _record = SecureSessionRecord(
          credential: stored.credential,
          session: session,
          serviceOrigin: stored.serviceOrigin,
        );
        return session;
      } on CloudException catch (error) {
        if (error.code == CloudErrorCode.unauthorized) {
          await _clearIfCurrent(epoch);
          return null;
        }
        rethrow;
      }
    } finally {
      _requests.remove(operation);
      unlink?.call();
      if (identical(_login, operation)) _login = null;
    }
  }

  Future<void> _clearIfCurrent(int epoch) async {
    await _storage(() async {
      if (epoch != _epoch) return;
      _record = null;
      try {
        await _store.clear();
      } catch (_) {
        throw const CloudException(CloudErrorCode.secureStorage);
      }
    });
  }

  /// Sends an authenticated request without exporting the underlying credential.
  Future<Map<String, Object?>> authorizedRequest(
    CloudRequest request, {
    CloudCancellation? cancellation,
    CloudAuthLease? expectedLease,
  }) async {
    if (_login != null) {
      throw const CloudException(CloudErrorCode.operationInProgress);
    }
    if (expectedLease != null) checkLease(expectedLease);
    final record = _record;
    if (_closed || record == null) {
      throw const CloudException(CloudErrorCode.unauthorized);
    }
    final epoch = _epoch, operation = CloudCancellation();
    final unlink = cancellation?.listen(operation.cancel);
    _requests.add(operation);
    try {
      final response = await _send(
        request,
        credential: record.credential,
        cancellation: operation,
      );
      _check(epoch, operation);
      return envelope(response);
    } on CloudException catch (error) {
      if (error.code == CloudErrorCode.unauthorized && epoch == _epoch) {
        await _clearIfCurrent(epoch);
      }
      rethrow;
    } finally {
      _requests.remove(operation);
      unlink?.call();
    }
  }

  /// Reads safe device metadata for the verified account.
  Future<List<CloudDevice>> listDevices({
    CloudCancellation? cancellation,
  }) async {
    final result = await authorizedRequest(
      CloudRequest(method: 'GET', path: '/v1/devices'),
      cancellation: cancellation,
    );
    final devices = result['devices'];
    if (devices is! List<Object?>) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    return List.unmodifiable(
      devices.map((item) => CloudDevice.fromJson(object(item))),
    );
  }

  /// Revokes a device and reports whether provider token cleanup remains pending.
  Future<bool> revokeDevice(
    String deviceId, {
    CloudCancellation? cancellation,
  }) async {
    identifier(deviceId);
    final result = await authorizedRequest(
      CloudRequest(
        method: 'POST',
        path: '/v1/devices/revoke',
        body: {'deviceId': deviceId},
      ),
      cancellation: cancellation,
    );
    final pending = boolean(result['pending']);
    if (_record?.session.deviceId == deviceId) await logoutCredentials();
    return pending;
  }

  /// Stops requests and removes credentials while preserving synchronization data.
  Future<void> logoutCredentials() async {
    ++_epoch;
    _record = null;
    _login?.cancel();
    _login = null;
    for (final request in List.of(_requests)) {
      request.cancel();
    }
    await _storage(() async {
      try {
        await _store.clear();
      } catch (_) {
        throw const CloudException(CloudErrorCode.secureStorage);
      }
    });
  }

  /// Stops requests and owned connections without deleting synchronization data.
  Future<void> close() async {
    _closed = true;
    ++_epoch;
    _record = null;
    _login?.cancel();
    _login = null;
    for (final request in List.of(_requests)) {
      request.cancel();
    }
    _transport.close();
    await _storageTail;
  }
}
