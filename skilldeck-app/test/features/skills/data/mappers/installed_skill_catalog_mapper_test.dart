import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/data/mappers/installed_skill_catalog_mapper.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

void main() {
  test('catalog mapping preserves first-added time after metadata changes', () {
    final createdAt = DateTime.utc(2026, 1);
    final skill = WorkspaceSkill(
      id: WorkspaceSkillId('a'),
      slotKey: 'a',
      declaredName: 'A',
      displayName: 'A',
      description: 'A',
      createdAt: createdAt,
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/tmp/a',
      ),
      currentRevision: SkillRevision(
        contentHash: 'hash',
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime.utc(2026, 2),
      ),
      activations: const [],
    );
    final updated = skill.copyWith(isFavorite: true, note: 'Note');
    final catalog = installedSkillCatalogFromWorkspace(
      SkillsWorkspaceSnapshot(
        revision: 2,
        projectRoots: const [],
        skills: [updated],
      ),
    );
    expect(catalog.skills.single.createdAt, createdAt);
    expect(catalog.skills.single.isFavorite, isTrue);
  });
}
