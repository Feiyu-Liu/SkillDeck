import 'dart:io';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/src/storage/sync_schema.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temporary;
  late String path;
  late SqliteCloudDatabase database;
  late CloudSyncStore store;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cloud-sync-store-');
    path = '${temporary.path}/cloud.sqlite';
    database = SqliteCloudDatabase.open(
      path: path,
      serviceOrigin: Uri.parse('https://cloud.example.invalid'),
    );
    store = database.syncStore;
    await database.initializeNewDeviceScope(
      const CloudSession(
        accountId: 'account',
        deviceId: 'device-1',
        sessionId: 'session',
      ),
    );
    await store.initializeOptInScope(
      scope: scope(),
      capture: captureState(),
      selection: CloudSyncSelection(
        cloudLineageIds: {'lineage', 'other'},
        localSkillIds: {'local-lineage'},
      ),
      initialCursor: CloudSequence.parse('0'),
    );
  });
  tearDown(() async {
    database.close();
    await temporary.delete(recursive: true);
  });
  Future<CloudApplied> proof(CloudInboxItem item, {int revision = 1}) async {
    final binding = await store.bindApplyIntent(
      scope(),
      item,
      localTargetId: item.change.lineageId == null
          ? null
          : 'local-${item.change.lineageId}',
    );
    return CloudApplied(
      eventKey: item.eventKey,
      operationId: binding.operationId,
      desiredFingerprint: binding.desiredFingerprint,
      capture: captureState(revision: revision),
      localSkillId: item.change.lineageId == null
          ? 'vocabulary'
          : 'local-${item.change.lineageId}',
      proofId: 'proof-${item.eventKey}',
    );
  }

  Future<CloudOutboundTask> createTag({String localId = 'local-tag'}) =>
      store.stageOutboundTask(
        scope(),
        kind: 'tagCreate',
        subjectId: localId,
        data: {'kind': 'tagCreate', 'name': 'Tag', 'color': null},
        localContext: {},
      );
  Map<String, Object?> tagReceipt(
    CloudOutboundTask task, {
    String sequence = '1',
  }) => {
    'operationId': task.operationId,
    'kind': 'tagCreate',
    'lineageId': null,
    'generation': null,
    'tagId': 'tag',
    'sequence': sequence,
    'receiptExpiresAt': 1700086400000,
    'outcome': 'committed',
  };
  test(
    'tag confirmation, local mapping and exact receipt echo are atomic',
    () async {
      final task = await createTag();
      await store.completeOutboundTask(
        scope(),
        task,
        tagReceipt(task),
        captureState(),
      );
      expect(
        (await store.personalTagMapping(scope(), 'tag'))!.localTagId,
        'local-tag',
      );
      await store.stageChangesPage(scope(), changes([tag(1)]));
      expect(await store.pendingItems(scope()), isEmpty);
      expect((await store.progress(scope())).applied.toJson(), '1');
      // Duplicate confirmation cannot replace the mapping or revive vocabulary.
      await store.completeOutboundTask(
        scope(),
        task,
        tagReceipt(task),
        captureState(revision: 5),
      );
      expect(
        (await store.personalTagMappings(scope())).single.localTagId,
        'local-tag',
      );
    },
  );
  test(
    'receipt kind or colliding sequence cannot partially acknowledge a new tag',
    () async {
      final first = await createTag();
      await store.completeOutboundTask(
        scope(),
        first,
        tagReceipt(first),
        captureState(),
      );
      final second = await createTag(localId: 'different-local');
      await expectLater(
        store.completeOutboundTask(scope(), second, {
          ...tagReceipt(second),
          'tagId': 'different-cloud',
        }, captureState()),
        throwsA(isA<CloudException>()),
      );
      expect(
        (await store.outboundTask(
          scope(),
          'tagCreate',
          'different-local',
        ))!.acknowledged,
        isFalse,
      );
      expect(
        await store.personalTagMapping(scope(), 'different-cloud'),
        isNull,
      );
      await expectLater(
        store.completeOutboundTask(scope(), second, {
          ...tagReceipt(second, sequence: '2'),
          'kind': 'tagDelete',
        }, captureState()),
        throwsA(isA<CloudException>()),
      );
      expect((await store.personalTagMappings(scope())), hasLength(1));
    },
  );
  test('confirmed sequence with changed desired payload is durable pending conflict', () async {
    final task = await createTag();
    await store.completeOutboundTask(
      scope(),
      task,
      tagReceipt(task),
      captureState(),
    );
    final event = tag(1);
    event['payload'] = {
      ...event['payload']! as Map<String, Object?>,
      'name': 'Different',
    };
    await store.stageChangesPage(scope(), changes([event]));
    expect(
      (await store.pendingItems(scope())).single.pendingReason,
      CloudPendingReason.receiptConflict,
    );
    expect((await store.progress(scope())).received.toJson(), '1');
    expect((await store.progress(scope())).applied.toJson(), '0');
  });
  test('tag deletion confirmation retires original ID without merging a new same-name tag', () async {
    final original = await createTag();
    await store.completeOutboundTask(
      scope(),
      original,
      tagReceipt(original),
      captureState(),
    );
    await store.stageChangesPage(scope(), changes([tag(1)]));
    final deletion = await store.stageOutboundTask(
      scope(),
      kind: 'tagDelete',
      subjectId: 'local-tag',
      data: {'kind': 'tagDelete', 'tagId': 'tag'},
      localContext: {},
    );
    await store.completeOutboundTask(scope(), deletion, {
      ...tagReceipt(deletion, sequence: '2'),
      'kind': 'tagDelete',
    }, captureState());
    await store.stageChangesPage(
      scope(),
      changes([tag(2, kind: 'tagDelete')], after: 1),
    );
    final replacement = await createTag(localId: 'new-local-tag');
    await store.completeOutboundTask(scope(), replacement, {
      ...tagReceipt(replacement, sequence: '3'),
      'tagId': 'new-cloud-tag',
    }, captureState());
    expect((await store.personalTagMapping(scope(), 'tag'))!.deleted, isTrue);
    expect(
      (await store.personalTagMapping(scope(), 'new-cloud-tag'))!.localTagId,
      'new-local-tag',
    );
    expect(await store.pendingItems(scope()), isEmpty);
  });
  test('lost field acknowledgement settles original desired state before a later edit gets a new operation', () async {
    await store.stageChangesPage(scope(), changes([revision(1, 'lineage')]));
    final incoming = (await store.pendingItems(scope())).single;
    await store.recordApplyProof(scope(), incoming, await proof(incoming));
    Future<CloudOutboundTask> fieldTask(String note) => store.stageOutboundTask(
      scope(),
      kind: 'fields',
      subjectId: 'local-lineage',
      data: {
        'kind': 'fields',
        'lineageId': 'lineage',
        'generation': 1,
        'patch': {'note': note},
      },
      localContext: {},
    );
    final original = await fieldTask('original desired');
    final laterWhilePending = await fieldTask('later local edit');
    expect(laterWhilePending.operationId, original.operationId);
    expect(laterWhilePending.data['patch'], {'note': 'original desired'});
    final result = {
      'operationId': original.operationId,
      'kind': 'fields',
      'lineageId': 'lineage',
      'generation': 1,
      'tagId': null,
      'sequence': '2',
      'receiptExpiresAt': 1700086400000,
      'outcome': 'replay',
    };
    await store.completeOutboundTask(
      scope(),
      original,
      result,
      captureState(revision: 8),
    );
    expect(
      (await store.publisherBaseline(scope(), 'local-lineage'))!.note,
      'original desired',
    );
    final echo = metadata(2, 'lineage');
    echo['payload'] = original.data;
    await store.stageChangesPage(scope(), changes([echo], after: 1));
    expect(await store.pendingItems(scope()), isEmpty);
    final latest = await fieldTask('later local edit');
    expect(latest.operationId, isNot(original.operationId));
    expect(
      (await store.pendingOutboundTasks(scope())).single.operationId,
      latest.operationId,
    );
    await store.setEnabled(scope(), false);
    expect((await store.progress(scope())).isEnabled, isFalse);
    expect((await store.progress(scope())).needsReconciliation, isFalse);
    await store.setEnabled(scope(), true);
    expect(
      (await store.pendingOutboundTasks(scope())).single.operationId,
      latest.operationId,
    );
    expect(
      (await store.publisherBaseline(scope(), 'local-lineage'))!.note,
      'original desired',
    );
  });
  test('initial desired-state proof is distinct and cannot settle an unknown operation', () async {
    await store.stageSnapshotPage(
      scope(),
      snapshot(next: null, complete: true),
    );
    final item = (await store.pendingItems(scope()))
        .firstWhere((item) => item.change.kind == 'revision');
    final binding = await store.bindApplyIntent(
      scope(),
      item,
      localTargetId: 'local-lineage',
      localLineageFingerprint: 'local-fingerprint',
    );
    final proof = CloudStateAlreadySatisfied(
      eventKey: item.eventKey,
      operationId: binding.operationId,
      desiredFingerprint: binding.desiredFingerprint,
      capture: CloudWorkspaceCapture(
        identity: identity,
        revision: '0',
        recoveryComplete: true,
        finalizationComplete: true,
        isComplete: true,
        localLineageFingerprints: {'local-lineage': 'local-fingerprint'},
      ),
      localSkillId: 'local-lineage',
      localLineageFingerprint: 'local-fingerprint',
      proofId: 'desiredStateSatisfied',
    );
    await store.recordPending(scope(), item, CloudPendingReason.unknownOutcome);
    final unknownItem = (await store.pendingItems(scope()))
        .firstWhere((item) => item.change.kind == 'revision');
    await expectLater(
      store.recordApplyProof(scope(), unknownItem, proof),
      throwsA(isA<CloudException>()),
    );
    // Fresh caller invocation can prove desired state after writing its boundary,
    // but replay must retain the durable unknown classification above.
    await store.recordApplyProof(scope(), item, proof);
    await store.recordApplyProof(scope(), item, proof);
    expect(
      (await store.mapping(scope(), 'lineage'))!.localLineageFingerprint,
      'local-fingerprint',
    );
    final raw = sqlite3.open(path);
    addTearDown(raw.close);
    expect(
      raw.select('SELECT count(*) AS n FROM cloud_sync_result').single['n'],
      1,
    );
  });
  for (final retire in [false, true]) {
    test(
      'late original content receipt settles task without rolling back ${retire ? 'Removal' : 'Replacement and newer Note'}',
      () async {
        await store.stageChangesPage(
          scope(),
          changes([revision(1, 'lineage')]),
        );
        final first = (await store.pendingItems(scope())).single;
        await store.recordApplyProof(scope(), first, await proof(first));
        final manifest =
            (revision(1, 'lineage')['payload']!
                    as Map<String, Object?>)['contentManifest']!
                as Map<String, Object?>;
        final old = await store.stageOutboundTask(
          scope(),
          kind: 'content',
          subjectId: 'local-lineage',
          data: {
            'lineageId': 'lineage',
            'generation': 1,
            'baseCommitId': 'a' * 40,
            'contentManifest': manifest,
          },
          localContext: {'localLineageFingerprint': 'old-native-lineage'},
        );
        if (retire) {
          await store.stageChangesPage(
            scope(),
            changes([removal(2, 'lineage')], after: 1),
          );
          final item = (await store.pendingItems(scope())).single;
          final binding = await store.bindApplyIntent(
            scope(),
            item,
            localTargetId: 'local-lineage',
            localLineageFingerprint: 'old-native-lineage',
          );
          await store.recordApplyProof(
            scope(),
            item,
            CloudTargetAbsent(
              eventKey: item.eventKey,
              operationId: binding.operationId,
              desiredFingerprint: binding.desiredFingerprint,
              capture: captureState(revision: 2),
              localSkillId: 'local-lineage',
              cleanupComplete: true,
              proofId: 'absence',
            ),
          );
        } else {
          final replaced = revision(2, 'lineage', generation: 2);
          replaced['kind'] = 'replacement';
          replaced['payload'] = {
            ...replaced['payload']! as Map<String, Object?>,
            'previousGeneration': 1,
          };
          await store.stageChangesPage(scope(), changes([replaced], after: 1));
          var item = (await store.pendingItems(scope())).single;
          var binding = await store.bindApplyIntent(
            scope(),
            item,
            localTargetId: 'local-lineage',
            localLineageFingerprint: 'new-native-lineage',
          );
          await store.recordApplyProof(
            scope(),
            item,
            CloudApplied(
              eventKey: item.eventKey,
              operationId: binding.operationId,
              desiredFingerprint: binding.desiredFingerprint,
              capture: captureState(revision: 2),
              localSkillId: 'local-lineage',
              proofId: 'replacement',
            ),
          );
          final note = metadata(3, 'lineage');
          note['generation'] = 2;
          note['payload'] = {
            'kind': 'fields',
            'lineageId': 'lineage',
            'generation': 2,
            'patch': {'note': 'newer confirmed Note'},
          };
          await store.stageChangesPage(scope(), changes([note], after: 2));
          item = (await store.pendingItems(scope())).single;
          binding = await store.bindApplyIntent(
            scope(),
            item,
            localTargetId: 'local-lineage',
            localLineageFingerprint: 'new-native-lineage',
          );
          await store.recordApplyProof(
            scope(),
            item,
            CloudApplied(
              eventKey: item.eventKey,
              operationId: binding.operationId,
              desiredFingerprint: binding.desiredFingerprint,
              capture: captureState(revision: 3),
              localSkillId: 'local-lineage',
              proofId: 'new-note',
            ),
          );
        }
        await store.completeOutboundTask(scope(), old, {
          'operationId': old.operationId,
          'lineageId': 'lineage',
          'generation': 1,
          'commitId': 'a' * 40,
          'sequence': '1',
          'outcome': 'replay',
          'receiptExpiresAt': 1700086400000,
          'contentManifestVersion': 1,
          'contentManifest': manifest,
        }, captureState(revision: 10));
        expect(
          (await store.outboundTask(
            scope(),
            'content',
            'local-lineage',
          ))!.acknowledged,
          isTrue,
        );
        final baseline = (await store.publisherBaseline(
          scope(),
          'local-lineage',
        ))!;
        expect(baseline.retired, retire);
        if (!retire) {
          expect(baseline.generation, 2);
          expect(baseline.localLineageFingerprint, 'new-native-lineage');
          expect(baseline.note, 'newer confirmed Note');
        }
      },
    );
  }
  test('late tag patch receipt after deletion never renames or revives the retired tag', () async {
    final created = await createTag();
    await store.completeOutboundTask(
      scope(),
      created,
      tagReceipt(created),
      captureState(),
    );
    final patch = await store.stageOutboundTask(
      scope(),
      kind: 'tagPatch',
      subjectId: 'local-tag',
      data: {
        'kind': 'tagPatch',
        'tagId': 'tag',
        'patch': {'name': 'old delayed rename'},
      },
      localContext: {},
    );
    final deleted = await store.stageOutboundTask(
      scope(),
      kind: 'tagDelete',
      subjectId: 'local-tag',
      data: {'kind': 'tagDelete', 'tagId': 'tag'},
      localContext: {},
    );
    await store.completeOutboundTask(scope(), deleted, {
      ...tagReceipt(deleted, sequence: '3'),
      'kind': 'tagDelete',
    }, captureState());
    await store.completeOutboundTask(scope(), patch, {
      ...tagReceipt(patch, sequence: '2'),
      'kind': 'tagPatch',
    }, captureState());
    final mapping = (await store.personalTagMapping(scope(), 'tag'))!;
    expect(mapping.deleted, isTrue);
    expect(mapping.name, 'Tag');
    expect(
      (await store.outboundTask(
        scope(),
        'tagPatch',
        'local-tag',
      ))!.acknowledged,
      isTrue,
    );
  });
  test(
    'pause cannot clear an existing reconciliation fence or authorize resume',
    () async {
      await store.requireReconciliation(scope());
      await store.setEnabled(scope(), false);
      expect((await store.progress(scope())).needsReconciliation, isTrue);
      expect((await store.progress(scope())).isEnabled, isFalse);
      await expectLater(
        store.setEnabled(scope(), true),
        throwsA(isA<CloudException>()),
      );
      expect((await store.progress(scope())).needsReconciliation, isTrue);
      expect(
        await database
            .forWorkspace('workspace')
            .hasAuthoritativeScope(accountId: 'account', deviceId: 'device-1'),
        isFalse,
      );
    },
  );
  test('startup opt-in probe is read-only, scoped and never creates a missing or foreign database', () async {
    final absent = '${temporary.path}/never-created.sqlite';
    expect(
      await BackgroundSqliteCloudDatabase.probeEnabledOptIn(
        path: absent,
        serviceOrigin: database.serviceOrigin,
      ),
      isFalse,
    );
    expect(await File(absent).exists(), isFalse);
    final before = await File(path).readAsBytes();
    expect(
      await BackgroundSqliteCloudDatabase.probeEnabledOptIn(
        path: path,
        serviceOrigin: database.serviceOrigin,
      ),
      isTrue,
    );
    expect(await File(path).readAsBytes(), before);
    expect(
      await BackgroundSqliteCloudDatabase.probeEnabledOptIn(
        path: path,
        serviceOrigin: Uri.parse('https://other.example.invalid'),
      ),
      isFalse,
    );
    expect(
      await database.hasEnabledOptIn(
        session: const CloudSession(
          accountId: 'other',
          deviceId: 'device-1',
          sessionId: 'session',
        ),
      ),
      isFalse,
    );
    await store.setEnabled(scope(), false);
    expect(
      await BackgroundSqliteCloudDatabase.probeEnabledOptIn(
        path: path,
        serviceOrigin: database.serviceOrigin,
      ),
      isFalse,
    );
    final foreign = File('${temporary.path}/foreign.sqlite');
    await foreign.writeAsString('preserve foreign bytes');
    expect(
      await BackgroundSqliteCloudDatabase.probeEnabledOptIn(
        path: foreign.path,
        serviceOrigin: database.serviceOrigin,
      ),
      isFalse,
    );
    expect(await foreign.readAsString(), 'preserve foreign bytes');
  });
  for (final replacement in [false, true]) {
    test(
      'confirmed local ${replacement ? 'replacement' : 'removal'} retires older known conflicts without executing their native intent',
      () async {
        await store.stageChangesPage(
          scope(),
          changes([revision(1, 'lineage')]),
        );
        var item = (await store.pendingItems(scope())).single;
        await store.recordApplyProof(scope(), item, await proof(item));
        await store.stageChangesPage(
          scope(),
          changes([metadata(2, 'lineage')], after: 1),
        );
        item = (await store.pendingItems(scope())).single;
        await store.recordPending(
          scope(),
          item,
          CloudPendingReason.metadataConflict,
        );
        final manifest =
            (revision(1, 'lineage')['payload']!
                    as Map<String, Object?>)['contentManifest']!
                as Map<String, Object?>;
        final task = await store.stageOutboundTask(
          scope(),
          kind: replacement ? 'replacement' : 'removal',
          subjectId: 'local-lineage',
          data: {
            'kind': replacement ? 'replacement' : 'removal',
            'lineageId': 'lineage',
            'generation': 1,
            if (replacement) ...{
              'baseCommitId': 'a' * 40,
              'contentManifest': manifest,
            },
          },
          localContext: {'localLineageFingerprint': 'new-local-lineage'},
        );
        final result = <String, Object?>{
          'operationId': task.operationId,
          'kind': 'removal',
          'lineageId': 'lineage',
          'generation': replacement ? 2 : 1,
          'tagId': null,
          'sequence': '3',
          'outcome': 'committed',
          'receiptExpiresAt': 1700086400000,
          if (replacement) ...{
            'commitId': 'a' * 40,
            'contentManifestVersion': 1,
            'contentManifest': manifest,
          },
        };
        await store.completeOutboundTask(
          scope(),
          task,
          result,
          captureState(revision: 5),
        );
        expect(await store.pendingItems(scope()), isEmpty);
        expect((await store.progress(scope())).pendingCount, 0);
        expect(
          (await store.mapping(scope(), 'lineage'))!.retired,
          !replacement,
        );
      },
    );
  }
  test('whole page and received cursor survive reopen; exact replay is noop and changed payload conflicts', () async {
    final page = changes([revision(1, 'lineage'), tag(2)], high: 3);
    expect(await store.hasPendingVocabulary(scope()), isFalse);
    await store.stageChangesPage(scope(), page);
    expect(await store.hasPendingVocabulary(scope()), isTrue);
    final first = (await store.pendingItems(scope())).first;
    await store.recordPending(
      scope(),
      first,
      CloudPendingReason.metadataConflict,
    );
    expect(await store.hasPendingLineageConflict(scope(), 'lineage'), isTrue);
    expect(await store.hasPendingLineageConflict(scope(), 'other'), isFalse);
    await store.stageChangesPage(scope(), page);
    expect((await store.progress(scope())).received.toJson(), '2');
    expect((await store.progress(scope())).applied.toJson(), '0');
    database.close();
    database = SqliteCloudDatabase.open(
      path: path,
      serviceOrigin: Uri.parse('https://cloud.example.invalid'),
    );
    store = database.syncStore;
    expect(await store.pendingItems(scope()), hasLength(2));
    await expectLater(
      store.stageChangesPage(
        scope(),
        changes([revision(1, 'other'), tag(2)], high: 3),
      ),
      throwsA(isA<CloudException>()),
    );
    await expectLater(
      store.stageChangesPage(
        scope(),
        changes([metadata(3, 'lineage')], after: 2, high: 4),
      ),
      throwsA(isA<CloudException>()),
    );
    expect((await store.progress(scope())).received.toJson(), '2');
  });
  test('real SQLite failure after inserting items rolls back page receipt, entries and cursor together', () async {
    final raw = sqlite3.open(path);
    addTearDown(raw.close);
    raw.execute(
      "CREATE TRIGGER fixture_fail BEFORE UPDATE ON cloud_sync_scope WHEN NEW.received='2' BEGIN SELECT RAISE(ABORT,'fixture'); END",
    );
    final page = changes([revision(1, 'lineage'), tag(2)]);
    await expectLater(
      store.stageChangesPage(scope(), page),
      throwsA(isA<CloudException>()),
    );
    expect((await store.progress(scope())).received.toJson(), '0');
    expect(await store.pendingItems(scope()), isEmpty);
    expect(raw.select('SELECT * FROM cloud_sync_page'), isEmpty);
    raw.execute('DROP TRIGGER fixture_fail');
    await store.stageChangesPage(scope(), page);
    expect(await store.pendingItems(scope()), hasLength(2));
  });
  test('global tag can apply independently without skipping an earlier pending lineage', () async {
    await store.stageChangesPage(
      scope(),
      changes([revision(1, 'lineage'), tag(2)]),
    );
    final items = await store.pendingItems(scope());
    await store.recordApplyProof(scope(), items[1], await proof(items[1]));
    var progress = await store.progress(scope());
    expect(progress.applied.toJson(), '0');
    expect(progress.pendingCount, 1);
    final firstProof = await proof(items[0], revision: 2);
    await store.recordApplyProof(scope(), items[0], firstProof);
    expect((await store.progress(scope())).applied.toJson(), '2');
    expect(await store.pendingItems(scope()), isEmpty);
    await store.recordApplyProof(scope(), items[0], firstProof);
    expect((await store.progress(scope())).expectedRevision, '2');
    final sameOutcomeLaterCapture = CloudApplied(
      eventKey: firstProof.eventKey,
      operationId: firstProof.operationId,
      desiredFingerprint: firstProof.desiredFingerprint,
      capture: captureState(revision: 50),
      localSkillId: firstProof.localSkillId,
      proofId: firstProof.proofId,
    );
    await store.recordApplyProof(scope(), items[0], sameOutcomeLaterCapture);
    expect(
      (await store.progress(scope())).expectedRevision,
      '2',
      reason: 'Duplicate proof cannot rewrite the current baseline',
    );
    final old = CloudApplied(
      eventKey: items[0].eventKey,
      operationId: firstProof.operationId,
      desiredFingerprint: firstProof.desiredFingerprint,
      capture: captureState(revision: 1),
      localSkillId: firstProof.localSkillId,
      proofId: 'different-old-proof',
    );
    await expectLater(
      store.recordApplyProof(scope(), items[0], old),
      throwsA(isA<CloudException>()),
    );
    expect((await store.progress(scope())).expectedRevision, '2');
  });
  test('same tag and lineage events cannot be applied out of order or resurrect deleted vocabulary', () async {
    await store.stageChangesPage(
      scope(),
      changes([tag(1), tag(2, kind: 'tagPatch'), tag(3, kind: 'tagDelete')]),
    );
    final items = await store.pendingItems(scope());
    await expectLater(
      store.recordApplyProof(scope(), items[1], await proof(items[1])),
      throwsA(isA<CloudException>()),
    );
    final first = await proof(items[0]);
    await store.recordApplyProof(scope(), items[0], first);
    await store.recordApplyProof(
      scope(),
      items[1],
      await proof(items[1], revision: 2),
    );
    await store.recordApplyProof(
      scope(),
      items[2],
      await proof(items[2], revision: 3),
    );
    await store.recordApplyProof(scope(), items[0], first);
    final raw = sqlite3.open(path);
    addTearDown(raw.close);
    expect(
      raw.select('SELECT deleted FROM cloud_sync_tags').single['deleted'],
      1,
    );
    expect((await store.progress(scope())).applied.toJson(), '3');
  });
  test('snapshot pages stage without apply, then advance received only after complete vocabulary page', () async {
    final first = snapshot();
    await store.stageSnapshotPage(scope(), first);
    await store.stageSnapshotPage(scope(), first);
    expect((await store.progress(scope())).received.toJson(), '0');
    expect(await store.pendingItems(scope()), isEmpty);
    await store.stageSnapshotPage(
      scope(),
      snapshot(
        cursor: 'next',
        next: null,
        complete: true,
        includeLineage: false,
        includeTag: true,
      ),
    );
    expect((await store.progress(scope())).received.toJson(), '20');
    final items = await store.pendingItems(scope());
    expect(items, hasLength(3));
    await store.recordApplyProof(scope(), items[2], await proof(items[2]));
    expect((await store.progress(scope())).applied.toJson(), '0');
    await store.recordApplyProof(
      scope(),
      items[0],
      await proof(items[0], revision: 2),
    );
    await store.recordApplyProof(
      scope(),
      items[1],
      await proof(items[1], revision: 3),
    );
    expect((await store.progress(scope())).applied.toJson(), '20');
  });
  test('retired mapping rejects later applied revision proof and preserves absence evidence', () async {
    await store.stageChangesPage(scope(), changes([revision(1, 'lineage')]));
    var item = (await store.pendingItems(scope())).single;
    await store.recordApplyProof(scope(), item, await proof(item));
    await store.stageChangesPage(
      scope(),
      changes([removal(2, 'lineage')], after: 1),
    );
    item = (await store.pendingItems(scope())).single;
    final binding = await store.bindApplyIntent(
      scope(),
      item,
      localTargetId: 'local-lineage',
    );
    final absence = CloudTargetAbsent(
      eventKey: item.eventKey,
      operationId: binding.operationId,
      desiredFingerprint: binding.desiredFingerprint,
      capture: captureState(revision: 2),
      localSkillId: 'local-lineage',
      cleanupComplete: true,
      proofId: 'cleanup-proof',
    );
    await store.recordApplyProof(scope(), item, absence);
    expect((await store.mapping(scope(), 'lineage'))?.retired, isTrue);
    await store.stageChangesPage(
      scope(),
      changes([revision(3, 'lineage')], after: 2),
    );
    item = (await store.pendingItems(scope())).single;
    await expectLater(
      store.recordApplyProof(scope(), item, await proof(item, revision: 3)),
      throwsA(isA<CloudException>()),
    );
    expect((await store.mapping(scope(), 'lineage'))?.retired, isTrue);
    expect((await store.progress(scope())).applied.toJson(), '2');
  });
  test('local apply binding survives unknown boundary and confirmed not-started requires exact operation', () async {
    await store.stageChangesPage(scope(), changes([revision(1, 'lineage')]));
    final item = (await store.pendingItems(scope())).single;
    final binding = await store.bindApplyIntent(
      scope(),
      item,
      localTargetId: 'local-lineage',
    );
    await store.recordPending(scope(), item, CloudPendingReason.unknownOutcome);
    database.close();
    database = SqliteCloudDatabase.open(
      path: path,
      serviceOrigin: Uri.parse('https://cloud.example.invalid'),
    );
    store = database.syncStore;
    expect(
      (await store.bindApplyIntent(scope(), item)).operationId,
      binding.operationId,
    );
    await expectLater(
      store.recordNotStarted(
        scope(),
        item,
        CloudConfirmedNotStarted(
          eventKey: item.eventKey,
          operationId: 'wrong',
          proofId: 'proof',
          capture: captureState(),
        ),
      ),
      throwsA(isA<CloudException>()),
    );
    await store.recordNotStarted(
      scope(),
      item,
      CloudConfirmedNotStarted(
        eventKey: item.eventKey,
        operationId: binding.operationId,
        proofId: 'caller-bound-not-started',
        capture: captureState(),
      ),
    );
    expect(
      (await store.pendingItems(scope())).single.pendingReason,
      CloudPendingReason.unavailable,
    );
  });
  test('outbox is explicit selected candidate only and never starts a retry window or network request', () async {
    const candidate = CloudOutboxCandidate(
      operationId: 'candidate',
      localSkillId: 'local-lineage',
      sourceLineageIdentity: 'source-lineage',
      historyIdentity: 'history-event',
      state: CloudOutboxState.candidate,
    );
    await store.stageOutboxCandidate(scope(), candidate);
    await store.stageOutboxCandidate(scope(), candidate);
    expect(
      (await store.outboxCandidates(scope())).single.firstAttemptUtc,
      isNull,
    );
    await expectLater(
      store.stageOutboxCandidate(
        scope(),
        const CloudOutboxCandidate(
          operationId: 'other',
          localSkillId: 'not-selected',
          sourceLineageIdentity: 'source',
          historyIdentity: 'history',
          state: CloudOutboxState.candidate,
        ),
      ),
      throwsA(isA<CloudException>()),
    );
  });
  test('v1 operations survive atomic migration to v2', () async {
    database.close();
    final raw = sqlite3.open(path);
    for (final table in syncSchemaColumns.keys) {
      raw.execute('DROP TABLE $table');
    }
    raw.userVersion = 1;
    raw.execute(
      "INSERT INTO cloud_operation VALUES('https://cloud.example.invalid','account','device-1','workspace','old-op',1,'metadata','2026-11-15T00:00:00.000Z','2026-11-15T00:00:00.000Z','{}',NULL)",
    );
    raw.close();
    database = SqliteCloudDatabase.open(
      path: path,
      serviceOrigin: Uri.parse('https://cloud.example.invalid'),
    );
    store = database.syncStore;
    final old = await database
        .forWorkspace('workspace')
        .readOperation(
          CloudOperationKey(
            accountId: 'account',
            deviceId: 'device-1',
            operationId: 'old-op',
          ),
        );
    expect(old?.version, 1);
    final check = sqlite3.open(path);
    expect(check.userVersion, 2);
    check.close();
  });

  test('only incomplete snapshot staging can be discarded; selection and candidates survive', () async {
    const candidate = CloudOutboxCandidate(
      operationId: 'candidate',
      localSkillId: 'local-lineage',
      sourceLineageIdentity: 'source',
      historyIdentity: 'history',
      state: CloudOutboxState.candidate,
    );
    await store.stageOutboxCandidate(scope(), candidate);
    await store.stageSnapshotPage(scope(), snapshot());
    await store.discardIncompleteSnapshot(scope(), 'snapshot');
    final progress = await store.progress(scope());
    expect(progress.snapshotId, isNull);
    expect(progress.received.toJson(), '0');
    expect(await store.outboxCandidates(scope()), hasLength(1));
    expect(progress.selection.localSkillIds, contains('local-lineage'));
    await store.stageSnapshotPage(
      scope(),
      snapshot(next: null, complete: true),
    );
    await expectLater(
      store.discardIncompleteSnapshot(scope(), 'snapshot'),
      throwsA(isA<CloudException>()),
    );
  });
  test('bounded page replay history compacts terminal inbox without accepting ancient pages again', () async {
    final first = changes([revision(1, 'not-selected')]);
    for (var index = 1; index <= 70; index++) {
      await store.stageChangesPage(
        scope(),
        changes([revision(index, 'not-selected')], after: index - 1),
      );
    }
    final raw = sqlite3.open(path);
    addTearDown(raw.close);
    expect(
      raw.select('SELECT count(*) AS n FROM cloud_sync_inbox').single['n'],
      0,
    );
    expect(
      raw.select('SELECT count(*) AS n FROM cloud_sync_page').single['n'],
      64,
    );
    await expectLater(
      store.stageChangesPage(scope(), first),
      throwsA(isA<CloudException>()),
    );
    expect((await store.progress(scope())).applied.toJson(), '70');
    expect(await store.mapping(scope(), 'not-selected'), isNull);
  });
}
