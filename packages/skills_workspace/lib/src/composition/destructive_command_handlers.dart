import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/destructive/destructive_operation_models.dart';
import '../application/destructive/destructive_operation_planner.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/operations/operation_plan_assembler.dart';
import '../application/ports/destructive_operation_ports.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'mutation_command_support.dart';

/// Builds identity-preserving Source Replacement and complete Removal commands.
///
/// Both commands repeat destructive-intent and internal lineage checks while
/// the Workspace Writer Lock is held. Source Replacement persists its minimal
/// Prepared envelope before source acquisition or Revision Store candidate
/// construction begins.
List<SkillsCommandHandler> buildDestructiveCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required OperationPlanAssembler operationPlans,
  required DestructivePlanningStatePort state,
  required DestructiveOperationPlanner planner,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<ReplaceSourceRequest, MutationReport>(
    kind: WorkspaceOperationKind.replaceSource,
    handle: (request, context) => _replaceSource(
      request: request,
      context: context,
      snapshots: snapshots,
      operations: operations,
      operationPlans: operationPlans,
      state: state,
      planner: planner,
    ),
  ),
  TypedSkillsCommandHandler<RemoveRequest, MutationReport>(
    kind: WorkspaceOperationKind.remove,
    handle: (request, context) => _remove(
      request: request,
      context: context,
      snapshots: snapshots,
      operations: operations,
      state: state,
      planner: planner,
    ),
  ),
];

Future<SkillsResult<MutationReport>> _replaceSource({
  required ReplaceSourceRequest request,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required OperationPlanAssembler operationPlans,
  required DestructivePlanningStatePort state,
  required DestructiveOperationPlanner planner,
}) async {
  context.reportProgress(OperationProgressPhase.inspecting);
  final publicSnapshot = snapshots.current;
  if (request.intent.reviewedRevision != publicSnapshot.revision) {
    return SkillsFailure<MutationReport>(
      code: SkillsErrorCode.staleSnapshot,
      context: <String, Object?>{
        'reviewedRevision': request.intent.reviewedRevision.value,
        'actualRevision': publicSnapshot.revision.value,
      },
    );
  }

  DestructivePlanningFailure<OperationPlan>? planningFailure;
  context.reportProgress(OperationProgressPhase.preparing);
  final outcome = await operations.executeDeferred<OperationPlan>(
    operationId: context.operationId,
    expectedRepositoryRevision: publicSnapshot.revision,
    lockWaitPolicy: context.lockWaitPolicy,
    buildEnvelope: (operationId, currentRevision) =>
        operationPlans.destructiveEnvelope(
          operationId: operationId,
          expectedRepositoryRevision: currentRevision,
          kind: WorkspaceOperationKind.replaceSource,
        ),
    prepareCandidate: (envelope, cancellationToken) async {
      final DestructivePlanningSnapshot lockHeldSnapshot;
      try {
        lockHeldSnapshot = await state.readPlanningSnapshot(
          publicSnapshot: publicSnapshot,
          purpose: DestructivePlanningPurpose.sourceReplacement,
          targetManagedSkillIds: <ManagedSkillId>{request.managedSkillId},
          cancellationToken: cancellationToken,
        );
      } on DestructivePlanningStateException catch (failure) {
        if (failure.code !=
            DestructivePlanningStateFailureCode.operationCancelled) {
          rethrow;
        }
        planningFailure = DestructivePlanningFailure<OperationPlan>(
          code: DestructivePlanningFailureCode.operationCancelled,
          context: <String, Object?>{
            if (failure.reason != null) 'reason': failure.reason,
          },
        );
        throw const _DestructivePlanningRejected();
      }
      final planned = await planner.planSourceReplacement(
        operationId: envelope.operationId,
        envelope: envelope,
        snapshot: lockHeldSnapshot,
        destructiveIntent: DestructiveOperationIntent(
          reviewedRevision: request.intent.reviewedRevision,
        ),
        managedSkillId: request.managedSkillId,
        source: request.source,
        includeInternal: request.includeInternal,
        fullDepth: request.fullDepth,
        cancellationToken: cancellationToken,
      );
      final failure = planned.failureOrNull;
      if (failure != null) {
        planningFailure = failure;
        throw const _DestructivePlanningRejected();
      }
      return planned.valueOrNull!;
    },
    buildPlan: (_, plan) => plan,
    cancellationToken: context.cancellationToken,
    onBusinessCommitted: () {
      context.reportProgress(OperationProgressPhase.committing);
      context.markBusinessCommitted();
    },
  );
  if (planningFailure case final failure?) {
    final rejectedPreparation =
        outcome is OperationRejected &&
        outcome.reason == OperationAbortReason.preparationFailed;
    if (outcome is OperationRolledBack || rejectedPreparation) {
      return _planningFailure<MutationReport>(failure);
    }
  }
  return mapMutationOutcome<MutationReport>(
    outcome: outcome,
    context: context,
    snapshots: snapshots,
    valueFromSnapshot: (snapshot) => MutationReport(
      snapshot: snapshot,
      affectedSkillIds: <ManagedSkillId>{request.managedSkillId},
    ),
  );
}

Future<SkillsResult<MutationReport>> _remove({
  required RemoveRequest request,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required DestructivePlanningStatePort state,
  required DestructiveOperationPlanner planner,
}) async {
  context.reportProgress(OperationProgressPhase.inspecting);
  final publicSnapshot = snapshots.current;
  if (request.intent.reviewedRevision != publicSnapshot.revision) {
    return SkillsFailure<MutationReport>(
      code: SkillsErrorCode.staleSnapshot,
      context: <String, Object?>{
        'reviewedRevision': request.intent.reviewedRevision.value,
        'actualRevision': publicSnapshot.revision.value,
      },
    );
  }

  DestructivePlanningFailure<OperationPlan>? planningFailure;
  context.reportProgress(OperationProgressPhase.preparing);
  final outcome = await operations.execute(
    operationId: context.operationId,
    expectedRepositoryRevision: publicSnapshot.revision,
    lockWaitPolicy: context.lockWaitPolicy,
    buildPlan: (operationId, _) async {
      final DestructivePlanningSnapshot lockHeldSnapshot;
      try {
        lockHeldSnapshot = await state.readPlanningSnapshot(
          publicSnapshot: publicSnapshot,
          purpose: DestructivePlanningPurpose.removal,
          targetManagedSkillIds: request.managedSkillIds,
          cancellationToken: context.cancellationToken,
        );
      } on DestructivePlanningStateException catch (failure) {
        if (failure.code !=
            DestructivePlanningStateFailureCode.operationCancelled) {
          rethrow;
        }
        planningFailure = DestructivePlanningFailure<OperationPlan>(
          code: DestructivePlanningFailureCode.operationCancelled,
          context: <String, Object?>{
            if (failure.reason != null) 'reason': failure.reason,
          },
        );
        throw const _DestructivePlanningRejected();
      }
      final planned = await planner.planRemoval(
        operationId: operationId,
        snapshot: lockHeldSnapshot,
        destructiveIntent: DestructiveOperationIntent(
          reviewedRevision: request.intent.reviewedRevision,
        ),
        managedSkillIds: request.managedSkillIds,
        cancellationToken: context.cancellationToken,
      );
      final failure = planned.failureOrNull;
      if (failure != null) {
        planningFailure = failure;
        throw const _DestructivePlanningRejected();
      }
      return planned.valueOrNull!;
    },
    cancellationToken: context.cancellationToken,
    onBusinessCommitted: () {
      context.reportProgress(OperationProgressPhase.committing);
      context.markBusinessCommitted();
    },
  );
  if (planningFailure case final failure?) {
    if (outcome case OperationRejected(
      reason: OperationAbortReason.preparationFailed,
    )) {
      return _planningFailure<MutationReport>(failure);
    }
  }
  return mapMutationOutcome<MutationReport>(
    outcome: outcome,
    context: context,
    snapshots: snapshots,
    valueFromSnapshot: (snapshot) => MutationReport(
      snapshot: snapshot,
      affectedSkillIds: request.managedSkillIds,
    ),
  );
}

SkillsFailure<T> _planningFailure<T>(
  DestructivePlanningFailure<Object?> failure,
) => SkillsFailure<T>(
  code: switch (failure.code) {
    DestructivePlanningFailureCode.staleIntent => SkillsErrorCode.staleSnapshot,
    DestructivePlanningFailureCode.managedSkillNotFound =>
      SkillsErrorCode.skillNotFound,
    DestructivePlanningFailureCode.operationCancelled =>
      SkillsErrorCode.operationCancelled,
    DestructivePlanningFailureCode.dirtyDraftResolutionRequired =>
      SkillsErrorCode.dirtyDraftResolutionRequired,
    DestructivePlanningFailureCode.updateCandidateResolutionRequired =>
      SkillsErrorCode.updateCandidateResolutionRequired,
    DestructivePlanningFailureCode.replacementSlotOccupied =>
      SkillsErrorCode.duplicateSkillSlot,
    DestructivePlanningFailureCode.sourcePreparationFailed =>
      _sourcePreparationFailure(failure.context),
    DestructivePlanningFailureCode.invalidReplacementCandidate =>
      SkillsErrorCode.invalidSkill,
  },
  context: failure.context,
);

SkillsErrorCode _sourcePreparationFailure(Map<String, Object?> context) =>
    switch (context['preparationCode']) {
      'operationCancelled' => SkillsErrorCode.operationCancelled,
      'sourceUnavailable' => SkillsErrorCode.sourceUnavailable,
      'sourceAmbiguous' ||
      'sourcePayloadInvalid' => SkillsErrorCode.invalidSkill,
      'ioFailure' => SkillsErrorCode.ioFailure,
      _ => SkillsErrorCode.operationFailed,
    };

final class _DestructivePlanningRejected implements Exception {
  const _DestructivePlanningRejected();
}
