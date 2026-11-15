import 'dart:async';
import 'dart:convert';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_workspace/skills_workspace.dart' as ws;

import 'workspace_cloud_adapter.dart';

enum AppCloudChoiceKind { local, remote }

final class AppCloudSkillChoice {
  const AppCloudSkillChoice({
    required this.id,
    required this.name,
    required this.kind,
    this.supported = true,
    this.conflict = false,
  });
  final String id, name;
  final AppCloudChoiceKind kind;
  final bool supported, conflict;
}

final class AppCloudSyncView {
  const AppCloudSyncView({
    this.available = true,
    this.enabled = false,
    this.choices = const [],
    this.selectedIds = const {},
    this.pendingCount = 0,
    this.pendingReasons = const {},
    this.needsReconciliation = false,
    this.backgroundRunning = false,
    this.backgroundError,
  });
  final bool available, enabled, needsReconciliation, backgroundRunning;
  final CloudErrorCode? backgroundError;
  final List<AppCloudSkillChoice> choices;
  final Set<String> selectedIds;
  final int pendingCount;
  final Set<CloudPendingReason> pendingReasons;
  AppCloudSyncView withChoices(List<AppCloudSkillChoice> value) =>
      AppCloudSyncView(
        available: available,
        enabled: enabled,
        choices: value,
        selectedIds: selectedIds,
        pendingCount: pendingCount,
        pendingReasons: pendingReasons,
        needsReconciliation: needsReconciliation,
      );
  AppCloudSyncView withBackground({
    required bool running,
    CloudErrorCode? error,
  }) => AppCloudSyncView(
    available: available,
    enabled: enabled,
    choices: choices,
    selectedIds: selectedIds,
    pendingCount: pendingCount,
    pendingReasons: pendingReasons,
    needsReconciliation:
        needsReconciliation || error == CloudErrorCode.needsReconciliation,
    backgroundRunning: running,
    backgroundError: error,
  );
}

abstract interface class AppCloudSyncGateway {
  Future<AppCloudSyncView> syncOverview();
  Future<AppCloudSyncView> enableSyncChoice(AppCloudSkillChoice choice);
  Future<AppCloudSyncView> enableSyncChoices(List<AppCloudSkillChoice> choices);
  Future<AppCloudSyncView> syncNow();
  Future<AppCloudSyncView> stopSync();
}

Future<T> _value<T>(ws.SkillsOperation<T> operation) async {
  final result = await operation.completed;
  if (result case ws.SkillsSuccess<T>(:final value)) return value;
  throw const CloudException(CloudErrorCode.needsReconciliation);
}

CloudWorkspaceCapture _captureProjection(
  ws.AuthoritativeWorkspaceCapture raw,
) => CloudWorkspaceCapture(
  identity: CloudWorkspaceIdentity(
    workspaceId: raw.identity.workspaceId,
    recoveryIncarnation: raw.identity.recoveryIncarnation,
  ),
  revision: raw.snapshot.revision.value.toString(),
  recoveryComplete: raw.recoveryComplete,
  finalizationComplete: raw.finalizationComplete,
  isComplete: raw.isComplete,
  localLineageFingerprints: Map.unmodifiable(
    raw.localLineageFingerprints.map(
      (key, value) => MapEntry(key.value, value),
    ),
  ),
);

/// Explicit manual synchronization composed from real public Workspace operations.
final class AppCloudSyncSession {
  AppCloudSyncSession({
    required CloudAuthClient auth,
    required BackgroundSqliteCloudDatabase database,
    required ws.SkillsRepository repository,
    required Future<bool> Function() canMutate,
    CloudWorkspaceRemoteFactory? testRemoteFactory,
  }) : _auth = auth,
       _database = database,
       _repository = repository,
       _canMutate = canMutate,
       _testRemoteFactory = testRemoteFactory;
  final CloudAuthClient _auth;
  final BackgroundSqliteCloudDatabase _database;
  final ws.SkillsRepository _repository;
  final Future<bool> Function() _canMutate;
  final CloudWorkspaceRemoteFactory? _testRemoteFactory;
  CloudSyncScope? _lastScope;
  CloudCancellation? _active;
  Future<AppCloudSyncView>? _running;
  bool _closed = false;
  String? _catalogRequestKey;

  Future<(CloudSyncScope, ws.AuthoritativeWorkspaceCapture)> _capture() async {
    if (_closed) throw const CloudException(CloudErrorCode.cancelled);
    final lease = _auth.captureLease();
    final raw = await _value(
      _repository.captureAuthoritativeState(
        const ws.CaptureAuthoritativeStateRequest(),
      ),
    );
    _auth.checkLease(lease);
    final capture = _captureProjection(raw);
    if (!capture.ready) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final scope = CloudSyncScope(
      accountId: lease.session.accountId,
      deviceId: lease.session.deviceId,
      workspaceIdentity: capture.identity,
    );
    _lastScope = scope;
    return (scope, raw);
  }

  CloudSyncClient _api(CloudSyncScope scope) => CloudSyncClient(
    auth: _auth,
    intents: _database.forWorkspace(scope.workspaceIdentity.workspaceId),
  );
  WorkspaceCloudAdapter _adapter(CloudSyncScope scope, CloudSyncClient api) =>
      _testRemoteFactory == null
      ? WorkspaceCloudAdapter(
          repository: _repository,
          scope: scope,
          api: api,
          syncStore: _database.syncStore,
          boundedNetworkFetchQualified: true,
        )
      : WorkspaceCloudAdapter.withTestRemoteFactory(
          repository: _repository,
          scope: scope,
          api: api,
          syncStore: _database.syncStore,
          boundedNetworkFetchQualified: true,
          remoteFactory: _testRemoteFactory,
        );
  bool _supported(ws.ManagedSkill skill) {
    try {
      switch (skill.source) {
        case ws.GitSourceDescriptor(
          :final locator,
          :final ref,
          :final repositorySubpath,
          :final skillPath,
        ):
          CloudGitSource(
            locator: locator,
            ref: ref,
            repositorySubpath: repositorySubpath,
            skillPath: skillPath,
          );
          return true;
        case ws.WellKnownSourceDescriptor(:final locator, :final skillPath):
          CloudWellKnownSource(locator: locator, skillPath: skillPath);
          return true;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<List<CloudLineage>> _catalog(
    CloudSyncClient api, {
    CloudCancellation? cancellation,
  }) async {
    final key = _catalogRequestKey ??= randomCloudToken();
    late final CloudSnapshotPage first;
    try {
      first = await api.createSnapshot(
        requestKey: key,
        cancellation: cancellation,
      );
    } on CloudException catch (error) {
      if (error.code == CloudErrorCode.snapshotExpired) {
        _catalogRequestKey = null;
      }
      rethrow;
    }
    var page = first;
    try {
      final result = <CloudLineage>[...page.items];
      var pages = 1;
      while (!page.complete) {
        if (pages++ >= 16) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        page = await api.snapshotPage(
          snapshotId: page.snapshotId,
          pageCursor: page.nextPageCursor!,
          highWatermark: page.highWatermark,
          cancellation: cancellation,
        );
        result.addAll(page.items);
      }
      return result;
    } finally {
      // Catalog browsing never owns a resumable bootstrap traversal.
      await api.releaseSnapshot(first.snapshotId, cancellation: cancellation);
      _catalogRequestKey = null;
    }
  }

  Future<bool> _canLink(
    ws.ManagedSkill local,
    CloudLineage remote,
    WorkspaceCloudAdapter adapter,
  ) async {
    if (remote.contentStatus != CloudContentStatus.ready ||
        remote.contentManifest == null ||
        !_supported(local)) {
      return false;
    }
    try {
      return cloudInitialRootsSatisfied(
        await adapter.exportSelected(local.id.value, CloudCancellation()),
        remote.contentManifest!,
      );
    } on CloudException {
      return false;
    }
  }

  Future<AppCloudSyncView> overview({bool loadChoices = true}) async {
    if (_closed) throw const CloudException(CloudErrorCode.cancelled);
    final (scope, raw) = await _capture();
    CloudSyncProgress? progress;
    try {
      progress = await _database.syncStore.progress(scope);
    } on CloudException {
      /* No opted-in Workspace scope yet. */
    }
    final choices = <AppCloudSkillChoice>[];
    if (loadChoices) {
      final api = _api(scope), remote = await _catalog(_api(scope));
      final adapter = _adapter(scope, api);
      final linkable = <String, bool>{};
      for (final item in remote) {
        final local = raw.snapshot.findSkillBySlotKey(item.slotKey);
        if (local != null) {
          linkable[item.lineageId] = await _canLink(local, item, adapter);
        }
      }
      for (final skill in raw.snapshot.managedSkills) {
        choices.add(
          AppCloudSkillChoice(
            id: skill.id.value,
            name: skill.displayName,
            kind: AppCloudChoiceKind.local,
            supported: _supported(skill),
            conflict: remote.any(
              (item) =>
                  item.slotKey == skill.slotKey &&
                  linkable[item.lineageId] != true,
            ),
          ),
        );
      }
      for (final item in remote) {
        choices.add(
          AppCloudSkillChoice(
            id: item.lineageId,
            name: item.slotKey,
            kind: AppCloudChoiceKind.remote,
            supported: item.contentStatus == CloudContentStatus.ready,
            conflict:
                raw.snapshot.findSkillBySlotKey(item.slotKey) != null &&
                linkable[item.lineageId] != true,
          ),
        );
      }
    }
    var pending = <CloudInboxItem>[];
    if (progress?.isEnabled == true) {
      pending = await _database.syncStore.pendingItems(scope, maximum: 2000);
    }
    return AppCloudSyncView(
      enabled: progress?.isEnabled ?? false,
      choices: List.unmodifiable(choices),
      selectedIds: {
        ...?progress?.selection.localSkillIds,
        ...?progress?.selection.cloudLineageIds,
      },
      pendingCount: progress?.pendingCount ?? 0,
      pendingReasons: {
        ...pending
            .map((item) => item.pendingReason)
            .whereType<CloudPendingReason>(),
        if (progress != null &&
            (await _database.syncStore.integrityStates(
              scope,
            )).any((value) => value.status == CloudContentStatus.needsReupload))
          CloudPendingReason.needsReupload,
      },
      needsReconciliation: progress?.needsReconciliation ?? false,
    );
  }

  Future<AppCloudSyncView> enable(AppCloudSkillChoice choice) =>
      enableChoices([choice]);
  Future<AppCloudSyncView> enableChoices(List<AppCloudSkillChoice> choices) {
    if (_running != null) {
      throw const CloudException(CloudErrorCode.operationInProgress);
    }
    final cancellation = CloudCancellation();
    _active = cancellation;
    final future = _enableChoices(choices, cancellation);
    _running = future;
    return future.whenComplete(() {
      _running = null;
      _active = null;
    });
  }

  Future<AppCloudSyncView> _enableChoices(
    List<AppCloudSkillChoice> choices,
    CloudCancellation cancellation,
  ) async {
    final (scope, raw) = await _capture();
    cancellation.throwIfCancelled();
    if (choices.isEmpty ||
        choices.length > 100 ||
        !await _database.hasDeviceScope(_auth.currentSession!)) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    if (choices.any((choice) => !choice.supported || choice.conflict)) {
      throw const CloudException(CloudErrorCode.operationConflict);
    }
    CloudSyncProgress? existing;
    try {
      existing = await _database.syncStore.progress(scope);
    } on CloudException {
      /* New opt-in. */
    }
    if (existing != null) {
      final selected = {
        ...existing.selection.localSkillIds,
        ...existing.selection.cloudLineageIds,
      };
      if (choices.length != selected.length ||
          choices.any((choice) => !selected.contains(choice.id))) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      cancellation.throwIfCancelled();
      await _database.syncStore.setEnabled(scope, true);
      cancellation.throwIfCancelled();
      return overview(loadChoices: false);
    }
    final api = _api(scope),
        catalog = await _catalog(_api(scope), cancellation: cancellation);
    final localIds = <String>{}, remoteIds = <String>{};
    for (final choice in choices) {
      if (choice.kind == AppCloudChoiceKind.remote) {
        final remote = catalog
            .where((item) => item.lineageId == choice.id)
            .firstOrNull;
        if (remote == null ||
            remote.contentStatus != CloudContentStatus.ready) {
          throw const CloudException(CloudErrorCode.missingLineage);
        }
        final local = raw.snapshot.findSkillBySlotKey(remote.slotKey);
        if (local != null &&
            !await _canLink(local, remote, _adapter(scope, api))) {
          throw const CloudException(CloudErrorCode.operationConflict);
        }
        remoteIds.add(remote.lineageId);
      } else {
        final local = raw.snapshot.findSkill(ws.ManagedSkillId(choice.id));
        if (local == null || !_supported(local)) {
          throw const CloudException(CloudErrorCode.invalidRequest);
        }
        final matches = catalog
            .where((item) => item.slotKey == local.slotKey)
            .toList();
        if (matches.isNotEmpty) {
          if (matches.length != 1 ||
              !await _canLink(local, matches.single, _adapter(scope, api))) {
            throw const CloudException(CloudErrorCode.operationConflict);
          }
          remoteIds.add(matches.single.lineageId);
        } else {
          localIds.add(local.id.value);
        }
      }
    }
    cancellation.throwIfCancelled();
    await _database.syncStore.initializeOptInScope(
      scope: scope,
      capture: _captureProjection(raw),
      selection: CloudSyncSelection(
        localSkillIds: localIds,
        cloudLineageIds: remoteIds,
      ),
      initialCursor: CloudSequence.parse('0'),
    );
    cancellation.throwIfCancelled();
    await _database.syncStore.setEnabled(scope, true);
    cancellation.throwIfCancelled();
    return overview(loadChoices: false);
  }

  Future<Map<String, Object?>> _send(
    CloudSyncScope scope,
    CloudSyncClient api,
    CloudOutboundTask task,
    CloudCancellation cancellation,
  ) async {
    final path = task.kind == 'removal'
        ? '/v1/sync/lifecycle'
        : task.kind == 'repair'
        ? '/v1/sync/repair'
        : '/v1/sync/metadata';
    return api.sendMutation(
      CloudMutationIntent.fresh(
        key: CloudOperationKey(
          accountId: scope.accountId,
          deviceId: scope.deviceId,
          operationId: task.operationId,
        ),
        path: path,
        data: task.data,
      ),
      cancellation: cancellation,
    );
  }

  Future<void> _finish(
    CloudSyncScope scope,
    CloudOutboundTask task,
    Map<String, Object?> result,
  ) async {
    final (current, raw) = await _capture();
    if (current.workspaceIdentity != scope.workspaceIdentity ||
        current.accountId != scope.accountId ||
        current.deviceId != scope.deviceId) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    await _database.syncStore.completeOutboundTask(
      scope,
      task,
      result,
      _captureProjection(raw),
    );
  }

  Future<void> _recoverConfirmed(
    CloudSyncScope scope,
    CloudSyncClient api,
    CloudCancellation cancellation,
  ) async {
    // Settle earlier sent intents before receiving their echo. A later local
    // edit must not be overwritten by our own previously committed value.
    for (final task in await _database.syncStore.pendingOutboundTasks(scope)) {
      final operation = await _database
          .forWorkspace(scope.workspaceIdentity.workspaceId)
          .readOperation(
            CloudOperationKey(
              accountId: scope.accountId,
              deviceId: scope.deviceId,
              operationId: task.operationId,
            ),
          );
      if (operation == null) continue; // Durably staged, genuinely unsent.
      if (task.kind == 'content' ||
          task.kind == 'replacement' ||
          task.kind == 'repair') {
        final status = await api.operationStatus(
          task.operationId,
          cancellation: cancellation,
        );
        if (status['state'] == 'committed') {
          if (status['actorDeviceId'] != scope.deviceId) {
            throw const CloudException(CloudErrorCode.operationConflict);
          }
          await _finish(scope, task, status);
        }
      } else {
        await _finish(scope, task, await _send(scope, api, task, cancellation));
      }
    }
  }

  Future<void> _repairSelected(
    CloudSyncScope scope,
    CloudSyncClient api,
    WorkspaceCloudAdapter adapter,
    CloudCancellation cancellation,
  ) async {
    for (final integrity in await _database.syncStore.integrityStates(scope)) {
      if (integrity.status != CloudContentStatus.needsReupload ||
          integrity.manifest == null) {
        continue;
      }
      final mapping = await _database.syncStore.mapping(
        scope,
        integrity.lineageId,
      );
      if (mapping == null ||
          mapping.retired ||
          mapping.generation != integrity.generation) {
        continue;
      }
      final (_, raw) = await _capture();
      final localId = ws.ManagedSkillId(mapping.localSkillId);
      if (raw.snapshot.findSkill(localId) == null ||
          raw.localLineageFingerprints[localId] !=
              mapping.localLineageFingerprint) {
        continue;
      }
      final batch = await adapter.exportSelected(
        mapping.localSkillId,
        cancellation,
      );
      final manifest = CloudContentManifest.fromJson(
        _object(jsonDecode(utf8.decode(batch.wireManifest))),
      );
      if (jsonEncode(manifest.toJson()) !=
          jsonEncode(integrity.manifest!.toJson())) {
        continue;
      }
      final task = await _database.syncStore.stageOutboundTask(
        scope,
        kind: 'repair',
        subjectId: mapping.localSkillId,
        data: {
          'kind': 'repair',
          'contentManifestVersion': 1,
          'lineageId': integrity.lineageId,
          'generation': integrity.generation,
          'baseCommitId': manifest.currentEffective,
          'contentManifest': manifest.toJson(),
        },
        localContext: {
          'localLineageFingerprint': mapping.localLineageFingerprint,
        },
      );
      final lease = await api.lineageTransfer(
        operationId: randomCloudToken(),
        lineageId: integrity.lineageId,
        generation: integrity.generation,
        access: CloudTransferAccess.write,
        cancellation: cancellation,
      );
      await adapter.pushExported(
        localSkillId: mapping.localSkillId,
        batch: batch,
        lease: lease,
        cancellation: cancellation,
      );
      await adapter.validateExportStillCurrent(
        localSkillId: mapping.localSkillId,
        batch: batch,
        cancellation: cancellation,
      );
      await _finish(scope, task, await _send(scope, api, task, cancellation));
    }
  }

  Future<void> _publishTags(
    CloudSyncScope scope,
    CloudSyncClient api,
    CloudCancellation cancellation,
  ) async {
    final (_, raw) = await _capture();
    // A SQL existence query covers every retained vocabulary event, including
    // events beyond one bounded pending-items page. Do not race a pending edit.
    if (await _database.syncStore.hasPendingVocabulary(scope)) return;
    final mappings = await _database.syncStore.personalTagMappings(scope);
    final localIds = raw.snapshot.personalTags.map((tag) => tag.id).toSet();
    for (final mapping in mappings) {
      if (mapping.deleted || localIds.contains(mapping.localTagId)) continue;
      final task = await _database.syncStore.stageOutboundTask(
        scope,
        kind: 'tagDelete',
        subjectId: mapping.localTagId,
        data: {'kind': 'tagDelete', 'tagId': mapping.cloudTagId},
        localContext: {},
      );
      await _finish(scope, task, await _send(scope, api, task, cancellation));
    }
    for (final tag in raw.snapshot.personalTags) {
      cancellation.throwIfCancelled();
      final matches = mappings
          .where((value) => value.localTagId == tag.id)
          .toList();
      if (matches.any((value) => value.deleted)) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      final mapping = matches.isEmpty ? null : matches.single;
      final patch = <String, Object?>{};
      if (mapping != null) {
        if (mapping.name != tag.name) patch['name'] = tag.name;
        if (mapping.color != tag.color) patch['color'] = tag.color;
        if (patch.isEmpty) continue;
      }
      final task = await _database.syncStore.stageOutboundTask(
        scope,
        kind: mapping == null ? 'tagCreate' : 'tagPatch',
        subjectId: tag.id,
        data: mapping == null
            ? {'kind': 'tagCreate', 'name': tag.name, 'color': tag.color}
            : {'kind': 'tagPatch', 'tagId': mapping.cloudTagId, 'patch': patch},
        localContext: {},
      );
      await _finish(scope, task, await _send(scope, api, task, cancellation));
    }
  }

  Future<void> _publish(
    CloudSyncScope scope,
    CloudSyncClient api,
    WorkspaceCloudAdapter adapter,
    CloudSyncProgress progress,
    CloudCancellation cancellation,
  ) async {
    await _publishTags(scope, api, cancellation);
    final selectedIds = {...progress.selection.localSkillIds};
    for (final remoteId in progress.selection.cloudLineageIds) {
      final mapping = await _database.syncStore.mapping(scope, remoteId);
      if (mapping != null && !mapping.retired) {
        selectedIds.add(mapping.localSkillId);
      }
    }
    for (final id in selectedIds) {
      cancellation.throwIfCancelled();
      final (current, raw) = await _capture();
      if (current.workspaceIdentity != scope.workspaceIdentity) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      var baseline = await _database.syncStore.publisherBaseline(scope, id);
      final local = raw.snapshot.findSkill(ws.ManagedSkillId(id));
      if (local == null) {
        if (baseline != null && !baseline.retired) {
          final task = await _database.syncStore.stageOutboundTask(
            scope,
            kind: 'removal',
            subjectId: id,
            data: {
              'kind': 'removal',
              'lineageId': baseline.lineageId,
              'generation': baseline.generation,
            },
            localContext: {
              'localLineageFingerprint': baseline.localLineageFingerprint,
            },
          );
          final result = await _send(scope, api, task, cancellation);
          await _finish(scope, task, result);
        }
        continue;
      }
      final localLineage = raw.localLineageFingerprints[local.id];
      if (localLineage == null || baseline?.retired == true) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final replacement =
          baseline != null && baseline.localLineageFingerprint != localLineage;
      final missingRemote = (await _database.syncStore.integrityStates(scope))
          .any(
            (value) =>
                value.lineageId == baseline?.lineageId &&
                value.status == CloudContentStatus.needsReupload,
          );
      if (missingRemote && !replacement) continue;
      if (!replacement &&
          baseline != null &&
          await _database.syncStore.hasPendingLineageConflict(
            scope,
            baseline.lineageId,
          )) {
        continue;
      }
      final batch = await adapter.exportSelected(id, cancellation);
      final manifest = CloudContentManifest.fromJson(
        _object(jsonDecode(utf8.decode(batch.wireManifest))),
      );
      final initialHistoryOnly =
          baseline?.initialLink == true &&
          baseline?.contentManifest != null &&
          cloudInitialRootsSatisfied(batch, baseline!.contentManifest!);
      if (replacement ||
          !initialHistoryOnly &&
              jsonEncode(baseline?.contentManifest?.toJson()) !=
                  jsonEncode(manifest.toJson())) {
        final task = await _database.syncStore.stageOutboundTask(
          scope,
          kind: replacement ? 'replacement' : 'content',
          subjectId: id,
          data: {
            'contentManifest': manifest.toJson(),
            if (baseline != null) ...{
              'lineageId': baseline.lineageId,
              'generation': baseline.generation,
              'baseCommitId': baseline.contentManifest!.currentEffective,
            },
          },
          localContext: {'localLineageFingerprint': localLineage},
        );
        // Original pending desired state must resolve before a later local edit.
        final desired = CloudContentManifest.fromJson(
          _object(task.data['contentManifest']),
        );
        if (jsonEncode(desired.toJson()) != jsonEncode(manifest.toJson())) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        final replacing = task.kind == 'replacement';
        final previous = replacing
            ? CloudReplacementTarget(
                lineageId: task.data['lineageId']! as String,
                generation: task.data['generation']! as int,
                baseCommitId: task.data['baseCommitId']! as String,
              )
            : null;
        final CloudPreparedUpload? prepared =
            task.data['lineageId'] == null || replacing
            ? await api.prepareUpload(
                api.createPrepareIntent(
                  CloudPrepareRequest(
                    operationId: task.operationId,
                    contentManifest: desired,
                    replacement: previous,
                  ),
                ),
                cancellation: cancellation,
              )
            : null;
        final transfer = prepared == null
            ? await api.lineageTransfer(
                operationId: randomCloudToken(),
                lineageId: task.data['lineageId']! as String,
                generation: task.data['generation']! as int,
                access: CloudTransferAccess.write,
                cancellation: cancellation,
              )
            : await api.preparedWriteTransfer(
                operationId: randomCloudToken(),
                uploadId: prepared.uploadId,
                cancellation: cancellation,
              );
        await adapter.pushExported(
          localSkillId: id,
          batch: batch,
          lease: transfer,
          cancellation: cancellation,
        );
        await adapter.validateExportStillCurrent(
          localSkillId: id,
          batch: batch,
          cancellation: cancellation,
        );
        final receipt = replacing
            ? CloudCommitReceipt.fromJson(
                await api.sendMutation(
                  api.createIntent(
                    operationId: task.operationId,
                    path: '/v1/sync/lifecycle',
                    data: CloudReplacementRequest(
                      operationId: task.operationId,
                      uploadId: prepared!.uploadId,
                      previous: previous!,
                      contentManifest: desired,
                    ).toJson(),
                  ),
                  cancellation: cancellation,
                ),
              )
            : await api.commit(
                api.createCommitIntent(
                  prepared == null
                      ? CloudCommitRequest.existing(
                          operationId: task.operationId,
                          lineageId: task.data['lineageId']! as String,
                          generation: task.data['generation']! as int,
                          baseCommitId: task.data['baseCommitId']! as String,
                          contentManifest: desired,
                        )
                      : CloudCommitRequest.firstUpload(
                          operationId: task.operationId,
                          uploadId: prepared.uploadId,
                          contentManifest: desired,
                        ),
                ),
                cancellation: cancellation,
              );
        await _finish(scope, task, {
          'operationId': receipt.operationId,
          'lineageId': receipt.lineageId,
          'generation': receipt.generation,
          'commitId': receipt.commitId,
          'sequence': receipt.sequence.toJson(),
          'outcome': receipt.outcome,
          'receiptExpiresAt': receipt.expiresAt.millisecondsSinceEpoch,
          'contentManifestVersion': 1,
          'contentManifest': receipt.contentManifest.toJson(),
        });
        baseline = await _database.syncStore.publisherBaseline(scope, id);
      }
      if (baseline == null || !baseline.favoriteKnown || !baseline.noteKnown) {
        continue; // Initial metadata differences require an explicit choice.
      }
      // Use the latest public capture after all potentially delayed content work.
      final (_, latest) = await _capture();
      final selected = latest.snapshot.findSkill(local.id);
      if (selected == null) continue;
      final patch = <String, Object?>{};
      if (selected.favorite.isFavorite != baseline.favorite) {
        patch['favorite'] = selected.favorite.isFavorite;
      }
      if (selected.note?.text != baseline.note) {
        patch['note'] = selected.note?.text;
      }
      if (patch.isNotEmpty) {
        final task = await _database.syncStore.stageOutboundTask(
          scope,
          kind: 'fields',
          subjectId: id,
          data: {
            'kind': 'fields',
            'lineageId': baseline.lineageId,
            'generation': baseline.generation,
            'patch': patch,
          },
          localContext: {'localLineageFingerprint': localLineage},
        );
        final result = await _send(scope, api, task, cancellation);
        await _finish(scope, task, result);
      }
      baseline = await _database.syncStore.publisherBaseline(scope, id);
      final (_, latestTags) = await _capture();
      final skillForTags = latestTags.snapshot.findSkill(local.id);
      if (skillForTags == null || baseline == null) continue;
      final desiredTags = skillForTags.personalTagIds.toSet();
      final mappings = await _database.syncStore.personalTagMappings(scope);
      for (final tagId in {...baseline.localTagIds, ...desiredTags}) {
        final add = desiredTags.contains(tagId);
        if (add == baseline.localTagIds.contains(tagId)) continue;
        final mapping = mappings
            .where((value) => value.localTagId == tagId && !value.deleted)
            .firstOrNull;
        if (mapping == null) continue; // Unresolved vocabulary stays pending.
        final task = await _database.syncStore.stageOutboundTask(
          scope,
          kind: 'assignment',
          subjectId: '$id:$tagId',
          data: {
            'kind': 'assignment',
            'lineageId': baseline.lineageId,
            'generation': baseline.generation,
            'tagId': mapping.cloudTagId,
            'action': add ? 'add' : 'remove',
          },
          localContext: {
            'localSkillId': id,
            'localTagId': tagId,
            'localLineageFingerprint': localLineage,
          },
        );
        await _finish(scope, task, await _send(scope, api, task, cancellation));
      }
    }
  }

  Future<AppCloudSyncView> synchronize() {
    if (_running != null) {
      throw const CloudException(CloudErrorCode.operationInProgress);
    }
    final cancellation = CloudCancellation();
    _active = cancellation;
    final future = _synchronize(cancellation);
    _running = future;
    return future.whenComplete(() {
      _running = null;
      _active = null;
    });
  }

  Future<void> _pullAllChanges(
    CloudSyncCoordinator coordinator,
    CloudCancellation cancellation,
  ) async {
    var progress = await coordinator.pullChanges(cancellation: cancellation);
    var pages = 1;
    while (progress.traversalHighWatermark != null) {
      if (pages++ >= 64) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      progress = await coordinator.pullChanges(cancellation: cancellation);
    }
  }

  Future<AppCloudSyncView> _synchronize(CloudCancellation cancellation) async {
    final (scope, _) = await _capture();
    final api = _api(scope), store = _database.syncStore;
    final progress = await store.progress(scope);
    if (!progress.isEnabled || progress.needsReconciliation) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    // Receipt recovery only reads remote state or replays the exact saved intent.
    // Ownership still gates every request that can create remote state.
    final canMutate = await _canMutate();
    if (canMutate) await _recoverConfirmed(scope, api, cancellation);
    final adapter = _adapter(scope, api),
        coordinator = CloudSyncCoordinator(
          scope: scope,
          auth: _auth,
          api: api,
          store: store,
          workspace: adapter,
        );
    if (progress.selection.cloudLineageIds.isNotEmpty &&
        progress.snapshotId == null &&
        progress.received.value == BigInt.zero) {
      var received = await coordinator.pullSnapshotPage(
        cancellation: cancellation,
      );
      while (received.snapshotCursor != null) {
        received = await coordinator.pullSnapshotPage(
          cancellation: cancellation,
        );
      }
    } else {
      await _pullAllChanges(coordinator, cancellation);
    }
    // Ownership conflicts permit reception, but never local apply or new writes.
    if (!canMutate || !await _canMutate()) return overview(loadChoices: false);
    await coordinator.applyPending(cancellation: cancellation);
    await _repairSelected(scope, api, adapter, cancellation);
    await _publish(
      scope,
      api,
      adapter,
      await store.progress(scope),
      cancellation,
    );
    await _pullAllChanges(coordinator, cancellation);
    await coordinator.applyPending(cancellation: cancellation);
    return overview(loadChoices: false);
  }

  Future<void> cancelAndDrain() async {
    _active?.cancel();
    try {
      await _running;
    } catch (_) {
      /* Keep original durable evidence. */
    }
  }

  Future<AppCloudSyncView> stop() async {
    await cancelAndDrain();
    final scope = _lastScope;
    if (scope != null) {
      try {
        await _database.syncStore.setEnabled(scope, false);
      } on CloudException {
        /* No initialized scope yet. */
      }
    }
    if (_auth.currentSession == null) return const AppCloudSyncView();
    return overview(loadChoices: false);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await cancelAndDrain();
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return value;
}
