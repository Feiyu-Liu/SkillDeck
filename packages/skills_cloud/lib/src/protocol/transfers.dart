import '../errors.dart';
import 'codec.dart';

enum CloudTransferAccess { read, write }

CloudTransferAccess _access(Object? value) => switch (value) {
  'read' => CloudTransferAccess.read,
  'write' => CloudTransferAccess.write,
  _ => throw const CloudException(CloudErrorCode.invalidResponse),
};
DateTime _now(DateTime Function() clock) {
  try {
    return clock().toUtc();
  } catch (_) {
    throw const CloudException(CloudErrorCode.unavailable);
  }
}

/// Explicit transport policy; loopback HTTP exists only for controlled tests.
final class CloudTransferRemotePolicy {
  const CloudTransferRemotePolicy.httpsOnly() : _loopback = false;
  const CloudTransferRemotePolicy.loopbackForTesting() : _loopback = true;
  final bool _loopback;
  Uri parse(Object? raw) {
    final value = text(raw), uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.toString() != value ||
        !(uri.scheme == 'https' ||
            _loopback &&
                uri.scheme == 'http' &&
                uri.host == '127.0.0.1' &&
                uri.hasPort &&
                uri.port >= 1024)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    return uri;
  }
}

/// A short-lived in-memory credential bound to one repository transfer intent.
final class CloudTransferLease {
  CloudTransferLease.fromJson(
    Map<String, Object?> json, {
    required CloudTransferRemotePolicy policy,
    DateTime Function()? clock,
  }) : operationId = identifier(json['operationId']),
       remote = policy.parse(json['remote']),
       access = _access(json['scope']),
       expiresAt = timestamp(json['expiresAt']),
       _token = text(json['token']),
       _clock = clock ?? DateTime.now,
       uploadId = json['uploadId'] == null
           ? null
           : identifier(json['uploadId']),
       lineageId = json['lineageId'] == null
           ? null
           : identifier(json['lineageId']),
       generation = json['generation'] == null
           ? null
           : integer(json['generation'], minimum: 1) {
    if (_token.contains(RegExp(r'\s')) ||
        _token.length > 4096 ||
        !((uploadId != null &&
                lineageId == null &&
                generation == null &&
                access == CloudTransferAccess.write) ||
            (uploadId == null && lineageId != null && generation != null))) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    _issuedAt = _now(_clock);
    final ttl = expiresAt.difference(_issuedAt);
    // At most 30 seconds of declared clock skew is tolerated; the monotonic
    // local lifetime is still capped at ten minutes, never extended by rollback.
    if (ttl <= Duration.zero || ttl > const Duration(seconds: 630)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    _lifetime = ttl > const Duration(minutes: 10)
        ? const Duration(minutes: 10)
        : ttl;
    _elapsed.start();
  }
  final String operationId;
  final Uri remote;
  final CloudTransferAccess access;
  final String? uploadId, lineageId;
  final int? generation;
  final DateTime expiresAt;
  final String _token;
  final DateTime Function() _clock;
  late final DateTime _issuedAt;
  late final Duration _lifetime;
  final Stopwatch _elapsed = Stopwatch();
  bool _invalidated = false;

  /// Supplies headers for the multiple Git HTTP requests of this one transfer.
  Future<List<String>> authorizationHeaders() async {
    final now = _now(_clock);
    if (_invalidated ||
        now.isBefore(_issuedAt) ||
        !now.isBefore(expiresAt) ||
        _elapsed.elapsed >= _lifetime) {
      throw const CloudException(CloudErrorCode.unauthorized);
    }
    return ['Authorization: Bearer $_token'];
  }

  /// Prevents further callback use after the native transfer finishes.
  ///
  /// Dart strings cannot be explicitly wiped; the token becomes collectible
  /// when this lease and native callback copies are released.
  void invalidate() {
    _invalidated = true;
    _elapsed.stop();
  }

  @override
  String toString() =>
      'CloudTransferLease(access: ${access.name}, [redacted credential and remote])';
}
