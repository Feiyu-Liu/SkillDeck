import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';
import '../support/operations/destructive_sqlite_crash_harness.dart';
import '../support/operations/remote_apply_test_support.dart';

void main() {
  late DriftFacadeFixture fixture;
  late SkillsRepository repository;
  late ManagedSkillId id;
  late WorkspaceLayout layout;

  setUp(() async {
    fixture = await DriftFacadeFixture.create(twoActivations: true);
    repository = fixture.repository;
    id = fixture.managedSkillId;
    layout = WorkspaceLayout(fixture.workspacePath);
  });

  Future<RevisionId> effective() async => (await driftSuccess(
    repository.inspectRevisionSelections(
      InspectRevisionSelectionsRequest(managedSkillIds: {id}),
    ),
  )).selections[id]!.effective;

  SkillsOperation<RemoteApplyResult> remove(RevisionId expected) =>
      repository.applyRemoteState(
        RemoteSkillRemoval(managedSkillId: id, expectedEffective: expected),
      );

  Future<void> expectMaterializations({required bool present}) async {
    for (final root in [
      fixture.repositoryCopyPath,
      fixture.activationPath(),
      fixture.activationPath(DriftFacadeFixture.secondAgentId),
    ]) {
      expect(await Directory(root).exists(), present, reason: root);
      if (present) {
        expect(
          await File(path.join(root, 'notes.md')).readAsString(),
          DriftFacadeFixture.baseNotes,
        );
      }
    }
  }

  test(
    'removes the Skill, Repository Copy, and Activations in one commit',
    () async {
      final expected = await effective();
      final draft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
      );
      final before = repository.snapshot.revision;
      expect(repository.snapshot.findSkill(id)!.activations, hasLength(2));

      expect(await driftSuccess(remove(expected)), isA<RemoteApplyRemoved>());

      expect(repository.snapshot.findSkill(id), isNull);
      expect(repository.snapshot.revision.value, before.value + 1);
      await expectMaterializations(present: false);
      expect(await Directory(draft.path).exists(), isFalse);
      final feed =
          await driftSuccess(
                repository.inspectCommittedChanges(
                  InspectCommittedChangesRequest(since: before),
                ),
              )
              as CommittedChangesAvailable;
      final entry = feed.entries.single;
      expect(entry.managedSkillId, id);
      expect(entry.kinds, {CommittedChangeKind.removed});
      expect(entry.revision, repository.snapshot.revision);

      final removedRows = readOperationDatabaseRows(layout.databasePath);
      await driftFailure(remove(expected), SkillsErrorCode.skillNotFound);
      expect(readOperationDatabaseRows(layout.databasePath), removedRows);
    },
  );

  test(
    'guards a stale Effective Revision before checking a Dirty Draft',
    () async {
      final expected = await effective();
      final draft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
      );
      await fixture.changeNotes(draft.path, 'dirty draft\n');
      final before = repository.snapshot;
      final rows = readOperationDatabaseRows(layout.databasePath);
      final stale = RevisionId(
        expected.value == '0' * 40 ? '1' * 40 : '0' * 40,
      );

      await driftFailure(
        remove(stale),
        SkillsErrorCode.staleSnapshot,
        reason: 'effectiveRevisionChanged',
      );

      expect(repository.snapshot, before);
      expect(readOperationDatabaseRows(layout.databasePath), rows);
      await expectMaterializations(present: true);
      expect(
        await File(path.join(draft.path, 'notes.md')).readAsString(),
        'dirty draft\n',
      );
    },
  );

  for (final candidate in [false, true]) {
    test('${candidate ? 'an Update Candidate Session' : 'a Dirty Draft'} '
        'blocks Removal without writing history or a journal', () async {
      final draft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
      );
      await fixture.changeNotes(draft.path, 'local customization\n');
      if (candidate) {
        await driftSuccess(
          repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
        );
        await fixture.changeNotes(fixture.sourcePath, 'incoming upstream\n');
        await driftSuccess(
          repository.update(UpdateRequest(managedSkillIds: {id})),
        );
        expect(repository.snapshot.findSkill(id)!.updateCandidate, isNotNull);
      }
      final inspected = await driftSuccess(
        repository.inspectDraft(InspectDraftRequest(managedSkillId: id)),
      );
      expect(inspected, isNotNull);
      expect(inspected!.isDirty, !candidate);
      final expected = await effective();
      final before = repository.snapshot;
      final rows = readOperationDatabaseRows(layout.databasePath);
      final notes = File(path.join(inspected.path, 'notes.md'));
      final draftBytes = await notes.readAsBytes();

      expect(
        await remove(expected).completed,
        isA<SkillsSuccess<RemoteApplyResult>>()
            .having(
              (result) => result.value,
              'value',
              isA<RemoteApplyDraftResolutionRequired>(),
            )
            .having((result) => result.changed, 'changed', isFalse),
      );

      expect(repository.snapshot, before);
      expect(readOperationDatabaseRows(layout.databasePath), rows);
      expect(await notes.readAsBytes(), draftBytes);
    });
  }

  test(
    'preserves an external edit after the clean Draft was reviewed',
    () async {
      final expected = await effective();
      final draft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
      );
      final before = repository.snapshot.revision;
      await driftSuccess(repository.close());
      const externalEdit = 'external edit during Removal\n';

      final result = await runRemoteRemovalAtCommitBoundary(
        workspaceRoot: layout.rootPath,
        skillId: id,
        expectedEffective: expected,
        afterPrepared: () => fixture.changeNotes(draft.path, externalEdit),
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
      expect(
        result.failureOrNull?.context['reason'],
        'externalPreconditionChanged',
      );
      final reopened = fixture.createRepository();
      await driftSuccess(reopened.open());
      expect(reopened.snapshot.revision, before);
      expect(reopened.snapshot.findSkill(id), isNotNull);
      expect(
        await File(path.join(draft.path, 'notes.md')).readAsString(),
        externalEdit,
      );
      await expectMaterializations(present: true);
    },
  );

  for (final committed in [false, true]) {
    test(
      'interruption ${committed ? 'after' : 'before'} the commit recovers Removal',
      () async {
        final expected = await effective();
        final before = repository.snapshot;
        await driftSuccess(repository.close());

        await crashRemoteApply(
          [layout.rootPath, id.value, expected.value],
          committed: committed,
          script:
              'test/support/operations/destructive_sqlite_crash_helper.dart',
        );
        final interrupted = readOperationDatabaseRows(layout.databasePath);
        expect(
          interrupted['operation_journals']!.single['phase'],
          committed ? 'committed' : 'applying',
        );
        expect(interrupted['managed_skills'], hasLength(committed ? 0 : 1));

        final reopened = fixture.createRepository();
        await driftSuccess(reopened.open());

        expect(
          reopened.snapshot.revision.value,
          before.revision.value + (committed ? 1 : 0),
        );
        expect(
          reopened.snapshot.findSkill(id),
          committed ? isNull : before.findSkill(id),
        );
        await expectMaterializations(present: !committed);
        expect(
          readOperationDatabaseRows(layout.databasePath)['operation_journals'],
          isEmpty,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
