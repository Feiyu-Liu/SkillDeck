import 'dart:async';

final class AppOperationState<P, W> {
  const AppOperationState({
    this.progress,
    this.warnings = const [],
    this.running = false,
  });

  final P? progress;
  final List<W> warnings;
  final bool running;
}

final class AppOperationTracker<P, W> {
  AppOperationTracker({
    required void Function(AppOperationState<P, W> state) onChanged,
    required Iterable<W> Function(P progress) warningsOf,
    required Object Function(W warning) warningKey,
  }) : _onChanged = onChanged,
       _warningsOf = warningsOf,
       _warningKey = warningKey;

  final void Function(AppOperationState<P, W> state) _onChanged;
  final Iterable<W> Function(P progress) _warningsOf;
  final Object Function(W warning) _warningKey;

  StreamSubscription<P>? _subscription;
  Future<void> Function()? _cancel;
  AppOperationState<P, W> _state = const AppOperationState();

  AppOperationState<P, W> get state => _state;

  Future<T> run<T>({
    required P current,
    required Stream<P> states,
    required Future<T> result,
    required Future<void> Function() cancel,
  }) async {
    final previousSubscription = _subscription;
    _subscription = null;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }
    _cancel = cancel;
    _setState(
      AppOperationState(
        progress: current,
        warnings: _mergeWarnings(const [], _warningsOf(current)),
        running: true,
      ),
    );
    _subscription = states.listen((progress) {
      _setState(
        AppOperationState(
          progress: progress,
          warnings: _mergeWarnings(_state.warnings, _warningsOf(progress)),
          running: true,
        ),
      );
    });
    try {
      return await result;
    } finally {
      _cancel = null;
      final subscription = _subscription;
      _subscription = null;
      _setState(
        AppOperationState(progress: _state.progress, warnings: _state.warnings),
      );
      if (subscription != null) unawaited(subscription.cancel());
    }
  }

  Future<C> runCompletion<C>({
    required P current,
    required Stream<P> states,
    required Future<C> completed,
    required Iterable<W> Function(C completion) warningsOfCompletion,
    required Future<void> Function() cancel,
  }) => run(
    current: current,
    states: states,
    result: completed.then((completion) {
      addWarnings(warningsOfCompletion(completion));
      return completion;
    }),
    cancel: cancel,
  );

  Future<void> cancel() async {
    final cancel = _cancel;
    if (cancel != null) await cancel();
  }

  void addWarnings(Iterable<W> warnings) {
    _setState(
      AppOperationState(
        progress: _state.progress,
        warnings: _mergeWarnings(_state.warnings, warnings),
        running: _state.running,
      ),
    );
  }

  void clear() => _setState(const AppOperationState());

  Future<void> dispose() async {
    _cancel = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  List<W> _mergeWarnings(Iterable<W> existing, Iterable<W> incoming) {
    final merged = <Object, W>{
      for (final warning in existing) _warningKey(warning): warning,
    };
    for (final warning in incoming) {
      merged[_warningKey(warning)] = warning;
    }
    return List<W>.unmodifiable(merged.values);
  }

  void _setState(AppOperationState<P, W> value) {
    _state = value;
    _onChanged(value);
  }
}
