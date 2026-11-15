import '../errors.dart';
import '../http/transport.dart';
import 'codec.dart';

/// The actor-bound identity of one immutable business operation.
final class CloudOperationKey {
  /// Creates a key independent of request IDs and credential values.
  CloudOperationKey({
    required this.accountId,
    required this.deviceId,
    required this.operationId,
  }) {
    identifier(accountId);
    identifier(deviceId);
    identifier(operationId);
  }

  /// The authorized account.
  final String accountId;

  /// The original authorized device.
  final String deviceId;

  /// The stable business operation identity.
  final String operationId;
  @override
  bool operator ==(Object other) =>
      other is CloudOperationKey &&
      accountId == other.accountId &&
      deviceId == other.deviceId &&
      operationId == other.operationId;
  @override
  int get hashCode => Object.hash(accountId, deviceId, operationId);
  @override
  String toString() => 'CloudOperationKey([redacted])';
}

/// A credential-free immutable candidate for one operation phase.
final class CloudMutationIntent {
  /// Creates a genuinely new, never-sent operation phase.
  ///
  /// Do not use this factory to reconstruct a previously uncertain operation.
  factory CloudMutationIntent.fresh({
    required CloudOperationKey key,
    required String path,
    required Map<String, Object?> data,
  }) => CloudMutationIntent._(
    key: key,
    path: path,
    data: data,
    firstAttemptUtc: null,
    isFresh: true,
  );

  /// Restores a queued phase without treating a lost origin as a new operation.
  factory CloudMutationIntent.restored({
    required CloudOperationKey key,
    required String path,
    required Map<String, Object?> data,
    required DateTime? firstAttemptUtc,
  }) => CloudMutationIntent._(
    key: key,
    path: path,
    data: data,
    firstAttemptUtc: firstAttemptUtc,
    isFresh: false,
  );
  CloudMutationIntent._({
    required this.key,
    required this.path,
    required Map<String, Object?> data,
    required this.firstAttemptUtc,
    required this.isFresh,
  }) : data = freezeMap({...data, 'operationId': key.operationId}) {
    if (![
          '/v1/sync/commits/prepare',
          '/v1/sync/commits',
          '/v1/sync/metadata',
          '/v1/sync/lifecycle',
          '/v1/sync/repair',
        ].contains(path) ||
        (data.containsKey('operationId') &&
            data['operationId'] != key.operationId)) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
  }

  /// The original account/device/operation binding.
  final CloudOperationKey key;

  /// The exact operation phase endpoint.
  final String path;

  /// The immutable, credential-free business payload.
  final Map<String, Object?> data;

  /// Whether this is explicitly marked new and never previously sent.
  final bool isFresh;

  /// The restored origin hint; authoritative durable records take precedence.
  final DateTime? firstAttemptUtc;

  /// Whether this commit depends on a persisted first-upload preparation.
  bool get isFirstUploadCommit =>
      (path == '/v1/sync/commits' ||
          path == '/v1/sync/lifecycle' && data['kind'] == 'replacement') &&
      data.containsKey('uploadId');

  /// The mutually exclusive business family, excluding valid upload phases.
  String get family => switch (path) {
    '/v1/sync/commits/prepare' when data.containsKey('replacement') =>
      'replacement',
    '/v1/sync/commits/prepare' => 'upload',
    '/v1/sync/lifecycle' when data['kind'] == 'replacement' => 'replacement',
    '/v1/sync/repair' => 'repair',
    '/v1/sync/commits' when isFirstUploadCommit => 'upload',
    '/v1/sync/commits' => 'commit',
    '/v1/sync/metadata' => 'metadata',
    _ => 'lifecycle',
  };
  @override
  String toString() => 'CloudMutationIntent([redacted identity and payload])';
}

/// An atomic operation record shared across phases and client restarts.
final class CloudStoredOperation {
  /// Creates an authoritative origin and immutable phase payload snapshot.
  CloudStoredOperation({
    required this.key,
    required this.version,
    required this.family,
    required this.originUtc,
    required this.lastObservedUtc,
    required Map<String, Map<String, Object?>> phases,
    this.uploadId,
  }) : phases = Map.unmodifiable(
         phases.map((key, value) => MapEntry(key, freezeMap(value))),
       );

  /// The stable actor and operation key.
  final CloudOperationKey key;

  /// The monotonically increasing local CAS revision.
  final int version;

  /// The immutable business family.
  final String family;

  /// The earliest persisted first-attempt time, never reset by another phase.
  final DateTime? originUtc;

  /// The most recent accepted wall-clock observation.
  final DateTime? lastObservedUtc;

  /// The endpoint-bound immutable payload for each admitted phase.
  final Map<String, Map<String, Object?>> phases;

  /// The server preparation result authorizing the first commit phase.
  final String? uploadId;
  @override
  String toString() =>
      'CloudStoredOperation(version: $version, [redacted intent])';
}

/// Atomic durable storage for credential-free operation origins and phases.
abstract interface class MutationIntentStore {
  /// Confirms the account/device storage scope is intact and reconciled.
  ///
  /// Missing/reset/lost scope metadata must return false, including when an
  /// operation record may have disappeared. New scope creation is an explicit
  /// application/bootstrap decision, never a side effect of this read.
  Future<bool> hasAuthoritativeScope({
    required String accountId,
    required String deviceId,
  });

  /// Reads authoritative records, including those written before restart.
  Future<CloudStoredOperation?> readOperation(CloudOperationKey key);

  /// Atomically compares the revision and durably persists the next record.
  ///
  /// A `null` expected revision means the key must be absent. Returns `false`
  /// on contention without changing data. Successful completion means durable
  /// storage before transmission; credentials never belong in this store.
  /// The same transaction must reject a scope that is no longer authoritative.
  Future<bool> compareAndSet({
    required int? expectedVersion,
    required CloudStoredOperation next,
  });
}
