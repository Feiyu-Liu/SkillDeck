import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/settings/data/workspace_validation_history_store.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';

final workspaceValidationHistoryStoreProvider =
    Provider<WorkspaceValidationHistoryStore>(
      (ref) => SharedPreferencesWorkspaceValidationHistoryStore(),
    );

final workspaceValidationViewModelProvider =
    NotifierProvider<WorkspaceValidationViewModel, WorkspaceValidationState>(
      WorkspaceValidationViewModel.new,
    );

const _unset = Object();

final class WorkspaceValidationState {
  const WorkspaceValidationState({
    this.running = false,
    this.completed = 0,
    this.total,
    this.last,
  });

  final bool running;
  final int completed;
  final int? total;

  /// The most recent finished validation, including ones from earlier
  /// sessions.
  final WorkspaceValidationRecord? last;

  WorkspaceValidationState copyWith({
    bool? running,
    int? completed,
    Object? total = _unset,
    Object? last = _unset,
  }) => WorkspaceValidationState(
    running: running ?? this.running,
    completed: completed ?? this.completed,
    total: identical(total, _unset) ? this.total : total as int?,
    last: identical(last, _unset)
        ? this.last
        : last as WorkspaceValidationRecord?,
  );
}

/// Runs Skills validation and remembers its latest result across launches.
///
/// It lives for the App session rather than the Settings page, so leaving
/// Settings while a validation runs neither loses its progress nor its result.
final class WorkspaceValidationViewModel
    extends Notifier<WorkspaceValidationState> {
  WorkspaceTask<WorkspaceValidationReport>? _task;
  StreamSubscription<WorkspaceOperationProgress>? _progress;

  @override
  WorkspaceValidationState build() {
    ref.onDispose(() => unawaited(_progress?.cancel()));
    unawaited(_loadLast());
    return const WorkspaceValidationState();
  }

  Future<void> _loadLast() async {
    final WorkspaceValidationRecord? last;
    try {
      last = await ref.read(workspaceValidationHistoryStoreProvider).readLast();
    } on Object {
      return;
    }
    // A validation that finished while the record was loading is newer.
    if (!ref.mounted || last == null || state.last != null) return;
    state = state.copyWith(last: last);
  }

  Future<void> validate() async {
    if (state.running) return;
    final task = ref
        .read(skillsWorkspaceRepositoryProvider)
        .validateWorkspace();
    _task = task;
    state = state.copyWith(
      running: true,
      completed: task.current.completed,
      total: task.current.total,
    );
    _progress = task.states.listen((progress) {
      if (!ref.mounted || !state.running) return;
      state = state.copyWith(
        completed: progress.completed,
        total: progress.total,
      );
    });
    final WorkspaceCompletion<WorkspaceValidationReport> completion;
    try {
      completion = await task.completed;
    } on Object {
      await _finish(null);
      return;
    }
    await _finish(switch (completion) {
      WorkspaceCompleted(:final value) => value,
      WorkspaceFailed() || WorkspaceCommittedPending() => null,
    }, cancelled: _isCancellation(completion));
  }

  Future<void> cancel() async => _task?.cancel();

  Future<void> _finish(
    WorkspaceValidationReport? report, {
    bool cancelled = false,
  }) async {
    // Only stops listening; nothing depends on the subscription's teardown.
    unawaited(_progress?.cancel());
    _progress = null;
    _task = null;
    if (!ref.mounted) return;
    // A cancelled validation says nothing about the Workspace, so the last
    // real result stays on screen.
    if (cancelled) {
      state = state.copyWith(running: false);
      return;
    }
    final record = WorkspaceValidationRecord(
      completedAt: DateTime.now().toUtc(),
      failed: report == null,
      checkedSkillCount: report?.checkedSkillCount ?? 0,
      repairedArtifactCount: report?.repairedArtifactCount ?? 0,
      driftedSkillCount: report?.driftedSkillIds.length ?? 0,
      failedSkillCount: report?.failedSkillIds.length ?? 0,
    );
    state = state.copyWith(running: false, last: record);
    try {
      await ref.read(workspaceValidationHistoryStoreProvider).writeLast(record);
    } on Object {
      // The result is still shown for this session; only its persistence
      // across launches is lost.
    }
  }
}

bool _isCancellation(WorkspaceCompletion<Object?> completion) =>
    completion is WorkspaceFailed<Object?> &&
    completion.failure.code == WorkspaceErrorCode.operationCancelled;
