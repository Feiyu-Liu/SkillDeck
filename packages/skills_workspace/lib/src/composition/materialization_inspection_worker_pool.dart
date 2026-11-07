import 'dart:async';
import 'dart:collection';

import '../application/ports/revision_content_worker_ports.dart';
import '../application/ports/workspace_lifecycle_ports.dart';
import '../domain/revision_content.dart';
import '../native/revision_worker/revision_worker_runtime.dart';
import 'revision_worker_task_executor.dart';

final class MaterializationInspectionWorkerPool
    implements RevisionContentWorkerPort, WorkspaceRevisionWorkerLifecyclePort {
  MaterializationInspectionWorkerPool({int size = 4})
    : assert(size > 0),
      _workers = List<RevisionWorkerRuntime>.generate(
        size,
        (_) => RevisionWorkerRuntime(
          taskExecutor: executeComposedRevisionWorkerTask,
        ),
      );

  final List<RevisionWorkerRuntime> _workers;
  final Queue<int> _available = Queue<int>();
  final Queue<Completer<int>> _waiters = Queue<Completer<int>>();
  bool _started = false;
  bool _closed = false;

  @override
  Future<void> start() async {
    if (_started) return;
    if (_closed) throw StateError('Materialization worker pool is closed.');
    try {
      await Future.wait(<Future<void>>[
        for (final worker in _workers) worker.start(),
      ]);
      _available.addAll(Iterable<int>.generate(_workers.length));
      _started = true;
    } on Object {
      await Future.wait(<Future<void>>[
        for (final worker in _workers) worker.close(),
      ]);
      _closed = true;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final failure = StateError('Materialization worker pool is closed.');
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(failure);
    }
    await Future.wait(<Future<void>>[
      for (final worker in _workers) worker.close(),
    ]);
    _available.clear();
  }

  @override
  Future<SkillContentResult<NormalizedSkillTree>> normalizeContent(
    List<SkillContentEntry> entries, {
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) => _withWorker(
    (worker) => worker.normalizeContent(
      entries,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
      isCancelled: isCancelled,
    ),
  );

  @override
  Future<SkillContentResult<NormalizedSkillTree>> readFilesystemTree(
    String rootPath, {
    required GitMetadataDisposition gitMetadataDisposition,
    required bool capturePosixExecutableIntent,
    required Map<String, bool> executableIntentOverrides,
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) => _withWorker(
    (worker) => worker.readFilesystemTree(
      rootPath,
      gitMetadataDisposition: gitMetadataDisposition,
      capturePosixExecutableIntent: capturePosixExecutableIntent,
      executableIntentOverrides: executableIntentOverrides,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
      isCancelled: isCancelled,
    ),
  );

  Future<T> _withWorker<T>(
    Future<T> Function(RevisionWorkerRuntime worker) operation,
  ) async {
    final index = await _acquire();
    try {
      return await operation(_workers[index]);
    } finally {
      _release(index);
    }
  }

  Future<int> _acquire() {
    if (!_started || _closed) {
      return Future<int>.error(
        StateError('Materialization worker pool is unavailable.'),
      );
    }
    if (_available.isNotEmpty) {
      return Future<int>.value(_available.removeFirst());
    }
    final waiter = Completer<int>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release(int index) {
    if (_closed) return;
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(index);
    } else {
      _available.addLast(index);
    }
  }
}

final class WorkspaceRevisionWorkerLifecycleGroup
    implements WorkspaceRevisionWorkerLifecyclePort {
  WorkspaceRevisionWorkerLifecycleGroup(
    List<WorkspaceRevisionWorkerLifecyclePort> workers,
  ) : _workers = List.unmodifiable(workers);

  final List<WorkspaceRevisionWorkerLifecyclePort> _workers;
  final List<WorkspaceRevisionWorkerLifecyclePort> _started = [];
  bool _closed = false;

  @override
  Future<void> start() async {
    if (_closed) throw StateError('Revision worker group is closed.');
    if (_started.length == _workers.length) return;
    try {
      for (final worker in _workers) {
        await worker.start();
        _started.add(worker);
      }
    } on Object {
      await _closeStarted();
      _closed = true;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _closeStarted();
  }

  Future<void> _closeStarted() async {
    Object? firstFailure;
    StackTrace? firstStackTrace;
    for (final worker in _started.reversed) {
      try {
        await worker.close();
      } on Object catch (error, stackTrace) {
        firstFailure ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    _started.clear();
    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstStackTrace!);
    }
  }
}
