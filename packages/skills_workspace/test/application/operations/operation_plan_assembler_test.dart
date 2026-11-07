import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

const _operation = '123e4567-e89b-42d3-a456-426614174510';
const _skill = '123e4567-e89b-42d3-b456-426614174511';
const _otherSkill = '123e4567-e89b-42d3-b456-426614174513';
const _subject = '123e4567-e89b-42d3-8456-426614174512';

void main() {
  test('binds SQLite-only changes and recovery to the public Operation ID', () {
    final recovery = _RecoveryPlans();
    final assembler = OperationPlanAssembler(
      subjectIdentities: _SubjectIdentities(),
      recoveryPlans: recovery,
    );
    final operationId = OperationId(_operation);
    final managedSkillId = ManagedSkillId(_skill);

    final plan = assembler.sqliteOnly(
      operationId: operationId,
      expectedRepositoryRevision: RepositoryRevision(7),
      kind: WorkspaceOperationKind.setFavorite,
      businessChanges: WorkspaceBusinessChangeSet(
        mutations: [
          PutSkillUserData(
            managedSkillId: managedSkillId,
            favorite: true,
            favoriteChangedAtMicros: 10,
            note: null,
            noteUpdatedAtMicros: null,
          ),
        ],
      ),
      subjects: [
        OperationSubjectIntent(
          managedSkillId: managedSkillId,
          displayName: 'Reviewer',
        ),
      ],
    );

    expect(plan.operationId, operationId);
    expect(plan.expectedRepositoryRevision, RepositoryRevision(7));
    expect(plan.committedRepositoryRevision, RepositoryRevision(8));
    expect(plan.operationGeneration, 8);
    expect(plan.record.kind, WorkspaceOperationKind.setFavorite.name);
    expect(plan.record.subjects.single.reference.operationId, operationId);
    expect(plan.record.subjects.single.reference.subjectId, _subject);
    expect(plan.businessChanges.mutations, hasLength(1));
    expect(plan.preparationSteps.single.stepId, 'prepare');
    expect(plan.finalizationSteps.single.stepId, 'backup');
    expect(recovery.operationId, operationId);
    expect(recovery.destructive, isFalse);
  });

  test('passes destruction epoch intent to the recovery plan factory', () {
    final recovery = _RecoveryPlans();
    final assembler = OperationPlanAssembler(
      subjectIdentities: _SubjectIdentities(),
      recoveryPlans: recovery,
    );

    final managedSkillId = ManagedSkillId(_skill);
    final sourceLineage = SourceLineageReference('lineage-1');
    final plan = assembler.destructive(
      operationId: OperationId(_operation),
      expectedRepositoryRevision: RepositoryRevision.initial(),
      kind: WorkspaceOperationKind.remove,
      businessChanges: WorkspaceBusinessChangeSet(
        mutations: [DeleteManagedSkill(managedSkillId)],
        incrementsDestructionEpoch: true,
      ),
      recoveryIntent: RemovalRecoveryIntent(
        skills: [
          DestructiveSkillRecoveryIntent(
            managedSkillId: managedSkillId,
            slotKey: 'reviewer',
            sourceLineages: [
              RecoverySourceLineageIntent(sourceLineage: sourceLineage),
            ],
            activationIds: const [],
            hasDraft: false,
            hasUpdateCandidateSession: false,
          ),
        ],
      ),
      revisionSelectionChanges: [
        RevisionSelectionChangePlan(
          managedSkillId: managedSkillId,
          previousUpstream: RevisionAddress(
            sourceLineage: sourceLineage,
            objectId: RevisionObjectId('1' * 40),
          ),
          previousEffective: RevisionAddress(
            sourceLineage: sourceLineage,
            objectId: RevisionObjectId('2' * 40),
          ),
          intendedUpstream: null,
          intendedEffective: null,
        ),
      ],
      subjects: [
        OperationSubjectIntent(
          managedSkillId: managedSkillId,
          displayName: 'Reviewer',
        ),
      ],
    );

    expect(plan.businessChanges.incrementsDestructionEpoch, isTrue);
    expect(recovery.destructive, isTrue);
  });

  test('rejects destructive cross-layer identity mismatch before recovery', () {
    final recovery = _RecoveryPlans();
    final assembler = OperationPlanAssembler(
      subjectIdentities: _SubjectIdentities(),
      recoveryPlans: recovery,
    );
    final managedSkillId = ManagedSkillId(_skill);
    final sourceLineage = SourceLineageReference('lineage-1');

    expect(
      () => assembler.destructive(
        operationId: OperationId(_operation),
        expectedRepositoryRevision: RepositoryRevision.initial(),
        kind: WorkspaceOperationKind.remove,
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: [DeleteManagedSkill(ManagedSkillId(_otherSkill))],
          incrementsDestructionEpoch: true,
        ),
        recoveryIntent: RemovalRecoveryIntent(
          skills: [
            DestructiveSkillRecoveryIntent(
              managedSkillId: managedSkillId,
              slotKey: 'reviewer',
              sourceLineages: [
                RecoverySourceLineageIntent(sourceLineage: sourceLineage),
              ],
              activationIds: const [],
              hasDraft: false,
              hasUpdateCandidateSession: false,
            ),
          ],
        ),
        revisionSelectionChanges: [
          RevisionSelectionChangePlan(
            managedSkillId: managedSkillId,
            previousUpstream: RevisionAddress(
              sourceLineage: sourceLineage,
              objectId: RevisionObjectId('1' * 40),
            ),
            previousEffective: RevisionAddress(
              sourceLineage: sourceLineage,
              objectId: RevisionObjectId('2' * 40),
            ),
            intendedUpstream: null,
            intendedEffective: null,
          ),
        ],
        subjects: [
          OperationSubjectIntent(
            managedSkillId: managedSkillId,
            displayName: 'Reviewer',
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(recovery.destructiveCalls, 0);
  });

  test('requires explicit independent history for subjectless operations', () {
    final assembler = OperationPlanAssembler(
      subjectIdentities: _SubjectIdentities(),
      recoveryPlans: _RecoveryPlans(),
    );
    final change = WorkspaceBusinessChangeSet(
      mutations: [
        PutProjectRoot(
          projectRootId: 'project-1',
          canonicalPath: '/workspace',
          createdAtMicros: 1,
          updatedAtMicros: 1,
        ),
      ],
    );

    expect(
      () => assembler.sqliteOnly(
        operationId: OperationId(_operation),
        expectedRepositoryRevision: RepositoryRevision.initial(),
        kind: WorkspaceOperationKind.registerProjectRoot,
        businessChanges: change,
      ),
      throwsArgumentError,
    );
    final plan = assembler.sqliteOnly(
      operationId: OperationId(_operation),
      expectedRepositoryRevision: RepositoryRevision.initial(),
      kind: WorkspaceOperationKind.registerProjectRoot,
      businessChanges: change,
      retainWithoutSubjects: true,
    );
    expect(plan.record.subjects, isEmpty);
    expect(plan.record.retainWithoutSubjects, isTrue);
  });

  test('rejects no-op mutation plans and duplicate Skill subjects', () {
    final assembler = OperationPlanAssembler(
      subjectIdentities: _SubjectIdentities(),
      recoveryPlans: _RecoveryPlans(),
    );
    expect(
      () => assembler.sqliteOnly(
        operationId: OperationId(_operation),
        expectedRepositoryRevision: RepositoryRevision.initial(),
        kind: WorkspaceOperationKind.setFavorite,
        businessChanges: WorkspaceBusinessChangeSet.empty,
        retainWithoutSubjects: true,
      ),
      throwsArgumentError,
    );
    final subject = OperationSubjectIntent(
      managedSkillId: ManagedSkillId(_skill),
      displayName: 'Reviewer',
    );
    expect(
      () => assembler.assemble(
        operationId: OperationId(_operation),
        expectedRepositoryRevision: RepositoryRevision.initial(),
        kind: WorkspaceOperationKind.setFavorite,
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: [DeleteSkillUserData(ManagedSkillId(_skill))],
        ),
        recoverySteps: OperationRecoveryPlanSteps(
          preparationSteps: const [],
          applyingSteps: const [],
          finalizationSteps: const [],
        ),
        subjects: [subject, subject],
      ),
      throwsArgumentError,
    );
  });
}

final class _SubjectIdentities implements OperationSubjectIdentityPort {
  @override
  String allocateOperationSubjectId() => _subject;
}

final class _RecoveryPlans implements OperationRecoveryPlanFactoryPort {
  OperationId? operationId;
  bool? destructive;
  DestructiveOperationRecoveryIntent? destructiveIntent;
  var destructiveCalls = 0;

  @override
  List<PreparationOperationStep> createDestructiveEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
  }) => _steps().preparationSteps;

  @override
  OperationRecoveryPlanSteps createSqliteOnly({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required bool destructive,
  }) {
    destructiveCalls += 1;
    this.operationId = operationId;
    this.destructive = destructive;
    final prepare = RecoveryReference('prepare');
    final backup = RecoveryReference('backup');
    return OperationRecoveryPlanSteps(
      preparationSteps: [
        PreparationOperationStep(
          stepId: 'prepare',
          recoveryReference: prepare,
          kind: PreparationStepKind.recoveryEvidence,
        ),
      ],
      applyingSteps: const [],
      finalizationSteps: [
        FinalizationOperationStep(
          stepId: 'backup',
          recoveryReference: backup,
          kind: FinalizationStepKind.backupRotation,
        ),
      ],
    );
  }

  @override
  OperationRecoveryPlanSteps createDestructive({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required DestructiveOperationRecoveryIntent intent,
  }) {
    this.operationId = operationId;
    destructive = true;
    destructiveIntent = intent;
    return _steps();
  }

  OperationRecoveryPlanSteps _steps() {
    final prepare = RecoveryReference('prepare');
    final backup = RecoveryReference('backup');
    return OperationRecoveryPlanSteps(
      preparationSteps: [
        PreparationOperationStep(
          stepId: 'prepare',
          recoveryReference: prepare,
          kind: PreparationStepKind.recoveryEvidence,
        ),
      ],
      applyingSteps: const [],
      finalizationSteps: [
        FinalizationOperationStep(
          stepId: 'backup',
          recoveryReference: backup,
          kind: FinalizationStepKind.backupRotation,
        ),
      ],
    );
  }
}
