import 'package:skills_workspace/src/composition/revision_worker_task_executor.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('starts once, delegates status, and closes once', () async {
    final runtime = RevisionWorkerRuntime(
      taskExecutor: executeComposedRevisionWorkerTask,
    );
    await Future.wait([runtime.start(), runtime.start()]);
    expect(runtime.isRunning, isTrue);
    expect((await runtime.status()).protocolVersion, greaterThan(0));

    await runtime.close();
    await runtime.close();
    expect(runtime.isRunning, isFalse);
    await expectLater(
      runtime.status(),
      throwsA(
        isA<RevisionWorkerException>().having(
          (error) => error.code,
          'code',
          RevisionWorkerFailureCode.closed,
        ),
      ),
    );
    await expectLater(runtime.start(), throwsA(isA<RevisionWorkerException>()));
  });
}
