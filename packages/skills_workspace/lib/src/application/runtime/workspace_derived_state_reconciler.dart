import '../../domain/identifiers.dart';
import '../ports/workspace_lifecycle_ports.dart';

/// Composes the two independent derived-state repair responsibilities used by
/// startup without exposing their infrastructure implementations upward.
final class WorkspaceDerivedStateReconciler
    implements WorkspaceDerivedStateReconcilerPort {
  const WorkspaceDerivedStateReconciler({
    required WorkspaceRevisionReferenceReconciliationPort revisionReferences,
    required WorkspaceMaterializationReconciliationPort materializations,
  }) : _revisionReferences = revisionReferences,
       _materializations = materializations;

  final WorkspaceRevisionReferenceReconciliationPort _revisionReferences;
  final WorkspaceMaterializationReconciliationPort _materializations;

  @override
  Future<void> reconcileRevisionReferences({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  }) => _revisionReferences.reconcileRevisionReferences(
    isolatedSkillIds: isolatedSkillIds,
    selectedSkillIds: selectedSkillIds,
  );

  @override
  Future<WorkspaceMaterializationReconciliationReport>
  reconcileMaterializations({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
    bool repairMismatching = true,
    bool repairMissing = true,
  }) => _materializations.reconcileMaterializations(
    isolatedSkillIds: isolatedSkillIds,
    selectedSkillIds: selectedSkillIds,
    repairMismatching: repairMismatching,
    repairMissing: repairMissing,
  );
}
