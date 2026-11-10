import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the reviewed Agent icon catalog remains explicit and complete', () async {
    expect(AgentLogoRegistry.reviewedAgentIds, hasLength(81));
    final root = await Directory.systemTemp.createTemp('agent-icon-catalog-');
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: path.join(root.path, 'workspace'),
        agentHomePath: path.join(root.path, 'agent-home'),
      ),
    );
    addTearDown(() async {
      await repository.close().completed;
      await root.delete(recursive: true);
    });
    expect(
      await repository.open().completed,
      isA<SkillsSuccess<RepositorySnapshot>>(),
    );
    final inspected = await repository.inspectAgents().completed;
    expect(inspected, isA<SkillsSuccess<List<AgentInfo>>>());
    expect(AgentLogoRegistry.reviewedAgentIds, {
      ...inspected.valueOrNull!.map((agent) => agent.id),
      // Universal is a location convention, omitted by public Agent inspection.
      'universal',
    });
    expect(
      AgentLogoRegistry.reviewedAgentIds,
      containsAll(AgentLogoRegistry.assetSlugs.keys),
    );
    expect(
      AgentLogoRegistry.reviewedAgentIds,
      containsAll(const {'claude-code', 'codex', 'gemini-cli', 'universal'}),
    );
  });

  test(
    'every mapped icon is bundled and aliases reuse curated assets',
    () async {
      expect(AgentLogoRegistry.assetSlugs, hasLength(36));
      expect(AgentLogoRegistry.monochromeAssetPaths, hasLength(33));
      expect(AgentLogoRegistry.colorAssetPaths, hasLength(21));
      expect(AgentLogoRegistry.assetPaths, hasLength(54));
      expect(
        AgentLogoRegistry.monochromeAssetPathFor('claude-code'),
        'assets/agent_icons/claudecode.svg',
      );
      expect(
        AgentLogoRegistry.colorAssetPathFor('claude-code'),
        'assets/agent_icons/claudecode-color.svg',
      );
      expect(
        AgentLogoRegistry.colorAssetPathFor('antigravity'),
        'assets/agent_icons/antigravity-color.png',
      );
      expect(
        AgentLogoRegistry.monochromeAssetPathFor('qoder-cn'),
        AgentLogoRegistry.monochromeAssetPathFor('qoder'),
      );
      expect(AgentLogoRegistry.colorAssetPathFor('cursor'), isNull);
      expect(AgentLogoRegistry.monochromeAssetPathFor('universal'), isNull);

      for (final assetPath in AgentLogoRegistry.assetPaths) {
        expect(await rootBundle.load(assetPath), isNotNull, reason: assetPath);
      }
    },
  );
}
