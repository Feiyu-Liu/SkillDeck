import 'dart:io';

import 'package:drift/drift.dart';
import 'package:skills_workspace/src/application/drafts/draft_snapshot_coordinator.dart';
import 'package:skills_workspace/src/application/ports/draft_dirty_state_ports.dart';
import 'package:skills_workspace/src/application/ports/draft_snapshot_ports.dart';
import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_update_draft_inspection.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart'
    hide ManagedSkill;
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

const _skillId = '123e4567-e89b-42d3-a456-426614174000';
const _lineageId = '123e4567-e89b-42d3-a456-426614174001';
const _objectId = '0123456789012345678901234567890123456789';

void main() {
  late Directory temporary;
  late WorkspaceDatabase database;
  late WorkspaceLayout layout;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-draft-dirty-inspection-',
    );
    layout = WorkspaceLayout(temporary.path);
    database = WorkspaceDatabase.forFile(File(layout.databasePath));
    await database.workspaceMetadata.select().getSingle();
    await _insertDraftState(database);
  });

  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  for (final code in <DraftSnapshotFailureCode>[
    DraftSnapshotFailureCode.invalidSkill,
    DraftSnapshotFailureCode.skillContentLimitExceeded,
  ]) {
    test('${code.name} unpublished bytes are authoritatively dirty', () async {
      final inspection = _inspection(database, layout, code);

      final presentation = await inspection.inspectDraftDirtyState(
        skill: _skill(layout),
        cancellationToken: CancellationToken.none(),
      );
      final update = await inspection.inspectForUpdate(
        skill: _skill(layout),
        cancellationToken: CancellationToken.none(),
      );

      expect(
        presentation,
        isA<DraftDirtyStateInspectionSuccess>().having(
          (result) => result.isDirty,
          'isDirty',
          isTrue,
        ),
      );
      expect(
        update,
        isA<UpdateDraftInspectionSuccess>().having(
          (result) => result.inspection.isDirty,
          'isDirty',
          isTrue,
        ),
      );
    });
  }

  test('an unstable Draft remains a consistency failure', () async {
    final inspection = _inspection(
      database,
      layout,
      DraftSnapshotFailureCode.draftChangedDuringPublish,
    );

    final result = await inspection.inspectDraftDirtyState(
      skill: _skill(layout),
      cancellationToken: CancellationToken.none(),
    );

    expect(
      result,
      isA<DraftDirtyStateInspectionFailure>().having(
        (failure) => failure.reason,
        'reason',
        'draftChangedDuringPublish',
      ),
    );
  });

  test('an I/O failure does not become a false dirty success', () async {
    final inspection = _inspection(
      database,
      layout,
      DraftSnapshotFailureCode.ioFailure,
    );

    final result = await inspection.inspectDraftDirtyState(
      skill: _skill(layout),
      cancellationToken: CancellationToken.none(),
    );

    expect(
      result,
      isA<DraftDirtyStateInspectionFailure>().having(
        (failure) => failure.reason,
        'reason',
        'ioFailure',
      ),
    );
  });
}

DriftUpdateDraftInspection _inspection(
  WorkspaceDatabase database,
  WorkspaceLayout layout,
  DraftSnapshotFailureCode code,
) => DriftUpdateDraftInspection(
  database: database,
  layout: layout,
  accessGate: ManagedSkillRevisionAccessGate(),
  storePath: layout.revisionStorePath,
  revisions: _RevisionEngine(),
  snapshots: DraftSnapshotCoordinator(
    filesystem: _DraftFilesystem(code),
    content: _DraftContent(),
    maximumCaptureAttempts: 1,
  ),
);

Future<void> _insertDraftState(
  WorkspaceDatabase database,
) => database.transaction(() async {
  await database
      .into(database.managedSkills)
      .insert(
        ManagedSkillsCompanion.insert(
          id: _skillId,
          slotKey: 'reviewer',
          declaredName: 'reviewer',
          displayName: 'Reviewer',
          description: 'Reviews Skills.',
          activeSourceLineageId: _lineageId,
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
      );
  await database
      .into(database.sourceLineages)
      .insert(
        SourceLineagesCompanion.insert(
          id: _lineageId,
          managedSkillId: _skillId,
          objectFormat: 'sha1',
          createdAtMicros: 1,
        ),
      );
  await database
      .into(database.revisionMetadata)
      .insert(
        RevisionMetadataCompanion.insert(
          sourceLineageId: _lineageId,
          objectId: _objectId,
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          fileCount: 1,
          byteSize: 1,
          declaredName: 'reviewer',
          validationState: 'valid',
          createdAtMicros: 1,
        ),
      );
  await database
      .into(database.draftWorkspaces)
      .insert(
        DraftWorkspacesCompanion.insert(
          managedSkillId: _skillId,
          sourceLineageId: _lineageId,
          baseObjectId: _objectId,
          purpose: 'customization',
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
      );
});

ManagedSkill _skill(WorkspaceLayout layout) {
  final id = ManagedSkillId(_skillId);
  return ManagedSkill(
    id: id,
    slotKey: 'reviewer',
    declaredName: 'reviewer',
    displayName: 'Reviewer',
    description: 'Reviews Skills.',
    source: GitSourceDescriptor(locator: 'https://example.com/repo.git'),
    currentRevision: ManagedSkillRevisionSummary(
      contentHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      fileCount: 1,
      byteSize: 1,
      publishedAt: DateTime.utc(2026, 8, 20),
    ),
    draft: DraftSummary(
      purpose: DraftPurpose.customization,
      path: layout.draftPath(id),
      isDirty: false,
      updatedAt: DateTime.utc(2026, 8, 20),
    ),
  );
}

final class _RevisionEngine implements RevisionEnginePort {
  @override
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commitOrTree,
  ) async => NormalizedSkillTree(
    files: <NormalizedSkillFile>[
      NormalizedSkillFile(
        relativePath: 'SKILL.md',
        bytes: const <int>[1],
        isExecutable: false,
      ),
    ],
    contentHash:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    byteSize: 1,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used');
}

final class _DraftFilesystem implements DraftSnapshotFilesystemPort {
  _DraftFilesystem(this.code);

  final DraftSnapshotFailureCode code;

  @override
  Future<DraftSnapshotResult<DraftCapture>> capture(
    DraftCaptureRequest request,
  ) async => DraftSnapshotFailure<DraftCapture>(code: code);

  @override
  Future<void> discardStaging(DraftCapture capture) async {}

  @override
  Future<DraftSnapshotResult<DraftFingerprint>> fingerprint(
    DraftCaptureRequest request,
  ) async => DraftSnapshotFailure<DraftFingerprint>(code: code);
}

final class _DraftContent implements DraftContentPort {
  @override
  Future<DraftSnapshotResult<NormalizedSkillTree>> normalize(
    List<CapturedDraftFile> files, {
    bool Function()? isCancelled,
  }) => Future<DraftSnapshotResult<NormalizedSkillTree>>.error(
    UnsupportedError('not used'),
  );

  @override
  Future<String?> readDeclaredName(NormalizedSkillTree tree) async => null;
}
