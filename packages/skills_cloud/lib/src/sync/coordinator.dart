import 'dart:async';

import '../auth/client.dart';
import '../cancellation.dart';
import '../errors.dart';
import '../protocol/client.dart';
import '../protocol/models.dart';
import '../protocol/content_manifest.dart';
import 'models.dart';
import 'store.dart';
import 'workspace_port.dart';

/// Pulls and applies only an explicitly initialized selected synchronization scope.
final class CloudSyncCoordinator {
  CloudSyncCoordinator({
    required this.scope,
    required this._auth,
    required this._api,
    required this._store,
    required this._workspace,
  });
  final CloudSyncScope scope;
  final CloudAuthClient _auth;
  final CloudSyncClient _api;
  final CloudSyncStore _store;
  final CloudWorkspacePort _workspace;
  Future<void> _applyTail = Future.value();
  bool _running = false;
  CloudAuthLease _lease() {
    final lease = _auth.captureLease();
    if (lease.session.accountId != scope.accountId ||
        lease.session.deviceId != scope.deviceId) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    return lease;
  }

  Future<CloudWorkspaceCapture> _capture(
    CloudAuthLease lease,
    CloudCancellation cancellation,
  ) async {
    cancellation.throwIfCancelled();
    _auth.checkLease(lease);
    final progress = await _store.progress(scope);
    final capture = await _workspace.capture();
    _auth.checkLease(lease);
    cancellation.throwIfCancelled();
    if (capture.identity != scope.workspaceIdentity) {
      await _store.requireReconciliation(scope);
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    if (progress.needsReconciliation) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    if (!capture.ready) {
      throw const CloudException(CloudErrorCode.unavailable, retryable: true);
    }
    await _store.observeCapture(scope, capture);
    return capture;
  }

  /// Receives one bounded changes page atomically, without advancing applied state.
  Future<CloudSyncProgress> pullChanges({
    CloudCancellation? cancellation,
  }) async {
    final operation = cancellation ?? CloudCancellation(), lease = _lease();
    await _capture(lease, operation);
    final before = await _store.progress(scope);
    _auth.checkLease(lease);
    if (before.snapshotId != null && before.snapshotCursor == null) {
      await _api.releaseSnapshot(before.snapshotId!, cancellation: operation);
    }
    final page = await _api.changes(
      after: before.received,
      highWatermark: before.traversalHighWatermark,
      cancellation: operation,
    );
    _auth.checkLease(lease);
    operation.throwIfCancelled();
    await _capture(lease, operation);
    await _store.stageChangesPage(scope, page);
    return _store.progress(scope);
  }

  /// Receives or resumes a snapshot; only the final page publishes its boundary.
  Future<CloudSyncProgress> pullSnapshotPage({
    CloudCancellation? cancellation,
  }) async {
    final operation = cancellation ?? CloudCancellation(), lease = _lease();
    await _capture(lease, operation);
    final before = await _store.progress(scope);
    _auth.checkLease(lease);
    if (before.snapshotId != null && before.snapshotCursor == null) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    late final CloudSnapshotPage page;
    final requestKey = before.snapshotId == null
        ? await _store.ensureSnapshotRequestKey(scope)
        : null;
    try {
      page = before.snapshotId == null
          ? await _api.createSnapshot(
              requestKey: requestKey,
              cancellation: operation,
            )
          : await _api.snapshotPage(
              snapshotId: before.snapshotId!,
              pageCursor: before.snapshotCursor!,
              highWatermark: before.snapshotHighWatermark!,
              cancellation: operation,
            );
    } on CloudException catch (error) {
      if (error.code == CloudErrorCode.snapshotExpired) {
        if (before.snapshotId != null) {
          await _store.discardIncompleteSnapshot(scope, before.snapshotId!);
        } else {
          await _store.clearSnapshotRequestKey(scope, requestKey!);
        }
      }
      rethrow;
    }
    _auth.checkLease(lease);
    await _capture(lease, operation);
    await _store.stageSnapshotPage(scope, page);
    if (page.complete) {
      await _api.releaseSnapshot(page.snapshotId, cancellation: operation);
    }
    return _store.progress(scope);
  }

  /// Applies staged events with four bounded preparations and ordered lineage work.
  ///
  /// Workspace mutations are serialized under authoritative revision checks.
  /// Independent lineages can download/verify concurrently; a pending lineage
  /// does not prevent another lineage or global tag from being applied.
  Future<CloudSyncProgress> applyPending({
    CloudCancellation? cancellation,
  }) async {
    if (_running) {
      throw const CloudException(CloudErrorCode.operationInProgress);
    }
    final operation = cancellation ?? CloudCancellation(), lease = _lease();
    _running = true;
    try {
      await _capture(lease, operation);
      final items = await _store.pendingItems(scope, maximum: 2000);
      final groups = <String, List<CloudInboxItem>>{};
      for (final item in items) {
        final group =
            item.change.lineageId ?? 'tag:${item.change.payload['tagId']}';
        (groups[group] ??= []).add(item);
      }
      Future<void> runGroups(List<List<CloudInboxItem>> jobs) async {
        var next = 0;
        Future<void> worker() async {
          while (next < jobs.length) {
            final group = jobs[next++];
            for (final item in group) {
              operation.throwIfCancelled();
              _auth.checkLease(lease);
              if (!await _applyOne(item, lease, operation)) break;
            }
          }
        }

        await Future.wait(
          List.generate(jobs.length < 4 ? jobs.length : 4, (_) => worker()),
        );
      }

      await runGroups(
        groups.values
            .where((items) => items.first.change.lineageId == null)
            .toList(),
      );
      await runGroups(
        groups.values
            .where((items) => items.first.change.lineageId != null)
            .toList(),
      );
      _auth.checkLease(lease);
      return await _store.progress(scope);
    } finally {
      _running = false;
    }
  }

  Future<T> _mutationGate<T>(Future<T> Function() action) async {
    final prior = _applyTail, release = Completer<void>();
    _applyTail = release.future;
    await prior;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  Future<bool> _applyOne(
    CloudInboxItem item,
    CloudAuthLease lease,
    CloudCancellation cancellation, {
    bool insideGate = false,
  }) async {
    if (item.change.kind != 'revision' && !insideGate) {
      return _mutationGate(
        () => _applyOne(item, lease, cancellation, insideGate: true),
      );
    }
    if (item.pendingReason == CloudPendingReason.receiptConflict) return false;
    final lineage = item.change.lineageId;
    if (item.change.kind == 'repairNeeded' ||
        item.change.kind == 'repairReady') {
      await _store.recordPending(scope, item, CloudPendingReason.needsReupload);
      return false;
    }
    final mapping = lineage == null
        ? null
        : await _store.mapping(scope, lineage);
    final replacement = item.change.kind == 'replacement';
    if (replacement &&
        (mapping == null ||
            item.change.payload['previousGeneration'] != mapping.generation ||
            item.change.generation != mapping.generation + 1)) {
      await _store.recordPending(
        scope,
        item,
        CloudPendingReason.unsupportedReplacement,
      );
      return false;
    }
    if (mapping != null &&
        !replacement &&
        mapping.generation != item.change.generation) {
      await _store.recordPending(
        scope,
        item,
        CloudPendingReason.unsupportedReplacement,
      );
      return false;
    }
    if (lineage != null && mapping == null && item.change.kind != 'revision') {
      await _store.recordPending(
        scope,
        item,
        CloudPendingReason.selectionRequired,
      );
      return false;
    }
    if (['revision', 'replacement'].contains(item.change.kind) &&
        item.pendingReason != CloudPendingReason.unknownOutcome) {
      final integrity = (await _store.integrityStates(scope))
          .where(
            (value) =>
                value.lineageId == lineage &&
                value.generation == item.change.generation,
          )
          .firstOrNull;
      if (integrity?.status == CloudContentStatus.needsReupload) {
        await _store.recordPending(
          scope,
          item,
          CloudPendingReason.needsReupload,
        );
        return false;
      }
    }
    var binding = await _store.bindApplyIntent(
      scope,
      item,
      localTargetId: mapping?.localSkillId,
    );
    CloudIncomingHandle? handle;
    try {
      final mustResolve =
          item.pendingReason == CloudPendingReason.unknownOutcome ||
          mapping?.retired == true;
      if (!mustResolve) {
        try {
          handle = (item.change.kind == 'revision' || replacement)
              ? await _workspace.prepareIncoming(
                  item: item,
                  binding: binding,
                  scope: scope,
                  cancellation: cancellation,
                )
              : await _workspace.prepareStateChange(
                  item: item,
                  binding: binding,
                  scope: scope,
                  mapping: mapping,
                  cancellation: cancellation,
                );
          binding = await _store.bindApplyIntent(
            scope,
            item,
            localTargetId: handle.localTargetId,
            workspaceRequestFingerprint: handle.workspaceRequestFingerprint,
            localLineageFingerprint: handle.localLineageFingerprint,
            preexistingTarget: handle is CloudInitialExistingIncomingHandle
                ? handle.preexistingTarget
                : false,
          );
          if (item.change.lineageId != null && binding.localTargetId == null) {
            await _store.recordPending(
              scope,
              item,
              CloudPendingReason.unknownOutcome,
            );
            return false;
          }
        } on CloudException catch (error) {
          if (error.code == CloudErrorCode.cancelled) rethrow;
          await _store.recordPending(scope, item, switch (error.code) {
            CloudErrorCode.needsReupload => CloudPendingReason.needsReupload,
            CloudErrorCode.dirtyDraftRequired => CloudPendingReason.dirtyDraft,
            CloudErrorCode.metadataConflict =>
              CloudPendingReason.metadataConflict,
            CloudErrorCode.unsupportedNormalization =>
              CloudPendingReason.unsupportedNormalization,
            CloudErrorCode.needsReconciliation =>
              CloudPendingReason.metadataProofUnavailable,
            _ => CloudPendingReason.unavailable,
          });
          return false;
        } catch (_) {
          await _store.recordPending(
            scope,
            item,
            CloudPendingReason.unavailable,
          );
          return false;
        }
      }
      Future<bool> applyPrepared() async {
        final capture = await _capture(lease, cancellation);
        // Persist the unknown-outcome boundary before crossing a mutable port.
        await _store.recordPending(
          scope,
          item,
          CloudPendingReason.unknownOutcome,
        );
        _auth.checkLease(lease);
        cancellation.throwIfCancelled();
        final CloudApplyResult result;
        try {
          if (mustResolve) {
            result = await _workspace.resolveOutcome(
              item: item,
              binding: binding,
              scope: scope,
              cancellation: cancellation,
            );
          } else if (item.change.kind == 'revision' || replacement) {
            result = await _workspace.applyIncoming(
              item: item,
              binding: binding,
              handle: handle!,
              expected: capture,
              mapping: mapping,
              cancellation: cancellation,
            );
          } else if (item.change.kind == 'removal') {
            result = await _workspace.applyLifecycle(
              item: item,
              binding: binding,
              handle: handle!,
              expected: capture,
              mapping: mapping,
              cancellation: cancellation,
            );
          } else {
            result = await _workspace.applyMetadata(
              item: item,
              binding: binding,
              handle: handle!,
              expected: capture,
              mapping: mapping,
              cancellation: cancellation,
            );
          }
        } on CloudException catch (error) {
          if (error.code == CloudErrorCode.cancelled) rethrow;
          return false;
        } catch (_) {
          return false;
        }
        _auth.checkLease(lease);
        cancellation.throwIfCancelled();
        if (result case CloudRetryDesiredRemovalAllowed()) {
          await _store.recordDesiredRemovalRetry(scope, item, result);
          return false;
        }
        if (result case CloudConfirmedNotStarted()) {
          await _store.recordNotStarted(scope, item, result);
          return false;
        }
        if (result case CloudApplyPending(:final reason)) {
          await _store.recordPending(scope, item, reason);
          return false;
        }
        try {
          await _store.recordApplyProof(scope, item, result);
          return true;
        } on CloudException {
          await _store.requireReconciliation(scope);
          rethrow;
        }
      }

      return insideGate
          ? await applyPrepared()
          : await _mutationGate(applyPrepared);
    } finally {
      await handle?.dispose();
    }
  }
}
