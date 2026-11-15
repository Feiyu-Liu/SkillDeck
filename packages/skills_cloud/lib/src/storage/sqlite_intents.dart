import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../auth/models.dart';
import '../errors.dart';
import '../protocol/canonical.dart';
import '../protocol/intents.dart';
import 'sqlite_schema.dart';
import 'sqlite_sync_store.dart';
import '../sync/store.dart';

/// A credential-free Cloud database, physically separate from Skill Workspace.
final class SqliteCloudDatabase {
  SqliteCloudDatabase._(this._database, this.serviceOrigin);

  /// Opens only an explicitly supplied Cloud database and trusted origin.
  factory SqliteCloudDatabase.open({
    required String path,
    required Uri serviceOrigin,
  }) {
    if (serviceOrigin.scheme != 'https' ||
        serviceOrigin.userInfo.isNotEmpty ||
        serviceOrigin.host.isEmpty ||
        serviceOrigin.toString() != serviceOrigin.origin) {
      throw const CloudException(CloudErrorCode.invalidConfiguration);
    }
    Database? opened;
    try {
      final database = sqlite3.open(path);
      opened = database;
      database.execute('PRAGMA busy_timeout=5000');
      database.execute('PRAGMA foreign_keys=ON');
      initializeCloudSchema(database);
      return SqliteCloudDatabase._(database, serviceOrigin);
    } catch (_) {
      opened?.close();
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }
  final Database _database;

  /// The trusted namespace, never a credential-bearing URL.
  final Uri serviceOrigin;

  /// Worker-side synchronous storage; Flutter callers use the background adapter.
  CloudSyncStore get syncStore {
    _open();
    return SqliteSyncStore(_database, serviceOrigin);
  }

  bool _closed = false;
  void _open() {
    if (_closed) throw const CloudException(CloudErrorCode.cancelled);
  }

  /// Initializes device authority only after a new server-minted sign-in.
  ///
  /// App restore must never call this merely because its local database is
  /// missing. Existing scopes are preserved and no Workspace is made ready.
  Future<void> initializeNewDeviceScope(CloudSession newlySignedIn) async {
    _open();
    try {
      _database.execute(
        'INSERT INTO cloud_device_scope VALUES(?,?,?,1) ON CONFLICT DO NOTHING',
        [serviceOrigin.origin, newlySignedIn.accountId, newlySignedIn.deviceId],
      );
    } catch (_) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }

  Future<bool> hasEnabledOptIn({CloudSession? session}) async {
    _open();
    return _database.select(
      'SELECT 1 FROM cloud_sync_scope WHERE origin=? AND status=\'enabled\'${session == null ? '' : ' AND account_id=? AND device_id=?'} LIMIT 1',
      [
        serviceOrigin.origin,
        if (session != null) ...[session.accountId, session.deviceId],
      ],
    ).isNotEmpty;
  }

  /// Reports whether device state survived, without creating missing scopes.
  Future<bool> hasDeviceScope(CloudSession session) async {
    _open();
    return _database.select(
      'SELECT 1 FROM cloud_device_scope WHERE origin=? AND account_id=? AND device_id=? AND ready=1',
      [serviceOrigin.origin, session.accountId, session.deviceId],
    ).isNotEmpty;
  }

  /// Binds operation storage to an explicit qualified Workspace identity.
  MutationIntentStore forWorkspace(String workspaceScopeId) {
    if (workspaceScopeId.isEmpty || workspaceScopeId.length > 256) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    return _SqliteIntentStore(this, workspaceScopeId);
  }

  /// Marks a Workspace scope ready only after explicit authoritative reconcile.
  ///
  /// This is not called by the authentication settings page or by restore.
  Future<void> markWorkspaceReconciled({
    required CloudSession session,
    required String workspaceScopeId,
  }) async {
    _open();
    forWorkspace(workspaceScopeId);
    if (!await hasDeviceScope(session)) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    _database.execute(
      'INSERT INTO cloud_workspace_scope VALUES(?,?,?,?,1) ON CONFLICT DO UPDATE SET ready=1',
      [
        serviceOrigin.origin,
        session.accountId,
        session.deviceId,
        workspaceScopeId,
      ],
    );
  }

  /// Fences future mutations without deleting synchronization data or receipts.
  Future<void> requireWorkspaceReconciliation({
    required CloudSession session,
    required String workspaceScopeId,
  }) async {
    _open();
    _database.execute(
      'UPDATE cloud_workspace_scope SET ready=0 WHERE origin=? AND account_id=? AND device_id=? AND workspace_id=?',
      [
        serviceOrigin.origin,
        session.accountId,
        session.deviceId,
        workspaceScopeId,
      ],
    );
  }

  /// Closes only the owned Cloud database.
  void close() {
    if (_closed) return;
    _closed = true;
    _database.close();
  }
}

final class _SqliteIntentStore implements MutationIntentStore {
  _SqliteIntentStore(this.owner, this.workspace);
  final SqliteCloudDatabase owner;
  final String workspace;
  List<Object?> _scope(String account, String device) => [
    owner.serviceOrigin.origin,
    account,
    device,
    workspace,
  ];
  List<Object?> _key(CloudOperationKey key) => [
    ..._scope(key.accountId, key.deviceId),
    key.operationId,
  ];
  @override
  Future<bool> hasAuthoritativeScope({
    required String accountId,
    required String deviceId,
  }) async {
    owner._open();
    return _ready(accountId, deviceId);
  }

  bool _ready(String account, String device) => owner._database.select(
    '''SELECT 1 FROM cloud_workspace_scope w
    JOIN cloud_device_scope d ON d.origin=w.origin AND d.account_id=w.account_id AND d.device_id=w.device_id
    WHERE w.origin=? AND w.account_id=? AND w.device_id=? AND w.workspace_id=? AND w.ready=1 AND d.ready=1''',
    _scope(account, device),
  ).isNotEmpty;
  CloudStoredOperation? _read(CloudOperationKey key) {
    final rows = owner._database.select(
      'SELECT * FROM cloud_operation WHERE origin=? AND account_id=? AND operation_id=?',
      [owner.serviceOrigin.origin, key.accountId, key.operationId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    if (row['workspace_id'] != workspace || row['device_id'] != key.deviceId) {
      throw const CloudException(CloudErrorCode.operationConflict);
    }
    final Object? decoded = jsonDecode(row['phases'] as String);
    if (decoded is! Map<String, Object?>) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    return CloudStoredOperation(
      key: CloudOperationKey(
        accountId: row['account_id'] as String,
        deviceId: row['device_id'] as String,
        operationId: row['operation_id'] as String,
      ),
      version: row['version'] as int,
      family: row['family'] as String,
      originUtc: row['origin_utc'] == null
          ? null
          : DateTime.tryParse(row['origin_utc'] as String),
      lastObservedUtc: row['observed_utc'] == null
          ? null
          : DateTime.tryParse(row['observed_utc'] as String),
      phases: decoded.map(
        (key, value) => MapEntry(key, value! as Map<String, Object?>),
      ),
      uploadId: row['upload_id'] as String?,
    );
  }

  @override
  Future<CloudStoredOperation?> readOperation(CloudOperationKey key) async {
    owner._open();
    try {
      return _read(key);
    } catch (_) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }

  @override
  Future<bool> compareAndSet({
    required int? expectedVersion,
    required CloudStoredOperation next,
  }) async {
    owner._open();
    final db = owner._database;
    var transaction = false;
    try {
      db.execute('BEGIN IMMEDIATE');
      transaction = true;
      if (!_ready(next.key.accountId, next.key.deviceId)) {
        db.execute('ROLLBACK');
        return false;
      }
      final prior = _read(next.key);
      if (prior?.version != expectedVersion ||
          next.version != (expectedVersion ?? 0) + 1 ||
          !_compatible(prior, next)) {
        db.execute('ROLLBACK');
        return false;
      }
      db.execute(
        '''INSERT INTO cloud_operation VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(origin,account_id,operation_id)
        DO UPDATE SET version=excluded.version,family=excluded.family,origin_utc=excluded.origin_utc,observed_utc=excluded.observed_utc,phases=excluded.phases,upload_id=excluded.upload_id''',
        [
          ..._key(next.key),
          next.version,
          next.family,
          next.originUtc?.toIso8601String(),
          next.lastObservedUtc?.toIso8601String(),
          jsonEncode(next.phases),
          next.uploadId,
        ],
      );
      db.execute('COMMIT');
      transaction = false;
      return true;
    } catch (_) {
      if (transaction) {
        try {
          db.execute('ROLLBACK');
        } catch (_) {}
      }
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }

  bool _compatible(CloudStoredOperation? prior, CloudStoredOperation next) {
    if (next.originUtc == null ||
        !next.originUtc!.isUtc ||
        next.lastObservedUtc == null ||
        !next.lastObservedUtc!.isUtc ||
        next.lastObservedUtc!.isBefore(next.originUtc!) ||
        next.phases.isEmpty) {
      return false;
    }
    final allowed = switch (next.family) {
      'upload' => {'/v1/sync/commits/prepare', '/v1/sync/commits'},
      'replacement' => {'/v1/sync/commits/prepare', '/v1/sync/lifecycle'},
      'repair' => {'/v1/sync/repair'},
      'commit' => {'/v1/sync/commits'},
      'metadata' => {'/v1/sync/metadata'},
      'lifecycle' => {'/v1/sync/lifecycle'},
      _ => <String>{},
    };
    if (next.phases.keys.any((path) => !allowed.contains(path))) return false;
    if (['upload', 'replacement'].contains(next.family) &&
        !next.phases.containsKey('/v1/sync/commits/prepare')) {
      return false;
    }
    if (prior == null) {
      return !['upload', 'replacement'].contains(next.family) ||
          next.phases.length == 1;
    }
    if (prior.family != next.family ||
        prior.originUtc != next.originUtc ||
        (prior.lastObservedUtc != null &&
            next.lastObservedUtc!.isBefore(prior.lastObservedUtc!)) ||
        (prior.uploadId != null && prior.uploadId != next.uploadId)) {
      return false;
    }
    for (final entry in prior.phases.entries) {
      if (canonicalPayload(entry.value) !=
          canonicalPayload(next.phases[entry.key])) {
        return false;
      }
    }
    final firstCommit =
        next.phases[next.family == 'replacement'
            ? '/v1/sync/lifecycle'
            : '/v1/sync/commits'];
    if (['upload', 'replacement'].contains(next.family) &&
        firstCommit != null &&
        (prior.uploadId == null || firstCommit['uploadId'] != prior.uploadId)) {
      return false;
    }
    return true;
  }
}
