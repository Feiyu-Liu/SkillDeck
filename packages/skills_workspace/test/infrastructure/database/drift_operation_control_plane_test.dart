import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_operation_control_plane.dart';
import 'package:skills_workspace/src/infrastructure/database/operation_plan_codec.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:test/test.dart';

const _skillA = '123e4567-e89b-42d3-a456-426614174200';
const _skillB = '123e4567-e89b-42d3-b456-426614174201';
const _lineageA = '123e4567-e89b-42d3-8456-426614174202';
const _lineageB = '123e4567-e89b-42d3-9456-426614174203';
const _operationA = '123e4567-e89b-42d3-a456-426614174204';
const _operationB = '123e4567-e89b-42d3-b456-426614174205';
const _subjectA = '123e4567-e89b-42d3-8456-426614174206';
const _subjectB = '123e4567-e89b-42d3-9456-426614174207';
const _subjectC = '123e4567-e89b-42d3-a456-426614174209';
const _tagId = '123e4567-e89b-42d3-a456-426614174208';
const _objectA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _objectB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceDatabase database;
  late DriftOperationControlPlane controlPlane;
  late int now;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'operation-control-plane-',
    );
    database = WorkspaceDatabase.forFile(
      File('${temporaryDirectory.path}/workspace.sqlite'),
    );
    await database.workspaceMetadata.select().getSingle();
    now = DateTime.now().toUtc().microsecondsSinceEpoch;
    controlPlane = DriftOperationControlPlane(
      database: database,
      clock: () => now++,
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'persists an immutable Prepared Journal and every planned step',
    () async {
      final plan = _installPlan();

      await controlPlane.persistPrepared(plan);

      final journal = await database.operationJournals.select().getSingle();
      expect(journal.operationId, _operationA);
      expect(journal.kind, 'install');
      expect(journal.phase, 'prepared');
      expect(
        journal.planSchemaVersion,
        OperationPlanCodec.currentSchemaVersion,
      );
      expect(journal.committedRepositoryRevision, isNull);
      expect(
        const OperationPlanCodec()
            .decode(
              schemaVersion: journal.planSchemaVersion,
              payload: journal.planJson,
            )
            .operationId,
        plan.operationId,
      );
      final steps =
          await (database.operationJournalSteps.select()
                ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
              .get();
      expect(steps.map((row) => row.sequence), [0, 1, 2]);
      expect(steps.map((row) => row.stepId), [
        'prepare-revision',
        'replace-materialization',
        'cleanup-staging',
      ]);
      expect(steps.map((row) => row.status).toSet(), {'planned'});
      expect(
        await controlPlane.readRepositoryRevision(),
        RepositoryRevision(0),
      );
    },
  );

  test(
    'seals a Prepared envelope atomically and preserves step progress',
    () async {
      final plan = _installPlan();
      final envelope = _preparedEnvelopeFor(plan);

      await controlPlane.persistPreparedEnvelope(envelope);

      var journal = await database.operationJournals.select().getSingle();
      expect(
        const OperationPlanCodec().decodeDefinition(
          schemaVersion: journal.planSchemaVersion,
          payload: journal.planJson,
        ),
        isA<PreparedOperationEnvelope>(),
      );
      expect(await database.operationJournalSteps.select().get(), hasLength(1));
      await expectLater(
        controlPlane.markApplying(plan.operationId),
        throwsA(_stateReason('unsealedJournalCannotApply')),
      );

      await controlPlane.markStepStarted(
        plan.operationId,
        envelope.preparationSteps.single.stepId,
      );
      await controlPlane.markStepCompleted(
        plan.operationId,
        envelope.preparationSteps.single.stepId,
      );
      await controlPlane.sealPreparedPlan(envelope, plan);
      await controlPlane.sealPreparedPlan(envelope, plan);

      journal = await database.operationJournals.select().getSingle();
      expect(
        const OperationPlanCodec()
            .decode(
              schemaVersion: journal.planSchemaVersion,
              payload: journal.planJson,
            )
            .operationId,
        plan.operationId,
      );
      final steps =
          await (database.operationJournalSteps.select()
                ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
              .get();
      expect(steps, hasLength(3));
      expect(steps.map((row) => row.stepId), <String>[
        'prepare-revision',
        'replace-materialization',
        'cleanup-staging',
      ]);
      expect(steps.first.status, OperationStepStatus.completed.name);
      expect(steps.skip(1).map((row) => row.status).toSet(), <String>{
        OperationStepStatus.planned.name,
      });

      await controlPlane.markApplying(plan.operationId);
      expect(
        (await database.operationJournals.select().getSingle()).phase,
        OperationJournalPhase.applying.name,
      );
    },
  );

  test(
    'rolls back an unsealed envelope without inventing a full plan',
    () async {
      final plan = _installPlan();
      final envelope = _preparedEnvelopeFor(plan);
      await controlPlane.persistPreparedEnvelope(envelope);

      await controlPlane.completePreparedEnvelopeRollback(
        envelope,
        OperationAbortReason.preparationFailed,
      );

      final journal = await database.operationJournals.select().getSingle();
      expect(journal.phase, OperationJournalPhase.completed.name);
      expect(journal.committedRepositoryRevision, 0);
      final loaded = await controlPlane.loadRecoverableOperations();
      expect(loaded.single.definition, isA<PreparedOperationEnvelope>());
      expect(loaded.single.phase, OperationJournalPhase.completed);
    },
  );

  test('sealing mismatched envelope facts fails closed', () async {
    final plan = _installPlan();
    final envelope = _preparedEnvelopeFor(plan);
    await controlPlane.persistPreparedEnvelope(envelope);
    final mismatched = PreparedOperationEnvelope(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      committedRepositoryRevision: envelope.committedRepositoryRevision,
      operationGeneration: envelope.operationGeneration,
      preparationSteps: <PreparationOperationStep>[
        PreparationOperationStep(
          stepId: envelope.preparationSteps.single.stepId,
          recoveryReference: RecoveryReference('different-reference'),
          kind: envelope.preparationSteps.single.kind,
        ),
      ],
      record: envelope.record,
    );

    await expectLater(
      controlPlane.sealPreparedPlan(mismatched, plan),
      throwsA(_stateReason('sealedPlanDoesNotPreserveEnvelope')),
    );
    final durable = await controlPlane.loadRecoverableOperations();
    expect(durable.single.definition, isA<PreparedOperationEnvelope>());
  });

  test('step and phase transitions are monotonic and idempotent', () async {
    final plan = _installPlan();
    await controlPlane.persistPrepared(plan);

    await expectLater(
      controlPlane.markStepCompleted(plan.operationId, 'prepare-revision'),
      throwsA(_stateReason('illegalJournalStepTransition')),
    );
    await controlPlane.markStepStarted(plan.operationId, 'prepare-revision');
    await controlPlane.markStepStarted(plan.operationId, 'prepare-revision');
    await controlPlane.markStepCompleted(plan.operationId, 'prepare-revision');
    await controlPlane.markStepCompleted(plan.operationId, 'prepare-revision');
    await controlPlane.markStepStarted(plan.operationId, 'prepare-revision');
    expect(
      (await _step(database, 'prepare-revision')).status,
      OperationStepStatus.completed.name,
    );
    await expectLater(
      controlPlane.markStepStarted(plan.operationId, 'missing'),
      throwsA(_stateReason('missingJournalStep')),
    );

    await controlPlane.markApplying(plan.operationId);
    await controlPlane.markApplying(plan.operationId);
    expect(
      (await database.operationJournals.select().getSingle()).phase,
      OperationJournalPhase.applying.name,
    );
    await expectLater(
      controlPlane.markFinalizing(plan.operationId),
      throwsA(_stateReason('illegalJournalPhaseTransition')),
    );
  });

  test('rejects stale revisions before Prepared and at the BCP', () async {
    final plan = _installPlan();
    await _setRepositoryRevision(database, 1, now++);
    await expectLater(
      controlPlane.persistPrepared(plan),
      throwsA(
        isA<StaleControlPlaneRevision>()
            .having((error) => error.expected, 'expected', 0)
            .having((error) => error.actual, 'actual', 1),
      ),
    );
    expect(await database.operationJournals.select().get(), isEmpty);

    await _setRepositoryRevision(database, 0, now++);
    await controlPlane.persistPrepared(plan);
    await controlPlane.markApplying(plan.operationId);
    await _setRepositoryRevision(database, 2, now++);
    await expectLater(
      controlPlane.commitBusinessState(plan),
      throwsA(
        isA<StaleControlPlaneRevision>()
            .having((error) => error.expected, 'expected', 0)
            .having((error) => error.actual, 'actual', 2),
      ),
    );
    expect(await database.managedSkills.select().get(), isEmpty);
    expect(
      (await database.operationJournals.select().getSingle()).phase,
      OperationJournalPhase.applying.name,
    );
  });

  test(
    'atomically commits business rows, pointers, revisions, and Journal marker',
    () async {
      final plan = _fullProjectionPlan();
      await controlPlane.persistPrepared(plan);
      await controlPlane.markApplying(plan.operationId);

      await controlPlane.commitBusinessState(plan);

      final metadata = await database.workspaceMetadata.select().getSingle();
      expect(metadata.repositoryRevision, 1);
      expect(metadata.destructionEpoch, 1);
      expect(await database.managedSkills.select().get(), hasLength(1));
      expect(await database.sourceLineages.select().get(), hasLength(1));
      expect(await database.skillSources.select().get(), hasLength(1));
      expect(await database.revisionMetadata.select().get(), hasLength(2));
      final selection = await database.currentRevisionSelection
          .select()
          .getSingle();
      expect(selection.sourceLineageId, _lineageA);
      expect(selection.upstreamObjectId, _objectA);
      expect(selection.effectiveObjectId, _objectA);
      expect(await database.projectRoots.select().get(), hasLength(1));
      expect(await database.activationLocations.select().get(), hasLength(1));
      expect(
        (await database.activationAgents.select().get()).map(
          (row) => row.agentId,
        ),
        ['claude', 'codex'],
      );
      expect(
        (await database.skillUserData.select().getSingle()).favorite,
        isTrue,
      );
      expect(await database.personalTags.select().get(), hasLength(1));
      expect(await database.skillTagAssignments.select().get(), hasLength(1));
      expect(await database.draftWorkspaces.select().get(), hasLength(1));
      expect(
        await database.updateCandidateSessions.select().get(),
        hasLength(1),
      );
      expect(await database.updateCandidateItems.select().get(), hasLength(1));
      final journal = await database.operationJournals.select().getSingle();
      expect(journal.phase, OperationJournalPhase.committed.name);
      expect(journal.committedRepositoryRevision, 1);

      await controlPlane.markFinalizing(plan.operationId);
      await controlPlane.markFinalizing(plan.operationId);
      await controlPlane.complete(plan);
      await controlPlane.complete(plan);
      final record = await database.operationRecords.select().getSingle();
      expect(record.status, 'succeeded');
      expect(await database.operationSubjects.select().get(), hasLength(1));
      expect(
        (await database.operationJournals.select().getSingle()).phase,
        OperationJournalPhase.completed.name,
      );
    },
  );

  test('selection mismatch rolls back every BCP mutation', () async {
    await _seedSkillGraph(database, skillId: _skillA, lineageId: _lineageA);
    final wrongPrevious = RevisionAddress(
      sourceLineage: SourceLineageReference(_lineageA),
      objectId: RevisionObjectId(_objectB),
    );
    final plan = _plan(
      operationId: _operationA,
      kind: 'update',
      changes: WorkspaceBusinessChangeSet(
        mutations: [
          PutPersonalTag(
            personalTagId: _tagId,
            normalizedKey: 'work',
            displayName: 'Work',
            color: null,
            createdAtMicros: 1,
            updatedAtMicros: 1,
          ),
        ],
      ),
      selections: [
        RevisionSelectionChangePlan(
          managedSkillId: ManagedSkillId(_skillA),
          previousUpstream: wrongPrevious,
          previousEffective: wrongPrevious,
          intendedUpstream: wrongPrevious,
          intendedEffective: wrongPrevious,
        ),
      ],
      subjects: [_subject(_operationA, _subjectA, _skillA, _lineageA)],
    );
    await controlPlane.persistPrepared(plan);
    await controlPlane.markApplying(plan.operationId);

    await expectLater(
      controlPlane.commitBusinessState(plan),
      throwsA(_stateReason('revisionSelectionMismatch')),
    );

    expect(await database.personalTags.select().get(), isEmpty);
    expect(
      (await database.currentRevisionSelection.select().getSingle())
          .upstreamObjectId,
      _objectA,
    );
    expect(
      (await database.operationJournals.select().getSingle()).phase,
      OperationJournalPhase.applying.name,
    );
  });

  test(
    'conflict resolution atomically updates item and Session time',
    () async {
      final initial = _fullProjectionPlan();
      await controlPlane.persistPrepared(initial);
      await controlPlane.markApplying(initial.operationId);
      await controlPlane.commitBusinessState(initial);
      await controlPlane.markFinalizing(initial.operationId);
      await controlPlane.complete(initial);
      await controlPlane.deleteCompletedJournal(initial.operationId);

      final resolution = _plan(
        operationId: _operationB,
        kind: 'resolveUpdateConflict',
        expectedRevision: 1,
        changes: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            SetUpdateCandidateItemResolution(
              managedSkillId: ManagedSkillId(_skillA),
              path: 'SKILL.md',
              state: WorkspaceUpdateCandidateItemState.resolved,
              updatedAtMicros: 99,
            ),
          ],
        ),
        selections: const <RevisionSelectionChangePlan>[],
        subjects: <OperationSubjectPlan>[
          _subject(_operationB, _subjectC, _skillA, _lineageA),
        ],
      );
      await controlPlane.persistPrepared(resolution);
      await controlPlane.markApplying(resolution.operationId);
      await controlPlane.commitBusinessState(resolution);

      expect(
        (await database.updateCandidateItems.select().getSingle()).state,
        WorkspaceUpdateCandidateItemState.resolved.name,
      );
      expect(
        (await database.updateCandidateSessions.select().getSingle())
            .updatedAtMicros,
        99,
      );
      expect(
        await controlPlane.readRepositoryRevision(),
        RepositoryRevision(2),
      );
    },
  );

  test(
    'constraint failure rolls back all business and commit metadata',
    () async {
      final base = _installPlan();
      final mutations = [...base.businessChanges.mutations];
      final sourceIndex = mutations.indexWhere(
        (item) => item is PutSkillSource,
      );
      mutations[sourceIndex] = PutSkillSource(
        sourceLineageId: _lineageA,
        kind: WorkspaceSourceKind.git,
        payloadSchemaVersion: 1,
        payloadJson: 'not-json',
      );
      final plan = _plan(
        operationId: _operationA,
        kind: 'install',
        changes: WorkspaceBusinessChangeSet(mutations: mutations),
        selections: base.revisionSelectionChanges,
        subjects: base.record.subjects,
      );
      await controlPlane.persistPrepared(plan);
      await controlPlane.markApplying(plan.operationId);

      await expectLater(
        controlPlane.commitBusinessState(plan),
        throwsA(anything),
      );

      expect(await database.managedSkills.select().get(), isEmpty);
      expect(await database.sourceLineages.select().get(), isEmpty);
      expect(await database.revisionMetadata.select().get(), isEmpty);
      expect(await database.currentRevisionSelection.select().get(), isEmpty);
      final metadata = await database.workspaceMetadata.select().getSingle();
      expect(metadata.repositoryRevision, 0);
      expect(metadata.destructionEpoch, 0);
      final journal = await database.operationJournals.select().getSingle();
      expect(journal.phase, OperationJournalPhase.applying.name);
      expect(journal.committedRepositoryRevision, isNull);
    },
  );

  test(
    'DeleteProjectRoot retains project Activation path and provenance',
    () async {
      await _seedSkillGraph(database, skillId: _skillA, lineageId: _lineageA);
      await database
          .into(database.projectRoots)
          .insert(
            ProjectRootsCompanion.insert(
              id: 'project-root',
              canonicalPath: '/workspace/project',
              createdAtMicros: 1,
              updatedAtMicros: 1,
            ),
          );
      await database
          .into(database.activationLocations)
          .insert(
            ActivationLocationsCompanion.insert(
              id: '123e4567-e89b-42d3-b456-426614174209',
              managedSkillId: _skillA,
              canonicalPath: '/workspace/project/.claude/skills/reviewer',
              scope: 'project',
              mode: 'copy',
              projectRootId: const Value('project-root'),
              projectRootPath: const Value('/workspace/project'),
              createdAtMicros: 1,
            ),
          );
      final plan = _plan(
        operationId: _operationA,
        kind: 'unregisterProjectRoot',
        changes: WorkspaceBusinessChangeSet(
          mutations: [DeleteProjectRoot('project-root')],
        ),
        selections: const [],
        subjects: [_subject(_operationA, _subjectA, _skillA, _lineageA)],
      );
      await controlPlane.persistPrepared(plan);
      await controlPlane.markApplying(plan.operationId);

      await controlPlane.commitBusinessState(plan);

      expect(await database.projectRoots.select().get(), isEmpty);
      final activation = await database.activationLocations
          .select()
          .getSingle();
      expect(activation.projectRootId, 'project-root');
      expect(activation.projectRootPath, '/workspace/project');
      expect(
        activation.canonicalPath,
        '/workspace/project/.claude/skills/reviewer',
      );
      expect(
        await controlPlane.readRepositoryRevision(),
        RepositoryRevision(1),
      );
    },
  );

  test(
    'Removal filters deleted subjects but retains unrelated history subjects',
    () async {
      await _seedSkillGraph(database, skillId: _skillA, lineageId: _lineageA);
      await _seedSkillGraph(
        database,
        skillId: _skillB,
        lineageId: _lineageB,
        slotKey: 'writer',
      );
      final oldAddress = RevisionAddress(
        sourceLineage: SourceLineageReference(_lineageA),
        objectId: RevisionObjectId(_objectA),
      );
      final plan = _plan(
        operationId: _operationA,
        kind: 'remove',
        changes: WorkspaceBusinessChangeSet(
          incrementsDestructionEpoch: true,
          mutations: [DeleteManagedSkill(ManagedSkillId(_skillA))],
        ),
        selections: [
          RevisionSelectionChangePlan(
            managedSkillId: ManagedSkillId(_skillA),
            previousUpstream: oldAddress,
            previousEffective: oldAddress,
            intendedUpstream: null,
            intendedEffective: null,
          ),
        ],
        subjects: [
          _subject(_operationA, _subjectA, _skillA, _lineageA),
          _subject(_operationA, _subjectB, _skillB, _lineageB),
        ],
      );
      await controlPlane.persistPrepared(plan);
      await controlPlane.markApplying(plan.operationId);
      await controlPlane.commitBusinessState(plan);
      await controlPlane.markFinalizing(plan.operationId);
      await controlPlane.complete(plan);

      expect(
        (await database.managedSkills.select().get()).map((row) => row.id),
        [_skillB],
      );
      final record = await database.operationRecords.select().getSingle();
      expect(record.status, 'succeeded');
      final subjects = await database.operationSubjects.select().get();
      expect(subjects, hasLength(1));
      expect(subjects.single.managedSkillId, _skillB);
      expect(
        (await database.workspaceMetadata.select().getSingle())
            .destructionEpoch,
        1,
      );
    },
  );

  test(
    'rollback completion is recoverable and completed cleanup is safe',
    () async {
      await _seedSkillGraph(database, skillId: _skillA, lineageId: _lineageA);
      final plan = _plan(
        operationId: _operationA,
        kind: 'publishDraft',
        changes: WorkspaceBusinessChangeSet.empty,
        selections: const [],
        subjects: [_subject(_operationA, _subjectA, _skillA, _lineageA)],
      );
      await controlPlane.persistPrepared(plan);
      await controlPlane.markStepStarted(plan.operationId, 'prepare-revision');
      await controlPlane.markStepCompleted(
        plan.operationId,
        'prepare-revision',
      );

      await expectLater(
        controlPlane.deleteCompletedJournal(plan.operationId),
        throwsA(_stateReason('journalNotCompleted')),
      );
      await controlPlane.completeRollback(
        plan,
        OperationAbortReason.preparationFailed,
      );
      await controlPlane.completeRollback(
        plan,
        OperationAbortReason.preparationFailed,
      );

      final record = await database.operationRecords.select().getSingle();
      expect(record.status, 'failed');
      final journal = await database.operationJournals.select().getSingle();
      expect(journal.phase, OperationJournalPhase.completed.name);
      expect(journal.committedRepositoryRevision, 0);
      final recoverable = await controlPlane.loadRecoverableOperations();
      expect(recoverable, hasLength(1));
      expect(recoverable.single.phase, OperationJournalPhase.completed);
      expect(
        recoverable.single.stepStatuses['prepare-revision'],
        OperationStepStatus.completed,
      );
      expect(
        recoverable.single.stepStatuses['replace-materialization'],
        OperationStepStatus.planned,
      );

      await controlPlane.deleteCompletedJournal(plan.operationId);
      await controlPlane.deleteCompletedJournal(plan.operationId);
      expect(await controlPlane.loadRecoverableOperations(), isEmpty);
      expect(await database.operationRecords.select().get(), hasLength(1));
    },
  );

  test(
    'recovery loading fails closed on malformed durable plan data',
    () async {
      final plan = _installPlan();
      await controlPlane.persistPrepared(plan);
      await (database.update(database.operationJournals)
            ..where((row) => row.operationId.equals(plan.operationId.value)))
          .write(const OperationJournalsCompanion(planJson: Value('{}')));

      await expectLater(
        controlPlane.loadRecoverableOperations(),
        throwsA(_stateReason('invalidJournalPlan')),
      );
    },
  );
}

OperationPlan _installPlan({bool incrementsDestructionEpoch = false}) {
  final skillId = ManagedSkillId(_skillA);
  final lineage = SourceLineageReference(_lineageA);
  final address = RevisionAddress(
    sourceLineage: lineage,
    objectId: RevisionObjectId(_objectA),
  );
  return _plan(
    operationId: _operationA,
    kind: 'install',
    changes: WorkspaceBusinessChangeSet(
      incrementsDestructionEpoch: incrementsDestructionEpoch,
      mutations: [
        PutManagedSkill(
          managedSkillId: skillId,
          slotKey: 'reviewer',
          declaredName: 'reviewer',
          displayName: 'Reviewer',
          description: 'Reviews code.',
          activeSourceLineageId: _lineageA,
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
        PutSourceLineage(
          sourceLineageId: _lineageA,
          managedSkillId: skillId,
          objectFormat: WorkspaceObjectFormat.sha1,
          createdAtMicros: 1,
        ),
        PutSkillSource(
          sourceLineageId: _lineageA,
          kind: WorkspaceSourceKind.local,
          payloadSchemaVersion: 1,
          payloadJson: '{"path":"/skills/reviewer"}',
        ),
        PutRevisionMetadata(
          sourceLineageId: _lineageA,
          objectId: _objectA,
          contentHash: _hashA,
          fileCount: 1,
          byteSize: 100,
          declaredName: 'reviewer',
          validationState: WorkspaceRevisionValidationState.valid,
          validationCode: null,
          createdAtMicros: 1,
        ),
      ],
    ),
    selections: [
      RevisionSelectionChangePlan(
        managedSkillId: skillId,
        previousUpstream: null,
        previousEffective: null,
        intendedUpstream: address,
        intendedEffective: address,
      ),
    ],
    subjects: [_subject(_operationA, _subjectA, _skillA, _lineageA)],
  );
}

PreparedOperationEnvelope _preparedEnvelopeFor(OperationPlan plan) =>
    PreparedOperationEnvelope(
      operationId: plan.operationId,
      expectedRepositoryRevision: plan.expectedRepositoryRevision,
      committedRepositoryRevision: plan.committedRepositoryRevision,
      operationGeneration: plan.operationGeneration,
      preparationSteps: <PreparationOperationStep>[plan.preparationSteps.first],
      record: OperationRecordPlan(
        operationId: plan.operationId,
        kind: plan.record.kind,
        retainWithoutSubjects: true,
        subjects: const <OperationSubjectPlan>[],
      ),
    );

OperationPlan _fullProjectionPlan() {
  final base = _installPlan(incrementsDestructionEpoch: true);
  return _plan(
    operationId: _operationA,
    kind: 'install',
    changes: WorkspaceBusinessChangeSet(
      incrementsDestructionEpoch: true,
      mutations: [
        ...base.businessChanges.mutations,
        PutRevisionMetadata(
          sourceLineageId: _lineageA,
          objectId: _objectB,
          contentHash: _hashB,
          fileCount: 2,
          byteSize: 200,
          declaredName: 'reviewer',
          validationState: WorkspaceRevisionValidationState.valid,
          validationCode: null,
          createdAtMicros: 2,
        ),
        PutProjectRoot(
          projectRootId: 'project-root',
          canonicalPath: '/workspace/project',
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
        PutActivation(
          activationId: '123e4567-e89b-42d3-b456-426614174209',
          managedSkillId: ManagedSkillId(_skillA),
          canonicalPath: '/workspace/project/.claude/skills/reviewer',
          scope: WorkspaceActivationScope.project,
          mode: WorkspaceActivationMode.copy,
          projectRootId: 'project-root',
          projectRootPath: '/workspace/project',
          agentIds: const ['claude', 'codex'],
          createdAtMicros: 1,
        ),
        PutSkillUserData(
          managedSkillId: ManagedSkillId(_skillA),
          favorite: true,
          favoriteChangedAtMicros: 1,
          note: 'Important',
          noteUpdatedAtMicros: 1,
        ),
        PutPersonalTag(
          personalTagId: _tagId,
          normalizedKey: 'work',
          displayName: 'Work',
          color: '#112233',
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
        PutSkillTagAssignment(
          managedSkillId: ManagedSkillId(_skillA),
          personalTagId: _tagId,
          createdAtMicros: 1,
        ),
        PutDraftWorkspace(
          managedSkillId: ManagedSkillId(_skillA),
          sourceLineageId: _lineageA,
          baseObjectId: _objectA,
          purpose: WorkspaceDraftPurpose.customization,
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
        PutUpdateCandidateSession(
          managedSkillId: ManagedSkillId(_skillA),
          sourceLineageId: _lineageA,
          previousUpstreamObjectId: _objectA,
          previousEffectiveObjectId: _objectA,
          incomingUpstreamObjectId: _objectB,
          candidateObjectId: 'candidate-tree',
          status: WorkspaceUpdateCandidateStatus.conflicted,
          validationCode: null,
          items: [
            WorkspaceUpdateCandidateItem(
              path: 'SKILL.md',
              kind: WorkspaceUpdateCandidateItemKind.text,
              state: WorkspaceUpdateCandidateItemState.unresolved,
              baseObjectId: _objectA,
              oursObjectId: _objectA,
              theirsObjectId: _objectB,
            ),
          ],
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
      ],
    ),
    selections: base.revisionSelectionChanges,
    subjects: base.record.subjects,
  );
}

OperationPlan _plan({
  required String operationId,
  required String kind,
  required WorkspaceBusinessChangeSet changes,
  required List<RevisionSelectionChangePlan> selections,
  required List<OperationSubjectPlan> subjects,
  int expectedRevision = 0,
}) {
  final id = OperationId(operationId);
  return OperationPlan(
    operationId: id,
    expectedRepositoryRevision: RepositoryRevision(expectedRevision),
    committedRepositoryRevision: RepositoryRevision(expectedRevision + 1),
    operationGeneration: 1,
    preparationSteps: [
      PreparationOperationStep(
        stepId: 'prepare-revision',
        recoveryReference: RecoveryReference('prepare:$operationId'),
        kind: PreparationStepKind.revisionCandidate,
      ),
    ],
    applyingSteps: [
      ApplyingOperationStep(
        stepId: 'replace-materialization',
        recoveryReference: RecoveryReference('apply:$operationId'),
        kind: ApplyingStepKind.materializationReplacement,
      ),
    ],
    finalizationSteps: [
      FinalizationOperationStep(
        stepId: 'cleanup-staging',
        recoveryReference: RecoveryReference('finalize:$operationId'),
        kind: FinalizationStepKind.stagingCleanup,
      ),
    ],
    revisionSelectionChanges: selections,
    businessChanges: changes,
    record: OperationRecordPlan(
      operationId: id,
      kind: kind,
      subjects: subjects,
    ),
  );
}

OperationSubjectPlan _subject(
  String operationId,
  String subjectId,
  String skillId,
  String lineageId,
) => OperationSubjectPlan(
  reference: OperationSubjectReference(
    operationId: OperationId(operationId),
    subjectId: subjectId,
  ),
  managedSkillId: ManagedSkillId(skillId),
  displayName: skillId == _skillA ? 'Reviewer' : 'Writer',
  sourceLineage: SourceLineageReference(lineageId),
  beforeObjectId: RevisionObjectId(_objectA),
  afterObjectId: RevisionObjectId(_objectA),
  beforeContentHash: _hashA,
  afterContentHash: _hashA,
);

Future<void> _seedSkillGraph(
  WorkspaceDatabase database, {
  required String skillId,
  required String lineageId,
  String slotKey = 'reviewer',
}) => database.transaction(() async {
  await database
      .into(database.managedSkills)
      .insert(
        ManagedSkillsCompanion.insert(
          id: skillId,
          slotKey: slotKey,
          declaredName: slotKey,
          displayName: slotKey,
          description: 'Description',
          activeSourceLineageId: lineageId,
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
      );
  await database
      .into(database.sourceLineages)
      .insert(
        SourceLineagesCompanion.insert(
          id: lineageId,
          managedSkillId: skillId,
          objectFormat: 'sha1',
          createdAtMicros: 1,
        ),
      );
  await database
      .into(database.skillSources)
      .insert(
        SkillSourcesCompanion.insert(
          sourceLineageId: lineageId,
          kind: 'local',
          payloadSchemaVersion: 1,
          payloadJson: '{"path":"/skills/$slotKey"}',
        ),
      );
  await database
      .into(database.revisionMetadata)
      .insert(
        RevisionMetadataCompanion.insert(
          sourceLineageId: lineageId,
          objectId: _objectA,
          contentHash: skillId == _skillA ? _hashA : _hashB,
          fileCount: 1,
          byteSize: 1,
          declaredName: slotKey,
          validationState: 'valid',
          createdAtMicros: 1,
        ),
      );
  await database
      .into(database.currentRevisionSelection)
      .insert(
        CurrentRevisionSelectionCompanion.insert(
          managedSkillId: skillId,
          sourceLineageId: lineageId,
          upstreamObjectId: _objectA,
          effectiveObjectId: _objectA,
        ),
      );
});

Future<void> _setRepositoryRevision(
  WorkspaceDatabase database,
  int revision,
  int updatedAtMicros,
) =>
    (database.update(
      database.workspaceMetadata,
    )..where((row) => row.singleton.equals(1))).write(
      WorkspaceMetadataCompanion(
        repositoryRevision: Value(revision),
        updatedAtMicros: Value(updatedAtMicros),
      ),
    );

Future<OperationJournalStep> _step(WorkspaceDatabase database, String stepId) =>
    (database.operationJournalSteps.select()
          ..where((row) => row.stepId.equals(stepId)))
        .getSingle();

Matcher _stateReason(String reason) =>
    isA<OperationControlPlaneStateException>().having(
      (error) => error.reason,
      'reason',
      reason,
    );
