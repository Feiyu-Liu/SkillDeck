import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import 'content_result.dart';
import 'normalized_skill_tree.dart';

/// Captures ordinary directory content before source-agnostic normalization.
///
/// Safe contained symbolic links are dereferenced into regular file entries.
/// Broken, cyclic, escaping, and special-file entries fail the entire capture.
/// Exact Git metadata entries are either rejected or excluded according to
/// [gitMetadataDisposition].
final class FilesystemSkillTreeReader {
  const FilesystemSkillTreeReader({
    this.gitMetadataDisposition = GitMetadataDisposition.reject,
    this.capturePosixExecutableIntent = true,
    this.executableIntentOverrides = const <String, bool>{},
    this.normalizer = const SkillContentNormalizer(),
  });

  final GitMetadataDisposition gitMetadataDisposition;

  /// Whether executable intent is derived from stable POSIX execute bits.
  ///
  /// Windows Local and Adopted sources set this to false. A Windows Draft also
  /// supplies [executableIntentOverrides] for paths that existed in Draft Base.
  final bool capturePosixExecutableIntent;

  /// Base executable intent keyed by normalized POSIX relative path.
  final Map<String, bool> executableIntentOverrides;

  final SkillContentNormalizer normalizer;

  Future<SkillContentResult<NormalizedSkillTree>> read(
    String rootPath, {
    bool Function()? isCancelled,
  }) async {
    final cancelled = isCancelled ?? _neverCancelled;
    if (cancelled()) {
      return SkillContentFailure<NormalizedSkillTree>(
        code: SkillContentFailureCode.cancelled,
      );
    }
    final absoluteRoot = paths.normalize(paths.absolute(rootPath));
    try {
      final rootType = await FileSystemEntity.type(
        absoluteRoot,
        followLinks: true,
      );
      if (rootType != FileSystemEntityType.directory) {
        return _failure(
          SkillContentFailureCode.unavailable,
          'sourceRootNotDirectory',
          path: absoluteRoot,
        );
      }
      final canonicalRoot = paths.normalize(
        await Directory(absoluteRoot).resolveSymbolicLinks(),
      );
      final collector = _FilesystemCollector(
        maximumFileCount: normalizer.maximumFileCount,
        maximumByteSize: normalizer.maximumByteSize,
        canonicalRoot: canonicalRoot,
        isCancelled: cancelled,
        gitMetadataDisposition: gitMetadataDisposition,
        capturePosixExecutableIntent: capturePosixExecutableIntent,
        executableIntentOverrides: executableIntentOverrides,
      );
      final failure = await collector.collect(
        directoryPath: canonicalRoot,
        outputPrefix: '',
        activeCanonicalDirectories: <String>{canonicalRoot},
      );
      if (failure != null) {
        return failure;
      }
      return normalizer.normalize(collector.entries, isCancelled: cancelled);
    } on FileSystemException {
      return _failure(
        SkillContentFailureCode.unavailable,
        'filesystemReadFailed',
        path: absoluteRoot,
      );
    }
  }
}

final class _FilesystemCollector {
  _FilesystemCollector({
    required this.maximumFileCount,
    required this.maximumByteSize,
    required this.canonicalRoot,
    required this.isCancelled,
    required this.gitMetadataDisposition,
    required this.capturePosixExecutableIntent,
    required this.executableIntentOverrides,
  });

  final int maximumFileCount;
  final int maximumByteSize;
  var byteCount = 0;

  SkillContentFailure<NormalizedSkillTree> limitFailure(
    String limit,
    int actual,
  ) => SkillContentFailure(
    code: SkillContentFailureCode.limitExceeded,
    context: {
      'limit': limit,
      'actual': actual,
      'actualIsLowerBound': true,
      'maximumFileCount': maximumFileCount,
      'maximumByteSize': maximumByteSize,
    },
  );

  final String canonicalRoot;
  final bool Function() isCancelled;
  final GitMetadataDisposition gitMetadataDisposition;
  final bool capturePosixExecutableIntent;
  final Map<String, bool> executableIntentOverrides;
  final List<SkillContentEntry> entries = <SkillContentEntry>[];

  Future<SkillContentFailure<NormalizedSkillTree>?> collect({
    required String directoryPath,
    required String outputPrefix,
    required Set<String> activeCanonicalDirectories,
  }) async {
    if (isCancelled()) {
      return SkillContentFailure<NormalizedSkillTree>(
        code: SkillContentFailureCode.cancelled,
      );
    }
    final entities = await Directory(
      directoryPath,
    ).list(followLinks: false).toList();
    entities.sort(
      (left, right) =>
          paths.basename(left.path).compareTo(paths.basename(right.path)),
    );

    for (final entity in entities) {
      if (isCancelled()) {
        return SkillContentFailure<NormalizedSkillTree>(
          code: SkillContentFailureCode.cancelled,
        );
      }
      final name = paths.basename(entity.path);
      final outputPath = outputPrefix.isEmpty ? name : '$outputPrefix/$name';
      if (_portableSegmentKey(name) == '.GIT') {
        if (gitMetadataDisposition == GitMetadataDisposition.exclude) {
          continue;
        }
        return _failure(
          SkillContentFailureCode.invalidContent,
          'gitMetadataNotAllowed',
          path: outputPath,
        );
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      final failure = switch (type) {
        FileSystemEntityType.directory => _collectDirectory(
          entity.path,
          outputPath,
          activeCanonicalDirectories,
        ),
        FileSystemEntityType.file => _collectFile(entity.path, outputPath),
        FileSystemEntityType.link => _collectLink(
          entity.path,
          outputPath,
          activeCanonicalDirectories,
        ),
        FileSystemEntityType.notFound => Future.value(
          _failure(
            SkillContentFailureCode.unavailable,
            'entryDisappearedDuringCapture',
            path: outputPath,
          ),
        ),
        FileSystemEntityType.pipe ||
        FileSystemEntityType.unixDomainSock => Future.value(
          _failure(
            SkillContentFailureCode.invalidContent,
            'unsupportedFilesystemEntry',
            path: outputPath,
          ),
        ),
        _ => Future.value(
          _failure(
            SkillContentFailureCode.invalidContent,
            'unsupportedFilesystemEntry',
            path: outputPath,
          ),
        ),
      };
      final resolvedFailure = await failure;
      if (resolvedFailure != null) {
        return resolvedFailure;
      }
    }
    return null;
  }

  Future<SkillContentFailure<NormalizedSkillTree>?> _collectDirectory(
    String path,
    String outputPath,
    Set<String> activeCanonicalDirectories,
  ) async {
    final canonical = paths.normalize(
      await Directory(path).resolveSymbolicLinks(),
    );
    if (!_isContained(canonicalRoot, canonical)) {
      return _failure(
        SkillContentFailureCode.invalidContent,
        'directoryEscapesSkillRoot',
        path: outputPath,
      );
    }
    if (activeCanonicalDirectories.contains(canonical)) {
      return _failure(
        SkillContentFailureCode.invalidContent,
        'cyclicSymbolicLink',
        path: outputPath,
      );
    }
    return collect(
      directoryPath: canonical,
      outputPrefix: outputPath,
      activeCanonicalDirectories: <String>{
        ...activeCanonicalDirectories,
        canonical,
      },
    );
  }

  Future<SkillContentFailure<NormalizedSkillTree>?> _collectLink(
    String linkPath,
    String outputPath,
    Set<String> activeCanonicalDirectories,
  ) async {
    String canonicalTarget;
    try {
      canonicalTarget = paths.normalize(
        await Link(linkPath).resolveSymbolicLinks(),
      );
    } on FileSystemException {
      return _failure(
        SkillContentFailureCode.invalidContent,
        'brokenOrCyclicSymbolicLink',
        path: outputPath,
      );
    }
    if (!_isContained(canonicalRoot, canonicalTarget)) {
      return _failure(
        SkillContentFailureCode.invalidContent,
        'symbolicLinkEscapesSkillRoot',
        path: outputPath,
      );
    }
    final sourceRelativeTarget = paths.relative(
      canonicalTarget,
      from: canonicalRoot,
    );
    if (sourceRelativeTarget
        .split(paths.separator)
        .any((segment) => _portableSegmentKey(segment) == '.GIT')) {
      return _failure(
        SkillContentFailureCode.invalidContent,
        'gitMetadataNotAllowed',
        path: outputPath,
      );
    }
    final targetType = await FileSystemEntity.type(
      canonicalTarget,
      followLinks: true,
    );
    if (targetType == FileSystemEntityType.file) {
      return _collectFile(canonicalTarget, outputPath);
    }
    if (targetType == FileSystemEntityType.directory) {
      if (activeCanonicalDirectories.contains(canonicalTarget)) {
        return _failure(
          SkillContentFailureCode.invalidContent,
          'cyclicSymbolicLink',
          path: outputPath,
        );
      }
      return collect(
        directoryPath: canonicalTarget,
        outputPrefix: outputPath,
        activeCanonicalDirectories: <String>{
          ...activeCanonicalDirectories,
          canonicalTarget,
        },
      );
    }
    return _failure(
      SkillContentFailureCode.invalidContent,
      'unsupportedSymbolicLinkTarget',
      path: outputPath,
    );
  }

  Future<SkillContentFailure<NormalizedSkillTree>?> _collectFile(
    String physicalPath,
    String outputPath,
  ) async {
    // Early termination reports the observed prefix, not an exact tree total.
    if (entries.length >= maximumFileCount) {
      return limitFailure('fileCount', entries.length + 1);
    }
    final file = File(physicalPath);
    final before = await file.stat();
    if (before.type != FileSystemEntityType.file) {
      return _failure(
        SkillContentFailureCode.unavailable,
        'entryChangedDuringCapture',
        path: outputPath,
      );
    }
    if (before.size > maximumByteSize - byteCount) {
      return limitFailure('byteSize', byteCount + before.size);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (isCancelled()) {
        return SkillContentFailure(code: SkillContentFailureCode.cancelled);
      }
      byteCount += chunk.length;
      if (byteCount > maximumByteSize) {
        return limitFailure('byteSize', byteCount);
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (isCancelled()) {
      return SkillContentFailure<NormalizedSkillTree>(
        code: SkillContentFailureCode.cancelled,
      );
    }
    final normalizedLookupPath = outputPath
        .replaceAll('\\', '/')
        .split('/')
        .map(unicode.nfc)
        .join('/');
    final executable =
        executableIntentOverrides[normalizedLookupPath] ??
        (capturePosixExecutableIntent && before.mode & 0x49 != 0);
    entries.add(
      SkillContentEntry.file(
        path: outputPath,
        bytes: bytes,
        isExecutable: executable,
      ),
    );
    return null;
  }
}

SkillContentFailure<NormalizedSkillTree> _failure(
  SkillContentFailureCode code,
  String reason, {
  String? path,
}) => SkillContentFailure<NormalizedSkillTree>(
  code: code,
  context: <String, Object?>{
    'reason': reason,
    if (path != null) 'path': _bounded(path),
  },
);

bool _isContained(String root, String target) =>
    paths.equals(root, target) || paths.isWithin(root, target);

String _portableSegmentKey(String segment) =>
    unicode.nfkc(unicode.nfc(segment).toUpperCase());

String _bounded(String value) =>
    value.length <= 256 ? value : '${value.substring(0, 253)}...';

bool _neverCancelled() => false;
