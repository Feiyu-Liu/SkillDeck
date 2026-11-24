import 'package:drift/drift.dart';

import '../../application/operations/operation_models.dart';
import '../../application/ports/revision_store_access_ports.dart';
import '../../application/revision_store/revision_store_access_models.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/identifiers.dart';
import '../../domain/source_descriptor.dart';
import 'source_descriptor_codec.dart';
import 'workspace_database.dart';

/// Read-only Drift adapter for authoritative Revision Pointer selection.
final class DriftRevisionPointerReader implements RevisionPointerReaderPort {
  const DriftRevisionPointerReader(this._database);

  final WorkspaceDatabase _database;

  @override
  Future<CurrentEffectiveRevisionSelection?> readCurrentEffective(
    ManagedSkillId managedSkillId,
  ) async {
    final row = await _selectCurrent(managedSkillId);
    if (row == null) return null;
    final selectionRow = row.readTable(_database.currentRevisionSelection);
    return CurrentEffectiveRevisionSelection(
      sourceLineage: SourceLineageReference(selectionRow.sourceLineageId),
      objectId: RevisionObjectId(selectionRow.effectiveObjectId),
    );
  }

  Future<({RevisionObjectId effective, RevisionObjectId? upstream})?>
  readCurrentPackHeads(ManagedSkillId managedSkillId) async {
    final row = await _selectCurrent(managedSkillId, includeSource: true);
    if (row == null) return null;
    final selection = row.readTable(_database.currentRevisionSelection);
    final source = row.readTable(_database.skillSources);
    // Adoption stores a baseline for recovery but has no tracked Source.
    final hasUpstream = switch (source.kind) {
      'adoptedSnapshot' => false,
      'syncedOrigin' => switch (const SourceDescriptorCodec().decode(
        kind: source.kind,
        payloadSchemaVersion: source.payloadSchemaVersion,
        payloadJson: source.payloadJson,
      )) {
        SyncedOriginSourceDescriptor(
          originSourceType: SyncedOriginSourceType.adoptedSnapshot,
        ) =>
          false,
        _ => true,
      },
      _ => true,
    };
    return (
      effective: RevisionObjectId(selection.effectiveObjectId),
      upstream: hasUpstream
          ? RevisionObjectId(selection.upstreamObjectId)
          : null,
    );
  }

  Future<TypedResult?> _selectCurrent(
    ManagedSkillId managedSkillId, {
    bool includeSource = false,
  }) {
    final selection = _database.currentRevisionSelection;
    final lineage = _database.sourceLineages;
    final skill = _database.managedSkills;
    final source = _database.skillSources;
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
        if (includeSource)
          innerJoin(source, source.sourceLineageId.equalsExp(lineage.id)),
      ],
    )..where(selection.managedSkillId.equals(managedSkillId.value));
    return query.getSingleOrNull();
  }
}
