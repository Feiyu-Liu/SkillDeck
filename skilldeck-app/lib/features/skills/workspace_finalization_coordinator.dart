import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

/// Process-lifetime coordinator for mutations committed before finalization.
///
/// It owns notification task handles and serializes explicit recovery commands.
/// The Runtime remains the sole owner of the shared Workspace repository; this
/// coordinator only borrows its public recovery operation.
final workspaceFinalizationCoordinatorProvider =
    NotifierProvider<
      WorkspaceFinalizationCoordinator,
      WorkspaceFinalizationState
    >(WorkspaceFinalizationCoordinator.new);

typedef WorkspaceAfterFinalization = Future<bool> Function();

final class WorkspaceFinalizationState {
  const WorkspaceFinalizationState({
    this.pendingOperationIds = const <String>{},
    this.failedOperationIds = const <String>{},
    this.warningsByOperationId = const <String, List<WorkspaceWarning>>{},
    this.activeOperationId,
  });

  final Set<String> pendingOperationIds;
  final Set<String> failedOperationIds;
  final Map<String, List<WorkspaceWarning>> warningsByOperationId;
  final String? activeOperationId;

  bool get isRecovering => activeOperationId != null;
  bool get canRetry => failedOperationIds.isNotEmpty;
}

/// Registers committed-pending outcomes and finishes their persistent task
/// notifications only when durable recovery has reached a terminal outcome.
final class WorkspaceFinalizationCoordinator
    extends Notifier<WorkspaceFinalizationState> {
  final Map<String, _PendingFinalization> _pending = {};
  final Set<String> _completedOperationIds = {};
  var _draining = false;
  var _disposed = false;

  @override
  WorkspaceFinalizationState build() {
    ref.onDispose(() => _disposed = true);
    return const WorkspaceFinalizationState();
  }

  /// Idempotently registers a committed mutation for finalization recovery.
  ///
  /// An operation ID is globally unique for the process, so repeated delivery
  /// of the same terminal outcome never creates a second task notification or
  /// recovery attempt.
  void register<T>(
    WorkspaceCommittedPending<T> pending, {
    WorkspaceAfterFinalization? afterRecovery,
  }) {
    final operationId = pending.operationId;
    if (_completedOperationIds.contains(operationId)) {
      return;
    }
    final existing = _pending[operationId];
    if (existing != null) {
      existing.attachAfterRecovery(afterRecovery);
      return;
    }

    _pending[operationId] = _PendingFinalization(
      operationId: operationId,
      committedRevision: pending.committedRevision,
      warnings: pending.warnings,
      notification: _startNotification(),
      afterRecovery: afterRecovery,
    );
    _publishState();
    unawaited(_drain());
  }

  /// Retries one or every finalization that previously reached a typed or
  /// unexpected recovery failure.
  ///
  /// Failed entries remain registered so a transient filesystem or lock error
  /// never turns committed work into an unobservable one-shot failure. A retry
  /// starts a fresh persistent task notification while preserving operation-ID
  /// de-duplication.
  void retryFailed([String? operationId]) {
    var changed = false;
    for (final entry in _pending.values) {
      if (!entry.failed ||
          (operationId != null && entry.operationId != operationId)) {
        continue;
      }
      entry
        ..failed = false
        ..notification = _startNotification();
      changed = true;
    }
    if (!changed) return;
    _publishState();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (!_disposed && _pending.isNotEmpty) {
        _PendingFinalization? entry;
        for (final candidate in _pending.values) {
          if (!candidate.failed) {
            entry = candidate;
            break;
          }
        }
        if (entry == null) break;
        _publishState(activeOperationId: entry.operationId);
        final recovered = await _recover(entry);
        if (_disposed) return;
        if (recovered) {
          _pending.remove(entry.operationId);
          _completedOperationIds.add(entry.operationId);
        } else {
          entry.failed = true;
        }
        _publishState();
      }
    } finally {
      _draining = false;
      if (!_disposed && _pending.values.any((entry) => !entry.failed)) {
        unawaited(_drain());
      }
    }
  }

  Future<bool> _recover(_PendingFinalization entry) async {
    try {
      final completion = await ref
          .read(skillsWorkspaceRepositoryProvider)
          .resumeFinalizationRecovery()
          .completed;
      if (_disposed) return false;
      entry.mergeWarnings(completion.warnings);
      switch (completion) {
        case WorkspaceCompleted(:final value)
            when value.revision >= entry.committedRevision:
          final cleanupSucceeded = await _runAfterRecovery(entry);
          if (_disposed) return false;
          _finish(
            entry,
            entry.warnings.isEmpty && cleanupSucceeded
                ? const AppNotification.message(
                    severity: AppNotificationSeverity.success,
                    message: AppNotificationMessage.finalizationRecovered,
                  )
                : const AppNotification.message(
                    severity: AppNotificationSeverity.warning,
                    message: AppNotificationMessage.completedWithWarnings,
                  ),
          );
          return true;
        case WorkspaceCompleted(:final value):
          _finish(
            entry,
            AppNotification.failure(
              WorkspaceFailure(
                code: WorkspaceErrorCode.finalizationRecoveryFailed,
                operation: WorkspaceOperationKind.resumeFinalizationRecovery,
                context: {
                  'operationId': entry.operationId,
                  'committedRevision': entry.committedRevision,
                  'observedRevision': value.revision,
                },
                warnings: entry.warnings,
              ),
            ),
          );
          return false;
        case WorkspaceFailed(:final failure):
          _finish(
            entry,
            AppNotification.failure(_withWarnings(failure, entry)),
          );
          return false;
        case WorkspaceCommittedPending():
          _finish(
            entry,
            AppNotification.failure(
              WorkspaceFailure(
                code: WorkspaceErrorCode.finalizationRecoveryFailed,
                operation: WorkspaceOperationKind.resumeFinalizationRecovery,
                context: {
                  'operationId': entry.operationId,
                  'committedRevision': entry.committedRevision,
                },
                warnings: entry.warnings,
              ),
            ),
          );
          return false;
      }
    } on Object catch (error, stackTrace) {
      if (_disposed) return false;
      final failure = error is AppFailure
          ? error
          : ref
                .read(appFailureReporterProvider)
                .capture(
                  error,
                  stackTrace,
                  operationKey:
                      WorkspaceOperationKind.resumeFinalizationRecovery.name,
                  operationId: entry.operationId,
                );
      _finish(
        entry,
        AppNotification.failure(
          failure is WorkspaceFailure ? _withWarnings(failure, entry) : failure,
        ),
      );
      return false;
    }
  }

  Future<bool> _runAfterRecovery(_PendingFinalization entry) async {
    final callback = entry.takeAfterRecovery();
    if (callback == null) return true;
    try {
      return await callback();
    } on Object catch (error, stackTrace) {
      ref
          .read(appFailureReporterProvider)
          .capture(
            error,
            stackTrace,
            operationKey: 'workspacePostFinalizationCleanup',
            message: AppFailureMessage.io,
            recoveryPolicy: AppRecoveryPolicy.none,
            operationId: entry.operationId,
          );
      return false;
    }
  }

  AppNotificationTaskHandle _startNotification() => ref
      .read(appNotificationControllerProvider.notifier)
      .startTask(
        const AppNotification.message(
          severity: AppNotificationSeverity.info,
          message: AppNotificationMessage.finalizationPending,
        ),
      );

  void _finish(_PendingFinalization entry, AppNotification notification) {
    entry.notification.finish(notification);
  }

  void _publishState({String? activeOperationId}) {
    if (_disposed || !ref.mounted) return;
    state = WorkspaceFinalizationState(
      pendingOperationIds: Set.unmodifiable(_pending.keys.toSet()),
      failedOperationIds: Set.unmodifiable({
        for (final entry in _pending.values)
          if (entry.failed) entry.operationId,
      }),
      warningsByOperationId: Map<String, List<WorkspaceWarning>>.unmodifiable(
        <String, List<WorkspaceWarning>>{
          for (final entry in _pending.values)
            entry.operationId: List<WorkspaceWarning>.unmodifiable(
              entry.warnings,
            ),
        },
      ),
      activeOperationId: activeOperationId,
    );
  }

  WorkspaceFailure _withWarnings(
    WorkspaceFailure failure,
    _PendingFinalization entry,
  ) {
    if (entry.warnings.isEmpty) return failure;
    return WorkspaceFailure(
      code: failure.code,
      operation: failure.operation,
      context: failure.context,
      diagnostic: failure.diagnostic,
      warnings: entry.warnings,
    );
  }
}

final class _PendingFinalization {
  _PendingFinalization({
    required this.operationId,
    required this.committedRevision,
    required Iterable<WorkspaceWarning> warnings,
    required this.notification,
    WorkspaceAfterFinalization? afterRecovery,
  }) : warnings = _mergeWarnings(const [], warnings),
       _afterRecovery = afterRecovery;

  final String operationId;
  final int committedRevision;
  List<WorkspaceWarning> warnings;
  AppNotificationTaskHandle notification;
  bool failed = false;
  WorkspaceAfterFinalization? _afterRecovery;
  bool _afterRecoveryConsumed = false;

  void mergeWarnings(Iterable<WorkspaceWarning> incoming) {
    warnings = _mergeWarnings(warnings, incoming);
  }

  void attachAfterRecovery(WorkspaceAfterFinalization? callback) {
    _afterRecovery ??= callback;
  }

  WorkspaceAfterFinalization? takeAfterRecovery() {
    if (_afterRecoveryConsumed) return null;
    _afterRecoveryConsumed = true;
    return _afterRecovery;
  }
}

List<WorkspaceWarning> _mergeWarnings(
  Iterable<WorkspaceWarning> existing,
  Iterable<WorkspaceWarning> incoming,
) {
  final merged = <Object, WorkspaceWarning>{
    for (final warning in existing) workspaceWarningKey(warning): warning,
  };
  for (final warning in incoming) {
    merged[workspaceWarningKey(warning)] = warning;
  }
  return List.unmodifiable(merged.values);
}
