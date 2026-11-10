import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

InstalledSkillCatalog installedSkillCatalogFromWorkspace(
  SkillsWorkspaceSnapshot snapshot,
) => InstalledSkillCatalog(
  revision: snapshot.revision,
  projectRoots: snapshot.projectRoots,
  skills: [
    for (final skill in snapshot.skills)
      InstalledSkill(
        id: skill.id,
        slotKey: skill.slotKey,
        declaredName: skill.declaredName,
        displayName: skill.displayName,
        description: skill.description,
        contentHash: skill.currentRevision.contentHash,
        activationCount: skill.activationCount,
        source: skill.source,
        currentRevision: skill.currentRevision,
        activations: skill.activations,
        isFavorite: skill.isFavorite,
        note: skill.note,
        personalTagIds: skill.personalTagIds,
      ),
  ],
);
