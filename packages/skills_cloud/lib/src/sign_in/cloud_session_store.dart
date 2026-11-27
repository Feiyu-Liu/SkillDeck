import 'cloud_service_origin.dart';

/// The Cloud Account as last verified by the issuing service.
final class CloudAccount {
  const CloudAccount({
    required this.id,
    required this.email,
    required this.sessionExpiresAt,
  });

  /// An opaque account identifier.
  final String id;

  /// Shown in Settings. Never log it.
  final String email;

  final DateTime sessionExpiresAt;
}

/// One Cloud Session token, its issuing origin, and its last verified account.
final class StoredCloudSession {
  const StoredCloudSession({
    required this.origin,
    required this.token,
    this.account,
  });

  final CloudServiceOrigin origin;

  /// The bearer token. Send it only to [origin], and never log it.
  final String token;

  /// For display when the service cannot be reached.
  final CloudAccount? account;

  @override
  String toString() => 'StoredCloudSession($origin)';
}

/// Keeps at most one Cloud Session per service origin.
///
/// The App implements it with platform secure storage. Nothing else may hold
/// the token.
abstract interface class CloudSessionStore {
  Future<StoredCloudSession?> read(CloudServiceOrigin origin);

  /// Replaces the session stored for the session's origin.
  Future<void> write(StoredCloudSession session);

  Future<void> delete(CloudServiceOrigin origin);
}

/// A [CloudSessionStore] that keeps sessions in memory, for tests.
final class InMemoryCloudSessionStore implements CloudSessionStore {
  final _sessions = <CloudServiceOrigin, StoredCloudSession>{};

  @override
  Future<StoredCloudSession?> read(CloudServiceOrigin origin) async =>
      _sessions[origin];

  @override
  Future<void> write(StoredCloudSession session) async {
    _sessions[session.origin] = session;
  }

  @override
  Future<void> delete(CloudServiceOrigin origin) async {
    _sessions.remove(origin);
  }
}
