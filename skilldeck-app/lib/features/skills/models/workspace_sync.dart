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
  unsupported,
}

typedef WorkspaceRemoteResult = ({
  WorkspaceRemoteResultKind kind,
  WorkspaceSkillId? skillId,
  String? effective,
  String? sourceEpoch,
});
