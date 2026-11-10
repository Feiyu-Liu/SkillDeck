import 'package:skills_manager/features/skills/data/mappers/installed_skill_catalog_mapper.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

abstract interface class SkillBrowserRepository {
  Stream<InstalledSkillCatalog> get catalogs;

  Future<WorkspaceCompletion<InstalledSkillCatalog>> open();

  Future<WorkspaceCompletion<InstalledSkillCatalog>> refresh();

  Future<WorkspaceCompletion<List<SkillDocumentEntry>>> listDocuments(
    InstalledSkill skill,
  );

  Future<WorkspaceCompletion<String>> readDocument(
    InstalledSkill skill,
    String relativePath, {
    required String expectedContentHash,
  });

  Future<void> close();
}

final class WorkspaceSkillBrowserRepository implements SkillBrowserRepository {
  const WorkspaceSkillBrowserRepository(this._workspace);

  final SkillsWorkspaceRepository _workspace;

  @override
  Stream<InstalledSkillCatalog> get catalogs =>
      _workspace.snapshots.map(installedSkillCatalogFromWorkspace);

  @override
  Future<WorkspaceCompletion<InstalledSkillCatalog>> open() async =>
      _mapCatalog(await _workspace.open());

  @override
  Future<WorkspaceCompletion<InstalledSkillCatalog>> refresh() async =>
      _mapCatalog(await _workspace.refresh());

  @override
  Future<WorkspaceCompletion<List<SkillDocumentEntry>>> listDocuments(
    InstalledSkill skill,
  ) => _workspace.listSkillDocuments(skill.id);

  @override
  Future<WorkspaceCompletion<String>> readDocument(
    InstalledSkill skill,
    String relativePath, {
    required String expectedContentHash,
  }) => _workspace.readSkillDocument(
    skill.id,
    relativePath,
    expectedContentHash: expectedContentHash,
  );

  @override
  Future<void> close() async {}
}

WorkspaceCompletion<InstalledSkillCatalog> _mapCatalog(
  WorkspaceCompletion<SkillsWorkspaceSnapshot> completion,
) => switch (completion) {
  WorkspaceCompleted(:final value, :final warnings) => WorkspaceCompleted(
    value: installedSkillCatalogFromWorkspace(value),
    warnings: warnings,
  ),
  WorkspaceFailed(:final failure, :final warnings) => WorkspaceFailed(
    failure: failure,
    warnings: warnings,
  ),
  WorkspaceCommittedPending(
    :final operationId,
    :final committedRevision,
    :final warnings,
  ) =>
    WorkspaceCommittedPending(
      operationId: operationId,
      committedRevision: committedRevision,
      warnings: warnings,
    ),
};
