import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';

Future<void> main(List<String> arguments) async {
  final root = arguments.single;
  final home = path.join(root, 'isolated-home');
  final repository = createSkillsRepository(
    SkillsRepositoryConfiguration(
      rootPath: path.join(root, 'workspace'),
      agentHomePath: home,
    ),
  );
  try {
    final opened = await repository.open().completed;
    if (opened is! SkillsSuccess<RepositorySnapshot>) {
      throw StateError('Fixture workspace could not open.');
    }
    final targets = await repository
        .inspectActivationTargets(
          InspectActivationTargetsRequest(scope: ActivationScope.global),
        )
        .completed;
    if (targets is! SkillsSuccess<List<ActivationTargetInfo>>) {
      throw StateError('Fixture targets could not resolve.');
    }
    for (final target in targets.value) {
      if (!path.isWithin(home, target.location)) {
        throw StateError(
          'Agent target escaped configured home: ${target.agentId}',
        );
      }
    }
    final agents = await repository.inspectAgents().completed;
    if (agents is! SkillsSuccess<List<AgentInfo>>) {
      throw StateError('Fixture agent inspection failed.');
    }
    const isolatedIds = {'grok', 'sarvam-code', 'reasonix', 'deepseek-harness'};
    if (agents.value.any(
      (agent) => isolatedIds.contains(agent.id) && agent.detectedGlobally,
    )) {
      throw StateError('Agent detection escaped configured home.');
    }
    // A shared-root override must not leak into compatibility discovery either.
    final discovery = await repository
        .discoverExternalSkills(
          const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
        )
        .completed;
    if (discovery is! SkillsSuccess<ExternalSkillsDiscovery>) {
      throw StateError('Fixture discovery failed.');
    }
    if (discovery.value.candidates.isNotEmpty ||
        discovery.value.conflicts.isNotEmpty) {
      throw StateError('Compatibility discovery escaped configured home.');
    }
  } finally {
    await repository.close().completed;
  }
}
