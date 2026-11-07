import 'dart:io';

import 'package:skills_workspace/src/application/drift/drift_plan_assembler.dart';
import 'package:skills_workspace/src/application/drift/drift_models.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

import '../../support/drift_test_support.dart';

void main() {
  const assembler = DriftPlanAssembler();

  test(
    'keep appends local publication and rebuilds repository plus every activation',
    () {
      final activations = [
        SkillActivation(
          location: '${Directory.systemTemp.path}/copy',
          scope: ActivationScope.global,
          mode: ActivationMode.copy,
          agentIds: ['one'],
        ),
        SkillActivation(
          location: '${Directory.systemTemp.path}/link',
          scope: ActivationScope.global,
          mode: ActivationMode.symbolicLink,
          agentIds: ['two'],
        ),
      ];
      final result = assembler.assemble(
        preflight: driftPreflight(skill: driftSkill(activations: activations)),
        prepared: prepared(),
      );
      final plan = result.valueOrNull!;
      final selection = plan.revisionSelectionChanges.single;
      expect(selection.previousEffective!.objectId, driftObject('2'));
      expect(selection.intendedEffective!.objectId, driftObject('5'));
      expect(selection.intendedUpstream!.objectId, driftObject('1'));
      expect(plan.materializationIntents, hasLength(3));
      expect(
        plan.materializationIntents.first,
        isA<RestoreRepositoryMaterializationIntent>(),
      );
      expect(
        plan.materializationIntents
            .whereType<RestoreActivationMaterializationIntent>()
            .map((intent) => intent.activation),
        activations,
      );
      expect(
        plan.businessChanges.mutations.whereType<PutDraftWorkspace>(),
        isEmpty,
      );
      expect(
        plan.businessChanges.mutations
            .whereType<PutRevisionMetadata>()
            .single
            .contentHash,
        'b' * 64,
      );
      expect(plan.recoveryIntent.retainedRoots, [driftObject('5')]);
      expect(plan.recoveryIntent.draftCleanup, isNull);
    },
  );

  test('a clean Draft is reanchored with its reviewed cleanup fingerprint', () {
    final result = assembler.assemble(
      preflight: driftPreflight(
        skill: driftSkill(draft: driftDraft()),
        hadCleanDraft: true,
      ),
      prepared: prepared(draftAction: RestoreDraftAction.preserveAndReanchor),
    );
    final plan = result.valueOrNull!;
    expect(
      plan.businessChanges.mutations
          .whereType<PutDraftWorkspace>()
          .single
          .baseObjectId,
      driftObject('5').value,
    );
    expect(
      plan.recoveryIntent.draftCleanup!.expectedBaseObjectId,
      driftObject('5'),
    );
    expect(
      plan.recoveryIntent.draftCleanup!.capturedFingerprint,
      DraftFingerprint(const []),
    );
  });

  for (final pair in <String, PreparedRestorePublish>{
    'wrong parent': prepared(parent: driftObject('1')),
    'wrong commit kind': prepared(kind: RevisionCommitKind.restorePublish),
    'wrong content fingerprint': prepared(contentHash: 'c' * 64),
    'renamed skill': prepared(declaredName: 'changed'),
    'wrong selected revision': prepared(selected: driftObject('1')),
    'wrong tree': prepared(requestTree: driftObject('4')),
    'unexpected Draft mutation': prepared(
      draftAction: RestoreDraftAction.preserveAndReanchor,
    ),
  }.entries) {
    test('rejects ${pair.key} before an operation plan is sealed', () {
      final result = assembler.assemble(
        preflight: driftPreflight(),
        prepared: pair.value,
      );
      expect(result.failureOrNull!.code, DriftFailureCode.invalidSkill);
    });
  }

  test('cannot drop an existing clean Draft during preparation', () {
    final result = assembler.assemble(
      preflight: driftPreflight(hadCleanDraft: true),
      prepared: prepared(),
    );
    expect(result.failureOrNull!.code, DriftFailureCode.invalidSkill);
  });
}

PreparedRestorePublish prepared({
  RevisionObjectId? parent,
  RevisionObjectId? selected,
  RevisionObjectId? requestTree,
  RevisionCommitKind kind = RevisionCommitKind.localPublish,
  String contentHash = '',
  String declaredName = 'sample',
  RestoreDraftAction draftAction = RestoreDraftAction.noDraft,
}) => PreparedRestorePublish(
  managedSkillId: driftSkillId,
  sourceLineage: driftLineage,
  selectedObjectId: selected ?? driftObject('2'),
  treeObjectId: driftObject('3'),
  effectiveObjectId: driftObject('5'),
  effectiveRequest: RevisionCommitRequest(
    tree: requestTree ?? driftObject('3'),
    parents: [parent ?? driftObject('2')],
    kind: kind,
  ),
  contentHash: contentHash.isEmpty ? 'b' * 64 : contentHash,
  fileCount: 1,
  byteSize: 2,
  declaredName: declaredName,
  description: 'External',
  draftAction: draftAction,
  capturedDraftFingerprint: draftAction == RestoreDraftAction.noDraft
      ? null
      : DraftFingerprint(const []),
  candidateRecoveryReference: RecoveryReference('candidate'),
  bundleRecoveryReference: RecoveryReference('bundle'),
  materializationRecoveryReference: RecoveryReference('materialization'),
  draftRecoveryReference: RecoveryReference('draft'),
);
