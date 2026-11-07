import 'dart:io';

import 'package:drift/drift.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/update_ports.dart';
import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_workspace_history_content.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart'
    hide ManagedSkill;
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceDatabase database;
  late _RevisionEngine revisions;
  late _DraftInspection drafts;
  late DriftWorkspaceHistoryContent content;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-history-content-',
    );
    database = WorkspaceDatabase.forFile(
      File('${temporaryDirectory.path}/workspace.sqlite'),
    );
    await database.workspaceMetadata.select().getSingle();
    await _seed(database);
    revisions = _RevisionEngine();
    drafts = _DraftInspection();
    content = DriftWorkspaceHistoryContent(
      database: database,
      accessGate: ManagedSkillRevisionAccessGate(),
      storePath: (_) => '/revision-store',
      revisionEngine: revisions,
      draftInspection: drafts,
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('resolves only a succeeded published Subject and metadata', () async {
    final selected = await content.resolvePublishedRevision(
      managedSkillId: _skillId,
      reference: _afterReference,
    );

    expect(selected?.sourceLineage, _lineage);
    expect(selected?.objectId, _afterObject);
    expect(selected?.contentHash, _hashB);
    expect(selected?.declaredName, 'one');
  });

  test('diff reads the canonical Store and maps native changes', () async {
    final before = await content.resolvePublishedRevision(
      managedSkillId: _skillId,
      reference: _beforeReference,
    );
    final after = await content.resolvePublishedRevision(
      managedSkillId: _skillId,
      reference: _afterReference,
    );

    final result = await content.compare(
      managedSkillId: _skillId,
      from: before,
      to: after!,
      cancellationToken: CancellationToken.none(),
    );

    final file = result.valueOrNull!.files.single;
    expect(file.path, 'renamed.md');
    expect(file.previousPath, 'old.md');
    expect(file.status, DiffFileStatus.renamed);
    expect(revisions.diffCalls, 1);
  });

  test('diff projects a deleted file with deletion hunks', () async {
    revisions.changes = const <RevisionChange>[
      RevisionChange(
        kind: RevisionChangeKind.deleted,
        oldPath: 'removed.md',
        newPath: null,
        oldExecutable: false,
        newExecutable: false,
        binary: false,
      ),
    ];
    revisions.trees[_beforeObject] = _tree(<NormalizedSkillFile>[
      NormalizedSkillFile(
        relativePath: 'removed.md',
        bytes: const <int>[111, 110, 101, 10, 116, 119, 111],
        isExecutable: false,
      ),
    ]);
    revisions.trees[_afterObject] = _tree(const <NormalizedSkillFile>[]);
    final before = await content.resolvePublishedRevision(
      managedSkillId: _skillId,
      reference: _beforeReference,
    );
    final after = await content.resolvePublishedRevision(
      managedSkillId: _skillId,
      reference: _afterReference,
    );

    final result = await content.compare(
      managedSkillId: _skillId,
      from: before,
      to: after!,
      cancellationToken: CancellationToken.none(),
    );

    final file = result.valueOrNull!.files.single;
    expect(file.path, 'removed.md');
    expect(file.previousPath, null);
    expect(file.status, DiffFileStatus.deleted);
    expect(file.additions, 0);
    expect(file.deletions, 2);
    expect(
      file.hunks.expand((hunk) => hunk.lines).map((line) => line.kind),
      everyElement(DiffLineKind.deletion),
    );
  });

  test(
    'diff from no prior Subject projects the selected tree as additions',
    () async {
      final after = await content.resolvePublishedRevision(
        managedSkillId: _skillId,
        reference: _afterReference,
      );

      final result = await content.compare(
        managedSkillId: _skillId,
        from: null,
        to: after!,
        cancellationToken: CancellationToken.none(),
      );

      final file = result.valueOrNull!.files.single;
      expect(file.status, DiffFileStatus.added);
      expect(file.additions, 1);
      expect(file.deletions, 0);
    },
  );

  test('Subject deletion before gated read fails revalidation', () async {
    final after = await content.resolvePublishedRevision(
      managedSkillId: _skillId,
      reference: _afterReference,
    );
    await (database.delete(
      database.operationSubjects,
    )..where((row) => row.subjectId.equals(_afterSubjectId))).go();

    final result = await content.compare(
      managedSkillId: _skillId,
      from: null,
      to: after!,
      cancellationToken: CancellationToken.none(),
    );

    expect(
      result.failureOrNull?.code,
      HistoryFailureCode.historicalRevisionOutsideCurrentLineage,
    );
    expect(revisions.readCalls, 0);
  });

  test('reads Restore pointers and persisted Draft creation time', () async {
    final state = await content.readRestoreState(_skillId);

    expect(state?.currentUpstream, _beforeObject);
    expect(state?.currentEffective, _afterObject);
    expect(state?.draftCreatedAtMicros, 3);
  });

  test(
    'maps authoritative Draft inspection without trusting Snapshot flag',
    () async {
      drafts.result = const UpdateDraftInspection.dirty();

      final result = await content.inspectDraftDirty(
        skill: _skill(),
        state: (await content.readRestoreState(_skillId))!,
        cancellationToken: CancellationToken.none(),
      );

      expect(result.valueOrNull, isTrue);
      expect(drafts.calls, 1);
    },
  );
}

final class _RevisionEngine implements RevisionEnginePort {
  var diffCalls = 0;
  var readCalls = 0;
  List<RevisionChange> changes = const <RevisionChange>[
    RevisionChange(
      kind: RevisionChangeKind.renamed,
      oldPath: 'old.md',
      newPath: 'renamed.md',
      oldExecutable: false,
      newExecutable: false,
      binary: false,
    ),
  ];
  final Map<RevisionObjectId, NormalizedSkillTree> trees =
      <RevisionObjectId, NormalizedSkillTree>{};

  @override
  Future<List<RevisionChange>> diff({
    required String repositoryPath,
    required RevisionObjectId oldCommit,
    required RevisionObjectId newCommit,
  }) async {
    diffCalls += 1;
    return changes;
  }

  @override
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commit,
  ) async {
    readCalls += 1;
    return trees[commit] ??
        NormalizedSkillTree(
          files: <NormalizedSkillFile>[
            NormalizedSkillFile(
              relativePath: 'SKILL.md',
              bytes: const <int>[97, 10],
              isExecutable: false,
            ),
          ],
          contentHash: _hashB,
          byteSize: 2,
        );
  }

  @override
  Future<void> close() async {}
  @override
  Future<RevisionObjectId> createCommit(
    String repositoryPath,
    RevisionCommitRequest request,
  ) => throw UnimplementedError();
  @override
  Future<void> createRecoveryPack({
    required String repositoryPath,
    required String bundleStagingPath,
    required List<RevisionObjectId> retainedRoots,
  }) => throw UnimplementedError();
  @override
  Future<void> createStore(String repositoryPath) => throw UnimplementedError();
  @override
  Future<bool> isAncestor({
    required String repositoryPath,
    required RevisionObjectId ancestor,
    required RevisionObjectId descendant,
  }) => throw UnimplementedError();
  @override
  Future<RevisionMergeResult> merge({
    required String repositoryPath,
    required RevisionObjectId previousUpstream,
    required RevisionObjectId currentEffective,
    required RevisionObjectId incomingUpstream,
  }) => throw UnimplementedError();
  @override
  Future<void> restoreRecoveryPack({
    required String stagedRepositoryPath,
    required String packPath,
    required String indexPath,
    required List<RevisionObjectId> retainedRoots,
  }) => throw UnimplementedError();
  @override
  Future<void> replaceRetentionRefs(
    String repositoryPath,
    List<RevisionRetentionRef> references,
  ) => throw UnimplementedError();
  @override
  Future<RevisionEngineStatus> status() => throw UnimplementedError();
  @override
  Future<void> verifyCommit(
    String repositoryPath,
    RevisionObjectId commit,
    RevisionCommitRequest expected,
  ) => throw UnimplementedError();
  @override
  Future<void> verifyStore(String repositoryPath) => throw UnimplementedError();
  @override
  Future<RevisionObjectId> writeTree(
    String repositoryPath,
    NormalizedSkillTree tree,
  ) => throw UnimplementedError();
}

final class _DraftInspection implements UpdateDraftInspectionPort {
  UpdateDraftInspection result = const UpdateDraftInspection.clean();
  var calls = 0;

  @override
  Future<UpdateDraftInspectionResult> inspectForUpdate({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    return UpdateDraftInspectionSuccess(result);
  }
}

Future<void> _seed(WorkspaceDatabase database) async {
  await database.transaction(() async {
    await database
        .into(database.managedSkills)
        .insert(
          ManagedSkillsCompanion.insert(
            id: _skillId.value,
            slotKey: 'one',
            declaredName: 'one',
            displayName: 'One',
            description: 'One Skill',
            activeSourceLineageId: _lineage.encoded,
            createdAtMicros: 1,
            updatedAtMicros: 2,
          ),
        );
    await database
        .into(database.sourceLineages)
        .insert(
          SourceLineagesCompanion.insert(
            id: _lineage.encoded,
            managedSkillId: _skillId.value,
            objectFormat: 'sha1',
            createdAtMicros: 1,
          ),
        );
    for (final revision in <(RevisionObjectId, String)>[
      (_beforeObject, _hashA),
      (_afterObject, _hashB),
    ]) {
      await database
          .into(database.revisionMetadata)
          .insert(
            RevisionMetadataCompanion.insert(
              sourceLineageId: _lineage.encoded,
              objectId: revision.$1.value,
              contentHash: revision.$2,
              fileCount: 1,
              byteSize: 2,
              declaredName: 'one',
              validationState: 'valid',
              createdAtMicros: 1,
            ),
          );
    }
    await database
        .into(database.currentRevisionSelection)
        .insert(
          CurrentRevisionSelectionCompanion.insert(
            managedSkillId: _skillId.value,
            sourceLineageId: _lineage.encoded,
            upstreamObjectId: _beforeObject.value,
            effectiveObjectId: _afterObject.value,
          ),
        );
    await database
        .into(database.draftWorkspaces)
        .insert(
          DraftWorkspacesCompanion.insert(
            managedSkillId: _skillId.value,
            sourceLineageId: _lineage.encoded,
            baseObjectId: _afterObject.value,
            purpose: 'customization',
            createdAtMicros: 3,
            updatedAtMicros: 3,
          ),
        );
    await _record(
      database,
      operationId: _beforeOperationId,
      subjectId: _beforeSubjectId,
      objectId: _beforeObject,
      hash: _hashA,
      completedAt: 4,
    );
    await _record(
      database,
      operationId: _afterOperationId,
      subjectId: _afterSubjectId,
      objectId: _afterObject,
      hash: _hashB,
      completedAt: 5,
    );
  });
}

Future<void> _record(
  WorkspaceDatabase database, {
  required String operationId,
  required String subjectId,
  required RevisionObjectId objectId,
  required String hash,
  required int completedAt,
}) async {
  await database
      .into(database.operationRecords)
      .insert(
        OperationRecordsCompanion.insert(
          operationId: operationId,
          kind: WorkspaceOperationKind.publishDraft.name,
          status: 'succeeded',
          startedAtMicros: completedAt - 1,
          completedAtMicros: completedAt,
          retainWithoutSubjects: const Value(false),
        ),
      );
  await database
      .into(database.operationSubjects)
      .insert(
        OperationSubjectsCompanion.insert(
          subjectId: subjectId,
          operationId: operationId,
          managedSkillId: _skillId.value,
          sourceLineageId: Value(_lineage.encoded),
          afterObjectId: Value(objectId.value),
          afterContentHash: Value(hash),
          displayName: 'One',
        ),
      );
}

ManagedSkill _skill() => ManagedSkill(
  id: _skillId,
  slotKey: 'one',
  declaredName: 'one',
  displayName: 'One',
  description: 'One Skill',
  source: LocalSourceDescriptor(locator: '/source/one'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: _hashB,
    fileCount: 1,
    byteSize: 2,
    publishedAt: DateTime.utc(2026, 8, 17),
  ),
  draft: DraftSummary(
    purpose: DraftPurpose.customization,
    path: '/drafts/${_skillId.value}',
    isDirty: false,
    updatedAt: DateTime.utc(2026, 8, 17),
  ),
);

NormalizedSkillTree _tree(List<NormalizedSkillFile> files) =>
    NormalizedSkillTree(
      files: files,
      contentHash: _hashA,
      byteSize: files.fold<int>(0, (size, file) => size + file.bytes.length),
    );

final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _lineage = SourceLineageReference('123e4567-e89b-42d3-8456-426614174001');
final _beforeObject = RevisionObjectId('1' * 40);
final _afterObject = RevisionObjectId('2' * 40);
const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _beforeOperationId = '123e4567-e89b-42d3-8456-426614174002';
const _beforeSubjectId = '123e4567-e89b-42d3-9456-426614174003';
const _afterOperationId = '123e4567-e89b-42d3-a456-426614174004';
const _afterSubjectId = '123e4567-e89b-42d3-b456-426614174005';
final _beforeReference = OperationSubjectReference(
  operationId: OperationId(_beforeOperationId),
  subjectId: _beforeSubjectId,
);
final _afterReference = OperationSubjectReference(
  operationId: OperationId(_afterOperationId),
  subjectId: _afterSubjectId,
);
