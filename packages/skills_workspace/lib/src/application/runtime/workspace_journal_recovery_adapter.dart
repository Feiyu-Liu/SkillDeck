import '../backup/control_plane_backup_models.dart';
import '../operations/operation_coordinator.dart';
import '../operations/operation_models.dart';
import '../ports/operation_ports.dart';
import '../ports/workspace_lifecycle_ports.dart';
import '../../domain/identifiers.dart';

/// Binds startup's armed destructive-backup fence to lock-held Journal
/// recovery without letting the open coordinator inspect persistence rows.
final class WorkspaceJournalRecoveryAdapter
    implements WorkspaceJournalRecoveryPort {
  const WorkspaceJournalRecoveryAdapter({
    required OperationControlPlanePort controlPlane,
    required OperationCoordinator operations,
  }) : _controlPlane = controlPlane,
       _operations = operations;

  final OperationControlPlanePort _controlPlane;
  final OperationCoordinator _operations;

  @override
  Future<void> recoverUnderWriterLock({
    ArmedBackupEligibility? armedBarrier,
    required Set<ManagedSkillId> isolatedSkillIds,
  }) async {
    final journaled = await _controlPlane.loadRecoverableOperations();
    _validateBarrier(journaled, armedBarrier);
    final report = await _operations.recoverUnderWriterLock(
      isolatedSkillIds: isolatedSkillIds,
    );
    if (report.operations.any(
      (operation) =>
          operation.disposition == RecoveredOperationDisposition.retryRequired,
    )) {
      throw StateError('One or more Workspace operations require recovery.');
    }
  }
}

void _validateBarrier(
  List<JournaledOperation> journaled,
  ArmedBackupEligibility? armed,
) {
  if (armed != null) {
    final matching = journaled
        .where(
          (operation) =>
              operation.definition.operationId.value == armed.operationId,
        )
        .toList(growable: false);
    if (matching.length != 1 || !_matchesArmedBarrier(matching.single, armed)) {
      throw StateError(
        'The armed destructive barrier has no matching Journal.',
      );
    }
  }

  for (final operation in journaled) {
    final definition = operation.definition;
    if (definition is! OperationPlan ||
        !definition.businessChanges.incrementsDestructionEpoch) {
      continue;
    }
    final requiresArmedBarrier = switch (operation.phase) {
      OperationJournalPhase.applying => true,
      // After the BCP, backup finalization may already have published the new
      // steady fence before Journal completion. Startup validated that steady
      // fence and the primary epoch before reaching Journal recovery, so both
      // armed and steady are legal roll-forward states here.
      OperationJournalPhase.committed ||
      OperationJournalPhase.finalizing => false,
      OperationJournalPhase.prepared => _destructiveBarrierCompleted(operation),
      OperationJournalPhase.completed => false,
    };
    if (requiresArmedBarrier &&
        (armed == null || armed.operationId != definition.operationId.value)) {
      throw StateError(
        'Destructive Journal recovery requires its armed fence.',
      );
    }
  }
}

bool _matchesArmedBarrier(
  JournaledOperation journaled,
  ArmedBackupEligibility armed,
) {
  final definition = journaled.definition;
  if (definition is! OperationPlan ||
      !definition.businessChanges.incrementsDestructionEpoch ||
      definition.expectedRepositoryRevision.value !=
          armed.armedAtRepositoryRevision ||
      definition.committedRepositoryRevision.value !=
          armed.armedAtRepositoryRevision + 1 ||
      armed.intendedDestructionEpoch != armed.previousDestructionEpoch + 1 ||
      journaled.phase == OperationJournalPhase.completed) {
    return false;
  }
  return switch (journaled.phase) {
    OperationJournalPhase.prepared => _destructiveBarrierStarted(journaled),
    OperationJournalPhase.applying ||
    OperationJournalPhase.committed ||
    OperationJournalPhase.finalizing => true,
    OperationJournalPhase.completed => false,
  };
}

bool _destructiveBarrierStarted(JournaledOperation journaled) {
  final plan = journaled.definition as OperationPlan;
  final steps = plan.preparationSteps.where(
    (step) => step.kind == PreparationStepKind.destructiveBarrier,
  );
  if (steps.length != 1) return false;
  return journaled.stepStatuses[steps.single.stepId] ==
          OperationStepStatus.started ||
      journaled.stepStatuses[steps.single.stepId] ==
          OperationStepStatus.completed;
}

bool _destructiveBarrierCompleted(JournaledOperation journaled) {
  final plan = journaled.definition as OperationPlan;
  final steps = plan.preparationSteps.where(
    (step) => step.kind == PreparationStepKind.destructiveBarrier,
  );
  return steps.length == 1 &&
      journaled.stepStatuses[steps.single.stepId] ==
          OperationStepStatus.completed;
}
