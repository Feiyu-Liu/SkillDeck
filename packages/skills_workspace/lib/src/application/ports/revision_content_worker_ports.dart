import '../../domain/revision_content.dart';

/// Stable private failure categories for worker-owned content preparation.
enum SkillContentFailureCode {
  invalidContent,
  limitExceeded,
  cancelled,
  unavailable,
}

sealed class SkillContentResult<T> {
  const SkillContentResult();

  T? get valueOrNull;
  SkillContentFailure<T>? get failureOrNull;
}

final class SkillContentSuccess<T> extends SkillContentResult<T> {
  const SkillContentSuccess({required this.value});

  final T value;

  @override
  T get valueOrNull => value;

  @override
  SkillContentFailure<T>? get failureOrNull => null;
}

final class SkillContentFailure<T> extends SkillContentResult<T> {
  SkillContentFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map<String, Object?>.unmodifiable(context);

  final SkillContentFailureCode code;
  final Map<String, Object?> context;

  @override
  T? get valueOrNull => null;

  @override
  SkillContentFailure<T> get failureOrNull => this;
}

/// CPU- and filesystem-intensive content work owned by the Revision worker.
///
/// Source adapters still acquire source-specific bytes. This port owns the
/// shared normalization, hashing, and complete ordinary-directory scan so the
/// caller isolate never becomes the content-processing execution context.
abstract interface class RevisionContentWorkerPort {
  Future<SkillContentResult<NormalizedSkillTree>> normalizeContent(
    List<SkillContentEntry> entries, {
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  });

  Future<SkillContentResult<NormalizedSkillTree>> readFilesystemTree(
    String rootPath, {
    required GitMetadataDisposition gitMetadataDisposition,
    required bool capturePosixExecutableIntent,
    required Map<String, bool> executableIntentOverrides,
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  });
}
