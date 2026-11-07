import '../../domain/immutable.dart';

enum ActivationFailureCode {
  duplicateAgentId,
  agentNotFound,
  activationUnsupported,
  projectRootNotFound,
  activationUnavailable,
  externalConflict,
  skillNotFound,
  operationCancelled,
}

enum ActivationWarningCode {
  noActivationTarget,
  projectSymbolicLinkPortability,
  duplicateExposure,
  activationTargetSkipped,
  sharedActivationLocation,
}

final class ActivationWarning {
  ActivationWarning({
    required this.code,
    Map<String, Object?> context = const {},
  }) : context = Map.unmodifiable(context);

  final ActivationWarningCode code;
  final Map<String, Object?> context;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivationWarning &&
          code == other.code &&
          mapsEqual(context, other.context);

  @override
  int get hashCode => Object.hash(code, unorderedMapHash(context));
}

sealed class ActivationResult<T> {
  const ActivationResult();

  T? get valueOrNull;
  ActivationFailure<T>? get failureOrNull;
  bool get isSuccess => this is ActivationSuccess<T>;
  bool get isFailure => this is ActivationFailure<T>;
}

final class ActivationSuccess<T> extends ActivationResult<T> {
  ActivationSuccess({
    required this.value,
    List<ActivationWarning> warnings = const [],
  }) : warnings = List.unmodifiable(warnings);

  final T value;
  final List<ActivationWarning> warnings;

  @override
  T get valueOrNull => value;

  @override
  ActivationFailure<T>? get failureOrNull => null;
}

final class ActivationFailure<T> extends ActivationResult<T> {
  ActivationFailure({
    required this.code,
    Map<String, Object?> context = const {},
    List<ActivationWarning> warnings = const [],
  }) : context = Map.unmodifiable(context),
       warnings = List.unmodifiable(warnings);

  final ActivationFailureCode code;
  final Map<String, Object?> context;
  final List<ActivationWarning> warnings;

  @override
  T? get valueOrNull => null;

  @override
  ActivationFailure<T> get failureOrNull => this;
}

ActivationFailure<T> copyActivationFailure<T>(
  ActivationFailure<Object?> failure, {
  List<ActivationWarning> additionalWarnings = const [],
}) => ActivationFailure<T>(
  code: failure.code,
  context: failure.context,
  warnings: <ActivationWarning>[...additionalWarnings, ...failure.warnings],
);
