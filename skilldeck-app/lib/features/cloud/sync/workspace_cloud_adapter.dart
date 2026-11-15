import 'dart:async';
import 'dart:convert';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_workspace/skills_workspace.dart' as ws;

/// Resolves only the public Workspace's caller-bound exact outcome proof.
typedef CloudWorkspaceOutcomeReader = Future<CloudApplyResult> Function({
  required ws.SkillsRepository repository,
  required CloudSyncScope scope,
  required CloudInboxItem item,
  required CloudApplyBinding binding,
  required CloudCancellation cancellation,
});
typedef CloudWorkspaceRemoteFactory = ws.RevisionTransferRemote Function(
  CloudTransferLease lease,
);

CloudWorkspaceCapture _projectCapture(
  ws.AuthoritativeWorkspaceCapture captured,
) => CloudWorkspaceCapture(
  identity: CloudWorkspaceIdentity(
    workspaceId: captured.identity.workspaceId,
    recoveryIncarnation: captured.identity.recoveryIncarnation,
  ),
  revision: captured.snapshot.revision.value.toString(),
  recoveryComplete: captured.recoveryComplete,
  finalizationComplete: captured.finalizationComplete,
  isComplete: captured.isComplete,
  localLineageFingerprints: Map.unmodifiable(
    captured.localLineageFingerprints.map(
      (key, value) => MapEntry(key.value, value),
    ),
  ),
);

Future<CloudApplyResult> _readPublicPersonalTagOutcome({
  required ws.SkillsRepository repository,
  required CloudSyncScope scope,
  required CloudInboxItem item,
  required CloudApplyBinding binding,
  required CloudCancellation cancellation,
}) async {
  final target = binding.localTargetId,
      fingerprint = binding.workspaceRequestFingerprint;
  if (target == null || fingerprint == null) {
    return const CloudApplyPending(CloudPendingReason.unknownOutcome);
  }
  cancellation.throwIfCancelled();
  final command = ws.PersonalTagCommandBinding(
    operationId: ws.OperationId(binding.operationId),
    requestFingerprint: fingerprint,
    personalTagId: target,
    expectedIdentity: ws.WorkspaceIdentity(
      workspaceId: scope.workspaceIdentity.workspaceId,
      recoveryIncarnation: scope.workspaceIdentity.recoveryIncarnation,
    ),
  );
  final result = await repository
      .inspectPersonalTagMutationOutcome(
        ws.InspectPersonalTagMutationOutcomeRequest(binding: command),
      )
      .completed;
  cancellation.throwIfCancelled();
  if (result is! ws.SkillsSuccess<ws.PersonalTagMutationOutcome>) {
    return const CloudApplyPending(CloudPendingReason.unknownOutcome);
  }
  final outcome = result.value, raw = result.value.capture;
  if (raw == null) {
    return CloudApplyPending(
      outcome.status == ws.PersonalTagMutationStatus.nameConflict
          ? CloudPendingReason.nameConflict
          : CloudPendingReason.unknownOutcome,
    );
  }
  final capture = _projectCapture(raw);
  if (!capture.ready || capture.identity != scope.workspaceIdentity) {
    return const CloudApplyPending(CloudPendingReason.needsReconciliation);
  }
  final stable = '${binding.operationId}:$fingerprint';
  return switch (outcome.status) {
    ws.PersonalTagMutationStatus.applied
        when outcome.committedRevision != null =>
      CloudApplied(
        eventKey: item.eventKey,
        operationId: binding.operationId,
        desiredFingerprint: binding.desiredFingerprint,
        capture: capture,
        localSkillId: target,
        proofId: '$stable:applied:${outcome.committedRevision!.value}',
      ),
    ws.PersonalTagMutationStatus.confirmedNotStarted =>
      CloudConfirmedNotStarted(
        eventKey: item.eventKey,
        operationId: binding.operationId,
        capture: capture,
        proofId: '$stable:notStarted',
      ),
    ws.PersonalTagMutationStatus.nameConflict => const CloudApplyPending(
      CloudPendingReason.nameConflict,
    ),
    _ => const CloudApplyPending(CloudPendingReason.unknownOutcome),
  };
}

Future<CloudApplyResult> _readDesiredRemovalOutcome({
  required ws.SkillsRepository repository,
  required CloudSyncScope scope,
  required CloudInboxItem item,
  required CloudApplyBinding binding,
  required CloudCancellation cancellation,
}) async {
  final target = binding.localTargetId,
      fingerprint = binding.localLineageFingerprint;
  if (target == null || fingerprint == null) {
    return const CloudApplyPending(CloudPendingReason.needsReconciliation);
  }
  cancellation.throwIfCancelled();
  final result = await repository
      .captureAuthoritativeState(const ws.CaptureAuthoritativeStateRequest())
      .completed;
  cancellation.throwIfCancelled();
  if (result is! ws.SkillsSuccess<ws.AuthoritativeWorkspaceCapture>) {
    return const CloudApplyPending(CloudPendingReason.unknownOutcome);
  }
  final raw = result.value, capture = _projectCapture(raw);
  if (!capture.ready || capture.identity != scope.workspaceIdentity) {
    return const CloudApplyPending(CloudPendingReason.needsReconciliation);
  }
  final skill = raw.snapshot.findSkill(ws.ManagedSkillId(target));
  if (skill == null) {
    return CloudTargetAbsent(
      eventKey: item.eventKey,
      operationId: binding.operationId,
      desiredFingerprint: binding.desiredFingerprint,
      capture: capture,
      localSkillId: target,
      cleanupComplete: true,
      proofId: 'absence:$target:$fingerprint',
    );
  }
  if (raw.localLineageFingerprints[skill.id] != fingerprint) {
    return CloudSuperseded(
      eventKey: item.eventKey,
      operationId: binding.operationId,
      desiredFingerprint: binding.desiredFingerprint,
      capture: capture,
      localSkillId: target,
      retiredGeneration: item.change.generation!,
      proofId: 'retired:$target:$fingerprint',
    );
  }
  if (skill.draft?.isDirty == true || skill.updateCandidate != null) {
    return const CloudApplyPending(CloudPendingReason.dirtyDraft);
  }
  return CloudRetryDesiredRemovalAllowed(
    eventKey: item.eventKey,
    operationId: binding.operationId,
    capture: capture,
    localTargetId: target,
    localLineageFingerprint: fingerprint,
  );
}

Future<CloudApplyResult> _readPublicWorkspaceOutcome({
  required ws.SkillsRepository repository,
  required CloudSyncScope scope,
  required CloudInboxItem item,
  required CloudApplyBinding binding,
  required CloudCancellation cancellation,
}) async {
  if (item.change.kind == 'personalTag') {
    return _readPublicPersonalTagOutcome(
      repository: repository,
      scope: scope,
      item: item,
      binding: binding,
      cancellation: cancellation,
    );
  }
  if (item.change.kind == 'removal') {
    return _readDesiredRemovalOutcome(
      repository: repository,
      scope: scope,
      item: item,
      binding: binding,
      cancellation: cancellation,
    );
  }
  final target = binding.localTargetId,
      fingerprint = binding.workspaceRequestFingerprint,
      lineage = binding.localLineageFingerprint;
  if (target == null || fingerprint == null || lineage == null) {
    return const CloudApplyPending(CloudPendingReason.unknownOutcome);
  }
  cancellation.throwIfCancelled();
  final command = ws.IncomingRevisionCommandBinding(
    operationId: ws.OperationId(binding.operationId),
    requestFingerprint: fingerprint,
    targetManagedSkillId: ws.ManagedSkillId(target),
    localLineageFingerprint: lineage,
    expectedIdentity: ws.WorkspaceIdentity(
      workspaceId: scope.workspaceIdentity.workspaceId,
      recoveryIncarnation: scope.workspaceIdentity.recoveryIncarnation,
    ),
  );
  final operation = repository.inspectIncomingRevisionOutcome(
    ws.InspectIncomingRevisionOutcomeRequest(binding: command),
  );
  final unlisten = cancellation.listen(
    () => unawaited(operation.cancel().catchError((Object _) {})),
  );
  try {
    final result = await operation.completed;
    cancellation.throwIfCancelled();
    if (result is! ws.SkillsSuccess<ws.IncomingRevisionOutcome>) {
      return const CloudApplyPending(CloudPendingReason.unknownOutcome);
    }
    final proof = result.value,
        actual = proof.binding,
        captured = proof.capture;
    if (actual.operationId != command.operationId ||
        actual.requestFingerprint != fingerprint ||
        actual.targetManagedSkillId != command.targetManagedSkillId ||
        actual.localLineageFingerprint != lineage ||
        actual.expectedIdentity != command.expectedIdentity ||
        captured == null) {
      return const CloudApplyPending(CloudPendingReason.unknownOutcome);
    }
    final capture = CloudWorkspaceCapture(
      identity: CloudWorkspaceIdentity(
        workspaceId: captured.identity.workspaceId,
        recoveryIncarnation: captured.identity.recoveryIncarnation,
      ),
      revision: captured.snapshot.revision.value.toString(),
      recoveryComplete: captured.recoveryComplete,
      finalizationComplete: captured.finalizationComplete,
      isComplete: captured.isComplete,
    );
    if (!capture.ready || capture.identity != scope.workspaceIdentity) {
      return const CloudApplyPending(CloudPendingReason.needsReconciliation);
    }
    final stable = '${binding.operationId}:$fingerprint';
    return switch (proof.status) {
      ws.IncomingRevisionOutcomeStatus.applied
          when proof.committedRevision != null =>
        CloudApplied(
          eventKey: item.eventKey,
          operationId: binding.operationId,
          desiredFingerprint: binding.desiredFingerprint,
          capture: capture,
          localSkillId: target,
          proofId: '$stable:applied:${proof.committedRevision!.value}',
        ),
      ws.IncomingRevisionOutcomeStatus.targetAbsent
          when captured.snapshot.findSkill(command.targetManagedSkillId) ==
              null =>
        CloudTargetAbsent(
          eventKey: item.eventKey,
          operationId: binding.operationId,
          desiredFingerprint: binding.desiredFingerprint,
          capture: capture,
          localSkillId: target,
          cleanupComplete: true,
          proofId: '$stable:targetAbsent',
        ),
      ws.IncomingRevisionOutcomeStatus.superseded
          when item.change.generation != null =>
        CloudSuperseded(
          eventKey: item.eventKey,
          operationId: binding.operationId,
          desiredFingerprint: binding.desiredFingerprint,
          capture: capture,
          localSkillId: target,
          retiredGeneration: item.change.generation!,
          proofId: '$stable:superseded',
        ),
      ws.IncomingRevisionOutcomeStatus.confirmedNotStarted =>
        CloudConfirmedNotStarted(
          eventKey: item.eventKey,
          operationId: binding.operationId,
          capture: capture,
          proofId: '$stable:notStarted',
        ),
      _ => const CloudApplyPending(CloudPendingReason.unknownOutcome),
    };
  } finally {
    unlisten();
  }
}

ws.RevisionTransferRemote _strictRemote(CloudTransferLease lease) {
  if (lease.remote.scheme != 'https' || lease.remote.userInfo.isNotEmpty) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return ws.RevisionTransferRemote(
    url: lease.remote.toString(),
    ephemeralHeaders: lease.authorizationHeaders,
  );
}

/// Full root/provenance match for fresh initial linking, including remote history.
bool cloudInitialRootsSatisfied(
  ws.CommittedRevisionBatch local,
  CloudContentManifest remote,
) {
  final actual = CloudContentManifest.fromJson(
    jsonDecode(utf8.decode(local.wireManifest)) as Map<String, Object?>,
  );
  return jsonEncode(actual.source.toJson()) ==
          jsonEncode(remote.source.toJson()) &&
      actual.slotKey == remote.slotKey &&
      actual.contentHash == remote.contentHash &&
      actual.currentUpstream == remote.currentUpstream &&
      actual.currentEffective == remote.currentEffective;
}

bool cloudInitialContentSatisfied(
  ws.CommittedRevisionBatch local,
  CloudContentManifest remote,
) {
  final actual = CloudContentManifest.fromJson(
    jsonDecode(utf8.decode(local.wireManifest)) as Map<String, Object?>,
  );
  return cloudInitialRootsSatisfied(local, remote) &&
      remote.publishedHistory.every(
        (event) => actual.publishedHistory.any(
          (candidate) =>
              jsonEncode(candidate.toJson()) == jsonEncode(event.toJson()),
        ),
      );
}

/// Composes only public Workspace operations with Cloud's independent state.
final class WorkspaceCloudAdapter implements CloudWorkspacePort {
  WorkspaceCloudAdapter({
    required ws.SkillsRepository repository,
    required CloudSyncScope scope,
    required CloudSyncClient api,
    this.boundedNetworkFetchQualified = false,
    CloudWorkspaceOutcomeReader? outcomeReader,
    CloudSyncStore? syncStore,
  }) : _repository = repository,
       _scope = scope,
       _api = api,
       _outcomeReader = outcomeReader ?? _readPublicWorkspaceOutcome,
       _remoteFactory = _strictRemote,
       _syncStore = syncStore;

  /// Installs a trusted test fixture mapping without weakening production URLs.
  WorkspaceCloudAdapter.withTestRemoteFactory({
    required ws.SkillsRepository repository,
    required CloudSyncScope scope,
    required CloudSyncClient api,
    required CloudWorkspaceRemoteFactory remoteFactory,
    this.boundedNetworkFetchQualified = false,
    CloudWorkspaceOutcomeReader? outcomeReader,
    CloudSyncStore? syncStore,
  }) : _repository = repository,
       _scope = scope,
       _api = api,
       _outcomeReader = outcomeReader ?? _readPublicWorkspaceOutcome,
       _remoteFactory = remoteFactory,
       _syncStore = syncStore;
  final ws.SkillsRepository _repository;
  final CloudSyncScope _scope;
  final CloudSyncClient _api;
  final CloudWorkspaceOutcomeReader? _outcomeReader;
  final CloudWorkspaceRemoteFactory _remoteFactory;
  final CloudSyncStore? _syncStore;

  Future<void> _portTail = Future.value();
  // The public authoritative-ready contract excludes active transfers. Keep
  // each native preparation and local transaction inside this adapter gate;
  // Cloud's core still bounds independent preparation jobs to at most four.
  Future<T> _portGate<T>(Future<T> Function() action) async {
    final prior = _portTail, release = Completer<void>();
    _portTail = release.future;
    await prior;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  /// The explicit composition gate for the native bounded-network-fetch qualification.
  final bool boundedNetworkFetchQualified;

  Future<T> _success<T>(
    ws.SkillsOperation<T> operation,
    CloudCancellation cancellation,
  ) async {
    if (cancellation.isCancelled) {
      try {
        await operation.cancel();
      } catch (_) {}
      await operation.completed;
      throw const CloudException(CloudErrorCode.cancelled);
    }
    final unlisten = cancellation.listen(
      () => unawaited(operation.cancel().catchError((Object _) {})),
    );
    try {
      final result = await operation.completed;
      cancellation.throwIfCancelled();
      if (result case ws.SkillsSuccess<T>(:final value)) return value;
      if (result case ws.SkillsFailure<T>(:final code)) {
        throw CloudException(switch (code) {
          ws.SkillsErrorCode.operationCancelled => CloudErrorCode.cancelled,
          ws.SkillsErrorCode.staleSnapshot => CloudErrorCode.staleSnapshot,
          ws.SkillsErrorCode.repositoryBusy =>
            CloudErrorCode.operationInProgress,
          ws.SkillsErrorCode.skillNotFound => CloudErrorCode.missingLineage,
          ws.SkillsErrorCode.dirtyDraftResolutionRequired ||
          ws.SkillsErrorCode.updateCandidateResolutionRequired =>
            CloudErrorCode.dirtyDraftRequired,
          _ => CloudErrorCode.unavailable,
        });
      }
      throw const CloudException(CloudErrorCode.needsReconciliation);
    } on CloudException {
      rethrow;
    } catch (_) {
      throw const CloudException(CloudErrorCode.unavailable);
    } finally {
      unlisten();
    }
  }

  CloudWorkspaceCapture _project(ws.AuthoritativeWorkspaceCapture capture) =>
      _projectCapture(capture);
  Future<ws.AuthoritativeWorkspaceCapture> _capture(
    CloudCancellation cancellation,
  ) async {
    final value = await _success(
      _repository.captureAuthoritativeState(
        const ws.CaptureAuthoritativeStateRequest(),
      ),
      cancellation,
    );
    final capture = _project(value);
    if (!capture.ready || capture.identity != _scope.workspaceIdentity) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    return value;
  }

  @override
  Future<CloudWorkspaceCapture> capture() =>
      _portGate(() async => _project(await _capture(CloudCancellation())));

  /// Exports a caller-selected existing Skill without exposing private Store paths.
  Future<ws.CommittedRevisionBatch> exportSelected(
    String localSkillId,
    CloudCancellation cancellation,
  ) async {
    final before = await _capture(cancellation);
    final batch = await _success(
      _repository.exportCommittedRevision(
        ws.ExportCommittedRevisionRequest(
          managedSkillId: ws.ManagedSkillId(localSkillId),
          expectedRevision: before.snapshot.revision,
        ),
      ),
      cancellation,
    );
    if (batch.identity != before.identity) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    return batch;
  }

  /// Pushes a verified local export through the native Git channel only.
  Future<ws.RevisionTransferReport> pushExported({
    required String localSkillId,
    required ws.CommittedRevisionBatch batch,
    required CloudTransferLease lease,
    required CloudCancellation cancellation,
  }) async {
    if (lease.access != CloudTransferAccess.write) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    try {
      final before = await _capture(cancellation);
      if (before.snapshot.findSkill(ws.ManagedSkillId(localSkillId)) == null) {
        throw const CloudException(CloudErrorCode.missingLineage);
      }
      if (batch.identity != before.identity) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      return await _success(
        _repository.pushCommittedRevision(
          ws.PushCommittedRevisionRequest(
            managedSkillId: ws.ManagedSkillId(localSkillId),
            expectedIdentity: before.identity,
            expectedRevision: before.snapshot.revision,
            batch: batch,
            remote: _remoteFactory(lease),
          ),
        ),
        cancellation,
      );
    } finally {
      lease.invalidate();
    }
  }

  /// Revalidates an in-memory export immediately before remote admission.
  ///
  /// Removal/Replacement never causes this adapter to reuse captured old bytes.
  Future<void> validateExportStillCurrent({
    required String localSkillId,
    required ws.CommittedRevisionBatch batch,
    required CloudCancellation cancellation,
  }) async {
    final before = await _capture(cancellation);
    if (before.snapshot.findSkill(ws.ManagedSkillId(localSkillId)) == null) {
      throw const CloudException(CloudErrorCode.missingLineage);
    }
    final current = await _success(
      _repository.exportCommittedRevision(
        ws.ExportCommittedRevisionRequest(
          managedSkillId: ws.ManagedSkillId(localSkillId),
          expectedRevision: before.snapshot.revision,
        ),
      ),
      cancellation,
    );
    if (current.identity != batch.identity ||
        current.source != batch.source ||
        current.currentEffective != batch.currentEffective ||
        current.currentUpstream != batch.currentUpstream ||
        utf8.decode(current.wireManifest) != utf8.decode(batch.wireManifest)) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }

  @override
  Future<CloudIncomingHandle> prepareIncoming({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  }) => _portGate(
    () => _prepareIncomingLocked(
      item: item,
      binding: binding,
      scope: scope,
      cancellation: cancellation,
    ),
  );

  Future<CloudIncomingHandle> _prepareIncomingLocked({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _prepareIncomingOnce(
          item: item,
          binding: binding,
          scope: scope,
          cancellation: cancellation,
        );
      } on CloudException catch (error) {
        if (attempt >= 2 ||
            ![
              CloudErrorCode.staleSnapshot,
              CloudErrorCode.operationInProgress,
            ].contains(error.code)) {
          rethrow;
        }
        cancellation.throwIfCancelled();
        // Only preparation is retried: the stable caller operation and target
        // survive, and no unknown local mutation is invoked again here.
        await Future<void>.delayed(Duration(milliseconds: 20 * (1 << attempt)));
      }
    }
  }

  Future<CloudIncomingHandle> _prepareIncomingOnce({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  }) async {
    if (!boundedNetworkFetchQualified) {
      throw const CloudException(CloudErrorCode.unavailable);
    }
    if (scope.workspaceIdentity != _scope.workspaceIdentity ||
        scope.accountId != _scope.accountId ||
        scope.deviceId != _scope.deviceId ||
        !['revision', 'replacement'].contains(item.change.kind)) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    final lineage = CloudLineage.fromJson(item.change.payload),
        manifest = lineage.contentManifest;
    if (lineage.contentStatus != CloudContentStatus.ready || manifest == null) {
      throw const CloudException(CloudErrorCode.needsReupload);
    }
    final before = await _capture(cancellation);
    String? initialExistingTarget;
    // Only a genuinely fresh initial snapshot may link a pre-existing Skill.
    // Unknown native operations always go through the caller outcome reader.
    if (binding.localTargetId == null &&
        item.pendingReason == null &&
        item.eventKey.startsWith('snapshot:')) {
      final local = before.snapshot.findSkillBySlotKey(lineage.slotKey);
      if (local != null) {
        final exported = await exportSelected(local.id.value, cancellation);
        if (cloudInitialContentSatisfied(exported, manifest) ||
            !cloudInitialRootsSatisfied(exported, manifest)) {
          return _WorkspaceInitialLink(
            owner: this,
            eventKey: item.eventKey,
            target: local.id.value,
            lineage: before.localLineageFingerprints[local.id]!,
            satisfied: cloudInitialContentSatisfied(exported, manifest),
          );
        }
        // Roots already match. Import the missing remote history through the
        // real Workspace transaction; retain all local history and Extra Data.
        initialExistingTarget = local.id.value;
      }
    }
    final lease = await _api.lineageTransfer(
      operationId: randomCloudToken(),
      lineageId: lineage.lineageId,
      generation: lineage.generation,
      access: CloudTransferAccess.read,
      cancellation: cancellation,
    );
    try {
      final batch = await _success(
        _repository.fetchIncomingRevision(
          ws.FetchIncomingRevisionRequest(
            managedSkillId:
                (initialExistingTarget ?? binding.localTargetId) == null
                ? null
                : ws.ManagedSkillId(
                    (initialExistingTarget ?? binding.localTargetId)!,
                  ),
            replaceExistingLineage: item.change.kind == 'replacement',
            localOperationId: ws.OperationId(binding.operationId),
            expectedIdentity: before.identity,
            expectedRevision: before.snapshot.revision,
            contentManifest: utf8.encode(jsonEncode(manifest.toJson())),
            remote: _remoteFactory(lease),
          ),
        ),
        cancellation,
      );
      final command = batch.localCommand;
      if (batch.identity != before.identity ||
          command == null ||
          command.operationId.value != binding.operationId ||
          command.expectedIdentity != before.identity) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      return _WorkspaceIncoming(
        owner: this,
        batch: batch,
        desiredFingerprint: binding.desiredFingerprint,
        eventKey: item.eventKey,
        preexistingTarget:
            initialExistingTarget != null || binding.preexistingTarget == true,
      );
    } finally {
      lease.invalidate();
    }
  }

  Future<CloudIncomingHandle> _preparePersonalTag(
    CloudInboxItem item,
    CloudApplyBinding binding,
    CloudCancellation cancellation,
  ) async {
    final store = _syncStore;
    if (store == null) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final payload = item.change.payload, id = payload['tagId'];
    if (id is! String) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
    final mapping = await store.personalTagMapping(_scope, id),
        before = await _capture(cancellation);
    final kind = payload['kind'];
    if (kind != 'tagCreate' && (mapping == null || mapping.deleted)) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final local = mapping == null
        ? null
        : before.snapshot.findPersonalTag(mapping.localTagId);
    if (mapping != null &&
        (local == null ||
            local.name != mapping.name ||
            local.color != mapping.color)) {
      throw const CloudException(CloudErrorCode.operationConflict);
    }
    final patch = payload['patch'] as Map<String, Object?>?;
    final name =
        (kind == 'tagCreate'
                ? payload['name']
                : patch?['name'] ?? mapping?.name)
            as String?;
    if (name != null && name.trim() != name) {
      throw const CloudException(CloudErrorCode.unsupportedNormalization);
    }
    final color =
        (kind == 'tagCreate'
                ? payload['color']
                : patch?.containsKey('color') == true
                ? patch!['color']
                : mapping?.color)
            as String?;
    final mutation = ws.PersonalTagMutation(
      kind: kind == 'tagDelete'
          ? ws.PersonalTagMutationKind.delete
          : mapping == null
          ? ws.PersonalTagMutationKind.create
          : ws.PersonalTagMutationKind.update,
      personalTagId: mapping?.localTagId,
      name: kind == 'tagDelete' ? null : name,
      color: color,
    );
    final command = await _success(
      _repository.reservePersonalTagMutation(
        ws.ReservePersonalTagMutationRequest(
          expectedIdentity: before.identity,
          expectedRevision: before.snapshot.revision,
          localOperationId: ws.OperationId(binding.operationId),
          mutation: mutation,
        ),
      ),
      cancellation,
    );
    return _WorkspaceTagIncoming(
      owner: this,
      eventKey: item.eventKey,
      command: command,
      mutation: mutation,
    );
  }

  Future<CloudIncomingHandle> _prepareRemoval(
    CloudInboxItem item,
    CloudApplyBinding binding,
    CloudLineageMapping? mapping,
    CloudCancellation cancellation,
  ) async {
    if (mapping == null || mapping.localLineageFingerprint == null) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    await _capture(cancellation);
    return _WorkspaceRemovalIncoming(
      owner: this,
      eventKey: item.eventKey,
      target: mapping.localSkillId,
      lineage: mapping.localLineageFingerprint!,
    );
  }

  Future<CloudApplyResult> _applyPersonalTag(
    CloudInboxItem item,
    CloudApplyBinding binding,
    _WorkspaceTagIncoming handle,
    CloudWorkspaceCapture expected,
    CloudCancellation cancellation,
  ) async {
    if (!identical(handle.owner, this) ||
        handle.eventKey != item.eventKey ||
        handle.localTargetId != binding.localTargetId ||
        handle.workspaceRequestFingerprint !=
            binding.workspaceRequestFingerprint) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    final before = await _capture(cancellation);
    if (before.snapshot.revision.value.toString() != expected.revision) {
      return const CloudApplyPending(CloudPendingReason.needsReconciliation);
    }
    final result = await _success(
      _repository.applyPersonalTagMutation(
        ws.ApplyPersonalTagMutationRequest(
          binding: handle.command,
          expectedRevision: before.snapshot.revision,
          mutation: handle.mutation,
        ),
      ),
      cancellation,
    );
    if (result.status == ws.PersonalTagMutationStatus.nameConflict) {
      return const CloudApplyPending(CloudPendingReason.nameConflict);
    }
    return _readPublicPersonalTagOutcome(
      repository: _repository,
      scope: _scope,
      item: item,
      binding: binding,
      cancellation: cancellation,
    );
  }

  @override
  Future<CloudIncomingHandle> prepareStateChange({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) => _portGate(
    () => _prepareStateChangeLocked(
      item: item,
      binding: binding,
      scope: scope,
      mapping: mapping,
      cancellation: cancellation,
    ),
  );

  Future<CloudIncomingHandle> _prepareStateChangeLocked({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) async {
    if (item.change.kind == 'personalTag') {
      return _preparePersonalTag(item, binding, cancellation);
    }
    if (item.change.kind == 'removal') {
      return _prepareRemoval(item, binding, mapping, cancellation);
    }
    if (item.change.kind != 'metadata' ||
        !['fields', 'assignment'].contains(item.change.payload['kind']) ||
        mapping == null) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final before = await _capture(cancellation);
    final localId = ws.ManagedSkillId(mapping.localSkillId);
    if (mapping.localLineageFingerprint == null ||
        before.localLineageFingerprints[localId] !=
            mapping.localLineageFingerprint) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final baseline = await _syncStore?.publisherBaseline(
      _scope,
      mapping.localSkillId,
    );
    final initialLink =
        baseline?.initialLink == true && item.eventKey.startsWith('snapshot:');
    final existing = before.snapshot.findSkill(localId);
    if (existing == null) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final ws.SkillExtraDataPatch patch;
    if (item.change.payload['kind'] == 'assignment') {
      final store = _syncStore, tagId = item.change.payload['tagId'];
      if (store == null || tagId is! String) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final tag = await store.personalTagMapping(_scope, tagId);
      if (tag == null || tag.deleted) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final add = item.change.payload['action'] == 'add';
      final localAssigned = existing.personalTagIds.contains(tag.localTagId);
      final confirmedAssigned =
          baseline?.localTagIds.contains(tag.localTagId) ?? false;
      if ((initialLink || localAssigned != confirmedAssigned) &&
          localAssigned != add) {
        throw const CloudException(CloudErrorCode.metadataConflict);
      }
      patch = ws.SkillExtraDataPatch(
        addPersonalTagIds: add ? {tag.localTagId} : {},
        removePersonalTagIds: add ? {} : {tag.localTagId},
      );
    } else {
      final raw = item.change.payload['patch'];
      if (raw is! Map<String, Object?>) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      final note = raw['note'];
      if (note != null && (note is! String || note.trim() != note)) {
        throw const CloudException(CloudErrorCode.unsupportedNormalization);
      }
      final favorite = raw['favorite'];
      if (favorite != null && favorite is! bool) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      patch = ws.SkillExtraDataPatch(
        favorite: raw.containsKey('favorite')
            ? (favorite as bool?) ?? false
            : null,
        noteChanged: raw.containsKey('note'),
        note: note == '' ? null : note as String?,
      );
    }
    if (patch.favorite != null &&
            patch.favorite != existing.favorite.isFavorite &&
            (initialLink ||
                (baseline?.favoriteKnown == true
                    ? existing.favorite.isFavorite != baseline!.favorite
                    : existing.favorite.isFavorite ||
                          existing.favorite.changedAt != null)) ||
        patch.noteChanged &&
            patch.note != existing.note?.text &&
            (initialLink ||
                (baseline?.noteKnown == true
                    ? existing.note?.text != baseline!.note
                    : existing.note != null))) {
      // Protect an unsent local edit. Confirmed server-order LWW is unchanged;
      // this client cannot yet settle the unsent publication order safely.
      throw const CloudException(CloudErrorCode.metadataConflict);
    }
    final command = await _success(
      _repository.reserveSkillExtraDataPatch(
        ws.ReserveSkillExtraDataPatchRequest(
          managedSkillId: ws.ManagedSkillId(mapping.localSkillId),
          expectedIdentity: before.identity,
          expectedRevision: before.snapshot.revision,
          localOperationId: ws.OperationId(binding.operationId),
          patch: patch,
        ),
      ),
      cancellation,
    );
    if (command.operationId.value != binding.operationId ||
        command.targetManagedSkillId.value != mapping.localSkillId ||
        command.expectedIdentity != before.identity) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    return _WorkspaceStateIncoming(
      owner: this,
      command: command,
      patch: patch,
      eventKey: item.eventKey,
      desiredFingerprint: binding.desiredFingerprint,
    );
  }

  @override
  Future<CloudApplyResult> applyIncoming({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) => _portGate(
    () => _applyIncomingLocked(
      item: item,
      binding: binding,
      handle: handle,
      expected: expected,
      mapping: mapping,
      cancellation: cancellation,
    ),
  );

  Future<CloudApplyResult> _applyIncomingLocked({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) async {
    if (handle is _WorkspaceInitialLink) {
      if (!identical(handle.owner, this) ||
          handle.eventKey != item.eventKey ||
          handle.localTargetId != binding.localTargetId ||
          handle.localLineageFingerprint != binding.localLineageFingerprint ||
          mapping != null ||
          item.pendingReason != null ||
          !item.eventKey.startsWith('snapshot:')) {
        throw const CloudException(CloudErrorCode.invalidRequest);
      }
      if (!handle.satisfied) {
        return const CloudApplyPending(CloudPendingReason.divergence);
      }
      final before = await _capture(cancellation);
      if (_project(before).revision != expected.revision ||
          before.localLineageFingerprints[ws.ManagedSkillId(handle.target)] !=
              handle.lineage) {
        return const CloudApplyPending(CloudPendingReason.needsReconciliation);
      }
      final exported = await exportSelected(handle.target, cancellation);
      final manifest = CloudLineage.fromJson(item.change.payload)
          .contentManifest!;
      if (!cloudInitialContentSatisfied(exported, manifest)) {
        return const CloudApplyPending(CloudPendingReason.divergence);
      }
      return CloudStateAlreadySatisfied(
        eventKey: item.eventKey,
        operationId: binding.operationId,
        desiredFingerprint: binding.desiredFingerprint,
        capture: _project(before),
        localSkillId: handle.target,
        localLineageFingerprint: handle.lineage,
        proofId:
            'desiredStateSatisfied:${binding.desiredFingerprint}:${handle.lineage}',
      );
    }
    // Until the public outcome lookup is composed, do not cross the mutation
    // boundary and then infer a proof from Unchanged or equal hashes.
    final reader = _outcomeReader;
    if (reader == null) {
      return const CloudApplyPending(CloudPendingReason.unknownOutcome);
    }
    if (handle is! _WorkspaceIncoming ||
        !identical(handle.owner, this) ||
        handle.eventKey != item.eventKey ||
        handle.desiredFingerprint != binding.desiredFingerprint ||
        handle.localTargetId != binding.localTargetId ||
        handle.workspaceRequestFingerprint !=
            binding.workspaceRequestFingerprint ||
        handle.localLineageFingerprint != binding.localLineageFingerprint) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    final before = await _capture(cancellation), batch = handle.batch;
    if (_project(before).revision != expected.revision || batch == null) {
      return const CloudApplyPending(CloudPendingReason.needsReconciliation);
    }
    final existingTarget =
        mapping?.localSkillId ??
        (handle.preexistingTarget ? binding.localTargetId : null);
    if (existingTarget != null &&
        (before.snapshot
                    .findSkill(ws.ManagedSkillId(existingTarget))
                    ?.draft
                    ?.isDirty ==
                true ||
            before.snapshot
                    .findSkill(ws.ManagedSkillId(existingTarget))
                    ?.updateCandidate !=
                null)) {
      return const CloudApplyPending(CloudPendingReason.dirtyDraft);
    }
    final ws.IncomingRevisionApplyResult result;
    if (item.change.kind == 'replacement') {
      final command = batch.localCommand;
      if (mapping == null ||
          command == null ||
          command.previousLocalLineageFingerprint !=
              mapping.localLineageFingerprint ||
          before.localLineageFingerprints[ws.ManagedSkillId(
                mapping.localSkillId,
              )] !=
              mapping.localLineageFingerprint ||
          command.previousEffectiveReference == null) {
        return const CloudApplyPending(CloudPendingReason.needsReconciliation);
      }
      result = await _success(
        _repository.replaceIncomingRevision(
          ws.ReplaceIncomingRevisionRequest(
            managedSkillId: ws.ManagedSkillId(mapping.localSkillId),
            expectedIdentity: before.identity,
            expectedRevision: before.snapshot.revision,
            expectedLocalLineageFingerprint: mapping.localLineageFingerprint!,
            expectedEffective: command.previousEffectiveReference!,
            incoming: batch,
          ),
        ),
        cancellation,
      );
    } else if (mapping == null && !handle.preexistingTarget) {
      result = await _success(
        _repository.installIncomingRevision(
          ws.InstallIncomingRevisionRequest(
            expectedIdentity: before.identity,
            expectedRevision: before.snapshot.revision,
            incoming: batch,
          ),
        ),
        cancellation,
      );
    } else {
      final local = await _success(
        _repository.exportCommittedRevision(
          ws.ExportCommittedRevisionRequest(
            managedSkillId: ws.ManagedSkillId(
              mapping?.localSkillId ?? binding.localTargetId!,
            ),
            expectedRevision: before.snapshot.revision,
          ),
        ),
        cancellation,
      );
      result = await _success(
        _repository.applyIncomingRevision(
          ws.ApplyIncomingRevisionRequest(
            managedSkillId: ws.ManagedSkillId(
              mapping?.localSkillId ?? binding.localTargetId!,
            ),
            expectedRevision: before.snapshot.revision,
            expectedIdentity: before.identity,
            expectedEffective: local.currentEffective,
            incoming: batch,
          ),
        ),
        cancellation,
      );
    }
    if (result case ws.IncomingRevisionPending(:final reason)) {
      return CloudApplyPending(switch (reason) {
        ws.IncomingRevisionPendingReason.dirtyDraft =>
          CloudPendingReason.dirtyDraft,
        ws.IncomingRevisionPendingReason.diverged =>
          CloudPendingReason.divergence,
        ws.IncomingRevisionPendingReason.sourceMismatch ||
        ws.IncomingRevisionPendingReason.slotMismatch ||
        ws.IncomingRevisionPendingReason.slotConflict =>
          CloudPendingReason.unsupportedReplacement,
        _ => CloudPendingReason.needsReconciliation,
      });
    }
    return reader(
      repository: _repository,
      scope: _scope,
      item: item,
      binding: binding,
      cancellation: cancellation,
    );
  }

  @override
  Future<CloudApplyResult> resolveOutcome({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  }) => _portGate(
    () => _resolveOutcomeLocked(
      item: item,
      binding: binding,
      scope: scope,
      cancellation: cancellation,
    ),
  );

  Future<CloudApplyResult> _resolveOutcomeLocked({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  }) async => _outcomeReader == null
      ? const CloudApplyPending(CloudPendingReason.unknownOutcome)
      : _outcomeReader(
          repository: _repository,
          scope: scope,
          item: item,
          binding: binding,
          cancellation: cancellation,
        );
  @override
  Future<CloudApplyResult> applyMetadata({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) => _portGate(
    () => _applyMetadataLocked(
      item: item,
      binding: binding,
      handle: handle,
      expected: expected,
      mapping: mapping,
      cancellation: cancellation,
    ),
  );

  Future<CloudApplyResult> _applyMetadataLocked({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) async {
    if (handle is _WorkspaceTagIncoming) {
      return _applyPersonalTag(item, binding, handle, expected, cancellation);
    }
    if (handle is! _WorkspaceStateIncoming ||
        !identical(handle.owner, this) ||
        handle.eventKey != item.eventKey ||
        handle.desiredFingerprint != binding.desiredFingerprint ||
        handle.localTargetId != binding.localTargetId ||
        handle.workspaceRequestFingerprint !=
            binding.workspaceRequestFingerprint ||
        handle.localLineageFingerprint != binding.localLineageFingerprint) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    final before = await _capture(cancellation), patch = handle.patch;
    if (patch == null || _project(before).revision != expected.revision) {
      return const CloudApplyPending(CloudPendingReason.needsReconciliation);
    }
    final result = await _success(
      _repository.applySkillExtraDataPatch(
        ws.ApplySkillExtraDataPatchRequest(
          binding: handle.command,
          expectedRevision: before.snapshot.revision,
          patch: patch,
        ),
      ),
      cancellation,
    );
    if (result case ws.IncomingRevisionPending()) {
      return const CloudApplyPending(
        CloudPendingReason.metadataProofUnavailable,
      );
    }
    return _readPublicWorkspaceOutcome(
      repository: _repository,
      scope: _scope,
      item: item,
      binding: binding,
      cancellation: cancellation,
    );
  }

  @override
  Future<CloudApplyResult> applyLifecycle({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) => _portGate(
    () => _applyLifecycleLocked(
      item: item,
      binding: binding,
      handle: handle,
      expected: expected,
      mapping: mapping,
      cancellation: cancellation,
    ),
  );

  Future<CloudApplyResult> _applyLifecycleLocked({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) async {
    if (handle is! _WorkspaceRemovalIncoming ||
        !identical(handle.owner, this) ||
        handle.eventKey != item.eventKey ||
        handle.localTargetId != binding.localTargetId ||
        handle.localLineageFingerprint != binding.localLineageFingerprint) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    final state = await _readDesiredRemovalOutcome(
      repository: _repository,
      scope: _scope,
      item: item,
      binding: binding,
      cancellation: cancellation,
    );
    if (state is! CloudRetryDesiredRemovalAllowed) return state;
    final before = await _capture(cancellation),
        id = ws.ManagedSkillId(binding.localTargetId!);
    if (before.snapshot.findSkill(id)?.draft?.isDirty == true ||
        before.snapshot.findSkill(id)?.updateCandidate != null) {
      return const CloudApplyPending(CloudPendingReason.dirtyDraft);
    }
    try {
      await _success(
        _repository.remove(
          ws.RemoveRequest(
            managedSkillIds: {id},
            intent: ws.DestructiveIntent(
              reviewedRevision: before.snapshot.revision,
            ),
            expectedIdentity: before.identity,
            requireCleanDraft: true,
            expectedLocalLineageFingerprints: {
              id: binding.localLineageFingerprint!,
            },
          ),
        ),
        cancellation,
      );
    } on CloudException catch (error) {
      if (error.code == CloudErrorCode.dirtyDraftRequired) {
        return const CloudApplyPending(CloudPendingReason.dirtyDraft);
      }
      rethrow;
    }
    return _readDesiredRemovalOutcome(
      repository: _repository,
      scope: _scope,
      item: item,
      binding: binding,
      cancellation: cancellation,
    );
  }
}

final class _WorkspaceInitialLink
    implements CloudInitialExistingIncomingHandle {
  _WorkspaceInitialLink({
    required this.owner,
    required this.eventKey,
    required this.target,
    required this.lineage,
    required this.satisfied,
  });
  final WorkspaceCloudAdapter owner;
  final String eventKey, target, lineage;
  final bool satisfied;
  @override
  bool get preexistingTarget => true;
  @override
  String? get localTargetId => target;
  @override
  String? get localLineageFingerprint => lineage;
  @override
  String? get workspaceRequestFingerprint => null;
  @override
  Future<void> dispose() async {}
}

final class _WorkspaceIncoming implements CloudInitialExistingIncomingHandle {
  _WorkspaceIncoming({
    required this.owner,
    required ws.CommittedRevisionBatch batch,
    required this.desiredFingerprint,
    required this.eventKey,
    this.preexistingTarget = false,
  }) : batch = batch;
  final WorkspaceCloudAdapter owner;
  final String desiredFingerprint, eventKey;
  ws.CommittedRevisionBatch? batch;
  @override
  final bool preexistingTarget;
  @override
  String? get localTargetId => batch?.localCommand?.targetManagedSkillId.value;
  @override
  String? get workspaceRequestFingerprint =>
      batch?.localCommand?.requestFingerprint;
  @override
  String? get localLineageFingerprint =>
      batch?.localCommand?.localLineageFingerprint;
  @override
  Future<void> dispose() async {
    batch = null;
  }

  @override
  String toString() => 'WorkspaceIncoming([redacted])';
}

final class _WorkspaceStateIncoming implements CloudIncomingHandle {
  _WorkspaceStateIncoming({
    required this.owner,
    required this.command,
    required ws.SkillExtraDataPatch patch,
    required this.eventKey,
    required this.desiredFingerprint,
  }) : patch = patch;
  final WorkspaceCloudAdapter owner;
  final ws.IncomingRevisionCommandBinding command;
  final String eventKey, desiredFingerprint;
  ws.SkillExtraDataPatch? patch;
  @override
  String? get localTargetId => command.targetManagedSkillId.value;
  @override
  String? get workspaceRequestFingerprint => command.requestFingerprint;
  @override
  String? get localLineageFingerprint => command.localLineageFingerprint;
  @override
  Future<void> dispose() async {
    patch = null;
  }
}

final class _WorkspaceTagIncoming implements CloudIncomingHandle {
  _WorkspaceTagIncoming({
    required this.owner,
    required this.eventKey,
    required this.command,
    required this.mutation,
  });
  final WorkspaceCloudAdapter owner;
  final String eventKey;
  final ws.PersonalTagCommandBinding command;
  final ws.PersonalTagMutation mutation;
  @override
  String? get localTargetId => command.personalTagId;
  @override
  String? get workspaceRequestFingerprint => command.requestFingerprint;
  @override
  String? get localLineageFingerprint => null;
  @override
  Future<void> dispose() async {}
}

final class _WorkspaceRemovalIncoming implements CloudIncomingHandle {
  _WorkspaceRemovalIncoming({
    required this.owner,
    required this.eventKey,
    required this.target,
    required this.lineage,
  });
  final WorkspaceCloudAdapter owner;
  final String eventKey, target, lineage;
  @override
  String? get localTargetId => target;
  @override
  String? get workspaceRequestFingerprint => null;
  @override
  String? get localLineageFingerprint => lineage;
  @override
  Future<void> dispose() async {}
}
