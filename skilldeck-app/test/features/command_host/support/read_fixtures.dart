import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';

WorkspaceSkill testSkill({
  String id = 'skill-1',
  String slot = 'alpha',
  String name = 'Alpha',
  bool favorite = true,
  List<String> tags = const ['tag-1'],
  String locator = 'https://user:password@example.test/repo',
  List<SkillActivationLocation>? activations,
  bool draft = true,
}) => WorkspaceSkill(
  id: WorkspaceSkillId(id),
  slotKey: slot,
  declaredName: 'declared-$slot',
  displayName: name,
  description: 'Description of $name',
  source: SkillSourceProvenance(
    kind: WorkspaceSourceKind.git,
    locator: locator,
    ref: 'private-ref',
    repositorySubpath: 'private-subpath',
  ),
  currentRevision: SkillRevision(
    contentHash: 'hash-$id',
    fileCount: 1,
    byteSize: 100,
    acquiredAt: DateTime.utc(2026),
    resolvedSourceRevision: 'private-git-oid',
  ),
  activations:
      activations ??
      [
        SkillActivationLocation(
          location: '/private/activation',
          scope: WorkspaceScope.global,
          mode: WorkspaceActivationMode.copy,
          agentIds: ['codex', 'claude'],
        ),
        SkillActivationLocation(
          location: '/private/project/activation',
          scope: WorkspaceScope.project,
          mode: WorkspaceActivationMode.symbolicLink,
          agentIds: ['codex'],
          projectRootId: 'project-1',
        ),
      ],
  isFavorite: favorite,
  note: 'Personal note',
  personalTagIds: tags,
  draft: draft
      ? WorkspaceDraftSummary(
          purpose: WorkspaceDraftPurpose.customization,
          path: '/private/draft',
          isDirty: false,
          updatedAt: DateTime.utc(2026),
        )
      : null,
);

SkillsWorkspaceSnapshot testSnapshot({
  List<WorkspaceSkill>? skills,
  String projectPath = '/projects/demo',
}) => SkillsWorkspaceSnapshot(
  revision: 7,
  projectRoots: [SkillProjectRoot(id: 'project-1', path: projectPath)],
  skills:
      skills ??
      [
        testSkill(),
        testSkill(
          id: 'skill-2',
          slot: 'beta',
          name: 'Beta',
          favorite: false,
          tags: const [],
          locator: '/sources/local',
          activations: const [],
          draft: false,
        ),
      ],
  personalTags: [
    for (final (id, name) in [('tag-1', 'Testing'), ('tag-2', 'Dart')])
      WorkspacePersonalTag(
        id: id,
        name: name,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
  ],
);

WorkspaceAgentInfo testAgent({String id = 'codex', String name = 'Codex'}) =>
    WorkspaceAgentInfo(
      id: id,
      displayName: name,
      isBuiltIn: true,
      supportedScopes: {WorkspaceScope.global, WorkspaceScope.project},
      detectedGlobally: true,
      detectedProjectRootIds: const {},
    );

const testGlobalTarget = WorkspaceActivationTarget(
  agentId: 'codex',
  displayName: 'Codex',
  detected: true,
  location: '/agents/codex',
  scope: WorkspaceScope.global,
);

SkillUpdateStatus testUpdates() => SkillUpdateStatus(
  states: {
    WorkspaceSkillId('skill-1'): SkillUpdateChecked(
      WorkspaceUpdateReport(
        skillId: WorkspaceSkillId('skill-1'),
        status: WorkspaceUpdateStatus.updateAvailable,
        currentContentHash: 'hash-skill-1',
      ),
    ),
  },
);
