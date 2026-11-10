import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/data/update_sweep_store.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/features/updates/presentation/view_models/updates_view_model.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

import '../../../../support/fake_skills_workspace_repository.dart';

void main() {
  test('opening the Updates page honors the persisted 24h sweep TTL', () async {
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWith(['alpha']),
    );
    final store = InMemoryUpdateSweepStore(
      DateTime.now().toUtc().subtract(const Duration(hours: 2)),
    );
    final container = _container(workspace, store);
    addTearDown(container.dispose);
    final viewModel = container.read(updatesViewModelProvider.notifier);
    await container.read(workspaceSnapshotProvider.future);

    await viewModel.ensureChecked();

    expect(workspace.checkUpdatesCalls, 0);
  });

  test('single and bulk updates publish their typed success events', () async {
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWith(['alpha', 'beta']),
      updateReports: [
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('alpha'),
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('beta'),
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
      ],
    );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(updatesViewModelProvider.notifier);
    await container.read(workspaceSnapshotProvider.future);

    await viewModel.ensureChecked();
    await viewModel.updateOne(_alphaId);

    var event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 1);
    expect(event.notification.severity, AppNotificationSeverity.success);
    expect(event.notification.message, AppNotificationMessage.skillUpdated);

    await viewModel.updateAll();

    event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 2);
    expect(event.notification.severity, AppNotificationSeverity.success);
    expect(event.notification.message, AppNotificationMessage.updatesApplied);
    // `alpha` is no longer offered to Update All: its post-Update state is
    // derived from the committed Snapshot, which now reports it as current.
    expect(workspace.updateRequests, [
      {'alpha'},
      {'beta'},
    ]);
  });

  test('completed update aggregates warnings into one notification', () async {
    final warning = WorkspaceWarning(
      code: WorkspaceWarningCode.activationTargetSkipped,
    );
    final workspace =
        FakeSkillsWorkspaceRepository(
            updateReports: [
              WorkspaceUpdateReport(
                skillId: WorkspaceSkillId('alpha'),
                status: WorkspaceUpdateStatus.updateAvailable,
              ),
            ],
          )
          ..updateTask = WorkspaceTask(
            current: _progress(warnings: [warning]),
            states: const Stream.empty(),
            completed: Future.value(
              WorkspaceCompleted(
                value: WorkspaceMutationReceipt(
                  snapshot: SkillsWorkspaceSnapshot.empty(),
                  affectedSkillIds: {_alphaId},
                ),
              ),
            ),
            cancel: () async {},
          );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(updatesViewModelProvider.notifier);

    await viewModel.updateOne(_alphaId);

    final event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 1);
    expect(event.notification.severity, AppNotificationSeverity.warning);
    expect(
      event.notification.message,
      AppNotificationMessage.completedWithWarnings,
    );
    expect(container.read(updatesViewModelProvider).operation.warnings, [
      warning,
    ]);
  });

  test(
    'a sweep aggregates warnings emitted only by the terminal outcome',
    () async {
      final warning = WorkspaceWarning(
        code: WorkspaceWarningCode.sourceEntrySkipped,
      );
      final workspace =
          FakeSkillsWorkspaceRepository(snapshot: _snapshotWith(['alpha']))
            ..checkUpdatesTask = WorkspaceTask(
              current: _progress(),
              states: const Stream.empty(),
              completed: Future.value(
                WorkspaceCompleted(
                  value: const <WorkspaceUpdateReport>[],
                  warnings: [warning],
                ),
              ),
              cancel: () async {},
            );
      final container = _container(workspace);
      addTearDown(container.dispose);
      await container.read(workspaceSnapshotProvider.future);

      await container.read(updatesViewModelProvider.notifier).ensureChecked();

      expect(container.read(skillUpdateStatusProvider).warnings, [warning]);
    },
  );

  test(
    'committed-pending update starts recovery notification, not success',
    () async {
      final warning = WorkspaceWarning(
        code: WorkspaceWarningCode.activationTargetSkipped,
      );
      final recovery =
          Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
      final workspace = FakeSkillsWorkspaceRepository()
        ..finalizationRecoveryTasks.add(
          WorkspaceTask(
            current: WorkspaceOperationProgress(
              operationId: 'recover-pending-update',
              kind: WorkspaceOperationKind.resumeFinalizationRecovery,
              phase: WorkspaceOperationPhase.finalizing,
            ),
            states: const Stream.empty(),
            completed: recovery.future,
            cancel: () async {},
          ),
        )
        ..updateTask = WorkspaceTask(
          current: _progress(),
          states: const Stream.empty(),
          completed: Future.value(
            WorkspaceCommittedPending(
              operationId: 'pending-update',
              committedRevision: 4,
              warnings: [warning],
            ),
          ),
          cancel: () async {},
        );
      final container = _container(workspace);
      addTearDown(container.dispose);

      await container
          .read(updatesViewModelProvider.notifier)
          .updateOne(_alphaId);

      final event = container.read(appNotificationControllerProvider)!;
      expect(event.kind, AppNotificationEventKind.taskStarted);
      expect(
        event.notification.message,
        AppNotificationMessage.finalizationPending,
      );
      expect(
        container
            .read(workspaceFinalizationCoordinatorProvider)
            .warningsByOperationId['pending-update'],
        [warning],
      );

      recovery.complete(
        WorkspaceCompleted(
          value: SkillsWorkspaceSnapshot(
            revision: 4,
            projectRoots: const [],
            skills: const [],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('abandon candidate invokes its explicit recovery action', () async {
    final candidate = WorkspaceUpdateCandidateSummary(
      status: WorkspaceUpdateCandidateStatus.conflicted,
      conflictPaths: const ['SKILL.md'],
      createdAt: DateTime.utc(2026),
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 1,
        projectRoots: const [],
        skills: [_skill(updateCandidate: candidate)],
      ),
      updateReports: [
        WorkspaceUpdateReport(
          skillId: _alphaId,
          status: WorkspaceUpdateStatus.resolutionRequired,
        ),
      ],
    );
    final container = _container(workspace);
    addTearDown(container.dispose);

    await container.read(workspaceSnapshotProvider.future);
    await container
        .read(updatesViewModelProvider.notifier)
        .abandonCandidate(_alphaId);

    expect(workspace.abandonedUpdateCandidates, [_alphaId]);
    // Abandoning does not issue a recheck of its own: the Snapshot change
    // invalidates the entry through the shared store.
    expect(workspace.checkUpdatesCalls, 0);
    expect(
      container.read(appNotificationControllerProvider)!.notification.message,
      AppNotificationMessage.updateCandidateAbandoned,
    );
  });

  test('integrity-isolated skill never starts an update mutation', () async {
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 1,
        projectRoots: const [],
        skills: [
          WorkspaceSkill(
            id: _alphaId,
            slotKey: 'alpha',
            declaredName: 'alpha',
            displayName: 'Alpha',
            description: 'Test skill',
            source: const SkillSourceProvenance(
              kind: WorkspaceSourceKind.local,
              locator: '/skills/alpha',
            ),
            currentRevision: SkillRevision(
              contentHash: 'abc123',
              fileCount: 1,
              byteSize: 1,
              acquiredAt: DateTime.utc(2026),
            ),
            activations: const [],
            integrity: WorkspaceSkillIntegrityStatus.revisionStoreCorrupt,
          ),
        ],
      ),
    );
    final container = _container(workspace);
    addTearDown(container.dispose);
    await container.read(workspaceSnapshotProvider.future);

    await container.read(updatesViewModelProvider.notifier).updateOne(_alphaId);

    expect(workspace.updateRequests, isEmpty);
    expect(container.read(appNotificationControllerProvider), isNull);
  });

  test('typed update failure is notified without replacing the list', () async {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.sourceUnavailable,
      operation: WorkspaceOperationKind.update,
    );
    final report = WorkspaceUpdateReport(
      skillId: WorkspaceSkillId('alpha'),
      status: WorkspaceUpdateStatus.updateAvailable,
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWith(['alpha']),
      updateReports: [report],
    )..updateError = failure;
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(updatesViewModelProvider.notifier);
    await container.read(workspaceSnapshotProvider.future);

    await viewModel.ensureChecked();
    await viewModel.updateOne(_alphaId);

    final state = container.read(updatesViewModelProvider);
    expect(state.status, UpdatesStatus.idle);
    // A failed mutation leaves the shared report untouched.
    expect(
      container.read(skillUpdateStatusProvider).stateOf(_alphaId).report,
      same(report),
    );
    expect(state.error, isNull);
    final event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 1);
    expect(event.notification.severity, AppNotificationSeverity.error);
    expect(event.notification.failure, same(failure));
  });

  test('unknown update failure is redacted before notification', () async {
    final result = Completer<WorkspaceCompletion<WorkspaceMutationReceipt>>();
    final workspace = FakeSkillsWorkspaceRepository()
      ..updateTask = WorkspaceTask(
        current: _progress(),
        states: const Stream.empty(),
        completed: result.future,
        cancel: () async {},
      );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(updatesViewModelProvider.notifier);

    final update = viewModel.updateOne(_alphaId);
    result.completeError(StateError('token=secret path=/private/repository'));
    await update;

    final failure = container
        .read(appNotificationControllerProvider)!
        .notification
        .failure!;
    expect(failure, isA<UnexpectedAppFailure>());
    expect(failure.operationKey, WorkspaceOperationKind.update.name);
    expect(failure.context, isEmpty);
    expect(failure.toString(), isNot(contains('secret')));
    expect(failure.toString(), isNot(contains('/private')));
  });

  test('cancelled update publishes info and keeps reports ready', () async {
    final report = WorkspaceUpdateReport(
      skillId: WorkspaceSkillId('alpha'),
      status: WorkspaceUpdateStatus.updateAvailable,
    );
    final workspace =
        FakeSkillsWorkspaceRepository(
            snapshot: _snapshotWith(['alpha']),
            updateReports: [report],
          )
          ..updateError = WorkspaceException(
            code: WorkspaceErrorCode.operationCancelled,
            operation: WorkspaceOperationKind.update,
          );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(updatesViewModelProvider.notifier);
    await container.read(workspaceSnapshotProvider.future);

    await viewModel.ensureChecked();
    await viewModel.updateOne(_alphaId);

    final state = container.read(updatesViewModelProvider);
    expect(state.status, UpdatesStatus.idle);
    expect(
      container.read(skillUpdateStatusProvider).stateOf(_alphaId).report,
      same(report),
    );
    final event = container.read(appNotificationControllerProvider)!;
    expect(event.sequence, 1);
    expect(event.notification.severity, AppNotificationSeverity.info);
    expect(
      event.notification.message,
      AppNotificationMessage.operationCancelled,
    );
    expect(event.notification.failure, isNull);
  });

  test('a sweep records its failure as state and stays silent', () async {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.sourceUnavailable,
      operation: WorkspaceOperationKind.checkUpdates,
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWith(['alpha']),
    )..checkUpdatesError = failure;
    final container = _container(workspace);
    addTearDown(container.dispose);
    final viewModel = container.read(updatesViewModelProvider.notifier);
    await container.read(workspaceSnapshotProvider.future);

    await viewModel.ensureChecked();

    final settled = container.read(skillUpdateStatusProvider).stateOf(_alphaId);
    expect(settled, isA<SkillUpdateCheckFailed>());
    expect((settled as SkillUpdateCheckFailed).failure, same(failure));
    // A background sweep never raises a toast: an offline launch would
    // otherwise show a failure notification on every start.
    expect(container.read(appNotificationControllerProvider), isNull);
  });
}

ProviderContainer _container(
  FakeSkillsWorkspaceRepository workspace, [
  UpdateSweepStore? store,
]) {
  return ProviderContainer(
    overrides: [
      skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
      skillUpdateSweepStoreProvider.overrideWithValue(
        store ?? InMemoryUpdateSweepStore(),
      ),
    ],
  );
}

/// A Snapshot the sweep can enumerate. The shared store derives its work list
/// from the Snapshot, so tests that expect a sweep must publish one.
SkillsWorkspaceSnapshot _snapshotWith(List<String> slotKeys) =>
    SkillsWorkspaceSnapshot(
      revision: 1,
      projectRoots: const [],
      skills: [for (final slotKey in slotKeys) _skillNamed(slotKey)],
    );

WorkspaceSkill _skillNamed(String slotKey) => WorkspaceSkill(
  id: WorkspaceSkillId(slotKey),
  slotKey: slotKey,
  declaredName: slotKey,
  displayName: slotKey,
  description: 'Test skill',
  source: SkillSourceProvenance(
    kind: WorkspaceSourceKind.local,
    locator: '/skills/$slotKey',
  ),
  currentRevision: SkillRevision(
    contentHash: 'hash-$slotKey',
    fileCount: 1,
    byteSize: 1,
    acquiredAt: DateTime.utc(2026),
  ),
  activations: const [],
);

WorkspaceOperationProgress _progress({
  List<WorkspaceWarning> warnings = const [],
}) => WorkspaceOperationProgress(
  operationId: 'test-update',
  kind: WorkspaceOperationKind.update,
  phase: WorkspaceOperationPhase.applying,
  warnings: warnings,
);

final _alphaId = WorkspaceSkillId('alpha');

WorkspaceSkill _skill({WorkspaceUpdateCandidateSummary? updateCandidate}) =>
    WorkspaceSkill(
      id: _alphaId,
      slotKey: 'alpha',
      declaredName: 'alpha',
      displayName: 'Alpha',
      description: 'Test skill',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/skills/alpha',
      ),
      currentRevision: SkillRevision(
        contentHash: 'abc123',
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime.utc(2026),
      ),
      activations: const [],
      updateCandidate: updateCandidate,
    );
