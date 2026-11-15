import '../http/transport.dart';
import '../protocol/codec.dart';
import '../errors.dart';

/// A verified, credential-free account and device identity.
final class CloudSession {
  /// Creates the identity returned by the authenticated service.
  const CloudSession({
    required this.accountId,
    required this.deviceId,
    required this.sessionId,
  });

  /// Parses the safe `/v1/session` result.
  factory CloudSession.fromJson(Map<String, Object?> json) => CloudSession(
    accountId: identifier(json['accountId']),
    deviceId: identifier(json['deviceId']),
    sessionId: identifier(json['sessionId']),
  );

  /// The server account ID.
  final String accountId;

  /// The server-minted device ID.
  final String deviceId;

  /// The database session identity, never its bearer token.
  final String sessionId;
  @override
  String toString() => 'CloudSession([redacted identifiers])';
}

/// One atomic secure-storage record, never an ordinary file or database row.
final class SecureSessionRecord {
  /// Creates a record owned by the platform secure-storage port.
  SecureSessionRecord({
    required this.credential,
    required this.session,
    required this.serviceOrigin,
  }) {
    if (serviceOrigin.scheme != 'https' ||
        serviceOrigin.host.isEmpty ||
        serviceOrigin.userInfo.isNotEmpty ||
        serviceOrigin.toString() != serviceOrigin.origin) {
      throw const CloudException(CloudErrorCode.secureStorage);
    }
  }

  /// Decodes a record read exclusively from platform secure storage.
  factory SecureSessionRecord.fromSecureJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const CloudException(CloudErrorCode.secureStorage);
    }
    return SecureSessionRecord(
      credential: CloudCredential(text(json['token'])),
      serviceOrigin: Uri.parse(text(json['serviceOrigin'])),
      session: CloudSession.fromJson(object(json['session'])),
    );
  }

  /// The credential restricted to transport and secure-storage adapters.
  final CloudCredential credential;

  /// The trusted origin to which this credential may be sent.
  final Uri serviceOrigin;

  /// The previously verified safe identity, reverified during restore.
  final CloudSession session;

  /// Encodes credentials exclusively for an atomic platform secure write.
  Map<String, Object?> toSecureJson() => {
    'version': 1,
    'token': credential.token,
    'serviceOrigin': serviceOrigin.origin,
    'session': {
      'accountId': session.accountId,
      'deviceId': session.deviceId,
      'sessionId': session.sessionId,
    },
  };
  @override
  String toString() => 'SecureSessionRecord([redacted])';
}

/// Platform secure storage with atomic replacement of the complete record.
abstract interface class SecureSessionStore {
  /// Reads a complete record, or `null` if none exists.
  Future<SecureSessionRecord?> read();

  /// Atomically replaces the complete record or leaves the previous one intact.
  Future<void> write(SecureSessionRecord record);

  /// Removes the credential record without touching synchronization data.
  Future<void> clear();
}

/// Safe metadata for one account device.
final class CloudDevice {
  /// Parses device metadata without any session or provider token.
  CloudDevice.fromJson(Map<String, Object?> json)
    : id = identifier(json['id']),
      name = text(json['name'], maximum: 80),
      platform = text(json['platform'], maximum: 16),
      createdAt = timestamp(json['createdAt']),
      lastSeenAt = timestamp(json['lastSeenAt']),
      revokedAt = json['revokedAt'] == null
          ? null
          : timestamp(json['revokedAt']);

  /// The server device ID.
  final String id;

  /// The user-visible device name.
  final String name;

  /// The device operating system.
  final String platform;

  /// The creation time.
  final DateTime createdAt;

  /// The last service observation.
  final DateTime lastSeenAt;

  /// The revocation time, if revoked.
  final DateTime? revokedAt;
  @override
  String toString() => 'CloudDevice([redacted identifiers and name])';
}
