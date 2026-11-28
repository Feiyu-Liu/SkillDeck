import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/testing.dart';
import 'package:test/test.dart';

final origin = CloudServiceOrigin.parse('https://cloud.example.invalid');
PortableSource git([String name = 'repo']) =>
    PortableSource.git(locator: 'https://github.com/test/$name.git');
Future<
  ({Reconciler sync, FakeSyncWorkspace workspace, InMemorySyncStateStore state})
>
device(
  FakeCloudService service,
  String name, {
  http.Client? client,
  String account = 'owner',
  FakeSyncWorkspace? existingWorkspace,
  InMemorySyncStateStore? existingState,
}) async {
  final workspace = existingWorkspace ?? FakeSyncWorkspace();
  final state = existingState ?? InMemorySyncStateStore();
  final sessions = InMemoryCloudSessionStore();
  await sessions.write(
    StoredCloudSession(
      origin: origin,
      token: service.session(account, deviceName: name),
    ),
  );
  final dir = await Directory.systemTemp.createTemp('reconcile-');
  addTearDown(() => dir.delete(recursive: true));
  return (
    sync: Reconciler(
      api: CloudApi(
        client: client ?? service.client,
        origin: origin,
        sessions: sessions,
      ),
      workspace: workspace,
      state: state,
      scratchDirectory: dir.path,
    ),
    workspace: workspace,
    state: state,
  );
}

void main() {
  for (final label in ['originDeviceLabel', 'displayLabel']) {
    test(
      '$label changes neither upload nor replace a stable Device-Bound source',
      () async {
        final service = FakeCloudService();
        addTearDown(service.client.close);
        final a = await device(service, 'A'), b = await device(service, 'B');
        final skill = a.workspace.seed(
          source: PortableSource.deviceBound(
            originSourceType: 'local',
            originDeviceLabel: 'Mac A',
            displayLabel: 'Skill',
            originSourceId: 'a' * 64,
          ),
        );
        await a.sync.startSyncing(skill.id);
        await b.sync.bootstrap();
        final reads = _RelabelledWorkspace(a.workspace, {label: 'Renamed'});
        final renamed = Reconciler(
          api: a.sync.api,
          workspace: reads,
          state: a.state,
          scratchDirectory: a.sync.scratchDirectory,
        );
        service.requests.clear();
        expect(await renamed.reconcileSkill(skill.id), isA<SkillSynced>());
        expect((await a.state.links()).single.generation, 1);
        expect(service.requests.where((r) => r.method != 'GET'), isEmpty);
        final applied = b.workspace.applyCount;
        await b.sync.feedCheck();
        expect(b.workspace.applyCount, applied);
        final fresh = InMemorySyncStateStore();
        final boot = await Reconciler(
          api: a.sync.api,
          workspace: reads,
          state: fresh,
          scratchDirectory: a.sync.scratchDirectory,
        ).bootstrap();
        expect(boot.completed, isTrue);
        expect(boot.installedSkillIds, isEmpty);
        expect((await fresh.links()).single.managedSkillId, skill.id);
      },
    );
  }
  test(
    'legacy Device-Bound label comparison still changes Generation',
    () async {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final a = await device(service, 'A');
      final skill = a.workspace.seed(
        source: PortableSource.deviceBound(
          originSourceType: 'local',
          originDeviceLabel: 'Mac A',
          displayLabel: 'Skill',
        ),
      );
      await a.sync.startSyncing(skill.id);
      final renamed = Reconciler(
        api: a.sync.api,
        workspace: _RelabelledWorkspace(a.workspace, {
          'displayLabel': 'Renamed',
        }),
        state: a.state,
        scratchDirectory: a.sync.scratchDirectory,
      );
      expect(await renamed.reconcileSkill(skill.id), isA<SkillSynced>());
      expect((await a.state.links()).single.generation, 2);
    },
  );

  test('two devices fast-forward, upload local changes, merge offline divergence and attribute conflicts', () async {
    final service = FakeCloudService();
    addTearDown(service.client.close);
    final a = await device(service, 'A'), b = await device(service, 'B');
    final skill = a.workspace.seed(source: git());
    expect(await a.sync.startSyncing(skill.id), isA<SkillSynced>());
    final boot = await b.sync.bootstrap();
    expect(boot.completed, isTrue);
    expect(boot.installedSkillIds, hasLength(1));
    final other = (await b.workspace.listSkills()).single;
    a.workspace.publish(skill.id, {'a.txt': 'A'});
    expect(await a.sync.reconcileSkill(skill.id), isA<SkillSynced>());
    b.workspace.publish(other.id, {'b.txt': 'B'});
    expect(await b.sync.reconcileSkill(other.id), isA<SkillSynced>());
    expect(await a.sync.reconcileSkill(skill.id), isA<SkillSynced>());
    expect(a.workspace.files(skill.id), b.workspace.files(other.id));
    expect(a.workspace.files(skill.id), containsPair('a.txt', 'A'));
    expect(a.workspace.files(skill.id), containsPair('b.txt', 'B'));
    a.workspace.publish(skill.id, {'body.txt': 'A'});
    b.workspace.publish(other.id, {'body.txt': 'B'});
    await a.sync.reconcileSkill(skill.id);
    final conflict =
        await b.sync.reconcileSkill(other.id) as SyncNeedsAttention;
    expect(conflict.reason, AttentionReason.syncMergeConflict);
    expect(conflict.deviceName, 'A');
  });
  test(
    'Draft blocks only its skill; same-version feed checks cause no downloads',
    () async {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final a = await device(service, 'A'), b = await device(service, 'B');
      for (final name in ['one', 'two']) {
        final s = a.workspace.seed(source: git(name), name: name);
        await a.sync.startSyncing(s.id);
      }
      await b.sync.bootstrap();
      final original = await a.workspace.listSkills(),
          remote = await b.workspace.listSkills();
      b.workspace.drafts.add(remote.first.id);
      for (final s in original) {
        a.workspace.publish(s.id, {'new.txt': 'change'});
        await a.sync.reconcileSkill(s.id);
      }
      await b.sync.feedCheck();
      expect(
        b.workspace.files(remote.last.id),
        containsPair('new.txt', 'change'),
      );
      expect(b.sync.outcomes[remote.first.id], isA<SyncNeedsAttention>());
      final count = b.workspace.applyCount;
      await b.sync.feedCheck();
      expect(b.workspace.applyCount, count);
      b.workspace.drafts.clear();
      expect(await b.sync.reconcileSkill(remote.first.id), isA<SkillSynced>());
    },
  );
  for (final expiry in ['before read', 'before upload', 'before advance']) {
    test(
      'recreates a pending Lineage expiring $expiry with the same key',
      () async {
        var now = DateTime.utc(2026, 11, 27),
            failUpload = true,
            expireOnWrite = false;
        final service = FakeCloudService(now: () => now);
        addTearDown(service.client.close);
        final createKeys = <String>[];
        final client = MockClient((request) async {
          final path = request.url.path;
          if (path == '/v0/lineages') {
            createKeys.add(
              (jsonDecode(request.body) as Map)['clientKey'] as String,
            );
          }
          if (request.method == 'PUT' && failUpload) {
            failUpload = false;
            return _error('unavailable', 503);
          }
          if (expireOnWrite &&
              (expiry == 'before upload' && request.method == 'PUT' ||
                  expiry == 'before advance' && path.endsWith('/head'))) {
            expireOnWrite = false;
            now = now.add(const Duration(hours: 25));
          }
          return _forward(service, request);
        });
        addTearDown(client.close);
        final a = await device(service, 'A', client: client);
        await a.sync.bootstrap();
        final skill = a.workspace.seed(source: git());
        expect(await a.sync.startSyncing(skill.id), isA<WaitingToUpload>());
        final pending = (await a.state.links()).single;
        expect(pending.lineageId, isNotNull);
        if (expiry == 'before read') {
          now = now.add(const Duration(hours: 25));
        } else {
          expireOnWrite = true;
        }
        expect(
          await _scheduledDelay(a.sync.feedCheck),
          const Duration(minutes: 2),
        );
        expect(a.sync.outcomes[skill.id], isA<SkillSynced>());
        final synced = (await a.state.links()).single;
        expect(synced.lineageId, isNot(pending.lineageId));
        expect(synced.clientKey, isNull);
        expect(createKeys, [pending.clientKey, pending.clientKey]);
        final listed =
            await a.sync.api.listLibrary() as CloudApiSuccess<LibraryPage>;
        expect(listed.value.lineages.map((l) => l.id), [synced.lineageId]);
      },
    );
  }
  for (final missingAt in ['upload', 'advance']) {
    test(
      'an established Lineage disappearing at $missingAt settles while another skill syncs',
      () async {
        final service = FakeCloudService();
        addTearDown(service.client.close);
        String? lostId;
        var disappeared = false;
        final client = MockClient((request) async {
          final path = request.url.path;
          if (lostId != null && path.startsWith('/v0/lineages/$lostId')) {
            if (missingAt == 'upload' && request.method == 'PUT' ||
                missingAt == 'advance' && path.endsWith('/head')) {
              disappeared = true;
            }
            if (disappeared) return _error('notFound', 404);
          }
          return _forward(service, request);
        });
        addTearDown(client.close);
        final a = await device(service, 'A', client: client);
        final first = a.workspace.seed(source: git('one'), name: 'one');
        final second = a.workspace.seed(source: git('two'), name: 'two');
        expect(await a.sync.startSyncing(first.id), isA<SkillSynced>());
        expect(await a.sync.startSyncing(second.id), isA<SkillSynced>());
        lostId = (await a.state.links()).first.lineageId;
        a.workspace.publish(first.id, {'body.txt': 'one'});
        a.workspace.publish(second.id, {'body.txt': 'two'});
        expect(
          await _scheduledDelay(a.sync.checkLocalChanges),
          const Duration(minutes: 2),
        );
        expect(
          (a.sync.outcomes[first.id] as SyncNeedsAttention).reason,
          AttentionReason.missingAfterReset,
        );
        expect(a.sync.outcomes[second.id], isA<SkillSynced>());
        final changes = await a.workspace.inspectCommittedChanges(
          await a.state.workspaceCursor(),
        );
        expect(changes.skillIds, isEmpty);
      },
    );
  }
  test(
    'a conflict settles the feed and waits for a committed resolution',
    () async {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final a = await device(service, 'A'), b = await device(service, 'B');
      final one = a.workspace.seed(source: git('one'), name: 'one');
      final two = a.workspace.seed(source: git('two'), name: 'two');
      await a.sync.startSyncing(one.id);
      await a.sync.startSyncing(two.id);
      await b.sync.bootstrap();
      final [localOne, localTwo] = await b.workspace.listSkills();
      await b.sync.checkLocalChanges();
      final before = await b.state.feedCursor();
      final incoming = a.workspace.publish(one.id, {'body.txt': 'A'});
      b.workspace.publish(localOne.id, {'body.txt': 'B'});
      a.workspace.publish(two.id, {'b.txt': 'independent change'});
      await a.sync.checkLocalChanges();
      final page = await a.sync.api.checkFeed(
        after: before,
      ) as CloudApiSuccess<FeedPage>;
      expect(page.value.entries, hasLength(2));
      expect(
        await _scheduledDelay(b.sync.feedCheck),
        const Duration(minutes: 2),
      );
      expect(await b.state.feedCursor(), page.value.cursor);
      final conflict = b.sync.outcomes[localOne.id] as SyncNeedsAttention;
      expect(conflict.reason, AttentionReason.syncMergeConflict);
      expect(conflict.deviceName, 'A');
      expect(b.sync.outcomes[localTwo.id], isA<SkillSynced>());
      final incomingDownloads = service.requests.where(_isDownload).length;
      await b.sync.feedCheck();
      expect(service.requests.where(_isDownload), hasLength(incomingDownloads));
      expect(b.sync.outcomes[localOne.id], same(conflict));

      b.workspace.publish(localOne.id, {
        'body.txt': 'resolved',
      }, mergeParent: incoming.effective);
      expect(
        await _scheduledDelay(b.sync.checkLocalChanges),
        const Duration(minutes: 2),
      );
      expect(b.sync.outcomes[localOne.id], isA<SkillSynced>());
      expect((await b.state.links()).first.attentionAttempt, isNull);
    },
  );
  test(
    'skips an unlinked 404 and records a new install by its local ID',
    () async {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final a = await device(service, 'A');
      final client = MockClient((request) async {
        final response = await _forward(service, request);
        if (request.url.path != '/v0/feed') return response;
        final page = jsonDecode(response.body) as Map<String, Object?>;
        (page['entries'] as List<Object?>).insert(0, {
          'kind': 'lineage',
          'id': 'gone',
          'version': 1,
        });
        return http.Response(jsonEncode(page), 200);
      });
      addTearDown(client.close);
      final b = await device(service, 'B', client: client);
      await b.sync.bootstrap();
      final s = a.workspace.seed(source: git());
      expect(await a.sync.startSyncing(s.id), isA<SkillSynced>());
      expect(
        await _scheduledDelay(b.sync.feedCheck),
        const Duration(minutes: 2),
      );
      expect(
        service.requests,
        contains((method: 'GET', path: '/v0/lineages/gone')),
      );
      final local = (await b.workspace.listSkills()).single;
      expect(b.sync.outcomes, {local.id: isA<SkillSynced>()});
    },
  );
  test('restarts an expired library listing once and never installs an incomplete listing', () async {
    for (final expiries in [1, 2]) {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final a = await device(service, 'A');
      for (final name in ['one', 'two']) {
        final s = a.workspace.seed(source: git(name), name: name);
        expect(await a.sync.startSyncing(s.id), isA<SkillSynced>());
      }
      var expired = 0;
      final cursors = <String?>[];
      final client = MockClient((request) {
        if (request.url.path != '/v0/library') {
          return _forward(service, request);
        }
        final params = request.url.queryParameters;
        cursors.add(params['cursor']);
        if (params.containsKey('cursor') && expired < expiries) {
          service.expireFeed('owner');
          expired++;
        }
        return _forward(
          service,
          http.Request(
            'GET',
            request.url.replace(queryParameters: {...params, 'limit': '1'}),
          )..headers.addAll(request.headers),
        );
      });
      addTearDown(client.close);
      final b = await device(service, 'B', client: client);
      final result = await b.sync.bootstrap();
      expect(cursors, [null, isNotNull, null, isNotNull]);
      expect(expired, expiries);
      expect(result.completed, expiries == 1);
      expect(result.installedSkillIds, hasLength(expiries == 1 ? 2 : 0));
      expect(b.workspace.installCount, expiries == 1 ? 2 : 0);
      expect(await b.state.feedCursor(), expiries == 1 ? isNotNull : isNull);
    }
  });
  test(
    'reports account conditions without a false failed check or cursor advance',
    () async {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      var unauthorized = false;
      final client = MockClient(
        (request) async => unauthorized
            ? _error('unauthorized', 401)
            : _forward(service, request),
      );
      addTearDown(client.close);
      for (final bootstrapped in [false, true]) {
        final a = await device(service, 'A', client: client);
        unauthorized = false;
        if (bootstrapped) expect((await a.sync.bootstrap()).completed, isTrue);
        final cursor = await a.state.feedCursor();
        unauthorized = true;
        expect(
          await _scheduledDelay(a.sync.feedCheck),
          const Duration(minutes: 2),
        );
        expect(a.sync.accountCondition?.condition, isA<ApiSignInRequired>());
        expect(await a.state.feedCursor(), cursor);
      }
    },
  );
  test('lost create, upload and advance responses recover from state without duplicate lineages', () async {
    for (final stage in ['create', 'upload', 'advance']) {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final a = await device(service, 'A');
      final skill = a.workspace.seed(source: git());
      if (stage == 'create') {
        service.failNext(path: '/v0/lineages', afterCommit: true);
      } else {
        // Pause after create to learn the opaque ID, then lose the selected write's response.
        service.failNext(path: '/v0/lineages', afterCommit: true);
        await a.sync.startSyncing(skill.id);
        final pending = (await a.state.links()).single;
        final created = await a.sync.api.createLineage(
          clientKey: pending.clientKey!,
          source: skill.source.toJson(),
        ) as CloudApiSuccess<Lineage>;
        if (stage == 'advance') {
          service.failNext(
            path: '/v0/lineages/${created.value.id}/head',
            afterCommit: true,
          );
        } else {
          service.failNext(
            afterCommit: true,
            path:
                '/v0/lineages/${created.value.id}/generations/1/packs/${await _digest(a.workspace, skill.id, a.sync.scratchDirectory)}',
          );
        }
      }
      expect(await a.sync.startSyncing(skill.id), isA<WaitingToUpload>());
      expect(await a.sync.reconcileSkill(skill.id), isA<SkillSynced>());
      expect(
        (await a.sync.api.listLibrary() as CloudApiSuccess<LibraryPage>)
            .value
            .lineages,
        hasLength(1),
      );
    }
  });
  test('a quota-blocked linked upload resumes after restart without a new local change', () async {
    final service = FakeCloudService();
    addTearDown(service.client.close);
    var quota = false;
    final client = MockClient(
      (request) async => request.method == 'PUT' && quota
          ? _error('storageLimitReached', 403)
          : _forward(service, request),
    );
    addTearDown(client.close);
    final a = await device(service, 'A', client: client);
    final skill = a.workspace.seed(source: git());
    expect(await a.sync.startSyncing(skill.id), isA<SkillSynced>());
    quota = true;
    final edited = a.workspace.publish(skill.id, {'body.txt': 'edited'});
    expect(
      await _scheduledDelay(a.sync.checkLocalChanges),
      const Duration(minutes: 2),
    );
    expect(a.sync.accountCondition?.condition, isA<ApiStorageLimitReached>());
    expect((await a.state.links()).single.uploadBlockedByQuota, isTrue);
    final cursor = await a.state.workspaceCursor();
    expect(
      (await a.workspace.inspectCommittedChanges(cursor)).skillIds,
      isEmpty,
    );

    final restarted = Reconciler(
      api: a.sync.api,
      workspace: a.workspace,
      state: a.state,
      scratchDirectory: a.sync.scratchDirectory,
    );
    quota = false;
    await restarted.checkLocalChanges();
    expect(restarted.outcomes[skill.id], isA<SkillSynced>());
    expect(restarted.accountCondition, isNull);
    final link = (await a.state.links()).single;
    expect(link.uploadBlockedByQuota, isFalse);
    expect(link.effective, edited.effective);
    expect(await a.state.workspaceCursor(), cursor);
  });
  test('removal, stop and lost removal responses converge without deleting stopped copies', () async {
    final service = FakeCloudService();
    addTearDown(service.client.close);
    final a = await device(service, 'A'), b = await device(service, 'B');
    var s = a.workspace.seed(source: git());
    await a.sync.startSyncing(s.id);
    await b.sync.bootstrap();
    var other = (await b.workspace.listSkills()).single;
    b.workspace.drafts.add(other.id);
    a.workspace.removeLocally(s.id);
    final lineage = (await a.state.links()).single.lineageId!;
    service.failNext(path: '/v0/lineages/$lineage/removal', afterCommit: true);
    expect(await a.sync.reconcileSkill(s.id), isA<WaitingToUpload>());
    expect(await a.sync.reconcileSkill(s.id), isA<SkillRemoved>());
    expect(
      (await b.sync.reconcileSkill(other.id) as SyncNeedsAttention).reason,
      AttentionReason.removedWithDraft,
    );
    b.workspace.drafts.clear();
    expect(await b.sync.reconcileSkill(other.id), isA<SkillRemoved>());
    s = a.workspace.seed(source: git());
    await a.sync.startSyncing(s.id);
    await b.sync.bootstrap();
    other = (await b.workspace.listSkills()).single;
    expect(await a.sync.stopSyncing(s.id), isA<SkillDeviceOnly>());
    expect(await b.sync.reconcileSkill(other.id), isA<SkillDeviceOnly>());
    expect(await b.workspace.inspectRevisionSelections(other.id), isNotNull);
  });
  test('size and transient failures have resolvable outcomes', () async {
    final service = FakeCloudService();
    addTearDown(service.client.close);
    final a = await device(service, 'A');
    final s = a.workspace.seed(source: git());
    a.workspace.exportSize = CloudApi.maxPackBytes + 1;
    expect(
      (await a.sync.startSyncing(s.id) as SyncNeedsAttention).reason,
      AttentionReason.tooLarge,
    );
    a.workspace.exportSize = null;
    service.failNext();
    expect(await a.sync.reconcileSkill(s.id), isA<WaitingToUpload>());
    expect(await a.sync.reconcileSkill(s.id), isA<SkillSynced>());
  });
  test('bootstrap links exact matches, preserves local copies through exclusions and resolves occupied slots', () async {
    final service = FakeCloudService();
    addTearDown(service.client.close);
    final a = await device(service, 'A'), b = await device(service, 'B');
    final sources = [
      git(),
      PortableSource.deviceBound(
        originSourceType: 'local',
        originDeviceLabel: 'A',
        displayLabel: 'Local source',
      ),
      PortableSource.deviceBound(
        originSourceType: 'adoptedSnapshot',
        originDeviceLabel: 'A',
        displayLabel: 'Adopted',
      ),
    ];
    for (var i = 0; i < sources.length; i++) {
      final s = a.workspace.seed(source: sources[i], name: 'skill$i');
      await a.sync.startSyncing(s.id);
    }
    b.workspace.seed(source: sources[0], name: 'skill0');
    final boot = await b.sync.bootstrap();
    expect(boot.installedSkillIds, hasLength(2));
    expect(b.workspace.syncedOriginSkills, hasLength(2));
    expect(b.workspace.activations, isEmpty);
    final linked = (await b.state.links()).first;
    await b.sync.exclude(linked.lineageId!);
    await b.sync.bootstrap();
    expect(
      (await b.state.links()).where((l) => l.lineageId == linked.lineageId),
      isEmpty,
    );
    expect(
      await b.workspace.inspectRevisionSelections(linked.managedSkillId),
      isNotNull,
    );
    await b.sync.include(linked.lineageId!);
    await b.sync.feedCheck();
    expect(
      (await b.state.links()).where((l) => l.lineageId == linked.lineageId),
      hasLength(1),
    );
    final c = await device(service, 'C');
    final occupied = c.workspace.seed(source: git('other'), name: 'skill0');
    final conflict = await c.sync.bootstrap();
    final id = conflict.outcomes.entries
        .firstWhere((e) => e.value is SyncNeedsAttention)
        .key;
    expect(
      (conflict.outcomes[id] as SyncNeedsAttention).reason,
      AttentionReason.slotOccupied,
    );
    expect(await c.sync.replaceOccupied(id, occupied.id), isA<SkillSynced>());
  });
  test('expired cursors reset without upload; missing copies have three explicit resolutions', () async {
    for (final action in ['keep', 'remove', 'upload']) {
      var now = DateTime.utc(2026, 11, 27);
      final service = FakeCloudService(now: () => now);
      addTearDown(service.client.close);
      final a = await device(service, 'A'), b = await device(service, 'B');
      final s = a.workspace.seed(source: git());
      await a.sync.startSyncing(s.id);
      await b.sync.bootstrap();
      final local = (await b.workspace.listSkills()).single;
      await a.sync.stopSyncing(s.id);
      now = now.add(const Duration(days: 91));
      await b.sync.feedCheck();
      expect(
        (b.sync.outcomes[local.id] as SyncNeedsAttention).reason,
        AttentionReason.missingAfterReset,
      );
      expect(
        (await b.sync.api.listLibrary() as CloudApiSuccess<LibraryPage>)
            .value
            .lineages,
        isEmpty,
      );
      final result = switch (action) {
        'keep' => await b.sync.keepDeviceOnly(local.id),
        'remove' => await b.sync.removeMissingLocally(local.id),
        _ => await b.sync.uploadAsNewLineage(local.id),
      };
      expect(
        result,
        action == 'keep'
            ? isA<SkillDeviceOnly>()
            : action == 'remove'
            ? isA<SkillRemoved>()
            : isA<SkillSynced>(),
      );
    }
  });
  test('source replacement syncs both ways, preserves ID and handles lost responses and local changes', () async {
    final service = FakeCloudService();
    addTearDown(service.client.close);
    final a = await device(service, 'A'), b = await device(service, 'B');
    final s = a.workspace.seed(source: git());
    await a.sync.startSyncing(s.id);
    await b.sync.bootstrap();
    final other = (await b.workspace.listSkills()).single;
    a.workspace.replaceLocally(s.id, git('new'));
    final id = (await a.state.links()).single.lineageId!;
    service.failNext(path: '/v0/lineages/$id/generations', afterCommit: true);
    expect(await a.sync.reconcileSkill(s.id), isA<WaitingToUpload>());
    expect(await a.sync.reconcileSkill(s.id), isA<SkillSynced>());
    expect(await b.sync.reconcileSkill(other.id), isA<SkillSynced>());
    expect((await b.workspace.listSkills()).single.id, other.id);
    expect((await b.state.links()).single.generation, 2);
    a.workspace.replaceLocally(s.id, git('third'));
    b.workspace.publish(other.id, {'local': 'unsynced'});
    await a.sync.reconcileSkill(s.id);
    expect(
      (await b.sync.reconcileSkill(other.id) as SyncNeedsAttention).reason,
      AttentionReason.sourceReplacedWithLocalChanges,
    );
    expect(await b.sync.acceptReplacement(other.id), isA<SkillSynced>());
    expect(b.workspace.files(other.id), isNot(contains('local')));
    a.workspace.replaceLocally(s.id, git('fourth'));
    b.workspace.replaceLocally(other.id, git('competing'));
    await a.sync.reconcileSkill(s.id);
    expect(
      (await b.sync.reconcileSkill(other.id) as SyncNeedsAttention).reason,
      AttentionReason.sourceReplacedWithLocalChanges,
    );
    await b.sync.keepDeviceOnly(other.id);
    await b.sync.feedCheck();
    expect((await b.workspace.listSkills()).single.source, git('competing'));
    expect(await b.state.links(), isEmpty);
  });
  test('concurrent replacements have one generation winner; Draft and slot blockers apply nothing', () async {
    final service = FakeCloudService();
    addTearDown(service.client.close);
    final a = await device(service, 'A'), b = await device(service, 'B');
    final s = a.workspace.seed(source: git());
    await a.sync.startSyncing(s.id);
    await b.sync.bootstrap();
    final other = (await b.workspace.listSkills()).single;
    a.workspace.replaceLocally(s.id, git('a'));
    b.workspace.replaceLocally(other.id, git('b'));
    final outcomes = await Future.wait([
      a.sync.reconcileSkill(s.id),
      b.sync.reconcileSkill(other.id),
    ]);
    expect(outcomes.whereType<SkillSynced>(), hasLength(1));
    expect(
      outcomes.whereType<SyncNeedsAttention>().single.reason,
      AttentionReason.sourceReplacedWithLocalChanges,
    );
    final winner = outcomes[0] is SkillSynced ? a : b,
        loser = outcomes[0] is SkillSynced ? b : a;
    final winnerId = (await winner.state.links()).single.managedSkillId,
        loserId = (await loser.state.links()).single.managedSkillId;
    await loser.sync.acceptReplacement(loserId);
    loser.workspace.drafts.add(loserId);
    winner.workspace.replaceLocally(winnerId, git('third'));
    await winner.sync.reconcileSkill(winnerId);
    final before = await loser.workspace.inspectRevisionSelections(loserId);
    expect(
      (await loser.sync.reconcileSkill(loserId) as SyncNeedsAttention).reason,
      AttentionReason.incomingDraft,
    );
    expect(
      await loser.workspace.inspectRevisionSelections(loserId),
      same(before),
    );
    loser.workspace.drafts.clear();
    await loser.sync.reconcileSkill(loserId);
    loser.workspace.seed(source: git('occupied'), name: 'occupied');
    winner.workspace.replaceLocally(winnerId, git('fourth'), name: 'occupied');
    await winner.sync.reconcileSkill(winnerId);
    expect(
      (await loser.sync.reconcileSkill(loserId) as SyncNeedsAttention).reason,
      AttentionReason.slotOccupied,
    );
    expect(
      (await loser.workspace.inspectRevisionSelections(loserId))!.declaredName,
      'fixture',
    );
  });
  test('same-descriptor Source replacement advances once despite a lost response and does not echo', () async {
    for (final preserveSelection in [false, true]) {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final a = await device(service, 'A'), b = await device(service, 'B');
      final source = git();
      final skill = a.workspace.seed(source: source);
      expect(await a.sync.startSyncing(skill.id), isA<SkillSynced>());
      final peerId = (await b.sync.bootstrap()).installedSkillIds.single;
      final originalPeerEpoch = (await b.state.links()).single.sourceEpoch;
      final originalLink = (await a.state.links()).single;
      final lineageId = originalLink.lineageId!;
      final next = a.workspace.replaceLocally(
        skill.id,
        source,
        preserveSelection: preserveSelection,
      );
      expect(next.sourceEpoch, isNot(originalLink.sourceEpoch));
      if (preserveSelection) expect(next.effective, skill.effective);
      service.failNext(
        path: '/v0/lineages/$lineageId/generations',
        afterCommit: true,
      );
      expect(await a.sync.reconcileSkill(skill.id), isA<WaitingToUpload>());
      final restarted = Reconciler(
        api: a.sync.api,
        workspace: a.workspace,
        state: a.state,
        scratchDirectory: a.sync.scratchDirectory,
      );
      expect(await restarted.reconcileSkill(skill.id), isA<SkillSynced>());
      expect((await a.state.links()).single.sourceEpoch, next.sourceEpoch);
      await b.sync.feedCheck();
      await b.sync.checkLocalChanges();
      expect(b.sync.outcomes[peerId], isA<SkillSynced>());
      final peer = await b.workspace.inspectRevisionSelections(peerId);
      expect(peer?.sourceEpoch, isNot(originalPeerEpoch));
      expect((await b.state.links()).single.sourceEpoch, peer?.sourceEpoch);
      expect(peer?.effective, next.effective);
      final remote =
          await a.sync.api.readLineage(lineageId) as CloudApiSuccess<Lineage>;
      expect(remote.value.generation, 2);
      expect(
        service.requests.where((r) => r.path.endsWith('/generations')),
        hasLength(1),
      );
    }
  });
  test('bootstrap retries lost listing/download responses without duplicate installs', () async {
    for (final stage in ['list', 'download']) {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final a = await device(service, 'A'), b = await device(service, 'B');
      final s = a.workspace.seed(source: git());
      await a.sync.startSyncing(s.id);
      final link = (await a.state.links()).single;
      final remote = (await a.sync.api.readLineage(
        link.lineageId!,
      ) as CloudApiSuccess<Lineage>).value;
      service.failNext(
        path: stage == 'list'
            ? '/v0/library'
            : '/v0/lineages/${remote.id}/generations/1/packs/${remote.head!.pack.value}',
        afterCommit: true,
      );
      expect((await b.sync.bootstrap()).completed, isFalse);
      expect((await b.sync.bootstrap()).completed, isTrue);
      await b.sync.bootstrap();
      expect(b.workspace.installCount, 1);
      expect(await b.state.links(), hasLength(1));
    }
  });
  test('portable sources round-trip and reject path-like device labels', () {
    for (final source in [
      git(),
      PortableSource.git(locator: 'git@github.com:owner/repo.git'),
      PortableSource.wellKnown(locator: 'https://example.com/index.json'),
      PortableSource.deviceBound(
        originSourceType: 'local',
        originDeviceLabel: 'Mac',
        displayLabel: 'Skills',
      ),
    ]) {
      expect(PortableSource.fromJson(source.toJson()), source);
    }
    expect(
      () => PortableSource.deviceBound(
        originSourceType: 'local',
        originDeviceLabel: 'Mac',
        displayLabel: '/Users/private/skills',
      ),
      throwsArgumentError,
    );
  });
}

Future<http.Response> _forward(
  FakeCloudService service,
  http.Request request,
) async => http.Response.fromStream(
  await service.client.send(
    http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = request.bodyBytes,
  ),
);

http.Response _error(String code, int status) =>
    http.Response(jsonEncode({'error': code}), status);

bool _isDownload(({String method, String path}) r) =>
    r.method == 'GET' && r.path.contains('/packs/');

Future<Duration> _scheduledDelay(
  Future<FeedCheckResult> Function() check,
) async {
  final next = Completer<Duration>();
  final scheduler = FeedCheckScheduler(
    check: check,
    random: () => 0.5,
    createTimer: (delay, callback) {
      next.complete(delay);
      return Timer(delay, callback);
    },
  )..start();
  try {
    return await next.future;
  } finally {
    scheduler.stop();
  }
}

Future<String> _digest(
  FakeSyncWorkspace workspace,
  String id,
  String scratch,
) async {
  final path = '$scratch/fixture.pack';
  await workspace.exportRevisionPack(id, path);
  final bytes = await File(path).readAsBytes();
  await File(path).delete();
  return sha256.convert(bytes).toString();
}

// Relabel only read results, without pretending an actual Source Replacement
// happened. Unsupported mutations fail so the no-apply assertions are meaningful.
final class _RelabelledWorkspace implements SyncWorkspace {
  _RelabelledWorkspace(this.delegate, this.labels);
  final SyncWorkspace delegate;
  final Map<String, String> labels;
  WorkspaceSkill _read(WorkspaceSkill value) => WorkspaceSkill(
    id: value.id,
    effective: value.effective,
    upstream: value.upstream,
    source: PortableSource.fromJson({...value.source.toJson(), ...labels}),
    declaredName: value.declaredName,
    slotKey: value.slotKey,
    sourceEpoch: value.sourceEpoch,
  );
  @override
  String? slotKeyForName(String name) => delegate.slotKeyForName(name);
  @override
  Future<List<WorkspaceSkill>> listSkills() async =>
      (await delegate.listSkills()).map(_read).toList();
  @override
  Future<WorkspaceSkill?> inspectRevisionSelections(String id) async {
    final value = await delegate.inspectRevisionSelections(id);
    return value == null ? null : _read(value);
  }

  @override
  Future<WorkspaceMetadataSnapshot> inspectMetadata() =>
      delegate.inspectMetadata();
  @override
  Future<WorkspaceChanges> inspectCommittedChanges(String? cursor) =>
      delegate.inspectCommittedChanges(cursor);
  @override
  Future<WorkspaceExport> exportRevisionPack(String id, String path) =>
      delegate.exportRevisionPack(id, path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
