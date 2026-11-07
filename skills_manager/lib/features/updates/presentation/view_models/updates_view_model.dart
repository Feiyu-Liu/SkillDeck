import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

final updatesViewModelProvider =
    NotifierProvider<UpdatesViewModel, UpdatesState>(UpdatesViewModel.new);

enum UpdatesStatus { idle, updating }

/// Mutation state for the Updates page.
///
/// Update reports are **not** held here. They live in the single App-session
/// authority, [skillUpdateStatusProvider], which the Skill detail page reads
/// too. This ViewModel owns only the mutations the page can start.
final class UpdatesState {
  const UpdatesState({
    this.status = UpdatesStatus.idle,
    this.error,
    this.operation = const WorkspaceOperationState(),
    this.updatingSkillIds = const <WorkspaceSkillId>{},
  });

  final UpdatesStatus status;
  final AppFailure? error;
  final WorkspaceOperationState operation;

  /// The Skills the running update was started for. The package reports only
  /// an opaque current item, so the page names what it is updating from this.
  final Set<WorkspaceSkillId> updatingSkillIds;

  bool get busy => status == UpdatesStatus.updating;
}

final class UpdatesViewModel extends Notifier<UpdatesState> {
  late final WorkspaceOperationTracker _operationTracker;

  @override
  UpdatesState build() {
    _operationTracker = WorkspaceOperationTracker(
      onChanged: (operation) {
        if (ref.mounted) {
          state = UpdatesState(
            status: state.status,
            error: state.error,
            operation: operation,
            updatingSkillIds: state.updatingSkillIds,
          );
        }
      },
      warningsOf: (progress) => progress.warnings,
      warningKey: workspaceWarningKey,
    );
    ref.onDispose(() => unawaited(_operationTracker.dispose()));
    return const UpdatesState();
  }

  /// Renders what is already known, and sweeps only when no in-session result
  /// exists. Opening a page is not a request to refresh.
  Future<void> ensureChecked() => _updates.startupSweep();

  /// The explicit **Check again** action. This is the only entry point that
  /// forces a full refresh, and a completed forced sweep resets the TTL.
  Future<void> checkAgain() => _updates.forceSweep();

  Future<void> cancelChecking() => _updates.cancelAll();

  /// Rechecks one Skill, or attaches to the active full sweep.
  Future<void> checkOne(WorkspaceSkillId skillId) =>
      _updates.checkSkill(skillId);

  Future<void> updateOne(WorkspaceSkillId skillId) =>
      _update({skillId}, successMessage: AppNotificationMessage.skillUpdated);

  Future<void> updateAll() => _update(
    _allowedUpdateSkillIds(
      ref.read(skillUpdateStatusProvider).availableSkillIds,
    ),
    successMessage: AppNotificationMessage.updatesApplied,
  );

  Future<void> abandonCandidate(WorkspaceSkillId skillId) async {
    if (state.busy || _mutationBlocked(skillId)) return;
    state = UpdatesState(
      status: UpdatesStatus.updating,
      operation: _operationTracker.state,
    );
    try {
      final completion = await ref
          .read(skillsWorkspaceRepositoryProvider)
          .abandonUpdateCandidate(skillId)
          .trackedCompletionBy(_operationTracker);
      if (!ref.mounted) return;
      switch (completion) {
        case WorkspaceCompleted():
          state = UpdatesState(
            status: UpdatesStatus.idle,
            operation: _operationTracker.state,
          );
          _notifications.success(
            AppNotificationMessage.updateCandidateAbandoned,
          );
        // Abandoning clears the Update Candidate, which changes the Skill's
        // update basis. The shared store observes that Snapshot change and
        // resets the entry, so no explicit recheck is issued here.
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          _publishFinalizationPending(operationId, committedRevision);
          state = UpdatesState(
            status: UpdatesStatus.idle,
            operation: _operationTracker.state,
          );
        case WorkspaceFailed(:final failure):
          _publishFailure(
            failure,
            operation: WorkspaceOperationKind.abandonUpdateCandidate,
          );
      }
    } on Object catch (error, stackTrace) {
      _publishFailure(
        error,
        stackTrace: stackTrace,
        operation: WorkspaceOperationKind.abandonUpdateCandidate,
      );
    }
  }

  Future<void> _update(
    Set<WorkspaceSkillId> skillIds, {
    required AppNotificationMessage successMessage,
  }) async {
    final allowedSkillIds = _allowedUpdateSkillIds(skillIds);
    if (state.busy || allowedSkillIds.isEmpty) return;
    state = UpdatesState(
      status: UpdatesStatus.updating,
      operation: _operationTracker.state,
      updatingSkillIds: allowedSkillIds,
    );
    try {
      final task = ref
          .read(skillsWorkspaceRepositoryProvider)
          .update(skillIds: allowedSkillIds);
      final completion = await task.trackedCompletionBy(_operationTracker);
      if (!ref.mounted) return;
      switch (completion) {
        case WorkspaceCompleted():
          state = UpdatesState(
            status: UpdatesStatus.idle,
            operation: _operationTracker.state,
          );
          _publishCompletion(successMessage);
          // A conflicting merge is also a *successful* mutation, so the new
          // state is derived from the committed Snapshot instead of being
          // assumed to be `current`.
          for (final skillId in allowedSkillIds) {
            _updates.deriveAfterUpdate(skillId);
          }
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          _publishFinalizationPending(operationId, committedRevision);
          state = UpdatesState(
            status: UpdatesStatus.idle,
            operation: _operationTracker.state,
          );
        case WorkspaceFailed(:final failure):
          _publishFailure(failure, operation: WorkspaceOperationKind.update);
      }
    } on Object catch (error, stackTrace) {
      _publishFailure(
        error,
        stackTrace: stackTrace,
        operation: WorkspaceOperationKind.update,
      );
    }
  }

  Future<void> cancelOperation() => _operationTracker.cancel();

  SkillUpdateStatusCoordinator get _updates =>
      ref.read(skillUpdateStatusProvider.notifier);

  AppNotificationController get _notifications =>
      ref.read(appNotificationControllerProvider.notifier);

  Set<WorkspaceSkillId> _allowedUpdateSkillIds(
    Set<WorkspaceSkillId> skillIds,
  ) => skillIds.where((skillId) => !_mutationBlocked(skillId)).toSet();

  bool _mutationBlocked(WorkspaceSkillId skillId) =>
      ref
          .read(workspaceSnapshotProvider)
          .value
          ?.findSkillById(skillId)
          ?.integrity
          .mutationBlocked ??
      false;

  void _publishFinalizationPending(String operationId, int committedRevision) =>
      ref
          .read(workspaceFinalizationCoordinatorProvider.notifier)
          .register(
            WorkspaceCommittedPending<void>(
              operationId: operationId,
              committedRevision: committedRevision,
              warnings: _operationTracker.state.warnings,
            ),
          );

  void _publishFailure(
    Object error, {
    StackTrace? stackTrace,
    required WorkspaceOperationKind operation,
  }) {
    final failure = ref
        .read(appFailureReporterProvider)
        .capture(
          error,
          stackTrace ?? StackTrace.current,
          operationKey: operation.name,
        );
    _operationTracker.addWarnings(
      failure.warnings.whereType<WorkspaceWarning>(),
    );
    if (!ref.mounted) return;
    state = UpdatesState(
      status: UpdatesStatus.idle,
      operation: _operationTracker.state,
    );
    if (failure.message == AppFailureMessage.operationCancelled) {
      _notifications.info(AppNotificationMessage.operationCancelled);
    } else {
      _notifications.publish(AppNotification.failure(failure));
    }
  }

  void _publishCompletion(AppNotificationMessage successMessage) {
    if (_operationTracker.state.warnings.isNotEmpty) {
      _notifications.warning(AppNotificationMessage.completedWithWarnings);
      return;
    }
    _notifications.success(successMessage);
  }
}
