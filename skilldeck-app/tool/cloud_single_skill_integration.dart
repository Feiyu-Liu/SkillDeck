import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_workspace/skills_workspace.dart' as ws;

import 'package:skills_manager/features/cloud/sync/workspace_cloud_adapter.dart';
import 'package:skills_manager/features/cloud/sync/cloud_sync_session.dart';
import 'package:skills_manager/features/cloud/data/real_cloud_gateway.dart';

// Manual cross-repository qualification, not a production App entrypoint.
// Secrets cross only dedicated inherited pipes; stdout contains safe claims.
final class _MemoryCredentials implements SecureSessionStore {
  SecureSessionRecord? value;
  @override
  Future<SecureSessionRecord?> read() async => value;
  @override
  Future<void> write(SecureSessionRecord record) async {
    value = record;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

final class _LoseMetadataAcknowledgement implements CloudTransport {
  _LoseMetadataAcknowledgement(this.inner);
  final CloudTransport inner;
  bool loseNext = false, loseNextSnapshot = false;
  final snapshotKeys = <String>[];
  @override
  Uri get baseUri => inner.baseUri;
  @override
  Future<CloudResponse> request(
    CloudRequest request, {
    CloudCredential? credential,
    CloudCancellation? cancellation,
  }) async {
    if (request.path == '/v1/sync/snapshots') {
      final key =
          (request.body?['data'] as Map<String, Object?>?)?['requestKey'];
      if (key is String) snapshotKeys.add(key);
    }
    final result = await inner.request(
      request,
      credential: credential,
      cancellation: cancellation,
    );
    if (loseNextSnapshot &&
        request.path == '/v1/sync/snapshots' &&
        result.statusCode == 200) {
      loseNextSnapshot = false;
      throw const CloudException(CloudErrorCode.unavailable);
    }
    if (loseNext &&
        request.path == '/v1/sync/metadata' &&
        result.statusCode == 200) {
      loseNext = false;
      throw const CloudException(CloudErrorCode.unavailable);
    }
    return result;
  }

  @override
  void close() => inner.close();
}

final class _LoseOneApplyAcknowledgement implements CloudWorkspacePort {
  _LoseOneApplyAcknowledgement(this.inner);
  final CloudWorkspacePort inner;
  bool lost = false;
  @override
  Future<CloudWorkspaceCapture> capture() => inner.capture();
  @override
  Future<CloudIncomingHandle> prepareIncoming({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  }) => inner.prepareIncoming(
    item: item,
    binding: binding,
    scope: scope,
    cancellation: cancellation,
  );
  @override
  Future<CloudIncomingHandle> prepareStateChange({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) => inner.prepareStateChange(
    item: item,
    binding: binding,
    scope: scope,
    mapping: mapping,
    cancellation: cancellation,
  );
  @override
  Future<CloudApplyResult> applyIncoming({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) async {
    final result = await inner.applyIncoming(
      item: item,
      binding: binding,
      handle: handle,
      expected: expected,
      mapping: mapping,
      cancellation: cancellation,
    );
    if (!lost && result is CloudApplied) {
      lost = true;
      throw const CloudException(CloudErrorCode.unavailable);
    }
    return result;
  }

  @override
  Future<CloudApplyResult> applyMetadata({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) => inner.applyMetadata(
    item: item,
    binding: binding,
    handle: handle,
    expected: expected,
    mapping: mapping,
    cancellation: cancellation,
  );
  @override
  Future<CloudApplyResult> applyLifecycle({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) => inner.applyLifecycle(
    item: item,
    binding: binding,
    handle: handle,
    expected: expected,
    mapping: mapping,
    cancellation: cancellation,
  );
  @override
  Future<CloudApplyResult> resolveOutcome({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  }) => inner.resolveOutcome(
    item: item,
    binding: binding,
    scope: scope,
    cancellation: cancellation,
  );
}

Future<void> _publish(
  ws.SkillsRepository repository,
  ws.ManagedSkillId id,
  String contents,
) async {
  final draft = await _success(
    repository.ensureDraft(ws.EnsureDraftRequest(managedSkillId: id)),
  );
  await File(path.join(draft.path, 'notes.md')).writeAsString(contents);
  await _success(
    repository.publishDraft(ws.PublishDraftRequest(managedSkillId: id)),
  );
}

Future<T> _success<T>(ws.SkillsOperation<T> operation) async {
  final result = await operation.completed;
  if (result case ws.SkillsSuccess<T>(:final value)) return value;
  throw const CloudException(CloudErrorCode.unavailable);
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return value;
}

String _text(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const CloudException(CloudErrorCode.invalidResponse);
  }
  return value;
}

void _require(bool value) {
  if (!value) throw const CloudException(CloudErrorCode.invalidResponse);
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Controlled integration pipes are required.');
    exitCode = 64;
    return;
  }
  final input = StreamIterator<String>(
    File(arguments[0])
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
  );
  final output = File(arguments[1]).openWrite();
  Directory? temporary;
  ws.SkillsRepository? a, b;
  CloudAuthClient? authA, authB;
  BackgroundSqliteCloudDatabase? dbA, dbB;
  var phase = 'configuration';
  void enter(String value) {
    phase = value;
    output.writeln(jsonEncode({'kind': 'phase', 'phase': value}));
  }

  final claims = <String>[];
  try {
    _require(await input.moveNext());
    final config = _object(jsonDecode(input.current));
    final base = Uri.parse(_text(config['baseURL'])),
        httpsGit = Uri.parse(_text(config['httpsGitOrigin'])),
        loopback = Uri.parse(_text(config['loopbackGitOrigin']));
    final prefix = _text(config['gitPathPrefix']);
    _require(
      base.scheme == 'https' &&
          base.host == '127.0.0.1' &&
          base.hasPort &&
          httpsGit.origin == base.origin &&
          loopback.scheme == 'http' &&
          loopback.host == '127.0.0.1' &&
          loopback.hasPort &&
          loopback.port >= 1024 &&
          prefix == '/git/',
    );
    final ca = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(_text(config['caCertificatePath']));
    Future<void> launch(Uri uri) async {
      output.writeln(jsonEncode({'kind': 'launch', 'uri': uri.toString()}));
      await output.flush();
    }

    final credentialsA = _MemoryCredentials(),
        credentialsB = _MemoryCredentials();
    final transports = <_MemoryCredentials, _LoseMetadataAcknowledgement>{};
    CloudAuthClient createAuth(_MemoryCredentials store) => CloudAuthClient(
      transport: transports[store] = _LoseMetadataAcknowledgement(
        HttpsCloudTransport(
          baseUri: base,
          securityContext: ca,
          maximumRequestBytes: 512 * 1024,
        ),
      ),
      secureStore: store,
      launchBrowser: launch,
    );
    authA = createAuth(credentialsA);
    authB = createAuth(credentialsB);
    enter('actualEmailOTPAndLoopback');
    await authA.signIn(deviceName: 'Synthetic Workspace A', platform: 'macos');
    await authB.signIn(deviceName: 'Synthetic Workspace B', platform: 'macos');
    _require(
      authA.currentSession!.accountId == authB.currentSession!.accountId &&
          authA.currentSession!.deviceId != authB.currentSession!.deviceId,
    );
    claims.add(
      'Actual OTP authentication, loopback/S256 exchange and independent device sessions',
    );
    temporary = await Directory.systemTemp.createTemp(
      'skilldeck-cross-repo-integration-',
    );
    ws.SkillsRepository create(String name) => ws.createSkillsRepository(
      ws.SkillsRepositoryConfiguration(
        rootPath: path.join(temporary!.path, name),
        agentHomePath: path.join(temporary.path, 'agent-home'),
      ),
    );
    a = create('workspace-a');
    b = create('workspace-b');
    await _success(a.open());
    await _success(b.open());
    enter('seedIncomingInstall');
    final seed = _object(config['seedSource']),
        seedManifest = CloudContentManifest.fromJson(
          _object(seed['contentManifest']),
        );
    final seedRemote = Uri.parse(_text(seed['remote']));
    _require(
      seedRemote.origin == loopback.origin &&
          seedRemote.path.startsWith(prefix),
    );
    final captureA = await _success(
      a.captureAuthoritativeState(const ws.CaptureAuthoritativeStateRequest()),
    );
    final seeded = await _success(
      a.fetchIncomingRevision(
        ws.FetchIncomingRevisionRequest(
          expectedIdentity: captureA.identity,
          expectedRevision: captureA.snapshot.revision,
          contentManifest: utf8.encode(jsonEncode(seedManifest.toJson())),
          remote: ws.RevisionTransferRemote.loopbackForTesting(
            url: seedRemote.toString(),
            ephemeralHeaders: () async => [
              'Authorization: Bearer ${_text(seed['readToken'])}',
            ],
          ),
        ),
      ),
    );
    final seededResult = await _success(
      a.installIncomingRevision(
        ws.InstallIncomingRevisionRequest(
          expectedIdentity: captureA.identity,
          expectedRevision: a.snapshot.revision,
          incoming: seeded,
        ),
      ),
    );
    _require(seededResult is ws.IncomingRevisionInstalled);
    final aId = (seededResult as ws.IncomingRevisionInstalled).managedSkillId;
    enter('realLocalPublish');
    final draft = await _success(
      a.ensureDraft(ws.EnsureDraftRequest(managedSkillId: aId)),
    );
    await File(path.join(draft.path, 'notes.md'))
        .writeAsString('Published from synthetic Workspace A.\n');
    await _success(a.publishDraft(ws.PublishDraftRequest(managedSkillId: aId)));
    final parallelSeed = _object(config['parallelSource']);
    final parallelRemote = Uri.parse(_text(parallelSeed['remote']));
    _require(
      parallelRemote.origin == loopback.origin &&
          parallelRemote.path.startsWith(prefix),
    );
    final beforeParallel = await _success(
      a.captureAuthoritativeState(const ws.CaptureAuthoritativeStateRequest()),
    );
    final parallelBatch = await _success(
      a.fetchIncomingRevision(
        ws.FetchIncomingRevisionRequest(
          expectedIdentity: beforeParallel.identity,
          expectedRevision: beforeParallel.snapshot.revision,
          contentManifest: utf8.encode(
            jsonEncode(parallelSeed['contentManifest']),
          ),
          remote: ws.RevisionTransferRemote.loopbackForTesting(
            url: parallelRemote.toString(),
            ephemeralHeaders: () async => [
              'Authorization: Bearer ${_text(parallelSeed['readToken'])}',
            ],
          ),
        ),
      ),
    );
    final parallelInstall = await _success(
      a.installIncomingRevision(
        ws.InstallIncomingRevisionRequest(
          expectedIdentity: beforeParallel.identity,
          expectedRevision: a.snapshot.revision,
          incoming: parallelBatch,
        ),
      ),
    );
    _require(parallelInstall is ws.IncomingRevisionInstalled);
    final otherAId =
        (parallelInstall as ws.IncomingRevisionInstalled).managedSkillId;
    final capturedA = await _success(
      a.captureAuthoritativeState(const ws.CaptureAuthoritativeStateRequest()),
    );
    final capturedB = await _success(
      b.captureAuthoritativeState(const ws.CaptureAuthoritativeStateRequest()),
    );
    CloudSyncScope syncScope(
      CloudSession session,
      ws.AuthoritativeWorkspaceCapture capture,
    ) => CloudSyncScope(
      accountId: session.accountId,
      deviceId: session.deviceId,
      workspaceIdentity: CloudWorkspaceIdentity(
        workspaceId: capture.identity.workspaceId,
        recoveryIncarnation: capture.identity.recoveryIncarnation,
      ),
    );
    final scopeA = syncScope(authA.currentSession!, capturedA),
        scopeB = syncScope(authB.currentSession!, capturedB);
    dbA = await BackgroundSqliteCloudDatabase.open(
      path: path.join(temporary.path, 'cloud-a.sqlite'),
      serviceOrigin: base,
    );
    dbB = await BackgroundSqliteCloudDatabase.open(
      path: path.join(temporary.path, 'cloud-b.sqlite'),
      serviceOrigin: base,
    );
    await dbA.initializeNewDeviceScope(authA.currentSession!);
    await dbB.initializeNewDeviceScope(authB.currentSession!);
    var apiA = CloudSyncClient(
      auth: authA,
      intents: dbA.forWorkspace(scopeA.workspaceIdentity.workspaceId),
    );
    var apiB = CloudSyncClient(
      auth: authB,
      intents: dbB.forWorkspace(scopeB.workspaceIdentity.workspaceId),
    );
    ws.RevisionTransferRemote mapped(CloudTransferLease lease) {
      _require(
        lease.remote.origin == httpsGit.origin &&
            lease.remote.path.startsWith(prefix) &&
            lease.remote.userInfo.isEmpty &&
            !lease.remote.hasQuery &&
            !lease.remote.hasFragment,
      );
      final remote = loopback.replace(path: lease.remote.path);
      return ws.RevisionTransferRemote.loopbackForTesting(
        url: remote.toString(),
        ephemeralHeaders: lease.authorizationHeaders,
      );
    }

    var adapterA = WorkspaceCloudAdapter.withTestRemoteFactory(
      repository: a,
      scope: scopeA,
      api: apiA,
      remoteFactory: mapped,
    );
    final batch = await adapterA.exportSelected(aId.value, CloudCancellation());
    claims.add(
      'Public incoming install and real local Draft Publish produce a verified native export with HTTPS provenance',
    );
    enter('manualAppPublisherWithLocalExtraData');
    final localAssigned = await _success(
      a.createPersonalTag(
        ws.CreatePersonalTagRequest(
          name: 'Assigned vocabulary',
          color: '#11AABB',
        ),
      ),
    );
    await _success(
      a.createPersonalTag(
        ws.CreatePersonalTagRequest(name: 'Unassigned vocabulary'),
      ),
    );
    await _success(
      a.setFavorite(
        ws.SetFavoriteRequest(managedSkillId: aId, isFavorite: true),
      ),
    );
    await _success(
      a.saveNote(
        ws.SaveNoteRequest(managedSkillId: aId, text: 'Bootstrap note'),
      ),
    );
    await _success(
      a.assignPersonalTag(
        ws.AssignPersonalTagRequest(
          managedSkillId: aId,
          tagId: localAssigned.id,
        ),
      ),
    );
    final beforeManual = a.snapshot.revision;
    late AppCloudSyncSession appSync;
    late RealAppCloudGateway appGateway;
    void composePublisher() {
      appSync = AppCloudSyncSession(
        auth: authA!,
        database: dbA!,
        repository: a!,
        canMutate: () async => true,
        testRemoteFactory: mapped,
      );
      appGateway = RealAppCloudGateway(
        auth: authA,
        database: dbA,
        deviceName: 'Synthetic Workspace A',
        platform: 'macos',
        syncFactory: (auth, database) => appSync,
      );
    }

    composePublisher();
    await appGateway.enableSyncChoices([
      AppCloudSkillChoice(
        id: aId.value,
        name: 'Primary Skill',
        kind: AppCloudChoiceKind.local,
      ),
      AppCloudSkillChoice(
        id: otherAId.value,
        name: 'Independent Skill',
        kind: AppCloudChoiceKind.local,
      ),
    ]);
    _require(
      (await dbA.syncStore.outboundTask(
                scopeA,
                'content',
                aId.value,
              ))?.acknowledged ==
              true &&
          (await dbA.syncStore.outboundTask(
                scopeA,
                'content',
                otherAId.value,
              ))?.acknowledged ==
              true,
    );
    final manual = await appGateway.syncNow();
    _require(manual.pendingCount == 0 && a.snapshot.revision == beforeManual);
    final contentTask = (await dbA.syncStore.outboundTask(
      scopeA,
      'content',
      aId.value,
    ))!;
    final receipt = CloudCommitReceipt.fromJson(
      await apiA.operationStatus(contentTask.operationId),
    );
    final otherTask = (await dbA.syncStore.outboundTask(
      scopeA,
      'content',
      otherAId.value,
    ))!;
    final otherReceipt = CloudCommitReceipt.fromJson(
      await apiA.operationStatus(otherTask.operationId),
    );
    final localBaseline = (await dbA.syncStore.publisherBaseline(
      scopeA,
      aId.value,
    ))!;
    _require(
      localBaseline.favorite &&
          localBaseline.note == 'Bootstrap note' &&
          localBaseline.localTagIds.contains(localAssigned.id),
    );
    _require((await dbA.syncStore.personalTagMappings(scopeA)).length == 2);
    claims.add(
      'Actual App manual publisher exports/pushes/commits public Workspace content, Favorite, Note, assigned and unassigned vocabulary; self pull has no pending work or extra Workspace revision',
    );
    Future<Map<String, Object?>> remoteMetadata(Map<String, Object?> data) =>
        apiA.sendMutation(
          apiA.createIntent(
            operationId: randomCloudToken(),
            path: '/v1/sync/metadata',
            data: data,
          ),
        );
    enter('durableSelectedBootstrap');
    await dbB.syncStore.initializeOptInScope(
      scope: scopeB,
      capture: CloudWorkspaceCapture(
        identity: scopeB.workspaceIdentity,
        revision: capturedB.snapshot.revision.value.toString(),
        recoveryComplete: capturedB.recoveryComplete,
        finalizationComplete: capturedB.finalizationComplete,
        isComplete: capturedB.isComplete,
      ),
      selection: CloudSyncSelection(
        cloudLineageIds: {receipt.lineageId, otherReceipt.lineageId},
      ),
      initialCursor: CloudSequence.parse('0'),
    );
    var adapterB = WorkspaceCloudAdapter.withTestRemoteFactory(
      repository: b,
      scope: scopeB,
      api: apiB,
      remoteFactory: mapped,
      boundedNetworkFetchQualified: true,
      syncStore: dbB.syncStore,
    );
    var coordinator = CloudSyncCoordinator(
      scope: scopeB,
      auth: authB,
      api: apiB,
      store: dbB.syncStore,
      workspace: adapterB,
    );
    transports[credentialsB]!.loseNextSnapshot = true;
    var lostSnapshot = false;
    try {
      await coordinator.pullSnapshotPage();
    } on CloudException {
      lostSnapshot = true;
    }
    _require(lostSnapshot && !transports[credentialsB]!.loseNextSnapshot);
    final pendingSnapshotKey = await dbB.syncStore.ensureSnapshotRequestKey(
      scopeB,
    );
    await dbB.close();
    dbB = await BackgroundSqliteCloudDatabase.open(
      path: path.join(temporary.path, 'cloud-b.sqlite'),
      serviceOrigin: base,
    );
    apiB = CloudSyncClient(
      auth: authB,
      intents: dbB.forWorkspace(scopeB.workspaceIdentity.workspaceId),
    );
    final initialInspector = adapterB;
    var editedBeforeFirstMetadata = false;
    adapterB = WorkspaceCloudAdapter.withTestRemoteFactory(
      repository: b,
      scope: scopeB,
      api: apiB,
      remoteFactory: mapped,
      boundedNetworkFetchQualified: true,
      syncStore: dbB.syncStore,
      outcomeReader:
          ({
            required repository,
            required scope,
            required item,
            required binding,
            required cancellation,
          }) async {
            final result = await initialInspector.resolveOutcome(
              item: item,
              binding: binding,
              scope: scope,
              cancellation: cancellation,
            );
            if (!editedBeforeFirstMetadata &&
                item.change.lineageId == receipt.lineageId &&
                result is CloudApplied) {
              editedBeforeFirstMetadata = true;
              await _success(
                repository.saveNote(
                  ws.SaveNoteRequest(
                    managedSkillId: ws.ManagedSkillId(result.localSkillId),
                    text: 'Unsent edit before first metadata',
                  ),
                ),
              );
              await _success(
                repository.setFavorite(
                  ws.SetFavoriteRequest(
                    managedSkillId: ws.ManagedSkillId(result.localSkillId),
                    isFavorite: true,
                  ),
                ),
              );
              await _success(
                repository.setFavorite(
                  ws.SetFavoriteRequest(
                    managedSkillId: ws.ManagedSkillId(result.localSkillId),
                    isFavorite: false,
                  ),
                ),
              );
            }
            return result;
          },
    );
    coordinator = CloudSyncCoordinator(
      scope: scopeB,
      auth: authB,
      api: apiB,
      store: dbB.syncStore,
      workspace: adapterB,
    );
    var snapshotProgress = await coordinator.pullSnapshotPage();
    while (snapshotProgress.snapshotCursor != null) {
      snapshotProgress = await coordinator.pullSnapshotPage();
    }
    final requestedKeys = transports[credentialsB]!.snapshotKeys;
    _require(
      requestedKeys.length == 2 &&
          requestedKeys.every((key) => key == pendingSnapshotKey),
    );
    claims.add(
      'With one active snapshot allowed, an actual successful create whose response is lost survives Cloud DB reopen and reuses its durable request key/frozen snapshot, then releases only after whole-page persistence',
    );
    final item = (await dbB.syncStore.pendingItems(scopeB)).singleWhere(
      (item) =>
          item.change.lineageId == receipt.lineageId &&
          item.change.kind == 'revision',
    );
    final incoming = CloudLineage.fromJson(item.change.payload);
    _require(
      incoming.contentManifest != null &&
          incoming.contentStatus == CloudContentStatus.ready,
    );
    enter('nativeGitDownloadAndCallerProofApply');
    final firstMetadataWindow = await coordinator.applyPending();
    final guardedMapping = (await dbB.syncStore.mapping(
      scopeB,
      receipt.lineageId,
    ))!;
    final guardedId = ws.ManagedSkillId(guardedMapping.localSkillId);
    _require(
      editedBeforeFirstMetadata &&
          firstMetadataWindow.pendingCount == 2 &&
          b.snapshot.findSkill(guardedId)!.note?.text ==
              'Unsent edit before first metadata' &&
          !b.snapshot.findSkill(guardedId)!.favorite.isFavorite,
    );
    await _success(
      b.saveNote(
        ws.SaveNoteRequest(managedSkillId: guardedId, text: 'Bootstrap note'),
      ),
    );
    await _success(
      b.setFavorite(
        ws.SetFavoriteRequest(managedSkillId: guardedId, isFavorite: true),
      ),
    );
    final applied = await coordinator.applyPending();
    claims.add(
      'A real local Note/Favorite edit between new-install proof and first snapshot fields remains intact with unknown metadata baseline; explicit local acceptance of desired values then permits exact native no-op proof and remaining assignment',
    );
    output.writeln(
      jsonEncode({
        'kind': 'diagnostic',
        'phase': phase,
        'pending': (await dbB.syncStore.pendingItems(scopeB))
            .map(
              (item) => {
                'kind': item.change.kind,
                'reason': item.pendingReason?.name,
              },
            )
            .toList(),
        'received': applied.received.toJson(),
        'applied': applied.applied.toJson(),
      }),
    );
    await output.flush();

    _require(
      applied.pendingCount == 0 &&
          applied.applied == snapshotProgress.snapshotHighWatermark,
    );
    final mapping = await dbB.syncStore.mapping(scopeB, receipt.lineageId);
    _require(mapping != null && !mapping.retired);
    final bId = ws.ManagedSkillId(mapping!.localSkillId);
    final otherMapping = (await dbB.syncStore.mapping(
      scopeB,
      otherReceipt.lineageId,
    ))!;
    final otherBId = ws.ManagedSkillId(otherMapping.localSkillId);
    final bootstrapped = b.snapshot.findSkill(bId)!;
    _require(
      bootstrapped.favorite.isFavorite &&
          bootstrapped.note?.text == 'Bootstrap note' &&
          bootstrapped.personalTagIds.length == 1 &&
          b.snapshot.personalTags.any(
            (tag) => tag.name == 'Unassigned vocabulary',
          ),
    );
    claims.add(
      'Nonempty bootstrap stages content, fields, assignments and unassigned global vocabulary as independent durable steps before advancing H',
    );

    final mirror = await _success(
      b.exportCommittedRevision(
        ws.ExportCommittedRevisionRequest(
          managedSkillId: bId,
          expectedRevision: b.snapshot.revision,
        ),
      ),
    );
    _require(
      mirror.contentHash == batch.contentHash &&
          mirror.currentEffective == batch.currentEffective &&
          mirror.currentUpstream == batch.currentUpstream &&
          mirror.publishedHistory.length == batch.publishedHistory.length,
    );
    final notes = await _success(
      b.readEffectiveFile(
        ws.ReadEffectiveFileRequest(
          managedSkillId: bId,
          expectedContentHash: mirror.contentHash,
          relativePath: 'notes.md',
        ),
      ),
    );
    _require(
      utf8.decode(notes.bytes) == 'Published from synthetic Workspace A.\n',
    );
    _require(b.snapshot.findSkill(bId)!.draft == null);
    claims.add(
      'Explicit selected-lineage snapshot, native Git fetch/install, real caller-outcome proof and atomic Cloud applied cursor mirror exact roots/history/content in empty Workspace B',
    );
    enter('freshExactInitialLinkThroughAppGateway');
    final c = create('workspace-c');
    try {
      await _success(c.open());
      final emptyC = await _success(
        c.captureAuthoritativeState(
          const ws.CaptureAuthoritativeStateRequest(),
        ),
      );
      final leaseC = await apiB.lineageTransfer(
        operationId: randomCloudToken(),
        lineageId: receipt.lineageId,
        generation: receipt.generation,
        access: CloudTransferAccess.read,
      );
      final batchC = await _success(
        c.fetchIncomingRevision(
          ws.FetchIncomingRevisionRequest(
            expectedIdentity: emptyC.identity,
            expectedRevision: emptyC.snapshot.revision,
            contentManifest: utf8.encode(
              jsonEncode(receipt.contentManifest.toJson()),
            ),
            remote: mapped(leaseC),
          ),
        ),
      );
      leaseC.invalidate();
      final installC = await _success(
        c.installIncomingRevision(
          ws.InstallIncomingRevisionRequest(
            expectedIdentity: emptyC.identity,
            expectedRevision: c.snapshot.revision,
            incoming: batchC,
          ),
        ),
      );
      _require(installC is ws.IncomingRevisionInstalled);
      final originalC =
          (installC as ws.IncomingRevisionInstalled).managedSkillId;
      await _success(
        c.saveNote(
          ws.SaveNoteRequest(
            managedSkillId: originalC,
            text: 'Unsynced local note',
          ),
        ),
      );
      final conflictingLocalTag = await _success(
        c.createPersonalTag(
          ws.CreatePersonalTagRequest(
            name: 'Unassigned vocabulary',
            color: '#AA0000',
          ),
        ),
      );
      final beforeLink = c.snapshot.revision.value;
      final sessionC = AppCloudSyncSession(
        auth: authB,
        database: dbB,
        repository: c,
        canMutate: () async => true,
        testRemoteFactory: mapped,
      );
      final gatewayC = RealAppCloudGateway(
        auth: authB,
        database: dbB,
        deviceName: 'Synthetic link C',
        platform: 'macos',
        syncFactory: (auth, database) => sessionC,
      );
      final choicesC = await gatewayC.syncOverview();
      final localChoice = choicesC.choices.singleWhere(
        (value) => value.kind == AppCloudChoiceKind.local,
      );
      _require(!localChoice.conflict && localChoice.supported);
      await gatewayC.enableSyncChoice(localChoice);
      final linked = await gatewayC.syncNow();
      final captureC = await _success(
        c.captureAuthoritativeState(
          const ws.CaptureAuthoritativeStateRequest(),
        ),
      );
      final scopeC = syncScope(authB.currentSession!, captureC);
      final mapC = await dbB.syncStore.mapping(scopeC, receipt.lineageId);
      _require(
        linked.pendingCount == 3 &&
            linked.pendingReasons.contains(
              CloudPendingReason.metadataConflict,
            ) &&
            c.snapshot.findSkill(originalC)!.note?.text ==
                'Unsynced local note' &&
            mapC!.localSkillId == originalC.value &&
            c.snapshot.managedSkills.length == 1 &&
            c.snapshot.revision.value == beforeLink + 1 &&
            c.snapshot.personalTags.length == 2 &&
            c.snapshot.findPersonalTag(conflictingLocalTag.id)!.color ==
                '#AA0000',
      );
      var cloudCheck = await apiB.createSnapshot(
        requestKey: randomCloudToken(),
      );
      final cloudTags = [...cloudCheck.personalTags];
      final cloudItems = [...cloudCheck.items];
      while (!cloudCheck.complete) {
        cloudCheck = await apiB.snapshotPage(
          snapshotId: cloudCheck.snapshotId,
          pageCursor: cloudCheck.nextPageCursor!,
          highWatermark: cloudCheck.highWatermark,
        );
        cloudTags.addAll(cloudCheck.personalTags);
        cloudItems.addAll(cloudCheck.items);
      }
      await apiB.releaseSnapshot(cloudCheck.snapshotId);
      _require(
        cloudTags.length == 2 &&
            cloudItems
                    .singleWhere((item) => item.lineageId == receipt.lineageId)
                    .metadata['note'] ==
                'Bootstrap note',
      );
      await gatewayC.stopSync();
      await sessionC.close();
      claims.add(
        'Real AppGateway fresh local choice links exact source/slot/hash/upstream/effective/history into the existing Cloud lineage without another content mutation or duplicate Skill; differing unsynced local Note/Favorite/assignments remain pending and preserved while independent vocabulary applies and same-name/different-color tag conflict creates no duplicate or merge',
      );
    } finally {
      await _success(c.close());
    }
    enter('independentInitialHistoryUnionAndNextRealPublish');
    final d = create('workspace-independent-d');
    try {
      await _success(d.open());
      final emptyD = await _success(
        d.captureAuthoritativeState(
          const ws.CaptureAuthoritativeStateRequest(),
        ),
      );
      final independentWire = {..._object(parallelSeed['contentManifest'])};
      final originalEvents =
          (independentWire['publishedHistory']! as List<Object?>)
              .cast<Map<String, Object?>>();
      independentWire['publishedHistory'] = [
        {
          ...originalEvents.single,
          'eventFingerprint': sha256
              .convert(
                utf8.encode('Controlled independent source installation D'),
              )
              .toString(),
        },
      ];
      final initialD = await _success(
        d.fetchIncomingRevision(
          ws.FetchIncomingRevisionRequest(
            expectedIdentity: emptyD.identity,
            expectedRevision: emptyD.snapshot.revision,
            contentManifest: utf8.encode(jsonEncode(independentWire)),
            remote: ws.RevisionTransferRemote.loopbackForTesting(
              url: parallelRemote.toString(),
              ephemeralHeaders: () async => [
                'Authorization: Bearer ${_text(parallelSeed['readToken'])}',
              ],
            ),
          ),
        ),
      );
      final installedD = await _success(
        d.installIncomingRevision(
          ws.InstallIncomingRevisionRequest(
            expectedIdentity: emptyD.identity,
            expectedRevision: d.snapshot.revision,
            incoming: initialD,
          ),
        ),
      );
      final dId = (installedD as ws.IncomingRevisionInstalled).managedSkillId;
      final sessionD = AppCloudSyncSession(
        auth: authB,
        database: dbB,
        repository: d,
        canMutate: () async => true,
        testRemoteFactory: mapped,
      );
      final gatewayD = RealAppCloudGateway(
        auth: authB,
        database: dbB,
        deviceName: 'Independent fixture D',
        platform: 'macos',
        syncFactory: (auth, database) => sessionD,
      );
      await gatewayD.enableSyncChoices([
        AppCloudSkillChoice(
          id: dId.value,
          name: 'Independent initial history',
          kind: AppCloudChoiceKind.local,
        ),
      ]);
      final linkedD = await gatewayD.syncNow();
      final union = await _success(
        d.exportCommittedRevision(
          ws.ExportCommittedRevisionRequest(
            managedSkillId: dId,
            expectedRevision: d.snapshot.revision,
          ),
        ),
      );
      _require(
        linkedD.pendingCount == 0 &&
            d.snapshot.managedSkills.length == 1 &&
            union.publishedHistory.length == 2,
      );
      await _publish(
        d,
        dId,
        'Real Publish after independent-install history union.\n',
      );
      final publishedD = await gatewayD.syncNow();
      final captureD = await _success(
        d.captureAuthoritativeState(
          const ws.CaptureAuthoritativeStateRequest(),
        ),
      );
      final scopeD = syncScope(authB.currentSession!, captureD);
      final taskD = (await dbB.syncStore.outboundTask(
        scopeD,
        'content',
        dId.value,
      ))!;
      final receiptD = CloudCommitReceipt.fromJson(
        await apiB.operationStatus(taskD.operationId),
      );
      _require(
        publishedD.pendingCount == 0 &&
            receiptD.lineageId == otherReceipt.lineageId &&
            receiptD.contentManifest.publishedHistory.length == 3,
      );
      await gatewayD.stopSync();
      await sessionD.close();
      await coordinator.pullChanges();
      while ((await dbB.syncStore.progress(scopeB)).traversalHighWatermark !=
          null) {
        await coordinator.pullChanges();
      }
      _require((await coordinator.applyPending()).pendingCount == 0);
      claims.add(
        'Controlled public incoming fixtures independently install identical source/slot/hash/roots with distinct installation events; fresh link performs real native history union on the same ID, and a subsequent real Draft Publish is accepted by the service with all three history events',
      );
    } finally {
      await _success(d.close());
    }
    enter('manualPublisherLostAckAndLaterLocalNote');
    await _success(
      a.saveNote(
        ws.SaveNoteRequest(
          managedSkillId: aId,
          text: 'Sent before lost acknowledgement',
        ),
      ),
    );
    transports[credentialsA]!.loseNext = true;
    var lostMetadata = false;
    try {
      await appGateway.syncNow();
    } on CloudException {
      lostMetadata = true;
    }
    _require(lostMetadata && !transports[credentialsA]!.loseNext);
    final pendingFields = (await dbA.syncStore.outboundTask(
      scopeA,
      'fields',
      aId.value,
    ))!;
    _require(!pendingFields.acknowledged);
    await _success(
      a.saveNote(
        ws.SaveNoteRequest(
          managedSkillId: aId,
          text: 'New local note after lost acknowledgement',
        ),
      ),
    );
    await appGateway.close();
    authA = createAuth(credentialsA);
    await authA.restore();
    dbA = await BackgroundSqliteCloudDatabase.open(
      path: path.join(temporary.path, 'cloud-a.sqlite'),
      serviceOrigin: base,
    );
    _require(await dbA.hasDeviceScope(authA.currentSession!));
    apiA = CloudSyncClient(
      auth: authA,
      intents: dbA.forWorkspace(scopeA.workspaceIdentity.workspaceId),
    );
    composePublisher();
    final beforeRecovery = a.snapshot.revision;
    final recoveredManual = await appGateway.syncNow();
    final latestFields = (await dbA.syncStore.outboundTask(
      scopeA,
      'fields',
      aId.value,
    ))!;
    _require(
      recoveredManual.pendingCount == 0 &&
          latestFields.acknowledged &&
          latestFields.operationId != pendingFields.operationId &&
          a.snapshot.revision == beforeRecovery &&
          a.snapshot.findSkill(aId)!.note?.text ==
              'New local note after lost acknowledgement' &&
          (await dbA.syncStore.publisherBaseline(scopeA, aId.value))!.note ==
              'New local note after lost acknowledgement',
    );
    claims.add(
      'Actual committed HTTP metadata acknowledgement loss survives AppGateway shutdown and durable scope/session restore, replays original stable operation before pull, preserves newer local Note, emits a distinct next operation, and self echo performs zero local mutations',
    );
    enter('secondPublishFastForwardAndLostAcknowledgement');
    await _publish(a, aId, 'Second published history from Workspace A.\n');
    final secondBatch = await adapterA.exportSelected(
      aId.value,
      CloudCancellation(),
    );
    await appGateway.syncNow();
    final secondTask = (await dbA.syncStore.outboundTask(
      scopeA,
      'content',
      aId.value,
    ))!;
    final secondReceipt = CloudCommitReceipt.fromJson(
      await apiA.operationStatus(secondTask.operationId),
    );
    await coordinator.pullChanges();
    final dropped = _LoseOneApplyAcknowledgement(adapterB);
    coordinator = CloudSyncCoordinator(
      scope: scopeB,
      auth: authB,
      api: apiB,
      store: dbB.syncStore,
      workspace: dropped,
    );
    final missingAck = await coordinator.applyPending();
    _require(
      dropped.lost &&
          missingAck.applied != secondReceipt.sequence &&
          (await dbB.syncStore.pendingItems(scopeB)).single.pendingReason ==
              CloudPendingReason.unknownOutcome,
    );
    final committedRevisionB = b.snapshot.revision;
    enter('reopenBothWorkspacesAndCloudDatabases');
    await appGateway.close();
    await dbA.close();
    await dbB.close();
    await _success(a.close());
    await _success(b.close());
    await authA.close();
    await authB.close();
    a = create('workspace-a');
    b = create('workspace-b');
    await _success(a.open());
    await _success(b.open());
    authA = createAuth(credentialsA);
    authB = createAuth(credentialsB);
    await authA.restore();
    await authB.restore();
    _require(
      authA.currentSession!.deviceId == scopeA.deviceId &&
          authB.currentSession!.deviceId == scopeB.deviceId,
    );
    dbA = await BackgroundSqliteCloudDatabase.open(
      path: path.join(temporary.path, 'cloud-a.sqlite'),
      serviceOrigin: base,
    );
    dbB = await BackgroundSqliteCloudDatabase.open(
      path: path.join(temporary.path, 'cloud-b.sqlite'),
      serviceOrigin: base,
    );
    apiA = CloudSyncClient(
      auth: authA,
      intents: dbA.forWorkspace(scopeA.workspaceIdentity.workspaceId),
    );
    apiB = CloudSyncClient(
      auth: authB,
      intents: dbB.forWorkspace(scopeB.workspaceIdentity.workspaceId),
    );
    composePublisher();
    adapterA = WorkspaceCloudAdapter.withTestRemoteFactory(
      repository: a,
      scope: scopeA,
      api: apiA,
      remoteFactory: mapped,
    );
    adapterB = WorkspaceCloudAdapter.withTestRemoteFactory(
      repository: b,
      scope: scopeB,
      api: apiB,
      remoteFactory: mapped,
      boundedNetworkFetchQualified: true,
      syncStore: dbB.syncStore,
    );
    coordinator = CloudSyncCoordinator(
      scope: scopeB,
      auth: authB,
      api: apiB,
      store: dbB.syncStore,
      workspace: adapterB,
    );
    final recovered = await coordinator.applyPending();
    _require(
      recovered.applied == secondReceipt.sequence &&
          recovered.pendingCount == 0 &&
          b.snapshot.revision == committedRevisionB,
    );
    final secondMirror = await _success(
      b.exportCommittedRevision(
        ws.ExportCommittedRevisionRequest(
          managedSkillId: bId,
          expectedRevision: b.snapshot.revision,
        ),
      ),
    );
    _require(
      secondMirror.currentEffective == secondBatch.currentEffective &&
          secondMirror.currentUpstream == secondBatch.currentUpstream &&
          secondMirror.publishedHistory.length ==
              secondBatch.publishedHistory.length,
    );
    claims.add(
      'Second Publish fast-forwards the same B Skill; real native commit acknowledgement loss survives both Workspace/Cloud DB/session reopen and resolves exact caller proof without another mutation',
    );
    enter('atomicMetadataPatchViaRealWorkspaceProof');
    final metadataIntent = apiA.createIntent(
      operationId: randomCloudToken(),
      path: '/v1/sync/metadata',
      data: {
        'kind': 'fields',
        'lineageId': receipt.lineageId,
        'generation': receipt.generation,
        'patch': {'favorite': true, 'note': 'Atomic Cloud note'},
      },
    );
    await apiA.sendMutation(metadataIntent);
    await coordinator.pullChanges();
    final metadataApplied = await coordinator.applyPending();
    _require(
      metadataApplied.pendingCount == 0 &&
          b.snapshot.findSkill(bId)!.favorite.isFavorite &&
          b.snapshot.findSkill(bId)!.note?.text == 'Atomic Cloud note',
    );
    await apiA.sendMutation(
      apiA.createIntent(
        operationId: randomCloudToken(),
        path: '/v1/sync/metadata',
        data: {
          'kind': 'fields',
          'lineageId': receipt.lineageId,
          'generation': receipt.generation,
          'patch': {'favorite': null, 'note': ''},
        },
      ),
    );
    await coordinator.pullChanges();
    await coordinator.applyPending();
    _require(
      !b.snapshot.findSkill(bId)!.favorite.isFavorite &&
          b.snapshot.findSkill(bId)!.note == null,
    );
    claims.add(
      'Favorite and Note apply atomically through reserved public Workspace commands and exact proofs, including explicit null/empty clears',
    );
    enter('unsentLocalMetadataPublicationOrderProtection');
    await _success(
      b.saveNote(
        ws.SaveNoteRequest(managedSkillId: bId, text: 'Same desired Note'),
      ),
    );
    await remoteMetadata({
      'kind': 'fields',
      'lineageId': receipt.lineageId,
      'generation': receipt.generation,
      'patch': {'note': 'Same desired Note'},
    });
    await coordinator.pullChanges();
    final beforeNoop = b.snapshot.revision;
    _require(
      (await coordinator.applyPending()).pendingCount == 0 &&
          b.snapshot.revision == beforeNoop,
    );
    await _success(
      b.saveNote(
        ws.SaveNoteRequest(managedSkillId: bId, text: 'Offline unsent Note'),
      ),
    );
    await remoteMetadata({
      'kind': 'fields',
      'lineageId': receipt.lineageId,
      'generation': receipt.generation,
      'patch': {'note': 'Different accepted remote Note', 'favorite': true},
    });
    await remoteMetadata({
      'kind': 'fields',
      'lineageId': otherReceipt.lineageId,
      'generation': otherReceipt.generation,
      'patch': {'note': 'Independent accepted Note', 'favorite': true},
    });
    await coordinator.pullChanges();
    while ((await dbB.syncStore.progress(scopeB)).traversalHighWatermark !=
        null) {
      await coordinator.pullChanges();
    }
    final conflict = await coordinator.applyPending();
    _require(
      conflict.pendingCount == 1 &&
          b.snapshot.findSkill(bId)!.note?.text == 'Offline unsent Note' &&
          b.snapshot.findSkill(otherBId)!.note?.text ==
              'Independent accepted Note',
    );
    final sessionB = AppCloudSyncSession(
      auth: authB,
      database: dbB,
      repository: b,
      canMutate: () async => true,
      testRemoteFactory: mapped,
    );
    final protected = await sessionB.synchronize();
    _require(
      protected.pendingCount == 1 &&
          protected.pendingReasons.contains(
            CloudPendingReason.metadataConflict,
          ) &&
          b.snapshot.findSkill(bId)!.note?.text == 'Offline unsent Note' &&
          await dbB.syncStore.outboundTask(scopeB, 'fields', bId.value) == null,
    );
    await sessionB.close();
    await _success(
      b.saveNote(
        ws.SaveNoteRequest(
          managedSkillId: bId,
          text: 'Different accepted remote Note',
        ),
      ),
    );
    _require(
      (await coordinator.applyPending()).pendingCount == 0 &&
          b.snapshot.findSkill(bId)!.favorite.isFavorite,
    );
    await remoteMetadata({
      'kind': 'fields',
      'lineageId': receipt.lineageId,
      'generation': receipt.generation,
      'patch': {'favorite': null, 'note': ''},
    });
    await coordinator.pullChanges();
    await coordinator.applyPending();
    _require(
      b.snapshot.findSkill(bId)!.note == null &&
          !b.snapshot.findSkill(bId)!.favorite.isFavorite,
    );
    claims.add(
      'Real unsent local Note differing from its confirmed baseline and another accepted remote value stays pending without either-side overwrite or outbound fields; an independent Skill continues, already-satisfied target uses true no-op proof, and normal confirmed-order Favorite/Note clears still apply',
    );
    enter('dirtyDraftDoesNotOverwriteAndIndependentVocabularyAdvances');
    final dirty = await _success(
      b.ensureDraft(ws.EnsureDraftRequest(managedSkillId: bId)),
    );
    await File(path.join(dirty.path, 'notes.md'))
        .writeAsString('Unpublished local B customization.\n');
    await _success(b.inspectDraft(ws.InspectDraftRequest(managedSkillId: bId)));
    await _publish(a, aId, 'Third remote published history from A.\n');
    await _publish(
      a,
      otherAId,
      'Independent second Skill still advances while B primary is dirty.\n',
    );
    await appGateway.syncNow();
    final thirdTask = (await dbA.syncStore.outboundTask(
      scopeA,
      'content',
      aId.value,
    ))!;
    final thirdReceipt = CloudCommitReceipt.fromJson(
      await apiA.operationStatus(thirdTask.operationId),
    );
    await remoteMetadata({
      'kind': 'tagCreate',
      'name': 'Independent dirty-Draft vocabulary',
      'color': null,
    });
    await coordinator.pullChanges();
    final dirtyProgress = await coordinator.applyPending();
    _require(
      dirtyProgress.pendingCount == 1 &&
          (await dbB.syncStore.pendingItems(scopeB)).single.pendingReason ==
              CloudPendingReason.dirtyDraft,
    );
    _require(
      await File(path.join(dirty.path, 'notes.md')).readAsString() ==
          'Unpublished local B customization.\n',
    );
    final otherExpected = await adapterA.exportSelected(
      otherAId.value,
      CloudCancellation(),
    );
    final otherActual = await _success(
      b.exportCommittedRevision(
        ws.ExportCommittedRevisionRequest(
          managedSkillId: otherBId,
          expectedRevision: b.snapshot.revision,
        ),
      ),
    );
    _require(
      otherActual.currentEffective == otherExpected.currentEffective &&
          otherActual.publishedHistory.length ==
              otherExpected.publishedHistory.length,
    );
    claims.add(
      'Two Skills are opted in atomically through AppGateway batch selection; while B primary has a Dirty Draft, the independent second Skill receives its real Publish and advances exact roots/history',
    );
    _require(
      b.snapshot.personalTags.any(
        (tag) => tag.name == 'Independent dirty-Draft vocabulary',
      ),
    );
    await _success(b.discardDraft(ws.DiscardDraftRequest(managedSkillId: bId)));
    final afterDiscard = await coordinator.applyPending();
    _require(
      afterDiscard.pendingCount == 0 &&
          afterDiscard.applied.compareTo(thirdReceipt.sequence) >= 0,
    );
    claims.add(
      'A remote Publish leaves B Dirty Draft untouched while independent global vocabulary applies; explicit user discard later permits the pending fast-forward',
    );
    enter('realLocalReplacementAndManualCloudGeneration');
    final replacementSeed = _object(config['replacementSource']);
    final replacementManifest = CloudContentManifest.fromJson(
      _object(replacementSeed['contentManifest']),
    );
    final replacementRemote = Uri.parse(_text(replacementSeed['remote']));
    _require(
      replacementRemote.origin == loopback.origin &&
          replacementRemote.path.startsWith(prefix),
    );
    final beforeReplacement = await _success(
      a.captureAuthoritativeState(const ws.CaptureAuthoritativeStateRequest()),
    );
    final replacementBatch = await _success(
      a.fetchIncomingRevision(
        ws.FetchIncomingRevisionRequest(
          managedSkillId: aId,
          replaceExistingLineage: true,
          localOperationId: ws.OperationId(
            '123e4567-e89b-42d3-a456-426614174190',
          ),
          expectedIdentity: beforeReplacement.identity,
          expectedRevision: beforeReplacement.snapshot.revision,
          contentManifest: utf8.encode(
            jsonEncode(replacementManifest.toJson()),
          ),
          remote: ws.RevisionTransferRemote.loopbackForTesting(
            url: replacementRemote.toString(),
            ephemeralHeaders: () async => [
              'Authorization: Bearer ${_text(replacementSeed['readToken'])}',
            ],
          ),
        ),
      ),
    );
    final replacementCommand = replacementBatch.localCommand!;
    final localReplacement = await _success(
      a.replaceIncomingRevision(
        ws.ReplaceIncomingRevisionRequest(
          managedSkillId: aId,
          expectedIdentity: beforeReplacement.identity,
          expectedRevision: a.snapshot.revision,
          expectedLocalLineageFingerprint:
              beforeReplacement.localLineageFingerprints[aId]!,
          expectedEffective: replacementCommand.previousEffectiveReference!,
          incoming: replacementBatch,
        ),
      ),
    );
    output.writeln(
      jsonEncode({
        'kind': 'diagnostic',
        'phase': phase,
        'localReplacementType': localReplacement.runtimeType.toString(),
        if (localReplacement is ws.IncomingRevisionPending)
          'pendingReason': localReplacement.reason.name,
      }),
    );
    await output.flush();
    _require(localReplacement is ws.IncomingRevisionApplied);
    final newGeneration = await appGateway.syncNow();
    output.writeln(
      jsonEncode({
        'kind': 'diagnostic',
        'phase': phase,
        'publisherPending': newGeneration.pendingCount,
        'reasons': newGeneration.pendingReasons
            .map((value) => value.name)
            .toList(),
      }),
    );
    await output.flush();
    _require(newGeneration.pendingCount == 0);
    final replacementTask = (await dbA.syncStore.outboundTask(
      scopeA,
      'replacement',
      aId.value,
    ))!;
    final replacementReceipt = CloudCommitReceipt.fromJson(
      await apiA.operationStatus(replacementTask.operationId),
    );
    _require(
      replacementReceipt.lineageId == receipt.lineageId &&
          replacementReceipt.generation == 2,
    );
    enter('missingCloudObjectsAndExactSelectedRepair');
    output.writeln(
      jsonEncode({
        'kind': 'removeRetentionForTesting',
        'lineageId': replacementReceipt.lineageId,
        'commitId': replacementReceipt.commitId,
      }),
    );
    await output.flush();
    _require(await input.moveNext());
    _require(_object(jsonDecode(input.current))['kind'] == 'retentionRemoved');
    await coordinator.pullChanges();
    while ((await dbB.syncStore.progress(scopeB)).traversalHighWatermark !=
        null) {
      await coordinator.pullChanges();
    }
    final missing = await coordinator.applyPending();
    _require(
      missing.pendingCount == 2 &&
          (await dbB.syncStore.pendingItems(scopeB)).single.pendingReason ==
              CloudPendingReason.needsReupload,
    );
    final beforeRepairA = a.snapshot.revision;
    final repaired = await appGateway.syncNow();
    _require(
      repaired.pendingCount == 0 && a.snapshot.revision == beforeRepairA,
    );
    final repairTask = (await dbA.syncStore.outboundTask(
      scopeA,
      'repair',
      aId.value,
    ))!;
    final repairReceipt = CloudCommitReceipt.fromJson(
      await apiA.operationStatus(repairTask.operationId),
    );
    _require(
      repairReceipt.commitId == replacementReceipt.commitId &&
          repairReceipt.contentManifest.publishedHistory.length ==
              replacementReceipt.contentManifest.publishedHistory.length,
    );
    await coordinator.pullChanges();
    while ((await dbB.syncStore.progress(scopeB)).traversalHighWatermark !=
        null) {
      await coordinator.pullChanges();
    }
    final replacementApplied = await coordinator.applyPending();
    claims.add(
      'A private fixture deletes a real retention ref and real maintenance emits needsReupload; B remains content-pending, A manually pushes only its exact selected objects and repairs without Publish or local revision, then repairReady control state unblocks B original native replacement to pending zero',
    );
    final mappedReplacement = (await dbB.syncStore.mapping(
      scopeB,
      receipt.lineageId,
    ))!;
    _require(
      replacementApplied.pendingCount == 0 &&
          mappedReplacement.generation == 2 &&
          mappedReplacement.localSkillId == bId.value &&
          b.snapshot.managedSkills.length == 2 &&
          b.snapshot.findSkill(bId)!.source ==
              a.snapshot.findSkill(aId)!.source &&
          b.snapshot.findSkill(bId)!.note?.text ==
              a.snapshot.findSkill(aId)!.note?.text,
    );
    claims.add(
      'Real public local source replacement uses AppGateway prepare/native-push/lifecycle finalize under one durable operation; B replaces the same Managed ID at generation +1 with exact old-lineage/effective guards and retains Extra Data',
    );
    enter('deleteOldExportFence');
    await _success(
      a.remove(
        ws.RemoveRequest(
          managedSkillIds: {aId},
          intent: ws.DestructiveIntent(reviewedRevision: a.snapshot.revision),
        ),
      ),
    );
    var rejected = false;
    try {
      await adapterA.validateExportStillCurrent(
        localSkillId: aId.value,
        batch: batch,
        cancellation: CloudCancellation(),
      );
    } on CloudException {
      rejected = true;
    }
    _require(rejected);
    claims.add(
      'A captured export cannot be admitted after its local Skill is removed',
    );
    enter('remoteRemovalFromMappedDeletedSource');
    await appGateway.syncNow();
    await coordinator.pullChanges();
    final removed = await coordinator.applyPending();
    _require(
      removed.pendingCount == 0 &&
          b.snapshot.findSkill(bId) == null &&
          (await dbB.syncStore.mapping(scopeB, receipt.lineageId))!.retired,
    );
    claims.add(
      'Mapped A local deletion sends an explicit remote Removal; B uses guarded same-local-lineage public removal and authoritative cleanup-complete absence proof before acknowledgement',
    );

    await appGateway.close();
    output.writeln(
      jsonEncode({
        'kind': 'result',
        'result': 'passed',
        'phase': phase,
        'claims': claims,
        'limits': [
          'Control plane uses verified temporary-CA HTTPS; native Git uses the explicitly approved fixture-only 127.0.0.1 mapping.',
        ],
      }),
    );
    await output.flush();
  } catch (error) {
    output.writeln(
      jsonEncode({
        'kind': 'result',
        'result': 'failed',
        'phase': phase,
        'errorCode': error is CloudException
            ? error.code.name
            : 'qualificationFailed',
        'claims': claims,
      }),
    );
    await output.flush();
    exitCode = 1;
  } finally {
    await dbA?.close();
    await dbB?.close();
    await authA?.close();
    await authB?.close();
    if (a?.isOpen ?? false) await a!.close().completed;
    if (b?.isOpen ?? false) await b!.close().completed;
    if (temporary != null) {
      await Process.run('chmod', ['-R', 'u+w', temporary.path]);
      await temporary.delete(recursive: true);
    }
    await input.cancel();
    await output.close();
  }
}
