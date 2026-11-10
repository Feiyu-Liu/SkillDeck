import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';

/// Also handles malformed URL authorities defensively, without echoing userinfo.
String stripLocatorUserinfo(String locator) => locator.replaceAllMapped(
  RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*://)[^/?#]*@'),
  (match) => match[1]!,
);

Map<String, Object?> projectRootJson(SkillProjectRoot root) => {
  'id': root.id,
  'path': root.path,
};

Map<String, Object?> agentJson(
  WorkspaceAgentInfo agent, {
  required Set<String> memberIds,
  required Iterable<WorkspaceActivationTarget> globalTargets,
}) => {
  'id': agent.id,
  'name': agent.displayName,
  'enabled': memberIds.contains(agent.id),
  'globalRoots':
      (globalTargets
          .where(
            (t) => t.agentId == agent.id && t.scope == WorkspaceScope.global,
          )
          .map((t) => t.location)
          .toSet()
          .toList()
        ..sort()),
};

Map<String, Object?> skillJson(
  WorkspaceSkill skill,
  SkillsWorkspaceSnapshot snapshot, {
  SkillUpdateState update = const SkillUpdateNotChecked(),
}) => {
  'id': skill.id.value,
  'slotKey': skill.slotKey,
  'name': skill.displayName,
  'declaredName': skill.declaredName,
  'description': skill.description,
  'source': {
    'kind': skill.source.kind.name,
    'locator': stripLocatorUserinfo(skill.source.locator),
  },
  'contentHash': skill.currentRevision.contentHash,
  'favorite': skill.isFavorite,
  'note': skill.note,
  'tags': [
    for (final id in skill.personalTagIds)
      if (snapshot.findPersonalTag(id) case final tag?) tag.name,
  ],
  'activations': [
    for (final activation in skill.activations)
      for (final agent in activation.agentIds)
        {
          'agent': agent,
          'scope': activation.scope.name,
          if (activation.scope == WorkspaceScope.project)
            'projectPath':
                activation.projectRootPath ??
                snapshot.projectRoots
                    .where((r) => r.id == activation.projectRootId)
                    .firstOrNull
                    ?.path,
          'mode': activation.mode.name,
        },
  ],
  'update': {
    'status':
        update.report?.status.name ??
        switch (update) {
          SkillUpdateChecking() => 'checking',
          SkillUpdateCheckFailed() => 'checkFailed',
          _ => 'notChecked',
        },
  },
  'draft': {'present': skill.draft != null},
  'integrity': skill.integrity.name,
};
