import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/operations/app_operation_tracker.dart';

void main() {
  test('managed identity is distinct from a mutable Slot Key lookup', () {
    final id = WorkspaceSkillId('managed-abc');
    final skill = WorkspaceSkill(
      id: id,
      slotKey: 'old-slot',
      declaredName: 'example',
      displayName: 'Example',
      description: 'Example Skill',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/tmp/example',
      ),
      currentRevision: SkillRevision(
        contentHash: 'hash',
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime.utc(2026),
      ),
      activations: const [],
    );
    final snapshot = SkillsWorkspaceSnapshot(
      revision: 1,
      projectRoots: const [],
      skills: [skill],
    );

    expect(snapshot.findSkillById(id), same(skill));
    expect(snapshot.findSkillBySlotKey('old-slot'), same(skill));
  });

  test('expected failure stays a typed task completion', () async {
    final failure = WorkspaceFailure(
      code: WorkspaceErrorCode.gitUnavailable,
      operation: WorkspaceOperationKind.inspectSource,
    );
    final task = WorkspaceTask<String>(
      current: WorkspaceOperationProgress(
        operationId: 'task-1',
        kind: WorkspaceOperationKind.inspectSource,
        phase: WorkspaceOperationPhase.queued,
      ),
      states: const Stream.empty(),
      completed: Future.value(WorkspaceFailed(failure: failure)),
      cancel: () async {},
    );

    final completion = await task.completed;
    expect(completion, isA<WorkspaceFailed<String>>());
    expect((completion as WorkspaceFailed<String>).failure, same(failure));
  });

  test(
    'tracker returns committed-pending without converting it to failure',
    () async {
      final tracker =
          AppOperationTracker<WorkspaceOperationProgress, WorkspaceWarning>(
            onChanged: (_) {},
            warningsOf: (progress) => progress.warnings,
            warningKey: workspaceWarningKey,
          );
      final task = WorkspaceTask<void>(
        current: WorkspaceOperationProgress(
          operationId: 'task-2',
          kind: WorkspaceOperationKind.update,
          phase: WorkspaceOperationPhase.finalizing,
        ),
        states: const Stream.empty(),
        completed: Future.value(
          WorkspaceCommittedPending(
            operationId: 'task-2',
            committedRevision: 3,
          ),
        ),
        cancel: () async {},
      );

      final completion = await task.trackedCompletionBy(tracker);
      expect(completion, isA<WorkspaceCommittedPending<void>>());
      expect(tracker.state.running, isFalse);
      await tracker.dispose();
    },
  );
}
