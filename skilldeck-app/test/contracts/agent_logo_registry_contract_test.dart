import 'dart:io';

import 'package:skills_workspace/src/application/agents/built_in_agent_definitions.dart';
import 'package:skills_workspace/skills_workspace.dart' show DesktopPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the reviewed Agent icon catalog remains explicit and complete', () {
    expect(AgentLogoRegistry.reviewedAgentIds, hasLength(81));
    final builtIns = buildBuiltInAgentDefinitions(
      platform: DesktopPlatform.macos,
      environment: {'HOME': Directory.systemTemp.path},
    );
    expect(
      AgentLogoRegistry.reviewedAgentIds,
      builtIns.map((agent) => agent.id).toSet(),
    );
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
