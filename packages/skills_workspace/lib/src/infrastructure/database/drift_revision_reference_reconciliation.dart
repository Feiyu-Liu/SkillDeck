import 'package:drift/drift.dart';

import '../../application/operations/operation_models.dart';
import '../../application/operations/workspace_business_changes.dart';
import '../../application/ports/workspace_lifecycle_ports.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/identifiers.dart';
import '../workspace_layout.dart';
import 'drift_committed_revision_roots.dart';
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
    final lineageIds = lineages.map((lineage) => lineage.id).toSet();
    final rootsByLineage = await DriftCommittedRevisionRoots(_database).read();

    void add(String lineage, RevisionObjectId object) {
      if (lineageIds.contains(lineage)) {
        rootsByLineage
            .putIfAbsent(lineage, () => <RevisionObjectId>{})
            .add(object);
      }
    }

    await _addRecoverablePlans(add);

    final desiredStores = <_DesiredStoreRefs>[];
    for (final lineage in lineages) {
      final managedSkillId = ManagedSkillId(lineage.managedSkillId);
      final storePath = _layout.revisionStorePath(managedSkillId);
      final objects =
          (rootsByLineage[lineage.id] ?? const <RevisionObjectId>{}).toList()
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

  Future<void> _addRecoverablePlans(
    void Function(String lineage, RevisionObjectId object) add,
  ) async {
    final journals = await _database.select(_database.operationJournals).get();
    for (final journal in journals) {
      if (journal.phase == OperationJournalPhase.completed.name) continue;
      final definition = _codec.decodeDefinition(
        schemaVersion: journal.planSchemaVersion,
        payload: journal.planJson,
      );
      if (definition is! OperationPlan) continue;
      for (final change in definition.revisionSelectionChanges) {
        for (final address in [
          change.previousUpstream,
          change.previousEffective,
          change.intendedUpstream,
          change.intendedEffective,
        ]) {
          if (address != null) {
            add(address.sourceLineage.encoded, address.objectId);
          }
        }
      }

      for (final subject in definition.record.subjects) {
        final lineage = subject.sourceLineage;
        if (lineage == null) continue;
        if (subject.beforeObjectId case final object?) {
          add(lineage.encoded, object);
        }
        if (subject.afterObjectId case final object?) {
          add(lineage.encoded, object);
        }
      }

      for (final mutation in definition.businessChanges.mutations) {
        switch (mutation) {
          case PutRevisionMetadata(:final sourceLineageId, :final objectId):
            add(sourceLineageId, RevisionObjectId(objectId));
          case PutDraftWorkspace(:final sourceLineageId, :final baseObjectId):
            add(sourceLineageId, RevisionObjectId(baseObjectId));
          case PutUpdateCandidateSession(
            :final sourceLineageId,
            :final previousUpstreamObjectId,
            :final previousEffectiveObjectId,
            :final incomingUpstreamObjectId,
            :final candidateObjectId,
          ):
            for (final object in [
              previousUpstreamObjectId,
              previousEffectiveObjectId,
              incomingUpstreamObjectId,
              candidateObjectId,
            ]) {
              add(sourceLineageId, RevisionObjectId(object));
            }
          default:
            break;
        }
      }
    }
  }
}

final class _DesiredStoreRefs {
  const _DesiredStoreRefs(this.repositoryPath, this.references);

  final String repositoryPath;
  final List<RevisionRetentionRef> references;
}
