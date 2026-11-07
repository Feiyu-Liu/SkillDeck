import 'package:skills_manager/features/skills/models/skills_workspace.dart';

final class InstalledSkill {
  const InstalledSkill({
    required this.id,
    required this.slotKey,
    required this.displayName,
    required this.description,
    required this.contentHash,
    required this.activationCount,
    this.declaredName = '',
    this.source,
    this.currentRevision,
    this.activations = const [],
    this.isFavorite = false,
    this.note,
    this.personalTagIds = const [],
  });

  final WorkspaceSkillId id;
  final String slotKey;
  final String declaredName;
  final String displayName;
  final String description;
  final String contentHash;
  final int activationCount;
  final SkillSourceProvenance? source;
  final SkillRevision? currentRevision;
  final List<SkillActivationLocation> activations;
  final bool isFavorite;
  final String? note;
  final List<String> personalTagIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstalledSkill &&
          id == other.id &&
          slotKey == other.slotKey &&
          displayName == other.displayName &&
          description == other.description &&
          contentHash == other.contentHash &&
          activationCount == other.activationCount &&
          declaredName == other.declaredName;

  @override
  int get hashCode => Object.hash(
    slotKey,
    id,
    displayName,
    description,
    contentHash,
    activationCount,
    declaredName,
  );
}

final class InstalledSkillCatalog {
  InstalledSkillCatalog({
    required this.revision,
    required List<InstalledSkill> skills,
    List<SkillProjectRoot> projectRoots = const [],
  }) : skills = List.unmodifiable(skills),
       projectRoots = List.unmodifiable(projectRoots);

  final int revision;
  final List<InstalledSkill> skills;
  final List<SkillProjectRoot> projectRoots;
}
