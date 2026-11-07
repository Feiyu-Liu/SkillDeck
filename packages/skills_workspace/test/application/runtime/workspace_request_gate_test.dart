import 'dart:async';

import 'package:skills_workspace/src/application/runtime/workspace_request_gate.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:test/test.dart';

const _first = '123e4567-e89b-42d3-a456-426614174520';
const _second = '123e4567-e89b-42d3-b456-426614174521';

void main() {
  test('admits only while open and rejects duplicate Operation IDs', () async {
    final gate = WorkspaceRequestGate();
    expect(
      gate.admit(
        operationId: OperationId(_first),
        cancelBeforeCommit: () async {},
      ),
      isNull,
    );
    await gate.openForRequests();
    final request = gate.admit(
      operationId: OperationId(_first),
      cancelBeforeCommit: () async {},
    );
    expect(request, isNotNull);
    expect(
      () => gate.admit(
        operationId: OperationId(_first),
        cancelBeforeCommit: () async {},
      ),
      throwsStateError,
    );
    request!.finish();
    await gate.stopAccepting();
    expect(
      gate.admit(
        operationId: OperationId(_second),
        cancelBeforeCommit: () async {},
      ),
      isNull,
    );
  });

  test(
    'shutdown cancels pre-commit work and waits for its terminal result',
    () async {
      final gate = WorkspaceRequestGate();
      await gate.openForRequests();
      final cancelled = Completer<void>();
      final request = gate.admit(
        operationId: OperationId(_first),
        cancelBeforeCommit: () async => cancelled.complete(),
      )!;

      var settled = false;
      final draining = gate.settleInFlightByCommitState().then(
        (_) => settled = true,
      );
      await cancelled.future;
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      request.finish();
      await draining;
      expect(settled, isTrue);
    },
  );

  test(
    'shutdown never cancels post-commit work but waits for finalization',
    () async {
      final gate = WorkspaceRequestGate();
      await gate.openForRequests();
      var cancellationCalls = 0;
      final request = gate.admit(
        operationId: OperationId(_first),
        cancelBeforeCommit: () async => cancellationCalls += 1,
      )!;
      request.markBusinessCommitted();

      var settled = false;
      final draining = gate.settleInFlightByCommitState().then(
        (_) => settled = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cancellationCalls, 0);
      expect(settled, isFalse);
      request.finish();
      await draining;
      expect(settled, isTrue);
      await gate.close();
    },
  );

  test('admission completion and cancellation are idempotent', () async {
    final gate = WorkspaceRequestGate();
    await gate.openForRequests();
    var cancellations = 0;
    final request = gate.admit(
      operationId: OperationId(_first),
      cancelBeforeCommit: () async => cancellations += 1,
    )!;

    await Future.wait([
      request.cancelIfPreCommit(),
      request.cancelIfPreCommit(),
    ]);
    expect(cancellations, 1);
    request.finish();
    request.finish();
    expect(gate.activeRequestCount, 0);
  });
}
