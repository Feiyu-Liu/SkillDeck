import 'skills_workspace.dart';

typedef WorkspaceRevisionHeads = ({String effective, String? upstream});
typedef WorkspaceSelectedRevisions = ({
  String effective,
  String? upstream,
  String? sourceEpoch,
});
typedef WorkspaceRevisionSelections = ({
  int revision,
  Map<WorkspaceSkillId, WorkspaceSelectedRevisions> heads,
});
typedef WorkspaceCommittedChanges = ({
  int revision,
  Set<WorkspaceSkillId> skillIds,
  bool resetRequired,
  bool vocabularyChanged,
});

sealed class WorkspaceRemoteChange {
  const WorkspaceRemoteChange();
}

final class WorkspaceRemoteContent extends WorkspaceRemoteChange {
  const WorkspaceRemoteContent({
    required this.skillId,
    required this.expectedEffective,
    this.expectedSourceEpoch,
    required this.heads,
    required this.packPath,
  });

  final WorkspaceSkillId skillId;
  final String expectedEffective;
  final String? expectedSourceEpoch;
  final WorkspaceRevisionHeads heads;
  final String packPath;
}

final class WorkspaceRemoteInstall extends WorkspaceRemoteChange {
  const WorkspaceRemoteInstall({
    required this.heads,
    required this.packPath,
    required this.source,
  });

  final WorkspaceRevisionHeads heads;
  final String packPath;
  final SkillSourceProvenance source;
}

final class WorkspaceRemoteRemoval extends WorkspaceRemoteChange {
  const WorkspaceRemoteRemoval(
    this.skillId,
    this.expectedEffective, {
    this.expectedSourceEpoch,
  });

  final WorkspaceSkillId skillId;
  final String expectedEffective;
  final String? expectedSourceEpoch;
}

final class WorkspaceRemoteSourceReplacement extends WorkspaceRemoteChange {
  const WorkspaceRemoteSourceReplacement({
    required this.skillId,
    required this.expectedEffective,
    this.expectedSourceEpoch,
    required this.heads,
    required this.packPath,
    required this.source,
  });

  final WorkspaceSkillId skillId;
  final String expectedEffective;
  final String? expectedSourceEpoch;
  final WorkspaceRevisionHeads heads;
  final String packPath;
  final SkillSourceProvenance source;
}

final class WorkspaceRemoteMetadata extends WorkspaceRemoteChange {
  const WorkspaceRemoteMetadata({
    required this.skillId,
    required this.expectedRevision,
    required this.expectedEffective,
    required this.favorite,
    required this.note,
    required this.tagIds,
  });

  final WorkspaceSkillId skillId;
  final int expectedRevision;
  final String expectedEffective;
  final bool favorite;
  final String? note;
  final Set<String> tagIds;
}

sealed class WorkspaceRemoteTag extends WorkspaceRemoteChange {
  const WorkspaceRemoteTag(this.expectedRevision);

  final int expectedRevision;
}

final class WorkspaceRemoteTagEnsure extends WorkspaceRemoteTag {
  const WorkspaceRemoteTagEnsure(super.expectedRevision, this.name, this.color);

  final String name;
  final String? color;
}

final class WorkspaceRemoteTagUpdate extends WorkspaceRemoteTag {
  const WorkspaceRemoteTagUpdate(
    super.expectedRevision,
    this.tagId,
    this.name,
    this.color,
  );

  final String tagId, name;
  final String? color;
}

final class WorkspaceRemoteTagDelete extends WorkspaceRemoteTag {
  const WorkspaceRemoteTagDelete(super.expectedRevision, this.tagId);

  final String tagId;
}

final class WorkspaceRemoteTagRenameMany extends WorkspaceRemoteTag {
  const WorkspaceRemoteTagRenameMany(super.expectedRevision, this.names);

  final Map<String, String> names;
}

enum WorkspaceRemoteResultKind {
  noChange,
  fastForwarded,
  merged,
  conflicted,
  draftResolutionRequired,
  slotOccupied,
  installed,
  removed,
  sourceReplaced,
  metadataApplied,
  tagApplied,
}

typedef WorkspaceRemoteResult = ({
  WorkspaceRemoteResultKind kind,
  WorkspaceSkillId? skillId,
  String? effective,
  String? sourceEpoch,
  String? tagId,
});
