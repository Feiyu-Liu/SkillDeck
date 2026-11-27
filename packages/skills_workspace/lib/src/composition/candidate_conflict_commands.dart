import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/ports/draft_snapshot_ports.dart';
import '../application/ports/update_ports.dart';
import '../application/revision_store/managed_skill_revision_access_gate.dart';
import '../application/runtime/revision_engine_port.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../application/update/update_models.dart';
import '../domain/draft_snapshot.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../native/revision_worker/revision_worker_runtime.dart';
import 'mutation_command_support.dart';
import 'revision_operation_plans.dart';
import 'revision_preparation_service.dart';

List<SkillsCommandHandler> buildCandidateConflictCommands({
  required WorkspaceSnapshotPublisher snapshots,
  required UpdateCandidateStatePort states,
  required ManagedSkillRevisionAccessGate access,
  required OperationCoordinator operations,
  required WorkspaceRevisionPreparationService preparation,
  required WorkspaceRevisionOperationPlans plans,
  required RevisionWorkerRuntime runtime,
}) {
  final owner = Object();
  return [
    TypedSkillsCommandHandler<ManagedSkillId, UpdateCandidateResolutionReview?>(
      kind: WorkspaceOperationKind.inspectUpdateCandidateResolution,
      handle: (id, context) async {
        final token = context.cancellationToken;
        context.reportProgress(OperationProgressPhase.inspecting);
        final skill = snapshots.current.findSkill(id);
        if (skill == null) return _failure(SkillsErrorCode.skillNotFound);
        final summary = skill.updateCandidate;
        if (summary == null) return SkillsSuccess(value: null);
        if (token.isCancelled) {
          return _failure(SkillsErrorCode.operationCancelled);
        }
        final state = await states.readCandidateState(
          id,
          cancellationToken: token,
        );
        if (token.isCancelled) {
          return _failure(SkillsErrorCode.operationCancelled);
        }
        if (state == null) {
          return _failure(SkillsErrorCode.revisionStoreCorrupt);
        }
        try {
          final permit = await access.acquireRead(id, cancellationToken: token);
          try {
            final result = await preparation.fingerprintCandidateDraft(
              operationId: context.operationId,
              state: state,
              token: token,
            );
            if (result.failureOrNull case final failure?) {
              return _failure(switch (failure.code) {
                DraftSnapshotFailureCode.operationCancelled =>
                  SkillsErrorCode.operationCancelled,
                DraftSnapshotFailureCode.draftChangedDuringPublish =>
                  SkillsErrorCode.staleSnapshot,
                DraftSnapshotFailureCode.ioFailure => SkillsErrorCode.ioFailure,
                _ => SkillsErrorCode.externalConflict,
              });
            }
            if (snapshots.current.findSkill(id)?.updateCandidate != summary) {
              return _failure(SkillsErrorCode.staleSnapshot);
            }
            return SkillsSuccess(
              value: UpdateCandidateResolutionReview(
                summary: summary,
                token: _ReviewToken(owner, state, summary, result.valueOrNull!),
              ),
            );
          } finally {
            await permit.release();
          }
        } on ManagedSkillRevisionAccessCancelled {
          return _failure(SkillsErrorCode.operationCancelled);
        } on RevisionEngineException {
          return _failure(SkillsErrorCode.revisionStoreCorrupt);
        }
      },
    ),
    TypedSkillsCommandHandler<
      ResolveUpdateCandidateConflictsRequest,
      RepositorySnapshot
    >(
      kind: WorkspaceOperationKind.resolveUpdateCandidateConflicts,
      handle: (request, context) async {
        final id = request.managedSkillId;
        final snapshot = snapshots.current;
        final skill = snapshot.findSkill(id);
        if (skill == null) return _failure(SkillsErrorCode.skillNotFound);
        final review = request.reviewToken;
        if (review is! _ReviewToken ||
            !identical(review.owner, owner) ||
            review.state.managedSkillId != id ||
            review.summary != skill.updateCandidate) {
          return _failure(SkillsErrorCode.staleSnapshot);
        }
        SkillsErrorCode? rejected;
        var unchanged = false;
        ManagedSkillRevisionAccessPermit? permit;
        final OperationExecutionOutcome outcome;
        try {
          outcome = await operations
              .executeDeferred<PreparedCandidateResolution>(
                operationId: context.operationId,
                expectedRepositoryRevision: snapshot.revision,
                lockWaitPolicy: context.lockWaitPolicy,
                cancellationToken: context.cancellationToken,
                reconcileReferencesAfterSealing: false,
                buildEnvelope: (operationId, revision) =>
                    plans.createCandidateResolutionEnvelope(
                      operationId: operationId,
                      revision: revision,
                      skillId: id,
                    ),
                prepareCandidate: (envelope, token) async {
                  context.reportProgress(OperationProgressPhase.preparing);
                  final current = await states.readCandidateState(
                    id,
                    cancellationToken: token,
                  );
                  if (current == null || !review.matches(current)) {
                    rejected = token.isCancelled
                        ? SkillsErrorCode.operationCancelled
                        : SkillsErrorCode.staleSnapshot;
                    throw const _ResolutionPreparationFailed();
                  }
                  try {
                    permit = await access.acquireExclusive(
                      id,
                      cancellationToken: token,
                    );
                  } on ManagedSkillRevisionAccessCancelled {
                    rejected = SkillsErrorCode.operationCancelled;
                    throw const _ResolutionPreparationFailed();
                  }
                  if (!current.hasUnresolvedConflicts) {
                    final draft = await preparation.fingerprintCandidateDraft(
                      operationId: envelope.operationId,
                      state: current,
                      token: token,
                    );
                    if (draft.valueOrNull != review.fingerprint) {
                      rejected = token.isCancelled
                          ? SkillsErrorCode.operationCancelled
                          : SkillsErrorCode.staleSnapshot;
                      throw const _ResolutionPreparationFailed();
                    }
                    unchanged = true;
                    throw const OperationPreparationUnchanged();
                  }
                  final result = await preparation.prepareCandidateResolution(
                    operationId: envelope.operationId,
                    state: current,
                    summary: review.summary,
                    side: request.side,
                    reviewedDraft: review.fingerprint,
                    runtime: runtime,
                    token: token,
                  );
                  if (result case SkillsSuccess(:final value)) return value;
                  rejected = result.failureOrNull?.code;
                  throw const _ResolutionPreparationFailed();
                },
                buildPlan: (envelope, prepared) =>
                    plans.sealCandidateResolutionPlan(
                      envelope: envelope,
                      skill: skill,
                      prepared: prepared,
                    ),
                onBusinessCommitted: () {
                  context.markBusinessCommitted();
                  context.reportProgress(OperationProgressPhase.committing);
                },
              );
        } finally {
          await permit?.release();
        }
        if (outcome case OperationRolledBack()) {
          if (rejected case final code?) return _failure(code);
          if (unchanged && outcome.reason != OperationAbortReason.cancelled) {
            return SkillsSuccess(value: snapshot);
          }
        }
        return mapMutationOutcome(
          outcome: outcome,
          context: context,
          snapshots: snapshots,
          valueFromSnapshot: (value) => value,
        );
      },
    ),
  ];
}

SkillsFailure<T> _failure<T>(SkillsErrorCode code) => SkillsFailure(code: code);

final class _ReviewToken {
  const _ReviewToken(this.owner, this.state, this.summary, this.fingerprint);

  final Object owner;
  final UpdateCandidateState state;
  final UpdateCandidateSummary summary;
  final DraftFingerprint fingerprint;

  bool matches(UpdateCandidateState current) =>
      state.candidateObjectId == current.candidateObjectId &&
      state.sourceLineage == current.sourceLineage &&
      state.previousUpstream == current.previousUpstream &&
      state.previousEffective == current.previousEffective &&
      state.incomingUpstream == current.incomingUpstream &&
      state.draftCreatedAtMicros == current.draftCreatedAtMicros &&
      state.conflicts.length == current.conflicts.length &&
      List.generate(state.conflicts.length, (index) => index).every((index) {
        final old = state.conflicts[index];
        final next = current.conflicts[index];
        return old.path == next.path &&
            old.kind == next.kind &&
            old.state == next.state;
      });
}

final class _ResolutionPreparationFailed implements Exception {
  const _ResolutionPreparationFailed();
}
