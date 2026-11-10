import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/command_host/data/approval_command_handlers.dart';
import 'package:skills_manager/features/command_host/data/command_approval.dart';
import 'package:skills_manager/features/command_host/data/command_approval_registry.dart';
import 'package:skills_manager/features/command_host/data/command_host_dispatcher.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import '../../support/fake_skills_workspace_repository.dart';
import 'support/approval_presenter.dart';
import 'support/read_fixtures.dart';
import 'support/write_repository.dart';

void main() {
  late FakeSkillsWorkspaceRepository repo;
  late ApprovalPresenter presenter;
  late CommandApprovalRegistry registry;
  late CommandHostDispatcher dispatcher;
  const destination = SkillSourceInput(
    kind: WorkspaceSourceKind.git,
    locator: 'https://user:password@github.com/new/repo',
    ref: 'new-ref',
    repositorySubpath: 'skills',
  );
  void inspect(
    List<WorkspaceSourceCandidate> candidates, {
    SkillSourceInput source = destination,
  }) {
    repo.sourceInspection = WorkspaceSourceInspection(
      source: source,
      candidates: candidates,
    );
  }

  setUp(() {
    repo = FakeSkillsWorkspaceRepository(snapshot: testSnapshot());
    presenter = ApprovalPresenter();
    registry = CommandApprovalRegistry(
      presenter: presenter,
      repository: () => repo,
    );
    dispatcher = CommandHostDispatcher(
      approvalCommandHandlers(
        skillsLock: () => null,
        registry: registry,
        repository: () => repo,
        snapshot: () => repo.current,
        updates: testUpdates,
        agents: () async => [],
      ),
    );
    inspect([WriteRepository.candidate('alpha')]);
  });
  tearDown(() async {
    await registry.close();
    await repo.close();
  });
  Future<CommandResult> run([Map<String, Object?> args = const {}]) =>
      dispatcher.dispatch(
        CommandRequest(
          command: 'source replace',
          arguments: {
            'selection': SkillSelection(refs: ['alpha']).toJson(),
            'to': 'new/repo',
            'dryRun': true,
            ...args,
          },
        ),
      );

  test(
    'one Skill and one differently named candidate can migrate Slot',
    () async {
      inspect([WriteRepository.candidate('renamed')]);
      final result = await run();
      expect(result.ok, true);
      final row = result.results.single as Map;
      expect(row['slotKey'], 'alpha');
      expect(row['outcome'], 'wouldSucceed');
      expect((row['to'] as Map)['skillPath'], 'renamed');
      expect(row['candidate'], {
        'declaredName': 'renamed',
        'contentHash': 'hash-renamed',
        'fileCount': 1,
        'byteSize': 100,
      });
      expect(repo.inspectedSources, hasLength(1));
      expect(repo.replaceSourceRequests, isEmpty);
      expect(presenter.requests, isEmpty);
    },
  );

  test('a lone Skill still prefers its own Slot Key among several', () async {
    inspect([
      WriteRepository.candidate('beta'),
      WriteRepository.candidate('alpha'),
    ]);
    final result = await run();
    expect(result.ok, true);
    expect(((result.results.single as Map)['to'] as Map)['skillPath'], 'alpha');
  });

  test(
    'single selection needs --skill when no candidate shares its Slot Key',
    () async {
      inspect([
        WriteRepository.candidate('gamma'),
        WriteRepository.candidate('beta'),
      ]);
      final result = await run();
      expect(result.error?.code, 'replacementCandidateAmbiguous');
      expect(((result.results.single as Map)['error'] as Map)['details'], {
        'candidates': [
          {'name': 'gamma', 'slotKey': 'gamma'},
          {'name': 'beta', 'slotKey': 'beta'},
        ],
      });
      final chosen = await run({'skill': 'BETA'});
      expect(chosen.ok, true);
      expect(
        ((chosen.results.single as Map)['to'] as Map)['skillPath'],
        'beta',
      );
    },
  );

  test(
    'batch matches Slot Key, stops before approval, or retains failed rows',
    () async {
      inspect([WriteRepository.candidate('beta')]);
      final stopped = await run({
        'selection': SkillSelection(all: true).toJson(),
        'dryRun': false,
      });
      expect(stopped.error?.code, 'replacementCandidateNotFound');
      expect(stopped.results.cast<Map>().map((r) => r['outcome']), [
        'failed',
        'skipped',
      ]);
      expect(presenter.requests, isEmpty);
      final running = run({
        'selection': SkillSelection(all: true).toJson(),
        'dryRun': false,
        'keepGoing': true,
      });
      await presenter.presented.future;
      final subject =
          presenter.requests.single.subject as CommandApprovalReplaceSource;
      expect(subject.items.single.skillId, 'skill-2');
      expect(subject.items.single.source.skillPath, 'beta');
      expect(subject.items.single.source.ref, 'new-ref');
      expect(repo.replaceSourceRequests, isEmpty);
      presenter.decide(const CommandApprovalApproved(reviewedRevision: 7));
      final result = await running;
      expect(result.error?.code, 'partialBatch');
      expect(result.results.cast<Map>().map((r) => r['outcome']), [
        'failed',
        'succeeded',
      ]);
      expect(repo.replaceSourceRequests.single.slotKey, 'beta');
    },
  );

  test('equal Source identity leaves no request or mutation', () async {
    final old = repo.current.skills.first.source;
    inspect(
      [
        WorkspaceSourceCandidate(
          declaredName: 'alpha',
          description: '',
          slotKey: 'alpha',
          skillPath: old.skillPath,
          contentHash: 'hash',
          fileCount: 1,
          byteSize: 1,
        ),
      ],
      source: SkillSourceInput(
        kind: old.kind,
        locator: old.locator,
        ref: old.ref,
        repositorySubpath: old.repositorySubpath,
      ),
    );
    final result = await run({'dryRun': false});
    expect(result.ok, true);
    expect((result.results.single as Map)['outcome'], 'unchanged');
    expect(presenter.requests, isEmpty);
    expect(repo.replaceSourceRequests, isEmpty);
  });

  test('unchanged pre-resolved row survives approved execution', () async {
    final old = repo.current.skills.first.source;
    inspect(
      [
        WorkspaceSourceCandidate(
          declaredName: 'alpha',
          description: '',
          slotKey: 'alpha',
          skillPath: old.skillPath,
          contentHash: 'h',
          fileCount: 1,
          byteSize: 1,
        ),
        WriteRepository.candidate('beta'),
      ],
      source: SkillSourceInput(
        kind: old.kind,
        locator: old.locator,
        ref: old.ref,
        repositorySubpath: old.repositorySubpath,
      ),
    );
    final running = run({
      'selection': SkillSelection(all: true).toJson(),
      'dryRun': false,
    });
    await presenter.presented.future;
    presenter.decide(const CommandApprovalApproved(reviewedRevision: 7));
    final result = await running;
    expect(result.results.cast<Map>().map((r) => r['outcome']), [
      'unchanged',
      'succeeded',
    ]);
    expect(repo.replaceSourceRequests, hasLength(1));
  });

  test(
    'dry-run locators never expose userinfo and inspection errors are typed',
    () async {
      final result = await run();
      expect(jsonEncode(result.toJson()), isNot(contains('user:password')));
      expect((result.results.single as Map)['from'], {
        'kind': 'git',
        'locator': 'https://example.test/repo',
      });
      for (final code in [
        WorkspaceErrorCode.sourceUnavailable,
        WorkspaceErrorCode.sourceAuthenticationRequired,
        WorkspaceErrorCode.invalidSource,
      ]) {
        repo.inspectSourceError = WorkspaceException(
          code: code,
          operation: WorkspaceOperationKind.inspectSource,
          diagnostic: 'sensitive text',
        );
        final failed = await run();
        expect(failed.error?.code, code.name);
        expect(jsonEncode(failed.toJson()), isNot(contains('sensitive')));
      }
      expect(presenter.requests, isEmpty);
      expect(repo.replaceSourceRequests, isEmpty);
    },
  );

  test(
    'new ref overrides parsed ref and never defaults to current ref',
    () async {
      await run({'to': 'new/repo#embedded', 'ref': 'explicit'});
      expect(repo.inspectedSources.last.ref, 'explicit');
      await run({'to': 'new/repo'});
      expect(repo.inspectedSources.last.ref, isNull);
    },
  );

  test('ambiguous candidate details are bounded', () async {
    inspect([
      for (var i = 0; i < 205; i++) WriteRepository.candidate('skill-$i'),
    ]);
    final result = await run();
    expect((result.error?.details['candidates'] as List), hasLength(200));
  });

  test(
    'empty selection succeeds; multi-selection --skill and bypasses fail usage',
    () async {
      final empty = await run({
        'selection': SkillSelection(tags: ['missing']).toJson(),
      });
      expect(empty.ok, true);
      expect(repo.inspectedSources, isEmpty);
      for (final args in [
        {'selection': SkillSelection(all: true).toJson(), 'skill': 'alpha'},
        {'yes': true},
        {'ref': 1},
        {'skill': ''},
        {'approvalTimeout': 601},
        {'keepGoing': 'yes'},
        {'to': ''},
      ]) {
        expect((await run(args)).error?.code, 'usage');
      }
      expect(repo.inspectedSources, isEmpty);
      expect(presenter.requests, isEmpty);
    },
  );
}
