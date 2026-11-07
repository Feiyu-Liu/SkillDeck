import 'dart:convert';

/// The source-level kind of one entry before normalization.
enum SkillContentEntryKind { file, symbolicLink, gitlink }

/// Controls how an ordinary-directory capture handles external Git metadata.
///
/// Managed Workspace content uses [reject]. Filesystem-backed Sources use
/// [exclude] so a Git working tree can be snapshotted without importing its
/// repository identity, configuration, hooks, or history.
enum GitMetadataDisposition { reject, exclude }

/// Source-agnostic bytes passed from acquisition into worker normalization.
final class SkillContentEntry {
  SkillContentEntry({
    required List<int> pathBytes,
    required List<int> bytes,
    this.isExecutable = false,
    this.kind = SkillContentEntryKind.file,
  }) : pathBytes = List<int>.unmodifiable(pathBytes),
       bytes = List<int>.unmodifiable(bytes) {
    if (pathBytes.any((value) => value < 0 || value > 255)) {
      throw ArgumentError.value(pathBytes, 'pathBytes', 'must contain bytes');
    }
    if (bytes.any((value) => value < 0 || value > 255)) {
      throw ArgumentError.value(bytes, 'bytes', 'must contain bytes');
    }
  }

  factory SkillContentEntry.file({
    required String path,
    required List<int> bytes,
    bool isExecutable = false,
  }) => SkillContentEntry(
    pathBytes: utf8.encode(path),
    bytes: bytes,
    isExecutable: isExecutable,
  );

  final List<int> pathBytes;
  final List<int> bytes;
  final bool isExecutable;
  final SkillContentEntryKind kind;
}

/// One immutable regular file in a normalized Skill tree.
final class NormalizedSkillFile {
  NormalizedSkillFile({
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedSkillFile &&
          relativePath == other.relativePath &&
          isExecutable == other.isExecutable &&
          _bytesEqual(bytes, other.bytes);

  @override
  int get hashCode =>
      Object.hash(relativePath, isExecutable, Object.hashAll(bytes));
}

/// A deterministic, portable and immutable snapshot of Skill content.
///
/// Normalization and hashing are infrastructure concerns. This model contains
/// only the validated result consumed by application and revision operations.
final class NormalizedSkillTree {
  NormalizedSkillTree({
    required List<NormalizedSkillFile> files,
    required this.contentHash,
    required this.byteSize,
  }) : files = List<NormalizedSkillFile>.unmodifiable(files) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(contentHash)) {
      throw ArgumentError.value(
        contentHash,
        'contentHash',
        'must be a lowercase SHA-256 digest',
      );
    }
    if (byteSize < 0) {
      throw ArgumentError.value(byteSize, 'byteSize', 'must not be negative');
    }
  }

  final List<NormalizedSkillFile> files;
  final String contentHash;
  final int byteSize;

  int get fileCount => files.length;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
