import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../backup/control_plane_backup_models.dart';

enum WorkspaceRuntimeState { closed, opening, open, closing }

enum WorkspaceOpenFailureCode {
  repositoryClosed,
  writerLockUnavailable,
  controlPlaneRecoveryBlocked,
  controlPlaneOpenFailed,
  revisionWorkerStartupFailed,
  revisionMaintenanceFailed,
  journalRecoveryFailed,
  revisionReferenceReconciliationFailed,
  materializationReconciliationFailed,
  snapshotReadFailed,
  snapshotPublicationFailed,
  requestGateOpenFailed,
}

enum WorkspaceShutdownStep {
  stopRequests,
  settleRequests,
  closeSnapshots,
  closeRevisionWorker,
  closeControlPlane,
  closeRequestGate,
  releaseWriterLock,
}

sealed class WorkspaceOpenOutcome {
  const WorkspaceOpenOutcome();
}

final class WorkspaceOpened extends WorkspaceOpenOutcome {
  WorkspaceOpened({
    required this.snapshot,
    required this.primaryRecovery,
    required Set<ManagedSkillId> recoveredSkillIds,
    required Set<ManagedSkillId> isolatedSkillIds,
  }) : recoveredSkillIds = Set.unmodifiable(recoveredSkillIds),
       isolatedSkillIds = Set.unmodifiable(isolatedSkillIds);

  final RepositorySnapshot snapshot;
  final ControlPlaneStartupResult primaryRecovery;
  final Set<ManagedSkillId> recoveredSkillIds;
  final Set<ManagedSkillId> isolatedSkillIds;
}

final class WorkspaceOpenFailed extends WorkspaceOpenOutcome {
  WorkspaceOpenFailed({
    required this.code,
    this.controlPlaneFailure,
    List<WorkspaceShutdownStep> cleanupFailures = const [],
  }) : cleanupFailures = List.unmodifiable(cleanupFailures);

  final WorkspaceOpenFailureCode code;
  final ControlPlaneBackupFailureCode? controlPlaneFailure;
  final List<WorkspaceShutdownStep> cleanupFailures;
}

sealed class WorkspaceCloseOutcome {
  const WorkspaceCloseOutcome();
}

final class WorkspaceClosed extends WorkspaceCloseOutcome {
  const WorkspaceClosed({required this.alreadyClosed});

  final bool alreadyClosed;
}

final class WorkspaceCloseFailed extends WorkspaceCloseOutcome {
  WorkspaceCloseFailed(List<WorkspaceShutdownStep> failures)
    : failures = List.unmodifiable(failures) {
    if (failures.isEmpty) {
      throw ArgumentError.value(failures, 'failures', 'must not be empty');
    }
  }

  final List<WorkspaceShutdownStep> failures;
}
