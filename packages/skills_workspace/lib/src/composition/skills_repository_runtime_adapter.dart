import '../api/default_skills_repository.dart';
import '../application/runtime/workspace_open_coordinator.dart';
import '../application/runtime/workspace_open_models.dart';
import '../application/runtime/workspace_request_gate.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../api/update_check_store.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';

/// Binds the public facade lifetime to the application runtime owners.
///
/// The composition layer is the only layer allowed to see both the public API
/// implementation and concrete application coordinators.
final class SkillsRepositoryRuntimeAdapter implements SkillsRepositoryRuntime {
  const SkillsRepositoryRuntimeAdapter({
    required WorkspaceOpenCoordinator lifecycle,
    required WorkspaceSnapshotPublisher snapshots,
    required WorkspaceRequestGate requestGate,
    required UpdateCheckStore updateCheckStore,
  }) : _lifecycle = lifecycle,
       _snapshots = snapshots,
       _requestGate = requestGate,
       _updateCheckStore = updateCheckStore;

  final WorkspaceOpenCoordinator _lifecycle;
  final WorkspaceSnapshotPublisher _snapshots;
  final WorkspaceRequestGate _requestGate;
  final UpdateCheckStore _updateCheckStore;

  @override
  UpdateCheckStore get updateCheckStore => _updateCheckStore;

  @override
  bool get isOpen => _lifecycle.isOpen;

  @override
  RepositorySnapshot get snapshot => _snapshots.current;

  @override
  Stream<RepositorySnapshot> get snapshots => _snapshots.snapshots;

  @override
  Future<WorkspaceOpenOutcome> open() => _lifecycle.open();

  @override
  Future<WorkspaceCloseOutcome> close() => _lifecycle.close();

  @override
  WorkspaceRequestAdmission? admit({
    required OperationId operationId,
    required Future<void> Function() cancelBeforeCommit,
  }) => _requestGate.admit(
    operationId: operationId,
    cancelBeforeCommit: cancelBeforeCommit,
  );
}
