import 'dart:async';

/// A cooperative cancellation signal for a Skill Workspace operation.
///
/// Cancellation is only advisory. An operation ignores a signal received after
/// its business commit point and reports its committed terminal state instead.
final class CancellationToken {
  CancellationToken._(this._cancelled);

  /// Creates a token that is never cancelled.
  factory CancellationToken.none() => CancellationToken._(Completer<void>());

  final Completer<void> _cancelled;

  /// Whether cancellation has already been requested.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes once cancellation is requested.
  Future<void> get whenCancelled => _cancelled.future;
}

/// Owns a [CancellationToken] and can request its cancellation exactly once.
final class CancellationSource {
  /// Creates a cancellation source with a fresh token.
  CancellationSource() : token = CancellationToken._(Completer<void>());

  /// The token passed to operations controlled by this source.
  final CancellationToken token;

  /// Requests cancellation.
  ///
  /// This operation is idempotent. Every call returns the same completed
  /// cancellation future.
  Future<void> cancel() {
    if (!token._cancelled.isCompleted) {
      token._cancelled.complete();
    }
    return token._cancelled.future;
  }
}
