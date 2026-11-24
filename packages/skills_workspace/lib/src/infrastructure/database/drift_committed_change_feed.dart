import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../application/operations/operation_models.dart';
import '../../application/operations/workspace_business_changes.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import 'workspace_database.dart';

/// Reads a coherent cursor and stores the latest revision of each change kind.
final class DriftCommittedChangeFeed {
  const DriftCommittedChangeFeed(this._database);

  static const _vocabularySubject = 'vocabulary';
  final WorkspaceDatabase _database;

  Future<CommittedChanges> inspect(
    RepositoryRevision since,
  ) => _database.transaction(() async {
    final metadata = await _database.workspaceMetadata.select().getSingle();
    final current = RepositoryRevision(metadata.repositoryRevision);
    if (since.value > current.value) {
      return CommittedChanges.resetRequired(current);
    }
    final cursor = since.value;
    final query = _database.select(_database.committedChangeStamps)
      ..where(
        (row) =>
            row.contentRevision.isBiggerThanValue(cursor) |
            row.metadataRevision.isBiggerThanValue(cursor) |
            row.removedRevision.isBiggerThanValue(cursor) |
            row.vocabularyRevision.isBiggerThanValue(cursor),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.subject)]);
    final rows = await query.get();
    return CommittedChanges.changes(
      current: current,
      vocabularyChanged: rows.any((row) => row.subject == _vocabularySubject),
      entries: [
        for (final row in rows)
          if (row.subject != _vocabularySubject)
            CommittedSkillChange(
              managedSkillId: ManagedSkillId(row.subject),
              revision: RepositoryRevision(
                math.max(
                  row.contentRevision,
                  math.max(row.metadataRevision, row.removedRevision),
                ),
              ),
              kinds: {
                if (row.contentRevision > cursor) CommittedChangeKind.content,
                if (row.metadataRevision > cursor) CommittedChangeKind.metadata,
                if (row.removedRevision > cursor) CommittedChangeKind.removed,
              },
            ),
      ],
    );
  });

  /// Called as each mutation is applied inside the Business Commit transaction.
  Future<void> recordMutation(
    WorkspaceBusinessMutation mutation,
    RepositoryRevision revision,
  ) async {
    switch (mutation) {
      case DeleteManagedSkill(:final managedSkillId):
        await _recordSkill(
          managedSkillId.value,
          CommittedChangeKind.removed,
          revision,
        );
      case PutSkillUserData(:final managedSkillId) ||
          DeleteSkillUserData(:final managedSkillId) ||
          PutSkillTagAssignment(:final managedSkillId) ||
          DeleteSkillTagAssignment(:final managedSkillId):
        await _recordSkill(
          managedSkillId.value,
          CommittedChangeKind.metadata,
          revision,
        );
      case PutPersonalTag():
        await _recordVocabulary(revision);
      case DeletePersonalTag(:final personalTagId):
        // Capture assignments before the tag deletion cascades to them.
        final assignments = await (_database.select(
          _database.skillTagAssignments,
        )..where((row) => row.personalTagId.equals(personalTagId))).get();
        for (final assignment in assignments) {
          await _recordSkill(
            assignment.managedSkillId,
            CommittedChangeKind.metadata,
            revision,
          );
        }
        await _recordVocabulary(revision);
      case PutManagedSkill() ||
          PutSourceLineage() ||
          DeleteSourceLineage() ||
          PutSkillSource() ||
          PutRevisionMetadata() ||
          PutProjectRoot() ||
          DeleteProjectRoot() ||
          PutActivation() ||
          DeleteActivation() ||
          PutDraftWorkspace() ||
          DeleteDraftWorkspace() ||
          PutUpdateCandidateSession() ||
          DeleteUpdateCandidateSession() ||
          SetUpdateCandidateItemResolution():
        break;
    }
  }

  Future<void> recordSelection(
    RevisionSelectionChangePlan selection,
    RepositoryRevision revision,
  ) async {
    if (selection.intendedEffective != null &&
        (selection.previousEffective != selection.intendedEffective ||
            selection.previousUpstream != selection.intendedUpstream)) {
      await _recordSkill(
        selection.managedSkillId.value,
        CommittedChangeKind.content,
        revision,
      );
    }
  }

  Future<void> _recordSkill(
    String skillId,
    CommittedChangeKind kind,
    RepositoryRevision revision,
  ) => _writeStamp(
    CommittedChangeStampsCompanion.insert(
      subject: skillId,
      contentRevision: kind == CommittedChangeKind.content
          ? Value(revision.value)
          : const Value.absent(),
      metadataRevision: kind == CommittedChangeKind.metadata
          ? Value(revision.value)
          : const Value.absent(),
      removedRevision: kind == CommittedChangeKind.removed
          ? Value(revision.value)
          : const Value.absent(),
    ),
  );

  Future<void> _recordVocabulary(RepositoryRevision revision) => _writeStamp(
    CommittedChangeStampsCompanion.insert(
      subject: _vocabularySubject,
      vocabularyRevision: Value(revision.value),
    ),
  );

  Future<void> _writeStamp(CommittedChangeStampsCompanion stamp) => _database
      .into(_database.committedChangeStamps)
      .insert(stamp, onConflict: DoUpdate((_) => stamp));
}
