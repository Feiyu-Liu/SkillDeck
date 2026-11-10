import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skilldeck_cli/src/cli/runner.dart';
import 'package:skills_manager/features/command_host/data/command_cancellation.dart';
import 'package:skills_manager/features/command_host/data/command_host_dispatcher.dart';
import 'package:skills_manager/features/command_host/data/command_host_server.dart';
import 'package:skills_manager/features/command_host/data/write_command_handlers.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import '../../support/recording_app_diagnostic_sink.dart';
import 'support/read_fixtures.dart';
import 'support/write_repository.dart';

void main() {
  late WriteRepository repo;
  late SkillsWorkspaceRepository seam;
  late CommandHostDispatcher dispatcher;
  setUp(() {
    repo = WriteRepository();
    seam = repo;
    dispatcher = CommandHostDispatcher(
      writeCommandHandlers(
        snapshot: () => repo.current,
        repository: () => seam,
        updates: () => SkillUpdateStatus(states: {}),
        agents: () async => [testAgent()],
        members: () async => {'codex'},
      ),
    );
  });
  Future<CommandResult> run(
    String command, {
    List<String>? refs,
    Map<String, Object?> args = const {},
    CommandCancellation? cancellation,
  }) => dispatcher.dispatch(
    CommandRequest(
      command: command,
      arguments: {
        if (command != 'tag rename')
          'selection': refs == null
              ? SkillSelection(all: true).toJson()
              : SkillSelection(refs: refs).toJson(),
        if (command == 'activate' || command == 'deactivate')
          'agents': ['codex'],
        ...args,
      },
    ),
    cancellation: cancellation,
  );
  List<String> outcomes(CommandResult r) =>
      r.results.cast<Map>().map((r) => r['outcome'] as String).toList();

  test('successful batch resolves once and performs sequential singleton operations', () async {
    final result = await run('activate');
    expect(outcomes(result), ['succeeded', 'succeeded', 'succeeded']);
    expect(repo.calls, ['activate', 'activate', 'activate']);
    expect(repo.skillSets.map((s) => s.single.value), [
      'alpha',
      'beta',
      'gamma',
    ]);
    expect(repo.maximumActive, 1);
    expect(result.results.cast<Map>().map((r) => r['operationId']), [
      'op-1',
      'op-2',
      'op-3',
    ]);
  });
  test(
    'failure stops and reports notAttempted without exposing diagnostics',
    () async {
      repo.failures[2] = WorkspaceErrorCode.ioFailure;
      final result = await run('activate');
      expect(outcomes(result), ['succeeded', 'failed', 'notAttempted']);
      expect(result.error!.code, 'partialBatch');
      expect(commandExitCode(result), 3);
      expect(repo.calls, hasLength(2));
      expect(jsonEncode(result.toJson()), isNot(contains('never-print')));
      expect(jsonEncode(result.toJson()), isNot(contains('sensitive text')));
    },
  );
  test(
    'first failure exits 1; unchanged does not count as committed',
    () async {
      repo.failures[1] = WorkspaceErrorCode.ioFailure;
      final result = await run('activate');
      expect(outcomes(result), ['failed', 'notAttempted', 'notAttempted']);
      expect(commandExitCode(result), 1);
    },
  );
  test('keep-going executes the remainder after failures', () async {
    repo.failures[1] = WorkspaceErrorCode.ioFailure;
    final result = await run('activate', args: {'keepGoing': true});
    expect(outcomes(result), ['failed', 'succeeded', 'succeeded']);
    expect(commandExitCode(result), 3);
  });
  test('unchanged favorite, activate, deactivate, notes and tag assignments skip mutations', () async {
    repo.current = testSnapshot(skills: [testSkill(id: 'alpha')]);
    expect(outcomes(await run('favorite')), ['unchanged']);
    expect(outcomes(await run('activate')), ['unchanged']);
    expect(
      outcomes(
        await run(
          'note',
          args: {
            'note': {'set': ' Personal note '},
          },
        ),
      ),
      ['unchanged'],
    );
    expect(
      outcomes(
        await run(
          'tag add',
          args: {
            'tags': ['testing'],
          },
        ),
      ),
      ['unchanged'],
    );
    expect(
      outcomes(
        await run(
          'tag remove',
          args: {
            'tags': ['Dart'],
          },
        ),
      ),
      ['unchanged'],
    );
    repo.current = testSnapshot(
      skills: [testSkill(id: 'alpha', activations: [])],
    );
    expect(outcomes(await run('deactivate')), ['unchanged']);
    expect(repo.calls, isEmpty);
  });
  test(
    'committed finalization pending has its own outcome and exits 0',
    () async {
      repo.pending.add(1);
      final result = await run('favorite', refs: ['alpha']);
      expect(outcomes(result), ['committedFinalizationPending']);
      expect((result.results.single as Map)['operationId'], 'pending-1');
      expect(commandExitCode(result), 0);
    },
  );
  test('unknown and nonmember Agents fail usage before any mutation', () async {
    final result = await run(
      'activate',
      args: {
        'agents': ['unknown'],
      },
    );
    expect(result.error!.code, 'unknownAgent');
    expect(result.error!.details, {'agent': 'unknown'});
    expect(commandExitCode(result), 2);
    expect(repo.calls, isEmpty);
  });
  test('project auto-registration occurs once before activation', () async {
    final result = await run('activate', args: {'projectPath': '/new/project'});
    expect(result.ok, true);
    expect(result.data['projectRootRegistered'], {
      'id': 'new-root',
      'path': '/new/project',
    });
    expect(repo.calls, ['register', 'activate', 'activate', 'activate']);
  });
  test('project dry-run predicts registration with zero writes', () async {
    final result = await run(
      'activate',
      args: {'projectPath': '/new/project', 'dryRun': true},
    );
    expect(outcomes(result), ['wouldSucceed', 'wouldSucceed', 'wouldSucceed']);
    expect(result.data['wouldRegisterProjectRoot'], {'path': '/new/project'});
    expect(result.data['dryRun'], true);
    expect(repo.calls, isEmpty);
  });
  test(
    'deactivate with an unregistered project never registers anything',
    () async {
      final result = await run(
        'deactivate',
        args: {'projectPath': '/new/project'},
      );
      expect(outcomes(result), ['unchanged', 'unchanged', 'unchanged']);
      expect(repo.calls, isEmpty);
    },
  );
  test(
    'deactivate selects only matching Agent locations within the scope',
    () async {
      repo.current = testSnapshot(skills: [testSkill(id: 'alpha')]);
      expect(
        (await run('deactivate', args: {'projectPath': '/projects/demo'})).ok,
        true,
      );
      expect(repo.locations, [
        {'/private/project/activation'},
      ]);
    },
  );
  test(
    'occupied targets require App action without confirming takeover',
    () async {
      repo.occupied = true;
      final result = await run('activate');
      expect(commandExitCode(result), 5);
      expect(result.error!.code, 'activationTargetOccupied');
      expect(result.error!.details, {'screen': 'skillDetail'});
      expect(outcomes(result), ['failed', 'notAttempted', 'notAttempted']);
      expect(repo.calls, ['activate']);
    },
  );
  test('ownership errors map to actionRequired and settings', () async {
    repo.failures[1] = WorkspaceErrorCode.agentRootOwnership;
    final result = await run('activate');
    expect(commandExitCode(result), 5);
    expect(result.error!.code, 'agentRootOwnershipRepairRequired');
    expect(result.error!.details, {'screen': 'settings'});
  });
  test('tag add creates a missing case-insensitive name once and assigns each Skill', () async {
    final result = await run(
      'tag add',
      args: {
        'tags': ['New', 'new'],
      },
    );
    expect(result.data['tagsCreated'], ['new']);
    expect(repo.calls, [
      'tag create',
      'tag assign',
      'tag assign',
      'tag assign',
    ]);
    expect(outcomes(result), ['succeeded', 'succeeded', 'succeeded']);
  });
  test('tag remove unknown reports tagNotFound', () async {
    final result = await run(
      'tag remove',
      args: {
        'tags': ['absent'],
      },
    );
    expect(result.error!.code, 'tagNotFound');
    expect(commandExitCode(result), 1);
    expect(repo.calls, isEmpty);
  });
  test('tag rename conflict, missing, unchanged and success', () async {
    expect(
      (await run(
        'tag rename',
        args: {
          'rename': {'from': 'testing', 'to': 'dart'},
        },
      )).error!.code,
      'tagNameConflict',
    );
    expect(
      (await run(
        'tag rename',
        args: {
          'rename': {'from': 'missing', 'to': 'new'},
        },
      )).error!.code,
      'tagNotFound',
    );
    expect(
      outcomes(
        await run(
          'tag rename',
          args: {
            'rename': {'from': 'Testing', 'to': 'Testing'},
          },
        ),
      ),
      ['unchanged'],
    );
    expect(
      (await run(
        'tag rename',
        args: {
          'rename': {'from': 'testing', 'to': 'Renamed'},
        },
      )).ok,
      true,
    );
    expect(repo.calls, ['tag rename']);
  });
  test('notes set and clear require exactly one Skill; blank set is stable failure', () async {
    expect(
      (await run(
        'note',
        refs: ['alpha'],
        args: {
          'note': {'set': 'text'},
        },
      )).ok,
      true,
    );
    expect(
      (await run(
        'note',
        refs: ['alpha'],
        args: {
          'note': {'clear': true},
        },
      )).ok,
      true,
    );
    expect(repo.calls, ['note set', 'note clear']);
    expect(
      (await run(
        'note',
        args: {
          'note': {'clear': true},
        },
      )).error!.code,
      'ambiguousSelection',
    );
    expect(
      (await run(
        'note',
        refs: ['alpha'],
        args: {
          'note': {'set': ' '},
        },
      )).error!.code,
      'invalidNote',
    );
  });
  test('all dry-run writes perform zero mutations', () async {
    for (final command in [
      'favorite',
      'note',
      'tag add',
      'tag remove',
      'tag rename',
    ]) {
      final result = await run(
        command,
        refs: ['alpha'],
        args: {
          'dryRun': true,
          if (command == 'note') 'note': {'clear': true},
          if (command.startsWith('tag ') && command != 'tag rename')
            'tags': [command == 'tag add' ? 'New' : 'Testing'],
          if (command == 'tag rename')
            'rename': {'from': 'Testing', 'to': 'New'},
        },
      );
      expect(result.ok, true);
      expect(result.data['dryRun'], true);
      if (command == 'tag add') expect(result.data['wouldCreateTags'], ['New']);
    }
    expect(repo.calls, isEmpty);
  });
  test(
    'cancellation mid-batch cancels in-flight task and remaining items',
    () async {
      repo.blockAt = 2;
      final cancellation = CommandCancellation();
      final running = run('activate', cancellation: cancellation);
      await repo.started.future;
      await cancellation.cancel();
      final result = await running;
      expect(outcomes(result), ['succeeded', 'cancelled', 'cancelled']);
      expect(repo.taskCancelled, true);
      expect(commandExitCode(result), 130);
      expect(repo.calls, ['activate', 'activate']);
    },
  );
  test(
    'sub-operation commit then failure remains partial even on first Skill',
    () async {
      repo.failures[2] = WorkspaceErrorCode.ioFailure;
      final result = await run(
        'tag add',
        refs: ['alpha'],
        args: {
          'tags': ['New'],
        },
      );
      expect(commandExitCode(result), 3);
      expect(result.data['tagsCreated'], ['New']);
    },
  );
  test(
    'unchanged items do not turn a later first mutation failure into partial',
    () async {
      repo.current = testSnapshot(
        skills: [
          testSkill(id: 'alpha', name: 'Alpha', favorite: true),
          testSkill(id: 'beta', name: 'Beta', favorite: false),
        ],
      );
      repo.failures[1] = WorkspaceErrorCode.ioFailure;
      final result = await run('favorite');
      expect(outcomes(result), ['unchanged', 'failed']);
      expect(commandExitCode(result), 1);
    },
  );
  test('all keep-going failures remain exit 1, and actionRequired after commit is partial', () async {
    repo.failures.addAll({
      1: WorkspaceErrorCode.ioFailure,
      2: WorkspaceErrorCode.ioFailure,
      3: WorkspaceErrorCode.ioFailure,
    });
    expect(
      commandExitCode(await run('activate', args: {'keepGoing': true})),
      1,
    );
    repo.failures.clear();
    repo.failures[repo.calls.length + 2] =
        WorkspaceErrorCode.agentRootOwnership;
    final result = await run('activate');
    expect(commandExitCode(result), 3);
    expect(outcomes(result), ['succeeded', 'failed', 'notAttempted']);
  });
  test('known catalog Agent without membership is unknownAgent', () async {
    final disabled = CommandHostDispatcher(
      writeCommandHandlers(
        snapshot: () => repo.current,
        repository: () => repo,
        updates: () => SkillUpdateStatus(states: {}),
        agents: () async => [testAgent()],
        members: () async => {},
      ),
    );
    final result = await disabled.dispatch(
      CommandRequest(
        command: 'activate',
        arguments: {
          'selection': SkillSelection(all: true).toJson(),
          'agents': ['codex'],
        },
      ),
    );
    expect(result.error!.code, 'unknownAgent');
    expect(repo.calls, isEmpty);
  });
  test(
    'server stop awaits cooperative cancellation before releasing the endpoint',
    () async {
      final temp = await Directory.systemTemp.createTemp('sd-write-stop-');
      final server = CommandHostServer(
        runDirectory: temp.path,
        isWindows: Platform.isWindows,
        appVersion: () async => 'test',
        dispatcher: dispatcher,
        diagnostics: AppDiagnostics.disabled(),
      );
      repo.blockAt = 1;
      await server.start();
      final client = await CommandHostClient(runDirectory: temp.path).connect();
      final executing = client
          .execute(
            CommandRequest(
              command: 'activate',
              arguments: {
                'selection': SkillSelection(all: true).toJson(),
                'agents': ['codex'],
              },
            ),
          )
          .then<void>((_) {}, onError: (Object _) {});
      try {
        await repo.started.future;
        await server.stop();
        expect(repo.taskCancelled, true);
        expect(repo.active, 0);
        expect(repo.calls, ['activate']);
        await executing;
      } finally {
        await client.close();
        await server.stop();
        await temp.delete(recursive: true);
      }
    },
  );
  test('real server and CLI round trip activate/favorite and disconnect cancellation', () async {
    final temp = await Directory.systemTemp.createTemp('sd-write-');
    final runDirectory = p.join(temp.path, '.skilldeck', 'run');
    final sink = RecordingAppDiagnosticSink();
    final server = CommandHostServer(
      runDirectory: runDirectory,
      isWindows: Platform.isWindows,
      appVersion: () async => 'test',
      dispatcher: dispatcher,
      diagnostics: AppDiagnostics(sink: sink),
    );
    await server.start();
    try {
      for (final command in ['activate', 'favorite']) {
        final out = StringBuffer();
        final err = StringBuffer();
        expect(
          await runSkilldeck(
            [
              command,
              '--all',
              if (command == 'activate') ...['--agent', 'codex'],
              '--json',
              '--no-launch',
            ],
            environment: {'HOME': temp.path, 'USERPROFILE': temp.path},
            isWindows: Platform.isWindows,
            out: out,
            err: err,
          ),
          0,
        );
        expect((jsonDecode(out.toString()) as Map)['results'], hasLength(3));
        expect(err.toString(), isEmpty);
      }
      repo.blockAt = repo.calls.length + 1;
      final client = await CommandHostClient(runDirectory: runDirectory)
          .connect();
      final executing = client.execute(
        CommandRequest(
          command: 'activate',
          arguments: {
            'selection': SkillSelection(all: true).toJson(),
            'agents': ['codex'],
          },
        ),
      );
      final ignored = executing.then<void>((_) {}, onError: (Object _) {});
      await repo.started.future;
      await client.close();
      await ignored;
      // Wait on the actual cancel event, not a fixed timing assumption.
      for (var i = 0; i < 100 && !repo.taskCancelled; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(repo.taskCancelled, true);
      final diagnostics = jsonEncode(
        sink.events.map((e) => e.toJson()).toList(),
      );
      expect(diagnostics, isNot(contains('alpha')));
      expect(diagnostics, isNot(contains(temp.path)));
    } finally {
      await server.stop();
      await temp.delete(recursive: true);
    }
  });
}
