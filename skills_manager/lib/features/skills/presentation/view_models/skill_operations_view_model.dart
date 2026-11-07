import 'dart:async';

import 'package:skills_manager/features/skills/activation_location_providers.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';

final skillOperationsViewModelProvider =
    NotifierProvider<SkillOperationsViewModel, SkillOperationsState>(
      SkillOperationsViewModel.new,
    );

enum RemoveSkillOutcome { removed, stale, cancelled, pending, failed }

enum ReplaceSourceOutcome { replaced, stale, cancelled, pending }

enum SetActivationOutcome { completed, cancelled, failed, pending }

typedef ActivationTakeoverConfirmation = Future<bool> Function(
  WorkspaceActivationTakeoverDraft draft,
);

/// One canonical location serves many Skills, so busy state is per Skill and
/// location: toggling one Skill must not spin every row sharing that Agent.
typedef ActivationBusyKey = ({WorkspaceSkillId skillId, String location});

final class SkillOperationsState {
  const SkillOperationsState({
    this.targets = const [],
    this.targetsLoaded = false,
    this.loadingTargets = false,
    this.busyActivations = const {},
    this.error,
    this.operation = const WorkspaceOperationState(),
  });

  final List<WorkspaceActivationTarget> targets;
  final bool targetsLoaded;
  final bool loadingTargets;
  final Set<ActivationBusyKey> busyActivations;
  final AppFailure? error;
  final WorkspaceOperationState operation;

  bool isActivationBusy(WorkspaceSkillId skillId, String location) =>
      busyActivations.contains((skillId: skillId, location: location));

  SkillOperationsState copyWith({
    List<WorkspaceActivationTarget>? targets,
    bool? targetsLoaded,
    bool? loadingTargets,
    Set<ActivationBusyKey>? busyActivations,
    AppFailure? error,
    bool clearError = false,
    WorkspaceOperationState? operation,
  }) => SkillOperationsState(
    targets: targets ?? this.targets,
    targetsLoaded: targetsLoaded ?? this.targetsLoaded,
    loadingTargets: loadingTargets ?? this.loadingTargets,
    busyActivations: busyActivations ?? this.busyActivations,
    error: clearError ? null : error ?? this.error,
    operation: operation ?? this.operation,
  );
}

final class SkillOperationsViewModel extends Notifier<SkillOperationsState> {
  late WorkspaceOperationTracker _operationTracker;
  bool _reloadTargetsPending = false;
  Future<void>? _targetLoad;

  @override
  SkillOperationsState build() {
    _operationTracker = WorkspaceOperationTracker(
      onChanged: (operation) {
        if (ref.mounted) state = state.copyWith(operation: operation);
      },
      warningsOf: (progress) => progress.warnings,
      warningKey: workspaceWarningKey,
    );
    ref.onDispose(() => unawaited(_operationTracker.dispose()));
    ref.listen(activationCatalogRevisionProvider, (_, _) {
      if (state.targetsLoaded || state.loadingTargets) unawaited(loadTargets());
    });
    ref.listen(workspaceProjectRootsProvider, (previous, next) {
      if (previous?.hasValue == true &&
          next.hasValue &&
          (state.targetsLoaded || state.loadingTargets)) {
        final before = previous?.value
            ?.map((r) => '${r.id}\u0000${r.path}')
            .join('\u0001');
        final after = next.value!
            .map((r) => '${r.id}\u0000${r.path}')
            .join('\u0001');
        if (before != after) unawaited(loadTargets());
      }
    });
    return const SkillOperationsState();
  }

  Future<void> loadTargets() async {
    if (_targetLoad case final pending?) {
      _reloadTargetsPending = true;
      await pending;
      return;
    }
    final loading = _loadTargetPasses();
    _targetLoad = loading;
    try {
      await loading;
    } finally {
      _targetLoad = null;
    }
  }

  Future<void> _loadTargetPasses() async {
    do {
      _reloadTargetsPending = false;
      await _loadTargetsOnce();
    } while (ref.mounted && _reloadTargetsPending);
  }

  Future<void> _loadTargetsOnce() async {
    state = state.copyWith(
      loadingTargets: true,
      clearError: true,
      targets: const [],
      targetsLoaded: false,
    );
    try {
      final globalTargets = await _readCompletion(
        ref.read(
          activationTargetsProvider((
            scope: WorkspaceScope.global,
            projectRootId: null,
          )).future,
        ),
        WorkspaceOperationKind.inspectActivationTargets,
      );
      if (globalTargets == null) {
        if (ref.mounted) {
          state = state.copyWith(loadingTargets: false, targetsLoaded: true);
        }
        return;
      }
      final targets = <WorkspaceActivationTarget>[...globalTargets];
      final snapshot = ref.read(workspaceSnapshotProvider).value;
      for (final root in snapshot?.projectRoots ?? const <SkillProjectRoot>[]) {
        final projectTargets = await _readCompletion(
          ref.read(
            activationTargetsProvider((
              scope: WorkspaceScope.project,
              projectRootId: root.id,
            )).future,
          ),
          WorkspaceOperationKind.inspectActivationTargets,
        );
        if (projectTargets == null) {
          if (ref.mounted) {
            state = state.copyWith(loadingTargets: false, targetsLoaded: true);
          }
          return;
        }
        targets.addAll(projectTargets);
      }
      if (!ref.mounted) return;
      state = state.copyWith(
        targets: List.unmodifiable(targets),
        targetsLoaded: true,
        loadingTargets: false,
      );
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      state = state.copyWith(
        error: ref
            .read(appFailureReporterProvider)
            .capture(
              error,
              stackTrace,
              operationKey:
                  WorkspaceOperationKind.inspectActivationTargets.name,
            ),
        loadingTargets: false,
        targetsLoaded: true,
      );
    }
  }

  void retryTargets() =>
      ref.read(activationCatalogRevisionProvider.notifier).refresh();

  /// [locations] lets a caller drive more than one Activation Location
  /// through a single Workspace commit (e.g. a "toggle all Agents" switch),
  /// so every row flips together instead of one at a time behind the
  /// `operation.running` single-flight guard below. Defaults to
  /// `target.location` for the common single-row case.
  Future<SetActivationOutcome> setActivation({
    required WorkspaceSkillId skillId,
    required WorkspaceActivationTarget target,
    required bool active,
    required ActivationTakeoverConfirmation onTakeoverRequired,
    Set<String>? agentIds,
    Set<String>? locations,
  }) async {
    final busyLocations = locations ?? {target.location};
    final busyKeys = {
      for (final location in busyLocations)
        (skillId: skillId, location: location),
    };
    if (state.operation.running ||
        state.busyActivations.any(busyKeys.contains)) {
      return SetActivationOutcome.failed;
    }
    state = state.copyWith(
      busyActivations: {...state.busyActivations, ...busyKeys},
      clearError: true,
    );
    try {
      final workspace = ref.read(skillsWorkspaceRepositoryProvider);
      if (active) {
        final completion = await workspace
            .activate(
              skillIds: {skillId},
              scope: target.scope,
              agentIds: agentIds ?? {target.agentId},
              projectRootId: target.projectRootId,
              activationMethod: ref.read(globalActivationMethodProvider),
            )
            .trackedCompletionBy(_operationTracker);
        if (!ref.mounted) return SetActivationOutcome.failed;
        late final WorkspaceActivationAttempt attempt;
        switch (completion) {
          case WorkspaceCompleted(:final value):
            attempt = value;
          case WorkspaceCommittedPending(
            :final operationId,
            :final committedRevision,
          ):
            _publishFinalizationPending(operationId, committedRevision);
            return SetActivationOutcome.pending;
          case WorkspaceFailed(:final failure):
            return _activationFailure(failure);
        }
        switch (attempt) {
          case WorkspaceActivationCompleted():
            _publishCompletion(AppNotificationMessage.activationEnabled);
            return SetActivationOutcome.completed;
          case WorkspaceActivationTakeoverRequired(:final draft):
            final confirmed = await onTakeoverRequired(draft);
            if (!ref.mounted) return SetActivationOutcome.failed;
            if (!confirmed) return SetActivationOutcome.cancelled;
            return await _confirmActivationTakeover(draft);
        }
      }
      final completion = await workspace
          .deactivate(skillIds: {skillId}, locations: busyLocations)
          .trackedCompletionBy(_operationTracker);
      if (!ref.mounted) return SetActivationOutcome.failed;
      switch (completion) {
        case WorkspaceCompleted():
          _publishCompletion(AppNotificationMessage.activationDisabled);
          return SetActivationOutcome.completed;
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          _publishFinalizationPending(operationId, committedRevision);
          return SetActivationOutcome.pending;
        case WorkspaceFailed(:final failure):
          return _activationFailure(failure);
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return SetActivationOutcome.failed;
      _publishOperationFailure(
        error,
        stackTrace,
        operation: active
            ? WorkspaceOperationKind.activate
            : WorkspaceOperationKind.deactivate,
      );
      return SetActivationOutcome.failed;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          busyActivations: {...state.busyActivations}..removeAll(busyKeys),
        );
      }
    }
  }

  Future<SetActivationOutcome> _confirmActivationTakeover(
    WorkspaceActivationTakeoverDraft draft,
  ) async {
    try {
      final completion = await ref
          .read(skillsWorkspaceRepositoryProvider)
          .confirmActivationTakeover(draft)
          .trackedCompletionBy(_operationTracker);
      if (!ref.mounted) return SetActivationOutcome.failed;
      switch (completion) {
        case WorkspaceCompleted():
          _publishCompletion(AppNotificationMessage.activationEnabled);
          return SetActivationOutcome.completed;
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          _publishFinalizationPending(operationId, committedRevision);
          return SetActivationOutcome.pending;
        case WorkspaceFailed(:final failure):
          return _activationFailure(failure);
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return SetActivationOutcome.failed;
      _publishOperationFailure(
        error,
        stackTrace,
        operation: WorkspaceOperationKind.confirmActivationTakeover,
      );
      return SetActivationOutcome.failed;
    }
  }

  /// Requests a check through the single shared scheduler.
  ///
  /// The detail page never starts a check on its own; this runs only on an
  /// explicit press. A request for a Skill already in flight attaches to that
  /// check rather than issuing a second one, and still raises the checking
  /// toast — the old ViewModel-local guard returned silently, so a press during
  /// an in-flight check produced no feedback at all.
  ///
  /// The checking toast is a task notification that resolves into the outcome.
  /// Only `updateAvailable` changes the action itself, so without this the
  /// other four outcomes would leave an explicit press with no visible result
  /// at all.
  Future<SkillUpdateState> checkUpdate(WorkspaceSkillId skillId) async {
    final task = _notifications.startTask(
      const AppNotification.message(
        severity: AppNotificationSeverity.info,
        message: AppNotificationMessage.updateCheckStarted,
      ),
    );
    final settled = await ref
        .read(skillUpdateStatusProvider.notifier)
        .checkSkill(skillId);
    if (!ref.mounted) {
      task.dismiss();
      return settled;
    }
    switch (settled) {
      // An explicitly requested check reports its failure once. Background
      // sweep failures stay silent and update state only.
      case SkillUpdateCheckFailed(:final failure):
        task.finish(
          failure.message == AppFailureMessage.operationCancelled
              ? const AppNotification.message(
                  severity: AppNotificationSeverity.info,
                  message: AppNotificationMessage.operationCancelled,
                )
              : AppNotification.failure(failure),
        );
      case SkillUpdateChecked(:final report):
        task.finish(_checkOutcome(report.status));
      // The entry was invalidated while the check ran, so there is no outcome
      // to report. Withdraw the toast instead of inventing one.
      case SkillUpdateNotChecked():
      case SkillUpdateChecking():
        task.dismiss();
    }
    return settled;
  }

  AppNotification _checkOutcome(
    WorkspaceUpdateStatus status,
  ) => switch (status) {
    WorkspaceUpdateStatus.current => const AppNotification.message(
      severity: AppNotificationSeverity.success,
      message: AppNotificationMessage.updateCheckCurrent,
    ),
    WorkspaceUpdateStatus.updateAvailable => const AppNotification.message(
      severity: AppNotificationSeverity.success,
      message: AppNotificationMessage.updateCheckAvailable,
    ),
    // The Source was reached and reported unavailable. That is an outcome, not
    // a failed check, so it is a warning rather than an error.
    WorkspaceUpdateStatus.sourceUnavailable => const AppNotification.message(
      severity: AppNotificationSeverity.warning,
      message: AppNotificationMessage.updateCheckUnavailable,
    ),
    WorkspaceUpdateStatus.updateUnsupported => const AppNotification.message(
      severity: AppNotificationSeverity.info,
      message: AppNotificationMessage.updateCheckUnsupported,
    ),
    WorkspaceUpdateStatus.resolutionRequired => const AppNotification.message(
      severity: AppNotificationSeverity.warning,
      message: AppNotificationMessage.updateCheckResolutionRequired,
    ),
  };

  Future<void> update(WorkspaceSkillId skillId) async {
    if (state.operation.running) return;
    state = state.copyWith(clearError: true);
    try {
      final task = ref
          .read(skillsWorkspaceRepositoryProvider)
          .update(skillIds: {skillId});
      final completion = await task.trackedCompletionBy(_operationTracker);
      if (!ref.mounted) return;
      switch (completion) {
        case WorkspaceCompleted():
          state = state.copyWith(clearError: true);
          _publishCompletion(AppNotificationMessage.skillUpdated);
          // A conflicting merge commits an Update Candidate Session through
          // the same success path, so the new state is derived from the
          // committed Snapshot instead of being assumed to be `current`.
          ref
              .read(skillUpdateStatusProvider.notifier)
              .deriveAfterUpdate(skillId);
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          _publishFinalizationPending(operationId, committedRevision);
        case WorkspaceFailed(:final failure):
          _publishOperationFailure(
            failure,
            StackTrace.current,
            operation: WorkspaceOperationKind.update,
          );
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      _publishOperationFailure(
        error,
        stackTrace,
        operation: WorkspaceOperationKind.update,
      );
    }
  }

  Future<void> abandonUpdateCandidate(WorkspaceSkillId skillId) async {
    if (state.operation.running) return;
    state = state.copyWith(clearError: true);
    try {
      final completion = await ref
          .read(skillsWorkspaceRepositoryProvider)
          .abandonUpdateCandidate(skillId)
          .trackedCompletionBy(_operationTracker);
      if (!ref.mounted) return;
      switch (completion) {
        case WorkspaceCompleted():
          state = state.copyWith(clearError: true);
          // Abandoning clears the Update Candidate, changing the Skill's
          // update basis; the shared store observes that Snapshot change.
          _publishCompletion(AppNotificationMessage.updateCandidateAbandoned);
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          _publishFinalizationPending(operationId, committedRevision);
        case WorkspaceFailed(:final failure):
          _publishOperationFailure(
            failure,
            StackTrace.current,
            operation: WorkspaceOperationKind.abandonUpdateCandidate,
          );
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      _publishOperationFailure(
        error,
        stackTrace,
        operation: WorkspaceOperationKind.abandonUpdateCandidate,
      );
    }
  }

  Future<ReplaceSourceOutcome?> replaceSource({
    required WorkspaceSkillId skillId,
    required SkillSourceInput source,
    required int expectedRevision,
  }) async {
    if (state.operation.running) return null;
    state = state.copyWith(clearError: true);
    try {
      final task = ref
          .read(skillsWorkspaceRepositoryProvider)
          .replaceSource(
            skillId: skillId,
            source: source,
            expectedRevision: expectedRevision,
          );
      final completion = await task.trackedCompletionBy(_operationTracker);
      if (!ref.mounted) return ReplaceSourceOutcome.replaced;
      switch (completion) {
        case WorkspaceCompleted():
          _publishCompletion(AppNotificationMessage.skillUpdated);
          return ReplaceSourceOutcome.replaced;
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          _publishFinalizationPending(operationId, committedRevision);
          return ReplaceSourceOutcome.pending;
        case WorkspaceFailed(:final failure):
          return _replaceFailure(failure);
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return null;
      final failure = ref
          .read(appFailureReporterProvider)
          .capture(
            error,
            stackTrace,
            operationKey: WorkspaceOperationKind.replaceSource.name,
          );
      state = state.copyWith(error: failure);
      if (failure.message == AppFailureMessage.staleSnapshot) {
        return ReplaceSourceOutcome.stale;
      }
      if (failure.message == AppFailureMessage.operationCancelled) {
        _notifications.info(AppNotificationMessage.operationCancelled);
        return ReplaceSourceOutcome.cancelled;
      }
      _notifications.publish(AppNotification.failure(failure));
      return null;
    }
  }

  Future<RemoveSkillOutcome> remove({
    required WorkspaceSkillId skillId,
    required int reviewedRevision,
  }) async {
    if (state.operation.running) {
      final failure = WorkspaceFailure(
        code: WorkspaceErrorCode.repositoryBusy,
        operation: WorkspaceOperationKind.remove,
      );
      _publishFailure(failure);
      return RemoveSkillOutcome.failed;
    }
    final reviewedSnapshot = ref.read(workspaceSnapshotProvider).value;
    final reviewedSkill = reviewedSnapshot?.revision == reviewedRevision
        ? reviewedSnapshot!.findSkillById(skillId)
        : null;
    if (reviewedSkill == null) return _refreshAfterStaleRemoval();

    final slotKey = reviewedSkill.slotKey;
    final cleanup = ref.read(appTranslationCacheCleanupProvider);
    final notifications = ref.read(appNotificationControllerProvider.notifier);
    final finalizationCoordinator = ref.read(
      workspaceFinalizationCoordinatorProvider.notifier,
    );
    final operationTracker = _operationTracker;
    try {
      final task = ref
          .read(skillsWorkspaceRepositoryProvider)
          .remove(skillIds: {skillId}, expectedRevision: reviewedRevision);
      final completion = await task.trackedCompletionBy(operationTracker);
      switch (completion) {
        case WorkspaceCompleted():
          final hadWarnings = operationTracker.state.warnings.isNotEmpty;
          final cleanupSucceeded = await cleanup.deleteSlot(slotKey);
          if (hadWarnings || !cleanupSucceeded) {
            notifications.warning(AppNotificationMessage.completedWithWarnings);
          } else {
            notifications.success(AppNotificationMessage.skillRemoved);
          }
          return RemoveSkillOutcome.removed;
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          finalizationCoordinator.register(
            WorkspaceCommittedPending<void>(
              operationId: operationId,
              committedRevision: committedRevision,
              warnings: operationTracker.state.warnings,
            ),
            afterRecovery: () => cleanup.deleteSlot(slotKey),
          );
          return RemoveSkillOutcome.pending;
        case WorkspaceFailed(:final failure):
          return await _removeFailure(failure);
      }
    } on Object catch (error, stackTrace) {
      final failure = ref
          .read(appFailureReporterProvider)
          .capture(
            error,
            stackTrace,
            operationKey: WorkspaceOperationKind.remove.name,
          );
      _addFailureWarnings(failure);
      if (failure.message == AppFailureMessage.operationCancelled) {
        if (ref.mounted) {
          _notifications.info(AppNotificationMessage.operationCancelled);
        }
        return RemoveSkillOutcome.cancelled;
      }
      if (failure.message == AppFailureMessage.staleSnapshot) {
        return _refreshAfterStaleRemoval();
      }
      if (ref.mounted) _publishFailure(failure);
      return RemoveSkillOutcome.failed;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  Future<T?> _readCompletion<T>(
    Future<WorkspaceCompletion<T>> pending,
    WorkspaceOperationKind operation,
  ) async {
    final completion = await pending;
    if (!ref.mounted) return null;
    switch (completion) {
      case WorkspaceCompleted(:final value):
        return value;
      case WorkspaceCommittedPending(
        :final operationId,
        :final committedRevision,
      ):
        _publishFinalizationPending(operationId, committedRevision);
        return null;
      case WorkspaceFailed(:final failure):
        final appFailure = ref
            .read(appFailureReporterProvider)
            .capture(failure, StackTrace.current, operationKey: operation.name);
        _addFailureWarnings(appFailure);
        state = state.copyWith(error: appFailure);
        // The detail page no longer renders an inline banner for this error,
        // so a toast is the only place it reaches the user.
        _publishFailure(appFailure);
        return null;
    }
  }

  SetActivationOutcome _activationFailure(WorkspaceFailure failure) {
    _publishOperationFailure(
      failure,
      StackTrace.current,
      operation: failure.operation,
    );
    return SetActivationOutcome.failed;
  }

  ReplaceSourceOutcome? _replaceFailure(WorkspaceFailure failure) {
    final appFailure = ref
        .read(appFailureReporterProvider)
        .capture(
          failure,
          StackTrace.current,
          operationKey: WorkspaceOperationKind.replaceSource.name,
        );
    state = state.copyWith(error: appFailure);
    if (appFailure.message == AppFailureMessage.staleSnapshot) {
      return ReplaceSourceOutcome.stale;
    }
    if (appFailure.message == AppFailureMessage.operationCancelled) {
      _notifications.info(AppNotificationMessage.operationCancelled);
      return ReplaceSourceOutcome.cancelled;
    }
    _notifications.publish(AppNotification.failure(appFailure));
    return null;
  }

  Future<RemoveSkillOutcome> _removeFailure(WorkspaceFailure failure) async {
    final appFailure = ref
        .read(appFailureReporterProvider)
        .capture(
          failure,
          StackTrace.current,
          operationKey: WorkspaceOperationKind.remove.name,
        );
    _addFailureWarnings(appFailure);
    if (appFailure.message == AppFailureMessage.operationCancelled) {
      if (ref.mounted) {
        _notifications.info(AppNotificationMessage.operationCancelled);
      }
      return RemoveSkillOutcome.cancelled;
    }
    if (appFailure.message == AppFailureMessage.staleSnapshot) {
      return _refreshAfterStaleRemoval();
    }
    if (ref.mounted) _publishFailure(appFailure);
    return RemoveSkillOutcome.failed;
  }

  Future<void> cancelOperation() => _operationTracker.cancel();

  AppNotificationController get _notifications =>
      ref.read(appNotificationControllerProvider.notifier);

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

  void _publishCompletion(AppNotificationMessage successMessage) {
    if (_operationTracker.state.warnings.isNotEmpty) {
      _notifications.warning(AppNotificationMessage.completedWithWarnings);
      return;
    }
    _notifications.success(successMessage);
  }

  void _publishOperationFailure(
    Object error,
    StackTrace stackTrace, {
    required WorkspaceOperationKind operation,
  }) {
    final failure = ref
        .read(appFailureReporterProvider)
        .capture(error, stackTrace, operationKey: operation.name);
    _addFailureWarnings(failure);
    if (failure.message == AppFailureMessage.operationCancelled) {
      _notifications.info(AppNotificationMessage.operationCancelled);
      return;
    }
    _publishFailure(failure);
  }

  void _publishFailure(AppFailure failure) {
    _notifications.publish(AppNotification.failure(failure));
  }

  void _addFailureWarnings(AppFailure failure) {
    _operationTracker.addWarnings(
      failure.warnings.whereType<WorkspaceWarning>(),
    );
  }

  Future<RemoveSkillOutcome> _refreshAfterStaleRemoval() async {
    try {
      final completion = await ref
          .read(skillsWorkspaceRepositoryProvider)
          .refresh();
      switch (completion) {
        case WorkspaceCompleted():
          return RemoveSkillOutcome.stale;
        case WorkspaceFailed(:final failure):
          final appFailure = ref
              .read(appFailureReporterProvider)
              .capture(
                failure,
                StackTrace.current,
                operationKey: WorkspaceOperationKind.refresh.name,
              );
          if (ref.mounted) _publishFailure(appFailure);
          return RemoveSkillOutcome.failed;
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          _publishFinalizationPending(operationId, committedRevision);
          return RemoveSkillOutcome.failed;
      }
    } on Object catch (error, stackTrace) {
      final failure = ref
          .read(appFailureReporterProvider)
          .capture(
            error,
            stackTrace,
            operationKey: WorkspaceOperationKind.refresh.name,
            message: AppFailureMessage.repositoryRefresh,
          );
      if (ref.mounted) _publishFailure(failure);
      return RemoveSkillOutcome.failed;
    }
  }
}
