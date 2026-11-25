import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';

void main() {
  late DriftFacadeFixture fixture;
  late WorkspaceLayout layout;
  late SkillsRepository repository;
  late ManagedSkillId id;
  late int lostStores;

  setUp(() async {
    fixture = await DriftFacadeFixture.create(activate: false);
    layout = WorkspaceLayout(fixture.workspacePath);
    repository = fixture.repository;
    id = fixture.managedSkillId;
    lostStores = 0;
  });

  Future<void> publish(String notes) async {
    final draft = await driftSuccess(
      repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
    );
    await fixture.changeNotes(draft.path, notes);
    await driftSuccess(
      repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
    );
  }

  Future<List<PublishedRevisionSummary>> history() async => (await driftSuccess(
    repository.inspectPublishedHistory(
      PublishedHistoryRequest(managedSkillId: id),
    ),
  )).revisions;

  Iterable<Object> historyEntries(Iterable<PublishedRevisionSummary> entries) =>
      entries.map(
        (entry) =>
            (entry.reference, entry.kind, entry.publishedAt, entry.contentHash),
      );

  Future<void> restore(OperationSubjectReference reference) => driftSuccess(
    repository.restorePublish(
      RestorePublishRequest(managedSkillId: id, selectedRevision: reference),
    ),
  );

  Future<RevisionId> effective() async => (await driftSuccess(
    repository.inspectRevisionSelections(
      InspectRevisionSelectionsRequest(managedSkillIds: {id}),
    ),
  )).selections[id]!.effective;

  Future<String> repositoryNotes() =>
      File(path.join(fixture.repositoryCopyPath, 'notes.md')).readAsString();

  Future<void> recoverAfterStoreLoss({void Function()? whileClosed}) async {
    final revision = repository.snapshot.revision;
    await driftSuccess(repository.close());
    whileClosed?.call();
    final store = Directory(layout.revisionStorePath(id));
    await store.rename(
      path.join(fixture.temporaryRoot.path, 'lost-${lostStores++}.git'),
    );
    repository = fixture.createRepository();
    final reopened = await driftSuccess(repository.open());
    expect(reopened.revision, revision);
    final health = reopened.integrity.skills.single;
    expect(health.managedSkillId, id);
    expect(health.status, SkillIntegrityStatus.recovered);
    expect(await store.exists(), isTrue);
  }

  Future<void> expectExport(String name) async {
    final target = path.join(fixture.exportDirectory, '$name.pack');
    final pack = await driftSuccess(
      repository.exportRevisionPack(
        ExportRevisionPackRequest(managedSkillId: id, destinationPath: target),
      ),
    );
    expect(pack.effective, await effective());
    expect(await File(target).openRead(0, 4).first, 'PACK'.codeUnits);
  }

  test(
    'restores two Publishes and a subsequent Restore Publish after Store loss',
    () async {
      await publish('first publish\n');
      final first = (await history()).first.reference;
      await publish('second publish\n');
      final beforeLoss = await history();
      expect(beforeLoss, hasLength(3));

      await recoverAfterStoreLoss();
      expect(historyEntries(await history()), historyEntries(beforeLoss));
      expect(await repositoryNotes(), 'second publish\n');
      await expectExport('after-publish');

      await restore(first);
      expect(await repositoryNotes(), 'first publish\n');
      final restoredHistory = await history();
      expect(restoredHistory.first.kind, WorkspaceOperationKind.restorePublish);
      expect(
        historyEntries(restoredHistory.skip(1)),
        historyEntries(beforeLoss),
      );

      await recoverAfterStoreLoss();
      expect(historyEntries(await history()), historyEntries(restoredHistory));
      await expectExport('after-restore');
      await restore(beforeLoss.first.reference);
      expect(await repositoryNotes(), 'second publish\n');
    },
  );

  test('recovers a Dirty Draft based on an older published revision', () async {
    await publish('older publish\n');
    final older = await effective();
    await publish('current publish\n');
    expect(await effective(), isNot(older));
    final draft = await driftSuccess(
      repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
    );
    await fixture.changeNotes(draft.path, 'unpublished edit\n');

    await recoverAfterStoreLoss(
      whileClosed: () {
        // Public mutations either re-anchor a Draft or block an Effective change.
        final database = sqlite3.open(layout.databasePath);
        try {
          database.execute(
            'UPDATE draft_workspaces SET base_object_id = ? WHERE managed_skill_id = ?',
            [older.value, id.value],
          );
          expect(database.updatedRows, 1);
        } finally {
          database.close();
        }
      },
    );

    final request = InspectDraftRequest(managedSkillId: id);
    final recovered = await driftSuccess(repository.inspectDraft(request));
    expect(recovered?.path, draft.path);
    expect(recovered?.isDirty, isTrue);
    expect(
      await File(path.join(draft.path, 'notes.md')).readAsString(),
      'unpublished edit\n',
    );
    await fixture.changeNotes(draft.path, 'older publish\n');
    expect(
      (await driftSuccess(repository.inspectDraft(request)))?.isDirty,
      isFalse,
    );
    expect(await repositoryNotes(), 'current publish\n');
  });

  test(
    'recovers an open Update Candidate Session and publishes its resolution',
    () async {
      await publish('first customization\n');
      await publish('second customization\n');
      await fixture.changeNotes(fixture.sourcePath, 'upstream edit\n');
      await driftSuccess(
        repository.update(UpdateRequest(managedSkillIds: {id})),
      );
      final candidateRequest = InspectUpdateCandidateRequest(
        managedSkillId: id,
      );
      final candidate = await driftSuccess(
        repository.inspectUpdateCandidate(candidateRequest),
      );
      expect(candidate?.status, UpdateCandidateStatus.conflicted);
      expect(candidate?.conflicts.single.path, 'notes.md');

      await recoverAfterStoreLoss();
      expect(
        await driftSuccess(repository.inspectUpdateCandidate(candidateRequest)),
        candidate,
      );
      final draft = await driftSuccess(
        repository.inspectDraft(InspectDraftRequest(managedSkillId: id)),
      );
      expect(draft?.purpose, DraftPurpose.updateCandidateResolution);
      await fixture.changeNotes(draft!.path, 'resolved conflict\n');
      await driftSuccess(
        repository.resolveUpdateConflict(
          ResolveUpdateConflictRequest(
            managedSkillId: id,
            path: 'notes.md',
            resolutionState: UpdateConflictResolutionState.resolved,
          ),
        ),
      );
      await driftSuccess(
        repository.publishUpdateCandidate(
          PublishUpdateCandidateRequest(managedSkillId: id),
        ),
      );
      expect(
        await driftSuccess(repository.inspectUpdateCandidate(candidateRequest)),
        isNull,
      );
      expect(await repositoryNotes(), 'resolved conflict\n');
      await expectExport('after-candidate');
    },
  );
}
