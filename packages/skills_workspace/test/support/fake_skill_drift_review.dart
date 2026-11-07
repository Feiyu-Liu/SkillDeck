import 'package:skills_workspace/skills_workspace.dart';

final class FakeSkillDriftReview implements SkillDriftReview {
  FakeSkillDriftReview({
    required this.managedSkillId,
    required this.effectiveContentHash,
    List<SkillDriftArtifact> artifacts = const [],
    this.missingArtifactCount = 0,
  }) : artifacts = List.unmodifiable(artifacts);

  @override
  final ManagedSkillId managedSkillId;

  @override
  final String effectiveContentHash;

  @override
  final List<SkillDriftArtifact> artifacts;

  @override
  final int missingArtifactCount;
}
