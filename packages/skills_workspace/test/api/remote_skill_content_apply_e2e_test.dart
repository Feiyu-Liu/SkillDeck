import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';
import '../support/process/direct_dart_process.dart';
import '../support/remote_revision_pack_fixture.dart';

void main() {
  late DriftFacadeFixture fixture;
  late SkillsRepository repository;
  late ManagedSkillId skillId;
  late WorkspaceLayout layout;
  late String liveStore;
  late Directory staging;
  late RevisionPackExport base;
  late RemoteRevisionPackFixture donor;

  setUp(() async {
    fixture = await DriftFacadeFixture.create(twoActivations: true);
    repository = fixture.repository;
    skillId = fixture.managedSkillId;
    layout = WorkspaceLayout(fixture.workspacePath);
    liveStore = layout.revisionStorePath(skillId);
    staging = Directory(layout.revisionPackStagingPath(skillId));
    donor = await RemoteRevisionPackFixture.create(fixture);
    base = donor.base;
  });

  Future<({RevisionId revision, String packPath})> incoming() =>
      donor.incoming(files: {'notes.md': 'remote revision\n'});

  SkillsOperation<RemoteApplyResult> apply(
    RevisionId target, {
    RevisionId? expected,
    RevisionId? upstream,
    String? packPath,
    ManagedSkillId? id,
  }) => repository.applyRemoteState(
    RemoteSkillContent(
      managedSkillId: id ?? skillId,
      expectedEffective: expected ?? base.effective,
      effective: target,
      upstream: upstream ?? base.upstream!,
      packPath: packPath,
    ),
  );

  for (final stageFirst in [false, true]) {
    test(
      'fast-forwards from ${stageFirst ? 'staged' : 'supplied'} pack data',
      () async {
        final remote = await incoming();
        final draft = await driftSuccess(
          repository.ensureDraft(EnsureDraftRequest(managedSkillId: skillId)),
        );
        final before = repository.snapshot.revision;
        if (stageFirst) {
          expect(
            await driftSuccess(
              repository.importRevisionPack(
                ImportRevisionPackRequest(
                  managedSkillId: skillId,
                  packPath: remote.packPath,
                  revisions: [remote.revision],
                ),
              ),
            ),
            RevisionPackImport.imported,
          );
          expect(await staging.list().isEmpty, isFalse);
        }

        expect(
          await driftSuccess(
            apply(
              remote.revision,
              upstream: remote.revision,
              packPath: stageFirst ? null : remote.packPath,
            ),
          ),
          isA<RemoteApplyFastForwarded>(),
        );

        expect(repository.snapshot.revision.value, before.value + 1);
        await fixture.expectEffectiveNotes('remote revision\n');
        await fixture.expectMaterializedNotes(
          'remote revision\n',
          secondActivation: true,
        );
        final exported = await driftSuccess(
          repository.exportRevisionPack(
            ExportRevisionPackRequest(
              managedSkillId: skillId,
              destinationPath: path.join(fixture.exportDirectory, 'after.pack'),
            ),
          ),
        );
        expect(exported.effective, remote.revision);
        expect(exported.upstream, remote.revision);
        final anchored = await driftSuccess(
          repository.inspectDraft(InspectDraftRequest(managedSkillId: skillId)),
        );
        expect(anchored?.isDirty, isFalse);
        expect(anchored?.path, draft.path);
        expect(
          await File(path.join(draft.path, 'notes.md')).readAsString(),
          'remote revision\n',
        );
        await _expectNoPackResidue(layout, staging);

        final applied = repository.snapshot.revision;
        for (final target in [remote.revision, base.effective]) {
          expect(
            await driftSuccess(apply(target, expected: remote.revision)),
            isA<RemoteApplyNoChange>(),
          );
        }
        expect(repository.snapshot.revision, applied);
      },
    );
  }

  test('a dirty Draft blocks the remote change', () async {
    final remote = await incoming();
    final draft = await driftSuccess(
      repository.ensureDraft(EnsureDraftRequest(managedSkillId: skillId)),
    );
    await fixture.changeNotes(draft.path, 'my draft\n');
    final before = repository.snapshot.revision;

    expect(
      await driftSuccess(apply(remote.revision, packPath: remote.packPath)),
      isA<RemoteApplyDraftResolutionRequired>(),
    );

    expect(repository.snapshot.revision, before);
    await fixture.expectEffectiveNotes(DriftFacadeFixture.baseNotes);
    await fixture.expectMaterializedNotes(
      DriftFacadeFixture.baseNotes,
      secondActivation: true,
    );
    expect(
      await File(path.join(draft.path, 'notes.md')).readAsString(),
      'my draft\n',
    );
    await _expectNoPackResidue(layout, staging);
  });

  test(
    'guards the Effective pointer and treats an equal target as a no-op',
    () async {
      final before = repository.snapshot.revision;
      final remote = await incoming();

      expect(
        await driftSuccess(apply(base.effective)),
        isA<RemoteApplyNoChange>(),
      );
      await driftFailure(
        apply(
          remote.revision,
          expected: remote.revision,
          packPath: remote.packPath,
        ),
        SkillsErrorCode.staleSnapshot,
        reason: 'effectiveRevisionChanged',
      );
      await driftFailure(
        apply(
          base.effective,
          id: ManagedSkillId('00000000-0000-4000-8000-000000000000'),
        ),
        SkillsErrorCode.skillNotFound,
      );
      expect(repository.snapshot.revision, before);
      await fixture.expectEffectiveNotes(DriftFacadeFixture.baseNotes);
      await _expectNoPackResidue(layout, staging);
    },
  );

  test(
    'invalid or absent pack data leaves live files and SQLite intact',
    () async {
      final remote = await incoming();
      final invalid = File(
        path.join(fixture.temporaryRoot.path, 'invalid.pack'),
      );
      await invalid.writeAsString('not a revision pack');
      final before = repository.snapshot.revision;
      final storeBefore = await _storeBytes(liveStore);
      final rowsBefore = _databaseRows(layout.databasePath);
      final historyBefore = (await fixture.history()).revisions
          .map((entry) => (entry.reference, entry.contentHash))
          .toList();

      for (final (packPath, code, reason) in [
        (invalid.path, SkillsErrorCode.archiveInvalid, 'packMalformed'),
        (
          path.join(fixture.exportDirectory, 'base.pack'),
          SkillsErrorCode.revisionStoreCorrupt,
          'packIncomplete',
        ),
        (null, SkillsErrorCode.revisionStoreCorrupt, null),
      ]) {
        await driftFailure(
          apply(remote.revision, packPath: packPath),
          code,
          reason: reason,
        );
        expect(repository.snapshot.revision, before);
        expect(await _storeBytes(liveStore), equals(storeBefore));
        expect(_databaseRows(layout.databasePath), equals(rowsBefore));
        await _expectNoPackResidue(layout, staging);
      }
      expect(
        (await fixture.history()).revisions.map(
          (entry) => (entry.reference, entry.contentHash),
        ),
        orderedEquals(historyBefore),
      );
      await fixture.expectMaterializedNotes(
        DriftFacadeFixture.baseNotes,
        secondActivation: true,
      );
    },
  );

  for (final committed in [false, true]) {
    test(
      'recovers a remote apply interrupted ${committed ? 'after' : 'before'} commit',
      () async {
        final remote = await incoming();
        expect(
          await driftSuccess(
            repository.importRevisionPack(
              ImportRevisionPackRequest(
                managedSkillId: skillId,
                packPath: remote.packPath,
                revisions: [remote.revision],
              ),
            ),
          ),
          RevisionPackImport.imported,
        );
        final before = repository.snapshot.revision;
        await driftSuccess(repository.close());
        final storeBefore = await _storeBytes(liveStore);
        final stageBefore = await _storeBytes(staging.path);
        final rowsBefore = _databaseRows(layout.databasePath);
        final operationId = OperationId('123e4567-e89b-42d3-a456-426614174099');
        final helper = await Process.start(
          Platform.resolvedExecutable,
          directDartScriptArguments(
            'test/support/operations/remote_content_crash_helper.dart',
            [
              layout.rootPath,
              skillId.value,
              base.effective.value,
              remote.revision.value,
              operationId.value,
              if (committed) 'afterCommit' else 'beforeCommit',
            ],
          ),
        );
        final output = [
          helper.stdout.drain<void>(),
          helper.stderr.drain<void>(),
        ];
        expect(
          await helper.exitCode.timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              helper.kill();
              throw StateError(
                'The remote apply crash point was not reached in time.',
              );
            },
          ),
          committed ? 72 : 71,
        );
        await Future.wait(output);
        final interrupted = _databaseRows(layout.databasePath);
        expect(
          interrupted['operation_journals']!.single['phase'],
          committed ? 'committed' : 'applying',
        );
        expect(
          interrupted['current_revision_selection']!
              .single['effective_object_id'],
          committed ? remote.revision.value : base.effective.value,
        );
        expect(await _storeBytes(liveStore), isNot(equals(storeBefore)));

        final reopened = fixture.createRepository();
        await driftSuccess(reopened.open());
        expect(
          reopened.snapshot.revision.value,
          before.value + (committed ? 1 : 0),
        );
        await fixture.expectMaterializedNotes(
          committed ? 'remote revision\n' : DriftFacadeFixture.baseNotes,
          secondActivation: true,
        );
        if (committed) {
          await _expectNoPackResidue(layout, staging);
        } else {
          expect(await _storeBytes(liveStore), equals(storeBefore));
          expect(await _storeBytes(staging.path), equals(stageBefore));
          expect(_databaseRows(layout.databasePath), equals(rowsBefore));
        }
        expect(
          await Directory(layout.operationStagingPath(operationId)).exists(),
          isFalse,
        );
        expect(
          _databaseRows(layout.databasePath)['operation_journals'],
          isEmpty,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

Future<void> _expectNoPackResidue(
  WorkspaceLayout layout,
  Directory staging,
) async {
  if (await staging.exists()) expect(await staging.list().isEmpty, isTrue);
  final temporary = Directory(layout.revisionStoresRoot).list().where(
    (entry) => path
        .basename(entry.path)
        .startsWith(WorkspaceLayout.revisionPackTemporaryPrefix),
  );
  expect(await temporary.isEmpty, isTrue);
}

Future<Map<String, List<int>>> _storeBytes(String liveStore) async => {
  await for (final entry in Directory(liveStore).list(recursive: true))
    if (entry is File)
      path.relative(entry.path, from: liveStore): await entry.readAsBytes(),
};

Map<String, List<Map<String, Object?>>> _databaseRows(String databasePath) {
  final database = sqlite3.open(databasePath, mode: OpenMode.readOnly);
  try {
    final tables = database.select(
      "SELECT name FROM sqlite_schema WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    return {
      for (final {'name': name as String} in tables)
        name: database
            .select('SELECT * FROM "$name" ORDER BY rowid')
            .map((row) => Map<String, Object?>.of(row))
            .toList(),
    };
  } finally {
    database.close();
  }
}
