import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/testing.dart';
import 'package:test/test.dart';

final origin = CloudServiceOrigin.parse('https://cloud.example.invalid');
PortableSource git([String name = 'repo']) =>
    PortableSource.git(locator: 'https://github.com/test/$name.git');
Future<
  ({Reconciler sync, FakeSyncWorkspace workspace, InMemorySyncStateStore state})
>
device(FakeCloudService service, String name) async {
  final workspace = FakeSyncWorkspace(),
      state = InMemorySyncStateStore(),
      sessions = InMemoryCloudSessionStore();
  await sessions.write(
    StoredCloudSession(
      origin: origin,
      token: service.session('owner', deviceName: name),
    ),
  );
  final dir = await Directory.systemTemp.createTemp('reconcile-');
  addTearDown(() => dir.delete(recursive: true));
  return (
    sync: Reconciler(
      api: CloudApi(client: service.client, origin: origin, sessions: sessions),
      workspace: workspace,
      state: state,
      scratchDirectory: dir.path,
    ),
    workspace: workspace,
    state: state,
  );
}

void main() {
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
      b.workspace.drafts.clear();
      await b.sync.feedCheck();
      final count = b.workspace.applyCount;
      await b.sync.feedCheck();
      expect(b.workspace.applyCount, count);
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
