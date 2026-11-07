import 'dart:async';

/// Stable private failure categories for source inspection and acquisition.
///
/// These values are mapped to the public error taxonomy by the application
/// layer. Infrastructure deliberately does not depend on public API result
/// types.
enum SourceFailureCode {
  cancelled,
  unavailable,
  rejected,
  invalidSource,
  notFound,
  httpFailure,
  digestMismatch,
  archiveInvalid,
  contentInvalid,
  contentLimitExceeded,
  ioFailure,
}

enum SourceWarningCode { sourceEntrySkipped }

final class SourceWarning {
  SourceWarning({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map<String, Object?>.unmodifiable(context);

  final SourceWarningCode code;
  final Map<String, Object?> context;
}

sealed class SourceResult<T> {
  const SourceResult();

  T? get valueOrNull;
  SourceFailure<T>? get failureOrNull;
  List<SourceWarning> get warnings;
}

final class SourceSuccess<T> extends SourceResult<T> {
  SourceSuccess({
    required this.value,
    List<SourceWarning> warnings = const <SourceWarning>[],
  }) : warnings = List<SourceWarning>.unmodifiable(warnings);

  final T value;

  @override
  final List<SourceWarning> warnings;

  @override
  T get valueOrNull => value;

  @override
  SourceFailure<T>? get failureOrNull => null;
}

final class SourceFailure<T> extends SourceResult<T> {
  SourceFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
    List<SourceWarning> warnings = const <SourceWarning>[],
  }) : context = Map<String, Object?>.unmodifiable(context),
       warnings = List<SourceWarning>.unmodifiable(warnings);

  final SourceFailureCode code;
  final Map<String, Object?> context;

  @override
  final List<SourceWarning> warnings;

  @override
  T? get valueOrNull => null;

  @override
  SourceFailure<T> get failureOrNull => this;
}

/// Cooperative cancellation used by private source adapters.
abstract interface class SourceCancellationSignal {
  bool get isCancelled;
  Future<void> get whenCancelled;
}

final class NoSourceCancellationSignal implements SourceCancellationSignal {
  const NoSourceCancellationSignal();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => _never;

  static final Future<void> _never = Completer<void>().future;
}

SourceFailure<TTarget> copySourceFailure<TSource, TTarget>(
  SourceFailure<TSource> failure,
) => SourceFailure<TTarget>(
  code: failure.code,
  context: failure.context,
  warnings: failure.warnings,
);
