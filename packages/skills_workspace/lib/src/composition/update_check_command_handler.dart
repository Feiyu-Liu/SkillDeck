import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/source/source_acquisition_models.dart';
import '../application/update/update_models.dart';
import '../application/update/update_planner.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/public_models.dart';

SkillsCommandHandler buildUpdateCheckCommandHandler({
  required WorkspaceSnapshotPublisher snapshots,
  required UpdatePlanner updates,
}) => TypedSkillsCommandHandler<CheckUpdatesRequest, List<UpdateReport>>(
  kind: WorkspaceOperationKind.checkUpdates,
  handle: (request, context) async {
    context.reportProgress(OperationProgressPhase.inspecting);
    final snapshot = snapshots.current;
    final requested = request.managedSkillIds == null
        ? snapshot.managedSkills.map((skill) => skill.id).toList()
        : request.managedSkillIds!.toList();
    requested.sort((left, right) => left.value.compareTo(right.value));
    // A Skill removed after the caller read its Snapshot gets no report rather
    // than failing every other Skill checked in the same request.
    final selected = [
      for (final managedSkillId in requested)
        if (snapshot.findSkill(managedSkillId) != null) managedSkillId,
    ];
    if (requested.isNotEmpty && selected.isEmpty) {
      return SkillsFailure<List<UpdateReport>>(
        code: SkillsErrorCode.skillNotFound,
        context: <String, Object?>{'managedSkillId': requested.first.value},
      );
    }

    var completed = 0;
    final results = await updates.checkUpdates(
      snapshot: snapshot,
      managedSkillIds: selected,
      cancellationToken: context.cancellationToken,
      onSettled: (managedSkillId, _) {
        completed += 1;
        context.reportProgress(
          OperationProgressPhase.inspecting,
          currentItem: managedSkillId.value,
          completed: completed,
          total: selected.length,
        );
      },
    );
    final reports = <UpdateReport>[];
    final warnings = <SkillsWarning>[];
    for (final managedSkillId in selected) {
      final result = results[managedSkillId]!;
      final check = result.valueOrNull;
      if (check != null) {
        warnings.addAll(_sourceWarnings(check.sourceWarnings));
        final skill = snapshot.findSkill(managedSkillId)!;
        reports.add(
          UpdateReport(
            managedSkillId: managedSkillId,
            status: check.changed
                ? _requiresResolution(skill)
                      ? UpdateStatus.resolutionRequired
                      : UpdateStatus.updateAvailable
                : UpdateStatus.current,
            currentContentHash: check.currentUpstreamContentHash,
            availableContentHash: check.incomingContentHash,
            resolvedSourceRevision: check.resolvedSourceRevision,
          ),
        );
        continue;
      }

      final failure = result.failureOrNull!;
      warnings.addAll(_sourceWarnings(failure.sourceWarnings));
      if (failure.code == UpdatePlanningFailureCode.operationCancelled) {
        return SkillsFailure<List<UpdateReport>>(
          code: SkillsErrorCode.operationCancelled,
          warnings: warnings,
        );
      }
      if (failure.code == UpdatePlanningFailureCode.skillNotFound) {
        return SkillsFailure<List<UpdateReport>>(
          code: SkillsErrorCode.skillNotFound,
          context: <String, Object?>{'managedSkillId': managedSkillId.value},
          warnings: warnings,
        );
      }
      reports.add(
        UpdateReport(
          managedSkillId: managedSkillId,
          status: _failureStatus(failure.code),
          failureReason: _failureReason(failure),
          currentContentHash: snapshot
              .findSkill(managedSkillId)!
              .currentRevision
              .contentHash,
        ),
      );
    }
    context.reportProgress(
      OperationProgressPhase.inspecting,
      completed: selected.length,
      total: selected.length,
    );
    return SkillsSuccess<List<UpdateReport>>(
      value: reports,
      changed: false,
      warnings: warnings,
    );
  },
);

UpdateCheckFailureReason? _failureReason(
  UpdatePlanningFailure<UpdateCheck> failure,
) {
  if (_failureStatus(failure.code) != UpdateStatus.sourceUnavailable) {
    return null;
  }
  if (failure.code != UpdatePlanningFailureCode.sourceAcquisitionFailed) {
    return failure.code == UpdatePlanningFailureCode.ioFailure
        ? UpdateCheckFailureReason.ioFailure
        : UpdateCheckFailureReason.sourceUnavailable;
  }
  return switch (failure.context['sourceCode']) {
    'sourceAuthenticationRequired' =>
      UpdateCheckFailureReason.authenticationRequired,
    'gitUnavailable' => UpdateCheckFailureReason.gitUnavailable,
    'developerToolsRequired' => UpdateCheckFailureReason.developerToolsRequired,
    'gitTimedOut' => UpdateCheckFailureReason.timedOut,
    'gitFailed' => UpdateCheckFailureReason.gitFailed,
    'ioFailure' => UpdateCheckFailureReason.ioFailure,
    _ => UpdateCheckFailureReason.sourceUnavailable,
  };
}

bool _requiresResolution(ManagedSkill skill) =>
    skill.updateCandidate != null || (skill.draft?.isDirty ?? false);

UpdateStatus _failureStatus(UpdatePlanningFailureCode code) => switch (code) {
  UpdatePlanningFailureCode.updateUnsupported => UpdateStatus.updateUnsupported,
  UpdatePlanningFailureCode.updateCandidateNotFound ||
  UpdatePlanningFailureCode.updateConflictNotFound ||
  UpdatePlanningFailureCode.updateCandidateResolutionRequired ||
  UpdatePlanningFailureCode.dirtyDraftResolutionRequired ||
  UpdatePlanningFailureCode.unresolvedUpdateConflicts ||
  UpdatePlanningFailureCode.slotMigrationConflict ||
  UpdatePlanningFailureCode.unsupportedSkillName ||
  UpdatePlanningFailureCode.declaredNameChangeNotAllowed ||
  UpdatePlanningFailureCode.staleIntent ||
  UpdatePlanningFailureCode.draftChangedDuringPublish ||
  UpdatePlanningFailureCode.invalidSkill ||
  UpdatePlanningFailureCode.invalidPreparedEvidence =>
    UpdateStatus.resolutionRequired,
  UpdatePlanningFailureCode.operationCancelled ||
  UpdatePlanningFailureCode.skillNotFound ||
  UpdatePlanningFailureCode.draftInspectionFailed ||
  UpdatePlanningFailureCode.revisionStateUnavailable ||
  UpdatePlanningFailureCode.sourceAcquisitionFailed ||
  UpdatePlanningFailureCode.sourceContinuityLost ||
  UpdatePlanningFailureCode.revisionStoreUnavailable ||
  UpdatePlanningFailureCode.recoveryEvidenceFailed ||
  UpdatePlanningFailureCode.ioFailure => UpdateStatus.sourceUnavailable,
};

List<SkillsWarning> _sourceWarnings(List<SourceAcquisitionWarning> warnings) =>
    warnings
        .map(
          (warning) => SkillsWarning(
            code: SkillsWarningCode.sourceEntrySkipped,
            context: warning.context,
          ),
        )
        .toList(growable: false);
