import '../drafts/draft_models.dart';
import '../operations/operation_models.dart';
import '../operations/workspace_business_changes.dart';
import '../runtime/revision_engine_port.dart';
import '../history/history_models.dart';
import 'drift_models.dart';

final class DriftPlanAssembler {
  const DriftPlanAssembler();

  DriftResult<PreparedRestorePublishPlan> assemble({
    required DriftResolutionPreflight preflight,
    required PreparedRestorePublish prepared,
  }) {
    final skill = preflight.skill;
    final state = preflight.state;
    if (prepared.managedSkillId != skill.id ||
        prepared.sourceLineage != state.sourceLineage ||
        prepared.selectedObjectId != state.currentEffective ||
        prepared.contentHash != preflight.selectedFingerprint ||
        prepared.declaredName != skill.declaredName ||
        prepared.effectiveRequest.kind != RevisionCommitKind.localPublish ||
        prepared.effectiveRequest.tree != prepared.treeObjectId ||
        prepared.effectiveRequest.parents.length != 1 ||
        prepared.effectiveRequest.parents.single != state.currentEffective) {
      return DriftFailure<PreparedRestorePublishPlan>(
        code: DriftFailureCode.invalidSkill,
      );
    }
    if (!preflight.hadCleanDraft &&
        prepared.draftAction != RestoreDraftAction.noDraft) {
      return DriftFailure<PreparedRestorePublishPlan>(
        code: DriftFailureCode.invalidSkill,
      );
    }
    if (preflight.hadCleanDraft &&
        prepared.draftAction == RestoreDraftAction.noDraft) {
      return DriftFailure<PreparedRestorePublishPlan>(
        code: DriftFailureCode.invalidSkill,
      );
    }
    final previousUpstream = RevisionAddress(
      sourceLineage: state.sourceLineage,
      objectId: state.currentUpstream,
    );
    final previousEffective = RevisionAddress(
      sourceLineage: state.sourceLineage,
      objectId: state.currentEffective,
    );
    final intendedEffective = RevisionAddress(
      sourceLineage: state.sourceLineage,
      objectId: prepared.effectiveObjectId,
    );
    final draftMutations = switch (prepared.draftAction) {
      RestoreDraftAction.noDraft => const <WorkspaceBusinessMutation>[],
      RestoreDraftAction.deleteUnchanged ||
      RestoreDraftAction.preserveAndReanchor => <WorkspaceBusinessMutation>[
        PutDraftWorkspace(
          managedSkillId: skill.id,
          sourceLineageId: state.sourceLineage.encoded,
          baseObjectId: prepared.effectiveObjectId.value,
          purpose: WorkspaceDraftPurpose.customization,
          createdAtMicros:
              state.draftCreatedAtMicros ?? preflight.plannedAtMicros,
          updatedAtMicros: preflight.plannedAtMicros,
        ),
      ],
    };
    return DriftSuccess<PreparedRestorePublishPlan>(
      value: PreparedRestorePublishPlan(
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            PutRevisionMetadata(
              sourceLineageId: state.sourceLineage.encoded,
              objectId: prepared.effectiveObjectId.value,
              contentHash: prepared.contentHash,
              fileCount: prepared.fileCount,
              byteSize: prepared.byteSize,
              declaredName: prepared.declaredName,
              validationState: WorkspaceRevisionValidationState.valid,
              validationCode: null,
              createdAtMicros: preflight.plannedAtMicros,
            ),
            PutManagedSkill(
              managedSkillId: skill.id,
              slotKey: skill.slotKey,
              declaredName: skill.declaredName,
              displayName: skill.displayName,
              description: prepared.description,
              activeSourceLineageId: state.sourceLineage.encoded,
              createdAtMicros: state.managedSkillCreatedAtMicros,
              updatedAtMicros: preflight.plannedAtMicros,
            ),
            ...draftMutations,
          ],
        ),
        revisionSelectionChanges: <RevisionSelectionChangePlan>[
          RevisionSelectionChangePlan(
            managedSkillId: skill.id,
            previousUpstream: previousUpstream,
            previousEffective: previousEffective,
            intendedUpstream: previousUpstream,
            intendedEffective: intendedEffective,
          ),
        ],
        recoveryIntent: RestoreRevisionRecoveryIntent(
          managedSkillId: skill.id,
          sourceLineage: state.sourceLineage,
          retainedRoots: <RevisionObjectId>[prepared.effectiveObjectId],
          candidateRecoveryReference: prepared.candidateRecoveryReference,
          bundleRecoveryReference: prepared.bundleRecoveryReference,
          draftCleanup: prepared.capturedDraftFingerprint == null
              ? null
              : PublishedDraftCleanupIntent(
                  managedSkillId: skill.id,
                  expectedBaseObjectId: prepared.effectiveObjectId,
                  capturedFingerprint: prepared.capturedDraftFingerprint!,
                ),
        ),
        materializationIntents: <RestoreMaterializationIntent>[
          RestoreRepositoryMaterializationIntent(
            managedSkillId: skill.id,
            revision: intendedEffective,
            recoveryReference: prepared.materializationRecoveryReference,
            slotKey: skill.slotKey,
          ),
          for (final activation in skill.activations)
            RestoreActivationMaterializationIntent(
              managedSkillId: skill.id,
              revision: intendedEffective,
              recoveryReference: prepared.materializationRecoveryReference,
              activation: activation,
              slotKey: skill.slotKey,
            ),
        ],
      ),
    );
  }
}
