import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/ports/initial_import_ports.dart';
import '../application/ports/update_ports.dart';
import '../application/revision_store/managed_skill_revision_access_gate.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
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
  required WorkspaceEntityIdentityPort identities,
  required SourcePayloadEncodingPort sourcePayloads,
  required ReadRemotePackHeads readPackHeads,
}) => TypedSkillsCommandHandler<ApplyRemoteStateRequest, RemoteApplyResult>(
  kind: WorkspaceOperationKind.applyRemoteState,
  handle: (request, context) async {
    final snapshot = snapshots.current;
    context.reportProgress(OperationProgressPhase.inspecting);
    switch (request) {
      case final RemoteSkillInstall install:
        if (context.cancellationToken.isCancelled) {
          return SkillsFailure(code: SkillsErrorCode.operationCancelled);
        }
        final id = identities.allocateManagedSkillId();
        final lineage = identities.allocateSourceLineage();
        return _executeRemoteApply<PreparedRemoteInstall>(
          snapshots: snapshots,
          operations: operations,
          plans: plans,
          snapshot: snapshot,
          id: id,
          context: context,
          prepare: (envelope, token) => preparation.prepareRemoteInstall(
            operationId: envelope.operationId,
            request: install,
            snapshot: snapshot,
            managedSkillId: id,
            lineage: lineage,
            sourcePayloads: sourcePayloads,
            readPackHeads: readPackHeads,
            runtime: runtime,
            token: token,
          ),
          resultOf: (prepared) => prepared.result,
          hasChanges: (prepared) => prepared.evidence != null,
          buildPlan: (envelope, prepared) => plans.sealRemoteInstallPlan(
            envelope: envelope,
            evidence: prepared.evidence!,
          ),
        );
      case final RemoteSkillContent content:
        final id = content.managedSkillId;
        final skill = snapshot.findSkill(id);
        if (skill == null) {
          return SkillsFailure(code: SkillsErrorCode.skillNotFound);
        }
        if (context.cancellationToken.isCancelled) {
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
        return _executeRemoteApply<PreparedRemoteContent>(
          snapshots: snapshots,
          operations: operations,
          plans: plans,
          snapshot: snapshot,
          id: id,
          context: context,
          acquireAccess: (token) =>
              access.acquireExclusive(id, cancellationToken: token),
          prepare: (envelope, token) => preparation.prepareRemoteContent(
            operationId: envelope.operationId,
            request: content,
            snapshot: snapshot,
            skill: skill,
            state: state,
            slotMigrations: slotMigrations,
            runtime: runtime,
            token: token,
          ),
          resultOf: (prepared) => prepared.result,
          hasChanges: (prepared) => prepared.plan != null,
          buildPlan: (envelope, prepared) => plans.sealRemoteContentPlan(
            envelope: envelope,
            skill: skill,
            preparedPlan: prepared.plan!,
            objectAdditions: prepared.objectAdditions,
            usedPackStaging: prepared.usedPackStaging,
            verifyDraft: prepared.verifyDraft,
          ),
        );
    }
  },
);

Future<SkillsResult<RemoteApplyResult>> _executeRemoteApply<T>({
  required WorkspaceSnapshotPublisher snapshots,
  required OperationCoordinator operations,
  required WorkspaceRevisionOperationPlans plans,
  required RepositorySnapshot snapshot,
  required ManagedSkillId id,
  required SkillsCommandContext context,
  required Future<SkillsResult<T>> Function(
    PreparedOperationEnvelope,
    CancellationToken,
  )
  prepare,
  required RemoteApplyResult Function(T) resultOf,
  required bool Function(T) hasChanges,
  required OperationPlan Function(PreparedOperationEnvelope, T) buildPlan,
  Future<ManagedSkillRevisionAccessPermit> Function(CancellationToken)?
  acquireAccess,
}) async {
  SkillsResult<T>? preparationResult;
  ManagedSkillRevisionAccessPermit? permit;
  final OperationExecutionOutcome outcome;
  try {
    outcome = await operations.executeDeferred<T>(
      operationId: context.operationId,
      expectedRepositoryRevision: snapshot.revision,
      lockWaitPolicy: context.lockWaitPolicy,
      // The applying phase makes the objects available to retention refs.
      reconcileReferencesAfterSealing: false,
      buildEnvelope: (operationId, revision) => plans.createRemoteApplyEnvelope(
        operationId: operationId,
        expectedRepositoryRevision: revision,
        managedSkillId: id,
      ),
      prepareCandidate: (envelope, token) async {
        context.reportProgress(OperationProgressPhase.preparing);
        permit = await acquireAccess?.call(token);
        final result = await prepare(envelope, token);
        preparationResult = result;
        switch (result) {
          case SkillsSuccess(:final value):
            if (hasChanges(value)) return value;
            throw const OperationPreparationUnchanged();
          case SkillsFailure():
            throw const _RemoteApplyPreparationFailed();
          case SkillsCommittedFinalizationPending():
            throw StateError('Candidate preparation cannot commit.');
        }
      },
      buildPlan: buildPlan,
      onBusinessCommitted: () {
        context.markBusinessCommitted();
        context.reportProgress(OperationProgressPhase.committing);
      },
      cancellationToken: context.cancellationToken,
    );
  } finally {
    // Snapshot reload may read the Skill Store while inspecting its Draft.
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
        value: resultOf((preparationResult! as SkillsSuccess<T>).value),
        changed: true,
        warnings: [
          if (cleanupPending)
            SkillsWarning(code: SkillsWarningCode.recoveryCleanupDeferred),
        ],
      );
    case OperationCommittedFinalizationPending():
      return finalizationPending(outcome);
    case OperationRolledBack() || OperationRejected():
      if (outcome case OperationRolledBack(
        reason: OperationAbortReason.cancelled,
      )) {
        return SkillsFailure(code: SkillsErrorCode.operationCancelled);
      }
      if (outcome is OperationRolledBack) {
        switch (preparationResult) {
          case SkillsFailure(:final code, :final context):
            return SkillsFailure(code: code, context: context);
          case SkillsSuccess(:final value) when !hasChanges(value):
            return SkillsSuccess(value: resultOf(value), changed: false);
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
          OperationAbortReason.cancelled => SkillsErrorCode.operationCancelled,
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
}

final class _RemoteApplyPreparationFailed implements Exception {
  const _RemoteApplyPreparationFailed();
}
