import 'package:drift/drift.dart';

import '../../application/drafts/draft_models.dart';
import '../../application/drafts/draft_ports.dart';
import '../../application/operations/operation_models.dart';
import '../../application/operations/workspace_business_changes.dart';
import '../../application/ports/update_ports.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../application/update/update_candidate_content_port.dart';
import '../../application/update/update_models.dart';
import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import 'workspace_database.dart' as db;

/// Drift-owned state projection shared by Draft and Update application flows.
/// Mutable Draft bytes remain behind the injected authoritative inspection
/// port; candidate frontmatter remains in the Revision Store.
final class DriftDraftUpdateState
    implements
        DraftWorkspaceStatePort,
        UpdateRevisionStatePort,
        UpdateCandidateStatePort {
  const DriftDraftUpdateState({
    required db.WorkspaceDatabase database,
    required UpdateDraftInspectionPort draftInspection,
    required UpdateCandidateContentPort candidateContent,
  }) : _database = database,
       _draftInspection = draftInspection,
       _candidateContent = candidateContent;

  final db.WorkspaceDatabase _database;
  final UpdateDraftInspectionPort _draftInspection;
  final UpdateCandidateContentPort _candidateContent;

  @override
  Future<DraftRevisionState?> readDraftState(
    ManagedSkillId managedSkillId,
  ) async {
    final state = await _readCurrentState(managedSkillId);
    if (state == null) return null;
    return DraftRevisionState(
      managedSkillId: managedSkillId,
      sourceLineage: state.lineage,
      currentUpstream: state.upstream,
      currentEffective: state.effective,
      managedSkillCreatedAtMicros: state.managedSkillCreatedAtMicros,
      draftCreatedAtMicros: state.draftCreatedAtMicros,
    );
  }

  @override
  Future<DraftPlanningResult<DraftSummary?>> inspectDraft({
    required ManagedSkill skill,
    required DraftRevisionState state,
    required CancellationToken cancellationToken,
  }) async {
    final summary = skill.draft;
    if (summary == null) {
      return const DraftPlanningSuccess<DraftSummary?>(null);
    }
    final inspected = await _draftInspection.inspectForUpdate(
      skill: skill,
      cancellationToken: cancellationToken,
    );
    return switch (inspected) {
      UpdateDraftInspectionSuccess(:final inspection) =>
        DraftPlanningSuccess<DraftSummary?>(
          DraftSummary(
            purpose: summary.purpose,
            path: summary.path,
            isDirty: inspection.isDirty,
            updatedAt: summary.updatedAt,
          ),
        ),
      UpdateDraftInspectionFailure(:final reason) =>
        DraftPlanningFailure<DraftSummary?>(
          code: DraftPlanningFailureCode.ioFailure,
          context: <String, Object?>{'reason': reason},
        ),
    };
  }

  @override
  Future<UpdateRevisionState?> readUpdateState(
    ManagedSkillId managedSkillId,
  ) async {
    final state = await _readCurrentState(managedSkillId);
    if (state == null) return null;
    final metadata = _database.revisionMetadata;
    final upstream =
        await (_database.select(metadata)
              ..where(
                (row) =>
                    row.sourceLineageId.equals(state.lineage.encoded) &
                    row.objectId.equals(state.upstream.value),
              )
              ..limit(1))
            .getSingleOrNull();
    if (upstream == null) return null;
    return UpdateRevisionState(
      managedSkillId: managedSkillId,
      sourceLineage: state.lineage,
      previousUpstream: state.upstream,
      currentEffective: state.effective,
      previousUpstreamContentHash: upstream.contentHash,
      managedSkillCreatedAtMicros: state.managedSkillCreatedAtMicros,
      draftCreatedAtMicros: state.draftCreatedAtMicros,
    );
  }

  @override
  Future<UpdateCandidateState?> readCandidateState(
    ManagedSkillId managedSkillId, {
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) return null;
    final sessions = _database.updateCandidateSessions;
    final lineages = _database.sourceLineages;
    final skills = _database.managedSkills;
    final drafts = _database.draftWorkspaces;
    final query = _database.select(sessions).join(<Join<HasResultSet, dynamic>>[
      innerJoin(
        lineages,
        lineages.id.equalsExp(sessions.sourceLineageId) &
            lineages.managedSkillId.equalsExp(sessions.managedSkillId),
      ),
      innerJoin(skills, skills.id.equalsExp(sessions.managedSkillId)),
      innerJoin(
        drafts,
        drafts.managedSkillId.equalsExp(sessions.managedSkillId),
      ),
    ])..where(sessions.managedSkillId.equals(managedSkillId.value));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final session = row.readTable(sessions);
    final lineage = row.readTable(lineages);
    final skill = row.readTable(skills);
    final draft = row.readTable(drafts);
    final sourceLineage = SourceLineageReference(lineage.id);
    final content = await _candidateContent.readCandidateContent(
      managedSkillId: managedSkillId,
      sourceLineage: sourceLineage,
      candidateObjectId: RevisionObjectId(session.candidateObjectId),
      cancellationToken: cancellationToken,
    );
    if (content == null) return null;
    final itemRows = await (_database.select(
      _database.updateCandidateItems,
    )..where((item) => item.managedSkillId.equals(managedSkillId.value))).get();
    itemRows.sort((left, right) => left.path.compareTo(right.path));
    final retainedPublishedRoots = await _readPublishedRoots(
      managedSkillId: managedSkillId,
      sourceLineage: sourceLineage,
    );
    return UpdateCandidateState(
      managedSkillId: managedSkillId,
      sourceLineage: sourceLineage,
      previousUpstream: RevisionObjectId(session.previousUpstreamObjectId),
      previousEffective: RevisionObjectId(session.previousEffectiveObjectId),
      incomingUpstream: RevisionObjectId(session.incomingUpstreamObjectId),
      candidateObjectId: RevisionObjectId(session.candidateObjectId),
      incomingDeclaredName: content.declaredName,
      incomingSlotKey: content.slotKey,
      incomingDescription: content.description,
      managedSkillCreatedAtMicros: skill.createdAtMicros,
      draftCreatedAtMicros: draft.createdAtMicros,
      retainedPublishedRoots: retainedPublishedRoots,
      conflicts: itemRows.map(_candidateItem).toList(growable: false),
    );
  }

  Future<List<RevisionObjectId>> _readPublishedRoots({
    required ManagedSkillId managedSkillId,
    required SourceLineageReference sourceLineage,
  }) async {
    final subjects = _database.operationSubjects;
    final records = _database.operationRecords;
    final query =
        _database.select(subjects).join(<Join<HasResultSet, dynamic>>[
          innerJoin(
            records,
            records.operationId.equalsExp(subjects.operationId),
          ),
        ])..where(
          subjects.managedSkillId.equals(managedSkillId.value) &
              subjects.sourceLineageId.equals(sourceLineage.encoded) &
              records.status.equals('succeeded'),
        );
    final roots = <String, RevisionObjectId>{};
    for (final row in await query.get()) {
      final subject = row.readTable(subjects);
      if (subject.beforeObjectId case final object?) {
        roots[object] = RevisionObjectId(object);
      }
      if (subject.afterObjectId case final object?) {
        roots[object] = RevisionObjectId(object);
      }
    }
    final values = roots.values.toList(growable: false)
      ..sort((left, right) => left.value.compareTo(right.value));
    return List<RevisionObjectId>.unmodifiable(values);
  }

  Future<_CurrentState?> _readCurrentState(
    ManagedSkillId managedSkillId,
  ) async {
    final selections = _database.currentRevisionSelection;
    final lineages = _database.sourceLineages;
    final skills = _database.managedSkills;
    final drafts = _database.draftWorkspaces;
    final query =
        _database.select(selections).join(<Join<HasResultSet, dynamic>>[
          innerJoin(
            lineages,
            lineages.id.equalsExp(selections.sourceLineageId) &
                lineages.managedSkillId.equalsExp(selections.managedSkillId),
          ),
          innerJoin(
            skills,
            skills.id.equalsExp(selections.managedSkillId) &
                skills.activeSourceLineageId.equalsExp(
                  selections.sourceLineageId,
                ),
          ),
          leftOuterJoin(
            drafts,
            drafts.managedSkillId.equalsExp(selections.managedSkillId),
          ),
        ])..where(selections.managedSkillId.equals(managedSkillId.value));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final selection = row.readTable(selections);
    final lineage = row.readTable(lineages);
    final skill = row.readTable(skills);
    final draft = row.readTableOrNull(drafts);
    return _CurrentState(
      lineage: SourceLineageReference(lineage.id),
      upstream: RevisionObjectId(selection.upstreamObjectId),
      effective: RevisionObjectId(selection.effectiveObjectId),
      managedSkillCreatedAtMicros: skill.createdAtMicros,
      draftCreatedAtMicros: draft?.createdAtMicros,
    );
  }
}

WorkspaceUpdateCandidateItem _candidateItem(db.UpdateCandidateItem item) =>
    WorkspaceUpdateCandidateItem(
      path: item.path,
      kind: WorkspaceUpdateCandidateItemKind.values.byName(item.kind),
      state: WorkspaceUpdateCandidateItemState.values.byName(item.state),
      baseObjectId: item.baseObjectId,
      oursObjectId: item.oursObjectId,
      theirsObjectId: item.theirsObjectId,
    );

final class _CurrentState {
  const _CurrentState({
    required this.lineage,
    required this.upstream,
    required this.effective,
    required this.managedSkillCreatedAtMicros,
    required this.draftCreatedAtMicros,
  });

  final SourceLineageReference lineage;
  final RevisionObjectId upstream;
  final RevisionObjectId effective;
  final int managedSkillCreatedAtMicros;
  final int? draftCreatedAtMicros;
}
