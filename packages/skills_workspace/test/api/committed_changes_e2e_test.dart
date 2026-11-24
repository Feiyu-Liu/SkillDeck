import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';

void main() {
  late DriftFacadeFixture fixture;
  late SkillsRepository repository;
  late ManagedSkillId skillId;

  setUp(() async {
    fixture = await DriftFacadeFixture.create(activate: false);
    repository = fixture.repository;
    skillId = fixture.managedSkillId;
  });

  Future<CommittedChangesAvailable> inspect(RepositoryRevision since) async =>
      await driftSuccess(
            repository.inspectCommittedChanges(
              InspectCommittedChangesRequest(since: since),
            ),
          )
          as CommittedChangesAvailable;

  Future<void> expectChange(
    RepositoryRevision since,
    Set<CommittedChangeKind> kinds, {
    bool vocabularyChanged = false,
  }) async {
    final current = repository.snapshot.revision;
    final feed = await inspect(since);
    expect(feed.current, current);
    expect(feed.vocabularyChanged, vocabularyChanged);
    final entry = feed.entries.single;
    expect(entry.managedSkillId, skillId);
    expect(entry.revision, current);
    expect(entry.kinds, kinds);
  }

  test(
    'install, update, publish, and restore report committed content',
    () async {
      const content = {CommittedChangeKind.content};
      await expectChange(RepositoryRevision(0), content);
      final installedAt = repository.snapshot.revision;
      final installed = (await fixture.history()).revisions.single;

      await fixture.changeNotes(fixture.sourcePath, 'new upstream notes\n');
      await driftSuccess(
        repository.update(UpdateRequest(managedSkillIds: {skillId})),
      );
      await expectChange(installedAt, content);
      final updatedAt = repository.snapshot.revision;

      final draft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: skillId)),
      );
      expect((await inspect(updatedAt)).entries, isEmpty);
      await File(
        path.join(draft.path, 'local.md'),
      ).writeAsString('local edit\n');
      final beforePublish = repository.snapshot.revision;
      await driftSuccess(
        repository.publishDraft(PublishDraftRequest(managedSkillId: skillId)),
      );
      await expectChange(beforePublish, content);

      final beforeRestore = repository.snapshot.revision;
      await driftSuccess(
        repository.restorePublish(
          RestorePublishRequest(
            managedSkillId: skillId,
            selectedRevision: installed.reference,
          ),
        ),
      );
      await expectChange(beforeRestore, content);
      final atCurrent = await inspect(repository.snapshot.revision);
      expect(atCurrent.entries, isEmpty);
      expect(atCurrent.vocabularyChanged, isFalse);
    },
  );

  test(
    'favorite, note, and tag changes retain all kinds newer than the cursor',
    () async {
      const metadata = {CommittedChangeKind.metadata};
      final installedAt = repository.snapshot.revision;
      final favorite = SetFavoriteRequest(
        managedSkillId: skillId,
        isFavorite: true,
      );
      await driftSuccess(repository.setFavorite(favorite));
      await expectChange(installedAt, metadata);
      await expectChange(RepositoryRevision(0), {
        CommittedChangeKind.content,
        CommittedChangeKind.metadata,
      });

      final favoriteAt = repository.snapshot.revision;
      await driftSuccess(repository.setFavorite(favorite));
      expect(repository.snapshot.revision, favoriteAt);
      expect((await inspect(favoriteAt)).entries, isEmpty);

      await driftSuccess(
        repository.saveNote(
          SaveNoteRequest(managedSkillId: skillId, text: 'new note'),
        ),
      );
      await expectChange(favoriteAt, metadata);
      final noteAt = repository.snapshot.revision;
      await driftSuccess(
        repository.deleteNote(DeleteNoteRequest(managedSkillId: skillId)),
      );
      await expectChange(noteAt, metadata);

      final beforeCreate = repository.snapshot.revision;
      final tag = await driftSuccess(
        repository.createPersonalTag(CreatePersonalTagRequest(name: 'Work')),
      );
      final created = await inspect(beforeCreate);
      expect(created.entries, isEmpty);
      expect(created.vocabularyChanged, isTrue);

      final beforeRename = repository.snapshot.revision;
      await driftSuccess(
        repository.updatePersonalTag(
          UpdatePersonalTagRequest(tagId: tag.id, name: 'Business'),
        ),
      );
      final renamed = await inspect(beforeRename);
      expect(renamed.entries, isEmpty);
      expect(renamed.vocabularyChanged, isTrue);

      final beforeAssignment = repository.snapshot.revision;
      await driftSuccess(
        repository.assignPersonalTag(
          AssignPersonalTagRequest(managedSkillId: skillId, tagId: tag.id),
        ),
      );
      await expectChange(beforeAssignment, metadata);

      final beforeDelete = repository.snapshot.revision;
      await driftSuccess(
        repository.deletePersonalTag(DeletePersonalTagRequest(tagId: tag.id)),
      );
      await expectChange(beforeDelete, metadata, vocabularyChanged: true);
    },
  );

  test('retains a Removal once the Skill has gone', () async {
    final installedAt = repository.snapshot.revision;
    await driftSuccess(
      repository.remove(
        RemoveRequest(
          managedSkillIds: {skillId},
          intent: DestructiveIntent(reviewedRevision: installedAt),
        ),
      ),
    );
    expect(repository.snapshot.findSkill(skillId), isNull);
    await expectChange(installedAt, {CommittedChangeKind.removed});
    await expectChange(RepositoryRevision(0), {
      CommittedChangeKind.content,
      CommittedChangeKind.removed,
    });
  });
}
