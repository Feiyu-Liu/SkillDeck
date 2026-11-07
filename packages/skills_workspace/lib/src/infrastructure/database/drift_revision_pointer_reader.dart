import 'package:drift/drift.dart';

import '../../application/operations/operation_models.dart';
import '../../application/ports/revision_store_access_ports.dart';
import '../../application/revision_store/revision_store_access_models.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/identifiers.dart';
import 'workspace_database.dart';

/// Read-only Drift adapter for authoritative Revision Pointer selection.
final class DriftRevisionPointerReader implements RevisionPointerReaderPort {
  const DriftRevisionPointerReader(this._database);

  final WorkspaceDatabase _database;

  @override
  Future<CurrentEffectiveRevisionSelection?> readCurrentEffective(
    ManagedSkillId managedSkillId,
  ) async {
    final selection = _database.currentRevisionSelection;
    final lineage = _database.sourceLineages;
    final skill = _database.managedSkills;
    final query = _database.select(selection).join(
      <Join<HasResultSet, dynamic>>[
        innerJoin(
          lineage,
          lineage.id.equalsExp(selection.sourceLineageId) &
              lineage.managedSkillId.equalsExp(selection.managedSkillId),
        ),
        innerJoin(
          skill,
          skill.id.equalsExp(selection.managedSkillId) &
              skill.activeSourceLineageId.equalsExp(selection.sourceLineageId),
        ),
      ],
    )..where(selection.managedSkillId.equals(managedSkillId.value));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final selectionRow = row.readTable(selection);
    final lineageRow = row.readTable(lineage);
    return CurrentEffectiveRevisionSelection(
      sourceLineage: SourceLineageReference(lineageRow.id),
      objectId: RevisionObjectId(selectionRow.effectiveObjectId),
    );
  }
}
