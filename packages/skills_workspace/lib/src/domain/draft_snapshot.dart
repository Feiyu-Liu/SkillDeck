import 'revision_content.dart';

enum DraftFilesystemEntryKind { file, directory, symbolicLink }

/// Stable physical identity captured without following the directory entry.
final class DraftPhysicalIdentity {
  const DraftPhysicalIdentity({required this.volumeId, required this.fileId});

  final String volumeId;
  final String fileId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DraftPhysicalIdentity &&
          volumeId == other.volumeId &&
          fileId == other.fileId;

  @override
  int get hashCode => Object.hash(volumeId, fileId);
}

/// Evidence for one live Draft entry at one complete scan boundary.
final class DraftEntryEvidence {
  DraftEntryEvidence({
    required this.relativePath,
    required this.kind,
    required this.entryIdentity,
    required this.resolvedIdentity,
    required this.modifiedAtMicrosecondsUtc,
    required this.byteSize,
    required this.contentHash,
    required this.isExecutable,
    this.symbolicLinkTarget,
  }) {
    if (relativePath.isEmpty && kind != DraftFilesystemEntryKind.directory) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'only the Draft root directory may use an empty path',
      );
    }
    if ((byteSize == null) != (contentHash == null)) {
      throw ArgumentError('File size and content hash must coexist.');
    }
    if (contentHash != null &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(contentHash!)) {
      throw ArgumentError.value(
        contentHash,
        'contentHash',
        'must be a lowercase SHA-256 digest',
      );
    }
  }

  final String relativePath;
  final DraftFilesystemEntryKind kind;
  final DraftPhysicalIdentity entryIdentity;
  final DraftPhysicalIdentity resolvedIdentity;
  final int modifiedAtMicrosecondsUtc;
  final int? byteSize;
  final String? contentHash;
  final bool isExecutable;
  final String? symbolicLinkTarget;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DraftEntryEvidence &&
          relativePath == other.relativePath &&
          kind == other.kind &&
          entryIdentity == other.entryIdentity &&
          resolvedIdentity == other.resolvedIdentity &&
          modifiedAtMicrosecondsUtc == other.modifiedAtMicrosecondsUtc &&
          byteSize == other.byteSize &&
          contentHash == other.contentHash &&
          isExecutable == other.isExecutable &&
          symbolicLinkTarget == other.symbolicLinkTarget;

  @override
  int get hashCode => Object.hash(
    relativePath,
    kind,
    entryIdentity,
    resolvedIdentity,
    modifiedAtMicrosecondsUtc,
    byteSize,
    contentHash,
    isExecutable,
    symbolicLinkTarget,
  );
}

/// Complete evidence used for authoritative live-Draft equality.
final class DraftFingerprint {
  DraftFingerprint(List<DraftEntryEvidence> entries)
    : entries = List<DraftEntryEvidence>.unmodifiable(entries) {
    for (var index = 1; index < this.entries.length; index += 1) {
      if (_evidenceOrder(this.entries[index - 1], this.entries[index]) >= 0) {
        throw ArgumentError.value(
          entries,
          'entries',
          'must be strictly ordered and contain no duplicate evidence keys',
        );
      }
    }
  }

  final List<DraftEntryEvidence> entries;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DraftFingerprint && _listsEqual(entries, other.entries);

  @override
  int get hashCode => Object.hashAll(entries);
}

/// Raw immutable file bytes captured from the live Draft.
final class CapturedDraftFile {
  CapturedDraftFile({
    required this.relativePath,
    required List<int> bytes,
    required this.isExecutable,
  }) : bytes = List<int>.unmodifiable(bytes) {
    if (relativePath.isEmpty) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'must not be empty',
      );
    }
  }

  final String relativePath;
  final List<int> bytes;
  final bool isExecutable;
}

/// One filesystem capture before normalization and stability revalidation.
final class DraftCapture {
  DraftCapture({
    required this.liveDraftPath,
    required this.stagingPath,
    required this.fingerprint,
    required List<CapturedDraftFile> files,
  }) : files = List<CapturedDraftFile>.unmodifiable(files);

  final String liveDraftPath;
  final String stagingPath;
  final DraftFingerprint fingerprint;
  final List<CapturedDraftFile> files;
}

/// The sole immutable content input permitted after Publish capture.
final class DraftPublishSnapshot {
  const DraftPublishSnapshot({
    required this.capture,
    required this.normalizedTree,
    required this.declaredName,
  });

  final DraftCapture capture;
  final NormalizedSkillTree normalizedTree;
  final String declaredName;
}

enum PublishedDraftDisposition { deleteUnchanged, preserveAndReanchor }

int _evidenceOrder(DraftEntryEvidence left, DraftEntryEvidence right) {
  final pathOrder = left.relativePath.compareTo(right.relativePath);
  if (pathOrder != 0) {
    return pathOrder;
  }
  return left.kind.index.compareTo(right.kind.index);
}

bool _listsEqual<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
