import 'package:drift/drift.dart';

import '../../application/operations/operation_models.dart';
import '../../application/runtime/revision_engine_port.dart';
import 'workspace_database.dart';

/// The SQLite roots shared by recovery bundles and retention reconciliation.
final class DriftCommittedRevisionRoots {
  const DriftCommittedRevisionRoots(this._database);

  final WorkspaceDatabase _database;

  Future<Set<RevisionObjectId>> readForBundle(
    SourceLineageReference lineage, {
    bool includeDraftAndSession = true,
  }) => _database.transaction(() async {
    final roots = await read(
      lineage: lineage,
      includeDraftAndSession: includeDraftAndSession,
    );
    return roots[lineage.encoded] ?? const <RevisionObjectId>{};
  });

  /// The caller coordinates the consistency of the read with other state.
  Future<Map<String, Set<RevisionObjectId>>> read({
    SourceLineageReference? lineage,
    bool includeDraftAndSession = true,
  }) async {
    final roots = await readPublished(lineage: lineage);
    final lineageId = lineage?.encoded;
    void add(String lineage, Iterable<String> objects) => roots
        .putIfAbsent(lineage, () => <RevisionObjectId>{})
        .addAll(objects.map(RevisionObjectId.new));

    final selections = _database.select(_database.currentRevisionSelection);
    if (lineageId != null) {
      selections.where((row) => row.sourceLineageId.equals(lineageId));
    }
    for (final selection in await selections.get()) {
      add(selection.sourceLineageId, [
        selection.upstreamObjectId,
        selection.effectiveObjectId,
      ]);
    }
    if (includeDraftAndSession) {
      final drafts = _database.select(_database.draftWorkspaces);
      final sessions = _database.select(_database.updateCandidateSessions);
      if (lineageId != null) {
        drafts.where((row) => row.sourceLineageId.equals(lineageId));
        sessions.where((row) => row.sourceLineageId.equals(lineageId));
      }
      for (final draft in await drafts.get()) {
        add(draft.sourceLineageId, [draft.baseObjectId]);
      }
      for (final session in await sessions.get()) {
        add(session.sourceLineageId, [
          session.previousUpstreamObjectId,
          session.previousEffectiveObjectId,
          session.incomingUpstreamObjectId,
          session.candidateObjectId,
        ]);
      }
    }
    return roots;
  }

  Future<Map<String, Set<RevisionObjectId>>> readPublished({
    SourceLineageReference? lineage,
  }) async {
    final subjects = _database.operationSubjects;
    final records = _database.operationRecords;
    final succeeded = records.status.equals('succeeded');
    final query =
        _database.select(subjects).join(<Join<HasResultSet, dynamic>>[
          innerJoin(
            records,
            records.operationId.equalsExp(subjects.operationId),
          ),
        ])..where(
          lineage == null
              ? succeeded
              : succeeded & subjects.sourceLineageId.equals(lineage.encoded),
        );
    final roots = <String, Set<RevisionObjectId>>{};
    for (final row in await query.get()) {
      final subject = row.readTable(subjects);
      final lineageId = subject.sourceLineageId;
      if (lineageId == null) continue;
      final objects = roots.putIfAbsent(lineageId, () => <RevisionObjectId>{});
      if (subject.beforeObjectId case final object?) {
        objects.add(RevisionObjectId(object));
      }
      if (subject.afterObjectId case final object?) {
        objects.add(RevisionObjectId(object));
      }
    }
    return roots;
  }
}
