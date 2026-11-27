import 'skills_workspace.dart';

enum WorkspaceUpdateCandidateSide { current, incoming }

abstract interface class WorkspaceUpdateCandidateReview {
  WorkspaceSkillId get skillId;
  WorkspaceUpdateCandidateSummary get summary;
  bool get hasUnresolvedConflicts;
}

enum WorkspaceDiffFileStatus { added, deleted, modified, renamed, modeChanged }

enum WorkspaceDiffLineKind { context, addition, deletion }

typedef WorkspaceDiffLine = ({
  WorkspaceDiffLineKind kind,
  String text,
  int? oldLineNumber,
  int? newLineNumber,
});

typedef WorkspaceDiffHunk = ({String header, List<WorkspaceDiffLine> lines});

typedef WorkspaceDiffFile = ({
  String path,
  String? previousPath,
  WorkspaceDiffFileStatus status,
  bool isBinary,
  int additions,
  int deletions,
  List<WorkspaceDiffHunk> hunks,
});

final class WorkspaceRevisionPackDiff {
  WorkspaceRevisionPackDiff({
    required this.skillId,
    required this.from,
    required this.to,
    required Iterable<WorkspaceDiffFile> files,
  }) : files = List.unmodifiable(files);

  final WorkspaceSkillId skillId;
  final String from;
  final String to;
  final List<WorkspaceDiffFile> files;
}
