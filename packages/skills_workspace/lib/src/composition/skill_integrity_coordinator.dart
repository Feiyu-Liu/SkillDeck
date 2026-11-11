import '../application/ports/operation_ports.dart';
import '../application/ports/workspace_lifecycle_ports.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../application/runtime/workspace_performance_trace.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';

final class SkillIntegrityValidationResult {
  const SkillIntegrityValidationResult({
    required this.status,
    this.repairedArtifactCount = 0,
  });

  final SkillIntegrityStatus status;
  final int repairedArtifactCount;
}

/// Coalesces one in-flight materialization validation per managed Skill.
final class SkillIntegrityCoordinator {
  SkillIntegrityCoordinator({
    required WorkspaceSnapshotPublisher snapshots,
    required WorkspaceMaterializationReconciliationPort materializations,
    required WorkspaceWriterLockPort writerLock,
  }) : _snapshots = snapshots,
       _materializations = materializations,
       _writerLock = writerLock;

  final WorkspaceSnapshotPublisher _snapshots;
  final WorkspaceMaterializationReconciliationPort _materializations;
  final WorkspaceWriterLockPort _writerLock;
  final Map<ManagedSkillId, Future<SkillIntegrityValidationResult>> _inFlight =
      <ManagedSkillId, Future<SkillIntegrityValidationResult>>{};
  Future<void> _publicationQueue = Future<void>.value();

  Future<SkillIntegrityValidationResult> validate(ManagedSkillId skillId) {
    final existing = _inFlight[skillId];
    if (existing != null) return existing;
    late final Future<SkillIntegrityValidationResult> validation;
    validation = _validate(skillId).whenComplete(() {
      if (identical(_inFlight[skillId], validation)) {
        _inFlight.remove(skillId);
      }
    });
    _inFlight[skillId] = validation;
    return validation;
  }

  /// Validates committed materializations after any earlier scan has finished.
  ///
  /// A mutation must not reuse a scan that observed artifacts before its commit.
  Future<SkillIntegrityValidationResult> forceRevalidate(
    ManagedSkillId skillId,
  ) async {
    while (true) {
      final existing = _inFlight[skillId];
      if (existing == null) break;
      await existing;
    }
    return validate(skillId);
  }

  Future<void> markRevisionStoreCorrupt(ManagedSkillId skillId) =>
      _publishStatus(skillId, SkillIntegrityStatus.revisionStoreCorrupt);

  Future<SkillIntegrityValidationResult> _validate(
    ManagedSkillId skillId,
  ) async {
    final trace = WorkspacePerformanceTrace(
      WorkspacePerformancePhase.skillValidation,
    );
    var failed = true;
    try {
      final result = await _runValidation(skillId, trace);
      failed = switch (result.status) {
        SkillIntegrityStatus.healthy ||
        SkillIntegrityStatus.recovered ||
        SkillIntegrityStatus.driftPending => false,
        _ => true,
      };
      return result;
    } finally {
      trace.finish(failed: failed, checkedSkillCount: 1);
    }
  }

  Future<SkillIntegrityValidationResult> _runValidation(
    ManagedSkillId skillId,
    WorkspacePerformanceTrace trace,
  ) async {
    final initialStatus = _statusFor(skillId);
    if (initialStatus == SkillIntegrityStatus.revisionStoreCorrupt) {
      return const SkillIntegrityValidationResult(
        status: SkillIntegrityStatus.revisionStoreCorrupt,
      );
    }
    await _publishStatus(skillId, SkillIntegrityStatus.validating);
    try {
      for (var attempt = 0; attempt < 3; attempt += 1) {
        final skill = _snapshots.current.findSkill(skillId);
        if (skill == null) {
          return await _finish(skillId, SkillIntegrityStatus.repairFailed);
        }
        final expectedContentHash = skill.currentRevision.contentHash;
        final inspected = await _materializations.reconcileMaterializations(
          isolatedSkillIds: const <ManagedSkillId>{},
          selectedSkillIds: <ManagedSkillId>{skillId},
          repairMismatching: false,
          repairMissing: false,
        );
        _recordInspection(trace, inspected);
        if (inspected.mismatchingSkillIds.contains(skillId)) {
          return await _finish(skillId, SkillIntegrityStatus.driftPending);
        }
        if (!inspected.missingSkillIds.contains(skillId)) {
          return await _finish(skillId, SkillIntegrityStatus.healthy);
        }

        final lease = await _writerLock.acquire();
        try {
          final current = _snapshots.current.findSkill(skillId);
          if (current == null ||
              current.currentRevision.contentHash != expectedContentHash) {
            continue;
          }
          final repaired = await _materializations.reconcileMaterializations(
            isolatedSkillIds: const <ManagedSkillId>{},
            selectedSkillIds: <ManagedSkillId>{skillId},
            repairMismatching: false,
            repairMissing: true,
          );
          _recordInspection(trace, repaired);
          if (repaired.mismatchingSkillIds.contains(skillId)) {
            return await _finish(skillId, SkillIntegrityStatus.driftPending);
          }
          if (repaired.repairedArtifactCount < repaired.missingArtifactCount) {
            return await _finish(skillId, SkillIntegrityStatus.repairFailed);
          }
          return await _finish(
            skillId,
            SkillIntegrityStatus.healthy,
            repairedArtifactCount: repaired.repairedArtifactCount,
          );
        } finally {
          await lease.release();
        }
      }
    } on Object {
      return _finish(skillId, SkillIntegrityStatus.repairFailed);
    }
    return _finish(skillId, SkillIntegrityStatus.repairFailed);
  }

  Future<SkillIntegrityValidationResult> _finish(
    ManagedSkillId skillId,
    SkillIntegrityStatus status, {
    int repairedArtifactCount = 0,
  }) async {
    await _publishStatus(skillId, status);
    return SkillIntegrityValidationResult(
      status: status,
      repairedArtifactCount: repairedArtifactCount,
    );
  }

  SkillIntegrityStatus? _statusFor(ManagedSkillId skillId) {
    for (final state in _snapshots.current.integrity.skills) {
      if (state.managedSkillId == skillId) return state.status;
    }
    return null;
  }

  Future<void> _publishStatus(
    ManagedSkillId skillId,
    SkillIntegrityStatus status,
  ) {
    Future<void> publish() async {
      final snapshot = _snapshots.current;
      if (snapshot.findSkill(skillId) == null) return;
      final byId = <ManagedSkillId, ManagedSkillIntegrity>{
        for (final state in snapshot.integrity.skills)
          state.managedSkillId: state,
      };
      byId[skillId] = ManagedSkillIntegrity(
        managedSkillId: skillId,
        status: status,
      );
      final skills = byId.values.toList(growable: false)
        ..sort(
          (left, right) =>
              left.managedSkillId.value.compareTo(right.managedSkillId.value),
        );
      _snapshots.publishIntegrity(
        WorkspaceIntegrity(status: snapshot.integrity.status, skills: skills),
      );
    }

    final next = _publicationQueue.then(
      (_) => publish(),
      onError: (_, _) => publish(),
    );
    _publicationQueue = next.catchError((_) {});
    return next;
  }
}

void _recordInspection(
  WorkspacePerformanceTrace trace,
  WorkspaceMaterializationReconciliationReport report,
) {
  trace.inspectedArtifactCount += report.inspectedArtifactCount;
  trace.inspectedFileCount += report.inspectedFileCount;
  trace.inspectedByteCount += report.inspectedByteCount;
  trace.repairedArtifactCount += report.repairedArtifactCount;
}
