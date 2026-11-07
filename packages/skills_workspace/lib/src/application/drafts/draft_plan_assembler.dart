import '../operations/operation_models.dart';
import '../operations/workspace_business_changes.dart';
import '../runtime/revision_engine_port.dart';
import 'draft_models.dart';

final class DraftPlanAssembler {
  const DraftPlanAssembler();

  DraftPlanningResult<PreparedEnsureDraftPlan> assembleEnsure({
    required EnsureDraftPreparationRequired preflight,
    required PreparedEnsureDraft prepared,
  }) {
    final state = preflight.state;
    if (prepared.managedSkillId != preflight.skill.id ||
        prepared.sourceLineage != state.sourceLineage ||
        prepared.baseObjectId != state.currentEffective) {
      return _invalidEvidence();
    }
    return DraftPlanningSuccess<PreparedEnsureDraftPlan>(
      PreparedEnsureDraftPlan(
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            PutDraftWorkspace(
              managedSkillId: preflight.skill.id,
              sourceLineageId: state.sourceLineage.encoded,
              baseObjectId: state.currentEffective.value,
              purpose: WorkspaceDraftPurpose.customization,
              createdAtMicros: preflight.plannedAtMicros,
              updatedAtMicros: preflight.plannedAtMicros,
            ),
          ],
        ),
        draftRecoveryReference: prepared.draftRecoveryReference,
      ),
    );
  }

  DraftPlanningResult<PreparedDraftPublishPlan> assemblePublish({
    required PublishDraftPreparationRequired preflight,
    required PreparedDraftPublish prepared,
  }) {
    final skill = preflight.skill;
    final state = preflight.state;
    if (prepared.managedSkillId != skill.id ||
        prepared.sourceLineage != state.sourceLineage ||
        prepared.declaredName != skill.declaredName ||
        prepared.effectiveRequest.kind != RevisionCommitKind.localPublish ||
        prepared.effectiveRequest.tree != prepared.treeObjectId ||
        prepared.effectiveRequest.parents.length != 1 ||
        prepared.effectiveRequest.parents.single != state.currentEffective) {
      return _invalidEvidence();
    }
    final intendedEffective = RevisionAddress(
      sourceLineage: state.sourceLineage,
      objectId: prepared.effectiveObjectId,
    );
    final previousUpstream = RevisionAddress(
      sourceLineage: state.sourceLineage,
      objectId: state.currentUpstream,
    );
    final previousEffective = RevisionAddress(
      sourceLineage: state.sourceLineage,
      objectId: state.currentEffective,
    );
    // Draft deletion is a post-commit compare-and-delete. The BCP must first
    // preserve the row and re-anchor its Base to the new Effective revision.
    final draftMutations = <WorkspaceBusinessMutation>[
      PutDraftWorkspace(
        managedSkillId: skill.id,
        sourceLineageId: state.sourceLineage.encoded,
        baseObjectId: prepared.effectiveObjectId.value,
        purpose: WorkspaceDraftPurpose.customization,
        createdAtMicros:
            state.draftCreatedAtMicros ?? preflight.plannedAtMicros,
        updatedAtMicros: preflight.plannedAtMicros,
      ),
    ];
    return DraftPlanningSuccess<PreparedDraftPublishPlan>(
      PreparedDraftPublishPlan(
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
              displayName: skill.displayName == skill.declaredName
                  ? prepared.declaredName
                  : skill.displayName,
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
        recoveryIntent: DraftRevisionRecoveryIntent(
          managedSkillId: skill.id,
          sourceLineage: state.sourceLineage,
          retainedRoots: <RevisionObjectId>[prepared.effectiveObjectId],
          candidateRecoveryReference: prepared.candidateRecoveryReference,
          bundleRecoveryReference: prepared.bundleRecoveryReference,
          draftCleanup: PublishedDraftCleanupIntent(
            managedSkillId: skill.id,
            expectedBaseObjectId: prepared.effectiveObjectId,
            capturedFingerprint: prepared.capturedDraftFingerprint,
          ),
        ),
        materializationIntents: <DraftMaterializationIntent>[
          DraftRepositoryMaterializationIntent(
            managedSkillId: skill.id,
            revision: intendedEffective,
            recoveryReference: prepared.materializationRecoveryReference,
            slotKey: skill.slotKey,
          ),
          for (final activation in skill.activations)
            DraftActivationMaterializationIntent(
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

DraftPlanningFailure<T> _invalidEvidence<T>() => DraftPlanningFailure<T>(
  code: DraftPlanningFailureCode.invalidPreparedEvidence,
);
