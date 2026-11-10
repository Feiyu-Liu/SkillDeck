import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skilldeck_cli/src/cli/runner.dart';
import 'package:skills_manager/features/command_host/data/command_cancellation.dart';
import 'package:skills_manager/features/command_host/data/command_host_dispatcher.dart';
import 'package:skills_manager/features/command_host/data/command_host_server.dart';
import 'package:skills_manager/features/command_host/data/write_command_handlers.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_input_parser.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import 'support/read_fixtures.dart';
import 'support/write_repository.dart';

void main() {
  late WriteRepository repo;
  late ProviderContainer container;
  late CommandHostDispatcher dispatcher;
  SkillUpdateStatusCoordinator coordinator() =>
      container.read(skillUpdateStatusProvider.notifier);
  SkillUpdateStatus updates() => container.read(skillUpdateStatusProvider);

  setUp(() async {
    repo = WriteRepository();
    container = ProviderContainer(
      overrides: [
        skillsWorkspaceRepositoryProvider.overrideWithValue(repo),
        skillsUpdateCheckStoreProvider.overrideWithValue(
          InMemorySkillsUpdateCheckStore(),
        ),
      ],
    );
    await container.read(workspaceSnapshotProvider.future);
    await coordinator().restorePersistedState();
    dispatcher = CommandHostDispatcher(
      writeCommandHandlers(
        snapshot: () => repo.current,
        repository: () => repo,
        updates: updates,
        updateCoordinator: coordinator,
        agents: () async => [testAgent()],
        members: () async => {'codex'},
      ),
    );
  });
  tearDown(() async {
    container.dispose();
    await repo.publications.close();
  });

  Future<CommandResult> install([Map<String, Object?> args = const {}]) =>
      dispatcher.dispatch(
        CommandRequest(
          command: 'install',
          arguments: {'source': 'owner/repo', ...args},
        ),
      );
  Future<CommandResult> update([Map<String, Object?> args = const {}]) =>
      dispatcher.dispatch(
        CommandRequest(
          command: 'update',
          arguments: {'selection': SkillSelection(all: true).toJson(), ...args},
        ),
      );
  List<Object?> outcomes(CommandResult r) => [
    for (final item in r.results) (item as Map)['outcome'],
  ];
  Future<void> available() async {
    repo.updateReports = [
      for (final s in repo.current.skills)
        WorkspaceUpdateReport(
          skillId: s.id,
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
    ];
    await update({'check': true});
    repo.calls.clear();
  }

  for (final source in [
    'owner/repo',
    'https://github.com/owner/repo.git',
    // A local Source is an absolute path in the host platform's own form.
    Platform.isWindows ? r'C:\fixture\skills' : '/fixture/skills',
    'https://skills.example.test/catalog',
  ]) {
    test('source matches GUI smart input: $source', () async {
      final parsed = SkillSourceInputParser(homePath: '/unused')
          .parse(source, mode: SkillSourceInputMode.smart);
      final expected = SkillSourceLocatorResolver(homePath: '/unused')
          .resolve(parsed.draft);
      final result = await install({'source': source, 'dryRun': true});
      expect(result.ok, true);
      final actual = repo.inspectedSources.single;
      expect(actual.kind.name, expected.kind.name);
      expect(actual.locator, expected.value);
      expect(actual.ref, expected.ref);
      expect(actual.repositorySubpath, expected.repositorySubpath);
      expect(repo.installRequests, isEmpty);
    });
  }
  test(
    'web input uses the shared well-known to Git fallback predicate',
    () async {
      repo.inspectionFailure = WorkspaceErrorCode.httpFailure;
      repo.inspectionFailureContext = {'reason': 'unexpectedStatus'};
      final result = await install({'source': 'https://example.test/catalog'});
      expect(result.ok, true);
      expect(repo.inspectedSources.map((s) => s.kind), [
        WorkspaceSourceKind.wellKnown,
        WorkspaceSourceKind.git,
      ]);
      expect(repo.installRequests.single.source.kind, WorkspaceSourceKind.git);
    },
  );
  test('web transport failure does not fall back', () async {
    repo.inspectionFailure = WorkspaceErrorCode.httpFailure;
    expect(
      (await install({'source': 'https://example.test'})).error?.code,
      'httpFailure',
    );
    expect(repo.inspectedSources, hasLength(1));
  });
  test(
    'single candidate installs store-only and returns its assigned id',
    () async {
      final result = await install();
      expect(result.ok, true);
      expect(repo.installRequests.single.storeOnly, true);
      expect(repo.installRequests.single.skillNames, {'delta'});
      expect(result.results.single, containsPair('id', 'installed-delta'));
      expect(result.results.single, containsPair('slotKey', 'delta'));
      expect(result.results.single, containsPair('operationId', 'op-2'));
    },
  );
  test('several candidates are ambiguous with bounded retry details', () async {
    repo.candidates = [
      for (var i = 0; i < 205; i++) WriteRepository.candidate('slot-$i'),
    ];
    final result = await install();
    expect(result.error?.code, 'ambiguousSource');
    expect(commandExitCode(result), 2);
    final candidates = result.error!.details['candidates'] as List;
    expect(candidates, hasLength(200));
    expect(candidates.first, {
      'name': 'slot-0',
      'slotKey': 'slot-0',
      'description': 'Description of slot-0',
    });
    expect(repo.installRequests, isEmpty);
  });
  test(
    'skill names and slot keys match case-insensitively and deduplicate',
    () async {
      repo.candidates = [
        WriteRepository.candidate('delta', name: 'Delta Name'),
        WriteRepository.candidate('epsilon'),
      ];
      expect(
        (await install({
          'skills': ['DELTA NAME', 'DELTA'],
        })).ok,
        true,
      );
      expect(repo.installRequests.single.skillNames, {'Delta Name'});
    },
  );
  test('unknown skill fails before any installs', () async {
    expect(
      (await install({
        'skills': ['missing'],
      })).error?.code,
      'candidateNotFound',
    );
    expect(repo.installRequests, isEmpty);
  });
  test('inline smart input selection is honored', () async {
    repo.candidates = [
      WriteRepository.candidate('delta'),
      WriteRepository.candidate('epsilon'),
    ];
    expect((await install({'source': 'owner/repo@delta'})).ok, true);
    expect(repo.installRequests.single.skillNames, {'delta'});
  });
  test(
    'all skills install sequentially, with source userinfo stripped in output',
    () async {
      repo.candidates = [
        WriteRepository.candidate('delta'),
        WriteRepository.candidate('epsilon'),
      ];
      final result = await install({
        'allSkills': true,
        'source': 'https://user:secret@github.com/owner/repo',
      });
      expect(outcomes(result), ['succeeded', 'succeeded']);
      expect(repo.installRequests.map((r) => r.skillNames), [
        {'delta'},
        {'epsilon'},
      ]);
      expect(repo.maximumActive, 1);
      expect(jsonEncode(result.toJson()), isNot(contains('user:secret')));
    },
  );
  test(
    'agent activates globally, project registers once before install',
    () async {
      final result = await install({
        'agents': ['codex'],
        'projectPath': '/fixture/new',
      });
      expect(result.ok, true);
      expect(repo.calls, ['inspect', 'register', 'install']);
      final request = repo.installRequests.single;
      expect(request.storeOnly, false);
      expect(request.agentIds, {'codex'});
      expect(request.scope, WorkspaceScope.project);
      expect(request.projectRootId, 'new-root');
      expect(result.data['projectRootRegistered'], {
        'id': 'new-root',
        'path': '/fixture/new',
      });
    },
  );
  test('global agent install does not register a project', () async {
    await install({
      'agents': ['codex'],
    });
    expect(repo.installRequests.single.scope, WorkspaceScope.global);
    expect(repo.installRequests.single.storeOnly, false);
    expect(repo.calls, ['inspect', 'install']);
  });
  test('takeover returns actionRequired without confirmation', () async {
    repo.occupied = true;
    final result = await install({
      'agents': ['codex'],
    });
    expect(commandExitCode(result), 5);
    expect(result.error?.code, 'actionRequired');
    expect(
      (result.results.single as Map)['error'],
      containsPair('code', 'activationTargetOccupied'),
    );
    expect(result.error?.details['screen'], 'addSkill');
    expect(repo.calls, ['inspect', 'install']);
  });
  test(
    'installed slot and repository duplicate both map to alreadyInstalled',
    () async {
      repo.candidates = [WriteRepository.candidate('alpha')];
      expect((await install()).error?.code, 'alreadyInstalled');
      repo.candidates = [WriteRepository.candidate('delta')];
      repo.failures[3] = WorkspaceErrorCode.duplicateSkillSlot;
      expect((await install()).error?.code, 'alreadyInstalled');
    },
  );
  for (final keepGoing in [false, true]) {
    test('install stop/keep-going: $keepGoing', () async {
      repo.candidates = [
        for (final slot in ['delta', 'epsilon', 'zeta'])
          WriteRepository.candidate(slot),
      ];
      repo.failures[3] = WorkspaceErrorCode.ioFailure;
      final result = await install({'allSkills': true, 'keepGoing': keepGoing});
      expect(outcomes(result), [
        'succeeded',
        'failed',
        keepGoing ? 'succeeded' : 'notAttempted',
      ]);
      expect(commandExitCode(result), 3);
    });
  }
  test('install cancellation stops remaining operations', () async {
    repo.candidates = [
      WriteRepository.candidate('delta'),
      WriteRepository.candidate('epsilon'),
    ];
    repo.blockAt = 2;
    final cancellation = CommandCancellation();
    final running = dispatcher.dispatch(
      CommandRequest(
        command: 'install',
        arguments: {'source': 'owner/repo', 'allSkills': true},
      ),
      cancellation: cancellation,
    );
    await repo.started.future;
    await cancellation.cancel();
    final result = await running;
    expect(commandExitCode(result), 130);
    expect(outcomes(result), ['cancelled', 'cancelled']);
    expect(repo.installRequests, hasLength(1));
  });
  test('dry install reports installed slots and project registration without writes', () async {
    repo.candidates = [
      WriteRepository.candidate('alpha'),
      WriteRepository.candidate('delta'),
    ];
    final result = await install({
      'allSkills': true,
      'agents': ['codex'],
      'projectPath': '/fixture/new',
      'dryRun': true,
    });
    expect(outcomes(result), ['alreadyInstalled', 'wouldSucceed']);
    expect(result.data['wouldRegisterProjectRoot'], {'path': '/fixture/new'});
    expect(repo.calls, ['inspect']);
  });
  test('install preserves committed finalization pending', () async {
    repo.pending.add(2);
    final result = await install();
    expect(outcomes(result), ['committedFinalizationPending']);
    expect(commandExitCode(result), 0);
  });
  test(
    'update check goes through coordinator and publishes badge state',
    () async {
      await available();
      expect(
        updates().availableSkillIds,
        repo.current.skills.map((s) => s.id).toSet(),
      );
      expect(repo.skillSets, isEmpty);
    },
  );
  test(
    'check failures are per item; exit 0 unless every check failed',
    () async {
      repo.updateReports = [
        WorkspaceUpdateReport(
          skillId: repo.current.skills.first.id,
          status: WorkspaceUpdateStatus.current,
        ),
      ];
      final mixed = await update({'check': true});
      expect(outcomes(mixed), ['upToDate', 'checkFailed', 'checkFailed']);
      expect(commandExitCode(mixed), 0);
      repo.updateReports = [];
      expect(commandExitCode(await update({'check': true})), 1);
    },
  );
  test(
    'unchecked skills are unchanged with no implicit check or update',
    () async {
      expect(outcomes(await update()), ['unchanged', 'unchanged', 'unchanged']);
      expect(repo.calls, isEmpty);
    },
  );
  test(
    'successful updates derive coordinator state from committed snapshot',
    () async {
      await available();
      final result = await update();
      expect(outcomes(result), ['succeeded', 'succeeded', 'succeeded']);
      expect(repo.calls, ['update', 'update', 'update']);
      expect(repo.skillSets, [
        for (final s in repo.current.skills) {s.id},
      ]);
      expect(updates().availableSkillIds, isEmpty);
      expect(
        updates().states.values.map((s) => s.report?.status),
        everyElement(WorkspaceUpdateStatus.current),
      );
    },
  );
  test(
    'dirty Draft blocks update even without observed availability',
    () async {
      final s = repo.current.skills.first;
      repo.current = testSnapshot(
        skills: [
          WorkspaceSkill(
            id: s.id,
            slotKey: s.slotKey,
            declaredName: s.declaredName,
            displayName: s.displayName,
            description: s.description,
            source: s.source,
            currentRevision: s.currentRevision,
            activations: [],
            draft: WorkspaceDraftSummary(
              purpose: WorkspaceDraftPurpose.customization,
              path: '/fixture/draft',
              isDirty: true,
              updatedAt: DateTime.utc(2026),
            ),
          ),
        ],
      );
      final result = await update();
      expect(result.error?.code, 'actionRequired');
      expect(result.error?.details['screen'], 'skillDetail');
      expect(repo.calls, isEmpty);
    },
  );
  test(
    'committed conflict derives resolution state and requires Updates screen',
    () async {
      await available();
      repo.conflictAfterUpdate = true;
      final result = await update();
      expect(result.error?.code, 'actionRequired');
      expect(result.error?.details['screen'], 'updates');
      expect(outcomes(result), ['failed', 'notAttempted', 'notAttempted']);
      expect(
        updates().stateOf(repo.current.skills.first.id).report?.status,
        WorkspaceUpdateStatus.resolutionRequired,
      );
    },
  );
  for (final code in [
    WorkspaceErrorCode.dirtyDraftResolutionRequired,
    WorkspaceErrorCode.externalConflict,
    WorkspaceErrorCode.updateCandidateResolutionRequired,
  ]) {
    test('repository update guard maps $code to actionRequired', () async {
      await available();
      repo.failures[1] = code;
      final result = await update();
      expect(result.error?.code, 'actionRequired');
      expect(commandExitCode(result), 5);
      expect(
        result.error?.details['screen'],
        code == WorkspaceErrorCode.dirtyDraftResolutionRequired
            ? 'skillDetail'
            : 'updates',
      );
    });
  }
  test('existing update candidate blocks without calling update', () async {
    final s = repo.current.skills.first;
    repo.current = testSnapshot(
      skills: [
        s.copyWith(
          updateCandidate: WorkspaceUpdateCandidateSummary(
            status: WorkspaceUpdateCandidateStatus.validationFailed,
            conflictPaths: [],
            createdAt: DateTime.utc(2026),
          ),
        ),
      ],
    );
    final result = await update();
    expect(result.error?.code, 'actionRequired');
    expect(result.error?.details['screen'], 'updates');
    expect(repo.calls, isEmpty);
  });
  for (final keepGoing in [false, true]) {
    test('update stop/keep-going: $keepGoing', () async {
      await available();
      repo.failures[2] = WorkspaceErrorCode.ioFailure;
      final result = await update({'keepGoing': keepGoing});
      expect(outcomes(result), [
        'succeeded',
        'failed',
        keepGoing ? 'succeeded' : 'notAttempted',
      ]);
      expect(commandExitCode(result), 3);
    });
  }
  test('update cancellation cancels task and remaining items', () async {
    await available();
    repo.blockAt = 1;
    final cancellation = CommandCancellation();
    final running = dispatcher.dispatch(
      CommandRequest(
        command: 'update',
        arguments: {'selection': SkillSelection(all: true).toJson()},
      ),
      cancellation: cancellation,
    );
    await repo.started.future;
    await cancellation.cancel();
    final result = await running;
    expect(commandExitCode(result), 130);
    expect(outcomes(result), ['cancelled', 'cancelled', 'cancelled']);
    expect(repo.calls, ['update']);
  });
  test(
    'update committed-pending derives state and keeps its distinct outcome',
    () async {
      await available();
      repo.pending.add(1);
      final result = await update();
      expect(outcomes(result), [
        'committedFinalizationPending',
        'succeeded',
        'succeeded',
      ]);
      expect(commandExitCode(result), 0);
      expect(updates().availableSkillIds, isEmpty);
    },
  );
  test('registration committed before takeover is a partial batch', () async {
    repo.occupied = true;
    final result = await install({
      'agents': ['codex'],
      'projectPath': '/fixture/new',
    });
    expect(commandExitCode(result), 3);
    expect(result.data['projectRootRegistered'], isNotNull);
    expect(result.error?.details['cause'], 'activationTargetOccupied');
  });
  test('dry update and dry check perform zero mutations and checks', () async {
    await available();
    expect(
      outcomes(await update({'dryRun': true})),
      everyElement('wouldSucceed'),
    );
    expect(
      outcomes(await update({'dryRun': true, 'check': true})),
      everyElement('wouldSucceed'),
    );
    expect(repo.calls, isEmpty);
  });
  test(
    'install JSON round trip with real CommandHostServer and client',
    () async {
      final temp = await Directory.systemTemp.createTemp('sd-install-');
      final server = CommandHostServer(
        runDirectory: '${temp.path}/.skilldeck/run',
        isWindows: Platform.isWindows,
        appVersion: () async => '1.0',
        dispatcher: dispatcher,
        executablePath: '${temp.path}/SkillDeck',
        diagnostics: AppDiagnostics.disabled(),
      );
      try {
        await server.start();
        final out = StringBuffer();
        final err = StringBuffer();
        final code = await runSkilldeck(
          ['install', 'owner/repo', '--json', '--no-launch'],
          environment: {Platform.isWindows ? 'USERPROFILE' : 'HOME': temp.path},
          isWindows: Platform.isWindows,
          cwd: temp.path,
          out: out,
          err: err,
          interrupts: const Stream.empty(),
        );
        expect(code, 0);
        final result = jsonDecode(out.toString()) as Map;
        expect(result['command'], 'install');
        expect(result['results'].single['outcome'], 'succeeded');
        expect(result['results'].single['id'], 'installed-delta');
        expect(err.toString(), isEmpty);
      } finally {
        await server.stop();
        await temp.delete(recursive: true);
      }
    },
  );
}
