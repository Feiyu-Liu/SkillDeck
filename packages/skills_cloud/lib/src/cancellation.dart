import 'errors.dart';

/// A cooperative cancellation signal shared by one bounded operation.
final class CloudCancellation {
  final Set<void Function()> _listeners = {};
  bool _cancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _cancelled;

  /// Stops registered requests and listeners exactly once.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// Throws a sanitized cancellation failure after cancellation.
  void throwIfCancelled() {
    if (_cancelled) throw const CloudException(CloudErrorCode.cancelled);
  }

  /// Registers cleanup and returns a function that unregisters it.
  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}
