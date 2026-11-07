enum GitTransportFailureCode {
  rejected,
  unavailable,

  /// The host's developer command line tools are missing or still installing,
  /// so the Git executable cannot run yet. Distinct from [unavailable], which
  /// means the executable could not be started at all.
  developerToolsRequired,
  authenticationRequired,
  commandFailed,
  timedOut,
  cancelled,
  invalidOutput,
  ioFailure,
}

sealed class GitTransportResult<T> {
  const GitTransportResult();

  T? get valueOrNull;

  GitTransportFailure<T>? get failureOrNull;
}

final class GitTransportSuccess<T> extends GitTransportResult<T> {
  const GitTransportSuccess(this.value);

  final T value;

  @override
  T get valueOrNull => value;

  @override
  GitTransportFailure<T>? get failureOrNull => null;
}

final class GitTransportFailure<T> extends GitTransportResult<T> {
  GitTransportFailure({
    required this.code,
    Map<String, Object?> context = const {},
    this.diagnostic,
  }) : context = Map.unmodifiable(context);

  final GitTransportFailureCode code;
  final Map<String, Object?> context;
  final String? diagnostic;

  @override
  T? get valueOrNull => null;

  @override
  GitTransportFailure<T> get failureOrNull => this;
}
