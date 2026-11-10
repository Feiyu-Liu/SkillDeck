import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/command_host/data/command_host_dispatcher.dart';
import 'package:skills_manager/features/command_host/data/write_command_handlers.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity_reporter.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';

import 'support/read_fixtures.dart';
import 'support/write_repository.dart';

void main() {
  late WriteRepository repo;
  late ProviderContainer container;
  late CommandHostDispatcher dispatcher;
  final snapshots = <CommandLineActivity>[];

  setUp(() async {
    repo = WriteRepository();
    snapshots.clear();
    container = ProviderContainer(
      overrides: [
        skillsWorkspaceRepositoryProvider.overrideWithValue(repo),
        skillsUpdateCheckStoreProvider.overrideWithValue(
          InMemorySkillsUpdateCheckStore(),
        ),
        commandLineSummaryLifetimeProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
      ],
    );
    container.listen(commandLineActivityProvider, (_, next) {
      if (next != null) snapshots.add(next);
    });
    await container.read(workspaceSnapshotProvider.future);
    await container
        .read(skillUpdateStatusProvider.notifier)
        .restorePersistedState();
    dispatcher = CommandHostDispatcher(
      writeCommandHandlers(
        snapshot: () => repo.current,
        repository: () => repo,
        updates: () => container.read(skillUpdateStatusProvider),
        updateCoordinator: () =>
            container.read(skillUpdateStatusProvider.notifier),
        agents: () async => [testAgent()],
        members: () async => {'codex'},
        activity: CommandLineActivityReporter(
          controller: () =>
              container.read(commandLineActivityProvider.notifier),
          agentName: (id) => id == 'codex' ? 'Codex' : id,
        ),
      ),
    );
  });
  tearDown(() async {
    container.dispose();
    await repo.publications.close();
  });

  Future<CommandResult> run(
    String command, [
    Map<String, Object?> args = const {},
  ]) => dispatcher.dispatch(
    CommandRequest(
      command: command,
      arguments: {
        if (command != 'install')
          'selection': SkillSelection(all: true).toJson(),
        if (command == 'install') 'source': 'owner/repo',
        if (command == 'activate') 'agents': ['codex'],
        ...args,
      },
    ),
  );

  test('reports a batch as it runs and ends with each outcome', () async {
    repo.failures[2] = WorkspaceErrorCode.ioFailure;

    await run('activate');

    final first = snapshots.first;
    expect(first.kind, CommandLineActivityKind.activate);
    expect(first.agentNames, ['Codex']);
    expect(
      first.items.map((i) => i.status),
      everyElement(CommandLineItemStatus.queued),
    );
    expect(
      snapshots.any((s) => s.current?.slotKey == 'beta'),
      isTrue,
      reason: 'each Skill is shown as running while its operation runs',
    );
    final last = container.read(commandLineActivityProvider)!;
    expect(last.finished, isTrue);
    expect(last.items.map((i) => i.status), [
      CommandLineItemStatus.succeeded,
      CommandLineItemStatus.failed,
      CommandLineItemStatus.notAttempted,
    ]);
    expect(last.items[1].errorCode, 'ioFailure');
  });

  test(
    'install reports candidate Slot Keys before a Skill id exists',
    () async {
      await run('install');
      final last = container.read(commandLineActivityProvider)!;
      expect(last.kind, CommandLineActivityKind.install);
      expect(last.items.single.skillId, 'delta');
      expect(last.items.single.status, CommandLineItemStatus.succeeded);
      expect(last.finished, true);
    },
  );

  test('update reports every selected item', () async {
    await run('update');
    final last = container.read(commandLineActivityProvider)!;
    expect(last.kind, CommandLineActivityKind.update);
    expect(
      last.items.map((i) => i.status),
      everyElement(CommandLineItemStatus.unchanged),
    );
    expect(last.finished, true);
  });

  test('available update reports running and successful activity', () async {
    repo.updateReports = [
      for (final skill in repo.current.skills)
        WorkspaceUpdateReport(
          skillId: skill.id,
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
    ];
    await run('update', {'check': true});
    expect(snapshots, isEmpty);
    await run('update');
    final last = container.read(commandLineActivityProvider)!;
    expect(last.kind, CommandLineActivityKind.update);
    expect(
      last.items.map((i) => i.status),
      everyElement(CommandLineItemStatus.succeeded),
    );
    expect(snapshots.any((s) => s.current?.slotKey == 'alpha'), true);
  });

  test('install/update dry runs and update checks report nothing', () async {
    await run('install', {'dryRun': true});
    await run('update', {'dryRun': true});
    await run('update', {'check': true});
    expect(snapshots, isEmpty);
  });

  test('reports unfavorite as its own kind', () async {
    await run('favorite', {'favorite': false});

    expect(
      container.read(commandLineActivityProvider)?.kind,
      CommandLineActivityKind.unfavorite,
    );
  });

  test('a dry run and a tag rename report nothing', () async {
    await run('activate', {'dryRun': true});
    await dispatcher.dispatch(
      CommandRequest(
        command: 'tag rename',
        arguments: {
          'rename': {'from': 'missing', 'to': 'other'},
        },
      ),
    );

    expect(snapshots, isEmpty);
  });

  test('cancelling from the App stops the rest of the batch', () async {
    repo.blockAt = 2;
    final running = run('activate');
    await repo.started.future;

    container.read(commandLineActivityProvider.notifier).cancel();
    final result = await running;

    expect(result.error?.code, 'operationCancelled');
    final last = container.read(commandLineActivityProvider)!;
    expect(last.wasCancelled, isTrue);
    expect(last.items.last.status, CommandLineItemStatus.cancelled);
  });
}
