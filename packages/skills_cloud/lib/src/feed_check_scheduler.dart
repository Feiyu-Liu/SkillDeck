import 'dart:async';
import 'dart:math';

/// The outcome of one check and an optional service-requested delay.
final class FeedCheckResult {
  const FeedCheckResult.success({this._retryAfter}) : _succeeded = true;

  /// A failure. A service-requested delay, such as `Retry-After` on a 429 or
  /// 503, replaces the jittered backoff for the next check.
  const FeedCheckResult.failure({this._retryAfter}) : _succeeded = false;

  final bool _succeeded;
  bool get succeeded => _succeeded;
  final Duration? _retryAfter;
  Duration? get retryAfter => _retryAfter;

  /// The combined result of two checks performed in the same scheduled run.
  FeedCheckResult followedBy(FeedCheckResult other) {
    final first = _retryAfter, second = other._retryAfter;
    final retryAfter = first != null && (second == null || first > second)
        ? first
        : second;
    return _succeeded && other._succeeded
        ? FeedCheckResult.success(retryAfter: retryAfter)
        : FeedCheckResult.failure(retryAfter: retryAfter);
  }
}

/// Schedules checks while started and coalesces triggers during a check.
///
/// [start] includes the initial check. The lifecycle methods request another
/// check while the scheduler is started. Periodic delays begin when a check
/// finishes.
final class FeedCheckScheduler {
  FeedCheckScheduler({
    required this._check,
    Duration Function()? elapsed,
    Timer Function(Duration, void Function())? createTimer,
    double Function()? random,
  }) : _elapsed = elapsed ?? _startClock(),
       _createTimer = createTimer ?? Timer.new,
       _random = random ?? Random().nextDouble;

  static const _interval = Duration(minutes: 2);
  static const _backoffBase = Duration(minutes: 4);
  static const _backoffCap = Duration(minutes: 30);

  final Future<FeedCheckResult> Function() _check;
  final Duration Function() _elapsed;
  final Timer Function(Duration, void Function()) _createTimer;
  final double Function() _random;

  Timer? _timer;
  bool _started = false;
  bool _checking = false;
  bool _followUp = false;
  Duration _backoff = _backoffBase;
  Duration _periodicNotBefore = Duration.zero;

  /// Enables polling and requests the first check immediately.
  void start() {
    if (_started) return;
    _started = true;
    _trigger();
  }

  /// Cancels future checks and lets any current check finish.
  void stop() {
    _started = false;
    _followUp = false;
    _timer?.cancel();
    _timer = null;
  }

  void onLaunch() => _trigger();
  void onForeground() => _trigger();
  void onReconnect() => _trigger();
  void onWake() => _trigger();

  void _trigger() {
    if (!_started) return;
    if (_checking) {
      _followUp = true;
      return;
    }

    _timer?.cancel();
    _timer = null;
    _checking = true;
    unawaited(_runCheck());
  }

  Future<void> _runCheck() async {
    FeedCheckResult result;
    try {
      result = await _check();
    } catch (_) {
      result = const FeedCheckResult.failure();
    }
    _checking = false;
    if (!_started) return;

    final delay = _nextDelay(result);
    if (_followUp) {
      _followUp = false;
      _trigger();
    } else {
      _timer = _createTimer(delay, _trigger);
    }
  }

  Duration _nextDelay(FeedCheckResult result) {
    final now = _elapsed();
    final retryAfter = result._retryAfter;
    if (retryAfter != null && now + retryAfter > _periodicNotBefore) {
      // Lifecycle triggers may run during this window. Polling still honors it.
      _periodicNotBefore = now + retryAfter;
    }

    var delay = _interval;
    if (result._succeeded) {
      _backoff = _backoffBase;
    } else {
      // Choose the upper half of the backoff window, including at the cap.
      delay = retryAfter ?? _backoff * (0.5 + _random() * 0.5);
      final doubled = _backoff * 2;
      _backoff = doubled > _backoffCap ? _backoffCap : doubled;
    }

    final remaining = _periodicNotBefore - now;
    return remaining > delay ? remaining : delay;
  }

  static Duration Function() _startClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
