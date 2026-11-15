import 'dart:isolate';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'sqlite_schema.dart';

import '../auth/models.dart';
import '../errors.dart';
import '../protocol/intents.dart';
import '../protocol/codec.dart';
import '../protocol/models.dart';
import '../protocol/content_manifest.dart';
import '../sync/models.dart';
import '../sync/store.dart';
import '../sync/workspace_port.dart';
import 'sqlite_intents.dart';

/// Account/device authority independent of authentication credential storage.
abstract interface class CloudDeviceScopeStore {
  Future<void> initializeNewDeviceScope(CloudSession newlySignedIn);
  Future<bool> hasDeviceScope(CloudSession session);
  Future<void> close();
}

enum _Command {
  probe,
  newDevice,
  device,
  ready,
  read,
  cas,
  reconcile,
  fence,
  sync,
  enabledOptIn,
}

// One short-lived worker owns each actual connection. There is no SQL work or
// five-second SQLite busy wait on the Flutter/UI isolate, and no RPC framework.
Future<T> _worker<T>(
  String path,
  Uri origin,
  _Command command,
  Object? payload,
) => Isolate.run<T>(() async {
  final database = SqliteCloudDatabase.open(path: path, serviceOrigin: origin);
  try {
    Object? result;
    switch (command) {
      case _Command.probe:
        break;
      case _Command.newDevice:
        await database.initializeNewDeviceScope(payload! as CloudSession);
      case _Command.device:
        result = await database.hasDeviceScope(payload! as CloudSession);
      case _Command.ready:
        final (workspace, key) = payload! as (String, CloudOperationKey);
        result = await database
            .forWorkspace(workspace)
            .hasAuthoritativeScope(
              accountId: key.accountId,
              deviceId: key.deviceId,
            );
      case _Command.read:
        final (workspace, key) = payload! as (String, CloudOperationKey);
        result = await database.forWorkspace(workspace).readOperation(key);
      case _Command.cas:
        final (workspace, version, next) =
            payload! as (String, int?, CloudStoredOperation);
        result = await database
            .forWorkspace(workspace)
            .compareAndSet(expectedVersion: version, next: next);
      case _Command.reconcile:
        final (session, workspace) = payload! as (CloudSession, String);
        await database.markWorkspaceReconciled(
          session: session,
          workspaceScopeId: workspace,
        );
      case _Command.fence:
        final (session, workspace) = payload! as (CloudSession, String);
        await database.requireWorkspaceReconciliation(
          session: session,
          workspaceScopeId: workspace,
        );
      case _Command.enabledOptIn:
        result = await database.hasEnabledOptIn(
          session: payload as CloudSession?,
        );
      case _Command.sync:
        final (name, data) = payload! as (String, Object?);
        final store = database.syncStore;
        switch (name) {
          case 'sendTask':
            final (scope, kind, subject, wire, context) =
                data!
                    as (
                      CloudSyncScope,
                      String,
                      String,
                      Map<String, Object?>,
                      Map<String, Object?>,
                    );
            result = await store.stageOutboundTask(
              scope,
              kind: kind,
              subjectId: subject,
              data: wire,
              localContext: context,
            );
          case 'pendingSendTasks':
            result = await store.pendingOutboundTasks(data! as CloudSyncScope);
          case 'readSendTask':
            final (scope, kind, subject) =
                data! as (CloudSyncScope, String, String);
            result = await store.outboundTask(scope, kind, subject);
          case 'finishSendTask':
            final (scope, task, resultData, capture) =
                data!
                    as (
                      CloudSyncScope,
                      CloudOutboundTask,
                      Map<String, Object?>,
                      CloudWorkspaceCapture,
                    );
            await store.completeOutboundTask(scope, task, resultData, capture);
          case 'pendingVocabulary':
            result = await store.hasPendingVocabulary(data! as CloudSyncScope);
          case 'pendingLineageConflict':
            final (scope, id) = data! as (CloudSyncScope, String);
            result = await store.hasPendingLineageConflict(scope, id);
          case 'integrity':
            result = await store.integrityStates(data! as CloudSyncScope);
          case 'snapshotKey':
            result = await store.ensureSnapshotRequestKey(
              data! as CloudSyncScope,
            );
          case 'clearSnapshotKey':
            final (scope, key) = data! as (CloudSyncScope, String);
            await store.clearSnapshotRequestKey(scope, key);
          case 'enabled':
            final (scope, enabled) = data! as (CloudSyncScope, bool);
            await store.setEnabled(scope, enabled);
          case 'baseline':
            final (scope, id) = data! as (CloudSyncScope, String);
            result = await store.publisherBaseline(scope, id);
          case 'linkOutbound':
            final (scope, id, fp, manifest, receipt, capture) =
                data!
                    as (
                      CloudSyncScope,
                      String,
                      String,
                      CloudContentManifest,
                      CloudCommitReceipt,
                      CloudWorkspaceCapture,
                    );
            await store.linkOutboundCommit(
              scope,
              localSkillId: id,
              localLineageFingerprint: fp,
              manifest: manifest,
              receipt: receipt,
              capture: capture,
            );
          case 'ackFields':
            final (scope, id, patch) =
                data! as (CloudSyncScope, String, Map<String, Object?>);
            await store.acknowledgeOutboundFields(scope, id, patch);
          case 'outboundTag':
            final (scope, cloud, local, name, color) =
                data! as (CloudSyncScope, String, String, String, String?);
            await store.bindOutboundPersonalTag(
              scope,
              cloudTagId: cloud,
              localTagId: local,
              name: name,
              color: color,
            );
          case 'ackAssignment':
            final (scope, skill, tag, assigned) =
                data! as (CloudSyncScope, String, String, bool);
            await store.acknowledgeOutboundAssignment(
              scope,
              localSkillId: skill,
              localTagId: tag,
              assigned: assigned,
            );
          case 'ackRemoval':
            final (scope, id) = data! as (CloudSyncScope, String);
            await store.acknowledgeOutboundRemoval(scope, id);
          case 'initialize':
            final (scope, capture, selection, cursor) =
                data!
                    as (
                      CloudSyncScope,
                      CloudWorkspaceCapture,
                      CloudSyncSelection,
                      CloudSequence,
                    );
            await store.initializeOptInScope(
              scope: scope,
              capture: capture,
              selection: selection,
              initialCursor: cursor,
            );
          case 'observe':
            final (scope, capture) =
                data! as (CloudSyncScope, CloudWorkspaceCapture);
            await store.observeCapture(scope, capture);
          case 'binding':
            final (scope, item, target, fingerprint, lineage, preexisting) =
                data!
                    as (
                      CloudSyncScope,
                      CloudInboxItem,
                      String?,
                      String?,
                      String?,
                      bool?,
                    );
            result = await store.bindApplyIntent(
              scope,
              item,
              localTargetId: target,
              workspaceRequestFingerprint: fingerprint,
              localLineageFingerprint: lineage,
              preexistingTarget: preexisting,
            );
          case 'removalRetry':
            final (scope, item, proof) =
                data!
                    as (
                      CloudSyncScope,
                      CloudInboxItem,
                      CloudRetryDesiredRemovalAllowed,
                    );
            await store.recordDesiredRemovalRetry(scope, item, proof);
          case 'notStarted':
            final (
              scope,
              item,
              proof,
            ) = data!
                as (CloudSyncScope, CloudInboxItem, CloudConfirmedNotStarted);
            await store.recordNotStarted(scope, item, proof);
          case 'progress':
            result = await store.progress(data! as CloudSyncScope);
          case 'changes':
            final (scope, page) = data! as (CloudSyncScope, CloudChangesPage);
            await store.stageChangesPage(scope, page);
          case 'snapshot':
            final (scope, page) = data! as (CloudSyncScope, CloudSnapshotPage);
            await store.stageSnapshotPage(scope, page);
          case 'discardSnapshot':
            final (scope, id) = data! as (CloudSyncScope, String);
            await store.discardIncompleteSnapshot(scope, id);
          case 'pending':
            final (scope, maximum) = data! as (CloudSyncScope, int);
            result = await store.pendingItems(scope, maximum: maximum);
          case 'tagMappings':
            result = await store.personalTagMappings(data! as CloudSyncScope);
          case 'tagMapping':
            final (scope, id) = data! as (CloudSyncScope, String);
            result = await store.personalTagMapping(scope, id);
          case 'mapping':
            final (scope, lineage) = data! as (CloudSyncScope, String);
            result = await store.mapping(scope, lineage);
          case 'reason':
            final (scope, item, reason) =
                data! as (CloudSyncScope, CloudInboxItem, CloudPendingReason);
            await store.recordPending(scope, item, reason);
          case 'proof':
            final (scope, item, proof) =
                data! as (CloudSyncScope, CloudInboxItem, CloudApplyResult);
            await store.recordApplyProof(scope, item, proof);
          case 'fence':
            await store.requireReconciliation(data! as CloudSyncScope);
          case 'candidate':
            final (scope, candidate) =
                data! as (CloudSyncScope, CloudOutboxCandidate);
            await store.stageOutboxCandidate(scope, candidate);
          case 'outbox':
            final (scope, maximum) = data! as (CloudSyncScope, int);
            result = await store.outboxCandidates(scope, maximum: maximum);
          default:
            throw const CloudException(CloudErrorCode.invalidRequest);
        }
    }
    return result as T;
  } finally {
    database.close();
  }
});

/// An asynchronous SQLite adapter suitable for App/UI composition.
final class BackgroundSqliteCloudDatabase implements CloudDeviceScopeStore {
  /// Startup probe: opens only an existing recognized Cloud DB in read-only mode.
  static Future<bool> probeEnabledOptIn({
    required String path,
    required Uri serviceOrigin,
  }) => Isolate.run(() {
    if (!File(path).existsSync()) return false;
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      verifyCloudSchemaReadOnly(db);
      return db.select(
        "SELECT 1 FROM cloud_sync_scope WHERE origin=? AND status='enabled' LIMIT 1",
        [serviceOrigin.origin],
      ).isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      db?.close();
    }
  });
  Future<bool> hasEnabledOptIn({CloudSession? session}) =>
      _call<bool>(_Command.enabledOptIn, session);

  BackgroundSqliteCloudDatabase._(this._path, this.serviceOrigin);
  static Future<BackgroundSqliteCloudDatabase> open({
    required String path,
    required Uri serviceOrigin,
  }) async {
    await _worker<void>(path, serviceOrigin, _Command.probe, null);
    return BackgroundSqliteCloudDatabase._(path, serviceOrigin);
  }

  final String _path;
  final Uri serviceOrigin;

  /// Inbox and progress operations executed exclusively in background isolates.
  CloudSyncStore get syncStore => _BackgroundSyncStore(this);
  final Set<Future<Object?>> _pending = {};
  bool _closed = false;
  Future<T> _call<T>(_Command command, Object? payload) async {
    if (_closed) throw const CloudException(CloudErrorCode.cancelled);
    final future = _worker<T>(_path, serviceOrigin, command, payload);
    _pending.add(future);
    try {
      return await future;
    } finally {
      _pending.remove(future);
    }
  }

  @override
  Future<void> initializeNewDeviceScope(CloudSession session) =>
      _call<void>(_Command.newDevice, session);
  @override
  Future<bool> hasDeviceScope(CloudSession session) =>
      _call<bool>(_Command.device, session);
  MutationIntentStore forWorkspace(String workspaceScopeId) =>
      _BackgroundIntentStore(this, workspaceScopeId);
  Future<void> markWorkspaceReconciled({
    required CloudSession session,
    required String workspaceScopeId,
  }) => _call<void>(_Command.reconcile, (session, workspaceScopeId));
  Future<void> requireWorkspaceReconciliation({
    required CloudSession session,
    required String workspaceScopeId,
  }) => _call<void>(_Command.fence, (session, workspaceScopeId));
  @override
  Future<void> close() async {
    _closed = true;
    await Future.wait(
      _pending.toList().map(
        (future) => future.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
  }
}

final class _BackgroundSyncStore implements CloudSyncStore {
  _BackgroundSyncStore(this.owner);
  final BackgroundSqliteCloudDatabase owner;
  Future<T> _call<T>(String name, Object? data) =>
      owner._call<T>(_Command.sync, (name, data));
  @override
  Future<CloudOutboundTask> stageOutboundTask(
    CloudSyncScope scope, {
    required String kind,
    required String subjectId,
    required Map<String, Object?> data,
    required Map<String, Object?> localContext,
  }) => _call<CloudOutboundTask>('sendTask', (
    scope,
    kind,
    subjectId,
    data,
    localContext,
  ));
  @override
  Future<List<CloudOutboundTask>> pendingOutboundTasks(CloudSyncScope scope) =>
      _call<List<CloudOutboundTask>>('pendingSendTasks', scope);
  @override
  Future<CloudOutboundTask?> outboundTask(
    CloudSyncScope scope,
    String kind,
    String subjectId,
  ) => _call<CloudOutboundTask?>('readSendTask', (scope, kind, subjectId));
  @override
  Future<void> completeOutboundTask(
    CloudSyncScope scope,
    CloudOutboundTask task,
    Map<String, Object?> result,
    CloudWorkspaceCapture capture,
  ) => _call<void>('finishSendTask', (scope, task, result, capture));
  @override
  Future<bool> hasPendingVocabulary(CloudSyncScope scope) =>
      _call<bool>('pendingVocabulary', scope);
  @override
  Future<bool> hasPendingLineageConflict(
    CloudSyncScope scope,
    String lineageId,
  ) => _call<bool>('pendingLineageConflict', (scope, lineageId));
  @override
  Future<List<CloudIntegrityState>> integrityStates(CloudSyncScope scope) =>
      _call<List<CloudIntegrityState>>('integrity', scope);
  @override
  Future<String> ensureSnapshotRequestKey(CloudSyncScope scope) =>
      _call<String>('snapshotKey', scope);
  @override
  Future<void> clearSnapshotRequestKey(
    CloudSyncScope scope,
    String expectedKey,
  ) => _call<void>('clearSnapshotKey', (scope, expectedKey));
  @override
  Future<void> setEnabled(CloudSyncScope scope, bool enabled) =>
      _call<void>('enabled', (scope, enabled));
  @override
  Future<CloudPublisherBaseline?> publisherBaseline(
    CloudSyncScope scope,
    String localSkillId,
  ) => _call<CloudPublisherBaseline?>('baseline', (scope, localSkillId));
  @override
  Future<void> linkOutboundCommit(
    CloudSyncScope scope, {
    required String localSkillId,
    required String localLineageFingerprint,
    required CloudContentManifest manifest,
    required CloudCommitReceipt receipt,
    required CloudWorkspaceCapture capture,
  }) => _call<void>('linkOutbound', (
    scope,
    localSkillId,
    localLineageFingerprint,
    manifest,
    receipt,
    capture,
  ));
  @override
  Future<void> acknowledgeOutboundFields(
    CloudSyncScope scope,
    String localSkillId,
    Map<String, Object?> patch,
  ) => _call<void>('ackFields', (scope, localSkillId, patch));
  @override
  Future<void> bindOutboundPersonalTag(
    CloudSyncScope scope, {
    required String cloudTagId,
    required String localTagId,
    required String name,
    String? color,
  }) =>
      _call<void>('outboundTag', (scope, cloudTagId, localTagId, name, color));
  @override
  Future<void> acknowledgeOutboundAssignment(
    CloudSyncScope scope, {
    required String localSkillId,
    required String localTagId,
    required bool assigned,
  }) =>
      _call<void>('ackAssignment', (scope, localSkillId, localTagId, assigned));
  @override
  Future<void> acknowledgeOutboundRemoval(
    CloudSyncScope scope,
    String localSkillId,
  ) => _call<void>('ackRemoval', (scope, localSkillId));
  @override
  Future<void> initializeOptInScope({
    required CloudSyncScope scope,
    required CloudWorkspaceCapture capture,
    required CloudSyncSelection selection,
    required CloudSequence initialCursor,
  }) => _call<void>('initialize', (scope, capture, selection, initialCursor));
  @override
  Future<void> observeCapture(
    CloudSyncScope scope,
    CloudWorkspaceCapture capture,
  ) => _call<void>('observe', (scope, capture));
  @override
  Future<CloudApplyBinding> bindApplyIntent(
    CloudSyncScope scope,
    CloudInboxItem item, {
    String? localTargetId,
    String? workspaceRequestFingerprint,
    String? localLineageFingerprint,
    bool? preexistingTarget,
  }) => _call<CloudApplyBinding>('binding', (
    scope,
    item,
    localTargetId,
    workspaceRequestFingerprint,
    localLineageFingerprint,
    preexistingTarget,
  ));
  @override
  Future<void> recordDesiredRemovalRetry(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudRetryDesiredRemovalAllowed proof,
  ) => _call<void>('removalRetry', (scope, item, proof));
  @override
  Future<void> recordNotStarted(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudConfirmedNotStarted proof,
  ) => _call<void>('notStarted', (scope, item, proof));
  @override
  Future<CloudSyncProgress> progress(CloudSyncScope scope) =>
      _call<CloudSyncProgress>('progress', scope);
  @override
  Future<void> stageChangesPage(CloudSyncScope scope, CloudChangesPage page) =>
      _call<void>('changes', (scope, page));
  @override
  Future<void> stageSnapshotPage(
    CloudSyncScope scope,
    CloudSnapshotPage page,
  ) => _call<void>('snapshot', (scope, page));
  @override
  Future<void> discardIncompleteSnapshot(
    CloudSyncScope scope,
    String snapshotId,
  ) => _call<void>('discardSnapshot', (scope, snapshotId));
  @override
  Future<List<CloudInboxItem>> pendingItems(
    CloudSyncScope scope, {
    int maximum = 100,
  }) => _call<List<CloudInboxItem>>('pending', (scope, maximum));
  @override
  Future<List<CloudPersonalTagMapping>> personalTagMappings(
    CloudSyncScope scope,
  ) => _call<List<CloudPersonalTagMapping>>('tagMappings', scope);
  @override
  Future<CloudPersonalTagMapping?> personalTagMapping(
    CloudSyncScope scope,
    String cloudTagId,
  ) => _call<CloudPersonalTagMapping?>('tagMapping', (scope, cloudTagId));
  @override
  Future<CloudLineageMapping?> mapping(
    CloudSyncScope scope,
    String lineageId,
  ) => _call<CloudLineageMapping?>('mapping', (scope, lineageId));
  @override
  Future<void> recordPending(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudPendingReason reason,
  ) => _call<void>('reason', (scope, item, reason));
  @override
  Future<void> recordApplyProof(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudApplyResult proof,
  ) => _call<void>('proof', (scope, item, proof));
  @override
  Future<void> requireReconciliation(CloudSyncScope scope) =>
      _call<void>('fence', scope);
  @override
  Future<void> stageOutboxCandidate(
    CloudSyncScope scope,
    CloudOutboxCandidate candidate,
  ) => _call<void>('candidate', (scope, candidate));
  @override
  Future<List<CloudOutboxCandidate>> outboxCandidates(
    CloudSyncScope scope, {
    int maximum = 100,
  }) => _call<List<CloudOutboxCandidate>>('outbox', (scope, maximum));
}

final class _BackgroundIntentStore implements MutationIntentStore {
  _BackgroundIntentStore(this.owner, this.workspace);
  final BackgroundSqliteCloudDatabase owner;
  final String workspace;
  @override
  Future<bool> hasAuthoritativeScope({
    required String accountId,
    required String deviceId,
  }) => owner._call<bool>(_Command.ready, (
    workspace,
    CloudOperationKey(
      accountId: accountId,
      deviceId: deviceId,
      operationId: 'scope-check',
    ),
  ));
  @override
  Future<CloudStoredOperation?> readOperation(CloudOperationKey key) =>
      owner._call<CloudStoredOperation?>(_Command.read, (workspace, key));
  @override
  Future<bool> compareAndSet({
    required int? expectedVersion,
    required CloudStoredOperation next,
  }) => owner._call<bool>(_Command.cas, (workspace, expectedVersion, next));
}
