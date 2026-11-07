import '../../domain/cancellation.dart';
import '../../domain/public_models.dart';
import '../history/history_models.dart';
import '../history/history_ports.dart';
import '../ports/workspace_lifecycle_ports.dart';
import 'drift_models.dart';
import 'drift_artifacts.dart';

final class DriftResolutionPlanner {
  const DriftResolutionPlanner({
    required WorkspaceHistoryContentPort content,
    required DateTime Function() clock,
  }) : _content = content,
       _clock = clock;
  final WorkspaceHistoryContentPort _content;
  final DateTime Function() _clock;

  Future<DriftResult<void>> validateEffectiveRevision(
    DriftReviewEvidence review,
  ) async {
    final state = await _content.readRestoreState(review.managedSkillId);
    if (state == null) {
      return DriftFailure(code: DriftFailureCode.revisionStoreCorrupt);
    }
    if (state.currentEffective != review.inspected.effectiveObjectId) {
      return DriftFailure(
        code: DriftFailureCode.staleDriftReview,
        context: const {'reason': 'effectiveRevisionChanged'},
      );
    }
    return const DriftSuccess(value: null);
  }

  Future<DriftResult<DriftResolutionPreflight>> plan({
    required RepositorySnapshot snapshot,
    required DriftReviewEvidence review,
    required SkillMaterializationInspection current,
    required SkillDriftResolution resolution,
    required CancellationToken cancellationToken,
  }) async {
    final skill = snapshot.findSkill(review.managedSkillId);
    if (skill == null) {
      return DriftFailure(code: DriftFailureCode.skillNotFound);
    }
    final state = await _content.readRestoreState(skill.id);
    if (state == null) {
      return DriftFailure(code: DriftFailureCode.revisionStoreCorrupt);
    }
    if (state.currentEffective != review.inspected.effectiveObjectId ||
        current.effectiveObjectId != review.inspected.effectiveObjectId) {
      return DriftFailure(
        code: DriftFailureCode.staleDriftReview,
        context: const {'reason': 'effectiveRevisionChanged'},
      );
    }
    if (cancellationToken.isCancelled) {
      return DriftFailure(code: DriftFailureCode.operationCancelled);
    }
    for (final artifact in review.inspected.artifacts) {
      if (artifact.inspection.mismatchKind != null &&
          !current.artifacts.any(
            (candidate) =>
                candidate.targetPath == artifact.targetPath &&
                candidate.locationKind == artifact.locationKind,
          )) {
        return DriftFailure(
          code: DriftFailureCode.staleDriftReview,
          context: const {'reason': 'artifactChanged'},
        );
      }
    }
    final reviewedPaths = review.inspected.artifacts
        .where((artifact) => artifact.inspection.mismatchKind != null)
        .map((artifact) => artifact.targetPath)
        .toSet();
    if (current.artifacts.any(
      (artifact) =>
          artifact.inspection.mismatchKind != null &&
          !reviewedPaths.contains(artifact.targetPath),
    )) {
      return DriftFailure(
        code: DriftFailureCode.staleDriftReview,
        context: const {'reason': 'artifactChanged'},
      );
    }
    String? selectedPath;
    String? fingerprint;
    var hadCleanDraft = false;
    if (resolution case KeepExternalSkillDrift(:final artifactId)) {
      final matches = review.artifacts.where((a) => a.artifactId == artifactId);
      if (matches.isEmpty) {
        return DriftFailure(
          code: DriftFailureCode.staleDriftReview,
          context: const {'reason': 'artifactNotFound'},
        );
      }
      final selected = matches.single;
      if (!selected.canKeepExternal) {
        return DriftFailure(
          code: DriftFailureCode.driftResolutionUnavailable,
          context: const {'reason': 'keepNotAllowed'},
        );
      }
      final observed = review.inspected.artifacts.singleWhere(
        (artifact) => driftArtifactId(artifact) == artifactId,
      );
      selectedPath = observed.targetPath;
      fingerprint = observed.inspection.fingerprint;
      if (skill.updateCandidate != null) {
        return DriftFailure(
          code: DriftFailureCode.updateCandidateResolutionRequired,
        );
      }
      if (skill.draft != null) {
        final dirty = await _content.inspectDraftDirty(
          skill: skill,
          state: state,
          cancellationToken: cancellationToken,
        );
        if (dirty.failureOrNull != null) {
          return DriftFailure(
            code:
                dirty.failureOrNull!.code ==
                    HistoryFailureCode.operationCancelled
                ? DriftFailureCode.operationCancelled
                : DriftFailureCode.invalidSkill,
            context: dirty.failureOrNull!.context,
          );
        }
        if (dirty.valueOrNull!) {
          return DriftFailure(
            code: DriftFailureCode.dirtyDraftResolutionRequired,
          );
        }
        hadCleanDraft = true;
      }
    }
    return DriftSuccess(
      value: DriftResolutionPreflight(
        snapshotRevision: snapshot.revision,
        plannedAtMicros: _clock().toUtc().microsecondsSinceEpoch,
        skill: skill,
        state: state,
        review: review,
        current: current,
        resolution: resolution,
        selectedPath: selectedPath,
        selectedFingerprint: fingerprint,
        hadCleanDraft: hadCleanDraft,
      ),
    );
  }
}
