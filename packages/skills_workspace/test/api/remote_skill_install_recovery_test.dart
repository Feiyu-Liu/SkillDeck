import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';
import '../support/operations/remote_apply_test_support.dart';
import '../support/remote_revision_pack_fixture.dart';

void main() {
  late DriftFacadeFixture donorWorkspace;
  late RemoteRevisionPackFixture donor;
  late SkillsRepository repository;
  late WorkspaceLayout layout;
  late String basePack;
  final source = SyncedOriginSourceDescriptor(
    originSourceType: SyncedOriginSourceType.local,
    originDeviceLabel: 'Donor Device',
    displayLabel: 'Donor folder',
  );

  SkillsRepository createReceiver() {
    final receiver = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: layout.rootPath,
        agentHomePath: donorWorkspace.agentHomePath,
      ),
    );
    addTearDown(() async {
      if (receiver.isOpen) await driftSuccess(receiver.close());
    });
    return receiver;
  }

  RemoteSkillInstall request({
    String? packPath,
    RevisionId? effective,
    RevisionId? upstream,
  }) => RemoteSkillInstall(
    packPath: packPath ?? basePack,
    effective: effective ?? donor.base.effective,
    upstream: upstream ?? donor.base.upstream,
    source: source,
  );

  setUp(() async {
    donorWorkspace = await DriftFacadeFixture.create(activate: false);
    donor = await RemoteRevisionPackFixture.create(donorWorkspace);
    await driftSuccess(donorWorkspace.repository.close());
    basePack = path.join(donorWorkspace.exportDirectory, 'base.pack');
    layout = WorkspaceLayout(
      path.join(donorWorkspace.temporaryRoot.path, 'receiving-workspace'),
    );
    repository = createReceiver();
    await driftSuccess(repository.open());
  });

  test('failed installs preserve state and record each failure', () async {
    final malformed = File(
      path.join(donorWorkspace.exportDirectory, 'malformed.pack'),
    );
    await malformed.writeAsBytes(
      (await File(basePack).readAsBytes()).take(8).toList(),
    );
    final invalid = await donor.incoming(
      files: {'SKILL.md': 'Missing Skill frontmatter\n'},
    );
    final unsupported = await donor.incoming(
      files: {'SKILL.md': '---\nname: 代码审查\ndescription: review\n---\n'},
    );
    final snapshotBefore = repository.snapshot;
    var rowsBefore = readOperationDatabaseRows(layout.databasePath);
    final filesBefore = await _artifactPaths(layout);
    for (final (input, code, reason) in [
      (
        request(packPath: malformed.path),
        SkillsErrorCode.archiveInvalid,
        'packMalformed',
      ),
      (
        request(effective: invalid.revision),
        SkillsErrorCode.revisionStoreCorrupt,
        'packIncomplete',
      ),
      (
        request(upstream: invalid.revision),
        SkillsErrorCode.revisionStoreCorrupt,
        'packIncomplete',
      ),
      (
        request(
          packPath: path.join(donorWorkspace.exportDirectory, 'missing.pack'),
        ),
        SkillsErrorCode.ioFailure,
        'packUnreadable',
      ),
      (
        request(packPath: invalid.packPath, effective: invalid.revision),
        SkillsErrorCode.invalidSkill,
        null,
      ),
      (
        request(
          packPath: unsupported.packPath,
          effective: unsupported.revision,
        ),
        SkillsErrorCode.unsupportedSkillName,
        null,
      ),
    ]) {
      final operation = repository.applyRemoteState(input);
      await driftFailure(operation, code, reason: reason);
      await _expectOperationStatus(
        repository,
        operation.operationId,
        OperationTerminalStatus.failed,
      );
      expect(repository.snapshot, snapshotBefore);
      expect(await _artifactPaths(layout), filesBefore);
      _expectUnchangedBusinessRows(
        layout,
        rowsBefore,
        operation.operationId,
        completedJournal: true,
      );
      rowsBefore = readOperationDatabaseRows(layout.databasePath);
    }
  });

  test(
    'cancellation during preparation leaves the Skill uninstalled',
    () async {
      final before = repository.snapshot;
      final filesBefore = await _artifactPaths(layout);
      final rowsBefore = readOperationDatabaseRows(layout.databasePath);
      final operation = repository.applyRemoteState(request());
      await operation.progress
          .firstWhere(
            (progress) => progress.phase == OperationProgressPhase.preparing,
          )
          .then((_) => operation.cancel());
      await driftFailure(operation, SkillsErrorCode.operationCancelled);
      await _expectOperationStatus(
        repository,
        operation.operationId,
        OperationTerminalStatus.cancelled,
      );
      expect(repository.snapshot, before);
      expect(await _artifactPaths(layout), filesBefore);
      _expectUnchangedBusinessRows(
        layout,
        rowsBefore,
        operation.operationId,
        completedJournal: true,
      );
    },
  );

  for (final committed in [false, true]) {
    test(
      'recovers install interrupted ${committed ? 'after' : 'before'} the business commit',
      () async {
        final before = repository.snapshot;
        await driftSuccess(repository.close());
        final filesBefore = await _artifactPaths(layout);
        final rowsBefore = readOperationDatabaseRows(layout.databasePath);
        final operationId = OperationId('123e4567-e89b-42d3-a456-426614174099');

        await crashRemoteApply([
          layout.rootPath,
          'install',
          basePack,
          donor.base.effective.value,
          donor.base.upstream!.value,
          operationId.value,
        ], committed: committed);
        final interrupted = readOperationDatabaseRows(layout.databasePath);
        expect(
          interrupted['operation_journals']!.single['phase'],
          committed ? 'committed' : 'applying',
        );
        expect(interrupted['managed_skills'], hasLength(committed ? 1 : 0));
        expect(
          await Directory(layout.revisionStoresRoot).list().isEmpty,
          isFalse,
        );

        final reopened = createReceiver();
        await driftSuccess(reopened.open());
        expect(
          reopened.snapshot.revision.value,
          before.revision.value + (committed ? 1 : 0),
        );
        await _expectOperationStatus(
          reopened,
          operationId,
          committed
              ? OperationTerminalStatus.succeeded
              : OperationTerminalStatus.failed,
        );
        expect(
          await Directory(layout.operationStagingPath(operationId)).exists(),
          isFalse,
        );
        expect(
          await Directory(layout.operationRecoveryPath(operationId)).exists(),
          isFalse,
        );
        expect(
          readOperationDatabaseRows(layout.databasePath)['operation_journals'],
          isEmpty,
        );

        if (committed) {
          final skill = reopened.snapshot.managedSkills.single;
          expect(skill.activations, isEmpty);
          expect(skill.source, source);
          final selected = await driftSuccess(
            reopened.inspectRevisionSelections(
              InspectRevisionSelectionsRequest(managedSkillIds: {skill.id}),
            ),
          );
          expect(
            selected.selections[skill.id]!.effective,
            donor.base.effective,
          );
          expect(selected.selections[skill.id]!.upstream, donor.base.upstream);
          expect(
            await File(
              path.join(layout.repositoryCopyPath(skill.slotKey), 'notes.md'),
            ).readAsString(),
            DriftFacadeFixture.baseNotes,
          );
          final exported = await driftSuccess(
            reopened.exportRevisionPack(
              ExportRevisionPackRequest(
                managedSkillId: skill.id,
                destinationPath: path.join(
                  donorWorkspace.exportDirectory,
                  'recovered.pack',
                ),
              ),
            ),
          );
          expect(exported.effective, donor.base.effective);
          expect(exported.upstream, donor.base.upstream);
        } else {
          expect(reopened.snapshot, before);
          expect(await _artifactPaths(layout), filesBefore);
          _expectUnchangedBusinessRows(layout, rowsBefore, operationId);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

Future<void> _expectOperationStatus(
  SkillsRepository repository,
  OperationId operationId,
  OperationTerminalStatus status,
) async {
  final history = await driftSuccess(
    repository.inspectOperationHistory(const OperationHistoryRequest()),
  );
  final record = history.entries.singleWhere(
    (entry) => entry.operationId == operationId,
  );
  expect(record.status, status);
  expect(record.kind, WorkspaceOperationKind.applyRemoteState);
}

void _expectUnchangedBusinessRows(
  WorkspaceLayout layout,
  Map<String, List<Map<String, Object?>>> before,
  OperationId operationId, {
  bool completedJournal = false,
}) {
  final actual = readOperationDatabaseRows(layout.databasePath);
  final records = actual['operation_records']!;
  expect(records, hasLength(before['operation_records']!.length + 1));
  records.remove(
    records.singleWhere((row) => row['operation_id'] == operationId.value),
  );
  if (completedJournal) {
    final journals = actual['operation_journals']!;
    final journal = journals.singleWhere(
      (row) => row['operation_id'] == operationId.value,
    );
    expect(journal['phase'], 'completed');
    journals.remove(journal);
    actual['operation_journal_steps']!.removeWhere(
      (row) => row['operation_id'] == operationId.value,
    );
  }
  expect(actual, before);
}

Future<Set<String>> _artifactPaths(WorkspaceLayout layout) async => {
  for (final root in [
    layout.repositoryCopiesRoot,
    layout.revisionStoresRoot,
    layout.revisionBundlesRoot,
    layout.draftsRoot,
    layout.stagingRoot,
    layout.recoveryRoot,
  ])
    if (await Directory(root).exists())
      await for (final entry in Directory(
        root,
      ).list(recursive: true, followLinks: false))
        entry.path,
};
