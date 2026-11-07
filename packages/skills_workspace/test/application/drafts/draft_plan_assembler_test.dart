import 'package:skills_workspace/src/application/drafts/draft_models.dart';
import 'package:skills_workspace/src/application/drafts/draft_plan_assembler.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

void main() {
  const assembler = DraftPlanAssembler();

  test('Ensure Draft must materialize the selected Effective revision', () {
    final result = assembler.assembleEnsure(
      preflight: _ensurePreflight(),
      prepared: PreparedEnsureDraft(
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        baseObjectId: _object('9'),
        draftRecoveryReference: RecoveryReference('draft'),
      ),
    );

    expect(
      result.failureOrNull?.code,
      DraftPlanningFailureCode.invalidPreparedEvidence,
    );
  });

  test('local Publish appends to Effective and preserves Upstream', () {
    final result = assembler.assemblePublish(
      preflight: _publishPreflight(),
      prepared: _preparedPublish(),
    );

    final plan = result.valueOrNull!;
    final selection = plan.revisionSelectionChanges.single;
    expect(selection.intendedUpstream?.objectId, _object('1'));
    expect(selection.intendedEffective?.objectId, _object('4'));
    expect(
      plan.businessChanges.mutations.whereType<PutDraftWorkspace>(),
      hasLength(1),
    );
    expect(plan.recoveryIntent.draftCleanup.expectedBaseObjectId, _object('4'));
    expect(plan.materializationIntents, hasLength(1));
  });

  test('local Publish rejects an Effective commit with wrong parent', () {
    final result = assembler.assemblePublish(
      preflight: _publishPreflight(),
      prepared: _preparedPublish(parent: _object('1')),
    );

    expect(
      result.failureOrNull?.code,
      DraftPlanningFailureCode.invalidPreparedEvidence,
    );
  });

  test('local Publish rejects a Declared Name change', () {
    final result = assembler.assemblePublish(
      preflight: _publishPreflight(),
      prepared: _preparedPublish(declaredName: 'other'),
    );

    expect(
      result.failureOrNull?.code,
      DraftPlanningFailureCode.invalidPreparedEvidence,
    );
  });
}

EnsureDraftPreparationRequired _ensurePreflight() =>
    EnsureDraftPreparationRequired(
      snapshotRevision: RepositoryRevision(5),
      plannedAtMicros: 10,
      skill: _skill(),
      state: _state(),
    );

PublishDraftPreparationRequired _publishPreflight() =>
    PublishDraftPreparationRequired(
      snapshotRevision: RepositoryRevision(5),
      plannedAtMicros: 10,
      skill: _skill(draft: _draft()),
      state: _state(),
    );

PreparedDraftPublish _preparedPublish({
  RevisionObjectId? parent,
  String declaredName = 'one',
}) => PreparedDraftPublish(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  treeObjectId: _object('3'),
  effectiveObjectId: _object('4'),
  effectiveRequest: RevisionCommitRequest(
    tree: _object('3'),
    parents: <RevisionObjectId>[parent ?? _object('2')],
    kind: RevisionCommitKind.localPublish,
  ),
  contentHash: 'b' * 64,
  fileCount: 1,
  byteSize: 2,
  declaredName: declaredName,
  description: 'Changed',
  draftAction: PublishedDraftAction.deleteUnchanged,
  capturedDraftFingerprint: DraftFingerprint(const []),
  candidateRecoveryReference: RecoveryReference('candidate'),
  bundleRecoveryReference: RecoveryReference('bundle'),
  materializationRecoveryReference: RecoveryReference('materialization'),
  draftRecoveryReference: RecoveryReference('draft'),
);

DraftRevisionState _state() => DraftRevisionState(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  currentUpstream: _object('1'),
  currentEffective: _object('2'),
  managedSkillCreatedAtMicros: 1,
  draftCreatedAtMicros: 2,
);

ManagedSkill _skill({DraftSummary? draft}) => ManagedSkill(
  id: _skillId,
  slotKey: 'one',
  declaredName: 'one',
  displayName: 'One',
  description: 'Old',
  source: LocalSourceDescriptor(locator: '/source/one'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: 'a' * 64,
    fileCount: 1,
    byteSize: 1,
    publishedAt: DateTime.utc(2026, 8, 1),
  ),
  draft: draft,
);

DraftSummary _draft() => DraftSummary(
  purpose: DraftPurpose.customization,
  path: '/drafts/${_skillId.value}',
  isDirty: true,
  updatedAt: DateTime.utc(2026, 8, 17),
);

final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _lineage = SourceLineageReference('lineage-1');
RevisionObjectId _object(String character) => RevisionObjectId(character * 40);
