import 'dart:async';
import 'dart:math';

import 'package:skills_cloud/skills_cloud.dart';

enum CloudSchedulePhase { paused, scheduled, running, backoff }

final class CloudScheduleState {
  const CloudScheduleState(this.phase, {this.nextAttempt, this.error});
  final CloudSchedulePhase phase;
  final DateTime? nextAttempt;
  final CloudErrorCode? error;
}

typedef CloudSyncTimerFactory = Timer Function(Duration, void Function());

/// One opted-in process scheduler; it never overlaps Workspace runs.
final class AppCloudSyncScheduler {
  AppCloudSyncScheduler({
    required Future<void> Function() synchronize,
    required Future<void> Function() cancelAndDrain,
    DateTime Function()? clock,
    double Function()? random,
    CloudSyncTimerFactory? timer,
    void Function(CloudScheduleState)? onState,
  }) : _synchronize = synchronize,
       _cancelAndDrain = cancelAndDrain,
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure().nextDouble,
       _timerFactory = timer ?? Timer.new,
       _onState = onState;
  final Future<void> Function() _synchronize, _cancelAndDrain;
  final DateTime Function() _clock;
  final double Function() _random;
  final CloudSyncTimerFactory _timerFactory;
  final void Function(CloudScheduleState)? _onState;
  Timer? _timer;
  Future<void>? _running, _draining, _closeFuture;
  bool _enabled = false, _closed = false;
  int _generation = 0, _failures = 0;
  CloudScheduleState state = const CloudScheduleState(
    CloudSchedulePhase.paused,
  );
  bool get enabled => _enabled;
  void _publish(CloudScheduleState value) {
    state = value;
    try {
      _onState?.call(value);
    } catch (_) {
      /* Observers never own scheduler progress. */
    }
  }

  void start({bool immediate = true}) {
    if (_closed) throw const CloudException(CloudErrorCode.cancelled);
    if (_draining != null) {
      throw const CloudException(CloudErrorCode.operationInProgress);
    }
    if (_enabled) return;
    _enabled = true;
    if (immediate) {
      unawaited(runNow().catchError((Object _) {}));
    } else {
      _schedule(_regularDelay(), CloudSchedulePhase.scheduled);
    }
  }

  Duration _regularDelay() => Duration(
    microseconds:
        (const Duration(minutes: 30).inMicroseconds *
                (0.8 + 0.4 * _random().clamp(0, 1)))
            .round(),
  );
  void _schedule(
    Duration delay,
    CloudSchedulePhase phase, {
    CloudErrorCode? error,
  }) {
    if (!_enabled || _closed) return;
    _timer?.cancel();
    final generation = _generation;
    _publish(
      CloudScheduleState(phase, nextAttempt: _clock().add(delay), error: error),
    );
    _timer = _timerFactory(delay, () {
      if (generation != _generation || !_enabled) return;
      unawaited(runNow().catchError((Object _) {}));
    });
  }

  /// Foreground wakeups debounce and respect an existing failure backoff.
  void foreground() {
    if (!_enabled ||
        _closed ||
        _running != null ||
        state.phase == CloudSchedulePhase.backoff) {
      return;
    }
    _schedule(const Duration(seconds: 1), CloudSchedulePhase.scheduled);
  }

  Future<void> runNow() {
    if (_draining != null) {
      throw const CloudException(CloudErrorCode.operationInProgress);
    }
    if (_closed || !_enabled) {
      throw const CloudException(CloudErrorCode.cancelled);
    }
    final existing = _running;
    if (existing != null) return existing;
    _timer?.cancel();
    _timer = null;
    final generation = _generation;
    final completion = Completer<void>();
    _running = completion.future;
    _publish(const CloudScheduleState(CloudSchedulePhase.running));
    unawaited(() async {
      CloudErrorCode? error;
      try {
        await _synchronize();
        _failures = 0;
        completion.complete();
      } catch (failure) {
        error = failure is CloudException
            ? failure.code
            : CloudErrorCode.unavailable;
        _failures++;
        completion.completeError(CloudException(error));
      } finally {
        _running = null;
        if (generation == _generation && _enabled && !_closed) {
          if (error == null) {
            _schedule(_regularDelay(), CloudSchedulePhase.scheduled);
          } else {
            final minutes = min(360, 1 << min(_failures - 1, 9));
            _schedule(
              Duration(minutes: minutes),
              CloudSchedulePhase.backoff,
              error: error,
            );
          }
        }
      }
    }());
    return completion.future;
  }

  /// Cancels timers and drains the actual session before reporting pause.
  Future<void> pause() => _draining ??= _pause().whenComplete(() {
    _draining = null;
  });
  Future<void> _pause() async {
    _enabled = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    try {
      await _cancelAndDrain();
    } finally {
      try {
        await _running;
      } catch (_) {
        /* Durable intents remain pending. */
      }
      _publish(const CloudScheduleState(CloudSchedulePhase.paused));
    }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    await pause();
  }
}
