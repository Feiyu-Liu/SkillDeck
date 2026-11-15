import '../auth/client.dart';
import '../auth/loopback.dart';
import '../cancellation.dart';
import '../errors.dart';
import '../http/transport.dart';
import 'codec.dart';
import 'canonical.dart';
import 'intents.dart';
import 'models.dart';
import 'requests.dart';
import 'transfers.dart';

/// The bounded Personal Sync wire client, without Workspace access or apply.
final class CloudSyncClient {
  /// Creates a client whose mutations require durable actor-bound origins.
  CloudSyncClient({
    required this._auth,
    required this._intents,
    DateTime Function()? clock,
    this.transferRemotePolicy = const CloudTransferRemotePolicy.httpsOnly(),
  }) : _clock = clock ?? DateTime.now;
  final CloudAuthClient _auth;
  final MutationIntentStore _intents;
  final DateTime Function() _clock;
  final CloudTransferRemotePolicy transferRemotePolicy;

  /// Requests one operation-scoped write credential for a prepared upload.
  Future<CloudTransferLease> preparedWriteTransfer({
    required String operationId,
    required String uploadId,
    CloudCancellation? cancellation,
  }) async {
    identifier(operationId);
    identifier(uploadId);
    return _transfer(
      {'operationId': operationId, 'scope': 'write', 'uploadId': uploadId},
      CloudTransferAccess.write,
      cancellation,
    );
  }

  /// Requests a short-lived native Git read/write credential for one lineage.
  Future<CloudTransferLease> lineageTransfer({
    required String operationId,
    required String lineageId,
    required int generation,
    required CloudTransferAccess access,
    CloudCancellation? cancellation,
  }) async {
    identifier(operationId);
    identifier(lineageId);
    integer(generation, minimum: 1);
    return _transfer(
      {
        'operationId': operationId,
        'scope': access.name,
        'lineageId': lineageId,
        'generation': generation,
      },
      access,
      cancellation,
    );
  }

  Future<CloudTransferLease> _transfer(
    Map<String, Object?> data,
    CloudTransferAccess access,
    CloudCancellation? cancellation,
  ) async {
    final response = await _auth.authorizedRequest(
      CloudRequest(
        method: 'POST',
        path: '/v1/sync/transfers',
        body: {
          'protocolVersion': 1,
          'requestId': randomCloudToken(),
          'data': data,
        },
      ),
      cancellation: cancellation,
    );
    final lease = CloudTransferLease.fromJson(
      response,
      policy: transferRemotePolicy,
      clock: _clock,
    );
    if (lease.operationId != data['operationId'] ||
        lease.access != access ||
        lease.uploadId != data['uploadId'] ||
        lease.lineageId != data['lineageId'] ||
        lease.generation != data['generation']) {
      lease.invalidate();
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    return lease;
  }

  DateTime _now() {
    try {
      return _clock().toUtc();
    } catch (_) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }

  /// Creates a typed first-upload preparation intent.
  CloudMutationIntent createPrepareIntent(CloudPrepareRequest request) =>
      createIntent(
        operationId: request.operationId,
        path: '/v1/sync/commits/prepare',
        data: request.toJson(),
      );

  /// Creates a typed commit phase whose persisted origin remains authoritative.
  CloudMutationIntent createCommitIntent(CloudCommitRequest request) =>
      createIntent(
        operationId: request.operationId,
        path: '/v1/sync/commits',
        data: request.toJson(),
      );

  /// Sends one preparation phase and durably binds its returned upload handle.
  Future<CloudPreparedUpload> prepareUpload(
    CloudMutationIntent intent, {
    CloudCancellation? cancellation,
  }) async {
    if (intent.path != '/v1/sync/commits/prepare') {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    return CloudPreparedUpload.fromJson(
      await sendMutation(intent, cancellation: cancellation),
    );
  }

  /// Sends one commit phase and parses its exact decimal-sequence receipt.
  Future<CloudCommitReceipt> commit(
    CloudMutationIntent intent, {
    CloudCancellation? cancellation,
  }) async {
    if (intent.path != '/v1/sync/commits') {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    return CloudCommitReceipt.fromJson(
      await sendMutation(intent, cancellation: cancellation),
    );
  }

  /// Creates an immutable intent bound to the currently verified device.
  CloudMutationIntent createIntent({
    required String operationId,
    required String path,
    required Map<String, Object?> data,
  }) {
    final actor = _auth.currentSession;
    if (actor == null) throw const CloudException(CloudErrorCode.unauthorized);
    return CloudMutationIntent.fresh(
      key: CloudOperationKey(
        accountId: actor.accountId,
        deviceId: actor.deviceId,
        operationId: operationId,
      ),
      path: path,
      data: data,
    );
  }

  void _window(DateTime? origin, DateTime? last, DateTime now) {
    if (origin == null ||
        !origin.isUtc ||
        now.isBefore(origin) ||
        (last != null && (!last.isUtc || now.isBefore(last))) ||
        now.difference(origin) >= const Duration(hours: 24)) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }

  void _actor(CloudOperationKey key) {
    final actor = _auth.currentSession;
    if (actor == null ||
        actor.accountId != key.accountId ||
        actor.deviceId != key.deviceId) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }

  Future<CloudStoredOperation> _bindAttempt(CloudMutationIntent intent) async {
    _actor(intent.key);
    if (!await _intents.hasAuthoritativeScope(
      accountId: intent.key.accountId,
      deviceId: intent.key.deviceId,
    )) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    for (var contention = 0; contention < 3; contention++) {
      final prior = await _intents.readOperation(intent.key);
      final now = _now();
      if (prior == null && !intent.isFresh) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final origin = prior == null ? now : prior.originUtc;
      _window(origin, prior?.lastObservedUtc, now);
      if (prior != null &&
          (prior.key != intent.key || prior.family != intent.family)) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      if (intent.isFirstUploadCommit &&
          (prior == null ||
              !['upload', 'replacement'].contains(prior.family) ||
              !prior.phases.containsKey('/v1/sync/commits/prepare') ||
              prior.uploadId == null ||
              prior.uploadId != intent.data['uploadId'])) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final existing = prior?.phases[intent.path];
      if (existing != null &&
          canonicalPayload(existing) != canonicalPayload(intent.data)) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      final next = CloudStoredOperation(
        key: intent.key,
        version: (prior?.version ?? 0) + 1,
        family: intent.family,
        originUtc: origin,
        lastObservedUtc: now,
        phases: {...?prior?.phases, intent.path: intent.data},
        uploadId: prior?.uploadId,
      );
      if (await _intents.compareAndSet(
        expectedVersion: prior?.version,
        next: next,
      )) {
        return next;
      }
    }
    throw const CloudException(CloudErrorCode.needsReconciliation);
  }

  /// Sends once, requiring reconciliation after the original 24-hour boundary.
  ///
  /// Rebuilt intents and prepare-to-commit transitions reuse the earliest
  /// persisted origin. Local CAS contention is retried; HTTP is not.
  Future<Map<String, Object?>> sendMutation(
    CloudMutationIntent intent, {
    CloudCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final lease = _auth.captureLease();
    late final CloudStoredOperation attempt;
    try {
      attempt = await _bindAttempt(intent);
    } on CloudException {
      rethrow;
    } catch (_) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    _actor(intent.key);
    _auth.checkLease(lease);
    _window(attempt.originUtc, attempt.lastObservedUtc, _now());
    cancellation?.throwIfCancelled();
    final result = await _auth.authorizedRequest(
      CloudRequest(
        method: 'POST',
        path: intent.path,
        body: {
          'protocolVersion': 1,
          'requestId': randomCloudToken(),
          'data': intent.data,
        },
      ),
      cancellation: cancellation,
      expectedLease: lease,
    );
    if (intent.path == '/v1/sync/commits/prepare') {
      final uploadId = identifier(result['uploadId']);
      try {
        for (var contention = 0; contention < 3; contention++) {
          final prior = await _intents.readOperation(intent.key);
          if (prior == null ||
              !['upload', 'replacement'].contains(prior.family) ||
              canonicalPayload(prior.phases[intent.path]) !=
                  canonicalPayload(intent.data) ||
              (prior.uploadId != null && prior.uploadId != uploadId)) {
            throw const CloudException(CloudErrorCode.needsReconciliation);
          }
          if (await _intents.compareAndSet(
            expectedVersion: prior.version,
            next: CloudStoredOperation(
              key: prior.key,
              version: prior.version + 1,
              family: prior.family,
              originUtc: prior.originUtc,
              lastObservedUtc: prior.lastObservedUtc,
              phases: prior.phases,
              uploadId: uploadId,
            ),
          )) {
            _auth.checkLease(lease);
            return result;
          }
        }
        throw const CloudException(CloudErrorCode.needsReconciliation);
      } on CloudException {
        rethrow;
      } catch (_) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
    }
    _auth.checkLease(lease);
    return result;
  }

  /// Reads a bounded change page without changing inbox or apply progress.
  Future<CloudChangesPage> changes({
    required CloudSequence after,
    CloudSequence? highWatermark,
    CloudCancellation? cancellation,
  }) async {
    final page = CloudChangesPage.fromJson(
      await _auth.authorizedRequest(
        CloudRequest(
          method: 'GET',
          path: '/v1/sync/changes',
          query: {
            'protocolVersion': '1',
            'after': after.toJson(),
            if (highWatermark != null) 'highWatermark': highWatermark.toJson(),
          },
        ),
        cancellation: cancellation,
      ),
    );
    if (page.after != after ||
        (highWatermark != null && page.highWatermark != highWatermark)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    return page;
  }

  /// Creates a snapshot and returns its first immutable page.
  Future<CloudSnapshotPage> createSnapshot({
    String? requestKey,
    CloudCancellation? cancellation,
  }) async => CloudSnapshotPage.fromJson(
    await _auth.authorizedRequest(
      CloudRequest(
        method: 'POST',
        path: '/v1/sync/snapshots',
        body: {
          'protocolVersion': 1,
          'requestId': randomCloudToken(),
          'data': <String, Object?>{
            if (requestKey != null) 'requestKey': identifier(requestKey),
          },
        },
      ),
      cancellation: cancellation,
    ),
  );

  /// Continues exactly the expected snapshot and high-water mark.
  Future<CloudSnapshotPage> snapshotPage({
    required String snapshotId,
    required String pageCursor,
    required CloudSequence highWatermark,
    CloudCancellation? cancellation,
  }) async {
    identifier(snapshotId);
    text(pageCursor);
    final page = CloudSnapshotPage.fromJson(
      await _auth.authorizedRequest(
        CloudRequest(
          method: 'GET',
          path: '/v1/sync/snapshots/${Uri.encodeComponent(snapshotId)}',
          query: {'protocolVersion': '1', 'pageCursor': pageCursor},
        ),
        cancellation: cancellation,
      ),
    );
    if (page.snapshotId != snapshotId ||
        page.highWatermark != highWatermark ||
        page.pageCursor != pageCursor) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    return page;
  }

  /// Releases only this device's disposable, fully consumed snapshot handle.
  Future<void> releaseSnapshot(
    String snapshotId, {
    CloudCancellation? cancellation,
  }) async {
    identifier(snapshotId);
    final result = await _auth.authorizedRequest(
      CloudRequest(
        method: 'POST',
        path: '/v1/sync/snapshots/${Uri.encodeComponent(snapshotId)}/release',
        body: {
          'protocolVersion': 1,
          'requestId': randomCloudToken(),
          'data': <String, Object?>{},
        },
      ),
      cancellation: cancellation,
    );
    if (result['released'] != true) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
  }

  /// Reads recovery state without replaying a mutation.
  Future<Map<String, Object?>> operationStatus(
    String operationId, {
    CloudCancellation? cancellation,
  }) {
    identifier(operationId);
    return _auth.authorizedRequest(
      CloudRequest(
        method: 'GET',
        path: '/v1/sync/operations/${Uri.encodeComponent(operationId)}',
        query: {'protocolVersion': '1'},
      ),
      cancellation: cancellation,
    );
  }
}
