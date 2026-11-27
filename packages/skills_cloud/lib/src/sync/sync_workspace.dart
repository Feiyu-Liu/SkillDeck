import 'portable_source.dart';

/// App adapts these local operations to SkillsRepository. No Cloud identifiers enter it.
abstract interface class SyncWorkspace {
  /// Adapt the Workspace's existing public Slot Key derivation.
  String? slotKeyForName(String declaredName);
  Future<List<WorkspaceSkill>> listSkills();
  Future<WorkspaceSkill?> inspectRevisionSelections(String managedSkillId);
  Future<WorkspaceChanges> inspectCommittedChanges(String? cursor);
  Future<WorkspaceMetadataSnapshot> inspectMetadata();
  Future<WorkspaceApply> applyMetadata({
    required String managedSkillId,
    required String expectedRevision,
    required bool favorite,
    required String? note,
    required Set<String> tagIds,
  });
  Future<WorkspaceTagApply> ensureTag({
    required String expectedRevision,
    required String name,
    required String? color,
  });
  Future<WorkspaceTagApply> updateTag({
    required String expectedRevision,
    required String localTagId,
    required String name,
    required String? color,
  });
  Future<WorkspaceTagApply> deleteTag({
    required String expectedRevision,
    required String localTagId,
  });
  Future<WorkspaceTagApply> renameTags({
    required String expectedRevision,
    required Map<String, String> names,
  });
  String tagClientKey(String localTagId);
  Future<WorkspaceExport> exportRevisionPack(
    String managedSkillId,
    String destination,
  );
  Future<WorkspaceApply> applyContent({
    required String managedSkillId,
    required String expectedEffective,
    String? expectedSourceEpoch,
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
    String? expectedSourceEpoch,
  });
  Future<WorkspaceApply> replaceSource({
    required String managedSkillId,
    required String expectedEffective,
    String? expectedSourceEpoch,
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
    this.sourceEpoch,
  });
  final String id, effective, declaredName, slotKey;
  final String? upstream;
  final String? sourceEpoch;
  final PortableSource source;
}

final class WorkspaceChanges {
  WorkspaceChanges({
    required Iterable<String> skillIds,
    required this.cursor,
    this.vocabularyChanged = false,
  }) : skillIds = Set.unmodifiable(skillIds);
  final Set<String> skillIds;
  final String cursor;
  final bool vocabularyChanged;
}

final class WorkspaceMetadataSnapshot {
  WorkspaceMetadataSnapshot({
    required this.revision,
    required Map<String, WorkspaceSkillMetadata> skills,
    required Map<String, WorkspaceTag> tags,
  }) : skills = Map.unmodifiable(skills),
       tags = Map.unmodifiable(tags);

  final String revision;
  final Map<String, WorkspaceSkillMetadata> skills;
  final Map<String, WorkspaceTag> tags;
}

final class WorkspaceSkillMetadata {
  WorkspaceSkillMetadata({
    required this.favorite,
    required this.note,
    required Iterable<String> tagIds,
  }) : tagIds = Set.unmodifiable(tagIds);

  final bool favorite;
  final String? note;
  final Set<String> tagIds;
}

final class WorkspaceTag {
  const WorkspaceTag({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.color,
  });
  final String id, name, normalizedName;
  final String? color;
}

sealed class WorkspaceTagApply {
  const WorkspaceTagApply();
}

final class WorkspaceTagApplied extends WorkspaceTagApply {
  const WorkspaceTagApplied({this.localTagId});
  final String? localTagId;
}

final class WorkspaceTagApplyFailed extends WorkspaceTagApply {
  const WorkspaceTagApplyFailed(this.code);
  final WorkspaceFailureCode code;
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
  const WorkspaceNoChange({this.sourceEpoch});

  final String? sourceEpoch;
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
  const WorkspaceInstalled(this.managedSkillId, {this.sourceEpoch});
  final String managedSkillId;
  final String? sourceEpoch;
}

final class WorkspaceRemoved extends WorkspaceApply {
  const WorkspaceRemoved();
}

final class WorkspaceSourceReplaced extends WorkspaceApply {
  const WorkspaceSourceReplaced({this.sourceEpoch});

  final String? sourceEpoch;
}

final class WorkspaceApplyFailed extends WorkspaceApply {
  const WorkspaceApplyFailed(this.code);
  final WorkspaceFailureCode code;
}
