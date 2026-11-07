import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;

import '../../application/drafts/draft_snapshot_coordinator.dart';
import '../../application/operations/operation_models.dart';
import '../../application/ports/draft_dirty_state_ports.dart';
import '../../application/ports/draft_snapshot_ports.dart';
import '../../application/ports/revision_store_access_ports.dart';
import '../../application/ports/update_ports.dart';
import '../../application/revision_store/managed_skill_revision_access_gate.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../application/update/update_models.dart';
import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../workspace_layout.dart';
import 'workspace_database.dart' as db;

/// Computes authoritative Draft dirty state from Draft Base and live bytes.
///
/// The Draft row and Source Lineage are selected in SQLite, protected by
/// shared canonical Store admission, then revalidated before the base tree is
/// read. The watcher hint and public Snapshot's cached `isDirty` projection
/// never participate in the answer.
final class DriftUpdateDraftInspection
    implements UpdateDraftInspectionPort, DraftDirtyStateInspectionPort {
  const DriftUpdateDraftInspection({
    required db.WorkspaceDatabase database,
    required WorkspaceLayout layout,
    required ManagedSkillRevisionAccessGate accessGate,
    required RevisionStorePathResolver storePath,
    required RevisionEnginePort revisions,
    required DraftSnapshotCoordinator snapshots,
  }) : _database = database,
       _layout = layout,
       _accessGate = accessGate,
       _storePath = storePath,
       _revisions = revisions,
       _snapshots = snapshots;

  final db.WorkspaceDatabase _database;
  final WorkspaceLayout _layout;
  final ManagedSkillRevisionAccessGate _accessGate;
  final RevisionStorePathResolver _storePath;
  final RevisionEnginePort _revisions;
  final DraftSnapshotCoordinator _snapshots;

  @override
  Future<UpdateDraftInspectionResult> inspectForUpdate({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  }) async {
    if (skill.draft == null) {
      return const UpdateDraftInspectionSuccess(UpdateDraftInspection.absent());
    }
    final result = await inspectDraftDirtyState(
      skill: skill,
      cancellationToken: cancellationToken,
    );
    return switch (result) {
      DraftDirtyStateInspectionSuccess(:final isDirty) =>
        UpdateDraftInspectionSuccess(
          isDirty
              ? const UpdateDraftInspection.dirty()
              : const UpdateDraftInspection.clean(),
        ),
      DraftDirtyStateInspectionFailure(:final reason) =>
        UpdateDraftInspectionFailure(reason),
    };
  }

  @override
  Future<DraftDirtyStateInspectionResult> inspectDraftDirtyState({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return const DraftDirtyStateInspectionFailure('operationCancelled');
    }
    final selected = await _readSelection(skill.id);
    if (selected == null) {
      return skill.draft == null
          ? const DraftDirtyStateInspectionSuccess(isDirty: false)
          : const DraftDirtyStateInspectionFailure('draftStateUnavailable');
    }
    ManagedSkillRevisionAccessPermit permit;
    try {
      permit = await _accessGate.acquireRead(
        skill.id,
        cancellationToken: cancellationToken,
      );
    } on ManagedSkillRevisionAccessCancelled {
      return const DraftDirtyStateInspectionFailure('operationCancelled');
    } on Object {
      return const DraftDirtyStateInspectionFailure('revisionStoreUnavailable');
    }
    try {
      if (cancellationToken.isCancelled) {
        return const DraftDirtyStateInspectionFailure('operationCancelled');
      }
      if (await _readSelection(skill.id) != selected) {
        return const DraftDirtyStateInspectionFailure('draftStateChanged');
      }
      final base = await _revisions.readTree(
        _storePath(skill.id),
        selected.baseObjectId,
      );
      final result = await _snapshots.inspectDirty(
        request: DraftCaptureRequest(
          liveDraftPath: _layout.draftPath(skill.id),
          stagingDestinationPath: path.join(
            _layout.stagingRoot,
            'draft-inspection-${skill.id.value}',
          ),
          capturePosixExecutableIntent: !Platform.isWindows,
          executableIntentOverrides: <String, bool>{
            for (final file in base.files) file.relativePath: file.isExecutable,
          },
          isCancelled: () => cancellationToken.isCancelled,
        ),
        draftBase: base,
      );
      final dirty = result.valueOrNull;
      if (dirty == null) {
        final code = result.failureOrNull!.code;
        if (code == DraftSnapshotFailureCode.invalidSkill ||
            code == DraftSnapshotFailureCode.skillContentLimitExceeded) {
          // A valid immutable Draft Base cannot normalize to either state.
          // Keep the Workspace readable and conservatively block Update until
          // the user repairs or discards these unpublished bytes.
          return const DraftDirtyStateInspectionSuccess(isDirty: true);
        }
        return DraftDirtyStateInspectionFailure(code.name);
      }
      return DraftDirtyStateInspectionSuccess(isDirty: dirty);
    } on RevisionEngineException catch (error) {
      return DraftDirtyStateInspectionFailure(error.code.name);
    } on Object {
      return const DraftDirtyStateInspectionFailure('ioFailure');
    } finally {
      await permit.release();
    }
  }

  Future<_DraftBaseSelection?> _readSelection(ManagedSkillId id) {
    final drafts = _database.draftWorkspaces;
    final lineages = _database.sourceLineages;
    final query = _database.select(drafts).join(<Join<HasResultSet, dynamic>>[
      innerJoin(
        lineages,
        lineages.id.equalsExp(drafts.sourceLineageId) &
            lineages.managedSkillId.equalsExp(drafts.managedSkillId),
      ),
    ])..where(drafts.managedSkillId.equals(id.value));
    return query.getSingleOrNull().then((row) {
      if (row == null) return null;
      final draft = row.readTable(drafts);
      final lineage = row.readTable(lineages);
      return _DraftBaseSelection(
        sourceLineage: SourceLineageReference(lineage.id),
        baseObjectId: RevisionObjectId(draft.baseObjectId),
      );
    });
  }
}

final class _DraftBaseSelection {
  const _DraftBaseSelection({
    required this.sourceLineage,
    required this.baseObjectId,
  });

  final SourceLineageReference sourceLineage;
  final RevisionObjectId baseObjectId;

  @override
  bool operator ==(Object other) =>
      other is _DraftBaseSelection &&
      sourceLineage == other.sourceLineage &&
      baseObjectId == other.baseObjectId;

  @override
  int get hashCode => Object.hash(sourceLineage, baseObjectId);
}
