import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/command_host/data/approval_command_handlers.dart';
import 'package:skills_manager/features/command_host/data/command_approval.dart';
import 'package:skills_manager/features/command_host/data/command_approval_registry.dart';
import 'package:skills_manager/features/command_host/data/command_host_dispatcher.dart';
import 'package:skills_manager/features/command_host/data/skills_lock_reader.dart';
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
  late _Lock lock;
  late SkillsLockReader? reader;
  const first = 'https://github.com/org/first';
  const second = 'https://github.com/org/second';

  WorkspaceSkill adopted(String slot) {
    final base = testSkill(id: slot, slot: slot);
    return WorkspaceSkill(
      id: base.id,
      slotKey: slot,
      declaredName: slot,
      displayName: slot,
      description: '',
      source: SkillSourceProvenance(
        kind: WorkspaceSourceKind.adoptedSnapshot,
        locator: '/temporary/adopted/$slot',
      ),
      currentRevision: base.currentRevision,
      activations: [],
    );
  }

  void inspect(String locator, List<String> slots) {
    repo.sourceInspections[locator] = WorkspaceSourceInspection(
      source: SkillSourceInput(kind: WorkspaceSourceKind.git, locator: locator),
      candidates: [
        for (final slot in slots)
          WriteRepository.candidate(slot, skillPath: 'skills/$slot'),
      ],
    );
  }

  setUp(() {
    repo = FakeSkillsWorkspaceRepository(
      snapshot: testSnapshot(
        skills: [
          adopted('alpha'),
          adopted('beta'),
          adopted('gamma'),
          testSkill(id: 'git'),
        ],
      ),
    );
    lock = _Lock({
      'alpha': (
        sourceUrl: first,
        skillPath: 'skills/alpha/SKILL.md',
        sourceType: 'github',
      ),
      'beta': (
        sourceUrl: second,
        skillPath: 'skills/beta/SKILL.md',
        sourceType: 'github',
      ),
      'gamma': (
        sourceUrl: first,
        skillPath: 'skills/gamma/SKILL.md',
        sourceType: 'github',
      ),
    });
    reader = lock;
    presenter = ApprovalPresenter();
    registry = CommandApprovalRegistry(
      presenter: presenter,
      repository: () => repo,
    );
    dispatcher = CommandHostDispatcher(
      approvalCommandHandlers(
        skillsLock: () => reader,
        registry: registry,
        repository: () => repo,
        snapshot: () => repo.current,
        updates: testUpdates,
        agents: () async => [],
      ),
    );
    inspect(first, ['alpha', 'gamma']);
    inspect(second, ['beta']);
  });
  tearDown(() async {
    await registry.close();
    await repo.close();
  });
  Future<CommandResult> run([Map<String, Object?> args = const {}]) =>
      dispatcher.dispatch(
        CommandRequest(
          command: 'source relink',
          arguments: {'fromSkillsLock': true, 'dryRun': true, ...args},
        ),
      );
  List<Map> rows(CommandResult result) => result.results.cast<Map>();

  test(
    'default selects adopted only, groups first-seen Sources, inspects once',
    () async {
      final result = await run();
      expect(result.ok, true);
      expect(rows(result).map((r) => r['id']), ['alpha', 'gamma', 'beta']);
      expect(
        rows(result).map((r) => r['outcome']),
        everyElement('wouldSucceed'),
      );
      expect(repo.inspectedSources.map((s) => s.locator), [first, second]);
      expect(result.data['sources'], [first, second]);
      expect(lock.reads, 1);
      expect(rows(result).first['lock'], {
        'source': first,
        'skillPath': 'skills/alpha/SKILL.md',
      });
      expect(presenter.requests, isEmpty);
      expect(repo.replaceSourceRequests, isEmpty);
    },
  );

  test(
    'explicit non-adopted selection is skipped and does not stop planning',
    () async {
      final result = await run({
        'selection': SkillSelection(refs: ['git', 'beta']).toJson(),
        'keepGoing': false,
      });
      expect(rows(result).map((r) => r['outcome']), [
        'skipped',
        'wouldSucceed',
      ]);
      expect((rows(result).first['reason'] as Map)['code'], 'notAdopted');
      expect(rows(result).first.containsKey('error'), isFalse);
      expect(repo.inspectedSources.single.locator, second);
    },
  );

  test(
    'a bulk relink skips Skills without a usable hint and still succeeds',
    () async {
      lock.entries.remove('alpha');
      lock.entries['beta'] = (
        sourceUrl: second,
        skillPath: 'SKILL.md',
        sourceType: 'mintlify',
      );
      final result = await run();
      expect(rows(result).map((r) => r['outcome']), [
        'skipped',
        'skipped',
        'wouldSucceed',
      ]);
      expect((rows(result)[0]['reason'] as Map)['code'], 'lockEntryMissing');
      expect(
        (rows(result)[1]['reason'] as Map)['code'],
        'lockSourceUnsupported',
      );
      expect(result.ok, isTrue, reason: 'skips are not failures');
      expect(result.error, isNull);
      expect(repo.inspectedSources.single.locator, first);
    },
  );

  test('a Skill the user named still fails when it has no hint', () async {
    lock.entries.remove('alpha');
    final result = await run({
      'selection': SkillSelection(refs: ['alpha', 'gamma']).toJson(),
    });
    expect(rows(result).map((r) => r['outcome']), ['failed', 'wouldSucceed']);
    expect((rows(result).first['error'] as Map)['code'], 'lockEntryMissing');
    expect(result.ok, isFalse);
  });

  test(
    'inspection errors affect only that group, with no raw diagnostics',
    () async {
      // A network failure is a real failure; a repository whose duplicate
      // Skill names cannot be inspected is a known, skippable case.
      for (final (code, outcome, key) in [
        (WorkspaceErrorCode.sourceUnavailable, 'failed', 'error'),
        (WorkspaceErrorCode.duplicateSkillSlot, 'skipped', 'reason'),
      ]) {
        repo.inspectSourceErrors[first] = WorkspaceException(
          code: code,
          operation: WorkspaceOperationKind.inspectSource,
          diagnostic: 'private diagnostic',
        );
        final result = await run();
        expect(rows(result).map((r) => r['outcome']), [
          outcome,
          outcome,
          'wouldSucceed',
        ]);
        expect(
          rows(result).take(2).map((r) => (r[key] as Map)['code']),
          everyElement(code.name),
        );
        expect(
          jsonEncode(result.toJson()),
          isNot(contains('private diagnostic')),
        );
      }
    },
  );

  test(
    'cancellation propagates without inspecting later repositories',
    () async {
      repo.inspectSourceErrors[first] = WorkspaceException(
        code: WorkspaceErrorCode.operationCancelled,
        operation: WorkspaceOperationKind.inspectSource,
      );
      expect((await run()).error?.code, 'operationCancelled');
      expect(repo.inspectedSources, hasLength(1));
    },
  );

  test('a Skill at the repository root matches the empty path', () async {
    lock.entries['beta'] = (
      sourceUrl: second,
      skillPath: 'SKILL.md',
      sourceType: 'github',
    );
    repo.sourceInspections[second] = WorkspaceSourceInspection(
      source: const SkillSourceInput(
        kind: WorkspaceSourceKind.git,
        locator: second,
      ),
      candidates: [WriteRepository.candidate('beta', skillPath: '')],
    );
    final result = await run();
    final beta = rows(result).singleWhere((r) => r['id'] == 'beta');
    expect(beta['outcome'], 'wouldSucceed');
    expect((beta['to'] as Map)['skillPath'], '');
  });

  test('path mismatch never falls back to a same-name candidate', () async {
    lock.entries['alpha'] = (
      sourceUrl: first,
      skillPath: 'other/alpha/SKILL.md',
      sourceType: 'github',
    );
    final result = await run();
    expect(rows(result).first['outcome'], 'skipped');
    expect(
      (rows(result).first['reason'] as Map)['code'],
      'replacementCandidateNotFound',
    );
    expect((rows(result).first['reason'] as Map)['details'], {
      'lockSkillPath': 'other/alpha/SKILL.md',
    });
    expect(rows(result)[1]['outcome'], 'wouldSucceed');
  });

  test(
    'no-keep-going skips later rows and Sources without an approval',
    () async {
      repo.inspectSourceErrors[first] = WorkspaceException(
        code: WorkspaceErrorCode.sourceUnavailable,
        operation: WorkspaceOperationKind.inspectSource,
      );
      final result = await run({'keepGoing': false, 'dryRun': false});
      expect(rows(result).map((r) => r['outcome']), [
        'failed',
        'skipped',
        'skipped',
      ]);
      expect(repo.inspectedSources, hasLength(1));
      expect(presenter.requests, isEmpty);
    },
  );

  test(
    'userinfo is stripped before inspection, grouping, and all result rows',
    () async {
      lock.entries['alpha'] = (
        sourceUrl: 'https://user:secret@github.com/org/first',
        skillPath: 'skills/alpha/SKILL.md',
        sourceType: 'github',
      );
      final result = await run();
      expect(repo.inspectedSources.map((s) => s.locator), [first, second]);
      expect(jsonEncode(result.toJson()), isNot(contains('user:secret')));
    },
  );

  test('one approval executes mixed Sources in grouped order and keeps going by default', () async {
    repo.replaceSourceError = WorkspaceException(
      code: WorkspaceErrorCode.sourceUnavailable,
      operation: WorkspaceOperationKind.replaceSource,
    );
    final running = run({'dryRun': false});
    await presenter.presented.future;
    final subject =
        presenter.requests.single.subject as CommandApprovalReplaceSource;
    expect(subject.items.map((i) => i.skillId), ['alpha', 'gamma', 'beta']);
    expect(subject.items.map((i) => i.source.locator), [first, first, second]);
    presenter.decide(const CommandApprovalApproved(reviewedRevision: 7));
    final result = await running;
    expect(repo.replaceSourceRequests, hasLength(3));
    expect(result.command, 'source relink');
    expect(result.data['sources'], [first, second]);
  });

  test('requires explicit lock source and validates arguments', () async {
    for (final args in [
      {'fromSkillsLock': null},
      {'fromSkillsLock': false},
      {'to': first},
      {'keepGoing': 'true'},
      {'approvalTimeout': 601},
      {'wait': -1},
    ]) {
      expect((await run(args)).error?.code, 'usage');
    }
    expect(
      (await dispatcher.dispatch(CommandRequest(command: 'source relink')))
          .error
          ?.code,
      'usage',
    );
    expect(lock.reads, 0);
    reader = null;
    expect((await run()).error?.code, 'lockUnavailable');
    expect(repo.inspectedSources, isEmpty);
  });
}

final class _Lock implements SkillsLockReader {
  _Lock(this.entries);
  final Map<String, SkillsLockEntry> entries;
  int reads = 0;
  @override
  Future<Map<String, SkillsLockEntry>> read() async {
    reads++;
    return entries;
  }
}
