/// Controls how one request waits for the cross-process Workspace Writer Lock.
final class LockWaitPolicy {
  const LockWaitPolicy.failFast()
    : waits = false,
      timeout = Duration.zero,
      pollInterval = Duration.zero;

  factory LockWaitPolicy.wait({
    Duration? timeout,
    Duration pollInterval = const Duration(milliseconds: 25),
  }) {
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (pollInterval <= Duration.zero) {
      throw ArgumentError.value(
        pollInterval,
        'pollInterval',
        'must be positive',
      );
    }
    return LockWaitPolicy._(
      waits: true,
      timeout: timeout,
      pollInterval: pollInterval,
    );
  }

  const LockWaitPolicy._({
    required this.waits,
    required this.timeout,
    required this.pollInterval,
  });

  final bool waits;
  final Duration? timeout;
  final Duration pollInterval;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LockWaitPolicy &&
          waits == other.waits &&
          timeout == other.timeout &&
          pollInterval == other.pollInterval;

  @override
  int get hashCode => Object.hash(waits, timeout, pollInterval);
}
