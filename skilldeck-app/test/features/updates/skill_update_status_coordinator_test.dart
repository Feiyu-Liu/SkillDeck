import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/data/update_sweep_store.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';

import '../../support/fake_skills_workspace_repository.dart';

void main() {
  test('a completed sweep records its timestamp and runs once', () async {
    final store = InMemoryUpdateSweepStore();
    final workspace = _workspace(['alpha', 'beta']);
    final container = _container(workspace, store);
    addTearDown(container.dispose);
    final coordinator = container.read(skillUpdateStatusProvider.notifier);

    await coordinator.startupSweep();

    expect(workspace.checkUpdatesCalls, 2);
    expect(await store.readLastSweepAt(), isNotNull);
    // A second startup request in the same session is a no-op.
    await coordinator.startupSweep();
    expect(workspace.checkUpdatesCalls, 2);
  });

  test(
    'a restart inside the TTL sweeps nothing and keeps state empty',
    () async {
      final store = InMemoryUpdateSweepStore(
        DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      );
      final workspace = _workspace(['alpha']);
      final container = _container(workspace, store);
      addTearDown(container.dispose);

      await container.read(skillUpdateStatusProvider.notifier).startupSweep();

      expect(workspace.checkUpdatesCalls, 0);
      // Reports are not persisted, so an unexpired TTL still starts unchecked.
      expect(
        container.read(skillUpdateStatusProvider).stateOf(_id('alpha')),
        isA<SkillUpdateNotChecked>(),
      );
    },
  );

  test('a sweep runs once the TTL has expired', () async {
    final store = InMemoryUpdateSweepStore(
      DateTime.now().toUtc().subtract(const Duration(hours: 25)),
    );
    final workspace = _workspace(['alpha']);
    final container = _container(workspace, store);
    addTearDown(container.dispose);

    await container.read(skillUpdateStatusProvider.notifier).startupSweep();

    expect(workspace.checkUpdatesCalls, 1);
  });

  test('a duplicate request attaches to the check already in flight', () async {
    final gate = Completer<WorkspaceCompletion<List<WorkspaceUpdateReport>>>();
    final workspace = _workspace(['alpha'])
      ..checkUpdatesTaskBuilder = (_) => _task(completed: gate.future);
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);
    final coordinator = container.read(skillUpdateStatusProvider.notifier);

    final first = coordinator.checkSkill(_id('alpha'));
    final second = coordinator.checkSkill(_id('alpha'));
    await Future<void>.delayed(Duration.zero);

    expect(workspace.checkUpdatesCalls, 1);
    gate.complete(
      WorkspaceCompleted(
        value: [
          WorkspaceUpdateReport(
            skillId: _id('alpha'),
            status: WorkspaceUpdateStatus.current,
          ),
        ],
      ),
    );

    // Both requesters receive the same settled outcome.
    expect(await first, isA<SkillUpdateChecked>());
    expect(await second, isA<SkillUpdateChecked>());
    expect(workspace.checkUpdatesCalls, 1);
  });

  test('a manual request during a sweep never exceeds the bound', () async {
    final gates =
        <Completer<WorkspaceCompletion<List<WorkspaceUpdateReport>>>>[];
    var inFlight = 0;
    var peak = 0;
    final workspace = _workspace([
      for (var index = 0; index < 12; index++) 'skill-$index',
    ]);
    workspace.checkUpdatesTaskBuilder = (_) {
      inFlight += 1;
      peak = peak > inFlight ? peak : inFlight;
      final gate =
          Completer<WorkspaceCompletion<List<WorkspaceUpdateReport>>>();
      gates.add(gate);
      return _task(completed: gate.future.whenComplete(() => inFlight -= 1));
    };
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);
    final coordinator = container.read(skillUpdateStatusProvider.notifier);

    final sweep = coordinator.sweep();
    await Future<void>.delayed(Duration.zero);
    // The background sweep alone stays at the conservative bound.
    expect(inFlight, skillUpdateStartupConcurrency);

    unawaited(coordinator.checkSkill(_id('skill-11')));
    await Future<void>.delayed(Duration.zero);
    expect(inFlight, lessThanOrEqualTo(skillUpdateManualConcurrency));
    expect(inFlight, greaterThan(skillUpdateStartupConcurrency));

    for (final gate in List.of(gates)) {
      if (!gate.isCompleted) {
        gate.complete(
          WorkspaceCompleted(value: const <WorkspaceUpdateReport>[]),
        );
      }
      await Future<void>.delayed(Duration.zero);
      for (final next in List.of(gates)) {
        if (!next.isCompleted) {
          next.complete(
            WorkspaceCompleted(value: const <WorkspaceUpdateReport>[]),
          );
        }
      }
    }
    await sweep;
    expect(peak, lessThanOrEqualTo(skillUpdateManualConcurrency));
  });

  test('concurrent startup requests attach to one sweep', () async {
    final workspace = _workspace(['alpha', 'beta']);
    final container = _container(workspace);
    addTearDown(container.dispose);
    final coordinator = container.read(skillUpdateStatusProvider.notifier);

    await Future.wait([coordinator.startupSweep(), coordinator.startupSweep()]);

    expect(workspace.checkUpdatesCalls, 2);
    expect(container.read(skillUpdateStatusProvider).sweeping, isFalse);
  });

  test('Skills sharing a Git repository and ref share one request', () async {
    final workspace = _workspace(
      ['one', 'two', 'next', 'other', 'local'],
      sources: {
        'one': _git('repo'),
        'two': _git('repo'),
        'next': _git('repo', ref: 'next'),
        'other': _git('other'),
      },
    );
    final container = _container(workspace);
    addTearDown(container.dispose);

    await container.read(skillUpdateStatusProvider.notifier).sweep();

    expect(
      workspace.checkUpdatesRequests,
      unorderedEquals([
        {_id('one'), _id('two')},
        {_id('next')},
        {_id('other')},
        {_id('local')},
      ]),
    );
    expect(
      container.read(skillUpdateStatusProvider).stateOf(_id('two')),
      isA<SkillUpdateChecked>(),
    );
  });

  test('one repository settles while another is still checking', () async {
    final gates =
        <
          WorkspaceSkillId,
          Completer<WorkspaceCompletion<List<WorkspaceUpdateReport>>>
        >{};
    final workspace =
        _workspace(
            ['one', 'two', 'other'],
            sources: {
              'one': _git('repo'),
              'two': _git('repo'),
              'other': _git('other'),
            },
          )
          ..checkUpdatesTaskBuilder = (skillIds) {
            final gate =
                Completer<WorkspaceCompletion<List<WorkspaceUpdateReport>>>();
            for (final skillId in skillIds!) {
              gates[skillId] = gate;
            }
            return _task(completed: gate.future);
          };
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);
    final coordinator = container.read(skillUpdateStatusProvider.notifier);

    final sweep = coordinator.sweep();
    await Future<void>.delayed(Duration.zero);
    gates[_id('one')]!.complete(_current([_id('one'), _id('two')]));
    await Future<void>.delayed(Duration.zero);

    final status = container.read(skillUpdateStatusProvider);
    expect(status.stateOf(_id('one')), isA<SkillUpdateChecked>());
    expect(status.stateOf(_id('two')), isA<SkillUpdateChecked>());
    expect(status.stateOf(_id('other')), isA<SkillUpdateChecking>());
    expect(status.sweepCompleted, 2);

    gates[_id('other')]!.complete(_current([_id('other')]));
    await sweep;
  });

  test('a failed repository request fails only its own Skills', () async {
    final workspace =
        _workspace(
            ['one', 'two', 'other'],
            sources: {
              'one': _git('repo'),
              'two': _git('repo'),
              'other': _git('other'),
            },
          )
          ..checkUpdatesTaskBuilder = (skillIds) =>
              skillIds!.contains(_id('other'))
              ? failedWorkspaceTask<List<WorkspaceUpdateReport>>(
                  kind: WorkspaceOperationKind.checkUpdates,
                  error: WorkspaceException(
                    code: WorkspaceErrorCode.sourceUnavailable,
                    operation: WorkspaceOperationKind.checkUpdates,
                  ),
                )
              : _task(completed: Future.value(_current(skillIds)));
    final container = _container(workspace);
    addTearDown(container.dispose);

    await container.read(skillUpdateStatusProvider.notifier).sweep();

    final status = container.read(skillUpdateStatusProvider);
    expect(status.stateOf(_id('one')), isA<SkillUpdateChecked>());
    expect(status.stateOf(_id('two')), isA<SkillUpdateChecked>());
    expect(status.stateOf(_id('other')), isA<SkillUpdateCheckFailed>());
  });

  test('a manual request starts its whole repository at once', () async {
    final gates =
        <Completer<WorkspaceCompletion<List<WorkspaceUpdateReport>>>>[];
    final locals = [for (var index = 0; index < 8; index++) 'local-$index'];
    final workspace =
        _workspace(
            [...locals, 'one', 'two'],
            sources: {'one': _git('repo'), 'two': _git('repo')},
          )
          ..checkUpdatesTaskBuilder = (skillIds) {
            final gate =
                Completer<WorkspaceCompletion<List<WorkspaceUpdateReport>>>();
            gates.add(gate);
            return _task(
              completed: gate.future.then((_) => _current(skillIds!)),
            );
          };
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);
    final coordinator = container.read(skillUpdateStatusProvider.notifier);

    final sweep = coordinator.sweep();
    await Future<void>.delayed(Duration.zero);
    expect(workspace.checkUpdatesCalls, skillUpdateStartupConcurrency);

    final manual = coordinator.checkSkill(_id('two'));
    await Future<void>.delayed(Duration.zero);
    expect(workspace.checkUpdatesRequests[skillUpdateStartupConcurrency], {
      _id('two'),
      _id('one'),
    });

    while (gates.any((gate) => !gate.isCompleted)) {
      for (final gate in List.of(gates)) {
        if (!gate.isCompleted) gate.complete(_current(const []));
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect(await manual, isA<SkillUpdateChecked>());
    await sweep;
    expect(
      workspace.checkUpdatesRequests.where(
        (request) => request!.contains(_id('one')),
      ),
      hasLength(1),
    );
  });

  test('a cancelled sweep neither resets the TTL nor counts as done', () async {
    final gate = Completer<WorkspaceCompletion<List<WorkspaceUpdateReport>>>();
    final store = InMemoryUpdateSweepStore();
    final workspace = _workspace(['alpha'])
      ..checkUpdatesTaskBuilder = (_) => _task(completed: gate.future);
    final container = _container(workspace, store);
    addTearDown(container.dispose);
    final coordinator = container.read(skillUpdateStatusProvider.notifier);

    final sweep = coordinator.sweep();
    await Future<void>.delayed(Duration.zero);
    await coordinator.cancelAll();
    gate.complete(WorkspaceCompleted(value: const <WorkspaceUpdateReport>[]));
    await sweep;

    expect(await store.readLastSweepAt(), isNull);
    expect(container.read(skillUpdateStatusProvider).sweptThisSession, isFalse);
  });

  test('a basis change during a check discards the obsolete report', () async {
    final gate = Completer<WorkspaceCompletion<List<WorkspaceUpdateReport>>>();
    final workspace = _workspace(['alpha'])
      ..checkUpdatesTaskBuilder = (_) => _task(completed: gate.future);
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);
    final coordinator = container.read(skillUpdateStatusProvider.notifier);

    final pending = coordinator.checkSkill(_id('alpha'));
    await Future<void>.delayed(Duration.zero);

    // A Source Replacement lands while the check is still running.
    workspace.publish(
      _snapshot(['alpha'], revision: 2, locatorSuffix: '-replaced'),
    );
    await Future<void>.delayed(Duration.zero);

    gate.complete(
      WorkspaceCompleted(
        value: [
          WorkspaceUpdateReport(
            skillId: _id('alpha'),
            status: WorkspaceUpdateStatus.updateAvailable,
          ),
        ],
      ),
    );
    await pending;

    expect(
      container.read(skillUpdateStatusProvider).stateOf(_id('alpha')),
      isA<SkillUpdateNotChecked>(),
    );
  });

  test('a removed Skill is dropped from shared state', () async {
    final workspace = _workspace(['alpha', 'beta']);
    final container = _container(workspace);
    addTearDown(container.dispose);
    final coordinator = container.read(skillUpdateStatusProvider.notifier);
    await coordinator.sweep();
    expect(
      container.read(skillUpdateStatusProvider).states.keys,
      containsAll([_id('alpha'), _id('beta')]),
    );

    workspace.publish(_snapshot(['alpha'], revision: 2));
    await Future<void>.delayed(Duration.zero);

    final states = container.read(skillUpdateStatusProvider).states;
    expect(states.containsKey(_id('beta')), isFalse);
    expect(states.containsKey(_id('alpha')), isTrue);
  });

  test('a changed revision invalidates the stored report', () async {
    final workspace = _workspace(['alpha']);
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(skillUpdateStatusProvider.notifier).sweep();
    expect(
      container.read(skillUpdateStatusProvider).stateOf(_id('alpha')),
      isA<SkillUpdateChecked>(),
    );

    workspace.publish(
      _snapshot(['alpha'], revision: 2, contentHashSuffix: '-next'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(skillUpdateStatusProvider).stateOf(_id('alpha')),
      isA<SkillUpdateNotChecked>(),
    );
  });

  test('a clean Update resolves to current', () async {
    final workspace = _workspace(['alpha']);
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);

    container
        .read(skillUpdateStatusProvider.notifier)
        .deriveAfterUpdate(_id('alpha'));

    expect(
      container
          .read(skillUpdateStatusProvider)
          .stateOf(_id('alpha'))
          .report
          ?.status,
      WorkspaceUpdateStatus.current,
    );
  });

  test('a conflicting Update resolves to resolutionRequired', () async {
    // A merge conflict is a *successful* mutation that commits an Update
    // Candidate Session, so the post-Update state must be derived from the
    // committed Snapshot rather than assumed to be current.
    final workspace = _workspace(['alpha'], conflicted: true);
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);

    container
        .read(skillUpdateStatusProvider.notifier)
        .deriveAfterUpdate(_id('alpha'));

    expect(
      container
          .read(skillUpdateStatusProvider)
          .stateOf(_id('alpha'))
          .report
          ?.status,
      WorkspaceUpdateStatus.resolutionRequired,
    );
  });

  test('resolution state is derived without a network round trip', () async {
    final workspace = _workspace(['alpha'], conflicted: true);
    final container = _container(workspace);
    addTearDown(container.dispose);

    await container.read(skillUpdateStatusProvider.notifier).sweep();

    expect(workspace.checkUpdatesCalls, 0);
    expect(
      container
          .read(skillUpdateStatusProvider)
          .stateOf(_id('alpha'))
          .report
          ?.status,
      WorkspaceUpdateStatus.resolutionRequired,
    );
  });

  test('restores a persisted report after a simulated app restart', () async {
    final cache = InMemorySkillsUpdateCheckStore();
    final sweepStore = InMemoryUpdateSweepStore();
    final workspace = _workspace(['alpha']);
    final first = _container(workspace, sweepStore, cache);
    await first.read(skillUpdateStatusProvider.notifier).sweep();
    first.dispose();

    final restarted = _container(workspace, sweepStore, cache);
    addTearDown(restarted.dispose);
    await restarted
        .read(skillUpdateStatusProvider.notifier)
        .restorePersistedState();

    expect(
      restarted
          .read(skillUpdateStatusProvider)
          .stateOf(_id('alpha'))
          .report
          ?.status,
      WorkspaceUpdateStatus.current,
    );
    expect(workspace.checkUpdatesCalls, 1);
  });

  test('drops a persisted report when its basis no longer matches', () async {
    final cache = InMemorySkillsUpdateCheckStore();
    await cache.upsertUpdateCache(
      WorkspaceUpdateCacheRecord(
        skillId: _id('alpha'),
        basisFingerprint: 'obsolete-basis',
        report: WorkspaceUpdateReport(
          skillId: _id('alpha'),
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
        checkedAt: DateTime.utc(2026),
      ),
    );
    final workspace = _workspace(['alpha']);
    final container = _container(workspace, null, cache);
    addTearDown(container.dispose);

    await container
        .read(skillUpdateStatusProvider.notifier)
        .restorePersistedState();

    expect(
      container.read(skillUpdateStatusProvider).stateOf(_id('alpha')),
      isA<SkillUpdateNotChecked>(),
    );
    expect((await cache.readUpdateCache()).records, isEmpty);
  });
}

ProviderContainer _container(
  FakeSkillsWorkspaceRepository workspace, [
  UpdateSweepStore? store,
  SkillsUpdateCheckStore? cache,
]) => ProviderContainer(
  overrides: [
    skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
    skillUpdateSweepStoreProvider.overrideWithValue(
      store ?? InMemoryUpdateSweepStore(),
    ),
    skillsUpdateCheckStoreProvider.overrideWithValue(
      cache ?? InMemorySkillsUpdateCheckStore(),
    ),
  ],
);

FakeSkillsWorkspaceRepository _workspace(
  List<String> slotKeys, {
  bool conflicted = false,
  Map<String, SkillSourceProvenance> sources = const {},
}) => FakeSkillsWorkspaceRepository(
  snapshot: _snapshot(slotKeys, conflicted: conflicted, sources: sources),
  updateReports: [
    for (final slotKey in slotKeys)
      WorkspaceUpdateReport(
        skillId: _id(slotKey),
        status: WorkspaceUpdateStatus.current,
      ),
  ],
);

SkillsWorkspaceSnapshot _snapshot(
  List<String> slotKeys, {
  int revision = 1,
  String locatorSuffix = '',
  String contentHashSuffix = '',
  bool conflicted = false,
  Map<String, SkillSourceProvenance> sources = const {},
}) => SkillsWorkspaceSnapshot(
  revision: revision,
  projectRoots: const [],
  skills: [
    for (final slotKey in slotKeys)
      WorkspaceSkill(
        id: _id(slotKey),
        slotKey: slotKey,
        declaredName: slotKey,
        displayName: slotKey,
        description: 'Test skill',
        source:
            sources[slotKey] ??
            SkillSourceProvenance(
              kind: WorkspaceSourceKind.local,
              locator: '/skills/$slotKey$locatorSuffix',
            ),
        currentRevision: SkillRevision(
          contentHash: 'hash-$slotKey$contentHashSuffix',
          fileCount: 1,
          byteSize: 1,
          acquiredAt: DateTime.utc(2026),
        ),
        activations: const [],
        updateCandidate: conflicted
            ? WorkspaceUpdateCandidateSummary(
                status: WorkspaceUpdateCandidateStatus.conflicted,
                conflictPaths: const ['SKILL.md'],
                createdAt: DateTime.utc(2026),
              )
            : null,
      ),
  ],
);

WorkspaceTask<List<WorkspaceUpdateReport>> _task({
  required Future<WorkspaceCompletion<List<WorkspaceUpdateReport>>> completed,
}) => WorkspaceTask(
  current: WorkspaceOperationProgress(
    operationId: 'check',
    kind: WorkspaceOperationKind.checkUpdates,
    phase: WorkspaceOperationPhase.inspecting,
  ),
  states: const Stream.empty(),
  completed: completed,
  cancel: () async {},
);

WorkspaceSkillId _id(String slotKey) => WorkspaceSkillId(slotKey);

SkillSourceProvenance _git(String repository, {String? ref = 'main'}) =>
    SkillSourceProvenance(
      kind: WorkspaceSourceKind.git,
      locator: 'https://example.test/$repository.git',
      ref: ref,
    );

WorkspaceCompletion<List<WorkspaceUpdateReport>> _current(
  Iterable<WorkspaceSkillId> skillIds,
) => WorkspaceCompleted(
  value: [
    for (final skillId in skillIds)
      WorkspaceUpdateReport(
        skillId: skillId,
        status: WorkspaceUpdateStatus.current,
      ),
  ],
);
