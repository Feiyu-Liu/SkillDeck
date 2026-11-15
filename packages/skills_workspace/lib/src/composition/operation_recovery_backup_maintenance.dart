import '../application/backup/control_plane_backup_service.dart';
import '../application/ports/control_plane_backup_ports.dart';
import '../application/ports/operation_ports.dart';
import '../application/operations/operation_models.dart';
import '../platform/operations/filesystem_operation_recovery.dart';
import '../platform/operations/operation_recovery_bundle.dart';

/// Connects operation recovery phases to the Control Plane backup epoch.
final class WorkspaceOperationRecoveryBackupMaintenance
    implements
        OperationRecoveryBackupMaintenancePort,
        OperationCompletedCheckpointPort {
  const WorkspaceOperationRecoveryBackupMaintenance({
    required ControlPlaneBackupService backups,
    required ControlPlaneBackupDatabasePort database,
  }) : _backups = backups,
       _database = database;

  final ControlPlaneBackupService _backups;
  final ControlPlaneBackupDatabasePort _database;

  Future<bool> _committed(OperationPlan plan) async {
    final terminal = await _database.completedOperationRevision(
      plan.operationId.value,
    );
    if (terminal == plan.expectedRepositoryRevision.value) return false;
    if (terminal != plan.committedRepositoryRevision.value) {
      throw StateError('Checkpoint terminal revision mismatch.');
    }
    return true;
  }

  @override
  Future<void> terminalCheckpoint(OperationPlan plan) async {
    if (await _committed(plan)) {
      await _backups.checkpointCompletedOperation(
        operationId: plan.operationId.value,
      );
    }
  }

  @override
  Future<void> cleanCheckpoint(OperationPlan plan) async {
    if (plan.businessChanges.incrementsDestructionEpoch &&
        await _committed(plan)) {
      await _backups.checkpointCompletedOperation(
        operationId: plan.operationId.value,
        clean: true,
      );
    }
  }

  @override
  Future<void> rotate(OperationRecoveryContext context) async {
    final backup = await _backups.createBackup();
    if (backup.manifest.identity.repositoryRevision !=
        context.committedRepositoryRevision.value) {
      throw StateError('The backup does not match the committed operation.');
    }
  }

  @override
  Future<void> armDestructiveBarrier(OperationRecoveryContext context) async {
    final live = await _database.liveIdentity();
    if (live.repositoryRevision != context.expectedRepositoryRevision.value) {
      throw StateError('The destructive backup barrier is stale.');
    }
    await _backups.armDestructiveBarrier(
      operationId: context.operationId.value,
      expectedIdentity: live,
    );
  }

  @override
  Future<void> restoreSteadyAfterProvenRollback(
    OperationRecoveryContext context,
  ) => _backups
      .restoreSteadyAfterProvenRollback(operationId: context.operationId.value)
      .then((_) {});

  @override
  Future<void> completeCommittedDestruction(OperationRecoveryContext context) =>
      _backups
          .completeCommittedDestruction(operationId: context.operationId.value)
          .then((_) {});
}
