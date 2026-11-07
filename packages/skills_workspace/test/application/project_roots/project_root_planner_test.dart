import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/project_roots/project_root_planner.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';
import '../../support/discovery/discovery_fakes.dart';

void main() {
  late FakeProjectRootPathPort pathPort;
  late FakeProjectRootIdPort idPort;
  late ProjectRootPlanner planner;

  setUp(() {
    pathPort = FakeProjectRootPathPort();
    idPort = FakeProjectRootIdPort('generated');
    planner = ProjectRootPlanner(
      pathPort: pathPort,
      locationIdentity: const PosixActivationLocationIdentity(),
      idPort: idPort,
      clock: FixedWorkspaceClock(DateTime.utc(2026, 8, 17, 12)),
    );
  });

  test('registration emits one canonical PutProjectRoot change', () async {
    pathPort.canonicalPaths['/candidate/../project'] = '/project';

    final result = await planner.register(
      snapshot: RepositorySnapshot.empty(),
      candidatePath: '/candidate/../project',
    );

    final plan = result.valueOrNull!;
    expect(plan.changed, isTrue);
    expect(plan.projectRoot, ProjectRoot(id: 'generated', path: '/project'));
    expect(idPort.reservedIds, isEmpty);
    final mutation = plan.changeSet.mutations.single as PutProjectRoot;
    expect(mutation.projectRootId, 'generated');
    expect(mutation.canonicalPath, '/project');
    expect(
      mutation.createdAtMicros,
      DateTime.utc(2026, 8, 17, 12).microsecondsSinceEpoch,
    );
    expect(mutation.updatedAtMicros, mutation.createdAtMicros);
  });

  test('same ID and canonical path is an idempotent no-op', () async {
    pathPort.canonicalPaths['/alias'] = '/project';
    final existing = ProjectRoot(id: 'project', path: '/project');

    final result = await planner.register(
      snapshot: _snapshot(<ProjectRoot>[existing]),
      candidatePath: '/alias',
      requestedId: 'project',
    );

    expect(result.valueOrNull!.changed, isFalse);
    expect(result.valueOrNull!.projectRoot, existing);
    expect(result.valueOrNull!.changeSet, WorkspaceBusinessChangeSet.empty);
  });

  test('same ID with another path is an ID conflict', () async {
    pathPort.canonicalPaths['/other'] = '/other';

    final result = await planner.register(
      snapshot: _snapshot(<ProjectRoot>[
        ProjectRoot(id: 'project', path: '/project'),
      ]),
      candidatePath: '/other',
      requestedId: 'project',
    );

    expect(
      result.failureOrNull?.code,
      ProjectRootFailureCode.projectRootIdConflict,
    );
  });

  test('same canonical path with another ID is a path conflict', () async {
    pathPort.canonicalPaths['/alias'] = '/project';

    final result = await planner.register(
      snapshot: _snapshot(<ProjectRoot>[
        ProjectRoot(id: 'existing', path: '/project'),
      ]),
      candidatePath: '/alias',
      requestedId: 'other',
    );

    expect(
      result.failureOrNull?.code,
      ProjectRootFailureCode.projectRootPathConflict,
    );
    expect(result.failureOrNull?.context['projectRootId'], 'existing');
  });

  test('invalid or missing directory fails without a change-set', () async {
    pathPort.canonicalPaths['relative'] = null;

    final result = await planner.register(
      snapshot: RepositorySnapshot.empty(),
      candidatePath: 'relative',
    );

    expect(result.failureOrNull?.code, ProjectRootFailureCode.invalidPath);
  });

  test('unregistration emits one DeleteProjectRoot change', () {
    final root = ProjectRoot(id: 'project', path: '/project');

    final result = planner.unregister(
      snapshot: _snapshot(<ProjectRoot>[root]),
      projectRootId: root.id,
    );

    expect(result.valueOrNull!.changed, isTrue);
    expect(result.valueOrNull!.projectRoot, root);
    expect(
      (result.valueOrNull!.changeSet.mutations.single as DeleteProjectRoot)
          .projectRootId,
      root.id,
    );
  });

  test('unregistration preserves detached Activation provenance', () {
    final root = ProjectRoot(id: 'project', path: '/project');
    final skill = ManagedSkill(
      id: ManagedSkillId('00000000-0000-4000-8000-000000000001'),
      slotKey: 'review',
      declaredName: 'review',
      displayName: 'Review',
      description: 'Review Skill',
      source: LocalSourceDescriptor(locator: '/source/review'),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        publishedAt: DateTime.utc(2026),
      ),
      activations: <SkillActivation>[
        SkillActivation(
          location: '/project/.agents/skills',
          scope: ActivationScope.project,
          mode: ActivationMode.copy,
          agentIds: const <String>['agent'],
          projectRootId: root.id,
          projectRootPath: root.path,
        ),
      ],
    );

    final result = planner.unregister(
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        managedSkills: <ManagedSkill>[skill],
        projectRoots: <ProjectRoot>[root],
      ),
      projectRootId: root.id,
    );

    expect(result.valueOrNull!.changeSet.mutations, hasLength(1));
    expect(
      result.valueOrNull!.changeSet.mutations.whereType<DeleteActivation>(),
      isEmpty,
    );
    expect(
      result.valueOrNull!.changeSet.mutations.single,
      isA<DeleteProjectRoot>(),
    );
  });

  test('unregistering an unknown ID is explicit failure', () {
    final result = planner.unregister(
      snapshot: RepositorySnapshot.empty(),
      projectRootId: 'missing',
    );

    expect(
      result.failureOrNull?.code,
      ProjectRootFailureCode.projectRootNotFound,
    );
  });
}

RepositorySnapshot _snapshot(List<ProjectRoot> roots) => RepositorySnapshot(
  revision: RepositoryRevision.initial(),
  projectRoots: roots,
);
