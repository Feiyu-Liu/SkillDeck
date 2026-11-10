import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import '../../../../support/fake_skills_workspace_repository.dart';

void main() {
  test('browser adapter forwards the authoritative snapshot stream', () async {
    final workspace = FakeSkillsWorkspaceRepository();
    final browser = WorkspaceSkillBrowserRepository(workspace);
    final catalogFuture = browser.catalogs.first;
    workspace.publish(
      SkillsWorkspaceSnapshot(
        revision: 3,
        projectRoots: const [SkillProjectRoot(id: 'project', path: '/project')],
        skills: const [],
      ),
    );

    final catalog = await catalogFuture;
    expect(catalog.revision, 3);
    expect(catalog.projectRoots.single.id, 'project');
  });

  test(
    'acquisition adapter preserves Git provenance and candidate metadata',
    () async {
      final workspace = FakeSkillsWorkspaceRepository();
      workspace.sourceInspection = WorkspaceSourceInspection(
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'owner/repository',
          ref: 'release/v2',
          repositorySubpath: 'packages/skills',
        ),
        candidates: const [
          WorkspaceSourceCandidate(
            declaredName: 'Review',
            description: 'Reviews changes',
            slotKey: 'review',
            skillPath: 'packages/skills/review',
            contentHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            fileCount: 3,
            byteSize: 128,
          ),
        ],
      );
      final acquisition = WorkspaceSkillAcquisitionRepository(
        workspace: workspace,
        resolver: SkillSourceLocatorResolver(),
      );

      final inspection = await _completedValue(
        acquisition.inspect(
          const SkillSourceDraft(
            kind: SkillSourceKind.git,
            locator: 'owner/repository',
            sourceRef: 'release/v2',
            repositorySubpath: 'packages/skills',
          ),
        ),
      );

      final source = workspace.inspectedSources.single;
      expect(source.kind, WorkspaceSourceKind.git);
      expect(source.ref, 'release/v2');
      expect(source.repositorySubpath, 'packages/skills');
      expect(inspection.source.kind, SkillSourceKind.git);
      expect(inspection.source.ref, 'release/v2');
      expect(inspection.source.repositorySubpath, 'packages/skills');
      expect(inspection.candidates.single.fileCount, 3);
      expect(inspection.candidates.single.byteSize, 128);
    },
  );

  test(
    'acquisition adapter submits explicit project scope and store-only',
    () async {
      final workspace = FakeSkillsWorkspaceRepository();
      final acquisition = WorkspaceSkillAcquisitionRepository(
        workspace: workspace,
        resolver: SkillSourceLocatorResolver(),
      );

      await _completedValue(
        acquisition.install(
          InstallSelection(
            source: const ResolvedSkillSource(
              kind: SkillSourceKind.local,
              value: '/source',
            ),
            selectedSkillNames: {'Review'},
            selectedAgentIds: const {},
            installAllSkills: false,
            scope: SkillActivationScope.project,
            projectRootId: 'project',
            storeOnly: true,
          ),
        ),
      );

      final request = workspace.installRequests.single;
      expect(request.source.kind, WorkspaceSourceKind.local);
      expect(request.skillNames, {'Review'});
      expect(request.scope, WorkspaceScope.project);
      expect(request.projectRootId, 'project');
      expect(request.agentIds, isEmpty);
      expect(request.storeOnly, isTrue);
    },
  );

  test('explicit web source is not reclassified from its URL', () async {
    final workspace = FakeSkillsWorkspaceRepository();
    final acquisition = WorkspaceSkillAcquisitionRepository(
      workspace: workspace,
      resolver: SkillSourceLocatorResolver(),
    );

    await _completedValue(
      acquisition.inspect(
        const SkillSourceDraft(
          kind: SkillSourceKind.wellKnown,
          locator: 'https://github.com/owner/repository',
          sourceRef: 'ignored',
          repositorySubpath: 'ignored',
        ),
      ),
    );

    final source = workspace.inspectedSources.single;
    expect(source.kind, WorkspaceSourceKind.wellKnown);
    expect(source.ref, isNull);
    expect(source.repositorySubpath, isEmpty);
  });
}

Future<T> _completedValue<T>(AcquisitionTask<T> task) async {
  final completion = await task.completed;
  return switch (completion) {
    WorkspaceCompleted(:final value) => value,
    WorkspaceFailed(:final failure) => throw failure,
    WorkspaceCommittedPending(:final operationId) => throw StateError(
      'Unexpected committed-pending test operation $operationId.',
    ),
  };
}
