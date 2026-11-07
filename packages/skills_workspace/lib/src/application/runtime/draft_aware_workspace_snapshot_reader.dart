import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../ports/draft_dirty_state_ports.dart';
import '../ports/workspace_lifecycle_ports.dart';

enum DraftAwareSnapshotReadFailureCode {
  dirtyStateUnavailable,
  snapshotChangedRepeatedly,
}

/// Stable failure from authoritative Draft presentation-state projection.
final class DraftAwareSnapshotReadException implements Exception {
  const DraftAwareSnapshotReadException(this.code, {this.reason});

  final DraftAwareSnapshotReadFailureCode code;
  final String? reason;

  @override
  String toString() => 'DraftAwareSnapshotReadException(${code.name})';
}

/// Decorates the SQLite projection with authoritative Draft dirty state.
///
/// Every read performs complete normalized Draft-vs-Base comparisons. The
/// first projection supplies stable Skill identities to inspect; the second
/// injects the computed results into one immutable public Snapshot. A racing
/// Control Plane mutation changes Repository Revision and retries the whole
/// read rather than publishing mismatched filesystem facts.
final class DraftAwareWorkspaceSnapshotReader
    implements WorkspaceSnapshotReaderPort {
  DraftAwareWorkspaceSnapshotReader({
    required WorkspaceSnapshotProjectionReaderPort projection,
    required DraftDirtyStateInspectionPort draftInspection,
    this.maximumConsistencyAttempts = 3,
  }) : _projection = projection,
       _draftInspection = draftInspection {
    if (maximumConsistencyAttempts <= 0) {
      throw ArgumentError.value(
        maximumConsistencyAttempts,
        'maximumConsistencyAttempts',
        'must be positive',
      );
    }
  }

  final WorkspaceSnapshotProjectionReaderPort _projection;
  final DraftDirtyStateInspectionPort _draftInspection;
  final int maximumConsistencyAttempts;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async {
    for (var attempt = 0; attempt < maximumConsistencyAttempts; attempt += 1) {
      final basis = await _projection.readWithDraftDirtyStates(
        draftDirtyStates: const <ManagedSkillId, bool>{},
        integrity: integrity,
      );
      final dirtyStates = <ManagedSkillId, bool>{};
      final blockedIds = <ManagedSkillId>{
        for (final state in basis.integrity.skills)
          if (state.mutationBlocked) state.managedSkillId,
      };
      var retry = false;

      for (final skill in basis.managedSkills) {
        if (skill.draft == null) continue;
        if (blockedIds.contains(skill.id)) {
          // No trustworthy Draft Base exists for an isolated corrupt Store.
          // Conservatively block dirty-sensitive actions while the typed
          // integrity state communicates why comparison is unavailable.
          dirtyStates[skill.id] = true;
          continue;
        }
        final result = await _draftInspection.inspectDraftDirtyState(
          skill: skill,
          cancellationToken: CancellationToken.none(),
        );
        switch (result) {
          case DraftDirtyStateInspectionSuccess(:final isDirty):
            dirtyStates[skill.id] = isDirty;
          case DraftDirtyStateInspectionFailure(:final reason):
            if (_isConsistencyRace(reason)) {
              retry = true;
              break;
            }
            throw DraftAwareSnapshotReadException(
              DraftAwareSnapshotReadFailureCode.dirtyStateUnavailable,
              reason: reason,
            );
        }
      }
      if (retry) continue;

      final projected = await _projection.readWithDraftDirtyStates(
        draftDirtyStates: dirtyStates,
        integrity: integrity,
      );
      if (projected.revision != basis.revision ||
          !_sameDraftSet(projected, dirtyStates.keys.toSet())) {
        continue;
      }
      return projected;
    }
    throw const DraftAwareSnapshotReadException(
      DraftAwareSnapshotReadFailureCode.snapshotChangedRepeatedly,
    );
  }
}

bool _isConsistencyRace(String reason) =>
    reason == 'draftStateChanged' ||
    reason == 'draftStateUnavailable' ||
    reason == 'draftChangedDuringPublish';

bool _sameDraftSet(
  RepositorySnapshot snapshot,
  Set<ManagedSkillId> inspectedDraftIds,
) {
  final projectedDraftIds = <ManagedSkillId>{
    for (final skill in snapshot.managedSkills)
      if (skill.draft != null) skill.id,
  };
  return projectedDraftIds.length == inspectedDraftIds.length &&
      projectedDraftIds.containsAll(inspectedDraftIds);
}
