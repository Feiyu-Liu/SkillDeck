import 'dart:io';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';
import 'support.dart';

void main() {
  late AuthFixture auth;
  late Directory temporary;
  late BackgroundSqliteCloudDatabase database;
  late CloudSyncStore store;
  late CloudSyncClient api;
  late FakeWorkspace workspace;
  late CloudSyncCoordinator coordinator;
  setUp(() async {
    auth = AuthFixture();
    await auth.login();
    temporary = await Directory.systemTemp.createTemp('cloud-coordinator-');
    database = await BackgroundSqliteCloudDatabase.open(
      path: '${temporary.path}/cloud.sqlite',
      serviceOrigin: auth.transport.baseUri,
    );
    await database.initializeNewDeviceScope(auth.auth.currentSession!);
    store = database.syncStore;
    await store.initializeOptInScope(
      scope: scope(),
      capture: captureState(),
      selection: CloudSyncSelection(
        cloudLineageIds: {
          'lineage',
          'other',
          for (var i = 0; i < 8; i++) 'parallel-$i',
        },
      ),
      initialCursor: CloudSequence.parse('0'),
    );
    workspace = FakeWorkspace();
    api = CloudSyncClient(auth: auth.auth, intents: MemoryIntents());
    coordinator = CloudSyncCoordinator(
      scope: scope(),
      auth: auth.auth,
      api: api,
      store: store,
      workspace: workspace,
    );
  });
  tearDown(() async {
    await database.close();
    await auth.auth.close();
    await temporary.delete(recursive: true);
  });
  test('pull stages a whole typed page; dirty lineage stays pending while another lineage and tag apply', () async {
    final page = changes([
      revision(1, 'lineage'),
      metadata(2, 'lineage'),
      revision(3, 'other'),
      tag(4),
    ]);
    auth.transport.handler = (request, credential, _) async =>
        request.path == '/v1/sync/changes'
        ? ok({
            'after': '0',
            'highWatermark': '4',
            'nextCursor': '4',
            'entries': [
              revision(1, 'lineage'),
              metadata(2, 'lineage'),
              revision(3, 'other'),
              tag(4),
            ],
          })
        : auth.transport.normal(request, credential);
    final received = await coordinator.pullChanges();
    expect(await store.hasPendingVocabulary(scope()), isTrue);
    expect(await store.hasPendingLineageConflict(scope(), 'lineage'), isFalse);
    expect(received.received.toJson(), page.nextCursor.toJson());
    expect(received.applied.toJson(), '0');
    workspace.pending['lineage'] = CloudPendingReason.dirtyDraft;
    var applied = await coordinator.applyPending();
    expect(applied.pendingCount, 2);
    expect(applied.applied.toJson(), '0');
    expect(workspace.applied, containsAll(['change:3', 'change:4']));
    expect(workspace.applied, isNot(contains('change:2')));
    workspace.pending.clear();
    applied = await coordinator.applyPending();
    expect(applied.applied.toJson(), '4');
    expect(applied.pendingCount, 0);
    expect(workspace.handles.every((handle) => handle.disposed), isTrue);
  });
  test('snapshot creation response loss persists request key across database restart before retry and releases only durable complete pages', () async {
    final keys = <String>[];
    var lose = true, released = 0;
    auth.transport.handler = (request, credential, _) async {
      if (request.path == '/v1/sync/snapshots') {
        keys.add(
          (request.body!['data']! as Map<String, Object?>)['requestKey']!
              as String,
        );
        if (lose) {
          lose = false;
          throw const CloudException(CloudErrorCode.unavailable);
        }
        return ok({
          'snapshotId': 'snapshot',
          'highWatermark': '20',
          'pageCursor': null,
          'nextPageCursor': null,
          'complete': true,
          'items': <Object?>[],
          'personalTags': <Object?>[],
        });
      }
      if (request.path.endsWith('/release')) {
        expect((await store.progress(scope())).received.toJson(), '20');
        released++;
        return ok({'released': true});
      }
      return auth.transport.normal(request, credential);
    };
    await expectLater(
      coordinator.pullSnapshotPage(),
      throwsA(isA<CloudException>()),
    );
    final key = await store.ensureSnapshotRequestKey(scope());
    expect(released, 0);
    await database.close();
    database = await BackgroundSqliteCloudDatabase.open(
      path: '${temporary.path}/cloud.sqlite',
      serviceOrigin: auth.transport.baseUri,
    );
    store = database.syncStore;
    coordinator = CloudSyncCoordinator(
      scope: scope(),
      auth: auth.auth,
      api: api,
      store: store,
      workspace: workspace,
    );
    await coordinator.pullSnapshotPage();
    expect(keys, [key, key]);
    expect(released, 1);
    expect((await store.progress(scope())).applied.toJson(), '20');
  });
  test('repair availability is observed without a local mutation, lets metadata through and later ready unblocks missing content', () async {
    await store.stageChangesPage(scope(), changes([revision(1, 'lineage')]));
    await coordinator.applyPending();
    Map<String, Object?> control(int sequence, String kind) {
      final event = revision(sequence, 'lineage');
      event['kind'] = kind;
      event['payload'] = {
        ...event['payload']! as Map<String, Object?>,
        'contentStatus': kind == 'repairNeeded' ? 'needsReupload' : 'ready',
      };
      return event;
    }

    await store.stageChangesPage(
      scope(),
      changes([control(2, 'repairNeeded'), metadata(3, 'lineage')], after: 1),
    );
    final metadataProgress = await coordinator.applyPending();
    expect(workspace.applied, ['change:1', 'change:3']);
    expect(metadataProgress.pendingCount, 1);
    expect(
      (await store.integrityStates(scope())).single.status,
      CloudContentStatus.needsReupload,
    );
    await store.stageChangesPage(
      scope(),
      changes([revision(4, 'lineage'), control(5, 'repairNeeded')], after: 3),
    );
    await coordinator.applyPending();
    expect(
      (await store.pendingItems(scope())).single.pendingReason,
      CloudPendingReason.needsReupload,
    );
    await store.stageChangesPage(
      scope(),
      changes([control(6, 'repairReady')], after: 5),
    );
    final ready = await coordinator.applyPending();
    expect(ready.pendingCount, 0);
    expect(ready.applied.toJson(), '6');
    expect(workspace.applied, ['change:1', 'change:3', 'change:4']);
    expect(
      (await store.integrityStates(scope())).single.status,
      CloudContentStatus.ready,
    );
  });
  test('at most four independent revisions prepare concurrently; every same-lineage event stays ordered', () async {
    final entries = [
      for (var i = 0; i < 8; i++) revision(i + 1, 'parallel-$i'),
    ];
    await store.stageChangesPage(scope(), changes(entries));
    final result = await coordinator.applyPending();
    expect(result.applied.toJson(), '8');
    expect(workspace.maximumPrepares, inInclusiveRange(2, 4));
    expect(workspace.handles.every((handle) => handle.disposed), isTrue);
  });
  test('actual local commit followed by a lost Cloud acknowledgement resolves caller proof after restart', () async {
    await store.stageChangesPage(scope(), changes([revision(1, 'lineage')]));
    workspace.throwAfterApply = true;
    var result = await coordinator.applyPending();
    expect(result.applied.toJson(), '0');
    expect(workspace.revisionNumber, 1);
    final pending = (await store.pendingItems(scope())).single;
    expect(pending.pendingReason, CloudPendingReason.unknownOutcome);
    await database.close();
    database = await BackgroundSqliteCloudDatabase.open(
      path: '${temporary.path}/cloud.sqlite',
      serviceOrigin: auth.transport.baseUri,
    );
    store = database.syncStore;
    coordinator = CloudSyncCoordinator(
      scope: scope(),
      auth: auth.auth,
      api: api,
      store: store,
      workspace: workspace,
    );
    result = await coordinator.applyPending();
    expect(result.applied.toJson(), '1');
    expect(workspace.applied, hasLength(1));
    expect(workspace.resolved, ['change:1']);
    expect(
      workspace.handles,
      hasLength(1),
      reason: 'Unknown outcomes do not prepare or apply again',
    );
  });
  test('persisted unknown-before-port remains pending until affirmative not-started proof, reuses operation ID', () async {
    await store.stageChangesPage(scope(), changes([revision(1, 'lineage')]));
    final item = (await store.pendingItems(scope())).single;
    final binding = await store.bindApplyIntent(
      scope(),
      item,
      localTargetId: 'local-lineage',
    );
    await store.recordPending(scope(), item, CloudPendingReason.unknownOutcome);
    var result = await coordinator.applyPending();
    expect(result.pendingCount, 1);
    expect(workspace.applied, isEmpty);
    workspace.outcomes[item.eventKey] = CloudConfirmedNotStarted(
      eventKey: item.eventKey,
      operationId: binding.operationId,
      proofId: 'authoritative-not-started',
      capture: captureState(),
    );
    await coordinator.applyPending();
    expect(
      (await store.pendingItems(scope())).single.pendingReason,
      CloudPendingReason.unavailable,
    );
    result = await coordinator.applyPending();
    expect(result.applied.toJson(), '1');
    expect(
      (workspace.outcomes[item.eventKey]! as CloudApplied).operationId,
      binding.operationId,
    );
  });
  test('normal local revision changes refresh baseline without assuming deletion or acknowledgement', () async {
    await store.stageChangesPage(scope(), changes([revision(1, 'lineage')]));
    workspace.revisionNumber = 5;
    final result = await coordinator.applyPending();
    expect(result.expectedRevision, '6');
    expect(result.applied.toJson(), '1');
  });
  test('recovery incarnation/readiness changes fence scope without mutating local content', () async {
    await store.stageChangesPage(scope(), changes([revision(1, 'lineage')]));
    workspace.currentIdentity = const CloudWorkspaceIdentity(
      workspaceId: 'workspace',
      recoveryIncarnation: 'restored-incarnation',
    );
    await expectLater(
      coordinator.applyPending(),
      throwsA(isA<CloudException>()),
    );
    expect((await store.progress(scope())).needsReconciliation, isTrue);
    expect(workspace.applied, isEmpty);
    expect((await store.progress(scope())).pendingCount, 1);
  });
  test('retired mapping never starts download or reapplies a later old-generation revision', () async {
    await store.stageChangesPage(scope(), changes([revision(1, 'lineage')]));
    await coordinator.applyPending();
    await store.stageChangesPage(
      scope(),
      changes([removal(2, 'lineage')], after: 1),
    );
    await coordinator.applyPending();
    expect((await store.mapping(scope(), 'lineage'))?.retired, isTrue);
    await store.stageChangesPage(
      scope(),
      changes([revision(3, 'lineage')], after: 2),
    );
    final handles = workspace.handles.length,
        applied = workspace.applied.length;
    final result = await coordinator.applyPending();
    expect(result.applied.toJson(), '2');
    expect(result.pendingCount, 1);
    expect(workspace.handles.length, handles);
    expect(workspace.applied.length, applied);
  });
  test('snapshots remain staged until all pages are persisted', () async {
    auth.transport.handler = (request, credential, _) async {
      if (request.path == '/v1/sync/snapshots') {
        return ok({
          'snapshotId': 'snapshot',
          'highWatermark': '20',
          'pageCursor': null,
          'nextPageCursor': 'next',
          'complete': false,
          'items': [revision(20, 'lineage')['payload']],
          'personalTags': <Object?>[],
        });
      }
      if (request.path == '/v1/sync/snapshots/snapshot') {
        return ok({
          'snapshotId': 'snapshot',
          'highWatermark': '20',
          'pageCursor': 'next',
          'nextPageCursor': null,
          'complete': true,
          'items': <Object?>[],
          'personalTags': [
            {
              'tagId': 'tag',
              'name': 'Unassigned',
              'color': null,
              'createdAt': 1000,
              'updatedAt': 1000,
            },
          ],
        });
      }
      return auth.transport.normal(request, credential);
    };
    expect((await coordinator.pullSnapshotPage()).received.toJson(), '0');
    expect((await coordinator.applyPending()).applied.toJson(), '0');
    expect(workspace.applied, isEmpty);
    expect((await coordinator.pullSnapshotPage()).received.toJson(), '20');
    expect((await coordinator.applyPending()).applied.toJson(), '20');
  });
  test('snapshot expiry discards only partial staging and allows a fresh bootstrap', () async {
    await store.stageSnapshotPage(scope(), snapshot());
    auth.transport.handler = (request, credential, _) async =>
        request.path.startsWith('/v1/sync/snapshots/')
        ? failure('snapshotExpired', status: 409)
        : auth.transport.normal(request, credential);
    await expectLater(
      coordinator.pullSnapshotPage(),
      throwsA(isA<CloudException>()),
    );
    final progress = await store.progress(scope());
    expect(progress.snapshotId, isNull);
    expect(progress.received.toJson(), '0');
    expect(progress.selection.cloudLineageIds, contains('lineage'));
    expect(workspace.applied, isEmpty);
  });
}
