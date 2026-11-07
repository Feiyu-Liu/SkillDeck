import 'package:drift/drift.dart';

import '../../application/operations/operation_models.dart';
import '../../application/operations/workspace_business_changes.dart';
import '../../application/ports/workspace_lifecycle_ports.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/identifiers.dart';
import '../workspace_layout.dart';
import 'operation_plan_codec.dart';
import 'workspace_database.dart' as db;

/// Rebuilds the derived retention set for every canonical Revision Store.
///
/// SQLite rows and recoverable Journal plans are the only inputs.  Git refs
/// are replaced as a whole per Store and are never read to elect a revision.
final class DriftWorkspaceRevisionReferenceReconciliation
    implements WorkspaceRevisionReferenceReconciliationPort {
  const DriftWorkspaceRevisionReferenceReconciliation({
    required db.WorkspaceDatabase database,
    required WorkspaceLayout layout,
    required RevisionEnginePort revisionEngine,
    OperationPlanCodec codec = const OperationPlanCodec(),
  }) : _database = database,
       _layout = layout,
       _revisionEngine = revisionEngine,
       _codec = codec;

  final db.WorkspaceDatabase _database;
  final WorkspaceLayout _layout;
  final RevisionEnginePort _revisionEngine;
  final OperationPlanCodec _codec;

  @override
  Future<void> reconcileRevisionReferences({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  }) async {
    final desiredStores = await _database.transaction(
      () => _readDesiredStores(isolatedSkillIds, selectedSkillIds),
    );
    for (final desired in desiredStores) {
      await _revisionEngine.replaceRetentionRefs(
        desired.repositoryPath,
        desired.references,
      );
    }
  }

  Future<List<_DesiredStoreRefs>> _readDesiredStores(
    Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  ) async {
    final lineageTable = _database.sourceLineages;
    final skills = _database.managedSkills;
    final lineageRows = await _database.select(lineageTable).join([
      innerJoin(
        skills,
        skills.id.equalsExp(lineageTable.managedSkillId) &
            skills.activeSourceLineageId.equalsExp(lineageTable.id),
      ),
    ]).get();
    final lineages =
        lineageRows
            .map((row) => row.readTable(lineageTable))
            .where((lineage) {
              final managedSkillId = ManagedSkillId(lineage.managedSkillId);
              return !isolatedSkillIds.contains(managedSkillId) &&
                  (selectedSkillIds == null ||
                      selectedSkillIds.contains(managedSkillId));
            })
            .toList(growable: false)
          ..sort((left, right) {
            final bySkill = left.managedSkillId.compareTo(right.managedSkillId);
            if (bySkill != 0) return bySkill;
            return left.id.compareTo(right.id);
          });
    final lineageById = <String, db.SourceLineage>{
      for (final lineage in lineages) lineage.id: lineage,
    };
    final refsByLineage = <String, Map<String, RevisionObjectId>>{};

    void add({
      required String lineage,
      required RevisionObjectId object,
      required String name,
    }) {
      if (!lineageById.containsKey(lineage)) return;
      refsByLineage.putIfAbsent(
        lineage,
        () => <String, RevisionObjectId>{},
      )[name] = object;
    }

    final selections = await _database
        .select(_database.currentRevisionSelection)
        .get();
    for (final selection in selections) {
      add(
        lineage: selection.sourceLineageId,
        object: RevisionObjectId(selection.upstreamObjectId),
        name:
            'refs/skills-workspace/current/${selection.managedSkillId}/upstream',
      );
      add(
        lineage: selection.sourceLineageId,
        object: RevisionObjectId(selection.effectiveObjectId),
        name:
            'refs/skills-workspace/current/${selection.managedSkillId}/effective',
      );
    }

    final drafts = await _database.select(_database.draftWorkspaces).get();
    for (final draft in drafts) {
      add(
        lineage: draft.sourceLineageId,
        object: RevisionObjectId(draft.baseObjectId),
        name: 'refs/skills-workspace/draft/${draft.managedSkillId}/base',
      );
    }

    final sessions = await _database
        .select(_database.updateCandidateSessions)
        .get();
    for (final session in sessions) {
      final prefix = 'refs/skills-workspace/session/${session.managedSkillId}';
      add(
        lineage: session.sourceLineageId,
        object: RevisionObjectId(session.previousUpstreamObjectId),
        name: '$prefix/previous-upstream',
      );
      add(
        lineage: session.sourceLineageId,
        object: RevisionObjectId(session.previousEffectiveObjectId),
        name: '$prefix/previous-effective',
      );
      add(
        lineage: session.sourceLineageId,
        object: RevisionObjectId(session.incomingUpstreamObjectId),
        name: '$prefix/incoming-upstream',
      );
      add(
        lineage: session.sourceLineageId,
        object: RevisionObjectId(session.candidateObjectId),
        name: '$prefix/candidate',
      );
    }

    await _addPublishedHistory(add);
    await _addRecoverablePlans(add);

    final desiredStores = <_DesiredStoreRefs>[];
    for (final lineage in lineages) {
      final refs =
          refsByLineage[lineage.id] ?? const <String, RevisionObjectId>{};
      final managedSkillId = ManagedSkillId(lineage.managedSkillId);
      final storePath = _layout.revisionStorePath(managedSkillId);
      final objects =
          <String, RevisionObjectId>{
              for (final object in refs.values) object.value: object,
            }.values.toList(growable: false)
            ..sort((left, right) => left.value.compareTo(right.value));
      final values = <RevisionRetentionRef>[
        for (var index = 0; index < objects.length; index += 1)
          RevisionRetentionRef(
            name: 'refs/skills-workspace/r/${index.toRadixString(36)}',
            target: objects[index],
          ),
      ];
      desiredStores.add(_DesiredStoreRefs(storePath, values));
    }
    return List<_DesiredStoreRefs>.unmodifiable(desiredStores);
  }

  Future<void> _addPublishedHistory(
    void Function({
      required String lineage,
      required RevisionObjectId object,
      required String name,
    })
    add,
  ) async {
    final subjects = _database.operationSubjects;
    final records = _database.operationRecords;
    final query = _database.select(subjects).join(<Join<HasResultSet, dynamic>>[
      innerJoin(records, records.operationId.equalsExp(subjects.operationId)),
    ])..where(records.status.equals('succeeded'));
    final rows = await query.get();
    for (final row in rows) {
      final subject = row.readTable(subjects);
      final lineage = subject.sourceLineageId;
      if (lineage == null) continue;
      final prefix =
          'refs/skills-workspace/history/${subject.operationId}/${subject.subjectId}';
      if (subject.beforeObjectId case final object?) {
        add(
          lineage: lineage,
          object: RevisionObjectId(object),
          name: '$prefix/before',
        );
      }
      if (subject.afterObjectId case final object?) {
        add(
          lineage: lineage,
          object: RevisionObjectId(object),
          name: '$prefix/after',
        );
      }
    }
  }

  Future<void> _addRecoverablePlans(
    void Function({
      required String lineage,
      required RevisionObjectId object,
      required String name,
    })
    add,
  ) async {
    final journals = await _database.select(_database.operationJournals).get();
    for (final journal in journals) {
      if (journal.phase == OperationJournalPhase.completed.name) continue;
      final definition = _codec.decodeDefinition(
        schemaVersion: journal.planSchemaVersion,
        payload: journal.planJson,
      );
      if (definition is! OperationPlan) continue;
      final operationPrefix =
          'refs/skills-workspace/journal/${definition.operationId.value}';
      for (
        var index = 0;
        index < definition.revisionSelectionChanges.length;
        index++
      ) {
        final change = definition.revisionSelectionChanges[index];
        void addAddress(RevisionAddress? address, String role) {
          if (address == null) return;
          add(
            lineage: address.sourceLineage.encoded,
            object: address.objectId,
            name: '$operationPrefix/selection-$index/$role',
          );
        }

        addAddress(change.previousUpstream, 'previous-upstream');
        addAddress(change.previousEffective, 'previous-effective');
        addAddress(change.intendedUpstream, 'intended-upstream');
        addAddress(change.intendedEffective, 'intended-effective');
      }

      for (final subject in definition.record.subjects) {
        final lineage = subject.sourceLineage;
        if (lineage == null) continue;
        final prefix =
            '$operationPrefix/subject/${subject.reference.subjectId}';
        if (subject.beforeObjectId case final object?) {
          add(lineage: lineage.encoded, object: object, name: '$prefix/before');
        }
        if (subject.afterObjectId case final object?) {
          add(lineage: lineage.encoded, object: object, name: '$prefix/after');
        }
      }

      var mutationIndex = 0;
      for (final mutation in definition.businessChanges.mutations) {
        switch (mutation) {
          case PutRevisionMetadata(:final sourceLineageId, :final objectId):
            add(
              lineage: sourceLineageId,
              object: RevisionObjectId(objectId),
              name: '$operationPrefix/metadata-$mutationIndex',
            );
          case PutDraftWorkspace(:final sourceLineageId, :final baseObjectId):
            add(
              lineage: sourceLineageId,
              object: RevisionObjectId(baseObjectId),
              name: '$operationPrefix/draft-base-$mutationIndex',
            );
          case PutUpdateCandidateSession(
            :final sourceLineageId,
            :final previousUpstreamObjectId,
            :final previousEffectiveObjectId,
            :final incomingUpstreamObjectId,
            :final candidateObjectId,
          ):
            for (final entry in <String, String>{
              'previous-upstream': previousUpstreamObjectId,
              'previous-effective': previousEffectiveObjectId,
              'incoming-upstream': incomingUpstreamObjectId,
              'candidate': candidateObjectId,
            }.entries) {
              add(
                lineage: sourceLineageId,
                object: RevisionObjectId(entry.value),
                name: '$operationPrefix/session-$mutationIndex/${entry.key}',
              );
            }
          default:
            break;
        }
        mutationIndex += 1;
      }
    }
  }
}

final class _DesiredStoreRefs {
  const _DesiredStoreRefs(this.repositoryPath, this.references);

  final String repositoryPath;
  final List<RevisionRetentionRef> references;
}
