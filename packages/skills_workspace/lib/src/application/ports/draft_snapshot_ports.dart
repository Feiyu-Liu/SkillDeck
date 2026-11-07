import '../../domain/draft_snapshot.dart';
import '../../domain/revision_content.dart';

const int defaultDraftSnapshotFileLimit = 1000;
const int defaultDraftSnapshotByteLimit = 50 * 1024 * 1024;

enum DraftSnapshotFailureCode {
  draftChangedDuringPublish,
  invalidSkill,
  skillContentLimitExceeded,
  operationCancelled,
  ioFailure,
  declaredNameChangeNotAllowed,
  historicalNameMismatch,
}

sealed class DraftSnapshotResult<T> {
  const DraftSnapshotResult();

  T? get valueOrNull;
  DraftSnapshotFailure<T>? get failureOrNull;
}

final class DraftSnapshotSuccess<T> extends DraftSnapshotResult<T> {
  const DraftSnapshotSuccess(this.value);

  final T value;

  @override
  T get valueOrNull => value;

  @override
  DraftSnapshotFailure<T>? get failureOrNull => null;
}

final class DraftSnapshotFailure<T> extends DraftSnapshotResult<T> {
  DraftSnapshotFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map<String, Object?>.unmodifiable(context);

  final DraftSnapshotFailureCode code;
  final Map<String, Object?> context;

  @override
  T? get valueOrNull => null;

  @override
  DraftSnapshotFailure<T> get failureOrNull => this;
}

final class DraftCaptureRequest {
  DraftCaptureRequest({
    required this.liveDraftPath,
    required this.stagingDestinationPath,
    this.capturePosixExecutableIntent = true,
    Map<String, bool> executableIntentOverrides = const <String, bool>{},
    this.maximumFileCount = defaultDraftSnapshotFileLimit,
    this.maximumByteSize = defaultDraftSnapshotByteLimit,
    this.isCancelled,
  }) : executableIntentOverrides = Map<String, bool>.unmodifiable(
         executableIntentOverrides,
       ) {
    if (maximumFileCount <= 0) {
      throw ArgumentError.value(
        maximumFileCount,
        'maximumFileCount',
        'must be positive',
      );
    }
    if (maximumByteSize <= 0) {
      throw ArgumentError.value(
        maximumByteSize,
        'maximumByteSize',
        'must be positive',
      );
    }
  }

  final String liveDraftPath;
  final String stagingDestinationPath;
  final bool capturePosixExecutableIntent;
  final Map<String, bool> executableIntentOverrides;
  final int maximumFileCount;
  final int maximumByteSize;
  final bool Function()? isCancelled;
}

abstract interface class DraftSnapshotFilesystemPort {
  Future<DraftSnapshotResult<DraftCapture>> capture(
    DraftCaptureRequest request,
  );

  Future<DraftSnapshotResult<DraftFingerprint>> fingerprint(
    DraftCaptureRequest request,
  );

  Future<void> discardStaging(DraftCapture capture);
}

abstract interface class DraftContentPort {
  Future<DraftSnapshotResult<NormalizedSkillTree>> normalize(
    List<CapturedDraftFile> files, {
    bool Function()? isCancelled,
  });

  Future<String?> readDeclaredName(NormalizedSkillTree tree);
}
