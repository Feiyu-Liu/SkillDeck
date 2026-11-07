import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../../domain/source_descriptor.dart';
import '../operations/destructive_recovery_intent.dart';
import '../operations/operation_models.dart';
import '../operations/operation_plan_assembler.dart';
import '../operations/workspace_business_changes.dart';
import '../ports/destructive_operation_ports.dart';
import '../ports/initial_import_ports.dart';
import 'destructive_operation_models.dart';

typedef DestructivePlanningClock = int Function();

/// Plans identity-preserving Source Replacement and complete aggregate Removal
/// from one authoritative lock-held projection.
///
/// Stale destructive intent is intentionally the first branch. Source
/// acquisition, identity allocation, recovery registration and every write are
/// unreachable until the reviewed Repository Revision matches.
final class DestructiveOperationPlanner {
  const DestructiveOperationPlanner({
    required WorkspaceEntityIdentityPort identities,
    required SourceReplacementPreparationPort replacementPreparation,
    required DestructiveRecoveryEntryPreparationPort recoveryEntries,
    required OperationPlanAssembler operationPlans,
    required DestructivePlanningClock clock,
  }) : _identities = identities,
       _replacementPreparation = replacementPreparation,
       _recoveryEntries = recoveryEntries,
       _operationPlans = operationPlans,
       _clock = clock;

  final WorkspaceEntityIdentityPort _identities;
  final SourceReplacementPreparationPort _replacementPreparation;
  final DestructiveRecoveryEntryPreparationPort _recoveryEntries;
  final OperationPlanAssembler _operationPlans;
  final DestructivePlanningClock _clock;

  Future<DestructivePlanningResult<OperationPlan>> planSourceReplacement({
    required OperationId operationId,
    required PreparedOperationEnvelope envelope,
    required DestructivePlanningSnapshot snapshot,
    required DestructiveOperationIntent destructiveIntent,
    required ManagedSkillId managedSkillId,
    required SourceDescriptor source,
    required bool includeInternal,
    required bool fullDepth,
    CancellationToken? cancellationToken,
  }) async {
    if (envelope.operationId != operationId ||
        envelope.expectedRepositoryRevision != snapshot.repositoryRevision ||
        envelope.record.kind != WorkspaceOperationKind.replaceSource.name) {
      return DestructivePlanningFailure<OperationPlan>(
        code: DestructivePlanningFailureCode.sourcePreparationFailed,
        context: const <String, Object?>{'reason': 'envelopeMismatch'},
      );
    }
    final stale = _validateReviewedRevision<OperationPlan>(
      snapshot,
      destructiveIntent,
    );
    if (stale != null) return stale;
    final token = cancellationToken ?? CancellationToken.none();
    if (token.isCancelled) return _cancelled();

    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return DestructivePlanningFailure<OperationPlan>(
        code: DestructivePlanningFailureCode.managedSkillNotFound,
        context: {'managedSkillId': managedSkillId.value},
      );
    }
    if (skill.draftState == DestructiveDraftState.dirty) {
      return DestructivePlanningFailure<OperationPlan>(
        code: DestructivePlanningFailureCode.dirtyDraftResolutionRequired,
        context: {'managedSkillId': managedSkillId.value},
      );
    }
    if (skill.hasUpdateCandidateSession) {
      return DestructivePlanningFailure<OperationPlan>(
        code: DestructivePlanningFailureCode.updateCandidateResolutionRequired,
        context: {'managedSkillId': managedSkillId.value},
      );
    }

    final intendedLineage = _identities.allocateSourceLineage();
    final prepared = await _replacementPreparation.prepareSourceReplacement(
      SourceReplacementPreparationIntent(
        operationId: operationId,
        managedSkillId: managedSkillId,
        source: source,
        intendedSourceLineage: intendedLineage,
        includeInternal: includeInternal,
        fullDepth: fullDepth,
      ),
      envelope: envelope,
      cancellationToken: token,
    );
    if (prepared case SourceReplacementPreparationFailure(:final code)) {
      return DestructivePlanningFailure<OperationPlan>(
        code: code == SourceReplacementPreparationFailureCode.operationCancelled
            ? DestructivePlanningFailureCode.operationCancelled
            : DestructivePlanningFailureCode.sourcePreparationFailed,
        context: {'preparationCode': code.name},
      );
    }
    final candidate =
        (prepared as SourceReplacementPreparationSuccess).candidate;
    if (candidate.managedSkillId != managedSkillId ||
        candidate.sourceLineage != intendedLineage) {
      return DestructivePlanningFailure<OperationPlan>(
        code: DestructivePlanningFailureCode.invalidReplacementCandidate,
      );
    }
    final occupied = snapshot.managedSkills.any(
      (other) =>
          other.managedSkillId != managedSkillId &&
          other.slotKey == candidate.slotKey,
    );
    if (occupied) {
      return DestructivePlanningFailure<OperationPlan>(
        code: DestructivePlanningFailureCode.replacementSlotOccupied,
        context: {'slotKey': candidate.slotKey},
      );
    }
    if (token.isCancelled) return _cancelled();

    final now = _clock();
    final intendedAddress = RevisionAddress(
      sourceLineage: intendedLineage,
      objectId: candidate.objectId,
    );
    final recoverySkill = _recoverySkill(skill);
    final mutations = <WorkspaceBusinessMutation>[
      PutSourceLineage(
        sourceLineageId: intendedLineage.encoded,
        managedSkillId: managedSkillId,
        objectFormat: candidate.objectFormat,
        createdAtMicros: now,
      ),
      PutSkillSource(
        sourceLineageId: intendedLineage.encoded,
        kind: candidate.persistedSourceKind,
        payloadSchemaVersion: candidate.sourcePayloadSchemaVersion,
        payloadJson: candidate.sourcePayloadJson,
      ),
      PutRevisionMetadata(
        sourceLineageId: intendedLineage.encoded,
        objectId: candidate.objectId.value,
        contentHash: candidate.contentHash,
        fileCount: candidate.fileCount,
        byteSize: candidate.byteSize,
        declaredName: candidate.declaredName,
        validationState: WorkspaceRevisionValidationState.valid,
        validationCode: null,
        createdAtMicros: now,
      ),
      PutManagedSkill(
        managedSkillId: managedSkillId,
        slotKey: candidate.slotKey,
        declaredName: candidate.declaredName,
        displayName: candidate.displayName,
        description: candidate.description,
        activeSourceLineageId: intendedLineage.encoded,
        createdAtMicros: skill.createdAtMicros,
        updatedAtMicros: now,
      ),
      if (skill.draftState == DestructiveDraftState.clean)
        DeleteDraftWorkspace(managedSkillId),
      for (final lineage in skill.sourceLineages)
        DeleteSourceLineage(lineage.sourceLineage.encoded),
    ];
    final recoveryIntent = SourceReplacementRecoveryIntent(
      skill: recoverySkill,
      intendedSourceLineage: intendedLineage,
      intendedSlotKey: candidate.slotKey,
      intendedObjectId: candidate.objectId,
      intendedContentHash: candidate.contentHash,
      intendedObjectFormat: candidate.objectFormat,
    );
    try {
      await _recoveryEntries.prepareRecoveryEntries(
        operationId: operationId,
        intent: recoveryIntent,
        cancellationToken: token,
      );
    } on Object {
      return DestructivePlanningFailure<OperationPlan>(
        code: token.isCancelled
            ? DestructivePlanningFailureCode.operationCancelled
            : DestructivePlanningFailureCode.sourcePreparationFailed,
        context: const <String, Object?>{
          'reason': 'recoveryEntryPreparationFailed',
        },
      );
    }
    final plan = _operationPlans.destructive(
      operationId: operationId,
      expectedRepositoryRevision: snapshot.repositoryRevision,
      kind: WorkspaceOperationKind.replaceSource,
      businessChanges: WorkspaceBusinessChangeSet(
        mutations: mutations,
        incrementsDestructionEpoch: true,
      ),
      recoveryIntent: recoveryIntent,
      revisionSelectionChanges: [
        RevisionSelectionChangePlan(
          managedSkillId: managedSkillId,
          previousUpstream: skill.currentUpstream,
          previousEffective: skill.currentEffective,
          intendedUpstream: intendedAddress,
          intendedEffective: intendedAddress,
        ),
      ],
      // The retained replacement history points only at the new lineage.
      subjects: [
        OperationSubjectIntent(
          managedSkillId: managedSkillId,
          displayName: candidate.displayName,
          sourceLineage: intendedLineage,
          afterObjectId: candidate.objectId,
          afterContentHash: candidate.contentHash,
        ),
      ],
    );
    return DestructivePlanningSuccess(plan);
  }

  Future<DestructivePlanningResult<OperationPlan>> planRemoval({
    required OperationId operationId,
    required DestructivePlanningSnapshot snapshot,
    required DestructiveOperationIntent destructiveIntent,
    required Set<ManagedSkillId> managedSkillIds,
    required CancellationToken cancellationToken,
  }) async {
    final stale = _validateReviewedRevision<OperationPlan>(
      snapshot,
      destructiveIntent,
    );
    if (stale != null) return stale;
    if (cancellationToken.isCancelled) return _cancelled();
    if (managedSkillIds.isEmpty) {
      throw ArgumentError.value(
        managedSkillIds,
        'managedSkillIds',
        'must not be empty',
      );
    }
    final skills = <DestructiveManagedSkillState>[];
    for (final managedSkillId in managedSkillIds) {
      final skill = snapshot.findSkill(managedSkillId);
      if (skill == null) {
        return DestructivePlanningFailure<OperationPlan>(
          code: DestructivePlanningFailureCode.managedSkillNotFound,
          context: {'managedSkillId': managedSkillId.value},
        );
      }
      skills.add(skill);
    }
    skills.sort(
      (left, right) =>
          left.managedSkillId.value.compareTo(right.managedSkillId.value),
    );

    final recoveryIntent = RemovalRecoveryIntent(
      skills: [for (final skill in skills) _recoverySkill(skill)],
    );
    try {
      await _recoveryEntries.prepareRecoveryEntries(
        operationId: operationId,
        intent: recoveryIntent,
        cancellationToken: cancellationToken,
      );
    } on Object {
      return DestructivePlanningFailure<OperationPlan>(
        code: cancellationToken.isCancelled
            ? DestructivePlanningFailureCode.operationCancelled
            : DestructivePlanningFailureCode.sourcePreparationFailed,
        context: const <String, Object?>{
          'reason': 'recoveryEntryPreparationFailed',
        },
      );
    }
    final plan = _operationPlans.destructive(
      operationId: operationId,
      expectedRepositoryRevision: snapshot.repositoryRevision,
      kind: WorkspaceOperationKind.remove,
      // DeleteManagedSkill is the aggregate deletion mutation. Schema-v1 FKs
      // cascade every per-Skill row while independent Personal Tags survive.
      businessChanges: WorkspaceBusinessChangeSet(
        mutations: [
          for (final skill in skills) DeleteManagedSkill(skill.managedSkillId),
        ],
        incrementsDestructionEpoch: true,
      ),
      recoveryIntent: recoveryIntent,
      revisionSelectionChanges: [
        for (final skill in skills)
          RevisionSelectionChangePlan(
            managedSkillId: skill.managedSkillId,
            previousUpstream: skill.currentUpstream,
            previousEffective: skill.currentEffective,
            intendedUpstream: null,
            intendedEffective: null,
          ),
      ],
      // Subjects exist only as recovery/history input before the BCP. The
      // Control Plane filters them after aggregate deletion and drops an empty
      // header, so completed Removal leaves no tombstone.
      subjects: [
        for (final skill in skills)
          OperationSubjectIntent(
            managedSkillId: skill.managedSkillId,
            displayName: skill.displayName,
            sourceLineage: skill.activeSourceLineage,
            beforeObjectId: skill.currentEffective.objectId,
            beforeContentHash: skill.currentContentHash,
          ),
      ],
    );
    return DestructivePlanningSuccess(plan);
  }

  DestructivePlanningFailure<T>? _validateReviewedRevision<T>(
    DestructivePlanningSnapshot snapshot,
    DestructiveOperationIntent intent,
  ) {
    if (intent.reviewedRevision == snapshot.repositoryRevision) return null;
    return DestructivePlanningFailure<T>(
      code: DestructivePlanningFailureCode.staleIntent,
      context: {
        'reviewedRevision': intent.reviewedRevision.value,
        'actualRevision': snapshot.repositoryRevision.value,
      },
    );
  }

  DestructiveSkillRecoveryIntent _recoverySkill(
    DestructiveManagedSkillState skill,
  ) => DestructiveSkillRecoveryIntent(
    managedSkillId: skill.managedSkillId,
    slotKey: skill.slotKey,
    sourceLineages: [
      for (final lineage in skill.sourceLineages)
        RecoverySourceLineageIntent(sourceLineage: lineage.sourceLineage),
    ],
    activationIds: skill.activationIds,
    hasDraft: skill.draftState != DestructiveDraftState.absent,
    hasUpdateCandidateSession: skill.hasUpdateCandidateSession,
  );

  DestructivePlanningFailure<OperationPlan> _cancelled() =>
      DestructivePlanningFailure<OperationPlan>(
        code: DestructivePlanningFailureCode.operationCancelled,
      );
}
