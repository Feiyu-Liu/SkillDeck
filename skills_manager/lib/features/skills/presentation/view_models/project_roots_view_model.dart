import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

const _failureUnset = Object();

final projectRootsViewModelProvider =
    NotifierProvider.autoDispose<ProjectRootsViewModel, ProjectRootsState>(
      ProjectRootsViewModel.new,
    );

final class ProjectRootsState {
  const ProjectRootsState({
    this.busy = false,
    this.failure,
    this.operation = const WorkspaceOperationState(),
  });

  final bool busy;
  final AppFailure? failure;
  final WorkspaceOperationState operation;

  ProjectRootsState copyWith({
    bool? busy,
    Object? failure = _failureUnset,
    WorkspaceOperationState? operation,
  }) => ProjectRootsState(
    busy: busy ?? this.busy,
    failure: identical(failure, _failureUnset)
        ? this.failure
        : failure as AppFailure?,
    operation: operation ?? this.operation,
  );
}

final class ProjectRootsViewModel extends Notifier<ProjectRootsState> {
  late final WorkspaceOperationTracker _operationTracker;

  @override
  ProjectRootsState build() {
    _operationTracker = WorkspaceOperationTracker(
      onChanged: (operation) {
        if (ref.mounted) state = state.copyWith(operation: operation);
      },
      warningsOf: (progress) => progress.warnings,
      warningKey: workspaceWarningKey,
    );
    ref.onDispose(() => unawaited(_operationTracker.dispose()));
    return const ProjectRootsState();
  }

  Future<void> register(String path) => _run(
    createTask: () => ref
        .read(skillsWorkspaceRepositoryProvider)
        .registerProjectRoot(path: path),
    operationKey: WorkspaceOperationKind.registerProjectRoot.name,
    successMessage: AppNotificationMessage.projectRootRegistered,
  );

  Future<void> unregister(String id) => _run(
    createTask: () =>
        ref.read(skillsWorkspaceRepositoryProvider).unregisterProjectRoot(id),
    operationKey: WorkspaceOperationKind.unregisterProjectRoot.name,
    successMessage: AppNotificationMessage.projectRootUnregistered,
  );

  Future<void> cancelOperation() => _operationTracker.cancel();

  Future<void> _run({
    required WorkspaceTask<WorkspaceMutationReceipt> Function() createTask,
    required String operationKey,
    required AppNotificationMessage successMessage,
  }) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, failure: null);
    _operationTracker.clear();
    try {
      final completion = await createTask().trackedCompletionBy(
        _operationTracker,
      );
      if (!ref.mounted) return;
      final notifications = ref.read(
        appNotificationControllerProvider.notifier,
      );
      switch (completion) {
        case WorkspaceCompleted():
          if (state.operation.warnings.isEmpty) {
            notifications.success(successMessage);
          } else {
            notifications.warning(AppNotificationMessage.completedWithWarnings);
          }
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          ref
              .read(workspaceFinalizationCoordinatorProvider.notifier)
              .register(
                WorkspaceCommittedPending<void>(
                  operationId: operationId,
                  committedRevision: committedRevision,
                  warnings: _operationTracker.state.warnings,
                ),
              );
        case WorkspaceFailed(:final failure):
          _handleFailure(failure, StackTrace.current, operationKey);
      }
    } on Object catch (error, stackTrace) {
      _handleFailure(error, stackTrace, operationKey);
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  void _handleFailure(
    Object error,
    StackTrace stackTrace,
    String operationKey,
  ) {
    if (!ref.mounted) return;
    final failure = ref
        .read(appFailureReporterProvider)
        .capture(error, stackTrace, operationKey: operationKey);
    _operationTracker.addWarnings(
      failure.warnings.whereType<WorkspaceWarning>(),
    );
    if (failure.message == AppFailureMessage.operationCancelled) {
      state = state.copyWith(failure: null);
      ref
          .read(appNotificationControllerProvider.notifier)
          .info(AppNotificationMessage.operationCancelled);
    } else {
      state = state.copyWith(failure: failure);
      ref
          .read(appNotificationControllerProvider.notifier)
          .publish(AppNotification.failure(failure));
    }
  }
}
