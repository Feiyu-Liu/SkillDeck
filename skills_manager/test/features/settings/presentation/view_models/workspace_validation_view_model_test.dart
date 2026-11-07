import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/settings/data/workspace_validation_history_store.dart';
import 'package:skills_manager/features/settings/presentation/view_models/workspace_validation_view_model.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';

import '../../../../support/fake_skills_workspace_repository.dart';

void main() {
  late FakeSkillsWorkspaceRepository repository;
  late _ControlledValidation validation;
  late InMemoryWorkspaceValidationHistoryStore store;
  late ProviderContainer container;

  ProviderContainer createContainer() => ProviderContainer(
    overrides: [
      skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
      workspaceValidationHistoryStoreProvider.overrideWithValue(store),
    ],
  );

  setUp(() {
    repository = FakeSkillsWorkspaceRepository();
    validation = _ControlledValidation(repository);
    store = InMemoryWorkspaceValidationHistoryStore();
    container = createContainer();
  });

  tearDown(() => container.dispose());

  test('reports progress and remembers the finished result', () async {
    final viewModel = container.read(
      workspaceValidationViewModelProvider.notifier,
    );
    final run = viewModel.validate();
    expect(container.read(workspaceValidationViewModelProvider).running, true);

    validation.progress(completed: 2, total: 5);
    await Future<void>.delayed(Duration.zero);
    final running = container.read(workspaceValidationViewModelProvider);
    expect((running.completed, running.total), (2, 5));

    validation.finish(
      WorkspaceCompleted(
        value: WorkspaceValidationReport(
          checkedSkillCount: 5,
          repairedArtifactCount: 1,
          healthySkillCount: 3,
          repairedSkillIds: const [],
          driftedSkillIds: [WorkspaceSkillId('drifted')],
          failedSkillIds: const [],
        ),
      ),
    );
    await run;

    final state = container.read(workspaceValidationViewModelProvider);
    expect(state.running, isFalse);
    expect(state.last?.failed, isFalse);
    expect(state.last?.checkedSkillCount, 5);
    expect(state.last?.repairedArtifactCount, 1);
    expect(state.last?.driftedSkillCount, 1);
    expect((await store.readLast())?.checkedSkillCount, 5);
  });

  test('records a failed validation', () async {
    final run = container
        .read(workspaceValidationViewModelProvider.notifier)
        .validate();
    validation.finish(
      WorkspaceFailed(
        failure: WorkspaceFailure(
          code: WorkspaceErrorCode.operationFailed,
          operation: WorkspaceOperationKind.validateWorkspace,
        ),
      ),
    );
    await run;

    expect(
      container.read(workspaceValidationViewModelProvider).last?.failed,
      isTrue,
    );
  });

  test('a cancelled validation keeps the previous result', () async {
    final previous = WorkspaceValidationRecord(
      completedAt: DateTime.utc(2026, 10, 1, 9),
      failed: false,
      checkedSkillCount: 3,
    );
    store = InMemoryWorkspaceValidationHistoryStore(previous);
    container.dispose();
    container = createContainer();
    container.read(workspaceValidationViewModelProvider);
    await Future<void>.delayed(Duration.zero);

    final run = container
        .read(workspaceValidationViewModelProvider.notifier)
        .validate();
    validation.finish(
      WorkspaceFailed(
        failure: WorkspaceFailure(
          code: WorkspaceErrorCode.operationCancelled,
          operation: WorkspaceOperationKind.validateWorkspace,
        ),
      ),
    );
    await run;

    final state = container.read(workspaceValidationViewModelProvider);
    expect(state.running, isFalse);
    expect(state.last, same(previous));
    expect(await store.readLast(), same(previous));
  });

  test('loads the result recorded in an earlier session', () async {
    final previous = WorkspaceValidationRecord(
      completedAt: DateTime.utc(2026, 10, 1, 9),
      failed: false,
      checkedSkillCount: 7,
    );
    store = InMemoryWorkspaceValidationHistoryStore(previous);
    container.dispose();
    container = createContainer();

    container.read(workspaceValidationViewModelProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(workspaceValidationViewModelProvider).last,
      same(previous),
    );
  });

  test('round-trips a record through JSON', () {
    final record = WorkspaceValidationRecord(
      completedAt: DateTime.utc(2026, 10, 16, 14, 32),
      failed: false,
      checkedSkillCount: 42,
      repairedArtifactCount: 1,
      driftedSkillCount: 2,
      failedSkillCount: 3,
    );

    final decoded = WorkspaceValidationRecord.fromJson(record.toJson())!;

    expect(decoded.completedAt, record.completedAt);
    expect(decoded.checkedSkillCount, 42);
    expect(decoded.repairedArtifactCount, 1);
    expect(decoded.driftedSkillCount, 2);
    expect(decoded.failedSkillCount, 3);
    expect(WorkspaceValidationRecord.fromJson('not a record'), isNull);
  });
}

final class _ControlledValidation {
  _ControlledValidation(FakeSkillsWorkspaceRepository repository) {
    repository.validationTasks.add(
      WorkspaceTask(
        current: WorkspaceOperationProgress(
          operationId: 'validation',
          kind: WorkspaceOperationKind.validateWorkspace,
          phase: WorkspaceOperationPhase.queued,
        ),
        states: _states.stream,
        completed: _completed.future,
        cancel: () async {},
      ),
    );
  }

  final _states = StreamController<WorkspaceOperationProgress>.broadcast();
  final _completed =
      Completer<WorkspaceCompletion<WorkspaceValidationReport>>();

  void progress({required int completed, required int total}) => _states.add(
    WorkspaceOperationProgress(
      operationId: 'validation',
      kind: WorkspaceOperationKind.validateWorkspace,
      phase: WorkspaceOperationPhase.inspecting,
      completed: completed,
      total: total,
    ),
  );

  void finish(WorkspaceCompletion<WorkspaceValidationReport> completion) =>
      _completed.complete(completion);
}
