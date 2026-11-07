import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/workspace_journal_recovery_adapter.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

import '../../support/operations/operation_fakes.dart';

void main() {
  test(
    'recovers a destructive Applying Journal only with matching fence',
    () async {
      final harness = OperationHarness();
      final plan = _destructivePlan();
      harness.controlPlane.seed(plan, OperationJournalPhase.applying);
      final adapter = WorkspaceJournalRecoveryAdapter(
        controlPlane: harness.controlPlane,
        operations: harness.createCoordinator(),
      );

      await adapter.recoverUnderWriterLock(
        armedBarrier: _armed(),
        isolatedSkillIds: const {},
      );

      expect(harness.controlPlane.journals, isEmpty);
      expect(harness.log.events, contains('recovery.rollback'));
    },
  );

  test(
    'fails closed when an applying destructive Journal has no fence',
    () async {
      final harness = OperationHarness();
      harness.controlPlane.seed(
        _destructivePlan(),
        OperationJournalPhase.applying,
      );
      final adapter = WorkspaceJournalRecoveryAdapter(
        controlPlane: harness.controlPlane,
        operations: harness.createCoordinator(),
      );

      await expectLater(
        adapter.recoverUnderWriterLock(isolatedSkillIds: const {}),
        throwsStateError,
      );

      expect(harness.log.events, isNot(contains('recovery.rollback')));
    },
  );

  test(
    'rolls forward a committed destructive Journal after steady publication',
    () async {
      final harness = OperationHarness();
      harness.controlPlane.seed(
        _destructivePlan(),
        OperationJournalPhase.committed,
      );
      final adapter = WorkspaceJournalRecoveryAdapter(
        controlPlane: harness.controlPlane,
        operations: harness.createCoordinator(),
      );

      await adapter.recoverUnderWriterLock(isolatedSkillIds: const {});

      expect(harness.controlPlane.journals, isEmpty);
      expect(harness.log.events, contains('recovery.roll-forward'));
    },
  );

  test('rejects an armed fence bound to another operation', () async {
    final harness = OperationHarness();
    harness.controlPlane.seed(
      _destructivePlan(),
      OperationJournalPhase.applying,
    );
    final adapter = WorkspaceJournalRecoveryAdapter(
      controlPlane: harness.controlPlane,
      operations: harness.createCoordinator(),
    );
    final mismatch = ArmedBackupEligibility(
      operationId: '123e4567-e89b-42d3-b456-426614174099',
      previousDestructionEpoch: 0,
      intendedDestructionEpoch: 1,
      previousSteadyRepositoryRevision: 0,
      armedAtRepositoryRevision: 0,
    );

    await expectLater(
      adapter.recoverUnderWriterLock(
        armedBarrier: mismatch,
        isolatedSkillIds: const {},
      ),
      throwsStateError,
    );
  });

  test(
    'propagates retry-required instead of opening a writable facade',
    () async {
      final harness = OperationHarness();
      final plan = _ordinaryPlan();
      harness.controlPlane.seed(plan, OperationJournalPhase.applying);
      harness.failures.failures.add('recovery.rollback');
      final adapter = WorkspaceJournalRecoveryAdapter(
        controlPlane: harness.controlPlane,
        operations: harness.createCoordinator(),
      );

      await expectLater(
        adapter.recoverUnderWriterLock(isolatedSkillIds: const {}),
        throwsStateError,
      );
    },
  );
}

final _operationId = OperationId('123e4567-e89b-42d3-a456-426614174000');
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174001');

ArmedBackupEligibility _armed() => ArmedBackupEligibility(
  operationId: _operationId.value,
  previousDestructionEpoch: 0,
  intendedDestructionEpoch: 1,
  previousSteadyRepositoryRevision: 0,
  armedAtRepositoryRevision: 0,
);

OperationPlan _destructivePlan() => OperationPlan(
  operationId: _operationId,
  expectedRepositoryRevision: RepositoryRevision(0),
  committedRepositoryRevision: RepositoryRevision(1),
  operationGeneration: 1,
  preparationSteps: <PreparationOperationStep>[
    PreparationOperationStep(
      stepId: 'barrier',
      recoveryReference: RecoveryReference('barrier'),
      kind: PreparationStepKind.destructiveBarrier,
    ),
  ],
  applyingSteps: const <ApplyingOperationStep>[],
  finalizationSteps: const <FinalizationOperationStep>[],
  revisionSelectionChanges: const <RevisionSelectionChangePlan>[],
  businessChanges: WorkspaceBusinessChangeSet(
    mutations: <WorkspaceBusinessMutation>[DeleteManagedSkill(_skillId)],
    incrementsDestructionEpoch: true,
  ),
  record: OperationRecordPlan(
    operationId: _operationId,
    kind: WorkspaceOperationKind.remove.name,
    subjects: const <OperationSubjectPlan>[],
    retainWithoutSubjects: true,
  ),
);

OperationPlan _ordinaryPlan() => OperationPlan(
  operationId: _operationId,
  expectedRepositoryRevision: RepositoryRevision(0),
  committedRepositoryRevision: RepositoryRevision(1),
  operationGeneration: 1,
  preparationSteps: const <PreparationOperationStep>[],
  applyingSteps: const <ApplyingOperationStep>[],
  finalizationSteps: const <FinalizationOperationStep>[],
  revisionSelectionChanges: const <RevisionSelectionChangePlan>[],
  businessChanges: WorkspaceBusinessChangeSet(
    mutations: <WorkspaceBusinessMutation>[DeleteManagedSkill(_skillId)],
  ),
  record: OperationRecordPlan(
    operationId: _operationId,
    kind: WorkspaceOperationKind.remove.name,
    subjects: const <OperationSubjectPlan>[],
    retainWithoutSubjects: true,
  ),
);
