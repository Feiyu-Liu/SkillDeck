import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/history/restore_plan_assembler.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

void main() {
  const assembler = RestorePlanAssembler();

  test(
    'Restore appends a new Effective revision without rewinding Upstream',
    () {
      final result = assembler.assemble(
        preflight: _preflight(),
        prepared: _prepared(),
      );

      final plan = result.valueOrNull!;
      final selection = plan.revisionSelectionChanges.single;
      expect(selection.intendedUpstream?.objectId, _object('1'));
      expect(selection.intendedEffective?.objectId, _object('5'));
      expect(
        plan.businessChanges.mutations.whereType<PutDraftWorkspace>(),
        hasLength(1),
      );
      expect(plan.recoveryIntent.draftCleanup, isNotNull);
      expect(
        plan.recoveryIntent.draftCleanup!.expectedBaseObjectId,
        _object('5'),
      );
    },
  );

  test('Restore commit has current Effective as sole parent', () {
    final result = assembler.assemble(
      preflight: _preflight(),
      prepared: _prepared(parent: _object('1')),
    );

    expect(
      result.failureOrNull?.code,
      HistoryFailureCode.invalidPreparedEvidence,
    );
  });

  test('Restore rejects a historical Declared Name mismatch', () {
    final result = assembler.assemble(
      preflight: _preflight(),
      prepared: _prepared(declaredName: 'other'),
    );

    expect(
      result.failureOrNull?.code,
      HistoryFailureCode.invalidPreparedEvidence,
    );
  });
}

RestorePublishPreflight _preflight() => RestorePublishPreflight(
  snapshotRevision: RepositoryRevision(5),
  plannedAtMicros: 10,
  skill: _skill(),
  selected: HistoricalRevisionSelection(
    reference: _reference,
    managedSkillId: _skillId,
    sourceLineage: _lineage,
    objectId: _object('4'),
    contentHash: 'a' * 64,
    declaredName: 'one',
  ),
  state: RestoreRevisionState(
    managedSkillId: _skillId,
    sourceLineage: _lineage,
    currentUpstream: _object('1'),
    currentEffective: _object('2'),
    managedSkillCreatedAtMicros: 1,
    draftCreatedAtMicros: 2,
  ),
  hadCleanDraft: true,
);

PreparedRestorePublish _prepared({
  RevisionObjectId? parent,
  String declaredName = 'one',
}) => PreparedRestorePublish(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  selectedObjectId: _object('4'),
  treeObjectId: _object('3'),
  effectiveObjectId: _object('5'),
  effectiveRequest: RevisionCommitRequest(
    tree: _object('3'),
    parents: <RevisionObjectId>[parent ?? _object('2')],
    kind: RevisionCommitKind.restorePublish,
  ),
  contentHash: 'a' * 64,
  fileCount: 1,
  byteSize: 2,
  declaredName: declaredName,
  description: 'Historical',
  draftAction: RestoreDraftAction.deleteUnchanged,
  capturedDraftFingerprint: DraftFingerprint(const []),
  candidateRecoveryReference: RecoveryReference('candidate'),
  bundleRecoveryReference: RecoveryReference('bundle'),
  materializationRecoveryReference: RecoveryReference('materialization'),
  draftRecoveryReference: RecoveryReference('draft'),
);

ManagedSkill _skill() => ManagedSkill(
  id: _skillId,
  slotKey: 'one',
  declaredName: 'one',
  displayName: 'One',
  description: 'Current',
  source: LocalSourceDescriptor(locator: '/source/one'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: 'a' * 64,
    fileCount: 1,
    byteSize: 1,
    publishedAt: DateTime.utc(2026, 8, 1),
  ),
  draft: DraftSummary(
    purpose: DraftPurpose.customization,
    path: '/drafts/${_skillId.value}',
    isDirty: false,
    updatedAt: DateTime.utc(2026, 8, 17),
  ),
);

final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _lineage = SourceLineageReference('lineage-1');
final _reference = OperationSubjectReference(
  operationId: OperationId('123e4567-e89b-42d3-8456-426614174001'),
  subjectId: '123e4567-e89b-42d3-9456-426614174002',
);
RevisionObjectId _object(String character) => RevisionObjectId(character * 40);
