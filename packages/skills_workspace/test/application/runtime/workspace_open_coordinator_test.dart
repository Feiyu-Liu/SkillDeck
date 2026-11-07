import 'dart:async';

import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/workspace_open_coordinator.dart';
import 'package:skills_workspace/src/application/runtime/workspace_open_models.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/lock_wait_policy.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

void main() {
  test(
    'shares concurrent open and performs startup exactly once in order',
    () async {
      final harness = _Harness();
      harness.startup.block = Completer<void>();

      final first = harness.coordinator.open();
      final second = harness.coordinator.open();

      expect(identical(first, second), isTrue);
      await harness.startup.entered.future;
      expect(harness.calls, ['lock.acquire', 'primary.recover']);

      harness.startup.block!.complete();
      final outcome = await first;

      expect(outcome, isA<WorkspaceOpened>());
      expect(await second, same(outcome));
      expect(harness.coordinator.state, WorkspaceRuntimeState.open);
      expect(harness.calls, [
        'lock.acquire',
        'primary.recover',
        'controlPlane.open',
        'worker.start',
        'revision.enumerate',
        'journal.recover',
        'reconcile.references',
        'snapshot.read',
        'snapshot.publish',
        'gate.open',
      ]);

      final repeated = await harness.coordinator.open();
      expect(repeated, same(outcome));
      expect(
        harness.calls.where((call) => call == 'worker.start'),
        hasLength(1),
      );
      await harness.coordinator.close();
    },
  );

  test(
    'fails closed when primary and eligible backup are unavailable',
    () async {
      final harness = _Harness();
      harness.startup.result = const ControlPlaneStartupBlocked(
        ControlPlaneBackupFailureCode.noEligibleBackup,
      );

      final outcome = await harness.coordinator.open();

      expect(
        outcome,
        isA<WorkspaceOpenFailed>()
            .having(
              (failure) => failure.code,
              'code',
              WorkspaceOpenFailureCode.controlPlaneRecoveryBlocked,
            )
            .having(
              (failure) => failure.controlPlaneFailure,
              'controlPlaneFailure',
              ControlPlaneBackupFailureCode.noEligibleBackup,
            ),
      );
      expect(harness.calls, [
        'lock.acquire',
        'primary.recover',
        'lock.release',
      ]);
      expect(harness.coordinator.state, WorkspaceRuntimeState.closed);
    },
  );

  test('direct close releases the unopened Control Plane owner', () async {
    final harness = _Harness();

    expect(
      await harness.coordinator.close(),
      isA<WorkspaceClosed>().having(
        (closed) => closed.alreadyClosed,
        'alreadyClosed',
        isFalse,
      ),
    );
    expect(harness.calls, [
      'snapshot.close',
      'controlPlane.close',
      'gate.close',
    ]);
    expect(harness.coordinator.state, WorkspaceRuntimeState.closed);
    expect(
      await harness.coordinator.open(),
      isA<WorkspaceOpenFailed>().having(
        (failure) => failure.code,
        'code',
        WorkspaceOpenFailureCode.repositoryClosed,
      ),
    );
  });

  test(
    'isolates only a Skill whose Store and Bundle are both corrupt',
    () async {
      final skillId = _skillId(1);
      final harness = _Harness(
        revisionResults: {
          skillId: WorkspaceRevisionMaintenanceDisposition.isolatedCorrupt,
        },
      );

      final outcome = await harness.coordinator.open() as WorkspaceOpened;

      expect(outcome.isolatedSkillIds, {skillId});
      expect(
        outcome.snapshot.integrity.status,
        WorkspaceIntegrityStatus.healthy,
      );
      expect(outcome.snapshot.integrity.skills, [
        ManagedSkillIntegrity(
          managedSkillId: skillId,
          status: SkillIntegrityStatus.revisionStoreCorrupt,
        ),
      ]);
      expect(harness.reconciler.referenceIsolatedSkillIds, {skillId});
      expect(harness.journal.isolatedSkillIds, {skillId});
      expect(
        harness.calls.indexOf('revision.maintain:${skillId.value}'),
        lessThan(harness.calls.indexOf('journal.recover')),
      );
      await harness.coordinator.close();
    },
  );

  test('reports verified Bundle restoration in the initial Snapshot', () async {
    final skillId = _skillId(2);
    final harness = _Harness(
      revisionResults: {
        skillId: WorkspaceRevisionMaintenanceDisposition.recoveredFromBundle,
      },
    );

    final outcome = await harness.coordinator.open() as WorkspaceOpened;

    expect(outcome.recoveredSkillIds, {skillId});
    expect(
      outcome.snapshot.integrity.status,
      WorkspaceIntegrityStatus.recovered,
    );
    expect(
      outcome.snapshot.integrity.skills.single.status,
      SkillIntegrityStatus.recovered,
    );
    await harness.coordinator.close();
  });

  test(
    'passes an armed destructive barrier only to lock-held Journal recovery',
    () async {
      final harness = _Harness();
      final armed = ArmedBackupEligibility(
        operationId: 'operation',
        previousDestructionEpoch: 4,
        intendedDestructionEpoch: 5,
        previousSteadyRepositoryRevision: 8,
        armedAtRepositoryRevision: 10,
      );
      harness.startup.result = ControlPlaneArmedBarrierNeedsResolution(
        identity: const ControlPlaneIdentity(
          schemaVersion: 1,
          repositoryRevision: 10,
          destructionEpoch: 4,
        ),
        eligibility: armed,
      );

      final outcome = await harness.coordinator.open();

      expect(outcome, isA<WorkspaceOpened>());
      expect(harness.journal.armedBarrier, same(armed));
      expect(
        harness.calls.where((call) => call == 'lock.acquire'),
        hasLength(1),
      );
      await harness.coordinator.close();
    },
  );

  test('cleans up Control Plane when Revision worker startup fails', () async {
    final harness = _Harness();
    harness.worker.failStart = true;

    final outcome = await harness.coordinator.open();

    expect(
      outcome,
      isA<WorkspaceOpenFailed>().having(
        (failure) => failure.code,
        'code',
        WorkspaceOpenFailureCode.revisionWorkerStartupFailed,
      ),
    );
    expect(harness.calls, [
      'lock.acquire',
      'primary.recover',
      'controlPlane.open',
      'worker.start',
      'controlPlane.close',
      'lock.release',
    ]);
  });

  test(
    'maps worker termination during maintenance and releases resources',
    () async {
      final skillId = _skillId(3);
      final harness = _Harness(
        revisionResults: {
          skillId: WorkspaceRevisionMaintenanceDisposition.healthy,
        },
      );
      harness.revisionMaintenance.failValidation = true;

      final outcome = await harness.coordinator.open();

      expect(
        outcome,
        isA<WorkspaceOpenFailed>().having(
          (failure) => failure.code,
          'code',
          WorkspaceOpenFailureCode.revisionMaintenanceFailed,
        ),
      );
      expect(harness.calls.takeLast(3), [
        'worker.close',
        'controlPlane.close',
        'lock.release',
      ]);
    },
  );

  test(
    'does not publish or admit requests before maintenance completes',
    () async {
      final harness = _Harness();
      harness.journal.block = Completer<void>();

      final opening = harness.coordinator.open();
      await harness.journal.entered.future;

      expect(harness.calls, isNot(contains('snapshot.read')));
      expect(harness.calls, isNot(contains('snapshot.publish')));
      expect(harness.calls, isNot(contains('gate.open')));

      harness.journal.block!.complete();
      expect(await opening, isA<WorkspaceOpened>());
      expect(
        harness.calls.indexOf('snapshot.publish'),
        lessThan(harness.calls.indexOf('gate.open')),
      );
      await harness.coordinator.close();
    },
  );

  test('close drains in-flight work before reverse-order shutdown', () async {
    final harness = _Harness();
    expect(await harness.coordinator.open(), isA<WorkspaceOpened>());
    harness.calls.clear();
    harness.gate.settleBlock = Completer<void>();

    final first = harness.coordinator.close();
    final second = harness.coordinator.close();
    expect(identical(first, second), isTrue);
    await harness.gate.settleEntered.future;

    expect(harness.calls, ['gate.stop', 'gate.settle']);
    expect(harness.snapshot.closed, isFalse);
    expect(harness.worker.closed, isFalse);

    harness.gate.settleBlock!.complete();
    expect(
      await first,
      isA<WorkspaceClosed>().having(
        (closed) => closed.alreadyClosed,
        'alreadyClosed',
        isFalse,
      ),
    );
    expect(await second, isA<WorkspaceClosed>());
    expect(harness.calls, [
      'gate.stop',
      'gate.settle',
      'snapshot.close',
      'worker.close',
      'controlPlane.close',
      'gate.close',
      'lock.release',
    ]);
    expect(harness.snapshot.closed, isTrue);
    expect(harness.coordinator.state, WorkspaceRuntimeState.closed);

    final callsAfterClose = List<String>.of(harness.calls);
    expect(
      await harness.coordinator.close(),
      isA<WorkspaceClosed>().having(
        (closed) => closed.alreadyClosed,
        'alreadyClosed',
        isTrue,
      ),
    );
    expect(harness.calls, callsAfterClose);
    expect(
      await harness.coordinator.open(),
      isA<WorkspaceOpenFailed>().having(
        (failure) => failure.code,
        'code',
        WorkspaceOpenFailureCode.repositoryClosed,
      ),
    );
    expect(harness.calls, callsAfterClose);
  });

  test(
    'gate-open failure closes published stream before workers and lock',
    () async {
      final harness = _Harness();
      harness.gate.failOpen = true;

      final outcome = await harness.coordinator.open();

      expect(
        outcome,
        isA<WorkspaceOpenFailed>().having(
          (failure) => failure.code,
          'code',
          WorkspaceOpenFailureCode.requestGateOpenFailed,
        ),
      );
      expect(harness.calls.takeLast(4), [
        'snapshot.close',
        'worker.close',
        'controlPlane.close',
        'lock.release',
      ]);
      expect(harness.snapshot.closed, isTrue);
    },
  );
}

ManagedSkillId _skillId(int suffix) => ManagedSkillId(
  '123e4567-e89b-42d3-a456-${suffix.toString().padLeft(12, '0')}',
);

extension<T> on Iterable<T> {
  List<T> takeLast(int count) => skip(length - count).toList(growable: false);
}

final class _Harness {
  _Harness({
    Map<ManagedSkillId, WorkspaceRevisionMaintenanceDisposition>
        revisionResults =
        const {},
  }) {
    lock = _FakeWriterLock(calls);
    startup = _FakeStartupRecovery(calls);
    controlPlane = _FakeControlPlane(calls);
    worker = _FakeRevisionWorker(calls);
    revisionMaintenance = _FakeRevisionMaintenance(calls, revisionResults);
    journal = _FakeJournalRecovery(calls);
    reconciler = _FakeReconciler(calls);
    snapshot = _FakeSnapshots(calls);
    gate = _FakeRequestGate(calls);
    coordinator = WorkspaceOpenCoordinator(
      writerLock: lock,
      startupRecovery: startup,
      controlPlane: controlPlane,
      revisionWorker: worker,
      revisionMaintenance: revisionMaintenance,
      journalRecovery: journal,
      reconciler: reconciler,
      snapshots: snapshot,
      requestGate: gate,
    );
  }

  final List<String> calls = [];
  late final _FakeWriterLock lock;
  late final _FakeStartupRecovery startup;
  late final _FakeControlPlane controlPlane;
  late final _FakeRevisionWorker worker;
  late final _FakeRevisionMaintenance revisionMaintenance;
  late final _FakeJournalRecovery journal;
  late final _FakeReconciler reconciler;
  late final _FakeSnapshots snapshot;
  late final _FakeRequestGate gate;
  late final WorkspaceOpenCoordinator coordinator;
}

final class _FakeWriterLock implements WorkspaceWriterLockPort {
  _FakeWriterLock(this.calls);

  final List<String> calls;

  @override
  Future<WorkspaceWriterLease> acquire({LockWaitPolicy? waitPolicy}) async {
    calls.add('lock.acquire');
    return _FakeWriterLease(calls);
  }
}

final class _FakeWriterLease implements WorkspaceWriterLease {
  _FakeWriterLease(this.calls);

  final List<String> calls;
  bool released = false;

  @override
  Future<void> release() async {
    if (released) return;
    released = true;
    calls.add('lock.release');
  }
}

final class _FakeStartupRecovery implements WorkspaceStartupRecoveryPort {
  _FakeStartupRecovery(this.calls);

  final List<String> calls;
  final Completer<void> entered = Completer<void>();
  Completer<void>? block;
  ControlPlaneStartupResult result = const ControlPlanePrimaryReady(
    ControlPlaneIdentity(
      schemaVersion: 1,
      repositoryRevision: 0,
      destructionEpoch: 0,
    ),
  );

  @override
  Future<ControlPlaneStartupResult> recoverPrimaryForStartup() async {
    calls.add('primary.recover');
    if (!entered.isCompleted) entered.complete();
    await block?.future;
    return result;
  }
}

final class _FakeControlPlane implements WorkspaceControlPlaneLifecyclePort {
  _FakeControlPlane(this.calls);

  final List<String> calls;

  @override
  Future<void> open() async => calls.add('controlPlane.open');

  @override
  Future<void> close() async => calls.add('controlPlane.close');
}

final class _FakeRevisionWorker
    implements WorkspaceRevisionWorkerLifecyclePort {
  _FakeRevisionWorker(this.calls);

  final List<String> calls;
  bool failStart = false;
  bool closed = false;

  @override
  Future<void> start() async {
    calls.add('worker.start');
    if (failStart) throw StateError('startup failed');
  }

  @override
  Future<void> close() async {
    calls.add('worker.close');
    closed = true;
  }
}

final class _FakeSelectedRevision implements WorkspaceSelectedRevision {
  const _FakeSelectedRevision(this.managedSkillId);

  @override
  final ManagedSkillId managedSkillId;
}

final class _FakeRevisionMaintenance
    implements WorkspaceRevisionMaintenancePort {
  _FakeRevisionMaintenance(this.calls, this.results);

  final List<String> calls;
  final Map<ManagedSkillId, WorkspaceRevisionMaintenanceDisposition> results;
  bool failValidation = false;

  @override
  Future<List<WorkspaceSelectedRevision>> selectedRevisions() async {
    calls.add('revision.enumerate');
    return [for (final skillId in results.keys) _FakeSelectedRevision(skillId)];
  }

  @override
  Future<WorkspaceRevisionMaintenanceResult> validateOrRecover(
    WorkspaceSelectedRevision selectedRevision,
  ) async {
    calls.add('revision.maintain:${selectedRevision.managedSkillId.value}');
    if (failValidation) throw StateError('worker terminated');
    return WorkspaceRevisionMaintenanceResult(
      managedSkillId: selectedRevision.managedSkillId,
      disposition: results[selectedRevision.managedSkillId]!,
    );
  }
}

final class _FakeJournalRecovery implements WorkspaceJournalRecoveryPort {
  _FakeJournalRecovery(this.calls);

  final List<String> calls;
  final Completer<void> entered = Completer<void>();
  Completer<void>? block;
  ArmedBackupEligibility? armedBarrier;
  Set<ManagedSkillId> isolatedSkillIds = const {};

  @override
  Future<void> recoverUnderWriterLock({
    ArmedBackupEligibility? armedBarrier,
    required Set<ManagedSkillId> isolatedSkillIds,
  }) async {
    calls.add('journal.recover');
    this.armedBarrier = armedBarrier;
    this.isolatedSkillIds = Set.of(isolatedSkillIds);
    if (!entered.isCompleted) entered.complete();
    await block?.future;
  }
}

final class _FakeReconciler implements WorkspaceDerivedStateReconcilerPort {
  _FakeReconciler(this.calls);

  final List<String> calls;
  Set<ManagedSkillId> isolatedSkillIds = const {};
  Set<ManagedSkillId> referenceIsolatedSkillIds = const {};

  @override
  Future<void> reconcileRevisionReferences({
    required Set<ManagedSkillId> isolatedSkillIds,
  }) async {
    calls.add('reconcile.references');
    referenceIsolatedSkillIds = Set.of(isolatedSkillIds);
  }

  @override
  Future<WorkspaceMaterializationReconciliationReport>
  reconcileMaterializations({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
    bool repairMismatching = true,
    bool repairMissing = true,
  }) async {
    calls.add('reconcile.materializations');
    this.isolatedSkillIds = Set.of(isolatedSkillIds);
    return const WorkspaceMaterializationReconciliationReport(
      inspectedArtifactCount: 0,
      inspectedFileCount: 0,
      inspectedByteCount: 0,
      repairedArtifactCount: 0,
      inspectionElapsed: Duration.zero,
      repairElapsed: Duration.zero,
    );
  }
}

final class _FakeSnapshots implements WorkspaceSnapshotLifecyclePort {
  _FakeSnapshots(this.calls);

  final List<String> calls;
  bool closed = false;

  @override
  Future<RepositorySnapshot> readInitial({
    required WorkspaceIntegrity integrity,
  }) async {
    calls.add('snapshot.read');
    return RepositorySnapshot(
      revision: RepositoryRevision.initial(),
      integrity: integrity,
    );
  }

  @override
  Future<void> publishInitial(RepositorySnapshot snapshot) async {
    if (closed) throw StateError('snapshot stream is closed');
    calls.add('snapshot.publish');
  }

  @override
  Future<void> close() async {
    if (closed) return;
    calls.add('snapshot.close');
    closed = true;
  }
}

final class _FakeRequestGate implements WorkspaceRequestGatePort {
  _FakeRequestGate(this.calls);

  final List<String> calls;
  final Completer<void> settleEntered = Completer<void>();
  Completer<void>? settleBlock;
  bool failOpen = false;

  @override
  Future<void> openForRequests() async {
    calls.add('gate.open');
    if (failOpen) throw StateError('gate failed');
  }

  @override
  Future<void> stopAccepting() async => calls.add('gate.stop');

  @override
  Future<void> settleInFlightByCommitState() async {
    calls.add('gate.settle');
    if (!settleEntered.isCompleted) settleEntered.complete();
    await settleBlock?.future;
  }

  @override
  Future<void> close() async => calls.add('gate.close');
}
