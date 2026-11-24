import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/ports/update_ports.dart';
import '../application/revision_store/managed_skill_revision_access_gate.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/public_models.dart';
import '../native/revision_worker/revision_worker_runtime.dart';
import 'revision_operation_plans.dart';
import 'revision_preparation_service.dart';

SkillsCommandHandler buildRemoteContentCommand({
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required UpdateRevisionStatePort states,
  required UpdateSlotMigrationInspectionPort slotMigrations,
  required WorkspaceRevisionPreparationService preparation,
  required WorkspaceRevisionOperationPlans plans,
  required RevisionWorkerRuntime runtime,
  required ManagedSkillRevisionAccessGate access,
}) => TypedSkillsCommandHandler<ApplyRemoteStateRequest, RemoteApplyResult>(
  kind: WorkspaceOperationKind.applyRemoteState,
  handle: (request, context) async {
    final RemoteSkillContent content;
    switch (request) {
      case final RemoteSkillContent value:
        content = value;
    }
    final snapshot = snapshots.current;
    final id = content.managedSkillId;
    final token = context.cancellationToken;
    context.reportProgress(OperationProgressPhase.inspecting);
    final skill = snapshot.findSkill(id);
    if (skill == null) {
      return SkillsFailure(code: SkillsErrorCode.skillNotFound);
    }
    if (token.isCancelled) {
      return SkillsFailure(code: SkillsErrorCode.operationCancelled);
    }
    final state = await states.readUpdateState(id);
    if (state == null) {
      return SkillsFailure(code: SkillsErrorCode.revisionStoreCorrupt);
    }
    if (state.currentEffective.value != content.expectedEffective.value) {
      return SkillsFailure(
        code: SkillsErrorCode.staleSnapshot,
        context: const {'reason': 'effectiveRevisionChanged'},
      );
    }
    if (skill.updateCandidate != null) {
      return SkillsSuccess(
        value: const RemoteApplyDraftResolutionRequired(),
        changed: false,
      );
    }

    ManagedSkillRevisionAccessPermit? permit;
    SkillsResult<PreparedRemoteContent>? preparationResult;
    final OperationExecutionOutcome outcome;
    try {
      outcome = await operations.executeDeferred<PreparedRemoteContent>(
        operationId: context.operationId,
        expectedRepositoryRevision: snapshot.revision,
        lockWaitPolicy: context.lockWaitPolicy,
        buildEnvelope: (id, revision) => plans.createRemoteContentEnvelope(
          operationId: id,
          expectedRepositoryRevision: revision,
          managedSkillId: content.managedSkillId,
        ),
        prepareCandidate: (envelope, cancellationToken) async {
          context.reportProgress(OperationProgressPhase.preparing);
          permit = await access.acquireExclusive(
            id,
            cancellationToken: cancellationToken,
          );
          final result = await preparation.prepareRemoteContent(
            operationId: envelope.operationId,
            request: content,
            snapshot: snapshot,
            skill: skill,
            state: state,
            slotMigrations: slotMigrations,
            runtime: runtime,
            token: cancellationToken,
          );
          preparationResult = result;
          if (result case SkillsSuccess(:final value) when value.plan != null) {
            return value;
          }
          throw const _RemoteContentUnchanged();
        },
        buildPlan: (envelope, prepared) => plans.sealRemoteContentPlan(
          envelope: envelope,
          skill: skill,
          preparedPlan: prepared.plan!,
          objectAdditions: prepared.objectAdditions,
          usedPackStaging: prepared.usedPackStaging,
          verifyDraft: prepared.verifyDraft,
        ),
        onBusinessCommitted: () {
          context.markBusinessCommitted();
          context.reportProgress(OperationProgressPhase.committing);
        },
        cancellationToken: token,
      );
    } finally {
      await permit?.release();
    }

    SkillsCommittedFinalizationPending<RemoteApplyResult> finalizationPending(
      OperationExecutionOutcome outcome,
    ) => SkillsCommittedFinalizationPending(
      operationId: context.operationId,
      committedRepositoryRevision: switch (outcome) {
        OperationCompleted(:final committedRepositoryRevision) ||
        OperationCommittedFinalizationPending(
          :final committedRepositoryRevision,
        ) => committedRepositoryRevision,
        _ => throw StateError('Missing committed revision.'),
      },
      warnings: [SkillsWarning(code: SkillsWarningCode.finalizationDeferred)],
    );

    switch (outcome) {
      case OperationCompleted(:final cleanupPending):
        context.reportProgress(OperationProgressPhase.finalizing);
        try {
          await snapshots.reload();
        } on Object {
          return finalizationPending(outcome);
        }
        return SkillsSuccess(
          value: (preparationResult! as SkillsSuccess<PreparedRemoteContent>)
              .value
              .result,
          changed: true,
          warnings: [
            if (cleanupPending)
              SkillsWarning(code: SkillsWarningCode.recoveryCleanupDeferred),
          ],
        );
      case OperationCommittedFinalizationPending():
        return finalizationPending(outcome);
      case OperationRolledBack() || OperationRejected():
        if (token.isCancelled) {
          return SkillsFailure(code: SkillsErrorCode.operationCancelled);
        }
        if (outcome is OperationRolledBack) {
          switch (preparationResult) {
            case SkillsFailure(:final code, :final context):
              return SkillsFailure(code: code, context: context);
            case SkillsSuccess(:final value) when value.plan == null:
              return SkillsSuccess(value: value.result, changed: false);
            default:
              break;
          }
        }
        final reason = switch (outcome) {
          OperationRolledBack(:final reason) ||
          OperationRejected(:final reason) => reason,
          _ => throw StateError('Missing rollback reason.'),
        };
        return SkillsFailure(
          code: switch (reason) {
            OperationAbortReason.cancelled =>
              SkillsErrorCode.operationCancelled,
            OperationAbortReason.staleRepositoryRevision ||
            OperationAbortReason.externalPreconditionChanged =>
              SkillsErrorCode.staleSnapshot,
            OperationAbortReason.lockUnavailable =>
              SkillsErrorCode.repositoryBusy,
            OperationAbortReason.snapshotReadFailed =>
              SkillsErrorCode.stateCorrupt,
            OperationAbortReason.journalWriteFailed =>
              SkillsErrorCode.journalCorrupt,
            _ => SkillsErrorCode.operationFailed,
          },
          context: {'reason': reason.name},
        );
      case OperationRollbackPending():
        return SkillsFailure(code: SkillsErrorCode.recoveryFailed);
    }
  },
);

final class _RemoteContentUnchanged implements Exception {
  const _RemoteContentUnchanged();
}
