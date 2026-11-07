import 'dart:io';

import 'package:drift/drift.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_revision_reference_reconciliation.dart';
import 'package:skills_workspace/src/infrastructure/database/operation_plan_codec.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late WorkspaceLayout layout;
  late WorkspaceDatabase database;
  late _RevisionEngine engine;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-retention-reconciliation-',
    );
    layout = WorkspaceLayout(temporary.path);
    database = WorkspaceDatabase.forFile(File(layout.databasePath));
    await database.workspaceMetadata.select().getSingle();
    await _seed(database);
    engine = _RevisionEngine();
  });

  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  test(
    'replaces refs from current, history, session, and Journal authority',
    () async {
      final reconciler = DriftWorkspaceRevisionReferenceReconciliation(
        database: database,
        layout: layout,
        revisionEngine: engine,
      );

      await reconciler.reconcileRevisionReferences(isolatedSkillIds: const {});

      expect(engine.calls, hasLength(1));
      final active = engine.calls.singleWhere(
        (call) => call.repositoryPath.endsWith(
          '${Platform.pathSeparator}$_skill.git',
        ),
      );
      final expectedObjects = <String>[
        _upstream,
        _effective,
        _published,
        _incoming,
        _candidate,
        _journalUpstream,
        _journalEffective,
        _draftBase,
      ]..sort();
      expect(
        active.references.map((reference) => reference.target.value),
        orderedEquals(expectedObjects),
      );
      expect(
        active.references.map((reference) => reference.name),
        orderedEquals(<String>[
          for (var index = 0; index < expectedObjects.length; index += 1)
            'refs/skills-workspace/r/${index.toRadixString(36)}',
        ]),
      );
      expect(
        active.references.every((reference) => reference.name.length < 32),
        isTrue,
      );
    },
  );

  test('is idempotent and never reads refs to elect business state', () async {
    final reconciler = DriftWorkspaceRevisionReferenceReconciliation(
      database: database,
      layout: layout,
      revisionEngine: engine,
    );

    await reconciler.reconcileRevisionReferences(isolatedSkillIds: const {});
    final first = engine.calls
        .map(
          (call) =>
              '${call.repositoryPath}\n${call.references.map((reference) => '${reference.name}=${reference.target.value}').join('\n')}',
        )
        .toList();
    engine.calls.clear();
    await reconciler.reconcileRevisionReferences(isolatedSkillIds: const {});

    expect(
      engine.calls.map(
        (call) =>
            '${call.repositoryPath}\n${call.references.map((reference) => '${reference.name}=${reference.target.value}').join('\n')}',
      ),
      first,
    );
  });

  test('leaves isolated Skill Stores untouched', () async {
    final reconciler = DriftWorkspaceRevisionReferenceReconciliation(
      database: database,
      layout: layout,
      revisionEngine: engine,
    );

    await reconciler.reconcileRevisionReferences(
      isolatedSkillIds: <ManagedSkillId>{ManagedSkillId(_skill)},
    );

    expect(engine.calls, isEmpty);
  });

  test('operation scope leaves unrelated Skill Stores untouched', () async {
    await _seedUnrelatedSkill(database);
    final reconciler = DriftWorkspaceRevisionReferenceReconciliation(
      database: database,
      layout: layout,
      revisionEngine: engine,
    );

    await reconciler.reconcileRevisionReferences(
      isolatedSkillIds: const {},
      selectedSkillIds: <ManagedSkillId>{ManagedSkillId(_skill)},
    );

    expect(engine.calls, hasLength(1));
    expect(
      engine.calls.single.repositoryPath,
      endsWith('${Platform.pathSeparator}$_skill.git'),
    );
  });

  test('does not retain candidates from a terminal Journal', () async {
    await (database.update(
      database.operationJournals,
    )..where((row) => row.operationId.equals(_journalOperation))).write(
      const OperationJournalsCompanion(
        phase: Value('completed'),
        committedRepositoryRevision: Value(1),
      ),
    );
    final reconciler = DriftWorkspaceRevisionReferenceReconciliation(
      database: database,
      layout: layout,
      revisionEngine: engine,
    );

    await reconciler.reconcileRevisionReferences(isolatedSkillIds: const {});

    expect(
      engine.calls
          .expand((call) => call.references)
          .map((reference) => reference.target.value),
      isNot(contains(_journalEffective)),
    );
  });

  test(
    'candidate abandonment retains only current and published authority',
    () async {
      await database.transaction(() async {
        await database.delete(database.updateCandidateSessions).go();
        await database.delete(database.draftWorkspaces).go();
        await (database.update(
          database.operationJournals,
        )..where((row) => row.operationId.equals(_journalOperation))).write(
          const OperationJournalsCompanion(
            phase: Value('completed'),
            committedRepositoryRevision: Value(1),
          ),
        );
      });
      final reconciler = DriftWorkspaceRevisionReferenceReconciliation(
        database: database,
        layout: layout,
        revisionEngine: engine,
      );

      await reconciler.reconcileRevisionReferences(isolatedSkillIds: const {});

      final active = engine.calls.singleWhere(
        (call) => call.repositoryPath.endsWith(
          '${Platform.pathSeparator}$_skill.git',
        ),
      );
      final retainedObjects = active.references
          .map((reference) => reference.target.value)
          .toList(growable: false);
      expect(
        retainedObjects,
        orderedEquals(<String>[_upstream, _effective, _published]..sort()),
      );
      for (final abandonedObject in <String>[
        _incoming,
        _candidate,
        _draftBase,
        _journalUpstream,
        _journalEffective,
      ]) {
        expect(
          retainedObjects,
          isNot(contains(abandonedObject)),
          reason: '$abandonedObject no longer has durable retention authority',
        );
      }
    },
  );
}

Future<void> _seed(WorkspaceDatabase database) =>
    database.transaction(() async {
      await database
          .into(database.managedSkills)
          .insert(
            ManagedSkillsCompanion.insert(
              id: _skill,
              slotKey: 'sample',
              declaredName: 'sample',
              displayName: 'Sample',
              description: 'Sample Skill',
              activeSourceLineageId: _lineage,
              createdAtMicros: 1,
              updatedAtMicros: 1,
            ),
          );
      for (final entry in <(String, int)>[(_lineage, 4), (_unusedLineage, 5)]) {
        await database
            .into(database.sourceLineages)
            .insert(
              SourceLineagesCompanion.insert(
                id: entry.$1,
                managedSkillId: _skill,
                objectFormat: 'sha1',
                createdAtMicros: 1,
              ),
            );
      }
      for (final object in <String>{
        _upstream,
        _effective,
        _published,
        _incoming,
        _draftBase,
      }) {
        await database
            .into(database.revisionMetadata)
            .insert(
              RevisionMetadataCompanion.insert(
                sourceLineageId: _lineage,
                objectId: object,
                contentHash: _hash,
                fileCount: 1,
                byteSize: 1,
                declaredName: 'sample',
                validationState: 'valid',
                createdAtMicros: 1,
              ),
            );
      }
      await database
          .into(database.currentRevisionSelection)
          .insert(
            CurrentRevisionSelectionCompanion.insert(
              managedSkillId: _skill,
              sourceLineageId: _lineage,
              upstreamObjectId: _upstream,
              effectiveObjectId: _effective,
            ),
          );
      await database
          .into(database.draftWorkspaces)
          .insert(
            DraftWorkspacesCompanion.insert(
              managedSkillId: _skill,
              sourceLineageId: _lineage,
              baseObjectId: _draftBase,
              purpose: 'customization',
              createdAtMicros: 2,
              updatedAtMicros: 2,
            ),
          );
      await database
          .into(database.updateCandidateSessions)
          .insert(
            UpdateCandidateSessionsCompanion.insert(
              managedSkillId: _skill,
              sourceLineageId: _lineage,
              previousUpstreamObjectId: _upstream,
              previousEffectiveObjectId: _effective,
              incomingUpstreamObjectId: _incoming,
              candidateObjectId: _candidate,
              status: 'conflicted',
              createdAtMicros: 2,
              updatedAtMicros: 2,
            ),
          );
      await database
          .into(database.operationRecords)
          .insert(
            OperationRecordsCompanion.insert(
              operationId: _publishedOperation,
              kind: 'publish',
              status: 'succeeded',
              startedAtMicros: 1,
              completedAtMicros: 2,
            ),
          );
      await database
          .into(database.operationSubjects)
          .insert(
            OperationSubjectsCompanion.insert(
              subjectId: _publishedSubject,
              operationId: _publishedOperation,
              managedSkillId: _skill,
              sourceLineageId: Value(_lineage),
              beforeObjectId: Value(_upstream),
              afterObjectId: Value(_published),
              displayName: 'Sample',
            ),
          );

      final plan = OperationPlan(
        operationId: OperationId(_journalOperation),
        expectedRepositoryRevision: RepositoryRevision(0),
        committedRepositoryRevision: RepositoryRevision(1),
        operationGeneration: 1,
        preparationSteps: const [],
        applyingSteps: const [],
        finalizationSteps: const [],
        revisionSelectionChanges: <RevisionSelectionChangePlan>[
          RevisionSelectionChangePlan(
            managedSkillId: ManagedSkillId(_skill),
            previousUpstream: _address(_upstream),
            previousEffective: _address(_effective),
            intendedUpstream: _address(_journalUpstream),
            intendedEffective: _address(_journalEffective),
          ),
        ],
        record: OperationRecordPlan(
          operationId: OperationId(_journalOperation),
          kind: 'update',
          retainWithoutSubjects: false,
          subjects: <OperationSubjectPlan>[
            OperationSubjectPlan(
              reference: OperationSubjectReference(
                operationId: OperationId(_journalOperation),
                subjectId: _journalSubject,
              ),
              managedSkillId: ManagedSkillId(_skill),
              displayName: 'Sample',
              sourceLineage: SourceLineageReference(_lineage),
              beforeObjectId: RevisionObjectId(_effective),
              afterObjectId: RevisionObjectId(_journalEffective),
            ),
          ],
        ),
      );
      await database
          .into(database.operationJournals)
          .insert(
            OperationJournalsCompanion.insert(
              operationId: _journalOperation,
              kind: 'update',
              phase: OperationJournalPhase.applying.name,
              planSchemaVersion: OperationPlanCodec.currentSchemaVersion,
              planJson: const OperationPlanCodec().encode(plan),
              operationGeneration: 1,
              startedAtMicros: 3,
              updatedAtMicros: 3,
            ),
          );
    });

Future<void> _seedUnrelatedSkill(WorkspaceDatabase database) =>
    database.transaction(() async {
      await database
          .into(database.managedSkills)
          .insert(
            ManagedSkillsCompanion.insert(
              id: _otherSkill,
              slotKey: 'other',
              declaredName: 'other',
              displayName: 'Other',
              description: 'Other Skill',
              activeSourceLineageId: _otherLineage,
              createdAtMicros: 1,
              updatedAtMicros: 1,
            ),
          );
      await database
          .into(database.sourceLineages)
          .insert(
            SourceLineagesCompanion.insert(
              id: _otherLineage,
              managedSkillId: _otherSkill,
              objectFormat: 'sha1',
              createdAtMicros: 1,
            ),
          );
      await database
          .into(database.revisionMetadata)
          .insert(
            RevisionMetadataCompanion.insert(
              sourceLineageId: _otherLineage,
              objectId: _otherObject,
              contentHash: _hash,
              fileCount: 1,
              byteSize: 1,
              declaredName: 'other',
              validationState: 'valid',
              createdAtMicros: 1,
            ),
          );
      await database
          .into(database.currentRevisionSelection)
          .insert(
            CurrentRevisionSelectionCompanion.insert(
              managedSkillId: _otherSkill,
              sourceLineageId: _otherLineage,
              upstreamObjectId: _otherObject,
              effectiveObjectId: _otherObject,
            ),
          );
    });

RevisionAddress _address(String object) => RevisionAddress(
  sourceLineage: SourceLineageReference(_lineage),
  objectId: RevisionObjectId(object),
);

final class _ReplaceCall {
  const _ReplaceCall(this.repositoryPath, this.references);

  final String repositoryPath;
  final List<RevisionRetentionRef> references;
}

final class _RevisionEngine implements RevisionEnginePort {
  final List<_ReplaceCall> calls = <_ReplaceCall>[];

  @override
  Future<void> replaceRetentionRefs(
    String repositoryPath,
    List<RevisionRetentionRef> references,
  ) async {
    calls.add(_ReplaceCall(repositoryPath, List.of(references)));
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
  Future<List<RevisionChange>> diff({
    required String repositoryPath,
    required RevisionObjectId oldCommit,
    required RevisionObjectId newCommit,
  }) => throw UnimplementedError();
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
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commit,
  ) => throw UnimplementedError();
  @override
  Future<void> restoreRecoveryPack({
    required String stagedRepositoryPath,
    required String packPath,
    required String indexPath,
    required List<RevisionObjectId> retainedRoots,
  }) => throw UnimplementedError();
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

const _skill = '123e4567-e89b-42d3-a456-426614174000';
const _otherSkill = '123e4567-e89b-42d3-a456-426614174100';
const _lineage = '123e4567-e89b-42d3-8456-426614174001';
const _otherLineage = '123e4567-e89b-42d3-8456-426614174101';
const _unusedLineage = '123e4567-e89b-42d3-9456-426614174002';
const _publishedOperation = '123e4567-e89b-42d3-a456-426614174010';
const _publishedSubject = '123e4567-e89b-42d3-8456-426614174011';
const _journalOperation = '123e4567-e89b-42d3-b456-426614174020';
const _journalSubject = '123e4567-e89b-42d3-9456-426614174021';
const _upstream = '1111111111111111111111111111111111111111';
const _effective = '2222222222222222222222222222222222222222';
const _published = '3333333333333333333333333333333333333333';
const _incoming = '4444444444444444444444444444444444444444';
const _draftBase = '8888888888888888888888888888888888888888';
const _candidate = '5555555555555555555555555555555555555555';
const _journalUpstream = '6666666666666666666666666666666666666666';
const _journalEffective = '7777777777777777777777777777777777777777';
const _otherObject = '9999999999999999999999999999999999999999';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
