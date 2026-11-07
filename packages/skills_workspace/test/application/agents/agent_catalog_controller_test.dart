import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog_controller.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  test('atomically replaces custom definitions and detects idempotence', () {
    final controller = AgentCatalogController.create(
      platform: DesktopPlatform.macos,
      detectionPort: FakeAgentDetectionPort(),
      builtIns: <AgentDefinition>[_agent('built-in')],
    ).valueOrNull!;
    final custom = _agent('custom');

    final first = controller.reconfigure(<AgentDefinition>[custom]);
    final second = controller.reconfigure(<AgentDefinition>[custom]);

    expect(first.valueOrNull!.changed, isTrue);
    expect(second.valueOrNull!.changed, isFalse);
    expect(controller.current.find('custom'), custom);
  });

  test('rejects a duplicate without replacing the current catalog', () {
    final builtIn = _agent('built-in');
    final controller = AgentCatalogController.create(
      platform: DesktopPlatform.macos,
      detectionPort: FakeAgentDetectionPort(),
      builtIns: <AgentDefinition>[builtIn],
    ).valueOrNull!;

    final result = controller.reconfigure(<AgentDefinition>[builtIn]);

    expect(result.failureOrNull?.code, ActivationFailureCode.duplicateAgentId);
    expect(controller.current.definitions, <AgentDefinition>[builtIn]);
  });
}

AgentDefinition _agent(String id) => AgentDefinition(
  id: id,
  displayName: id,
  platforms: <DesktopPlatform, AgentPlatformDefinition>{
    DesktopPlatform.macos: AgentPlatformDefinition(
      globalSkillsPath: '/agents/$id/skills',
    ),
  },
);
