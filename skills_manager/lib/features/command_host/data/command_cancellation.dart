import 'dart:async';

import 'package:skills_manager/features/skills/models/skills_workspace.dart';

/// One connection's cooperative cancellation, isolated from other callers.
final class CommandCancellation {
  CommandCancellation({this.onProgress});
  final void Function(WorkspaceOperationProgress)? onProgress;
  static final _key = Object();
  static CommandCancellation? get current =>
      Zone.current[_key] as CommandCancellation?;

  bool isCancelled = false;
  Future<void> Function()? _cancelTask;

  T run<T>(T Function() action) => runZoned(action, zoneValues: {_key: this});

  Future<void> cancel() async {
    if (isCancelled) return;
    isCancelled = true;
    await _cancelTask?.call();
  }

  Future<WorkspaceCompletion<T>> complete<T>(
    WorkspaceTask<T> task, {
    void Function(WorkspaceOperationProgress)? observe,
  }) async {
    void progress(WorkspaceOperationProgress value) {
      observe?.call(value);
      if (!isCancelled) onProgress?.call(value);
    }

    progress(task.current);
    final subscription = task.states.listen(progress);
    _cancelTask = task.cancel;
    try {
      if (isCancelled) await task.cancel();
      return await task.completed;
    } finally {
      _cancelTask = null;
      await subscription.cancel();
    }
  }
}
