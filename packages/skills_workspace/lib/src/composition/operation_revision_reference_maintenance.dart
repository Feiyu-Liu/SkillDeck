import '../application/ports/operation_ports.dart';
import '../application/ports/workspace_lifecycle_ports.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';

/// Adapts the startup-wide reconciler to live operation maintenance.
final class WorkspaceOperationRevisionReferenceMaintenance
    implements OperationRevisionReferenceMaintenancePort {
  const WorkspaceOperationRevisionReferenceMaintenance({
    required WorkspaceRevisionReferenceReconciliationPort reconciliation,
    required WorkspaceSnapshotPublisher snapshots,
  }) : _reconciliation = reconciliation,
       _snapshots = snapshots;

  final WorkspaceRevisionReferenceReconciliationPort _reconciliation;
  final WorkspaceSnapshotPublisher _snapshots;

  @override
  Future<void> reconcileRevisionReferences({
    Set<ManagedSkillId>? isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  }) => _reconciliation.reconcileRevisionReferences(
    isolatedSkillIds:
        isolatedSkillIds ?? _isolated(_snapshots.current.integrity),
    selectedSkillIds: selectedSkillIds,
  );
}

Set<ManagedSkillId> _isolated(WorkspaceIntegrity integrity) => Set.unmodifiable(
  integrity.skills
      .where((skill) => skill.mutationBlocked)
      .map((skill) => skill.managedSkillId),
);
