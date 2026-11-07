import '../../application/destructive/destructive_operation_models.dart';
import '../../application/operations/operation_models.dart';
import '../../application/ports/destructive_operation_ports.dart';
import '../../application/ports/update_ports.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../application/update/update_models.dart';
import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import 'workspace_database.dart' as db;

/// Reconstructs the complete destructive-planning projection from SQLite.
///
/// Public Snapshots deliberately omit Source Lineage and Git
/// object identities. The caller passes the already-reviewed public Snapshot;
/// this adapter verifies the same Repository Revision under the Writer Lock and
/// enriches each Skill with internal authority from one Drift transaction.
final class DriftDestructivePlanningState
    implements DestructivePlanningStatePort {
  const DriftDestructivePlanningState({
    required db.WorkspaceDatabase database,
    required UpdateDraftInspectionPort draftInspection,
  }) : _database = database,
       _draftInspection = draftInspection;

  final db.WorkspaceDatabase _database;
  final UpdateDraftInspectionPort _draftInspection;

  @override
  Future<DestructivePlanningSnapshot> readPlanningSnapshot({
    required RepositorySnapshot publicSnapshot,
    required DestructivePlanningPurpose purpose,
    required Set<ManagedSkillId> targetManagedSkillIds,
    required CancellationToken cancellationToken,
  }) => _database.transaction(() async {
    _throwIfCancelled(cancellationToken);
    final metadata = await _database
        .select(_database.workspaceMetadata)
        .getSingle();
    if (metadata.repositoryRevision != publicSnapshot.revision.value) {
      throw StateError(
        'The public Snapshot is stale for destructive planning.',
      );
    }

    final skillRows = await _database.select(_database.managedSkills).get();
    final lineageRows = await _database.select(_database.sourceLineages).get();
    final selectionRows = await _database
        .select(_database.currentRevisionSelection)
        .get();
    final revisionRows = await _database
        .select(_database.revisionMetadata)
        .get();
    final activationRows = await _database
        .select(_database.activationLocations)
        .get();
    final draftRows = await _database.select(_database.draftWorkspaces).get();
    final sessionRows = await _database
        .select(_database.updateCandidateSessions)
        .get();

    final skillById = <String, db.ManagedSkill>{
      for (final row in skillRows) row.id: row,
    };
    final lineagesBySkill = <String, List<db.SourceLineage>>{};
    for (final row in lineageRows) {
      lineagesBySkill.putIfAbsent(row.managedSkillId, () => []).add(row);
    }
    final selectionBySkill = <String, db.CurrentRevisionSelectionData>{
      for (final row in selectionRows) row.managedSkillId: row,
    };
    final revisionsByAddress = <(String, String), db.RevisionMetadataData>{
      for (final row in revisionRows) (row.sourceLineageId, row.objectId): row,
    };
    final activationIdsBySkill = <String, List<String>>{};
    for (final row in activationRows) {
      activationIdsBySkill
          .putIfAbsent(row.managedSkillId, () => <String>[])
          .add(row.id);
    }
    final draftBySkill = <String, db.DraftWorkspace>{
      for (final row in draftRows) row.managedSkillId: row,
    };
    final sessionSkillIds = <String>{
      for (final row in sessionRows) row.managedSkillId,
    };

    final plannedSkills = <DestructiveManagedSkillState>[];
    for (final publicSkill in publicSnapshot.managedSkills) {
      _throwIfCancelled(cancellationToken);
      final id = publicSkill.id.value;
      final skill = skillById[id];
      final selection = selectionBySkill[id];
      final lineages = lineagesBySkill[id] ?? const <db.SourceLineage>[];
      if (skill == null || selection == null || lineages.isEmpty) {
        throw StateError('Incomplete destructive planning state.');
      }
      final activeLineage = SourceLineageReference(skill.activeSourceLineageId);
      if (selection.sourceLineageId != activeLineage.encoded) {
        throw StateError(
          'The selected revisions do not use the active lineage.',
        );
      }
      final effectiveMetadata =
          revisionsByAddress[(
            selection.sourceLineageId,
            selection.effectiveObjectId,
          )];
      if (effectiveMetadata == null) {
        throw StateError('The selected Effective Revision is not indexed.');
      }

      final draft = draftBySkill[id];
      final DestructiveDraftState draftState;
      if (draft == null) {
        draftState = DestructiveDraftState.absent;
      } else if (purpose == DestructivePlanningPurpose.removal ||
          !targetManagedSkillIds.contains(publicSkill.id)) {
        // Removal deletes the Draft with the aggregate and therefore needs
        // only the durable presence bit. Unrelated Skills must never be
        // inspected while planning another Skill's destructive operation.
        draftState = DestructiveDraftState.clean;
      } else {
        final inspected = await _draftInspection.inspectForUpdate(
          skill: publicSkill,
          cancellationToken: cancellationToken,
        );
        draftState = switch (inspected) {
          UpdateDraftInspectionSuccess(:final inspection) =>
            inspection.isDirty
                ? DestructiveDraftState.dirty
                : DestructiveDraftState.clean,
          UpdateDraftInspectionFailure(:final reason) =>
            throw DestructivePlanningStateException(
              reason == 'operationCancelled'
                  ? DestructivePlanningStateFailureCode.operationCancelled
                  : DestructivePlanningStateFailureCode.draftInspectionFailed,
              reason: reason,
            ),
        };
      }

      final activationIds = activationIdsBySkill[id] ?? <String>[];
      activationIds.sort();
      lineages.sort((left, right) => left.id.compareTo(right.id));
      plannedSkills.add(
        DestructiveManagedSkillState(
          managedSkillId: publicSkill.id,
          slotKey: skill.slotKey,
          declaredName: skill.declaredName,
          displayName: skill.displayName,
          description: skill.description,
          createdAtMicros: skill.createdAtMicros,
          sourceLineages: [
            for (final lineage in lineages)
              DestructiveSourceLineageState(
                sourceLineage: SourceLineageReference(lineage.id),
              ),
          ],
          activeSourceLineage: activeLineage,
          currentUpstream: RevisionAddress(
            sourceLineage: activeLineage,
            objectId: RevisionObjectId(selection.upstreamObjectId),
          ),
          currentEffective: RevisionAddress(
            sourceLineage: activeLineage,
            objectId: RevisionObjectId(selection.effectiveObjectId),
          ),
          currentContentHash: effectiveMetadata.contentHash,
          activationIds: activationIds,
          draftState: draftState,
          hasUpdateCandidateSession: sessionSkillIds.contains(id),
        ),
      );
    }
    plannedSkills.sort(
      (left, right) =>
          left.managedSkillId.value.compareTo(right.managedSkillId.value),
    );
    return DestructivePlanningSnapshot(
      repositoryRevision: publicSnapshot.revision,
      managedSkills: plannedSkills,
    );
  });
}

void _throwIfCancelled(CancellationToken token) {
  if (token.isCancelled) {
    throw const DestructivePlanningStateException(
      DestructivePlanningStateFailureCode.operationCancelled,
    );
  }
}
