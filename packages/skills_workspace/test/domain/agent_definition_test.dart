import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  test('Agent definitions are immutable value objects', () {
    final detection = AgentDetectionPath.absolute('/opt/agent');
    final platform = AgentPlatformDefinition(
      globalSkillsPath: '/opt/agent/skills',
      projectSkillsPath: '.agent/skills',
      globalDiscoverySkillsPaths: const <String>['/opt/agent/legacy-skills'],
      projectDiscoverySkillsPaths: const <String>['.agent/legacy-skills'],
      detectionPaths: [detection],
    );
    final definition = AgentDefinition(
      id: 'agent',
      displayName: 'Agent',
      platforms: {DesktopPlatform.linux: platform},
    );

    expect(
      definition,
      AgentDefinition(
        id: 'agent',
        displayName: 'Agent',
        platforms: {
          DesktopPlatform.linux: AgentPlatformDefinition(
            globalSkillsPath: '/opt/agent/skills',
            projectSkillsPath: '.agent/skills',
            globalDiscoverySkillsPaths: const <String>[
              '/opt/agent/legacy-skills',
            ],
            projectDiscoverySkillsPaths: const <String>['.agent/legacy-skills'],
            detectionPaths: [AgentDetectionPath.absolute('/opt/agent')],
          ),
        },
      ),
    );
    expect(definition.onPlatform(DesktopPlatform.linux), platform);
    expect(
      () => definition.platforms[DesktopPlatform.macos] = platform,
      throwsUnsupportedError,
    );
    expect(
      () => platform.detectionPaths.add(detection),
      throwsUnsupportedError,
    );
    expect(
      () => platform.globalDiscoverySkillsPaths.add('/other'),
      throwsUnsupportedError,
    );
    expect(
      () => platform.projectDiscoverySkillsPaths.add('.other'),
      throwsUnsupportedError,
    );
  });

  test('Agent paths are validated at the domain boundary', () {
    expect(
      () => AgentDetectionPath.absolute('relative/path'),
      throwsArgumentError,
    );
    expect(
      () => AgentDetectionPath.projectRelative('../skills'),
      throwsArgumentError,
    );
    expect(
      () => AgentDetectionPath.projectPackageDependency('  '),
      throwsArgumentError,
    );
    expect(
      () => AgentPlatformDefinition(globalSkillsPath: 'relative/skills'),
      throwsArgumentError,
    );
    expect(
      () => AgentPlatformDefinition(projectSkillsPath: '../skills'),
      throwsArgumentError,
    );
    expect(
      () => AgentPlatformDefinition(
        globalSkillsPath: '/opt/agent/skills',
        globalDiscoverySkillsPaths: const <String>['relative/skills'],
      ),
      throwsArgumentError,
    );
    expect(
      () => AgentPlatformDefinition(
        projectSkillsPath: '.agent/skills',
        projectDiscoverySkillsPaths: const <String>['../legacy'],
      ),
      throwsArgumentError,
    );
    expect(
      () => AgentPlatformDefinition(
        projectSkillsPath: '.agent/skills',
        globalDiscoverySkillsPaths: const <String>['/opt/legacy'],
      ),
      throwsArgumentError,
    );
    expect(
      () => AgentPlatformDefinition(
        globalSkillsPath: '/opt/agent/skills',
        projectDiscoverySkillsPaths: const <String>['.agent/legacy'],
      ),
      throwsArgumentError,
    );
  });
}
