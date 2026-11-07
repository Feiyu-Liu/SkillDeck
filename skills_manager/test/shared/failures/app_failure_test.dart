import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

void main() {
  test('normalizes unknown errors without retaining raw error data', () {
    final failure = normalizeAppFailure(
      StateError('/private/path?token=secret'),
      operationKey: 'loadCatalog',
    );

    expect(failure, isA<UnexpectedAppFailure>());
    expect(failure.codeKey, 'unexpected');
    expect(failure.operationKey, 'loadCatalog');
    expect(failure.message, AppFailureMessage.unexpected);
    expect(failure.context, isEmpty);
    expect(failure.warnings, isEmpty);
    expect(failure.toString(), isNot(contains('/private/path')));
    expect(failure.toString(), isNot(contains('secret')));
  });

  test('preserves an existing typed app failure', () {
    const failure = UnexpectedAppFailure(operationKey: 'refreshRepository');

    expect(
      normalizeAppFailure(failure, operationKey: 'ignored'),
      same(failure),
    );
  });

  test('keeps diagnostics separate from user-facing failure text', () {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.gitFailed,
      operation: WorkspaceOperationKind.install,
      diagnostic: 'Sanitized Git diagnostic',
    );

    expect(failure.diagnostic, 'Sanitized Git diagnostic');
    expect(failure.toString(), isNot(contains('Sanitized Git diagnostic')));
  });

  test('only a blocked Agent folder trades retry for refresh and review', () {
    WorkspaceException failure(WorkspaceErrorCode code, [String? reason]) =>
        WorkspaceException(
          code: code,
          operation: WorkspaceOperationKind.adopt,
          context: {'reason': ?reason},
        );

    expect(
      failure(
        WorkspaceErrorCode.agentRootOwnership,
        'agentRootOwnershipBlocked',
      ).recoveryPolicy,
      AppRecoveryPolicy.refreshThenReview,
    );
    expect(
      failure(
        WorkspaceErrorCode.agentRootOwnership,
        'agentRootOwnershipRepairFailed',
      ).recoveryPolicy,
      AppRecoveryPolicy.retryExplicitly,
    );
    // Codes listed beside it keep their retry.
    for (final code in [
      WorkspaceErrorCode.repositoryBusy,
      WorkspaceErrorCode.sourceUnavailable,
      WorkspaceErrorCode.httpFailure,
      WorkspaceErrorCode.operationCancelled,
    ]) {
      expect(failure(code).recoveryPolicy, AppRecoveryPolicy.retryExplicitly);
    }
  });

  test('external conflicts require refresh and explicit review', () {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.externalConflict,
      operation: WorkspaceOperationKind.install,
      context: const {
        'slotKey': 'review',
        'location': '/agent/skills',
        'targetPath': '/agent/skills/review',
        'reason': 'unmanagedTargetOccupied',
      },
    );

    expect(failure.message, AppFailureMessage.externalSkillConflict);
    expect(failure.recoveryPolicy, AppRecoveryPolicy.refreshThenReview);
    expect(failure.context['reason'], 'unmanagedTargetOccupied');
  });

  test(
    'Journal integrity failures do not retry a possibly committed write',
    () {
      for (final code in [
        WorkspaceErrorCode.unsupportedJournalVersion,
        WorkspaceErrorCode.journalMaintenanceFailed,
      ]) {
        final failure = WorkspaceException(
          code: code,
          operation: WorkspaceOperationKind.open,
        );

        expect(failure.message, AppFailureMessage.controlPlaneCorrupt);
        expect(failure.recoveryPolicy, AppRecoveryPolicy.none);
      }
    },
  );

  test('maps resolution and recovery failures to dedicated user messages', () {
    final expectations = <WorkspaceErrorCode, AppFailureMessage>{
      WorkspaceErrorCode.migrationFailed: AppFailureMessage.migrationFailed,
      WorkspaceErrorCode.revisionStoreCorrupt:
          AppFailureMessage.revisionStoreCorrupt,
      WorkspaceErrorCode.dirtyDraftResolutionRequired:
          AppFailureMessage.dirtyDraftResolutionRequired,
      WorkspaceErrorCode.updateCandidateResolutionRequired:
          AppFailureMessage.updateCandidateResolutionRequired,
      WorkspaceErrorCode.declaredNameChangeNotAllowed:
          AppFailureMessage.nameChangeNotAllowed,
      WorkspaceErrorCode.finalizationRecoveryFailed:
          AppFailureMessage.finalizationRecoveryFailed,
    };

    for (final entry in expectations.entries) {
      final failure = WorkspaceException(
        code: entry.key,
        operation: WorkspaceOperationKind.open,
      );
      expect(failure.message, entry.value, reason: entry.key.name);
    }
    expect(
      WorkspaceException(
        code: WorkspaceErrorCode.finalizationRecoveryFailed,
        operation: WorkspaceOperationKind.resumeFinalizationRecovery,
      ).recoveryPolicy,
      AppRecoveryPolicy.retryExplicitly,
    );
  });
  test(
    'drift failures offer refresh and review or a dedicated integrity message',
    () {
      for (final code in [
        WorkspaceErrorCode.staleSnapshot,
        WorkspaceErrorCode.staleDriftReview,
      ]) {
        final failure = WorkspaceFailure(
          code: code,
          operation: WorkspaceOperationKind.resolveSkillDrift,
        );
        expect(failure.message, AppFailureMessage.staleSnapshot);
        expect(failure.recoveryPolicy, AppRecoveryPolicy.refreshThenReview);
      }
      final unavailable = WorkspaceFailure(
        code: WorkspaceErrorCode.driftResolutionUnavailable,
        operation: WorkspaceOperationKind.resolveSkillDrift,
      );
      expect(unavailable.message, AppFailureMessage.driftResolutionUnavailable);
      expect(unavailable.recoveryPolicy, AppRecoveryPolicy.none);
    },
  );
}
