import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_workspace/skills_workspace.dart' as workspace;

final class FakeWorkspaceSkillDriftReview implements WorkspaceSkillDriftReview {
  FakeWorkspaceSkillDriftReview({
    required this.skillId,
    List<WorkspaceDriftedArtifact> artifacts = const [],
    this.missingArtifactCount = 0,
  }) : artifacts = List.unmodifiable(artifacts);

  @override
  final WorkspaceSkillId skillId;
  @override
  final List<WorkspaceDriftedArtifact> artifacts;
  @override
  final int missingArtifactCount;
}

final class FakePackageSkillDriftReview implements workspace.SkillDriftReview {
  FakePackageSkillDriftReview({
    required this.managedSkillId,
    required this.effectiveContentHash,
    required List<workspace.SkillDriftArtifact> artifacts,
    this.missingArtifactCount = 0,
  }) : artifacts = List.unmodifiable(artifacts);
  @override
  final workspace.ManagedSkillId managedSkillId;
  @override
  final String effectiveContentHash;
  @override
  final List<workspace.SkillDriftArtifact> artifacts;
  @override
  final int missingArtifactCount;
}
