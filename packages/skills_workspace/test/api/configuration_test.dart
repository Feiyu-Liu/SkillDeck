import 'dart:io';

import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  test('configuration normalizes absolute paths and is immutable', () {
    final workspaceInput = Platform.isWindows
        ? r'C:\workspace\child\..'
        : '/tmp/workspace/child/..';
    final workspaceExpected = Platform.isWindows
        ? r'C:\workspace'
        : '/tmp/workspace';
    final homeInput = Platform.isWindows
        ? r'C:\home\.\agent'
        : '/tmp/home/./agent';
    final homeExpected = Platform.isWindows
        ? r'C:\home\agent'
        : '/tmp/home/agent';
    final agent = _agent('custom', 'Custom');
    final configuration = SkillsRepositoryConfiguration(
      rootPath: workspaceInput,
      agentHomePath: homeInput,
      additionalAgents: [agent],
      defaultLockWaitPolicy: LockWaitPolicy.wait(
        timeout: const Duration(seconds: 1),
      ),
    );

    expect(configuration.rootPath, workspaceExpected);
    expect(configuration.agentHomePath, homeExpected);
    expect(configuration.additionalAgents, [agent]);
    expect(
      () => configuration.additionalAgents.clear(),
      throwsUnsupportedError,
    );
    expect(configuration.defaultLockWaitPolicy.waits, isTrue);
  });

  test('configuration rejects relative paths and duplicate Agent IDs', () {
    final absolute = Platform.isWindows ? r'C:\workspace' : '/tmp/workspace';
    expect(
      () => SkillsRepositoryConfiguration(rootPath: 'relative'),
      throwsArgumentError,
    );
    expect(
      () => SkillsRepositoryConfiguration(
        rootPath: absolute,
        agentHomePath: 'relative',
      ),
      throwsArgumentError,
    );
    expect(
      () => SkillsRepositoryConfiguration(
        rootPath: absolute,
        additionalAgents: [
          _agent('duplicate', 'First'),
          _agent('duplicate', 'Second'),
        ],
      ),
      throwsArgumentError,
    );
  });
}

AgentDefinition _agent(String id, String displayName) => AgentDefinition(
  id: id,
  displayName: displayName,
  platforms: {
    DesktopPlatform.macos: AgentPlatformDefinition(
      globalSkillsPath: '/tmp/custom',
    ),
  },
);
