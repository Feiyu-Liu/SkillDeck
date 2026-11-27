import 'dart:convert';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/testing.dart';
import 'package:test/test.dart';

import 'reconciler_test.dart' show device, git;

Future<LineageMetadata> cloudMetadata(
  Reconciler sync,
  String lineageId,
) async => (await sync.api.readMetadata(
  lineageId,
) as CloudApiSuccess<LineageMetadata>).value;

Future<List<CloudTag>> cloudTags(Reconciler sync) async =>
    (await sync.api.readTags() as CloudApiSuccess<TagVocabulary>)
        .value
        .tags
        .values
        .toList();

void main() {
  late FakeCloudService service;
  setUp(() {
    service = FakeCloudService(supportsMetadata: true);
    addTearDown(service.client.close);
  });

  test('first association initializes untouched fields and new installs adopt them', () async {
    final a = await device(service, 'A'), b = await device(service, 'B');
    final old = a.workspace.createLocalTag('Existing unused');
    final assigned = a.workspace.createLocalTag('Original', color: '#123456');
    final skill = a.workspace.seed(source: git());
    a.workspace.editMetadata(
      skill.id,
      favorite: true,
      note: 'A note',
      tagIds: [assigned.id],
    );
    await a.sync.rebaselineTagEligibility();
    expect((await a.sync.bootstrap()).completed, isTrue);
    expect(await a.sync.startSyncing(skill.id), isA<SkillSynced>());
    expect((await cloudTags(a.sync)).map((tag) => tag.name), ['Original']);
    final deviceOnly = a.workspace.seed(source: git('local'), name: 'local');
    final newTag = a.workspace.createLocalTag('Created after connection');
    a.workspace.editMetadata(
      deviceOnly.id,
      favorite: false,
      note: null,
      tagIds: [old.id, newTag.id],
    );
    expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
    expect((await cloudTags(a.sync)).map((tag) => tag.name), [
      'Original',
      'Created after connection',
    ]);
    final boot = await b.sync.bootstrap();
    expect(boot.completed, isTrue);
    final installed = boot.installedSkillIds.single;
    final local = await b.workspace.inspectMetadata();
    expect(local.skills[installed]!.favorite, isTrue);
    expect(local.skills[installed]!.note, 'A note');
    expect(local.skills[installed]!.tagIds.map((id) => local.tags[id]!.name), [
      'Original',
    ]);
  });

  test('recovered existing Skill respects edited false/empty fields and keeps a Note versus cloud clear', () async {
    final a = await device(service, 'A');
    final b = await device(service, 'B');
    final skill = a.workspace.seed(source: git());
    await a.sync.bootstrap();
    await a.sync.startSyncing(skill.id);
    final id = (await a.state.links()).single.lineageId!;
    await a.sync.api.writeFavorite(id, expectedVersion: 0, value: true);
    await a.sync.api.writeFavorite(id, expectedVersion: 1, value: false);
    await a.sync.api.writeNote(id, expectedVersion: 0, value: 'previous');
    await a.sync.api.writeNote(id, expectedVersion: 1, value: null);
    final tag = (await a.sync.api.createTag(
      clientKey: 'a' * 64,
      name: 'Shared',
      color: null,
    ) as CloudApiSuccess<CloudTag>).value;
    await a.sync.api.writeAssignment(
      id,
      tag.id,
      expectedVersion: 0,
      assigned: true,
    );
    await a.sync.api.writeAssignment(
      id,
      tag.id,
      expectedVersion: 1,
      assigned: false,
    );

    final old = b.workspace.createLocalTag('Keep local');
    final shared = b.workspace.createLocalTag('Shared');
    final existing = b.workspace.seed(source: git());
    b.workspace.editMetadata(
      existing.id,
      favorite: true,
      note: 'Recovered',
      tagIds: [old.id, shared.id],
    );
    final boot = await b.sync.bootstrap();
    expect(boot.completed, isTrue);
    expect(boot.installedSkillIds, isEmpty);
    final local = await b.workspace.inspectMetadata();
    expect(local.skills[existing.id]!.favorite, isFalse);
    expect(local.skills[existing.id]!.tagIds, isEmpty);
    expect(local.tags, contains(old.id));
    expect(local.skills[existing.id]!.note, 'Recovered');
    final conflict = b.sync.metadataAttention[existing.id]!.note!.conflict!;
    expect(conflict.accepted.text, isNull);
    expect(conflict.incoming.text, 'Recovered');
    expect((await cloudTags(a.sync)).map((tag) => tag.name), ['Shared']);
  });

  test(
    'edited cloud assignments replace old unmapped local Skill assignments',
    () async {
      final a = await device(service, 'A'), b = await device(service, 'B');
      final source = a.workspace.seed(source: git());
      final remoteTag = a.workspace.createLocalTag('Remote assignment');
      a.workspace.editMetadata(
        source.id,
        favorite: false,
        note: null,
        tagIds: [remoteTag.id],
      );
      await a.sync.bootstrap();
      await a.sync.startSyncing(source.id);

      final existing = b.workspace.seed(source: git());
      final unrelated = b.workspace.seed(source: git('local'), name: 'local');
      final localTag = b.workspace.createLocalTag('Old local tag');
      for (final skill in [existing, unrelated]) {
        b.workspace.editMetadata(
          skill.id,
          favorite: false,
          note: null,
          tagIds: [localTag.id],
        );
      }
      final boot = await b.sync.bootstrap();
      expect(boot.completed, isTrue);
      expect(boot.installedSkillIds, isEmpty);
      final local = await b.workspace.inspectMetadata();
      expect(
        local.skills[existing.id]!.tagIds.map((id) => local.tags[id]!.name),
        ['Remote assignment'],
      );
      expect(local.skills[unrelated.id]!.tagIds, {localTag.id});
      expect(local.tags, contains(localTag.id));
      expect((await cloudTags(a.sync)).map((tag) => tag.name), [
        'Remote assignment',
      ]);
    },
  );

  test(
    'an assignment made during initial cloud apply remains pending',
    () async {
      final a = await device(service, 'A'), b = await device(service, 'B');
      final source = a.workspace.seed(source: git());
      final cloudTag = a.workspace.createLocalTag('Cloud');
      a.workspace.editMetadata(
        source.id,
        favorite: false,
        note: null,
        tagIds: [cloudTag.id],
      );
      await a.sync.bootstrap();
      await a.sync.startSyncing(source.id);

      final existing = b.workspace.seed(source: git());
      final old = b.workspace.createLocalTag('Old');
      final added = b.workspace.createLocalTag('Added during apply');
      b.workspace.editMetadata(
        existing.id,
        favorite: false,
        note: null,
        tagIds: [old.id],
      );
      b.workspace.beforeMetadataApply = () {
        b.workspace.beforeMetadataApply = null;
        b.workspace.editMetadata(
          existing.id,
          favorite: false,
          note: null,
          tagIds: [old.id, added.id],
        );
      };
      expect((await b.sync.bootstrap()).completed, isTrue);
      final local = await b.workspace.inspectMetadata();
      expect(
        local.skills[existing.id]!.tagIds.map((id) => local.tags[id]!.name),
        unorderedEquals(['Cloud', 'Added during apply']),
      );
      expect((await b.sync.checkLocalChanges()).succeeded, isTrue);
      final vocabulary = {
        for (final tag in await cloudTags(a.sync)) tag.id: tag.name,
      };
      final id = (await a.state.links()).single.lineageId!;
      final metadata = await cloudMetadata(a.sync, id);
      expect(
        metadata.assignments.keys.map((id) => vocabulary[id]),
        unorderedEquals(['Cloud', 'Added during apply']),
      );
    },
  );

  test('old service fallback discovers upgrade without replacing existing Feed cursor', () async {
    service.supportsMetadata = false;
    final a = await device(service, 'A'), b = await device(service, 'B');
    final skill = a.workspace.seed(source: git());
    await a.sync.startSyncing(skill.id);
    await a.sync.bootstrap();
    expect(a.sync.metadataUnavailable, isTrue);
    final priorCursor = (await a.state.feedCursor())!;
    a.workspace.editMetadata(
      skill.id,
      favorite: true,
      note: 'legacy local',
      tagIds: [],
    );
    await a.sync.checkLocalChanges();
    service.supportsMetadata = true;
    await b.sync.bootstrap();
    final bSkill = (await b.workspace.listSkills()).single;
    b.workspace.publish(bSkill.id, {'new.txt': 'an update after old cursor'});
    await b.sync.reconcileSkill(bSkill.id);
    final observedAfter = <String?>[];
    service.beforeRequest = (request) async {
      if (request.url.path == '/v0/feed') {
        observedAfter.add(request.url.queryParameters['after']);
      }
    };
    expect((await a.sync.feedCheck()).succeeded, isTrue);
    expect(a.sync.metadataUnavailable, isFalse);
    expect(observedAfter.first, priorCursor);
    expect(
      a.workspace.files(skill.id),
      containsPair('new.txt', 'an update after old cursor'),
    );
    final remote = await cloudMetadata(
      a.sync,
      (await a.state.links()).single.lineageId!,
    );
    expect(remote.favorite.value, isTrue);
    expect(remote.note.value, 'legacy local');
  });

  test(
    'local edits during field HTTP and guarded metadata apply are preserved',
    () async {
      final a = await device(service, 'A'), b = await device(service, 'B');
      final skill = a.workspace.seed(source: git());
      await a.sync.bootstrap();
      await a.sync.startSyncing(skill.id);
      final bId = (await b.sync.bootstrap()).installedSkillIds.single;
      final lineage = (await a.state.links()).single.lineageId!;

      a.workspace.editMetadata(
        skill.id,
        favorite: true,
        note: null,
        tagIds: [],
      );
      service.beforeRequest = (request) async {
        if (request.method == 'PUT' && request.url.path.endsWith('/favorite')) {
          service.beforeRequest = null;
          a.workspace.editMetadata(
            skill.id,
            favorite: false,
            note: null,
            tagIds: [],
          );
        }
      };
      expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
      expect((await cloudMetadata(a.sync, lineage)).favorite.value, isFalse);

      await a.sync.api.writeFavorite(lineage, expectedVersion: 2, value: true);
      b.workspace.beforeMetadataApply = () {
        b.workspace.beforeMetadataApply = null;
        b.workspace.editMetadata(
          bId,
          favorite: false,
          note: 'CLI note',
          tagIds: [],
        );
      };
      expect((await b.sync.feedCheck()).succeeded, isTrue);
      final local = (await b.workspace.inspectMetadata()).skills[bId]!;
      expect(local.favorite, isTrue);
      expect(local.note, 'CLI note');
      expect((await cloudMetadata(a.sync, lineage)).note.value, 'CLI note');
    },
  );

  test(
    'synced content can have a pending Note until the next successful check',
    () async {
      final a = await device(service, 'A');
      final skill = a.workspace.seed(source: git());
      await a.sync.bootstrap();
      await a.sync.startSyncing(skill.id);
      final id = (await a.state.links()).single.lineageId!;
      a.workspace.editMetadata(
        skill.id,
        favorite: false,
        note: 'Pending Note',
        tagIds: [],
      );
      service.failNext(
        path: '/v0/lineages/$id/metadata/note',
        method: 'PUT',
        status: 503,
      );
      expect(await a.sync.reconcileSkill(skill.id), isA<SkillSynced>());
      expect(a.sync.outcomes[skill.id], isA<SkillSynced>());
      expect(a.sync.metadataWaitingSkillIds, {skill.id});
      expect(a.sync.metadataAttention, isEmpty);
      expect((await cloudMetadata(a.sync, id)).note.value, isNull);

      expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
      expect(a.sync.metadataWaitingSkillIds, isEmpty);
      expect((await cloudMetadata(a.sync, id)).note.value, 'Pending Note');
    },
  );

  test('a failed metadata bootstrap marks linked Skills and retries without new local edits', () async {
    final a = await device(service, 'A');
    final skill = a.workspace.seed(source: git());
    await a.sync.bootstrap();
    await a.sync.startSyncing(skill.id);
    expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
    final id = (await a.state.links()).single.lineageId!;

    service.failNext(path: '/v0/library', status: 503);
    expect((await a.sync.bootstrap(reset: true)).completed, isFalse);
    expect(a.sync.metadataWaitingSkillIds, {skill.id});
    final before = service.requests.length;
    expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
    expect(
      service.requests.skip(before).map((request) => request.path),
      contains('/v0/lineages/$id/metadata'),
    );
    expect(a.sync.metadataWaitingSkillIds, isEmpty);

    service.failNext(path: '/v0/library', status: 503);
    expect((await a.sync.bootstrap(reset: true)).completed, isFalse);
    expect(a.sync.metadataWaitingSkillIds, {skill.id});
    expect(await a.sync.stopSyncing(skill.id), isA<SkillDeviceOnly>());
    expect(a.sync.metadataWaitingSkillIds, isEmpty);
  });

  test('lost Note conflict and resolution responses settle; third text survives pair resolution and restart', () async {
    final a = await device(service, 'A'),
        b = await device(service, 'B'),
        c = await device(service, 'C');
    final skill = a.workspace.seed(source: git());
    await a.sync.bootstrap();
    await a.sync.startSyncing(skill.id);
    final bId = (await b.sync.bootstrap()).installedSkillIds.single;
    final cId = (await c.sync.bootstrap()).installedSkillIds.single;
    final lineage = (await a.state.links()).single.lineageId!;
    a.workspace.editMetadata(
      skill.id,
      favorite: false,
      note: 'accepted',
      tagIds: [],
    );
    await a.sync.checkLocalChanges();
    b.workspace.editMetadata(bId, favorite: true, note: 'incoming', tagIds: []);
    service.failNext(
      path: '/v0/lineages/$lineage/metadata/note/conflicts',
      afterCommit: true,
    );
    expect((await b.sync.checkLocalChanges()).succeeded, isFalse);
    expect((await b.sync.checkLocalChanges()).succeeded, isTrue);
    final pair = b.sync.metadataAttention[bId]!;
    expect(pair.note!.conflict!.accepted.text, 'accepted');
    expect(pair.note!.conflict!.incoming.text, 'incoming');
    expect((await cloudMetadata(a.sync, lineage)).favorite.value, isTrue);

    c.workspace.editMetadata(cId, favorite: false, note: 'third', tagIds: []);
    await c.sync.checkLocalChanges();
    expect(c.sync.metadataAttention[cId]!.hasUnsubmittedLocalNote, isTrue);
    service.failNext(
      path: '/v0/lineages/$lineage/metadata/note/resolve',
      afterCommit: true,
    );
    expect(
      await b.sync.resolveNoteConflict(
        bId,
        expectedVersion: pair.note!.version,
        expectedLocalNote: 'incoming',
        value: 'merged',
      ),
      isA<SkillSynced>(),
    );
    expect((await b.workspace.inspectMetadata()).skills[bId]!.note, 'merged');

    final saved = jsonDecode(
      jsonEncode((await c.state.metadataState()).toJson()),
    ) as Map<String, Object?>;
    await c.state.setMetadataState(SyncMetadataState.fromJson(saved));
    final restored = await device(
      service,
      'C',
      existingWorkspace: c.workspace,
      existingState: c.state,
    );
    expect((await restored.sync.feedCheck()).succeeded, isTrue);
    final third = restored.sync.metadataAttention[cId]!;
    expect(third.note!.value, 'merged');
    expect(third.note!.conflict, isNull);
    expect(third.localNote, 'third');
    expect(third.hasUnsubmittedLocalNote, isTrue);
    expect(
      await restored.sync.resolveNoteConflict(
        cId,
        expectedVersion: third.note!.version,
        expectedLocalNote: 'third',
        value: 'merged plus third',
      ),
      isA<SkillSynced>(),
    );
    expect(
      (await cloudMetadata(a.sync, lineage)).note.value,
      'merged plus third',
    );
  });

  test('failed resolution preserves locally chosen text and does not acknowledge a newer edit', () async {
    final a = await device(service, 'A'), b = await device(service, 'B');
    final skill = a.workspace.seed(source: git());
    await a.sync.bootstrap();
    await a.sync.startSyncing(skill.id);
    final other = (await b.sync.bootstrap()).installedSkillIds.single;
    final id = (await a.state.links()).single.lineageId!;
    await a.sync.api.writeNote(id, expectedVersion: 0, value: 'initial');
    await a.sync.api.openNoteConflict(id, expectedVersion: 1, value: 'other');
    await b.sync.feedCheck();
    final displayed = b.sync.metadataAttention[other]!;
    service.failNext(
      path: '/v0/lineages/$id/metadata/note/resolve',
      status: 429,
      retryAfter: const Duration(seconds: 60),
    );
    expect(
      await b.sync.resolveNoteConflict(
        other,
        expectedVersion: displayed.note!.version,
        expectedLocalNote: displayed.localNote,
        value: 'saved locally',
      ),
      isA<WaitingToUpload>(),
    );
    expect(
      (await b.workspace.inspectMetadata()).skills[other]!.note,
      'saved locally',
    );
    expect(b.sync.metadataAttention[other]!.localNote, 'saved locally');

    service.beforeRequest = (request) async {
      if (request.url.path.endsWith('/resolve')) {
        service.beforeRequest = null;
        expect(
          (await b.workspace.inspectMetadata()).skills[other]!.note,
          'second choice',
        );
        b.workspace.editMetadata(
          other,
          favorite: false,
          note: 'new edit',
          tagIds: [],
        );
      }
    };
    expect(
      await b.sync.resolveNoteConflict(
        other,
        expectedVersion: displayed.note!.version,
        expectedLocalNote: 'saved locally',
        value: 'second choice',
      ),
      isA<WaitingToUpload>(),
    );
    expect((await cloudMetadata(a.sync, id)).note.value, 'second choice');
    expect(b.sync.metadataAttention[other]!.localNote, 'new edit');
  });

  for (final change in ['rename', 'merge', 'delete']) {
    test(
      'lost tag create response followed by $change does not recreate tag',
      () async {
        final a = await device(service, 'A'), b = await device(service, 'B');
        await a.sync.bootstrap();
        await b.sync.bootstrap();
        final original = a.workspace.createLocalTag('Original');
        final localOnly = a.workspace.seed(source: git('local'), name: 'local');
        a.workspace.editMetadata(
          localOnly.id,
          favorite: false,
          note: null,
          tagIds: [original.id],
        );
        service.failNext(path: '/v0/tags', method: 'POST', afterCommit: true);
        expect((await a.sync.checkLocalChanges()).succeeded, isFalse);
        final before = await a.state.metadataState();
        expect(before.eligibleTagIds, contains(original.id));
        expect(before.tags, isEmpty);
        final target = (await cloudTags(b.sync)).single;
        switch (change) {
          case 'rename':
            await b.sync.api.renameTag(
              target.id,
              expectedVersion: target.nameVersion,
              name: 'Renamed',
            );
          case 'merge':
            final destination = (await b.sync.api.createTag(
              clientKey: 'c' * 64,
              name: 'Survivor',
              color: '#AABBCC',
            ) as CloudApiSuccess<CloudTag>).value;
            await b.sync.api.renameTag(
              target.id,
              expectedVersion: target.nameVersion,
              name: destination.name,
            );
          case 'delete':
            await b.sync.api.deleteTag(
              target.id,
              expectedVersion: target.version,
            );
        }
        expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
        expect((await a.sync.feedCheck()).succeeded, isTrue);
        final remote = await cloudTags(b.sync);
        final local = await a.workspace.inspectMetadata();
        expect(remote.map((tag) => tag.name), switch (change) {
          'rename' => ['Renamed'],
          'merge' => ['Survivor'],
          _ => [],
        });
        expect(
          local.tags.values.map((tag) => tag.name),
          remote.map((tag) => tag.name),
        );
        expect(
          local.skills[localOnly.id]!.tagIds.length,
          change == 'delete' ? 0 : 1,
        );
      },
    );
  }

  test('account switch ignores preexisting unrelated tags and restart keeps eligible offline tags', () async {
    final a = await device(service, 'A'),
        ignored = a.workspace.createLocalTag('Initial');
    await a.sync.rebaselineTagEligibility();
    await a.sync.bootstrap();
    a.workspace.createLocalTag('Account A');
    await a.sync.checkLocalChanges();
    final other = await device(
      service,
      'B',
      account: 'other',
      existingWorkspace: a.workspace,
    );
    await other.sync.rebaselineTagEligibility();
    await other.sync.bootstrap();
    expect(await cloudTags(other.sync), isEmpty);
    expect((await a.workspace.inspectMetadata()).tags, contains(ignored.id));
    other.workspace.createLocalTag('Offline new');
    final restarted = await device(
      service,
      'B',
      account: 'other',
      existingWorkspace: other.workspace,
      existingState: other.state,
    );
    await restarted.sync.feedCheck();
    await restarted.sync.checkLocalChanges();
    expect((await cloudTags(restarted.sync)).map((tag) => tag.name), [
      'Offline new',
    ]);
    expect((await cloudTags(a.sync)).map((tag) => tag.name), ['Account A']);
  });

  test(
    'tag quota and over-limit Note settle cursors, then retry when corrected',
    () async {
      final a = await device(service, 'A');
      final skill = a.workspace.seed(source: git());
      await a.sync.bootstrap();
      await a.sync.startSyncing(skill.id);
      final first = a.workspace.createLocalTag('First');
      service.maxTags = 0;
      a.workspace.editMetadata(
        skill.id,
        favorite: true,
        note: '界' * 1500,
        tagIds: [],
      );
      expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
      expect(await a.state.workspaceCursor(), isNotNull);
      expect(a.sync.vocabularyAttention[first.id], MetadataLimit.vocabulary);
      expect(
        a.sync.metadataAttention[skill.id]!.reason,
        MetadataAttentionReason.noteTooLarge,
      );
      final id = (await a.state.links()).single.lineageId!;
      expect((await cloudMetadata(a.sync, id)).favorite.value, isTrue);
      service.maxTags = 1;
      expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
      expect(a.sync.vocabularyAttention, isEmpty);
      a.workspace.editMetadata(
        skill.id,
        favorite: true,
        note: 'fits',
        tagIds: [first.id],
      );
      expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
      expect((await cloudMetadata(a.sync, id)).note.value, 'fits');
      expect(a.sync.metadataAttention, isEmpty);
    },
  );

  test('tag quota stops further new creates in a pass and retries after capacity returns', () async {
    final a = await device(service, 'A');
    await a.sync.bootstrap();
    service.maxTags = 2;
    final mapped = a.workspace.createLocalTag('Mapped');
    await a.sync.checkLocalChanges();
    await a.sync.api.createTag(
      clientKey: 'a' * 64,
      name: 'Duplicate',
      color: null,
    );
    final duplicate = a.workspace.createLocalTag('duplicate');
    a.workspace.editTag(mapped.id, name: 'Renamed', color: null);
    final newTags = [
      for (var i = 0; i < 4; i++) a.workspace.createLocalTag('New $i'),
    ];
    int creates() => service.requests
        .where((r) => r.path == '/v0/tags' && r.method == 'POST')
        .length;

    final before = creates();
    expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
    expect(creates() - before, 2); // One duplicate and one rejected new tag.
    expect(a.sync.vocabularyAttention, {
      for (final tag in newTags) tag.id: MetadataLimit.vocabulary,
    });
    final local = await a.workspace.inspectMetadata();
    expect(local.tags[duplicate.id]?.name, 'Duplicate');
    expect(
      (await cloudTags(a.sync)).map((tag) => tag.name),
      unorderedEquals(['Renamed', 'Duplicate']),
    );

    service.maxTags = 6;
    final blocked = creates();
    expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
    expect(creates() - blocked, newTags.length);
    expect(a.sync.vocabularyAttention, isEmpty);
    expect(await cloudTags(a.sync), hasLength(6));
  });

  test(
    'draft content attention and Note conflict settle alongside other Skills',
    () async {
      final a = await device(service, 'A'), b = await device(service, 'B');
      final one = a.workspace.seed(source: git('one'), name: 'one');
      final two = a.workspace.seed(source: git('two'), name: 'two');
      await a.sync.bootstrap();
      await a.sync.startSyncing(one.id);
      await a.sync.startSyncing(two.id);
      await b.sync.bootstrap();
      final other = await b.workspace.listSkills();
      final bOne = other.firstWhere((skill) => skill.declaredName == 'one');
      final bTwo = other.firstWhere((skill) => skill.declaredName == 'two');
      b.workspace.drafts.add(bOne.id);
      final id = (await a.state.links())
          .firstWhere((link) => link.managedSkillId == one.id)
          .lineageId!;
      await a.sync.api.writeNote(id, expectedVersion: 0, value: 'remote');
      await a.sync.api.openNoteConflict(
        id,
        expectedVersion: 1,
        value: 'alternate',
      );
      a.workspace.publish(one.id, {'draft-blocked.txt': 'new content'});
      await a.sync.reconcileSkill(one.id);
      a.workspace.editMetadata(
        two.id,
        favorite: true,
        note: 'unblocked',
        tagIds: [],
      );
      await a.sync.checkLocalChanges();
      expect((await b.sync.feedCheck()).succeeded, isTrue);
      expect(
        (b.sync.outcomes[bOne.id] as SyncNeedsAttention).reason,
        AttentionReason.incomingDraft,
      );
      expect(
        b.sync.metadataAttention[bOne.id]!.reason,
        MetadataAttentionReason.noteConflict,
      );
      expect(
        (await b.workspace.inspectMetadata()).skills[bTwo.id]!.note,
        'unblocked',
      );
    },
  );

  test('switching back does not import another account tag assigned to a linked Skill', () async {
    final a = await device(service, 'Account A');
    final skill = a.workspace.seed(source: git());
    await a.sync.rebaselineTagEligibility();
    await a.sync.bootstrap();
    await a.sync.startSyncing(skill.id);
    await a.sync.checkLocalChanges();
    final b = await device(
      service,
      'Account B',
      account: 'other',
      existingWorkspace: a.workspace,
    );
    await b.sync.rebaselineTagEligibility();
    await b.sync.bootstrap();
    final other = b.workspace.createLocalTag('Other account tag');
    b.workspace.editMetadata(
      skill.id,
      favorite: false,
      note: null,
      tagIds: [other.id],
    );
    await b.sync.checkLocalChanges();
    expect((await cloudTags(b.sync)).map((tag) => tag.name), [
      'Other account tag',
    ]);

    final returned = await device(
      service,
      'Account A',
      existingWorkspace: a.workspace,
      existingState: a.state,
    );
    await returned.sync.rebaselineTagEligibility();
    expect((await returned.sync.feedCheck()).succeeded, isTrue);
    expect((await returned.sync.checkLocalChanges()).succeeded, isTrue);
    expect(await cloudTags(returned.sync), isEmpty);
    expect(
      (await returned.workspace.inspectMetadata()).skills[skill.id]!.tagIds,
      {other.id},
    );
  });

  test('switching back resumes an eligible tag and keeps another account tag local', () async {
    final a = await device(service, 'Account A');
    final skill = a.workspace.seed(source: git());
    await a.sync.rebaselineTagEligibility();
    await a.sync.bootstrap();
    await a.sync.startSyncing(skill.id);
    service.maxTags = 0;
    final pending = a.workspace.createLocalTag('A pending');
    expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
    expect(a.sync.vocabularyAttention[pending.id], MetadataLimit.vocabulary);

    final b = await device(
      service,
      'Account B',
      account: 'other',
      existingWorkspace: a.workspace,
    );
    await b.sync.rebaselineTagEligibility();
    await b.sync.bootstrap();
    service.maxTags = 2;
    final newTag = b.workspace.createLocalTag('B new');
    expect((await b.sync.checkLocalChanges()).succeeded, isTrue);
    expect((await cloudTags(b.sync)).map((tag) => tag.name), ['B new']);

    final returned = await device(
      service,
      'Account A',
      existingWorkspace: a.workspace,
      existingState: a.state,
    );
    await returned.sync.rebaselineTagEligibility();
    expect((await returned.sync.feedCheck()).succeeded, isTrue);
    expect((await returned.sync.checkLocalChanges()).succeeded, isTrue);
    expect((await cloudTags(returned.sync)).map((tag) => tag.name), [
      'A pending',
    ]);
    expect(
      (await returned.workspace.inspectMetadata()).tags,
      contains(newTag.id),
    );

    returned.workspace.editMetadata(
      skill.id,
      favorite: false,
      note: null,
      tagIds: [newTag.id],
    );
    expect((await returned.sync.checkLocalChanges()).succeeded, isTrue);
    final vocabulary = await cloudTags(returned.sync);
    final shared = vocabulary.singleWhere((tag) => tag.name == 'B new');
    final id = (await returned.state.links()).single.lineageId!;
    expect((await cloudMetadata(returned.sync, id)).assignments.keys, [
      shared.id,
    ]);
  });

  test('a new live cloud tag can reuse a vacated name without inheriting assignments', () async {
    final a = await device(service, 'A'), b = await device(service, 'B');
    final skill = a.workspace.seed(source: git());
    final original = a.workspace.createLocalTag('Original');
    a.workspace.editMetadata(
      skill.id,
      favorite: false,
      note: null,
      tagIds: [original.id],
    );
    await a.sync.bootstrap();
    await a.sync.startSyncing(skill.id);
    final other = (await b.sync.bootstrap()).installedSkillIds.single;
    final source = (await cloudTags(a.sync)).single;
    await a.sync.api.renameTag(
      source.id,
      expectedVersion: source.nameVersion,
      name: 'Renamed',
    );
    await a.sync.api.createTag(
      clientKey: 'c' * 64,
      name: 'Original',
      color: null,
    );
    expect((await b.sync.feedCheck()).succeeded, isTrue);
    final local = await b.workspace.inspectMetadata();
    expect(
      local.tags.values.map((tag) => tag.name),
      unorderedEquals(['Original', 'Renamed']),
    );
    expect(local.skills[other]!.tagIds.map((id) => local.tags[id]!.name), [
      'Renamed',
    ]);
  });

  test('remote merge transfers local-only assignments and preserves survivor edits during apply', () async {
    final a = await device(service, 'A'), b = await device(service, 'B');
    await a.sync.bootstrap();
    final source = a.workspace.createLocalTag('Source');
    a.workspace.createLocalTag('Survivor', color: '#111111');
    await a.sync.checkLocalChanges();
    final bSkill = b.workspace.seed(source: git());
    await b.sync.bootstrap();
    final tags = (await b.workspace.inspectMetadata()).tags.values;
    final localSource = tags.firstWhere((tag) => tag.name == 'Source');
    final localSurvivor = tags.firstWhere((tag) => tag.name == 'Survivor');
    b.workspace.editMetadata(
      bSkill.id,
      favorite: false,
      note: null,
      tagIds: [localSource.id],
    );
    final remote = (await cloudTags(a.sync))
        .firstWhere((tag) => tag.name == source.name);
    await a.sync.api.renameTag(
      remote.id,
      expectedVersion: remote.nameVersion,
      name: 'Survivor',
    );
    b.workspace.beforeTagApply = () {
      b.workspace.beforeTagApply = null;
      b.workspace.editTag(
        localSurvivor.id,
        name: 'Local survivor rename',
        color: '#222222',
      );
    };
    expect((await b.sync.feedCheck()).succeeded, isTrue);
    final local = await b.workspace.inspectMetadata();
    expect(local.tags.values.single.name, 'Local survivor rename');
    expect(local.tags.values.single.color, '#222222');
    expect(local.skills[bSkill.id]!.tagIds, {localSurvivor.id});
    final server = (await cloudTags(a.sync)).single;
    expect(server.name, 'Local survivor rename');
    expect(server.color, '#222222');
  });

  test('retry after is preserved when capability probe or metadata write is throttled', () async {
    const delay = Duration(seconds: 45);
    final a = await device(service, 'A');
    service.failNext(path: '/v0/tags', status: 429, retryAfter: delay);
    final boot = await a.sync.bootstrap();
    expect(boot.completed, isFalse);
    expect(boot.retryAfter, delay);
    expect(
      service.requests.where((request) => request.path == '/v0/library'),
      isEmpty,
    );
    await a.sync.bootstrap();
    final skill = a.workspace.seed(source: git());
    await a.sync.startSyncing(skill.id);
    await a.sync.checkLocalChanges();
    a.workspace.editMetadata(
      skill.id,
      favorite: true,
      note: 'also pending',
      tagIds: [],
    );
    final id = (await a.state.links()).single.lineageId!;
    service.failNext(
      path: '/v0/lineages/$id/metadata/favorite',
      status: 429,
      retryAfter: delay,
    );
    final result = await a.sync.checkLocalChanges();
    expect(result.succeeded, isFalse);
    expect(result.retryAfter, delay);
    expect((await cloudMetadata(a.sync, id)).note.value, isNull);
    expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
    expect((await cloudMetadata(a.sync, id)).note.value, 'also pending');
  });

  test('offline rename cycle keeps both tag identities, Device Only assignments and a racing color', () async {
    final a = await device(service, 'A'), b = await device(service, 'B');
    await a.sync.bootstrap();
    a.workspace.createLocalTag('First', color: '#111111');
    a.workspace.createLocalTag('Second', color: '#222222');
    await a.sync.checkLocalChanges();
    await b.sync.bootstrap();
    final deviceOnlyFirst = b.workspace.seed(source: git('one'), name: 'one');
    final deviceOnlySecond = b.workspace.seed(source: git('two'), name: 'two');
    final localTags = (await b.workspace.inspectMetadata()).tags.values;
    final localFirst = localTags.firstWhere((tag) => tag.name == 'First');
    final localSecond = localTags.firstWhere((tag) => tag.name == 'Second');
    b.workspace.editMetadata(
      deviceOnlyFirst.id,
      favorite: false,
      note: null,
      tagIds: [localFirst.id],
    );
    b.workspace.editMetadata(
      deviceOnlySecond.id,
      favorite: false,
      note: null,
      tagIds: [localSecond.id],
    );

    final remoteTags = await cloudTags(a.sync);
    final first = remoteTags.firstWhere((tag) => tag.name == 'First');
    final second = remoteTags.firstWhere((tag) => tag.name == 'Second');
    await a.sync.api.renameTag(first.id, expectedVersion: 1, name: 'Middle');
    await a.sync.api.renameTag(second.id, expectedVersion: 1, name: 'First');
    await a.sync.api.renameTag(first.id, expectedVersion: 2, name: 'Second');
    b.workspace.beforeTagApply = () {
      b.workspace.beforeTagApply = null;
      b.workspace.editTag(
        localFirst.id,
        name: localFirst.name,
        color: '#ABCDEF',
      );
    };
    expect((await b.sync.feedCheck()).succeeded, isTrue);
    final local = await b.workspace.inspectMetadata();
    expect(local.tags[localFirst.id]!.name, 'Second');
    expect(local.tags[localFirst.id]!.color, '#ABCDEF');
    expect(local.tags[localSecond.id]!.name, 'First');
    expect(local.tags[localSecond.id]!.color, '#222222');
    expect(local.skills[deviceOnlyFirst.id]!.tagIds, {localFirst.id});
    expect(local.skills[deviceOnlySecond.id]!.tagIds, {localSecond.id});
    expect(
      (await cloudTags(a.sync)).firstWhere((tag) => tag.id == first.id).color,
      '#ABCDEF',
    );
  });

  test(
    'metadata API rejects invalid local path identifiers before any HTTP',
    () async {
      final a = await device(service, 'A');
      final api = a.sync.api;
      for (final suffix in ['?x=1', '#fragment', '/path', '%2F', '\n']) {
        final id = 'valid$suffix';
        for (final call in <Object? Function()>[
          () => api.readTag(id),
          () => api.renameTag(id, expectedVersion: 1, name: 'name'),
          () => api.recolorTag(id, expectedVersion: 1, color: null),
          () => api.deleteTag(id, expectedVersion: 1),
          () => api.readAssignment('lineage', id),
          () => api.writeAssignment(
            'lineage',
            id,
            expectedVersion: 0,
            assigned: true,
          ),
          () => api.readMetadata(id),
          () => api.readFavorite(id),
          () => api.writeFavorite(id, expectedVersion: 0, value: true),
          () => api.readAssignment(id, 'tag'),
          () => api.readNote(id),
          () => api.writeNote(id, expectedVersion: 0, value: null),
          () => api.openNoteConflict(id, expectedVersion: 1, value: ''),
          () => api.resolveNote(id, expectedVersion: 1, value: null),
        ]) {
          expect(call, throwsArgumentError);
        }
      }
      expect(service.requests, isEmpty);
    },
  );

  test('restart derives queued vocabulary changes from state after local cursor settled', () async {
    final a = await device(service, 'A');
    await a.sync.bootstrap();
    final mapped = a.workspace.createLocalTag('Mapped');
    await a.sync.checkLocalChanges();
    // Quota and size settle local cursors and leave their values in Workspace.
    service.maxTags = 1;
    final blocked = a.workspace.createLocalTag('Quota blocked');
    a.workspace.editTag(mapped.id, name: '界' * 65, color: null);
    expect((await a.sync.checkLocalChanges()).succeeded, isTrue);
    expect(a.sync.vocabularyAttention, {
      mapped.id: MetadataLimit.name,
      blocked.id: MetadataLimit.vocabulary,
    });
    expect((await a.sync.feedCheck()).succeeded, isTrue);
    final savedMetadata = jsonDecode(
      jsonEncode((await a.state.metadataState()).toJson()),
    ) as Map<String, Object?>;
    await a.state.setMetadataState(SyncMetadataState.fromJson(savedMetadata));
    final restored = await device(
      service,
      'A',
      existingWorkspace: a.workspace,
      existingState: a.state,
    );
    service.maxTags = 2;
    expect((await restored.sync.feedCheck()).succeeded, isTrue);
    expect(restored.sync.vocabularyAttention, {mapped.id: MetadataLimit.name});
    expect(
      (await cloudTags(restored.sync)).map((tag) => tag.name),
      unorderedEquals(['Mapped', 'Quota blocked']),
    );
  });

  for (final status in [401, 429, 200]) {
    test(
      'Note resolution preserves choice when recovery sees HTTP $status',
      () async {
        final a = await device(service, 'A');
        final skill = a.workspace.seed(source: git());
        await a.sync.bootstrap();
        await a.sync.startSyncing(skill.id);
        final id = (await a.state.links()).single.lineageId!;
        await a.sync.api.writeNote(id, expectedVersion: 0, value: 'First');
        await a.sync.api.openNoteConflict(
          id,
          expectedVersion: 1,
          value: 'Second',
        );
        await a.sync.feedCheck();
        final shown = a.sync.metadataAttention[skill.id]!;
        final notePath = '/v0/lineages/$id/metadata/note';
        final start = service.requests.length;
        const retryAfter = Duration(seconds: 63);
        service.failNext(
          path: '$notePath/resolve',
          method: 'POST',
          status: status == 200 ? 200 : 503,
        );
        if (status != 200) {
          service.failNext(
            path: notePath,
            method: 'GET',
            status: status,
            retryAfter: status == 429 ? retryAfter : null,
          );
        }
        final resolution = a.sync.resolveNoteConflict(
          skill.id,
          expectedVersion: shown.note!.version,
          expectedLocalNote: shown.localNote,
          value: 'Local choice',
        );
        switch (status) {
          case 401:
            final outcome = await resolution as SyncAccountCondition;
            expect(outcome.condition, isA<ApiSignInRequired>());
            expect(
              a.sync.accountCondition?.condition,
              isA<ApiSignInRequired>(),
            );
          case 429:
            final outcome = await resolution as WaitingToUpload;
            expect(outcome.retryAfter, retryAfter);
          default:
            await expectLater(
              resolution,
              throwsA(
                isA<StateError>().having(
                  (error) => error.message,
                  'message',
                  'cloud_protocol',
                ),
              ),
            );
            expect(
              service.requests
                  .skip(start)
                  .where((request) => request.path == notePath),
              isEmpty,
            );
        }
        expect(
          (await a.workspace.inspectMetadata()).skills[skill.id]!.note,
          'Local choice',
        );
        expect(a.sync.metadataAttention[skill.id]!.localNote, 'Local choice');
      },
    );
  }

  for (final sameValue in [false, true]) {
    test(
      '${sameValue ? 'equal' : 'different'} Note after rollback rebases the metadata feed',
      () async {
        final a = await device(service, 'A');
        final skill = a.workspace.seed(source: git());
        await a.sync.bootstrap();
        await a.sync.startSyncing(skill.id);
        final id = (await a.state.links()).single.lineageId!;
        await a.sync.api.writeNote(id, expectedVersion: 0, value: 'Original');
        expect((await a.sync.feedCheck()).succeeded, isTrue);
        final priorCursor = (await a.state.feedCursor())!;
        final priorMetadata = await cloudMetadata(a.sync, id);

        final latest = sameValue ? 'Original' : 'Last agreed';
        var version = priorMetadata.note.version;
        for (final note in [
          'A later edit',
          'Another edit',
          'Third edit',
          latest,
        ]) {
          expect(
            await a.sync.api.writeNote(
              id,
              expectedVersion: version++,
              value: note,
            ),
            isA<CloudApiSuccess<CloudNote>>(),
          );
        }
        expect((await a.sync.feedCheck()).succeeded, isTrue);
        expect(
          (await a.workspace.inspectMetadata()).skills[skill.id]!.note,
          latest,
        );
        final futureCursor = (await a.state.feedCursor())!;
        service.restoreNote('owner', priorMetadata, priorCursor);
        expect(
          await a.sync.api.checkFeed(after: futureCursor),
          isA<ApiCursorExpired>(),
        );
        expect((await a.sync.feedCheck()).succeeded, isTrue);
        expect(await a.state.feedCursor(), priorCursor);
        expect(
          (await a.workspace.inspectMetadata()).skills[skill.id]!.note,
          latest,
        );
        if (sameValue) {
          expect(a.sync.metadataAttention[skill.id], isNull);
        } else {
          final conflict = a.sync.metadataAttention[skill.id]!.note!.conflict!;
          expect(conflict.accepted.text, 'Original');
          expect(conflict.incoming.text, latest);
        }

        await a.sync.api.writeFavorite(id, expectedVersion: 0, value: true);
        expect((await a.sync.feedCheck()).succeeded, isTrue);
        expect(
          (await a.workspace.inspectMetadata()).skills[skill.id]!.favorite,
          isTrue,
        );
      },
    );
  }

  for (final pendingEdit in [false, true]) {
    test(
      'Tag version rollback with ${pendingEdit ? 'a pending local edit' : 'no pending edit'} settles reset',
      () async {
        final a = await device(service, 'A');
        await a.sync.bootstrap();
        final initial = (await a.sync.api.createTag(
          clientKey: 'a' * 64,
          name: 'Original',
          color: '#112233',
        ) as CloudApiSuccess<CloudTag>).value;
        expect((await a.sync.feedCheck()).succeeded, isTrue);
        final priorCursor = (await a.state.feedCursor())!;
        final localId = (await a.workspace.inspectMetadata()).tags.keys.single;
        await a.sync.api.renameTag(
          initial.id,
          expectedVersion: 1,
          name: 'Newer',
        );
        await a.sync.api.recolorTag(
          initial.id,
          expectedVersion: 1,
          color: '#445566',
        );
        expect((await a.sync.feedCheck()).succeeded, isTrue);
        final futureCursor = (await a.state.feedCursor())!;

        if (pendingEdit) {
          a.workspace.editTag(localId, name: 'Local edit', color: '#445566');
        }
        service.restoreTag('owner', initial, priorCursor);
        expect(
          await a.sync.api.checkFeed(after: futureCursor),
          isA<ApiCursorExpired>(),
        );
        expect((await a.sync.feedCheck()).succeeded, isTrue);
        final after = (await a.workspace.inspectMetadata()).tags.values.single;
        expect(after.id, localId);
        expect(after.name, pendingEdit ? 'Local edit' : 'Original');
        expect(after.color, '#112233');
        expect((await cloudTags(a.sync)).single.name, after.name);
        expect(await a.state.feedCursor(), priorCursor);
      },
    );
  }

  test('a previously chosen candidate survives another Device resolving after a failed reply', () async {
    final a = await device(service, 'A'), b = await device(service, 'B');
    final skill = a.workspace.seed(source: git());
    await a.sync.bootstrap();
    await a.sync.startSyncing(skill.id);
    final localId = (await b.sync.bootstrap()).installedSkillIds.single;
    final id = (await a.state.links()).single.lineageId!;
    await a.sync.api.writeNote(id, expectedVersion: 0, value: 'First');
    await a.sync.api.openNoteConflict(id, expectedVersion: 1, value: 'Second');
    await b.sync.feedCheck();
    final shown = b.sync.metadataAttention[localId]!;
    service.failNext(
      path: '/v0/lineages/$id/metadata/note/resolve',
      status: 503,
    );
    expect(
      await b.sync.resolveNoteConflict(
        localId,
        expectedVersion: shown.note!.version,
        expectedLocalNote: shown.localNote,
        value: 'Second',
      ),
      isA<WaitingToUpload>(),
    );
    await b.sync.checkLocalChanges();
    await a.sync.api.resolveNote(
      id,
      expectedVersion: shown.note!.version,
      value: 'Different selection',
    );
    await b.sync.feedCheck();
    final retained = b.sync.metadataAttention[localId]!;
    expect(retained.hasUnsubmittedLocalNote, isTrue);
    expect(retained.localNote, 'Second');
    expect(retained.note!.value, 'Different selection');
  });
}
