import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';

import '../../support/fake_skills_workspace_repository.dart';
import '../../support/recording_app_analytics.dart';

void main() {
  test('opens once and projects the first Workspace Snapshot', () async {
    final repository = FakeSkillsWorkspaceRepository(
      snapshot: _snapshot(revision: 7, favorite: true),
    );
    final analytics = RecordingAppAnalytics();
    final container = _container(repository, analytics: analytics);
    addTearDown(container.dispose);

    final snapshot = await container.read(workspaceSnapshotProvider.future);

    expect(repository.openCalls, 1);
    expect(analytics.events.single.action, 'workspace_bootstrap');
    expect(analytics.events.single.name, 'success');
    expect(snapshot.revision, 7);
    expect(
      container.read(workspaceInstalledSkillCatalogProvider).value?.revision,
      7,
    );
    expect(
      container.read(workspaceFavoriteSkillsProvider).value?.single.id.value,
      'managed-7',
    );
    expect(
      container
          .read(workspaceSkillByIdProvider(WorkspaceSkillId('managed-7')))
          .value
          ?.slotKey,
      'skill-7',
    );
    expect(
      container
          .read(workspaceSkillByIdProvider(WorkspaceSkillId('missing')))
          .value,
      isNull,
    );
  });

  test('de-duplicates same-revision publications', () async {
    final repository = FakeSkillsWorkspaceRepository(
      snapshot: _snapshot(revision: 1),
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);
    await _settle();

    final revisions = <int>[];
    final subscription = container.listen(workspaceSnapshotProvider, (
      _,
      value,
    ) {
      value.whenData((snapshot) => revisions.add(snapshot.revision));
    });
    addTearDown(subscription.close);

    repository.publish(_snapshot(revision: 1));
    repository.publish(_snapshot(revision: 2));
    await _settle();

    expect(revisions, [2]);
    expect(container.read(workspaceSnapshotProvider).value?.revision, 2);
  });

  test('retains one newer Snapshot published while open is pending', () async {
    final open = Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
    final repository = FakeSkillsWorkspaceRepository(
      snapshot: _snapshot(revision: 1),
    )..openCompleter = open;
    final container = _container(repository);
    addTearDown(container.dispose);
    final revisions = <int>[];
    final subscription = container.listen(workspaceSnapshotProvider, (
      _,
      value,
    ) {
      value.whenData((snapshot) => revisions.add(snapshot.revision));
    });
    addTearDown(subscription.close);

    final opened = container.read(workspaceSnapshotProvider.future);
    await _settle();
    expect(repository.openCalls, 1);

    repository.publish(_snapshot(revision: 2));
    repository.publish(_snapshot(revision: 2));
    open.complete(WorkspaceCompleted(value: _snapshot(revision: 1)));

    expect((await opened).revision, 2);
    await _settle();
    expect(revisions, [2]);
    expect(container.read(workspaceSnapshotProvider).value?.revision, 2);
  });

  test(
    'same-revision integrity updates reach the selected Skill projection',
    () async {
      final repository = FakeSkillsWorkspaceRepository(
        snapshot: _snapshot(revision: 1),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(workspaceSnapshotProvider.future);
      await _settle();
      final id = WorkspaceSkillId('managed-1');
      final statuses = <WorkspaceSkillIntegrityStatus>[];
      final listener = container.listen(workspaceSkillByIdProvider(id), (
        _,
        next,
      ) {
        if (next.value case final skill?) statuses.add(skill.integrity);
      });
      addTearDown(listener.close);
      final expected = [
        WorkspaceSkillIntegrityStatus.validating,
        WorkspaceSkillIntegrityStatus.driftPending,
        WorkspaceSkillIntegrityStatus.repairFailed,
        WorkspaceSkillIntegrityStatus.healthy,
      ];
      for (final status in expected) {
        repository.publishIntegrity(skills: {id: status});
        repository.publishIntegrity(skills: {id: status});
        await _settle();
        expect(
          container.read(workspaceSkillByIdProvider(id)).value?.integrity,
          status,
        );
        expect(container.read(workspaceSnapshotProvider).value?.revision, 1);
      }
      expect(statuses, expected);
    },
  );

  test('workspace integrity changes at the same revision but older revisions stay ignored', () async {
    final repository = FakeSkillsWorkspaceRepository(
      snapshot: _snapshot(revision: 2),
    );
    final container = _container(repository);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);
    await _settle();
    repository.publishIntegrity(integrity: WorkspaceIntegrityStatus.recovered);
    await _settle();
    expect(
      container.read(workspaceSnapshotProvider).value?.integrity,
      WorkspaceIntegrityStatus.recovered,
    );
    repository.publish(
      _snapshot(revision: 1, integrity: WorkspaceIntegrityStatus.corrupt),
    );
    await _settle();
    final accepted = container.read(workspaceSnapshotProvider).value!;
    expect(accepted.revision, 2);
    expect(accepted.integrity, WorkspaceIntegrityStatus.recovered);
  });

  test(
    'integrity equality uses Skill identity rather than list order',
    () async {
      final first = _snapshot(revision: 1);
      final other = _snapshot(revision: 2).skills.single;
      final repository = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 1,
          projectRoots: const [],
          skills: [first.skills.single, other],
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      await container.read(workspaceSnapshotProvider.future);
      await _settle();
      var updates = 0;
      final listener = container.listen(
        workspaceSnapshotProvider,
        (_, _) => updates++,
      );
      addTearDown(listener.close);
      repository.publish(
        SkillsWorkspaceSnapshot(
          revision: 1,
          projectRoots: const [],
          skills: [other, first.skills.single],
        ),
      );
      await _settle();
      expect(updates, 0);
    },
  );

  test(
    'a captured open result cannot replace newer same-revision integrity',
    () async {
      final captured = _snapshot(revision: 1);
      final open = Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
      final repository = FakeSkillsWorkspaceRepository(snapshot: captured)
        ..openCompleter = open;
      final container = _container(repository);
      addTearDown(container.dispose);
      final opening = container.read(workspaceSnapshotProvider.future);
      await _settle();
      repository.publishIntegrity(
        skills: {
          WorkspaceSkillId('managed-1'):
              WorkspaceSkillIntegrityStatus.driftPending,
        },
      );
      await _settle();
      open.complete(WorkspaceCompleted(value: captured));
      final accepted = await opening;
      expect(accepted.revision, 1);
      expect(
        accepted.skills.single.integrity,
        WorkspaceSkillIntegrityStatus.driftPending,
      );
    },
  );

  test(
    'does not close the shared repository when the provider is disposed',
    () async {
      final repository = FakeSkillsWorkspaceRepository();
      final container = _container(repository);
      await container.read(workspaceSnapshotProvider.future);

      container.dispose();
      await _settle();

      expect(repository.closeCalls, 0);
    },
  );

  test('exposes a typed open failure as AsyncError', () async {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.repositoryNotOpen,
      operation: WorkspaceOperationKind.open,
    );
    final repository = FakeSkillsWorkspaceRepository()..openError = failure;
    final container = _container(repository);
    addTearDown(container.dispose);
    final reported = Completer<Object>();
    final subscription = container.listen(workspaceSnapshotProvider, (
      _,
      value,
    ) {
      if (value.hasError && !reported.isCompleted) {
        reported.complete(value.error);
      }
    }, fireImmediately: true);
    addTearDown(subscription.close);

    expect(await reported.future, same(failure));

    expect(container.read(workspaceSnapshotProvider).hasError, isTrue);
  });
}

ProviderContainer _container(
  FakeSkillsWorkspaceRepository repository, {
  AppAnalytics analytics = const NoopAppAnalytics(),
}) => ProviderContainer(
  overrides: [
    appAnalyticsProvider.overrideWithValue(analytics),
    skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
  ],
);

SkillsWorkspaceSnapshot _snapshot({
  required int revision,
  bool favorite = false,
  WorkspaceIntegrityStatus integrity = WorkspaceIntegrityStatus.healthy,
}) => SkillsWorkspaceSnapshot(
  revision: revision,
  integrity: integrity,
  projectRoots: const [],
  skills: [
    WorkspaceSkill(
      id: WorkspaceSkillId('managed-$revision'),
      slotKey: 'skill-$revision',
      declaredName: 'skill-$revision',
      displayName: 'Skill $revision',
      description: 'Description',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/source',
      ),
      currentRevision: SkillRevision(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime(2026),
        resolvedSourceRevision: 'local',
      ),
      activations: const [],
      isFavorite: favorite,
    ),
  ],
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);
