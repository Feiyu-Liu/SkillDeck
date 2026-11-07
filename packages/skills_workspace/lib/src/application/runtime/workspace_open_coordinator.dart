import 'dart:async';
import 'dart:developer' as developer;

import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../backup/control_plane_backup_models.dart';
import '../ports/operation_ports.dart';
import '../ports/workspace_lifecycle_ports.dart';
import 'workspace_open_models.dart';

/// Serializes fail-closed Workspace startup and deterministic shutdown.
///
/// All startup maintenance runs under one Workspace Writer Lock. The request
/// gate opens only after the first Snapshot has been read and published.
final class WorkspaceOpenCoordinator {
  WorkspaceOpenCoordinator({
    required WorkspaceWriterLockPort writerLock,
    required WorkspaceStartupRecoveryPort startupRecovery,
    required WorkspaceControlPlaneLifecyclePort controlPlane,
    required WorkspaceRevisionWorkerLifecyclePort revisionWorker,
    required WorkspaceRevisionMaintenancePort revisionMaintenance,
    required WorkspaceJournalRecoveryPort journalRecovery,
    required WorkspaceDerivedStateReconcilerPort reconciler,
    required WorkspaceSnapshotLifecyclePort snapshots,
    required WorkspaceRequestGatePort requestGate,
  }) : _writerLock = writerLock,
       _startupRecovery = startupRecovery,
       _controlPlane = controlPlane,
       _revisionWorker = revisionWorker,
       _revisionMaintenance = revisionMaintenance,
       _journalRecovery = journalRecovery,
       _reconciler = reconciler,
       _snapshots = snapshots,
       _requestGate = requestGate;

  final WorkspaceWriterLockPort _writerLock;
  final WorkspaceStartupRecoveryPort _startupRecovery;
  final WorkspaceControlPlaneLifecyclePort _controlPlane;
  final WorkspaceRevisionWorkerLifecyclePort _revisionWorker;
  final WorkspaceRevisionMaintenancePort _revisionMaintenance;
  final WorkspaceJournalRecoveryPort _journalRecovery;
  final WorkspaceDerivedStateReconcilerPort _reconciler;
  final WorkspaceSnapshotLifecyclePort _snapshots;
  final WorkspaceRequestGatePort _requestGate;

  WorkspaceRuntimeState _state = WorkspaceRuntimeState.closed;
  Future<WorkspaceOpenOutcome>? _opening;
  Future<WorkspaceCloseOutcome>? _closing;
  WorkspaceOpened? _opened;
  WorkspaceWriterLease? _writerLease;
  bool _controlPlaneOpened = false;
  bool _revisionWorkerStarted = false;
  bool _snapshotPublished = false;
  bool _requestGateOpened = false;
  bool _disposed = false;

  WorkspaceRuntimeState get state => _state;

  bool get isOpen => _state == WorkspaceRuntimeState.open;

  WorkspaceOpened? get opened => _opened;

  Future<WorkspaceOpenOutcome> open() {
    if (_disposed) {
      return Future.value(
        WorkspaceOpenFailed(code: WorkspaceOpenFailureCode.repositoryClosed),
      );
    }
    switch (_state) {
      case WorkspaceRuntimeState.open:
        return Future.value(_opened!);
      case WorkspaceRuntimeState.opening:
        return _opening!;
      case WorkspaceRuntimeState.closing:
        return _closing!.then((_) => open());
      case WorkspaceRuntimeState.closed:
        final future = _runOpen();
        _opening = future;
        return future;
    }
  }

  Future<WorkspaceCloseOutcome> close() {
    final existing = _closing;
    if (existing != null) return existing;

    final completer = Completer<WorkspaceCloseOutcome>();
    _closing = completer.future;
    unawaited(() async {
      try {
        final opening = _opening;
        if (_state == WorkspaceRuntimeState.opening && opening != null) {
          await opening;
        }

        final WorkspaceCloseOutcome outcome;
        if (_state == WorkspaceRuntimeState.open) {
          outcome = await _runClose();
        } else if (_disposed) {
          outcome = const WorkspaceClosed(alreadyClosed: true);
        } else {
          outcome = await _disposeUnopened();
        }
        completer.complete(outcome);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _closing = null;
      }
    }());
    return completer.future;
  }

  Future<WorkspaceOpenOutcome> _runOpen() async {
    _state = WorkspaceRuntimeState.opening;
    WorkspaceOpenFailureCode? failure;
    ControlPlaneBackupFailureCode? controlPlaneFailure;
    ControlPlaneStartupResult? primaryRecovery;
    final recoveredSkillIds = <ManagedSkillId>{};
    final isolatedSkillIds = <ManagedSkillId>{};
    final selectedSkillIds = <ManagedSkillId>{};

    try {
      try {
        _writerLease = await _tracePhase('writerLock', _writerLock.acquire);
      } on Object {
        failure = WorkspaceOpenFailureCode.writerLockUnavailable;
      }
      if (failure != null) {
        return await _finishFailedOpen(failure);
      }

      try {
        primaryRecovery = await _tracePhase(
          'controlPlaneRecovery',
          _startupRecovery.recoverPrimaryForStartup,
        );
      } on Object {
        failure = WorkspaceOpenFailureCode.controlPlaneRecoveryBlocked;
      }
      if (primaryRecovery case ControlPlaneStartupBlocked(:final code)) {
        failure = WorkspaceOpenFailureCode.controlPlaneRecoveryBlocked;
        controlPlaneFailure = code;
      }
      if (failure != null) {
        return await _finishFailedOpen(
          failure,
          controlPlaneFailure: controlPlaneFailure,
        );
      }

      try {
        await _tracePhase('controlPlaneOpen', _controlPlane.open);
        _controlPlaneOpened = true;
      } on Object {
        failure = WorkspaceOpenFailureCode.controlPlaneOpenFailed;
      }
      if (failure != null) return await _finishFailedOpen(failure);

      try {
        await _tracePhase('revisionWorkerStartup', _revisionWorker.start);
        _revisionWorkerStarted = true;
      } on Object {
        failure = WorkspaceOpenFailureCode.revisionWorkerStartupFailed;
      }
      if (failure != null) return await _finishFailedOpen(failure);

      try {
        await _tracePhase<void>('revisionMaintenance', () async {
          final selections = await _revisionMaintenance.selectedRevisions();
          for (final selection in selections) {
            selectedSkillIds.add(selection.managedSkillId);
            final result = await _revisionMaintenance.validateOrRecover(
              selection,
            );
            if (result.managedSkillId != selection.managedSkillId) {
              throw StateError('Revision maintenance changed Skill identity.');
            }
            switch (result.disposition) {
              case WorkspaceRevisionMaintenanceDisposition.healthy:
                break;
              case WorkspaceRevisionMaintenanceDisposition.recoveredFromBundle:
                recoveredSkillIds.add(result.managedSkillId);
              case WorkspaceRevisionMaintenanceDisposition.isolatedCorrupt:
                isolatedSkillIds.add(result.managedSkillId);
            }
          }
        });
      } on Object {
        failure = WorkspaceOpenFailureCode.revisionMaintenanceFailed;
      }
      if (failure != null) return await _finishFailedOpen(failure);

      try {
        await _tracePhase<void>(
          'journalRecovery',
          () => _journalRecovery.recoverUnderWriterLock(
            armedBarrier: switch (primaryRecovery) {
              ControlPlaneArmedBarrierNeedsResolution(:final eligibility) =>
                eligibility,
              _ => null,
            },
            isolatedSkillIds: Set.unmodifiable(isolatedSkillIds),
          ),
        );
      } on Object {
        failure = WorkspaceOpenFailureCode.journalRecoveryFailed;
      }
      if (failure != null) return await _finishFailedOpen(failure);

      try {
        await _tracePhase<void>(
          'revisionReferenceReconciliation',
          () => _reconciler.reconcileRevisionReferences(
            isolatedSkillIds: Set.unmodifiable(isolatedSkillIds),
          ),
        );
      } on Object {
        failure =
            WorkspaceOpenFailureCode.revisionReferenceReconciliationFailed;
      }
      if (failure != null) return await _finishFailedOpen(failure);

      final integrity = _integrity(
        primaryRecovery: primaryRecovery!,
        selectedSkillIds: selectedSkillIds,
        recoveredSkillIds: recoveredSkillIds,
        isolatedSkillIds: isolatedSkillIds,
      );
      late final RepositorySnapshot snapshot;
      try {
        snapshot = await _tracePhase(
          'snapshotRead',
          () => _snapshots.readInitial(integrity: integrity),
        );
      } on Object {
        failure = WorkspaceOpenFailureCode.snapshotReadFailed;
      }
      if (failure != null) return await _finishFailedOpen(failure);

      try {
        await _tracePhase(
          'snapshotPublication',
          () => _snapshots.publishInitial(snapshot),
        );
        _snapshotPublished = true;
      } on Object {
        failure = WorkspaceOpenFailureCode.snapshotPublicationFailed;
      }
      if (failure != null) return await _finishFailedOpen(failure);

      try {
        await _tracePhase('requestGateOpen', _requestGate.openForRequests);
        _requestGateOpened = true;
      } on Object {
        failure = WorkspaceOpenFailureCode.requestGateOpenFailed;
      }
      if (failure != null) return await _finishFailedOpen(failure);

      final opened = WorkspaceOpened(
        snapshot: snapshot,
        primaryRecovery: primaryRecovery,
        recoveredSkillIds: recoveredSkillIds,
        isolatedSkillIds: isolatedSkillIds,
      );
      _opened = opened;
      _state = WorkspaceRuntimeState.open;
      return opened;
    } finally {
      _opening = null;
    }
  }

  Future<T> _tracePhase<T>(String phase, Future<T> Function() operation) async {
    final task = developer.TimelineTask()
      ..start('skills_workspace.open.$phase');
    final stopwatch = Stopwatch()..start();
    try {
      final result = await operation();
      stopwatch.stop();
      task.finish(
        arguments: <String, Object>{
          'elapsedMicros': stopwatch.elapsedMicroseconds,
          'failed': false,
        },
      );
      return result;
    } on Object {
      stopwatch.stop();
      task.finish(
        arguments: <String, Object>{
          'elapsedMicros': stopwatch.elapsedMicroseconds,
          'failed': true,
        },
      );
      rethrow;
    }
  }

  Future<WorkspaceOpenFailed> _finishFailedOpen(
    WorkspaceOpenFailureCode failure, {
    ControlPlaneBackupFailureCode? controlPlaneFailure,
  }) async {
    final cleanupFailures = await _cleanupOpenedResources(
      disposeRequestGate: false,
    );
    _opened = null;
    _state = WorkspaceRuntimeState.closed;
    return WorkspaceOpenFailed(
      code: failure,
      controlPlaneFailure: controlPlaneFailure,
      cleanupFailures: cleanupFailures,
    );
  }

  Future<WorkspaceCloseOutcome> _runClose() async {
    _state = WorkspaceRuntimeState.closing;
    final failures = await _cleanupOpenedResources(disposeRequestGate: true);
    _opened = null;
    _disposed = true;
    _state = WorkspaceRuntimeState.closed;
    return failures.isEmpty
        ? const WorkspaceClosed(alreadyClosed: false)
        : WorkspaceCloseFailed(failures);
  }

  Future<WorkspaceCloseOutcome> _disposeUnopened() async {
    _state = WorkspaceRuntimeState.closing;
    final failures = <WorkspaceShutdownStep>[];
    await _captureShutdownFailure(
      WorkspaceShutdownStep.closeSnapshots,
      _snapshots.close,
      failures,
    );
    await _captureShutdownFailure(
      WorkspaceShutdownStep.closeControlPlane,
      _controlPlane.close,
      failures,
    );
    await _captureShutdownFailure(
      WorkspaceShutdownStep.closeRequestGate,
      _requestGate.close,
      failures,
    );
    _disposed = true;
    _state = WorkspaceRuntimeState.closed;
    return failures.isEmpty
        ? const WorkspaceClosed(alreadyClosed: false)
        : WorkspaceCloseFailed(failures);
  }

  Future<List<WorkspaceShutdownStep>> _cleanupOpenedResources({
    required bool disposeRequestGate,
  }) async {
    final failures = <WorkspaceShutdownStep>[];
    if (_requestGateOpened) {
      await _captureShutdownFailure(
        WorkspaceShutdownStep.stopRequests,
        _requestGate.stopAccepting,
        failures,
      );
      await _captureShutdownFailure(
        WorkspaceShutdownStep.settleRequests,
        _requestGate.settleInFlightByCommitState,
        failures,
      );
      _requestGateOpened = false;
    }
    if (_snapshotPublished) {
      await _captureShutdownFailure(
        WorkspaceShutdownStep.closeSnapshots,
        _snapshots.close,
        failures,
      );
      _snapshotPublished = false;
    }
    if (_revisionWorkerStarted) {
      await _captureShutdownFailure(
        WorkspaceShutdownStep.closeRevisionWorker,
        _revisionWorker.close,
        failures,
      );
      _revisionWorkerStarted = false;
    }
    if (_controlPlaneOpened) {
      await _captureShutdownFailure(
        WorkspaceShutdownStep.closeControlPlane,
        _controlPlane.close,
        failures,
      );
      _controlPlaneOpened = false;
    }
    if (disposeRequestGate) {
      await _captureShutdownFailure(
        WorkspaceShutdownStep.closeRequestGate,
        _requestGate.close,
        failures,
      );
    }
    final lease = _writerLease;
    _writerLease = null;
    if (lease != null) {
      await _captureShutdownFailure(
        WorkspaceShutdownStep.releaseWriterLock,
        lease.release,
        failures,
      );
    }
    return failures;
  }
}

WorkspaceIntegrity _integrity({
  required ControlPlaneStartupResult primaryRecovery,
  required Set<ManagedSkillId> selectedSkillIds,
  required Set<ManagedSkillId> recoveredSkillIds,
  required Set<ManagedSkillId> isolatedSkillIds,
}) {
  final skillStates =
      <ManagedSkillIntegrity>[
        for (final skillId in selectedSkillIds)
          if (!recoveredSkillIds.contains(skillId) &&
              !isolatedSkillIds.contains(skillId))
            ManagedSkillIntegrity(
              managedSkillId: skillId,
              status: SkillIntegrityStatus.unverified,
            ),
        for (final skillId in recoveredSkillIds)
          ManagedSkillIntegrity(
            managedSkillId: skillId,
            status: SkillIntegrityStatus.recovered,
          ),
        for (final skillId in isolatedSkillIds)
          ManagedSkillIntegrity(
            managedSkillId: skillId,
            status: SkillIntegrityStatus.revisionStoreCorrupt,
          ),
      ]..sort(
        (left, right) =>
            left.managedSkillId.value.compareTo(right.managedSkillId.value),
      );
  return WorkspaceIntegrity(
    status:
        primaryRecovery is ControlPlanePrimaryRestored ||
            recoveredSkillIds.isNotEmpty
        ? WorkspaceIntegrityStatus.recovered
        : WorkspaceIntegrityStatus.healthy,
    skills: skillStates,
  );
}

Future<void> _captureShutdownFailure(
  WorkspaceShutdownStep step,
  Future<void> Function() action,
  List<WorkspaceShutdownStep> failures,
) async {
  try {
    await action();
  } on Object {
    failures.add(step);
  }
}
