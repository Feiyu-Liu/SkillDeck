import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  test(
    'public factory can close without ever creating workspace state',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'skills-workspace-factory-direct-close-',
      );
      await root.delete(recursive: true);
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final repository = createSkillsRepository(
        SkillsRepositoryConfiguration(rootPath: root.path),
      );

      expect(await repository.close().completed, isA<SkillsSuccess<void>>());
      expect(await root.exists(), isFalse);
      expect(repository.isOpen, isFalse);
      expect(
        await repository.open().completed,
        isA<SkillsFailure<RepositorySnapshot>>().having(
          (failure) => failure.code,
          'code',
          SkillsErrorCode.operationFailed,
        ),
      );
    },
  );

  test('public factory constructs without opening runtime resources', () async {
    final root = await Directory.systemTemp.createTemp(
      'skills-workspace-factory-',
    );
    await root.delete(recursive: true);
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: root.path,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(milliseconds: 250),
        ),
      ),
    );

    expect(repository, isA<SkillsRepository>());
    expect(repository.isOpen, isFalse);
    expect(() => repository.snapshot, throwsStateError);
    expect(await root.exists(), isFalse);

    expect(
      await repository.open().completed,
      isA<SkillsSuccess<RepositorySnapshot>>(),
    );
    expect(await repository.close().completed, isA<SkillsSuccess<void>>());
  });

  test(
    'public factory opens, refreshes, exposes configured agents, and closes',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'skills-workspace-runtime-',
      );
      await workspace.delete(recursive: true);
      final agentHome = await Directory.systemTemp.createTemp(
        'skills-workspace-agent-home-',
      );
      addTearDown(() async {
        if (await workspace.exists()) await workspace.delete(recursive: true);
        if (await agentHome.exists()) await agentHome.delete(recursive: true);
      });
      final customLocation = path.join(agentHome.path, 'custom-skills');
      final repository = createSkillsRepository(
        SkillsRepositoryConfiguration(
          rootPath: workspace.path,
          agentHomePath: agentHome.path,
          additionalAgents: <AgentDefinition>[
            AgentDefinition(
              id: 'public-factory-agent',
              displayName: 'Public Factory Agent',
              platforms: <DesktopPlatform, AgentPlatformDefinition>{
                _platform(): AgentPlatformDefinition(
                  globalSkillsPath: customLocation,
                  projectSkillsPath: '.public-factory/skills',
                ),
              },
            ),
          ],
        ),
      );

      final opened = await repository.open().completed;
      expect(opened, isA<SkillsSuccess<RepositorySnapshot>>());
      expect(repository.isOpen, isTrue);
      expect(repository.snapshot.revision, RepositoryRevision.initial());

      final targets = await repository
          .inspectActivationTargets(
            InspectActivationTargetsRequest(scope: ActivationScope.global),
          )
          .completed;
      expect(targets, isA<SkillsSuccess<List<ActivationTargetInfo>>>());
      expect(
        targets.valueOrNull,
        contains(
          isA<ActivationTargetInfo>()
              .having(
                (target) => target.agentId,
                'agentId',
                'public-factory-agent',
              )
              .having((target) => target.location, 'location', customLocation),
        ),
      );
      expect(
        targets.valueOrNull,
        contains(
          isA<ActivationTargetInfo>()
              .having((target) => target.agentId, 'agentId', 'universal')
              .having(
                (target) => target.location,
                'location',
                path.join(agentHome.path, '.agents', 'skills'),
              ),
        ),
      );

      final refreshed = await repository.refresh().completed;
      expect(refreshed.valueOrNull, repository.snapshot);

      final closed = await repository.close().completed;
      expect(closed, isA<SkillsSuccess<void>>());
      expect(repository.isOpen, isFalse);
      await expectLater(repository.snapshots, emitsDone);
    },
  );

  test(
    'runtime ownership rejects a second facade until the first closes',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'skills-workspace-runtime-ownership-',
      );
      await workspace.delete(recursive: true);
      addTearDown(() async {
        if (await workspace.exists()) await workspace.delete(recursive: true);
      });
      SkillsRepository createRepository() => createSkillsRepository(
        SkillsRepositoryConfiguration(rootPath: workspace.path),
      );
      final first = createRepository();
      final second = createRepository();

      expect(
        await first.open().completed,
        isA<SkillsSuccess<RepositorySnapshot>>(),
      );
      expect(
        await second.open().completed,
        isA<SkillsFailure<RepositorySnapshot>>().having(
          (failure) => failure.code,
          'code',
          SkillsErrorCode.repositoryBusy,
        ),
      );

      expect(await first.close().completed, isA<SkillsSuccess<void>>());
      expect(
        await second.open().completed,
        isA<SkillsSuccess<RepositorySnapshot>>(),
      );
      expect(await second.close().completed, isA<SkillsSuccess<void>>());
    },
  );
}

DesktopPlatform _platform() {
  if (Platform.isMacOS) return DesktopPlatform.macos;
  if (Platform.isWindows) return DesktopPlatform.windows;
  return DesktopPlatform.linux;
}
