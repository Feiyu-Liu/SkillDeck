import 'dart:async';

import 'package:skills_workspace/src/api/cancellation.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/lock_wait_policy.dart';
import 'package:test/test.dart';

import '../../support/operations/operation_fakes.dart';

final _operationId = OperationId('10000000-0000-4000-8000-000000000001');

void main() {
  group('OperationCoordinator.execute', () {
    test('uses the fixed operation and durability order', () async {
      final harness = OperationHarness();
      final coordinator = harness.createCoordinator();

      final outcome = await coordinator.execute(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildPlan: (operationId, currentRevision) {
          harness.log.add('plan.build');
          return _plan(operationId, currentRevision);
        },
      );

      expect(outcome, isA<OperationCompleted>());
      final completed = outcome as OperationCompleted;
      expect(completed.committedRepositoryRevision, RepositoryRevision(1));
      expect(completed.cleanupPending, isFalse);
      expect(harness.controlPlane.journals, isEmpty);
      expect(harness.referenceMaintenance.calls, 3);
      expect(
        harness.referenceMaintenance.observedSelectedSkillIds,
        everyElement(<ManagedSkillId>{
          ManagedSkillId('20000000-0000-4000-8000-000000000001'),
        }),
      );
      final postCommitReconciliation =
          harness.referenceMaintenance.observedEventPrefixes[1];
      expect(
        postCommitReconciliation,
        contains('control.step-complete:finalize-2'),
      );
      expect(postCommitReconciliation, isNot(contains('control.complete')));
      expect(harness.log.events, <String>[
        'lock.acquire',
        'control.read',
        'plan.build',
        'control.prepared',
        'control.step-start:prepare-1',
        'recovery.prepare:prepare-1',
        'control.step-complete:prepare-1',
        'control.step-start:prepare-2',
        'recovery.prepare:prepare-2',
        'control.step-complete:prepare-2',
        'control.applying',
        'control.step-start:apply-1',
        'recovery.apply:apply-1',
        'control.step-complete:apply-1',
        'control.step-start:apply-2',
        'recovery.apply:apply-2',
        'control.step-complete:apply-2',
        'control.commit',
        'control.finalizing',
        'control.step-start:finalize-1',
        'recovery.finalize:finalize-1',
        'control.step-complete:finalize-1',
        'control.step-start:finalize-2',
        'recovery.finalize:finalize-2',
        'control.step-complete:finalize-2',
        'control.complete',
        'recovery.cleanup',
        'control.delete-journal',
        'lock.release',
      ]);
    });

    test('passes the request lock wait policy to the Writer Lock', () async {
      final harness = OperationHarness();
      final policy = LockWaitPolicy.wait(
        timeout: const Duration(seconds: 3),
        pollInterval: const Duration(milliseconds: 7),
      );

      final outcome = await harness.createCoordinator().execute(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildPlan: _plan,
        lockWaitPolicy: policy,
      );

      expect(outcome, isA<OperationCompleted>());
      expect(harness.writerLock.observedWaitPolicy, policy);
    });

    test('Retention Ref failure after Prepared triggers rollback', () async {
      final harness = OperationHarness();
      harness.referenceMaintenance.failOnCalls.add(1);

      final outcome = await harness.createCoordinator().execute(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildPlan: _plan,
      );

      expect(
        outcome,
        isA<OperationRolledBack>().having(
          (value) => value.reason,
          'reason',
          OperationAbortReason.preparationFailed,
        ),
      );
      expect(harness.referenceMaintenance.calls, 2);
      expect(
        harness.controlPlane.journals.single.phase,
        OperationJournalPhase.completed,
      );
    });

    test('post-BCP Retention Ref failure is finalization-pending', () async {
      final harness = OperationHarness();
      harness.referenceMaintenance.failOnCalls.add(2);

      final outcome = await harness.createCoordinator().execute(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildPlan: _plan,
      );

      expect(outcome, isA<OperationCommittedFinalizationPending>());
      expect(harness.controlPlane.repositoryRevision, RepositoryRevision(1));
      expect(harness.referenceMaintenance.calls, 2);
    });

    test(
      'rejects a stale Repository Revision before planning or journaling',
      () async {
        final harness = OperationHarness(
          repositoryRevision: RepositoryRevision(3),
        );

        final outcome = await harness.createCoordinator().execute(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision(2),
          buildPlan: _plan,
        );

        expect(
          outcome,
          isA<OperationRejected>()
              .having(
                (value) => value.reason,
                'reason',
                OperationAbortReason.staleRepositoryRevision,
              )
              .having(
                (value) => value.actualRepositoryRevision,
                'actualRepositoryRevision',
                RepositoryRevision(3),
              ),
        );
        expect(harness.log.events, <String>[
          'lock.acquire',
          'control.read',
          'lock.release',
        ]);
      },
    );

    test('awaits lock-held asynchronous planning before Journaling', () async {
      final harness = OperationHarness();
      final entered = Completer<void>();
      final release = Completer<void>();
      final execution = harness.createCoordinator().execute(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildPlan: (operationId, currentRevision) async {
          harness.log.add('plan.async-enter');
          entered.complete();
          await release.future;
          harness.log.add('plan.async-exit');
          return _plan(operationId, currentRevision);
        },
      );

      await entered.future;
      expect(harness.log.events, <String>[
        'lock.acquire',
        'control.read',
        'plan.async-enter',
      ]);
      release.complete();
      expect(await execution, isA<OperationCompleted>());
      expect(
        harness.log.events.indexOf('plan.async-exit'),
        lessThan(harness.log.events.indexOf('control.prepared')),
      );
    });

    test('maps lock-held planning failure before Journal creation', () async {
      final harness = OperationHarness();

      final outcome = await harness.createCoordinator().execute(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildPlan: (_, _) async => throw StateError('planning failed'),
      );

      expect(
        outcome,
        isA<OperationRejected>()
            .having(
              (value) => value.reason,
              'reason',
              OperationAbortReason.preparationFailed,
            )
            .having(
              (value) => value.detail,
              'detail',
              OperationAbortDetail.planInvariant,
            ),
      );
      expect(harness.log.events, <String>[
        'lock.acquire',
        'control.read',
        'lock.release',
      ]);
    });

    test('classifies the exception behind a planning rejection', () async {
      final cases = <Object, OperationAbortDetail>{
        const _SelfDescribingFailure(OperationAbortDetail.recoveryConflict):
            OperationAbortDetail.recoveryConflict,
        ArgumentError('bad plan'): OperationAbortDetail.planInvariant,
        Exception('opaque'): OperationAbortDetail.unknown,
      };
      for (final entry in cases.entries) {
        final outcome = await OperationHarness().createCoordinator().execute(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision.initial(),
          buildPlan: (_, _) async => throw entry.key,
        );
        expect(
          outcome,
          isA<OperationRejected>().having(
            (value) => value.detail,
            'detail',
            entry.value,
          ),
          reason: '${entry.key}',
        );
      }
    });

    test('an injected classifier decides the detail', () async {
      final harness = OperationHarness();
      final outcome = await harness
          .createCoordinator(
            classifyAbort: (_) => OperationAbortDetail.filesystem,
          )
          .execute(
            operationId: _operationId,
            expectedRepositoryRevision: RepositoryRevision.initial(),
            buildPlan: (_, _) async => throw Exception('disk'),
          );
      expect(
        outcome,
        isA<OperationRejected>().having(
          (value) => value.detail,
          'detail',
          OperationAbortDetail.filesystem,
        ),
      );
    });

    test('maps lock, Snapshot, and Prepared Journal failures', () async {
      final cases = <String, OperationAbortReason>{
        'lock.acquire': OperationAbortReason.lockUnavailable,
        'control.read': OperationAbortReason.snapshotReadFailed,
        'control.prepared': OperationAbortReason.journalWriteFailed,
      };
      for (final entry in cases.entries) {
        final harness = OperationHarness();
        harness.failures.failures.add(entry.key);

        final outcome = await harness.createCoordinator().execute(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision.initial(),
          buildPlan: _plan,
        );

        expect(
          outcome,
          isA<OperationRejected>().having(
            (value) => value.reason,
            entry.key,
            entry.value,
          ),
        );
        expect(harness.log.events, isNot(contains('recovery.rollback')));
      }
    });

    test('honors cancellation at every pre-commit boundary', () async {
      final cancellationBoundaries = <String>[
        'lock.acquire',
        'control.read',
        'control.prepared',
        'control.step-start:prepare-1',
        'recovery.prepare:prepare-1',
        'control.step-complete:prepare-1',
        'control.step-start:prepare-2',
        'recovery.prepare:prepare-2',
        'control.step-complete:prepare-2',
        'control.applying',
        'control.step-start:apply-1',
        'recovery.apply:apply-1',
        'control.step-complete:apply-1',
        'control.step-start:apply-2',
        'recovery.apply:apply-2',
        'control.step-complete:apply-2',
      ];

      for (final boundary in cancellationBoundaries) {
        final harness = OperationHarness();
        final source = CancellationSource();
        harness.log.afterEvent = (event) {
          if (event == boundary) {
            unawaited(source.cancel());
          }
        };

        final outcome = await harness.createCoordinator().execute(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision.initial(),
          buildPlan: _plan,
          cancellationToken: source.token,
        );

        if (boundary == 'lock.acquire' || boundary == 'control.read') {
          expect(
            outcome,
            isA<OperationRejected>().having(
              (value) => value.reason,
              boundary,
              OperationAbortReason.cancelled,
            ),
          );
          expect(harness.log.events, isNot(contains('recovery.rollback')));
        } else {
          expect(
            outcome,
            isA<OperationRolledBack>().having(
              (value) => value.reason,
              boundary,
              OperationAbortReason.cancelled,
            ),
          );
          expect(harness.log.events, contains('recovery.rollback'));
          expect(harness.log.events, isNot(contains('control.commit')));
        }
      }
    });

    test('ignores cancellation after the Business Commit Point', () async {
      final harness = OperationHarness();
      final source = CancellationSource();
      harness.log.afterEvent = (event) {
        if (event == 'control.commit') {
          unawaited(source.cancel());
        }
      };

      final outcome = await harness.createCoordinator().execute(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildPlan: _plan,
        cancellationToken: source.token,
      );

      expect(outcome, isA<OperationCompleted>());
      expect(harness.log.events, contains('recovery.finalize:finalize-2'));
      expect(harness.log.events, isNot(contains('recovery.rollback')));
    });

    test('rolls back every failed preparation and applying step', () async {
      final cases = <String, OperationAbortReason>{
        'control.step-start:prepare-1': OperationAbortReason.preparationFailed,
        'recovery.prepare:prepare-1': OperationAbortReason.preparationFailed,
        'control.step-complete:prepare-1':
            OperationAbortReason.preparationFailed,
        'control.step-start:prepare-2': OperationAbortReason.preparationFailed,
        'recovery.prepare:prepare-2': OperationAbortReason.preparationFailed,
        'control.step-complete:prepare-2':
            OperationAbortReason.preparationFailed,
        'control.applying': OperationAbortReason.preparationFailed,
        'control.step-start:apply-1': OperationAbortReason.applyFailed,
        'recovery.apply:apply-1': OperationAbortReason.applyFailed,
        'control.step-complete:apply-1': OperationAbortReason.applyFailed,
        'control.step-start:apply-2': OperationAbortReason.applyFailed,
        'recovery.apply:apply-2': OperationAbortReason.applyFailed,
        'control.step-complete:apply-2': OperationAbortReason.applyFailed,
      };

      for (final entry in cases.entries) {
        final harness = OperationHarness();
        harness.failures.failures.add(entry.key);

        final outcome = await harness.createCoordinator().execute(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision.initial(),
          buildPlan: _plan,
        );

        expect(
          outcome,
          isA<OperationRolledBack>().having(
            (value) => value.reason,
            entry.key,
            entry.value,
          ),
        );
        expect(harness.log.events, contains('recovery.rollback'));
        expect(harness.log.events, contains('control.rollback-complete'));
        expect(harness.log.events, isNot(contains('control.commit')));
        expect(
          harness.controlPlane.journals.single.phase,
          OperationJournalPhase.completed,
        );
      }
    });

    test('rolls back an external precondition change as stale', () async {
      final harness = OperationHarness();
      harness.failures.externalPreconditionFailures.add(
        'recovery.prepare:prepare-1',
      );

      final outcome = await harness.createCoordinator().execute(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildPlan: _plan,
      );

      expect(
        outcome,
        isA<OperationRolledBack>().having(
          (value) => value.reason,
          'reason',
          OperationAbortReason.externalPreconditionChanged,
        ),
      );
      expect(harness.log.events, contains('recovery.rollback'));
      expect(harness.log.events, isNot(contains('control.commit')));
      expect(
        harness.controlPlane.journals.single.phase,
        OperationJournalPhase.completed,
      );
    });

    test('rolls back a failed Business Commit Point', () async {
      final harness = OperationHarness();
      harness.failures.failures.add('control.commit');

      final outcome = await harness.createCoordinator().execute(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildPlan: _plan,
      );

      expect(
        outcome,
        isA<OperationRolledBack>().having(
          (value) => value.reason,
          'reason',
          OperationAbortReason.businessCommitFailed,
        ),
      );
      expect(harness.controlPlane.repositoryRevision, RepositoryRevision(0));
      expect(harness.log.events, contains('recovery.rollback'));
      expect(harness.log.events, isNot(contains('control.finalizing')));
    });

    test('leaves recoverable evidence when rollback fails', () async {
      for (final rollbackFailure in <String>[
        'recovery.rollback',
        'control.rollback-complete',
      ]) {
        final harness = OperationHarness();
        harness.failures.failures
          ..add('recovery.apply:apply-1')
          ..add(rollbackFailure);

        final outcome = await harness.createCoordinator().execute(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision.initial(),
          buildPlan: _plan,
        );

        expect(
          outcome,
          isA<OperationRollbackPending>()
              .having(
                (value) => value.reason,
                rollbackFailure,
                OperationPendingReason.rollbackFailed,
              )
              .having(
                (value) => value.originalReason,
                'original reason',
                OperationAbortReason.applyFailed,
              ),
        );
        expect(
          harness.controlPlane.journals.single.phase,
          OperationJournalPhase.applying,
        );
      }
    });

    test(
      'returns finalization-pending at every post-commit boundary',
      () async {
        final failureEvents = <String>[
          'control.finalizing',
          'control.step-start:finalize-1',
          'recovery.finalize:finalize-1',
          'control.step-complete:finalize-1',
          'control.step-start:finalize-2',
          'recovery.finalize:finalize-2',
          'control.step-complete:finalize-2',
          'control.complete',
        ];

        for (final event in failureEvents) {
          final harness = OperationHarness();
          harness.failures.failures.add(event);

          final outcome = await harness.createCoordinator().execute(
            operationId: _operationId,
            expectedRepositoryRevision: RepositoryRevision.initial(),
            buildPlan: _plan,
          );

          expect(
            outcome,
            isA<OperationCommittedFinalizationPending>()
                .having(
                  (value) => value.reason,
                  event,
                  OperationPendingReason.finalizationFailed,
                )
                .having(
                  (value) => value.committedRepositoryRevision,
                  'committedRepositoryRevision',
                  RepositoryRevision(1),
                ),
          );
          expect(
            harness.controlPlane.repositoryRevision,
            RepositoryRevision(1),
          );
          expect(harness.log.events, isNot(contains('recovery.rollback')));
          expect(harness.log.events, isNot(contains('recovery.cleanup')));
        }
      },
    );

    test(
      'reports cleanup pending without changing committed success',
      () async {
        for (final event in <String>[
          'recovery.cleanup',
          'control.delete-journal',
        ]) {
          final harness = OperationHarness();
          harness.failures.failures.add(event);

          final outcome = await harness.createCoordinator().execute(
            operationId: _operationId,
            expectedRepositoryRevision: RepositoryRevision.initial(),
            buildPlan: _plan,
          );

          expect(
            outcome,
            isA<OperationCompleted>()
                .having((value) => value.cleanupPending, event, isTrue)
                .having(
                  (value) => value.committedRepositoryRevision,
                  'committedRepositoryRevision',
                  RepositoryRevision(1),
                ),
          );
          expect(
            harness.controlPlane.journals.single.phase,
            OperationJournalPhase.completed,
          );
        }
      },
    );

    test('destructive cleanup failure remains finalization pending', () async {
      for (final event in <String>[
        'recovery.cleanup',
        'control.delete-journal',
      ]) {
        final harness = OperationHarness();
        harness.failures.failures.add(event);

        final outcome = await harness.createCoordinator().execute(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision.initial(),
          buildPlan: (operationId, currentRevision) =>
              _plan(operationId, currentRevision, destructive: true),
        );

        expect(
          outcome,
          isA<OperationCommittedFinalizationPending>().having(
            (value) => value.committedRepositoryRevision,
            event,
            RepositoryRevision(1),
          ),
        );
        expect(
          harness.controlPlane.journals.single.phase,
          OperationJournalPhase.completed,
        );
      }
    });
  });

  group('OperationCoordinator.executeDeferred', () {
    test(
      'durably journals the envelope before candidate construction',
      () async {
        final harness = OperationHarness();
        final coordinator = harness.createCoordinator();

        final outcome = await coordinator.executeDeferred<String>(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision.initial(),
          buildEnvelope: (operationId, currentRevision) {
            harness.log.add('envelope.build');
            return _envelope(operationId, currentRevision);
          },
          prepareCandidate: (envelope, cancellationToken) async {
            harness.log.add('candidate.build');
            expect(
              harness.controlPlane.journals.single.definition,
              isA<PreparedOperationEnvelope>(),
            );
            expect(
              harness.controlPlane.journals.single.phase,
              OperationJournalPhase.prepared,
            );
            return 'candidate-object';
          },
          buildPlan: (envelope, preparedCandidate) {
            harness.log.add('plan.seal:$preparedCandidate');
            return _plan(
              envelope.operationId,
              envelope.expectedRepositoryRevision,
            );
          },
        );

        expect(outcome, isA<OperationCompleted>());
        expect(harness.log.events, <String>[
          'lock.acquire',
          'control.read',
          'envelope.build',
          'control.prepared-envelope',
          'control.step-start:prepare-1',
          'candidate.build',
          'control.step-complete:prepare-1',
          'plan.seal:candidate-object',
          'control.seal-plan',
          'control.step-start:prepare-2',
          'recovery.prepare:prepare-2',
          'control.step-complete:prepare-2',
          'control.applying',
          'control.step-start:apply-1',
          'recovery.apply:apply-1',
          'control.step-complete:apply-1',
          'control.step-start:apply-2',
          'recovery.apply:apply-2',
          'control.step-complete:apply-2',
          'control.commit',
          'control.finalizing',
          'control.step-start:finalize-1',
          'recovery.finalize:finalize-1',
          'control.step-complete:finalize-1',
          'control.step-start:finalize-2',
          'recovery.finalize:finalize-2',
          'control.step-complete:finalize-2',
          'control.complete',
          'recovery.cleanup',
          'control.delete-journal',
          'lock.release',
        ]);
      },
    );

    test(
      'candidate failure rolls back through the Prepared envelope',
      () async {
        final harness = OperationHarness();

        final outcome = await harness.createCoordinator().executeDeferred<void>(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision.initial(),
          buildEnvelope: _envelope,
          prepareCandidate: (envelope, cancellationToken) async {
            throw const InjectedOperationFailure('candidate');
          },
          buildPlan: (envelope, preparedCandidate) =>
              throw StateError('must not seal'),
        );

        expect(
          outcome,
          isA<OperationRolledBack>().having(
            (value) => value.reason,
            'reason',
            OperationAbortReason.preparationFailed,
          ),
        );
        expect(harness.log.events, contains('recovery.rollback-envelope'));
        expect(
          harness.log.events,
          contains('control.envelope-rollback-complete'),
        );
        expect(harness.log.events, isNot(contains('control.seal-plan')));
        expect(
          harness.controlPlane.journals.single.definition,
          isA<PreparedOperationEnvelope>(),
        );
      },
    );

    test('a mismatched sealed plan fails closed and rolls back', () async {
      final harness = OperationHarness();
      final otherId = OperationId('10000000-0000-4000-8000-000000000099');

      final outcome = await harness.createCoordinator().executeDeferred<void>(
        operationId: _operationId,
        expectedRepositoryRevision: RepositoryRevision.initial(),
        buildEnvelope: _envelope,
        prepareCandidate: (envelope, cancellationToken) async {},
        buildPlan: (envelope, preparedCandidate) =>
            _plan(otherId, envelope.expectedRepositoryRevision),
      );

      expect(outcome, isA<OperationRolledBack>());
      expect(harness.log.events, contains('recovery.rollback-envelope'));
      expect(harness.log.events, isNot(contains('control.seal-plan')));
    });

    test(
      'failure after sealing rolls back through the complete plan',
      () async {
        final harness = OperationHarness();
        harness.failures.failures.add('recovery.prepare:prepare-2');

        final outcome = await harness.createCoordinator().executeDeferred<void>(
          operationId: _operationId,
          expectedRepositoryRevision: RepositoryRevision.initial(),
          buildEnvelope: _envelope,
          prepareCandidate: (envelope, cancellationToken) async {},
          buildPlan: (envelope, preparedCandidate) =>
              _plan(envelope.operationId, envelope.expectedRepositoryRevision),
        );

        expect(outcome, isA<OperationRolledBack>());
        expect(harness.log.events, contains('control.seal-plan'));
        expect(harness.log.events, contains('recovery.rollback'));
        expect(
          harness.log.events,
          isNot(contains('recovery.rollback-envelope')),
        );
        expect(
          harness.controlPlane.journals.single.definition,
          isA<OperationPlan>(),
        );
      },
    );
  });

  group('OperationCoordinator.recover', () {
    test(
      'a pre-seal Prepared envelope rolls back without a full plan',
      () async {
        final harness = OperationHarness();
        final envelope = _envelope(_operationId, RepositoryRevision.initial());
        harness.controlPlane.seedPreparedEnvelope(
          envelope,
          OperationJournalPhase.prepared,
        );

        final report = await harness.createCoordinator().recover();

        expect(
          report.operations.single.disposition,
          RecoveredOperationDisposition.rolledBack,
        );
        expect(harness.log.events, contains('recovery.rollback-envelope'));
        expect(harness.log.events, contains('recovery.cleanup-envelope'));
        expect(harness.log.events, isNot(contains('recovery.rollback')));
        expect(harness.controlPlane.journals, isEmpty);
      },
    );

    test(
      'lock-held startup recovery does not acquire the Writer Lock',
      () async {
        final harness = OperationHarness();
        harness.controlPlane.seed(
          _plan(_operationId, RepositoryRevision.initial()),
          OperationJournalPhase.completed,
        );

        final report = await harness.createCoordinator().recoverUnderWriterLock(
          isolatedSkillIds: const {},
        );

        expect(
          report.operations.single.disposition,
          RecoveredOperationDisposition.cleanedCompleted,
        );
        expect(harness.log.events, isNot(contains('lock.acquire')));
        expect(harness.log.events, isNot(contains('lock.release')));
      },
    );

    for (final phase in <OperationJournalPhase>[
      OperationJournalPhase.prepared,
      OperationJournalPhase.applying,
    ]) {
      test('$phase rolls back and cleans up', () async {
        final harness = OperationHarness();
        final plan = _seededPlan(phase.index + 1);
        harness.controlPlane.seed(plan, phase);

        final report = await harness.createCoordinator().recover();

        expect(report.operations, hasLength(1));
        expect(
          report.operations.single.disposition,
          RecoveredOperationDisposition.rolledBack,
        );
        expect(harness.controlPlane.journals, isEmpty);
        expect(harness.log.events, <String>[
          'lock.acquire',
          'control.load-recoverable',
          'recovery.rollback',
          'control.rollback-complete',
          'recovery.cleanup',
          'control.delete-journal',
          'lock.release',
        ]);
      });
    }

    for (final phase in <OperationJournalPhase>[
      OperationJournalPhase.committed,
      OperationJournalPhase.finalizing,
    ]) {
      test('$phase rolls forward and cleans up', () async {
        final harness = OperationHarness();
        final plan = _seededPlan(phase.index + 1);
        harness.controlPlane.seed(plan, phase);

        final report = await harness.createCoordinator().recover();

        expect(
          report.operations.single.disposition,
          RecoveredOperationDisposition.rolledForward,
        );
        expect(harness.controlPlane.journals, isEmpty);
        final rollForwardReconciliation =
            harness.referenceMaintenance.observedEventPrefixes.single;
        expect(rollForwardReconciliation, contains('recovery.roll-forward'));
        expect(rollForwardReconciliation, isNot(contains('control.complete')));
        expect(harness.log.events, <String>[
          'lock.acquire',
          'control.load-recoverable',
          'control.finalizing',
          'recovery.roll-forward',
          'control.complete',
          'recovery.cleanup',
          'control.delete-journal',
          'lock.release',
        ]);
      });
    }

    test(
      'lock-held startup recovery forwards isolated Skills to ref maintenance',
      () async {
        final harness = OperationHarness();
        final plan = _seededPlan(41);
        final isolatedSkillId = ManagedSkillId(
          '10000000-0000-4000-8000-000000000041',
        );
        harness.controlPlane.seed(plan, OperationJournalPhase.committed);

        final report = await harness.createCoordinator().recoverUnderWriterLock(
          isolatedSkillIds: {isolatedSkillId},
        );

        expect(
          report.operations.single.disposition,
          RecoveredOperationDisposition.rolledForward,
        );
        expect(harness.referenceMaintenance.observedIsolatedSkillIds, [
          {isolatedSkillId},
        ]);
        expect(harness.referenceMaintenance.observedSelectedSkillIds, [
          {ManagedSkillId('20000000-0000-4000-8000-000000000001')},
        ]);
      },
    );

    test('Completed performs cleanup only', () async {
      final harness = OperationHarness();
      final plan = _seededPlan(5);
      harness.controlPlane.seed(plan, OperationJournalPhase.completed);

      final report = await harness.createCoordinator().recover();

      expect(
        report.operations.single.disposition,
        RecoveredOperationDisposition.cleanedCompleted,
      );
      expect(harness.log.events, isNot(contains('recovery.rollback')));
      expect(harness.log.events, isNot(contains('recovery.roll-forward')));
      expect(harness.log.events, contains('recovery.cleanup'));
      expect(harness.controlPlane.journals, isEmpty);
    });

    test('is idempotent when repeated after successful recovery', () async {
      final harness = OperationHarness();
      final plan = _seededPlan(6);
      harness.controlPlane.seed(plan, OperationJournalPhase.committed);
      final coordinator = harness.createCoordinator();

      final first = await coordinator.recover();
      harness.log.clear();
      final second = await coordinator.recover();

      expect(
        first.operations.single.disposition,
        RecoveredOperationDisposition.rolledForward,
      );
      expect(second.operations, isEmpty);
      expect(harness.log.events, <String>[
        'lock.acquire',
        'control.load-recoverable',
        'lock.release',
      ]);
    });

    test('keeps retryable state after a failed recovery attempt', () async {
      final harness = OperationHarness();
      final plan = _seededPlan(7);
      harness.controlPlane.seed(plan, OperationJournalPhase.applying);
      harness.failures.failures.add('recovery.rollback');
      final coordinator = harness.createCoordinator();

      final first = await coordinator.recover();
      expect(
        first.operations.single.disposition,
        RecoveredOperationDisposition.retryRequired,
      );
      expect(
        harness.controlPlane.journals.single.phase,
        OperationJournalPhase.applying,
      );

      harness.failures.failures.clear();
      final second = await coordinator.recover();
      expect(
        second.operations.single.disposition,
        RecoveredOperationDisposition.rolledBack,
      );
      expect(harness.controlPlane.journals, isEmpty);
    });

    test('retries cleanup from the persisted Completed phase', () async {
      final harness = OperationHarness();
      final plan = _seededPlan(10);
      harness.controlPlane.seed(plan, OperationJournalPhase.completed);
      harness.failures.failures.add('recovery.cleanup');
      final coordinator = harness.createCoordinator();

      final first = await coordinator.recover();
      expect(
        first.operations.single.disposition,
        RecoveredOperationDisposition.retryRequired,
      );
      expect(
        harness.controlPlane.journals.single.phase,
        OperationJournalPhase.completed,
      );

      harness.failures.failures.clear();
      final second = await coordinator.recover();
      expect(
        second.operations.single.disposition,
        RecoveredOperationDisposition.cleanedCompleted,
      );
      expect(harness.controlPlane.journals, isEmpty);
    });

    test('selects direction only from the persisted Journal phase', () async {
      final harness = OperationHarness();
      final applying = _seededPlan(8);
      final committed = _seededPlan(9);
      harness.controlPlane
        ..seed(applying, OperationJournalPhase.applying)
        ..seed(committed, OperationJournalPhase.committed);

      final report = await harness.createCoordinator().recover();

      expect(
        report.operations.map((operation) => operation.disposition),
        <RecoveredOperationDisposition>[
          RecoveredOperationDisposition.rolledBack,
          RecoveredOperationDisposition.rolledForward,
        ],
      );
      expect(
        harness.log.events.where((event) => event == 'recovery.rollback'),
        hasLength(1),
      );
      expect(
        harness.log.events.where((event) => event == 'recovery.roll-forward'),
        hasLength(1),
      );
    });
  });
}

OperationPlan _seededPlan(int seed) {
  final suffix = seed.toString().padLeft(12, '0');
  return _plan(
    OperationId('10000000-0000-4000-8000-$suffix'),
    RepositoryRevision(seed),
  );
}

OperationPlan _plan(
  OperationId operationId,
  RepositoryRevision currentRevision, {
  bool destructive = false,
}) {
  final subject = OperationSubjectPlan(
    reference: OperationSubjectReference(
      operationId: operationId,
      subjectId: '30000000-0000-4000-8000-000000000001',
    ),
    managedSkillId: ManagedSkillId('20000000-0000-4000-8000-000000000001'),
    displayName: 'Example Skill',
    sourceLineage: SourceLineageReference('lineage-1'),
  );
  return OperationPlan(
    operationId: operationId,
    expectedRepositoryRevision: currentRevision,
    committedRepositoryRevision: currentRevision.next(),
    operationGeneration: 1,
    preparationSteps: <PreparationOperationStep>[
      PreparationOperationStep(
        stepId: 'prepare-1',
        recoveryReference: RecoveryReference('prepare-ref-1'),
        kind: PreparationStepKind.revisionCandidate,
      ),
      PreparationOperationStep(
        stepId: 'prepare-2',
        recoveryReference: RecoveryReference('prepare-ref-2'),
        kind: PreparationStepKind.durabilityVerification,
      ),
    ],
    applyingSteps: <ApplyingOperationStep>[
      ApplyingOperationStep(
        stepId: 'apply-1',
        recoveryReference: RecoveryReference('apply-ref-1'),
        kind: ApplyingStepKind.materializationReplacement,
      ),
      ApplyingOperationStep(
        stepId: 'apply-2',
        recoveryReference: RecoveryReference('apply-ref-2'),
        kind: ApplyingStepKind.materializationReplacement,
      ),
    ],
    finalizationSteps: <FinalizationOperationStep>[
      FinalizationOperationStep(
        stepId: 'finalize-1',
        recoveryReference: RecoveryReference('finalize-ref-1'),
        kind: FinalizationStepKind.retentionReconciliation,
      ),
      FinalizationOperationStep(
        stepId: 'finalize-2',
        recoveryReference: RecoveryReference('finalize-ref-2'),
        kind: FinalizationStepKind.stagingCleanup,
      ),
    ],
    revisionSelectionChanges: <RevisionSelectionChangePlan>[
      RevisionSelectionChangePlan(
        managedSkillId: subject.managedSkillId,
        previousUpstream: RevisionAddress(
          sourceLineage: subject.sourceLineage!,
          objectId: RevisionObjectId(
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ),
        previousEffective: RevisionAddress(
          sourceLineage: subject.sourceLineage!,
          objectId: RevisionObjectId(
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ),
        ),
        intendedUpstream: RevisionAddress(
          sourceLineage: subject.sourceLineage!,
          objectId: RevisionObjectId(
            'cccccccccccccccccccccccccccccccccccccccc',
          ),
        ),
        intendedEffective: RevisionAddress(
          sourceLineage: subject.sourceLineage!,
          objectId: RevisionObjectId(
            'dddddddddddddddddddddddddddddddddddddddd',
          ),
        ),
      ),
    ],
    businessChanges: WorkspaceBusinessChangeSet(
      incrementsDestructionEpoch: destructive,
    ),
    record: OperationRecordPlan(
      operationId: operationId,
      kind: 'test-operation',
      subjects: <OperationSubjectPlan>[subject],
    ),
  );
}

PreparedOperationEnvelope _envelope(
  OperationId operationId,
  RepositoryRevision currentRevision,
) => PreparedOperationEnvelope(
  operationId: operationId,
  expectedRepositoryRevision: currentRevision,
  committedRepositoryRevision: currentRevision.next(),
  operationGeneration: 1,
  preparationSteps: <PreparationOperationStep>[
    PreparationOperationStep(
      stepId: 'prepare-1',
      recoveryReference: RecoveryReference('prepare-ref-1'),
      kind: PreparationStepKind.revisionCandidate,
    ),
  ],
  record: OperationRecordPlan(
    operationId: operationId,
    kind: 'test-operation',
    retainWithoutSubjects: true,
    subjects: const <OperationSubjectPlan>[],
  ),
);

final class _SelfDescribingFailure
    implements Exception, OperationAbortDetailSource {
  const _SelfDescribingFailure(this.abortDetail);

  @override
  final OperationAbortDetail abortDetail;
}
