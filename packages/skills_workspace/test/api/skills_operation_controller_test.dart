import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/api/skills_operation_controller.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

const _operationId = '123e4567-e89b-42d3-a456-426614174000';

void main() {
  test('closes progress before resolving the terminal result', () async {
    final controller = SkillsOperationController<String>(
      operationId: OperationId(_operationId),
      kind: WorkspaceOperationKind.install,
    );
    var progressDone = false;
    final observed = <OperationProgress>[];
    controller.operation.progress.listen(
      observed.add,
      onDone: () => progressDone = true,
    );

    controller
      ..emit(OperationProgressPhase.queued)
      ..emit(OperationProgressPhase.inspecting, currentItem: 'source')
      ..emit(OperationProgressPhase.preparing, completed: 1, total: 2);
    await controller.finish(
      SkillsSuccess<String>(value: 'installed', changed: true),
    );
    final result = await controller.operation.completed;

    expect(progressDone, isTrue);
    expect(observed.map((event) => event.phase), [
      OperationProgressPhase.queued,
      OperationProgressPhase.inspecting,
      OperationProgressPhase.preparing,
    ]);
    expect(result.valueOrNull, 'installed');
  });

  test('cancellation is idempotent and visible to the producer', () async {
    final controller = SkillsOperationController<void>(
      operationId: OperationId(_operationId),
      kind: WorkspaceOperationKind.refresh,
    );

    await Future.wait([
      controller.operation.cancel(),
      controller.operation.cancel(),
    ]);

    expect(controller.cancellationToken.isCancelled, isTrue);
  });

  test('rejects invalid progress and transitions after completion', () async {
    final controller = SkillsOperationController<void>(
      operationId: OperationId(_operationId),
      kind: WorkspaceOperationKind.refresh,
    );
    controller.emit(OperationProgressPhase.preparing);

    expect(
      () => controller.emit(OperationProgressPhase.inspecting),
      throwsStateError,
    );
    expect(
      () => controller.emit(
        OperationProgressPhase.preparing,
        completed: 2,
        total: 1,
      ),
      throwsArgumentError,
    );

    await controller.finish(SkillsSuccess<void>(value: null));
    expect(
      () => controller.emit(OperationProgressPhase.finalizing),
      throwsStateError,
    );
    await expectLater(
      controller.finish(SkillsSuccess<void>(value: null)),
      throwsStateError,
    );
  });
}
