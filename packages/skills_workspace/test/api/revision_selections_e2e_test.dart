import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:sqlite3/sqlite3.dart';
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

  SkillsOperation<RevisionSelections> inspect(Set<ManagedSkillId> ids) =>
      repository.inspectRevisionSelections(
        InspectRevisionSelectionsRequest(managedSkillIds: ids),
      );

  test('reads installed heads and the feed cursor without writing', () async {
    final heads = await driftSuccess(
      repository.exportRevisionPack(
        ExportRevisionPackRequest(
          managedSkillId: skillId,
          destinationPath: path.join(fixture.exportDirectory, 'installed.pack'),
        ),
      ),
    );
    final layout = WorkspaceLayout(fixture.workspacePath);
    final database = sqlite3.open(layout.databasePath, mode: OpenMode.readOnly);
    addTearDown(database.close);
    Iterable<OperationId> historyIds(OperationHistoryPage history) =>
        history.entries.map((entry) => entry.operationId);
    Future<OperationHistoryPage> inspectHistory() => driftSuccess(
      repository.inspectOperationHistory(const OperationHistoryRequest()),
    );
    final history = await inspectHistory();
    final journals = database.select('SELECT * FROM operation_journals');
    final revision = repository.snapshot.revision;

    final store = Directory(layout.revisionStorePath(skillId));
    final movedStore = await store.rename('${store.path}.moved');
    late RevisionSelections result;
    try {
      result = await driftSuccess(inspect({skillId}));
    } finally {
      await movedStore.rename(store.path);
    }

    final empty = await driftSuccess(inspect({}));
    final feed = await driftSuccess(
      repository.inspectCommittedChanges(
        InspectCommittedChangesRequest(since: revision),
      ),
    );
    expect(result.current, feed.current);
    expect(empty.current, feed.current);
    expect(empty.selections, isEmpty);
    expect(result.selections[skillId]!.effective, heads.effective);
    expect(result.selections[skillId]!.upstream, heads.upstream);
    expect(repository.snapshot.revision, revision);
    expect(historyIds(await inspectHistory()), historyIds(history));
    expect(database.select('SELECT * FROM operation_journals'), journals);
  });

  test('reads across batches and skips unknown and removed Skills', () async {
    final source = await Directory(
      path.join(fixture.temporaryRoot.path, 'second-source'),
    ).create();
    await fixture.writeSkillMarkdown(source.path, name: 'second-skill');
    final installed = await driftSuccess(
      repository.install(
        InstallRequest(
          source: LocalSourceDescriptor(locator: source.path),
          activationSelection: const ActivationSelection.none(),
          activationMode: RequestedActivationMode.copy,
        ),
      ),
    );
    final secondId =
        (installed as InstallCompleted).report.affectedSkillIds.single;
    final ids = {
      skillId,
      for (var index = 0; index < 500; index++)
        ManagedSkillId(
          '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
        ),
      secondId,
    };
    expect(
      (await driftSuccess(inspect(ids))).selections.keys,
      unorderedEquals([skillId, secondId]),
    );

    await driftSuccess(
      repository.remove(
        RemoveRequest(
          managedSkillIds: {skillId},
          intent: DestructiveIntent(
            reviewedRevision: repository.snapshot.revision,
          ),
        ),
      ),
    );
    expect((await driftSuccess(inspect(ids))).selections.keys, [secondId]);
  });

  test('reports cancellation through the public operation', () async {
    final operation = inspect({skillId});
    await operation.cancel();
    await driftFailure(operation, SkillsErrorCode.operationCancelled);
  });
}
