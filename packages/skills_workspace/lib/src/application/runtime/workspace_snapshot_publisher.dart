import 'dart:async';

import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../ports/draft_change_hint_ports.dart';
import '../ports/workspace_lifecycle_ports.dart';

abstract interface class DraftHintDebounceHandle {
  void cancel();
}

typedef DraftHintDebounceScheduler =
    DraftHintDebounceHandle Function(
      Duration duration,
      void Function() callback,
    );

typedef DraftHintRefreshErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Owns the current immutable Snapshot and its application-facing stream.
final class WorkspaceSnapshotPublisher
    implements WorkspaceSnapshotLifecyclePort {
  WorkspaceSnapshotPublisher({
    required WorkspaceSnapshotReaderPort reader,
    DraftChangeHintPort? draftChangeHints,
    Duration draftHintDebounce = const Duration(milliseconds: 120),
    DraftHintDebounceScheduler debounceScheduler = _scheduleDebounce,
    DraftHintRefreshErrorHandler? onHintRefreshError,
  }) : _reader = reader,
       _draftChangeHints = draftChangeHints,
       _draftHintDebounce = draftHintDebounce,
       _debounceScheduler = debounceScheduler,
       _onHintRefreshError = onHintRefreshError {
    if (draftHintDebounce.isNegative) {
      throw ArgumentError.value(
        draftHintDebounce,
        'draftHintDebounce',
        'must not be negative',
      );
    }
  }

  final WorkspaceSnapshotReaderPort _reader;
  final DraftChangeHintPort? _draftChangeHints;
  final Duration _draftHintDebounce;
  final DraftHintDebounceScheduler _debounceScheduler;
  final DraftHintRefreshErrorHandler? _onHintRefreshError;
  final StreamController<RepositorySnapshot> _snapshots =
      StreamController<RepositorySnapshot>.broadcast();
  final Map<ManagedSkillId, _DraftWatch> _draftWatches = {};
  RepositorySnapshot? _current;
  Future<void> _reloadQueue = Future<void>.value();
  Future<void>? _hintRefresh;
  DraftHintDebounceHandle? _hintDebounceHandle;
  var _hintEpoch = 0;
  var _hintRefreshRunning = false;
  bool _closed = false;

  bool get hasSnapshot => _current != null && !_closed;

  RepositorySnapshot get current {
    final value = _current;
    if (value == null || _closed) {
      throw StateError('No open Workspace Snapshot is available.');
    }
    return value;
  }

  Stream<RepositorySnapshot> get snapshots => _snapshots.stream;

  @override
  Future<RepositorySnapshot> readInitial({
    required WorkspaceIntegrity integrity,
  }) {
    if (_closed) throw StateError('The Snapshot publisher is closed.');
    return _reader.read(integrity: integrity);
  }

  @override
  Future<void> publishInitial(RepositorySnapshot snapshot) async {
    if (_closed) throw StateError('The Snapshot publisher is closed.');
    if (_current != null) {
      throw StateError('The initial Snapshot has already been published.');
    }
    _publish(snapshot);
    await _synchronizeDraftWatches(snapshot);
  }

  /// Reloads committed state and publishes only an observable change.
  ///
  /// The injected Reader remains responsible for authoritative Draft scans.
  /// Explicit and hint-triggered reloads share one queue so their filesystem
  /// comparisons and publications never overlap or reorder.
  Future<RepositorySnapshot> reload({WorkspaceIntegrity? integrity}) {
    if (_closed || _current == null) {
      return Future<RepositorySnapshot>.error(
        StateError('The Workspace must be open before Snapshot reload.'),
      );
    }
    final completer = Completer<RepositorySnapshot>();
    final requestedIntegrity = integrity;
    _reloadQueue = _reloadQueue.then((_) async {
      if (_closed || _current == null) {
        completer.completeError(
          StateError('The Workspace must be open before Snapshot reload.'),
        );
        return;
      }
      try {
        final next = await _reader.read(
          integrity: requestedIntegrity ?? _current!.integrity,
        );
        if (_closed || _current == null) {
          throw StateError('The Snapshot publisher was closed during reload.');
        }
        await _synchronizeDraftWatches(next);
        if (next != _current) _publish(next);
        completer.complete(next);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Publishes derived integrity state without rereading committed SQLite or
  /// rescanning Drafts. Repository revision and business projections stay
  /// unchanged.
  void publishIntegrity(WorkspaceIntegrity integrity) {
    if (_closed || _current == null) {
      throw StateError('The Workspace must be open before integrity updates.');
    }
    final current = _current!;
    final next = RepositorySnapshot(
      revision: current.revision,
      managedSkills: current.managedSkills,
      projectRoots: current.projectRoots,
      personalTags: current.personalTags,
      integrity: integrity,
    );
    if (next != current) _publish(next);
  }

  void _publish(RepositorySnapshot snapshot) {
    _current = snapshot;
    _snapshots.add(snapshot);
  }

  Future<void> _synchronizeDraftWatches(RepositorySnapshot snapshot) async {
    final hints = _draftChangeHints;
    if (hints == null || _closed) return;
    final desired = <ManagedSkillId, String>{
      for (final skill in snapshot.managedSkills)
        if (skill.draft case final draft?) skill.id: draft.path,
    };
    final obsolete = <_DraftWatch>[];
    for (final entry in _draftWatches.entries.toList(growable: false)) {
      if (desired[entry.key] != entry.value.path) {
        _draftWatches.remove(entry.key);
        obsolete.add(entry.value);
      }
    }
    await Future.wait<void>([
      for (final watch in obsolete) _cancelDraftWatch(watch),
    ]);
    if (_closed) return;
    for (final entry in desired.entries) {
      if (_draftWatches.containsKey(entry.key)) continue;
      _startDraftWatch(hints, entry.key, entry.value);
    }
  }

  void _startDraftWatch(
    DraftChangeHintPort hints,
    ManagedSkillId managedSkillId,
    String draftPath,
  ) {
    final watch = _DraftWatch(path: draftPath);
    _draftWatches[managedSkillId] = watch;
    try {
      watch.subscription = hints
          .watchDraft(draftPath)
          .listen(
            (_) => _handleDraftHint(),
            onError: (Object error, StackTrace stackTrace) {
              _handleDraftWatchTermination(
                managedSkillId,
                watch,
                error: error,
                stackTrace: stackTrace,
              );
            },
            onDone: () => _handleDraftWatchTermination(managedSkillId, watch),
            cancelOnError: true,
          );
    } catch (error, stackTrace) {
      if (identical(_draftWatches[managedSkillId], watch)) {
        _draftWatches.remove(managedSkillId);
      }
      _reportHintRefreshError(error, stackTrace);
    }
  }

  void _handleDraftWatchTermination(
    ManagedSkillId managedSkillId,
    _DraftWatch watch, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!identical(_draftWatches[managedSkillId], watch)) return;
    _draftWatches.remove(managedSkillId);
    if (_closed) return;
    if (error != null) {
      _reportHintRefreshError(error, stackTrace ?? StackTrace.current);
    }
    // Termination can mean deletion or atomic replacement of the watched
    // directory. It is still only a hint; an authoritative reload decides.
    _handleDraftHint();
  }

  void _handleDraftHint() {
    if (_closed) return;
    _hintEpoch += 1;
    _scheduleHintRefresh();
  }

  void _scheduleHintRefresh() {
    if (_closed || _hintRefreshRunning) return;
    _hintDebounceHandle?.cancel();
    _hintDebounceHandle = _debounceScheduler(
      _draftHintDebounce,
      _beginHintRefresh,
    );
  }

  void _beginHintRefresh() {
    _hintDebounceHandle = null;
    if (_closed || _hintRefreshRunning || _current == null) return;
    _hintRefreshRunning = true;
    final refreshedEpoch = _hintEpoch;
    _hintRefresh = () async {
      try {
        await reload();
      } catch (error, stackTrace) {
        _reportHintRefreshError(error, stackTrace);
      } finally {
        _hintRefreshRunning = false;
        _hintRefresh = null;
        if (!_closed && _hintEpoch > refreshedEpoch) {
          _scheduleHintRefresh();
        }
      }
    }();
  }

  void _reportHintRefreshError(Object error, StackTrace stackTrace) {
    try {
      _onHintRefreshError?.call(error, stackTrace);
    } on Object {
      // Advisory error reporting must not escape into the async runtime.
    }
  }

  Future<void> _cancelDraftWatch(_DraftWatch watch) async {
    final subscription = watch.subscription;
    if (subscription == null) return;
    try {
      await subscription.cancel();
    } catch (error, stackTrace) {
      _reportHintRefreshError(error, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _hintDebounceHandle?.cancel();
    _hintDebounceHandle = null;
    final watches = _draftWatches.values.toList(growable: false);
    _draftWatches.clear();
    await Future.wait<void>([
      for (final watch in watches) _cancelDraftWatch(watch),
    ]);
    await _reloadQueue;
    await _hintRefresh;
    _current = null;
    await _snapshots.close();
  }
}

final class _DraftWatch {
  _DraftWatch({required this.path});

  final String path;
  StreamSubscription<DraftChangeHint>? subscription;
}

final class _TimerDraftHintDebounceHandle implements DraftHintDebounceHandle {
  const _TimerDraftHintDebounceHandle(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

DraftHintDebounceHandle _scheduleDebounce(
  Duration duration,
  void Function() callback,
) => _TimerDraftHintDebounceHandle(Timer(duration, callback));
