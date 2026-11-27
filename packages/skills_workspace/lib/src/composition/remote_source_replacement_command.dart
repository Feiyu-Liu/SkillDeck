import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/destructive/destructive_operation_models.dart';
import '../application/destructive/destructive_operation_planner.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/operations/operation_plan_assembler.dart';
import '../application/ports/destructive_operation_ports.dart';
import '../application/ports/initial_import_ports.dart';
import '../application/ports/update_ports.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/public_models.dart';
import '../native/revision_worker/revision_worker_runtime.dart';
import 'mutation_command_support.dart';
import 'revision_preparation_service.dart';

Future<SkillsResult<RemoteApplyResult>> applyRemoteSourceReplacement({
  required RemoteSkillSourceReplacement request,
  required SkillsCommandContext context,
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required OperationPlanAssembler operationPlans,
  required UpdateRevisionStatePort states,
  required DestructivePlanningStatePort state,
  required DestructiveOperationPlanner planner,
  required WorkspaceRevisionPreparationService preparation,
  required WorkspaceEntityIdentityPort identities,
  required SourcePayloadEncodingPort sourcePayloads,
  required ReadRemotePackHeads readPackHeads,
  required RevisionWorkerRuntime runtime,
}) async {
  final snapshot = snapshots.current, id = request.managedSkillId;
  SkillsResult<RemoteApplyResult>? rejection;
  Never reject(SkillsResult<RemoteApplyResult> result) {
    rejection = result;
    // Expected guards are unchanged operations, including failed pack validation:
    // roll back the candidate envelope without retaining an Operation Record.
    throw const OperationPreparationUnchanged();
  }

  final outcome = await operations.executeDeferred<OperationPlan>(
    operationId: context.operationId,
    expectedRepositoryRevision: snapshot.revision,
    lockWaitPolicy: context.lockWaitPolicy,
    cancellationToken: context.cancellationToken,
    reconcileReferencesAfterSealing: false,
    buildEnvelope: (operationId, revision) =>
        operationPlans.destructiveEnvelope(
          operationId: operationId,
          expectedRepositoryRevision: revision,
          kind: WorkspaceOperationKind.replaceSource,
        ),
    prepareCandidate: (envelope, token) async {
      final skill = snapshot.findSkill(id);
      if (skill == null) {
        reject(SkillsFailure(code: SkillsErrorCode.skillNotFound));
      }
      final selection = await states.readUpdateState(id);
      if (selection == null) {
        reject(SkillsFailure(code: SkillsErrorCode.revisionStoreCorrupt));
      }
      if (selection.currentEffective.value != request.expectedEffective.value) {
        reject(
          SkillsFailure(
            code: SkillsErrorCode.staleSnapshot,
            context: const {'reason': 'effectiveRevisionChanged'},
          ),
        );
      }
      final heads = await readPackHeads(id);
      if (skill.source == request.source &&
          heads?.effective.value == request.effective.value &&
          heads?.upstream?.value == request.upstream?.value) {
        reject(SkillsSuccess(value: RemoteApplyNoChange(), changed: false));
      }
      final planning = await state.readPlanningSnapshot(
        publicSnapshot: snapshot,
        purpose: DestructivePlanningPurpose.sourceReplacement,
        targetManagedSkillIds: {id},
        cancellationToken: token,
      );
      final current = planning.findSkill(id)!;
      if (current.draftState == DestructiveDraftState.dirty ||
          current.hasUpdateCandidateSession) {
        reject(
          SkillsSuccess(
            value: RemoteApplyDraftResolutionRequired(),
            changed: false,
          ),
        );
      }
      final prepared = await preparation.prepareRemoteSourceReplacement(
        operationId: envelope.operationId,
        request: request,
        snapshot: snapshot,
        lineage: identities.allocateSourceLineage(),
        sourcePayloads: sourcePayloads,
        readPackHeads: readPackHeads,
        runtime: runtime,
        token: token,
      );
      if (prepared case SkillsFailure(:final code, :final context)) {
        reject(SkillsFailure(code: code, context: context));
      }
      final candidate =
          (prepared
                  as SkillsSuccess<
                    ({
                      RemoteApplyResult result,
                      PreparedSourceReplacement? candidate,
                    })
                  >)
              .value;
      if (candidate.candidate == null) {
        reject(SkillsSuccess(value: candidate.result, changed: false));
      }
      final planned = await planner.planPreparedSourceReplacement(
        operationId: envelope.operationId,
        snapshot: planning,
        candidate: candidate.candidate!,
        cancellationToken: token,
      );
      if (planned.failureOrNull case final failure?) {
        reject(
          SkillsFailure(
            code:
                failure.code ==
                    DestructivePlanningFailureCode.operationCancelled
                ? SkillsErrorCode.operationCancelled
                : SkillsErrorCode.operationFailed,
          ),
        );
      }
      return planned.valueOrNull!;
    },
    buildPlan: (_, plan) => plan,
    onBusinessCommitted: () {
      context.markBusinessCommitted();
      context.reportProgress(OperationProgressPhase.committing);
    },
  );
  if (rejection != null &&
      (outcome is OperationRolledBack || outcome is OperationRejected)) {
    return rejection!;
  }
  return mapMutationOutcome<RemoteApplyResult>(
    outcome: outcome,
    context: context,
    snapshots: snapshots,
    valueFromSnapshot: (_) => const RemoteApplySourceReplaced(),
  );
}
