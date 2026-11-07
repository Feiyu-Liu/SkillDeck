import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog_controller.dart';
import 'package:skills_workspace/src/application/agents/agent_root_ownership_auditor.dart';
import 'package:skills_workspace/src/application/ports/agent_root_ownership_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/agent_command_handlers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

import '../support/activation/activation_fakes.dart';

void main() {
  late WorkspaceSnapshotPublisher snapshots;
  late AgentCatalogController catalogs;
  late CompositeSkillsRepositoryCommandDispatcher dispatcher;

  setUp(() async {
    snapshots = WorkspaceSnapshotPublisher(
      reader: _SnapshotReader(
        RepositorySnapshot(
          revision: RepositoryRevision.initial(),
          projectRoots: <ProjectRoot>[
            ProjectRoot(id: 'project', path: '/workspace'),
          ],
        ),
      ),
    );
    await snapshots.publishInitial(
      RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        projectRoots: <ProjectRoot>[
          ProjectRoot(id: 'project', path: '/workspace'),
        ],
      ),
    );
    catalogs = AgentCatalogController.create(
      platform: DesktopPlatform.macos,
      detectionPort: FakeAgentDetectionPort(matches: (_, _) => true),
      builtIns: <AgentDefinition>[
        _agent('zeta', projectPath: '.zeta/skills'),
        _agent('alpha', projectPath: '.alpha/skills'),
      ],
    ).valueOrNull!;
    dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      buildAgentCommandHandlers(
        catalogs: catalogs,
        ownershipAuditor: AgentRootOwnershipAuditor(
          catalogs: catalogs,
          inspection: const _UnsupportedOwnershipInspection(),
          userHomePath: '/home/tester',
        ),
        snapshots: snapshots,
      ),
    );
  });

  tearDown(() => snapshots.close());

  test(
    'Agent inspection returns metadata without requiring a Project Root',
    () async {
      await snapshots.close();
      final empty = RepositorySnapshot(revision: RepositoryRevision.initial());
      snapshots = WorkspaceSnapshotPublisher(reader: _SnapshotReader(empty));
      await snapshots.publishInitial(empty);
      dispatcher = CompositeSkillsRepositoryCommandDispatcher(
        buildAgentCommandHandlers(
          catalogs: catalogs,
          ownershipAuditor: AgentRootOwnershipAuditor(
            catalogs: catalogs,
            inspection: const _UnsupportedOwnershipInspection(),
            userHomePath: '/home/tester',
          ),
          snapshots: snapshots,
        ),
      );
      final revision = snapshots.current.revision;
      final result = await _execute<List<AgentInfo>>(
        dispatcher,
        WorkspaceOperationKind.inspectAgents,
        const InspectAgentsRequest(),
      );
      expect(result.valueOrNull!.map((a) => a.id), ['alpha', 'zeta']);
      expect(
        result.valueOrNull!.every(
          (a) =>
              a.isBuiltIn &&
              a.supportedScopes.contains(ActivationScope.project),
        ),
        isTrue,
      );
      expect(
        result.valueOrNull!.every((a) => a.detectedProjectRootIds.isEmpty),
        isTrue,
      );
      expect(snapshots.current.revision, revision);
    },
  );

  test(
    'Agent inspection separates custom origin and scoped detection',
    () async {
      await _execute<RepositorySnapshot>(
        dispatcher,
        WorkspaceOperationKind.reconfigureAgentCatalog,
        ReconfigureAgentCatalogRequest(
          agents: [_agent('custom', projectPath: '.custom/skills')],
        ),
      );
      final result = await _execute<List<AgentInfo>>(
        dispatcher,
        WorkspaceOperationKind.inspectAgents,
        const InspectAgentsRequest(),
      );
      final custom = result.valueOrNull!.singleWhere((a) => a.id == 'custom');
      expect(custom.isBuiltIn, isFalse);
      expect(custom.detectedGlobally, isTrue);
      expect(custom.detectedProjectRootIds, {'project'});
      expect(() => custom.supportedScopes.clear(), throwsUnsupportedError);
    },
  );

  test('returns sorted detected targets for a Project Root', () async {
    final result = await _execute<List<ActivationTargetInfo>>(
      dispatcher,
      WorkspaceOperationKind.inspectActivationTargets,
      InspectActivationTargetsRequest(
        scope: ActivationScope.project,
        projectRootId: 'project',
      ),
    );

    expect(result.valueOrNull?.map((target) => target.agentId), <String>[
      'alpha',
      'zeta',
    ]);
    expect(result.valueOrNull?.every((target) => target.detected), isTrue);
    expect(
      result.valueOrNull?.first.location,
      path.join(_platformLocation('/workspace'), '.alpha', 'skills'),
    );
  });

  test('rejects an unknown Project Root', () async {
    final result = await _execute<List<ActivationTargetInfo>>(
      dispatcher,
      WorkspaceOperationKind.inspectActivationTargets,
      InspectActivationTargetsRequest(
        scope: ActivationScope.project,
        projectRootId: 'missing',
      ),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.projectRootNotFound);
  });

  test('reconfiguration is immediately visible to target inspection', () async {
    final custom = _agent('custom', projectPath: '.custom/skills');
    final reconfigured = await _execute<RepositorySnapshot>(
      dispatcher,
      WorkspaceOperationKind.reconfigureAgentCatalog,
      ReconfigureAgentCatalogRequest(agents: <AgentDefinition>[custom]),
    );
    final targets = await _execute<List<ActivationTargetInfo>>(
      dispatcher,
      WorkspaceOperationKind.inspectActivationTargets,
      InspectActivationTargetsRequest(scope: ActivationScope.global),
    );

    expect((reconfigured as SkillsSuccess<RepositorySnapshot>).changed, isTrue);
    expect(targets.valueOrNull?.map((target) => target.agentId), <String>[
      'alpha',
      'custom',
      'zeta',
    ]);
  });

  test('duplicate built-in reconfiguration is rejected atomically', () async {
    final result = await _execute<RepositorySnapshot>(
      dispatcher,
      WorkspaceOperationKind.reconfigureAgentCatalog,
      ReconfigureAgentCatalogRequest(
        agents: <AgentDefinition>[
          _agent('alpha', projectPath: '.another/skills'),
        ],
      ),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.duplicateAgentId);
    expect(catalogs.current.find('alpha')?.displayName, 'alpha');
  });
}

AgentDefinition _agent(String id, {required String projectPath}) =>
    AgentDefinition(
      id: id,
      displayName: id,
      platforms: <DesktopPlatform, AgentPlatformDefinition>{
        DesktopPlatform.macos: AgentPlatformDefinition(
          globalSkillsPath: '/agents/$id/skills',
          projectSkillsPath: projectPath,
          detectionPaths: <AgentDetectionPath>[
            AgentDetectionPath.absolute('/agents/$id'),
          ],
        ),
      },
    );

String _platformLocation(String value) => path.normalize(path.absolute(value));

Future<SkillsResult<T>> _execute<T>(
  CompositeSkillsRepositoryCommandDispatcher dispatcher,
  WorkspaceOperationKind kind,
  Object request,
) => dispatcher.execute<T>(
  operationId: OperationId('123e4567-e89b-42d3-a456-426614174000'),
  kind: kind,
  request: request,
  cancellationToken: CancellationToken.none(),
  markBusinessCommitted: () {},
  reportProgress: (phase, {currentItem, completed = 0, total}) {},
);

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  const _SnapshotReader(this.value);

  final RepositorySnapshot value;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      value;
}

final class _UnsupportedOwnershipInspection
    implements AgentRootOwnershipInspectionPort {
  const _UnsupportedOwnershipInspection();

  @override
  bool get supported => false;

  @override
  int currentUserId() => throw UnsupportedError('unsupported');

  @override
  Stream<String> descendants(String rootPath) => const Stream.empty();

  @override
  Future<AgentRootEntryMetadata?> inspect(String path) =>
      throw UnsupportedError('unsupported');

  @override
  Future<String> physicalDirectoryPath(String path) =>
      throw UnsupportedError('unsupported');
}
