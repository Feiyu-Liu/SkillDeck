import '../../domain/draft_snapshot.dart';
import '../../domain/revision_content.dart';
import '../ports/draft_snapshot_ports.dart';

final class DraftSnapshotCoordinator {
  DraftSnapshotCoordinator({
    required DraftSnapshotFilesystemPort filesystem,
    required DraftContentPort content,
    this.maximumCaptureAttempts = 3,
  }) : _filesystem = filesystem,
       _content = content {
    if (maximumCaptureAttempts <= 0) {
      throw ArgumentError.value(
        maximumCaptureAttempts,
        'maximumCaptureAttempts',
        'must be positive',
      );
    }
  }

  final DraftSnapshotFilesystemPort _filesystem;
  final DraftContentPort _content;
  final int maximumCaptureAttempts;

  /// Captures the one immutable input used by every later Publish phase.
  Future<DraftSnapshotResult<DraftPublishSnapshot>> captureForDirectPublish({
    required DraftCaptureRequest request,
    required String expectedDeclaredName,
  }) async {
    final stable = await _captureStable(request);
    final failure = stable.failureOrNull;
    if (failure != null) {
      return DraftSnapshotFailure<DraftPublishSnapshot>(
        code: failure.code,
        context: failure.context,
      );
    }
    final captured = stable.valueOrNull!;
    final declaredName = await _content.readDeclaredName(captured.tree);
    if (declaredName == null) {
      final cleanupFailure = await _discard<DraftPublishSnapshot>(
        captured.capture,
      );
      if (cleanupFailure != null) return cleanupFailure;
      return DraftSnapshotFailure<DraftPublishSnapshot>(
        code: DraftSnapshotFailureCode.invalidSkill,
        context: const <String, Object?>{'reason': 'missingSkillFrontmatter'},
      );
    }
    if (declaredName != expectedDeclaredName) {
      final cleanupFailure = await _discard<DraftPublishSnapshot>(
        captured.capture,
      );
      if (cleanupFailure != null) return cleanupFailure;
      return DraftSnapshotFailure<DraftPublishSnapshot>(
        code: DraftSnapshotFailureCode.declaredNameChangeNotAllowed,
      );
    }
    return DraftSnapshotSuccess<DraftPublishSnapshot>(
      DraftPublishSnapshot(
        capture: captured.capture,
        normalizedTree: captured.tree,
        declaredName: declaredName,
      ),
    );
  }

  /// Computes authoritative dirty state from a complete normalized comparison.
  Future<DraftSnapshotResult<bool>> inspectDirty({
    required DraftCaptureRequest request,
    required NormalizedSkillTree draftBase,
  }) async {
    final stable = await _captureStable(request);
    final failure = stable.failureOrNull;
    if (failure != null) {
      return DraftSnapshotFailure<bool>(
        code: failure.code,
        context: failure.context,
      );
    }
    final captured = stable.valueOrNull!;
    final isDirty = !_normalizedTreesEqual(captured.tree, draftBase);
    final cleanupFailure = await _discard<bool>(captured.capture);
    return cleanupFailure ?? DraftSnapshotSuccess<bool>(isDirty);
  }

  /// Captures the exact generation that a later post-commit cleanup may
  /// compare-and-delete.
  ///
  /// A dirty Draft is reported without exposing a cleanup fingerprint. A
  /// clean Draft returns the stable fingerprint from the same immutable scan
  /// used for the normalized comparison, so finalization never redefines the
  /// generation that was reviewed before candidate creation.
  Future<DraftSnapshotResult<DraftCleanupInspection>> inspectForCleanup({
    required DraftCaptureRequest request,
    required NormalizedSkillTree draftBase,
  }) async {
    final stable = await _captureStable(request);
    final failure = stable.failureOrNull;
    if (failure != null) {
      return DraftSnapshotFailure<DraftCleanupInspection>(
        code: failure.code,
        context: failure.context,
      );
    }
    final captured = stable.valueOrNull!;
    final isDirty = !_normalizedTreesEqual(captured.tree, draftBase);
    final fingerprint = isDirty ? null : captured.capture.fingerprint;
    final cleanupFailure = await _discard<DraftCleanupInspection>(
      captured.capture,
    );
    return cleanupFailure ??
        DraftSnapshotSuccess<DraftCleanupInspection>(
          DraftCleanupInspection(
            isDirty: isDirty,
            cleanupFingerprint: fingerprint,
          ),
        );
  }

  /// Freezes the post-commit Draft action for the operation journal.
  ///
  /// An unavailable or inconclusive revalidation always preserves user bytes.
  Future<PublishedDraftDisposition> decidePublishedDraftDisposition({
    required DraftPublishSnapshot snapshot,
    required DraftCaptureRequest request,
  }) async {
    final current = await _filesystem.fingerprint(request);
    final fingerprint = current.valueOrNull;
    if (fingerprint != null && fingerprint == snapshot.capture.fingerprint) {
      return PublishedDraftDisposition.deleteUnchanged;
    }
    return PublishedDraftDisposition.preserveAndReanchor;
  }

  Future<DraftSnapshotResult<void>> validateRestoreDeclaredName({
    required String expectedDeclaredName,
    required NormalizedSkillTree historicalTree,
  }) async {
    final declaredName = await _content.readDeclaredName(historicalTree);
    if (declaredName == null) {
      return DraftSnapshotFailure<void>(
        code: DraftSnapshotFailureCode.invalidSkill,
        context: const <String, Object?>{'reason': 'missingSkillFrontmatter'},
      );
    }
    if (declaredName != expectedDeclaredName) {
      return DraftSnapshotFailure<void>(
        code: DraftSnapshotFailureCode.historicalNameMismatch,
      );
    }
    return const DraftSnapshotSuccess<void>(null);
  }

  Future<DraftSnapshotResult<_StableDraftCapture>> _captureStable(
    DraftCaptureRequest request,
  ) async {
    for (var attempt = 1; attempt <= maximumCaptureAttempts; attempt += 1) {
      if (request.isCancelled?.call() ?? false) {
        return DraftSnapshotFailure<_StableDraftCapture>(
          code: DraftSnapshotFailureCode.operationCancelled,
        );
      }
      final captureResult = await _filesystem.capture(request);
      final captureFailure = captureResult.failureOrNull;
      if (captureFailure != null) {
        if (captureFailure.code ==
                DraftSnapshotFailureCode.draftChangedDuringPublish &&
            attempt < maximumCaptureAttempts) {
          continue;
        }
        return DraftSnapshotFailure<_StableDraftCapture>(
          code: captureFailure.code,
          context: captureFailure.context,
        );
      }

      final capture = captureResult.valueOrNull!;
      final normalized = await _content.normalize(
        capture.files,
        isCancelled: request.isCancelled,
      );
      final normalizationFailure = normalized.failureOrNull;
      if (normalizationFailure != null) {
        final cleanupFailure = await _discard<_StableDraftCapture>(capture);
        if (cleanupFailure != null) return cleanupFailure;
        return DraftSnapshotFailure<_StableDraftCapture>(
          code: normalizationFailure.code,
          context: normalizationFailure.context,
        );
      }

      final current = await _filesystem.fingerprint(request);
      final stable = current.valueOrNull == capture.fingerprint;
      if (stable) {
        return DraftSnapshotSuccess<_StableDraftCapture>(
          _StableDraftCapture(capture: capture, tree: normalized.valueOrNull!),
        );
      }
      final cleanupFailure = await _discard<_StableDraftCapture>(capture);
      if (cleanupFailure != null) return cleanupFailure;
      if (attempt == maximumCaptureAttempts) {
        break;
      }
    }
    return DraftSnapshotFailure<_StableDraftCapture>(
      code: DraftSnapshotFailureCode.draftChangedDuringPublish,
    );
  }

  Future<DraftSnapshotFailure<T>?> _discard<T>(DraftCapture capture) async {
    try {
      await _filesystem.discardStaging(capture);
      return null;
    } catch (_) {
      return DraftSnapshotFailure<T>(
        code: DraftSnapshotFailureCode.ioFailure,
        context: const <String, Object?>{'reason': 'stagingCleanupFailed'},
      );
    }
  }
}

final class DraftCleanupInspection {
  const DraftCleanupInspection({
    required this.isDirty,
    required this.cleanupFingerprint,
  }) : assert(isDirty == (cleanupFingerprint == null));

  final bool isDirty;
  final DraftFingerprint? cleanupFingerprint;
}

final class _StableDraftCapture {
  const _StableDraftCapture({required this.capture, required this.tree});

  final DraftCapture capture;
  final NormalizedSkillTree tree;
}

bool _normalizedTreesEqual(
  NormalizedSkillTree left,
  NormalizedSkillTree right,
) {
  if (left.files.length != right.files.length ||
      left.byteSize != right.byteSize ||
      left.contentHash != right.contentHash) {
    return false;
  }
  for (var index = 0; index < left.files.length; index += 1) {
    if (left.files[index] != right.files[index]) {
      return false;
    }
  }
  return true;
}
