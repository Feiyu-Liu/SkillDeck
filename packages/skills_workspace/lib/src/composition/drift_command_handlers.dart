import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/drift/drift_artifacts.dart';
import '../application/drift/drift_models.dart';
import '../application/drift/drift_plan_assembler.dart';
import '../application/drift/drift_resolution_planner.dart';
import '../application/history/history_models.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/ports/published_artifact_ports.dart';
import '../application/ports/workspace_lifecycle_ports.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../application/runtime/revision_engine_port.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'skill_integrity_coordinator.dart';

List<SkillsCommandHandler> buildDriftCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required WorkspaceMaterializationReconciliationPort materializations,
  required PublishedArtifactInspectorPort inspector,
  required DriftArtifactExporterPort exporter,
  required DriftResolutionPlanner planner,
  required DriftRevisionPreparationPort revisions,
  required DriftOperationPlanPort plans,
  required OperationCoordinator operations,
  required SkillIntegrityCoordinator integrity,
  required List<String> Function() forbiddenExportRoots,
}) {
  final owner = Object();
  SkillsFailure<T>? reviewFailure<T>(SkillDriftReview review) {
    if (review is! DriftReviewEvidence || !identical(review.owner, owner)) {
      return SkillsFailure(
        code: SkillsErrorCode.staleDriftReview,
        context: const {'reason': 'foreignReview'},
      );
    }
    return null;
  }

  SkillsFailure<T>? skillFailure<T>(ManagedSkillId id) {
    if (snapshots.current.findSkill(id) == null) {
      return SkillsFailure(code: SkillsErrorCode.skillNotFound);
    }
    if (snapshots.current.integrity.skills.any(
      (s) =>
          s.managedSkillId == id &&
          s.status == SkillIntegrityStatus.revisionStoreCorrupt,
    )) {
      return SkillsFailure(code: SkillsErrorCode.revisionStoreCorrupt);
    }
    return null;
  }

  return [
    TypedSkillsCommandHandler<InspectSkillDriftRequest, SkillDriftReview>(
      kind: WorkspaceOperationKind.inspectSkillDrift,
      handle: (request, context) async {
        context.reportProgress(OperationProgressPhase.inspecting);
        if (context.cancellationToken.isCancelled) {
          return SkillsFailure(code: SkillsErrorCode.operationCancelled);
        }
        if (skillFailure<SkillDriftReview>(request.managedSkillId)
            case final failure?) {
          return failure;
        }
        try {
          final inspected = await materializations.inspectSkillMaterializations(
            request.managedSkillId,
            cancellationToken: context.cancellationToken,
          );
          if (context.cancellationToken.isCancelled) {
            return SkillsFailure(code: SkillsErrorCode.operationCancelled);
          }
          final artifacts = driftArtifactsFor(inspected);
          return SkillsSuccess(
            value: createDriftReview(
              owner: owner,
              managedSkillId: request.managedSkillId,
              inspected: inspected,
              artifacts: artifacts,
              missingArtifactCount: inspected.artifacts
                  .where(
                    (a) => a.inspection.state == PublishedArtifactState.missing,
                  )
                  .length,
            ),
            changed: false,
          );
        } on SkillDriftUnsafe {
          return context.cancellationToken.isCancelled
              ? SkillsFailure(code: SkillsErrorCode.operationCancelled)
              : _unsafe();
        }
      },
    ),
    TypedSkillsCommandHandler<
      ExportSkillDriftArtifactRequest,
      SkillDriftExport
    >(
      kind: WorkspaceOperationKind.exportSkillDriftArtifact,
      handle: (request, context) async {
        context.reportProgress(OperationProgressPhase.inspecting);
        if (context.cancellationToken.isCancelled) {
          return SkillsFailure(code: SkillsErrorCode.operationCancelled);
        }
        if (reviewFailure<SkillDriftExport>(request.review)
            case final failure?) {
          return failure;
        }
        if (skillFailure<SkillDriftExport>(request.review.managedSkillId)
            case final failure?) {
          return failure;
        }
        final review = request.review as DriftReviewEvidence;
        final matches = review.artifacts.where(
          (a) => a.artifactId == request.artifactId,
        );
        if (matches.isEmpty) return _stale('artifactNotFound');
        if (!matches.single.canExport) {
          return SkillsFailure(
            code: SkillsErrorCode.driftResolutionUnavailable,
            context: const {'reason': 'exportNotAllowed'},
          );
        }
        // Export is a read operation and intentionally acquires no writer lock.
        final a = review.inspected.artifacts.singleWhere(
          (a) => driftArtifactId(a) == request.artifactId,
        );
        final currentSkill = snapshots.current.findSkill(
          review.managedSkillId,
        )!;
        final effective = await planner.validateEffectiveRevision(review);
        if (effective is DriftFailure<void>) return _driftFailure(effective);
        final result = await exporter.export(
          sourcePath: a.targetPath,
          slotKey: currentSkill.slotKey,
          destinationDirectory: request.destinationDirectory,
          forbiddenRoots: forbiddenExportRoots(),
          expectedFingerprint: a.inspection.fingerprint!,
          inspector: inspector,
          cancellationToken: context.cancellationToken,
          now: DateTime.now().toUtc(),
        );
        if (result is DriftFailure<String>) {
          return _driftFailure(result);
        }
        return SkillsSuccess(
          value: SkillDriftExport(
            exportedPath: (result as DriftSuccess<String>).value,
          ),
          changed: false,
        );
      },
    ),
    TypedSkillsCommandHandler<ResolveSkillDriftRequest, MutationReport>(
      kind: WorkspaceOperationKind.resolveSkillDrift,
      handle: (request, context) async {
        context.reportProgress(OperationProgressPhase.inspecting);
        if (context.cancellationToken.isCancelled) {
          return SkillsFailure(code: SkillsErrorCode.operationCancelled);
        }
        if (reviewFailure<MutationReport>(request.review) case final failure?) {
          return failure;
        }
        if (skillFailure<MutationReport>(request.review.managedSkillId)
            case final failure?) {
          return failure;
        }
        final review = request.review as DriftReviewEvidence;
        SkillMaterializationInspection current;
        try {
          current = await materializations.inspectSkillMaterializations(
            review.managedSkillId,
            cancellationToken: context.cancellationToken,
          );
        } on SkillDriftUnsafe {
          return context.cancellationToken.isCancelled
              ? SkillsFailure(code: SkillsErrorCode.operationCancelled)
              : _unsafe();
        }
        final planned = await planner.plan(
          snapshot: snapshots.current,
          review: review,
          current: current,
          resolution: request.resolution,
          cancellationToken: context.cancellationToken,
        );
        if (planned is DriftFailure<DriftResolutionPreflight>) {
          return _driftFailure(planned);
        }
        final preflight =
            (planned as DriftSuccess<DriftResolutionPreflight>).value;
        if (!preflight.keepsExternal &&
            review.artifacts.isEmpty &&
            current.artifacts.every(
              (artifact) =>
                  artifact.inspection.state != PublishedArtifactState.missing,
            )) {
          await integrity.forceRevalidate(review.managedSkillId);
          return SkillsSuccess(
            value: MutationReport(
              snapshot: snapshots.current,
              affectedSkillIds: const {},
            ),
            changed: false,
          );
        }
        DriftFailure<Object?>? preparationFailure;
        final outcome = await operations
            .executeDeferred<PreparedRestorePublishPlan?>(
              operationId: context.operationId,
              expectedRepositoryRevision: preflight.snapshotRevision,
              lockWaitPolicy: context.lockWaitPolicy,
              buildEnvelope: (id, revision) => plans.createDriftEnvelope(
                operationId: id,
                expectedRepositoryRevision: revision,
                preflight: preflight,
              ),
              prepareCandidate: (envelope, token) async {
                if (!preflight.keepsExternal) {
                  final result = await revisions.prepareRestoreArtifacts(
                    envelope: envelope,
                    preflight: preflight,
                    cancellationToken: token,
                  );
                  if (result is DriftFailure<RevisionObjectId>) {
                    preparationFailure = result;
                    throw const _DriftPreparationRejected();
                  }
                  return null;
                }
                final result = await revisions.prepareAcceptExternal(
                  envelope: envelope,
                  preflight: preflight,
                  cancellationToken: token,
                );
                if (result is DriftFailure<PreparedRestorePublish>) {
                  preparationFailure = result;
                  throw const _DriftPreparationRejected();
                }
                final assembled = const DriftPlanAssembler().assemble(
                  preflight: preflight,
                  prepared:
                      (result as DriftSuccess<PreparedRestorePublish>).value,
                );
                if (assembled is DriftFailure<PreparedRestorePublishPlan>) {
                  preparationFailure = assembled;
                  throw const _DriftPreparationRejected();
                }
                return (assembled as DriftSuccess<PreparedRestorePublishPlan>)
                    .value;
              },
              buildPlan: (envelope, plan) => plans.sealDriftPlan(
                envelope: envelope,
                preflight: preflight,
                publishedPlan: plan,
                cancellationToken: context.cancellationToken,
              ),
              cancellationToken: context.cancellationToken,
              onBusinessCommitted: () {
                context.markBusinessCommitted();
                context.reportProgress(OperationProgressPhase.committing);
              },
            );
        if (preparationFailure != null && outcome is OperationRolledBack) {
          return _driftFailure(preparationFailure!);
        }
        return _resolveOutcome(
          outcome,
          review.managedSkillId,
          snapshots,
          integrity,
          context,
        );
      },
    ),
  ];
}

SkillsFailure<T> _unsafe<T>() => SkillsFailure(
  code: SkillsErrorCode.driftResolutionUnavailable,
  context: const {'reason': 'unsafeInspection'},
);
SkillsFailure<T> _stale<T>(String reason) => SkillsFailure(
  code: SkillsErrorCode.staleDriftReview,
  context: {'reason': reason},
);

Future<SkillsResult<MutationReport>> _resolveOutcome(
  OperationExecutionOutcome outcome,
  ManagedSkillId id,
  WorkspaceSnapshotPublisher snapshots,
  SkillIntegrityCoordinator integrity,
  SkillsCommandContext context,
) async {
  switch (outcome) {
    case OperationCompleted(
      :final operationId,
      :final committedRepositoryRevision,
      :final cleanupPending,
    ):
      return _reloadAndValidate(
        operationId: operationId,
        committedRepositoryRevision: committedRepositoryRevision,
        id: id,
        snapshots: snapshots,
        integrity: integrity,
        context: context,
        committedPending: false,
        cleanupPending: cleanupPending,
      );
    case OperationCommittedFinalizationPending(
      :final operationId,
      :final committedRepositoryRevision,
    ):
      return _reloadAndValidate(
        operationId: operationId,
        committedRepositoryRevision: committedRepositoryRevision,
        id: id,
        snapshots: snapshots,
        integrity: integrity,
        context: context,
        committedPending: true,
      );
    case OperationRollbackPending(:final originalReason):
      return SkillsFailure(
        code: SkillsErrorCode.recoveryFailed,
        context: {'reason': originalReason.name},
      );
    case OperationRejected(:final reason, :final actualRepositoryRevision):
      return _abort(reason, actualRepositoryRevision: actualRepositoryRevision);
    case OperationRolledBack(:final reason):
      return _abort(reason);
  }
}

Future<SkillsResult<MutationReport>> _reloadAndValidate({
  required OperationId operationId,
  required RepositoryRevision committedRepositoryRevision,
  required ManagedSkillId id,
  required WorkspaceSnapshotPublisher snapshots,
  required SkillIntegrityCoordinator integrity,
  required SkillsCommandContext context,
  required bool committedPending,
  bool cleanupPending = false,
}) async {
  context.reportProgress(OperationProgressPhase.finalizing);
  var pending = committedPending;
  try {
    await snapshots.reload();
  } on Object {
    pending = true;
  }
  await integrity.forceRevalidate(id);
  if (pending) {
    return SkillsCommittedFinalizationPending(
      operationId: operationId,
      committedRepositoryRevision: committedRepositoryRevision,
      warnings: [SkillsWarning(code: SkillsWarningCode.finalizationDeferred)],
    );
  }
  return SkillsSuccess(
    value: MutationReport(snapshot: snapshots.current, affectedSkillIds: {id}),
    changed: true,
    warnings: cleanupPending
        ? [SkillsWarning(code: SkillsWarningCode.recoveryCleanupDeferred)]
        : const [],
  );
}

SkillsFailure<T> _abort<T>(
  OperationAbortReason reason, {
  RepositoryRevision? actualRepositoryRevision,
}) => SkillsFailure(
  code: switch (reason) {
    OperationAbortReason.externalPreconditionChanged =>
      SkillsErrorCode.staleDriftReview,
    // The coordinator detects unrelated control-plane changes after planning
    // under the writer lock, preserving the normal stale Snapshot contract.
    // App adapters should map staleSnapshot and staleDriftReview to the same
    // stale presentation state and refresh before reviewing again.
    OperationAbortReason.staleRepositoryRevision =>
      SkillsErrorCode.staleSnapshot,
    OperationAbortReason.cancelled => SkillsErrorCode.operationCancelled,
    OperationAbortReason.lockUnavailable => SkillsErrorCode.repositoryBusy,
    OperationAbortReason.snapshotReadFailed => SkillsErrorCode.stateCorrupt,
    OperationAbortReason.journalWriteFailed => SkillsErrorCode.journalCorrupt,
    _ => SkillsErrorCode.operationFailed,
  },
  context: {
    'reason': reason == OperationAbortReason.externalPreconditionChanged
        ? 'artifactChanged'
        : reason.name,
    if (actualRepositoryRevision != null)
      'actualRepositoryRevision': actualRepositoryRevision.value,
  },
);

final class _DriftPreparationRejected implements Exception {
  const _DriftPreparationRejected();
}

SkillsFailure<T> _driftFailure<T>(DriftFailure<Object?> failure) =>
    SkillsFailure(
      code: switch (failure.code) {
        DriftFailureCode.operationCancelled =>
          SkillsErrorCode.operationCancelled,
        DriftFailureCode.skillNotFound => SkillsErrorCode.skillNotFound,
        DriftFailureCode.revisionStoreCorrupt =>
          SkillsErrorCode.revisionStoreCorrupt,
        DriftFailureCode.staleDriftReview => SkillsErrorCode.staleDriftReview,
        DriftFailureCode.driftResolutionUnavailable =>
          SkillsErrorCode.driftResolutionUnavailable,
        DriftFailureCode.updateCandidateResolutionRequired =>
          SkillsErrorCode.updateCandidateResolutionRequired,
        DriftFailureCode.dirtyDraftResolutionRequired =>
          SkillsErrorCode.dirtyDraftResolutionRequired,
        DriftFailureCode.invalidSkill => SkillsErrorCode.invalidSkill,
        DriftFailureCode.skillContentLimitExceeded =>
          SkillsErrorCode.skillContentLimitExceeded,
        DriftFailureCode.declaredNameChangeNotAllowed =>
          SkillsErrorCode.declaredNameChangeNotAllowed,
        DriftFailureCode.historicalNameMismatch =>
          SkillsErrorCode.historicalNameMismatch,
        DriftFailureCode.ioFailure => SkillsErrorCode.ioFailure,
      },
      context: failure.context,
    );
