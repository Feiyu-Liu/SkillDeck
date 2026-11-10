import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/command_host/presentation/command_host_providers.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_distribution_providers.dart';
import 'package:skills_manager/features/command_host/data/command_line_distribution_service.dart';
import 'package:skills_manager/features/settings/data/skills_manager_runtime.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

import '../../support/fake_skills_workspace_repository.dart';

void main() {
  test('unconfigured embedding never accesses home or runtime', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(commandHostProvider.future), isNull);
  });

  for (final shutdown in ['runtime', 'dispose']) {
    test(
      'starts after open, keeps one host across snapshots, stops on $shutdown',
      () async {
        final temp = await Directory.systemTemp.createTemp('sd-provider-');
        final run = p.join(temp.path, '.skilldeck', 'run');
        final repository = FakeSkillsWorkspaceRepository();
        final opening =
            Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
        repository.openCompleter = opening;
        final diagnostics = AppDiagnostics.disabled();
        final runtime = SkillsManagerRuntime(
          repositoryRoot: p.join(temp.path, 'workspace'),
          settings: const AppSettings(),
          diagnostics: diagnostics,
          failureReporter: AppFailureReporter(diagnostics),
          workspace: repository,
        );
        final bundled = await File(p.join(temp.path, 'bundled'))
            .writeAsString('bundled CLI');
        var sourceLoads = 0;
        final distribution = CommandLineDistributionService(
          rootDirectory: p.join(temp.path, '.skilldeck'),
          bundledExecutable: bundled.path,
          isWindows: Platform.isWindows,
          loadSkill: () async {
            // Source refresh starts only after the host publishes discovery.
            expect(
              await File(p.join(run, commandHostDiscoveryFileName)).exists(),
              isTrue,
            );
            sourceLoads++;
            return 'Agent Skill asset'.codeUnits;
          },
          diagnostics: diagnostics,
        );
        Future<void> Function()? stop;
        final container = ProviderContainer(
          overrides: [
            commandLineDistributionServiceProvider.overrideWithValue(
              distribution,
            ),
            commandHostConfigurationProvider.overrideWithValue(
              CommandHostConfiguration(
                environment: {'HOME': temp.path, 'USERPROFILE': temp.path},
                isWindows: Platform.isWindows,
              ),
            ),
            commandHostAppVersionProvider.overrideWith((ref) async => '9.8.7'),
            skillsManagerRuntimeFactoryProvider.overrideWithValue(
              () => runtime,
            ),
            skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
            commandHostShutdownRegistrarProvider.overrideWithValue(
              (callback) => stop = callback,
            ),
          ],
        );
        var disposed = false;
        try {
          final starting = container.read(commandHostProvider.future);
          await Future<void>.delayed(Duration.zero);
          expect(
            await File(p.join(run, commandHostDiscoveryFileName)).exists(),
            isFalse,
          );
          expect(await File(distribution.toolPath).exists(), isFalse);
          expect(
            await Directory(distribution.sourceDirectory).exists(),
            isFalse,
          );
          opening.complete(
            WorkspaceCompleted(value: SkillsWorkspaceSnapshot.empty()),
          );
          final server = await starting;
          expect(server, isNotNull);
          expect(
            await File(distribution.toolPath).readAsString(),
            'bundled CLI',
          );
          expect(sourceLoads, 1);
          final before = await readDiscovery(run);
          repository.publish(
            SkillsWorkspaceSnapshot(
              revision: 2,
              skills: const [],
              projectRoots: [
                SkillProjectRoot(
                  id: 'test',
                  path: p.join(temp.path, 'project'),
                ),
              ],
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            await container.read(commandHostProvider.future),
            same(server),
          );
          expect((await readDiscovery(run)).secret, before.secret);
          expect(sourceLoads, 1);
          final status = await CommandHostClient(runDirectory: run)
              .execute(CommandRequest(command: 'status'));
          expect(status.data['appVersion'], '9.8.7');
          expect((status.data['workspace'] as Map)['projectRootCount'], 1);
          if (shutdown == 'runtime') {
            // Registered beforeClose hooks execute before Workspace close.
            await runtime.close();
          } else {
            container.dispose();
            disposed = true;
            await stop!();
          }
          expect(
            await File(p.join(run, commandHostDiscoveryFileName)).exists(),
            isFalse,
          );
          expect(await File(distribution.toolPath).exists(), isTrue);
          expect(
            await Directory(distribution.sourceDirectory).exists(),
            isTrue,
          );
        } finally {
          if (!disposed) container.dispose();
          await stop?.call();
          await runtime.close();
          await temp.delete(recursive: true);
        }
      },
    );
  }
  test('shutdown during pending open cannot publish a late host', () async {
    final temp = await Directory.systemTemp.createTemp('sd-dispose-');
    final repository = FakeSkillsWorkspaceRepository();
    final opening = Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
    repository.openCompleter = opening;
    final diagnostics = AppDiagnostics.disabled();
    final runtime = SkillsManagerRuntime(
      repositoryRoot: temp.path,
      settings: const AppSettings(),
      diagnostics: diagnostics,
      failureReporter: AppFailureReporter(diagnostics),
      workspace: repository,
    );
    Future<void> Function()? stop;
    final container = ProviderContainer(
      overrides: [
        commandHostConfigurationProvider.overrideWithValue(
          CommandHostConfiguration(
            environment: {'HOME': temp.path, 'USERPROFILE': temp.path},
            isWindows: Platform.isWindows,
          ),
        ),
        commandHostAppVersionProvider.overrideWith((ref) async => '1.0'),
        skillsManagerRuntimeFactoryProvider.overrideWithValue(() => runtime),
        skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
        commandHostShutdownRegistrarProvider.overrideWithValue(
          (callback) => stop = callback,
        ),
      ],
    );
    final starting = container.read(commandHostProvider.future);
    await Future<void>.delayed(Duration.zero);
    await stop!();
    opening.complete(
      WorkspaceCompleted(value: SkillsWorkspaceSnapshot.empty()),
    );
    expect(await starting, isNull);
    expect(await Directory(p.join(temp.path, '.skilldeck')).exists(), isFalse);
    container.dispose();
    await runtime.close();
    await temp.delete(recursive: true);
  });
  test('runtime closes Workspace even if Command Host cleanup fails', () async {
    final temp = await Directory.systemTemp.createTemp('sd-close-failure-');
    final repository = FakeSkillsWorkspaceRepository();
    final diagnostics = AppDiagnostics.disabled();
    final runtime = SkillsManagerRuntime(
      repositoryRoot: temp.path,
      settings: const AppSettings(),
      diagnostics: diagnostics,
      failureReporter: AppFailureReporter(diagnostics),
      workspace: repository,
    );
    runtime.addBeforeClose(() async {
      expect(repository.closeCalls, 0);
      throw StateError('cleanup failed');
    });
    await expectLater(runtime.close(), throwsStateError);
    expect(repository.closeCalls, 1);
    await expectLater(runtime.close(), throwsStateError);
    expect(repository.closeCalls, 1);
    await temp.delete(recursive: true);
  });
}
