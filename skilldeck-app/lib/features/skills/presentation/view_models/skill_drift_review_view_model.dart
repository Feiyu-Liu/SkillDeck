import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

enum SkillDriftReviewStatus { loading, loaded, busy, stale, failed }

const _unset = Object();

final skillDriftReviewViewModelProvider = NotifierProvider.autoDispose
    .family<SkillDriftReviewViewModel, SkillDriftReviewState, WorkspaceSkillId>(
      SkillDriftReviewViewModel.new,
    );

final class SkillDriftReviewState {
  SkillDriftReviewState({
    this.status = SkillDriftReviewStatus.loading,
    this.review,
    this.selectedArtifactId,
    this.restoreSelected = false,
    this.failure,
    Map<String, String> exportedPaths = const {},
    this.operation = const WorkspaceOperationState(),
  }) : exportedPaths = Map.unmodifiable(exportedPaths);

  final SkillDriftReviewStatus status;
  final WorkspaceSkillDriftReview? review;
  final String? selectedArtifactId;

  /// Whether the user chose to restore the SkillDeck version. Mutually
  /// exclusive with [selectedArtifactId].
  final bool restoreSelected;
  final AppFailure? failure;
  final Map<String, String> exportedPaths;
  final WorkspaceOperationState operation;

  bool get isBusy => status == SkillDriftReviewStatus.busy;
  bool get canReviewActions =>
      status == SkillDriftReviewStatus.loaded ||
      status == SkillDriftReviewStatus.failed;
  bool get canKeepExternal =>
      canReviewActions &&
      review?.artifacts.any(
            (artifact) =>
                artifact.artifactId == selectedArtifactId &&
                artifact.canKeepExternal,
          ) ==
          true;
  bool get canRestoreManaged => canReviewActions && review != null;

  SkillDriftReviewState copyWith({
    SkillDriftReviewStatus? status,
    Object? review = _unset,
    Object? selectedArtifactId = _unset,
    bool? restoreSelected,
    Object? failure = _unset,
    Map<String, String>? exportedPaths,
    WorkspaceOperationState? operation,
  }) => SkillDriftReviewState(
    status: status ?? this.status,
    review: identical(review, _unset)
        ? this.review
        : review as WorkspaceSkillDriftReview?,
    selectedArtifactId: identical(selectedArtifactId, _unset)
        ? this.selectedArtifactId
        : selectedArtifactId as String?,
    restoreSelected: restoreSelected ?? this.restoreSelected,
    failure: identical(failure, _unset) ? this.failure : failure as AppFailure?,
    exportedPaths: exportedPaths ?? this.exportedPaths,
    operation: operation ?? this.operation,
  );
}

final class SkillDriftReviewViewModel extends Notifier<SkillDriftReviewState> {
  SkillDriftReviewViewModel(this.skillId);
  final WorkspaceSkillId skillId;
  late WorkspaceOperationTracker _operationTracker;
  var _generation = 0;
  var _lifecycleGeneration = 0;
  var _active = false;

  @override
  SkillDriftReviewState build() {
    _active = false;
    final lifecycle = ++_lifecycleGeneration;
    final buildRef = ref;
    final tracker = WorkspaceOperationTracker(
      onChanged: (operation) {
        if (buildRef.mounted && lifecycle == _lifecycleGeneration) {
          state = state.copyWith(operation: operation);
        }
      },
      warningsOf: (progress) => progress.warnings,
      warningKey: workspaceWarningKey,
    );
    _operationTracker = tracker;
    ref.onDispose(() {
      _generation += 1;
      _lifecycleGeneration += 1;
      unawaited(tracker.cancel());
      unawaited(tracker.dispose());
    });
    return SkillDriftReviewState();
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  Future<void> load({bool refresh = false}) async {
    if (_active) return;
    final needsRefresh =
        refresh || state.status == SkillDriftReviewStatus.stale;
    _active = true;
    final generation = ++_generation;
    final tracker = _operationTracker;
    state = state.copyWith(
      status: SkillDriftReviewStatus.loading,
      review: null,
      selectedArtifactId: null,
      restoreSelected: false,
      failure: null,
      exportedPaths: const {},
    );
    tracker.clear();
    var operation = needsRefresh
        ? WorkspaceOperationKind.refresh
        : WorkspaceOperationKind.inspectSkillDrift;
    try {
      final repository = ref.read(skillsWorkspaceRepositoryProvider);
      final refreshWarnings = <WorkspaceWarning>[];
      if (needsRefresh) {
        final completion = await repository.refresh();
        if (!_current(generation)) return;
        refreshWarnings.addAll(completion.warnings);
        switch (completion) {
          case WorkspaceCompleted():
            break;
          case WorkspaceFailed(:final failure):
            tracker.addWarnings(refreshWarnings);
            _fail(failure, StackTrace.current, operation);
            return;
          case WorkspaceCommittedPending():
            tracker.addWarnings(refreshWarnings);
            _fail(_unexpectedPending(operation), StackTrace.current, operation);
            return;
        }
      }
      operation = WorkspaceOperationKind.inspectSkillDrift;
      final completion = await repository
          .inspectSkillDrift(skillId)
          .trackedCompletionBy(tracker);
      if (!_current(generation)) return;
      tracker.addWarnings(refreshWarnings);
      switch (completion) {
        case WorkspaceCompleted(:final value):
          state = state.copyWith(
            status: SkillDriftReviewStatus.loaded,
            review: value,
            selectedArtifactId: null,
            // Restoring is the only resolution when no location can be kept,
            // so there is nothing for the user to choose.
            restoreSelected:
                value.artifacts.isNotEmpty &&
                !value.artifacts.any((artifact) => artifact.canKeepExternal),
            failure: null,
          );
        case WorkspaceFailed(:final failure):
          _fail(failure, StackTrace.current, operation);
        case WorkspaceCommittedPending():
          _fail(_unexpectedPending(operation), StackTrace.current, operation);
      }
    } on Object catch (error, stackTrace) {
      if (_current(generation)) _fail(error, stackTrace, operation);
    } finally {
      if (_current(generation)) _active = false;
    }
  }

  void select(String artifactId) {
    if (!state.canReviewActions ||
        state.review?.artifacts.any(
              (artifact) =>
                  artifact.artifactId == artifactId && artifact.canKeepExternal,
            ) !=
            true) {
      return;
    }
    state = state.copyWith(
      status: SkillDriftReviewStatus.loaded,
      selectedArtifactId: artifactId,
      restoreSelected: false,
      failure: null,
    );
  }

  void selectRestore() {
    if (!state.canReviewActions || state.review == null) return;
    state = state.copyWith(
      status: SkillDriftReviewStatus.loaded,
      selectedArtifactId: null,
      restoreSelected: true,
      failure: null,
    );
  }

  Future<void> export(String artifactId) async {
    final review = state.review;
    if (_active ||
        !state.canReviewActions ||
        review == null ||
        !review.artifacts.any(
          (artifact) => artifact.artifactId == artifactId && artifact.canExport,
        )) {
      return;
    }
    _active = true;
    final generation = ++_generation;
    final tracker = _operationTracker;
    state = state.copyWith(status: SkillDriftReviewStatus.busy, failure: null);
    tracker.clear();
    const operation = WorkspaceOperationKind.exportSkillDriftArtifact;
    try {
      final destination = await ref
          .read(directoryPickerProvider)
          .pickDirectory();
      if (!_current(generation)) return;
      if (destination == null) {
        state = state.copyWith(status: SkillDriftReviewStatus.loaded);
        return;
      }
      final completion = await ref
          .read(skillsWorkspaceRepositoryProvider)
          .exportSkillDriftArtifact(
            review: review,
            artifactId: artifactId,
            destinationDirectory: destination,
          )
          .trackedCompletionBy(tracker);
      if (!_current(generation)) return;
      switch (completion) {
        case WorkspaceCompleted(:final value):
          state = state.copyWith(
            status: SkillDriftReviewStatus.loaded,
            exportedPaths: {
              ...state.exportedPaths,
              artifactId: value.exportedPath,
            },
          );
        case WorkspaceFailed(:final failure):
          _fail(failure, StackTrace.current, operation);
        case WorkspaceCommittedPending():
          _fail(_unexpectedPending(operation), StackTrace.current, operation);
      }
    } on Object catch (error, stackTrace) {
      if (_current(generation)) _fail(error, stackTrace, operation);
    } finally {
      if (_current(generation)) _active = false;
    }
  }

  Future<bool> keepExternal() {
    if (!state.canKeepExternal) return Future.value(false);
    return _resolve(
      WorkspaceDriftResolution.keepExternal(state.selectedArtifactId!),
    );
  }

  Future<bool> restoreManaged() {
    if (!state.canRestoreManaged) return Future.value(false);
    return _resolve(const WorkspaceDriftResolution.restoreManaged());
  }

  Future<bool> _resolve(WorkspaceDriftResolution resolution) async {
    if (_active) return false;
    final review = state.review!;
    final repository = ref.read(skillsWorkspaceRepositoryProvider);
    // Capture the root coordinator before awaiting. It outlives a closed dialog.
    final finalization = ref.read(
      workspaceFinalizationCoordinatorProvider.notifier,
    );
    _active = true;
    final generation = ++_generation;
    final tracker = _operationTracker;
    state = state.copyWith(status: SkillDriftReviewStatus.busy, failure: null);
    tracker.clear();
    const operation = WorkspaceOperationKind.resolveSkillDrift;
    try {
      final completion = await repository
          .resolveSkillDrift(review: review, resolution: resolution)
          .trackedCompletionBy(tracker);
      switch (completion) {
        case WorkspaceCompleted():
          if (_current(generation)) {
            state = state.copyWith(status: SkillDriftReviewStatus.loaded);
            if (state.operation.warnings.isNotEmpty) {
              ref
                  .read(appNotificationControllerProvider.notifier)
                  .warning(AppNotificationMessage.completedWithWarnings);
            }
          }
          return true;
        case WorkspaceFailed(:final failure):
          if (_current(generation)) {
            _fail(failure, StackTrace.current, operation);
          }
          return false;
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          if (finalization.ref.mounted) {
            finalization.register(
              WorkspaceCommittedPending<void>(
                operationId: operationId,
                committedRevision: committedRevision,
                warnings: tracker.state.warnings,
              ),
            );
          }
          if (_current(generation)) {
            state = state.copyWith(status: SkillDriftReviewStatus.loaded);
          }
          return true;
      }
    } on Object catch (error, stackTrace) {
      if (_current(generation)) _fail(error, stackTrace, operation);
      return false;
    } finally {
      if (_current(generation)) _active = false;
    }
  }

  Future<void> cancelOperation() => _operationTracker.cancel();

  WorkspaceFailure _unexpectedPending(WorkspaceOperationKind operation) =>
      WorkspaceFailure(
        code: WorkspaceErrorCode.operationFailed,
        operation: operation,
      );

  void _fail(
    Object error,
    StackTrace stackTrace,
    WorkspaceOperationKind operation,
  ) {
    if (!ref.mounted) return;
    final failure = ref
        .read(appFailureReporterProvider)
        .capture(error, stackTrace, operationKey: operation.name);
    _operationTracker.addWarnings(
      failure.warnings.whereType<WorkspaceWarning>(),
    );
    final stale =
        failure is WorkspaceFailure &&
        (failure.code == WorkspaceErrorCode.staleDriftReview ||
            failure.code == WorkspaceErrorCode.staleSnapshot);
    state = state.copyWith(
      status: stale
          ? SkillDriftReviewStatus.stale
          : SkillDriftReviewStatus.failed,
      review: stale ? null : state.review,
      selectedArtifactId: stale ? null : state.selectedArtifactId,
      restoreSelected: !stale && state.restoreSelected,
      failure: failure,
    );
  }
}
