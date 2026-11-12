import '../../domain/identifiers.dart';
import '../../domain/public_models.dart' as domain;
import '../../application/ports/workspace_lifecycle_ports.dart';
import '../workspace_layout.dart';
import 'source_descriptor_codec.dart';
import 'workspace_database.dart' as db;

/// Reads one immutable public Snapshot from a single SQLite transaction.
///
/// Drift rows remain confined to this adapter. Filesystem-derived facts that
/// SQLite deliberately does not persist, such as authoritative Draft dirty
/// state and Revision Store integrity, are supplied by the caller after their
/// own validation has completed.
final class WorkspaceSnapshotReader
    implements WorkspaceSnapshotProjectionReaderPort {
  const WorkspaceSnapshotReader({
    required db.WorkspaceDatabase database,
    required WorkspaceLayout layout,
    SourceDescriptorCodec sourceCodec = const SourceDescriptorCodec(),
  }) : _database = database,
       _layout = layout,
       _sourceCodec = sourceCodec;

  final db.WorkspaceDatabase _database;
  final WorkspaceLayout _layout;
  final SourceDescriptorCodec _sourceCodec;

  @override
  Future<domain.RepositorySnapshot> read({
    domain.WorkspaceIntegrity? integrity,
  }) => readWithDraftDirtyStates(
    draftDirtyStates: const <ManagedSkillId, bool>{},
    integrity: integrity,
  );

  @override
  Future<domain.RepositorySnapshot> readWithDraftDirtyStates({
    required Map<ManagedSkillId, bool> draftDirtyStates,
    domain.WorkspaceIntegrity? integrity,
  }) => _database.transaction(() async {
    final metadata = await _database
        .select(_database.workspaceMetadata)
        .getSingle();
    final skills = await _database.select(_database.managedSkills).get();
    final lineages = await _database.select(_database.sourceLineages).get();
    final sources = await _database.select(_database.skillSources).get();
    final revisions = await _database.select(_database.revisionMetadata).get();
    final selections = await _database
        .select(_database.currentRevisionSelection)
        .get();
    final drafts = await _database.select(_database.draftWorkspaces).get();
    final sessions = await _database
        .select(_database.updateCandidateSessions)
        .get();
    final sessionItems = await _database
        .select(_database.updateCandidateItems)
        .get();
    final projectRoots = await _database.select(_database.projectRoots).get();
    final activationLocations = await _database
        .select(_database.activationLocations)
        .get();
    final activationAgents = await _database
        .select(_database.activationAgents)
        .get();
    final userData = await _database.select(_database.skillUserData).get();
    final tags = await _database.select(_database.personalTags).get();
    final assignments = await _database
        .select(_database.skillTagAssignments)
        .get();

    final lineageById = {for (final row in lineages) row.id: row};
    final sourceByLineage = {
      for (final row in sources) row.sourceLineageId: row,
    };
    final revisionByAddress = {
      for (final row in revisions) (row.sourceLineageId, row.objectId): row,
    };
    final selectionBySkill = {
      for (final row in selections) row.managedSkillId: row,
    };
    final draftBySkill = {for (final row in drafts) row.managedSkillId: row};
    final sessionBySkill = {
      for (final row in sessions) row.managedSkillId: row,
    };
    final itemsBySkill = <String, List<db.UpdateCandidateItem>>{};
    for (final item in sessionItems) {
      itemsBySkill.putIfAbsent(item.managedSkillId, () => []).add(item);
    }
    final agentsByLocation = <String, List<String>>{};
    for (final agent in activationAgents) {
      agentsByLocation
          .putIfAbsent(agent.activationLocationId, () => [])
          .add(agent.agentId);
    }
    final activationsBySkill = <String, List<domain.SkillActivation>>{};
    for (final location in activationLocations) {
      final agentIds = agentsByLocation[location.id] ?? const <String>[];
      agentIds.sort();
      activationsBySkill
          .putIfAbsent(location.managedSkillId, () => [])
          .add(
            domain.SkillActivation(
              location: location.canonicalPath,
              scope: _activationScope(location.scope),
              mode: _activationMode(location.mode),
              agentIds: agentIds,
              projectRootId: location.projectRootId,
              projectRootPath: location.projectRootPath,
            ),
          );
    }
    for (final activations in activationsBySkill.values) {
      activations.sort((a, b) => a.location.compareTo(b.location));
    }
    final userDataBySkill = {
      for (final row in userData) row.managedSkillId: row,
    };
    final tagIdsBySkill = <String, List<String>>{};
    for (final assignment in assignments) {
      tagIdsBySkill
          .putIfAbsent(assignment.managedSkillId, () => [])
          .add(assignment.personalTagId);
    }
    for (final tagIds in tagIdsBySkill.values) {
      tagIds.sort();
    }

    final managedSkills = <domain.ManagedSkill>[];
    for (final skill in skills) {
      final managedSkillId = ManagedSkillId(skill.id);
      final lineage = lineageById[skill.activeSourceLineageId];
      final sourceRow = sourceByLineage[skill.activeSourceLineageId];
      final selection = selectionBySkill[skill.id];
      if (lineage == null || sourceRow == null || selection == null) {
        throw StateError('Incomplete persisted Skill projection.');
      }
      if (lineage.managedSkillId != skill.id ||
          selection.sourceLineageId != lineage.id) {
        throw StateError('Inconsistent active Source Lineage projection.');
      }
      final effectiveRevision =
          revisionByAddress[(
            selection.sourceLineageId,
            selection.effectiveObjectId,
          )];
      if (effectiveRevision == null) {
        throw StateError('Selected Effective Revision metadata is missing.');
      }
      final draft = draftBySkill[skill.id];
      final session = sessionBySkill[skill.id];
      final persistedUserData = userDataBySkill[skill.id];

      managedSkills.add(
        domain.ManagedSkill(
          id: managedSkillId,
          createdAt: _utc(skill.createdAtMicros),
          slotKey: skill.slotKey,
          declaredName: skill.declaredName,
          displayName: skill.displayName,
          description: skill.description,
          source: _sourceCodec.decode(
            kind: sourceRow.kind,
            payloadSchemaVersion: sourceRow.payloadSchemaVersion,
            payloadJson: sourceRow.payloadJson,
          ),
          currentRevision: domain.ManagedSkillRevisionSummary(
            contentHash: effectiveRevision.contentHash,
            fileCount: effectiveRevision.fileCount,
            byteSize: effectiveRevision.byteSize,
            publishedAt: _utc(effectiveRevision.createdAtMicros),
          ),
          favorite: domain.SkillFavorite(
            isFavorite: persistedUserData?.favorite ?? false,
            changedAt: persistedUserData?.favoriteChangedAtMicros == null
                ? null
                : _utc(persistedUserData!.favoriteChangedAtMicros!),
          ),
          note: persistedUserData?.note == null
              ? null
              : domain.SkillNote(
                  text: persistedUserData!.note!,
                  updatedAt: _utc(persistedUserData.noteUpdatedAtMicros!),
                ),
          personalTagIds: tagIdsBySkill[skill.id] ?? const <String>[],
          activations:
              activationsBySkill[skill.id] ?? const <domain.SkillActivation>[],
          draft: draft == null
              ? null
              : domain.DraftSummary(
                  purpose: _draftPurpose(draft.purpose),
                  path: _layout.draftPath(managedSkillId),
                  isDirty: draftDirtyStates[managedSkillId] ?? false,
                  updatedAt: _utc(draft.updatedAtMicros),
                ),
          updateCandidate: session == null
              ? null
              : _updateCandidate(
                  session,
                  itemsBySkill[skill.id] ?? const <db.UpdateCandidateItem>[],
                ),
        ),
      );
    }
    managedSkills.sort((a, b) => a.slotKey.compareTo(b.slotKey));

    final projectedRoots =
        projectRoots
            .map(
              (row) => domain.ProjectRoot(id: row.id, path: row.canonicalPath),
            )
            .toList(growable: false)
          ..sort((a, b) => a.path.compareTo(b.path));
    final projectedTags =
        tags
            .map(
              (row) => domain.PersonalTag(
                id: row.id,
                name: row.displayName,
                color: row.color,
                createdAt: _utc(row.createdAtMicros),
                updatedAt: _utc(row.updatedAtMicros),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final byName = a.name.compareTo(b.name);
            return byName == 0 ? a.id.compareTo(b.id) : byName;
          });

    return domain.RepositorySnapshot(
      revision: RepositoryRevision(metadata.repositoryRevision),
      managedSkills: managedSkills,
      projectRoots: projectedRoots,
      personalTags: projectedTags,
      integrity: integrity,
    );
  });
}

domain.UpdateCandidateSummary _updateCandidate(
  db.UpdateCandidateSession session,
  List<db.UpdateCandidateItem> items,
) {
  final conflicts =
      items
          .map(
            (item) => domain.UpdateConflict(
              path: item.path,
              kind: _conflictKind(item.kind),
              resolutionState: _conflictResolutionState(item.state),
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => a.path.compareTo(b.path));
  return domain.UpdateCandidateSummary(
    status: _candidateStatus(session.status),
    conflicts: conflicts,
    createdAt: _utc(session.createdAtMicros),
    validationCode: session.validationCode,
  );
}

domain.ActivationScope _activationScope(String value) => switch (value) {
  'global' => domain.ActivationScope.global,
  'project' => domain.ActivationScope.project,
  _ => throw StateError('Unsupported Activation scope.'),
};

domain.ActivationMode _activationMode(String value) => switch (value) {
  'copy' => domain.ActivationMode.copy,
  'symbolicLink' => domain.ActivationMode.symbolicLink,
  _ => throw StateError('Unsupported Activation mode.'),
};

domain.DraftPurpose _draftPurpose(String value) => switch (value) {
  'customization' => domain.DraftPurpose.customization,
  'updateCandidateResolution' => domain.DraftPurpose.updateCandidateResolution,
  _ => throw StateError('Unsupported Draft purpose.'),
};

domain.UpdateCandidateStatus _candidateStatus(String value) => switch (value) {
  'conflicted' => domain.UpdateCandidateStatus.conflicted,
  'validationFailed' => domain.UpdateCandidateStatus.validationFailed,
  _ => throw StateError('Unsupported Update Candidate status.'),
};

domain.UpdateConflictResolutionState _conflictResolutionState(String value) =>
    switch (value) {
      'unresolved' => domain.UpdateConflictResolutionState.unresolved,
      'resolved' => domain.UpdateConflictResolutionState.resolved,
      _ => throw StateError('Unsupported Update conflict resolution state.'),
    };

domain.ConflictKind _conflictKind(String value) => switch (value) {
  'text' => domain.ConflictKind.text,
  'rename' => domain.ConflictKind.rename,
  'deleteModify' => domain.ConflictKind.deleteModify,
  'binary' => domain.ConflictKind.binary,
  'executableMode' => domain.ConflictKind.executableMode,
  _ => throw StateError('Unsupported conflict kind.'),
};

DateTime _utc(int micros) =>
    DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
