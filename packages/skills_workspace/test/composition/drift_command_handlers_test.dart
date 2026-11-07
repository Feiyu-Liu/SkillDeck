import 'dart:async';

import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/drift/drift_models.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

import '../support/drift_command_test_support.dart';
import '../support/drift_test_support.dart';

void main() {
  late DriftCommandFixture fixture;
  setUp(() async => fixture = await DriftCommandFixture.create());
  tearDown(() => fixture.snapshots.close());

  for (final pending in [false, true]) {
    test(
      '${pending ? 'pending' : 'completed'} resolve waits for an old scan then validates committed artifacts freshly',
      () async {
        final review = await fixture.inspect();
        final blocked =
            Completer<WorkspaceMaterializationReconciliationReport>();
        fixture.materializations.blockedValidation = blocked;
        final oldValidation = fixture.integrity.validate(driftSkillId);
        await fixture.materializations.validationStarted.future;
        if (pending) {
          fixture.operations.failures.failures.add(
            'recovery.finalize:finalize',
          );
        }
        var finished = false;
        final resolution = fixture.restore(review).then((result) {
          finished = true;
          return result;
        });
        await fixture.committed.future;
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        blocked.complete(driftReconciliation(drifted: true));
        expect((await oldValidation).status, SkillIntegrityStatus.driftPending);
        final result = await resolution;

        expect(result.isCommittedFinalizationPending, pending);
        expect(result.isSuccess, !pending);
        expect(fixture.materializations.validations, 2);
        expect(fixture.status, SkillIntegrityStatus.healthy);
        expect(fixture.snapshots.current.revision, RepositoryRevision(1));
        expect(
          fixture.progress,
          containsAllInOrder([
            OperationProgressPhase.inspecting,
            OperationProgressPhase.committing,
            OperationProgressPhase.finalizing,
          ]),
        );
        if (pending) {
          expect(
            result.warnings.single.code,
            SkillsWarningCode.finalizationDeferred,
          );
          expect(
            result.finalizationPendingOrNull!.committedRepositoryRevision,
            RepositoryRevision(1),
          );
        } else {
          expect(
            result.valueOrNull!.snapshot.integrity.skills.single.status,
            SkillIntegrityStatus.healthy,
          );
        }
      },
    );
  }

  test(
    'Snapshot reload failure still forces integrity and retains committed-pending warning',
    () async {
      final review = await fixture.inspect();
      fixture.reader.throwOnRead = true;
      final result = await fixture.restore(review);

      expect(result.isCommittedFinalizationPending, isTrue);
      expect(
        result.warnings.single.code,
        SkillsWarningCode.finalizationDeferred,
      );
      expect(fixture.materializations.validations, 1);
      expect(fixture.status, SkillIntegrityStatus.healthy);
      expect(fixture.progress.last, OperationProgressPhase.finalizing);
    },
  );

  test(
    'cleanup failure remains a validated success with recovery warning',
    () async {
      final review = await fixture.inspect();
      fixture.operations.failures.failures.add('recovery.cleanup');
      final result = await fixture.restore(review);

      expect(result.isSuccess, isTrue);
      expect(
        result.warnings.single.code,
        SkillsWarningCode.recoveryCleanupDeferred,
      );
      expect(fixture.materializations.validations, 1);
      expect(fixture.status, SkillIntegrityStatus.healthy);
    },
  );

  test(
    'restore with no drift or missing artifacts is unchanged and never journals',
    () async {
      fixture.materializations.inspection = SkillMaterializationInspection(
        effectiveObjectId: driftObject('2'),
        effectiveContentHash: 'a' * 64,
        artifacts: const [],
      );
      final review = await fixture.inspect();
      final result = await fixture.restore(review);

      expect(result, isA<SkillsSuccess<MutationReport>>());
      expect((result as SkillsSuccess<MutationReport>).changed, isFalse);
      expect(result.value.affectedSkillIds, isEmpty);
      expect(result.value.snapshot.revision, RepositoryRevision(0));
      expect(fixture.operations.log.events, isEmpty);
      expect(fixture.operations.controlPlane.journals, isEmpty);
      expect(fixture.revisions.calls, 0);
      expect(fixture.materializations.validations, 1);
      expect(fixture.status, SkillIntegrityStatus.healthy);
    },
  );

  test('a would-be no-op still rejects a changed Effective Revision', () async {
    fixture.materializations.inspection = SkillMaterializationInspection(
      effectiveObjectId: driftObject('2'),
      effectiveContentHash: 'a' * 64,
      artifacts: const [],
    );
    final review = await fixture.inspect();
    fixture.content.state = driftState(effective: driftObject('3'));
    final result = await fixture.restore(review);

    expect(result.failureOrNull!.code, SkillsErrorCode.staleDriftReview);
    expect(result.failureOrNull!.context['reason'], 'effectiveRevisionChanged');
    expect(fixture.operations.log.events, isEmpty);
  });

  test(
    'restore refuses a newly drifted unreviewed location before journaling',
    () async {
      final review = await fixture.inspect();
      fixture.materializations.inspection = driftInspection(
        targetPath: '$driftTargetPath-other',
      );
      final result = await fixture.restore(review);

      expect(result.failureOrNull!.code, SkillsErrorCode.staleDriftReview);
      expect(result.failureOrNull!.context['reason'], 'artifactChanged');
      expect(fixture.operations.log.events, isEmpty);
    },
  );

  test(
    'lock-time Snapshot rejection preserves actual revision and reason',
    () async {
      final review = await fixture.inspect();
      fixture.operations.controlPlane.repositoryRevision = RepositoryRevision(
        9,
      );
      final result = await fixture.restore(review);

      expect(result.failureOrNull!.code, SkillsErrorCode.staleSnapshot);
      expect(result.failureOrNull!.context, {
        'reason': 'staleRepositoryRevision',
        'actualRepositoryRevision': 9,
      });
    },
  );

  for (final failure in [
    (
      event: 'lock.acquire',
      code: SkillsErrorCode.repositoryBusy,
      reason: 'lockUnavailable',
    ),
    (
      event: 'control.read',
      code: SkillsErrorCode.stateCorrupt,
      reason: 'snapshotReadFailed',
    ),
    (
      event: 'control.prepared-envelope',
      code: SkillsErrorCode.journalCorrupt,
      reason: 'journalWriteFailed',
    ),
    (
      event: 'recovery.apply:apply',
      code: SkillsErrorCode.operationFailed,
      reason: 'applyFailed',
    ),
    (
      event: 'control.commit',
      code: SkillsErrorCode.operationFailed,
      reason: 'businessCommitFailed',
    ),
  ]) {
    test('${failure.event} preserves typed outcome reason', () async {
      final review = await fixture.inspect();
      fixture.operations.failures.failures.add(failure.event);
      final result = await fixture.restore(review);

      expect(result.failureOrNull!.code, failure.code);
      expect(result.failureOrNull!.context['reason'], failure.reason);
    });
  }

  test('failed rollback preserves the original failure reason', () async {
    final review = await fixture.inspect();
    fixture.operations.failures.failures.addAll([
      'recovery.apply:apply',
      'recovery.rollback',
    ]);
    final result = await fixture.restore(review);

    expect(result.failureOrNull!.code, SkillsErrorCode.recoveryFailed);
    expect(result.failureOrNull!.context['reason'], 'applyFailed');
  });

  test(
    'last-moment external precondition maps to the public stale reason',
    () async {
      final review = await fixture.inspect();
      fixture.operations.failures.externalPreconditionFailures.add(
        'recovery.apply:apply',
      );
      final result = await fixture.restore(review);

      expect(result.failureOrNull!.code, SkillsErrorCode.staleDriftReview);
      expect(result.failureOrNull!.context['reason'], 'artifactChanged');
    },
  );

  for (final entry in _codes.entries) {
    test(
      'revision preparation retains ${entry.key.name} and bounded context',
      () async {
        final review = await fixture.inspect();
        fixture.revisions.result = DriftFailure<RevisionObjectId>(
          code: entry.key,
          context: const {'stage': 'prepare'},
        );
        final result = await fixture.restore(review);

        expect(result.failureOrNull!.code, entry.value);
        expect(result.failureOrNull!.context['stage'], 'prepare');
        expect(
          fixture.operations.log.events,
          contains('recovery.rollback-envelope'),
        );
      },
    );
  }

  test(
    'export delegates to the application port without taking a writer lock',
    () async {
      final review = await fixture.inspect();
      fixture.exporter.result = DriftFailure(
        code: DriftFailureCode.staleDriftReview,
        context: const {'reason': 'artifactChanged'},
      );
      final result = await fixture.execute<SkillDriftExport>(
        WorkspaceOperationKind.exportSkillDriftArtifact,
        ExportSkillDriftArtifactRequest(
          review: review,
          artifactId: 'repositoryCopy',
          destinationDirectory: '/exports',
        ),
      );

      expect(result.failureOrNull!.code, SkillsErrorCode.staleDriftReview);
      expect(result.failureOrNull!.context['reason'], 'artifactChanged');
      expect(fixture.operations.log.events, isEmpty);
    },
  );
}

const _codes = {
  DriftFailureCode.operationCancelled: SkillsErrorCode.operationCancelled,
  DriftFailureCode.skillNotFound: SkillsErrorCode.skillNotFound,
  DriftFailureCode.revisionStoreCorrupt: SkillsErrorCode.revisionStoreCorrupt,
  DriftFailureCode.staleDriftReview: SkillsErrorCode.staleDriftReview,
  DriftFailureCode.driftResolutionUnavailable:
      SkillsErrorCode.driftResolutionUnavailable,
  DriftFailureCode.updateCandidateResolutionRequired:
      SkillsErrorCode.updateCandidateResolutionRequired,
  DriftFailureCode.dirtyDraftResolutionRequired:
      SkillsErrorCode.dirtyDraftResolutionRequired,
  DriftFailureCode.invalidSkill: SkillsErrorCode.invalidSkill,
  DriftFailureCode.skillContentLimitExceeded:
      SkillsErrorCode.skillContentLimitExceeded,
  DriftFailureCode.declaredNameChangeNotAllowed:
      SkillsErrorCode.declaredNameChangeNotAllowed,
  DriftFailureCode.historicalNameMismatch:
      SkillsErrorCode.historicalNameMismatch,
  DriftFailureCode.ioFailure: SkillsErrorCode.ioFailure,
};
