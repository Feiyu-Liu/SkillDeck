import 'dart:async';

import 'package:skills_workspace/src/application/operations/finalization_recovery_service.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:test/test.dart';

void main() {
  test(
    'coalesces concurrent recovery callers and retries after completion',
    () async {
      final firstAttempt = Completer<OperationRecoveryReport>();
      var calls = 0;
      final recovery = OperationCoordinatorFinalizationRecovery.withRecovery(
        recover: () {
          calls += 1;
          return calls == 1
              ? firstAttempt.future
              : Future<OperationRecoveryReport>.value(
                  OperationRecoveryReport(const <RecoveredOperation>[]),
                );
        },
      );

      final first = recovery.resumeFinalizationRecovery();
      final second = recovery.resumeFinalizationRecovery();

      expect(identical(first, second), isTrue);
      expect(calls, 1);

      firstAttempt.complete(
        OperationRecoveryReport(const <RecoveredOperation>[]),
      );
      await Future.wait(<Future<OperationRecoveryReport>>[first, second]);

      await recovery.resumeFinalizationRecovery();
      expect(calls, 2);
    },
  );

  test('clears the shared attempt after a recovery error', () async {
    var calls = 0;
    final recovery = OperationCoordinatorFinalizationRecovery.withRecovery(
      recover: () {
        calls += 1;
        if (calls == 1) {
          return Future<OperationRecoveryReport>.error(StateError('failed'));
        }
        return Future<OperationRecoveryReport>.value(
          OperationRecoveryReport(const <RecoveredOperation>[]),
        );
      },
    );

    await expectLater(
      recovery.resumeFinalizationRecovery(),
      throwsA(isA<StateError>()),
    );

    await recovery.resumeFinalizationRecovery();
    expect(calls, 2);
  });
}
