import 'portable_source.dart';

/// App adapts these local operations to SkillsRepository. No Cloud identifiers enter it.
abstract interface class SyncWorkspace {
  /// Adapt the Workspace's existing public Slot Key derivation.
  String? slotKeyForName(String declaredName);
  Future<List<WorkspaceSkill>> listSkills();
  Future<WorkspaceSkill?> inspectRevisionSelections(String managedSkillId);
  Future<WorkspaceChanges> inspectCommittedChanges(String? cursor);
  Future<WorkspaceExport> exportRevisionPack(
    String managedSkillId,
    String destination,
  );
  Future<WorkspaceApply> applyContent({
    required String managedSkillId,
    required String expectedEffective,
    required String effective,
    required String? upstream,
    required String packPath,
  });
  Future<WorkspaceApply> install({
    required String packPath,
    required String effective,
    required String? upstream,
    required PortableSource source,
  });
  Future<WorkspaceApply> remove({
    required String managedSkillId,
    required String expectedEffective,
  });
  Future<WorkspaceApply> replaceSource({
    required String managedSkillId,
    required String expectedEffective,
    required String packPath,
    required String effective,
    required String? upstream,
    required PortableSource source,
  });
}

final class WorkspaceSkill {
  const WorkspaceSkill({
    required this.id,
    required this.effective,
    required this.upstream,
    required this.source,
    required this.declaredName,
    required this.slotKey,
  });
  final String id, effective, declaredName, slotKey;
  final String? upstream;
  final PortableSource source;
}

final class WorkspaceChanges {
  WorkspaceChanges({required Iterable<String> skillIds, required this.cursor})
    : skillIds = Set.unmodifiable(skillIds);
  final Set<String> skillIds;
  final String cursor;
}

enum WorkspaceFailureCode {
  skillNotFound,
  staleSnapshot,
  objectUnavailable,
  invalidPack,
  invalidSkill,
  destinationUnusable,
  cancelled,
  ioFailure,
  operationFailed,
}

sealed class WorkspaceExport {
  const WorkspaceExport();
}

final class WorkspaceExported extends WorkspaceExport {
  const WorkspaceExported({required this.effective, required this.upstream});
  final String effective;
  final String? upstream;
}

final class WorkspaceExportFailed extends WorkspaceExport {
  const WorkspaceExportFailed(this.code);
  final WorkspaceFailureCode code;
}

sealed class WorkspaceApply {
  const WorkspaceApply();
}

final class WorkspaceNoChange extends WorkspaceApply {
  const WorkspaceNoChange();
}

final class WorkspaceFastForwarded extends WorkspaceApply {
  const WorkspaceFastForwarded();
}

final class WorkspaceMerged extends WorkspaceApply {
  const WorkspaceMerged(this.effective);
  final String effective;
}

final class WorkspaceConflicted extends WorkspaceApply {
  const WorkspaceConflicted();
}

final class WorkspaceDraftRequired extends WorkspaceApply {
  const WorkspaceDraftRequired();
}

final class WorkspaceSlotOccupied extends WorkspaceApply {
  const WorkspaceSlotOccupied(this.occupant);
  final String occupant;
}

final class WorkspaceInstalled extends WorkspaceApply {
  const WorkspaceInstalled(this.managedSkillId);
  final String managedSkillId;
}

final class WorkspaceRemoved extends WorkspaceApply {
  const WorkspaceRemoved();
}

final class WorkspaceSourceReplaced extends WorkspaceApply {
  const WorkspaceSourceReplaced();
}

final class WorkspaceApplyFailed extends WorkspaceApply {
  const WorkspaceApplyFailed(this.code);
  final WorkspaceFailureCode code;
}
