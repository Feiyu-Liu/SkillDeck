import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../../domain/revision_content.dart';
import 'content_result.dart';

export '../../domain/revision_content.dart';

const int maximumNormalizedSkillFileCount = 1000;
const int maximumNormalizedSkillByteSize = 50 * 1024 * 1024;

const List<int> _hashDomain = <int>[
  0x73,
  0x6b,
  0x69,
  0x6c,
  0x6c,
  0x73,
  0x2d,
  0x77,
  0x6f,
  0x72,
  0x6b,
  0x73,
  0x70,
  0x61,
  0x63,
  0x65,
  0x2d,
  0x74,
  0x72,
  0x65,
  0x65,
  0x00,
  0x01,
];

/// Converts source-acquired entries into the one canonical Revision format.
final class SkillContentNormalizer {
  const SkillContentNormalizer({
    this.maximumFileCount = maximumNormalizedSkillFileCount,
    this.maximumByteSize = maximumNormalizedSkillByteSize,
  }) : assert(maximumFileCount > 0),
       assert(maximumByteSize > 0);

  final int maximumFileCount;
  final int maximumByteSize;

  SkillContentResult<NormalizedSkillTree> normalize(
    Iterable<SkillContentEntry> entries, {
    bool Function()? isCancelled,
  }) {
    final cancelled = isCancelled ?? _neverCancelled;
    final normalized = <_Candidate>[];
    var byteSize = 0;

    for (final entry in entries) {
      if (cancelled()) {
        return SkillContentFailure<NormalizedSkillTree>(
          code: SkillContentFailureCode.cancelled,
        );
      }
      if (normalized.length >= maximumFileCount) {
        return _limitFailure('fileCount', normalized.length + 1);
      }
      if (entry.kind != SkillContentEntryKind.file) {
        return _invalidFailure(
          entry.kind == SkillContentEntryKind.gitlink
              ? 'gitlinkNotAllowed'
              : 'unresolvedSymbolicLink',
          rawPath: _safeDecode(entry.pathBytes),
        );
      }

      final pathResult = _normalizePath(entry.pathBytes);
      if (pathResult.failure case final failure?) {
        return SkillContentFailure<NormalizedSkillTree>(
          code: SkillContentFailureCode.invalidContent,
          context: failure,
        );
      }
      final relativePath = pathResult.path!;
      if (entry.bytes.length > maximumByteSize - byteSize) {
        return _limitFailure('byteSize', byteSize + entry.bytes.length);
      }
      byteSize += entry.bytes.length;
      normalized.add(
        _Candidate(
          file: NormalizedSkillFile(
            relativePath: relativePath,
            bytes: entry.bytes,
            isExecutable: entry.isExecutable,
          ),
          collisionKey: _portableCollisionKey(relativePath),
        ),
      );
    }

    normalized.sort(
      (left, right) =>
          left.file.relativePath.compareTo(right.file.relativePath),
    );
    final collisionKeys = <String, String>{};
    final exactPaths = <String>{};
    for (final candidate in normalized) {
      final path = candidate.file.relativePath;
      if (!exactPaths.add(path)) {
        return _invalidFailure('duplicatePath', path: path);
      }
      final previous = collisionKeys[candidate.collisionKey];
      if (previous != null) {
        return _invalidFailure(
          'portablePathCollision',
          path: path,
          conflictingPath: previous,
        );
      }
      collisionKeys[candidate.collisionKey] = path;
    }
    for (final path in exactPaths) {
      var separator = path.indexOf('/');
      while (separator >= 0) {
        final prefix = path.substring(0, separator);
        if (exactPaths.contains(prefix)) {
          return _invalidFailure(
            'fileDirectoryCollision',
            path: path,
            conflictingPath: prefix,
          );
        }
        separator = path.indexOf('/', separator + 1);
      }
    }

    final files = normalized.map((candidate) => candidate.file).toList();
    return SkillContentSuccess<NormalizedSkillTree>(
      value: NormalizedSkillTree(
        files: files,
        contentHash: _hash(files),
        byteSize: byteSize,
      ),
    );
  }

  SkillContentFailure<NormalizedSkillTree> _limitFailure(
    String limit,
    int actual,
  ) => SkillContentFailure<NormalizedSkillTree>(
    code: SkillContentFailureCode.limitExceeded,
    context: <String, Object?>{
      'limit': limit,
      'actual': actual,
      'maximumFileCount': maximumFileCount,
      'maximumByteSize': maximumByteSize,
    },
  );
}

final class _Candidate {
  const _Candidate({required this.file, required this.collisionKey});

  final NormalizedSkillFile file;
  final String collisionKey;
}

final class _PathResult {
  const _PathResult.success(this.path) : failure = null;
  const _PathResult.failure(this.failure) : path = null;

  final String? path;
  final Map<String, Object?>? failure;
}

_PathResult _normalizePath(List<int> encodedPath) {
  String rawPath;
  try {
    rawPath = utf8.decode(encodedPath, allowMalformed: false);
  } on FormatException {
    return const _PathResult.failure(<String, Object?>{
      'reason': 'pathNotUtf8',
    });
  }
  if (!_hasWellFormedUtf16(rawPath)) {
    return _PathResult.failure(<String, Object?>{
      'reason': 'pathNotUnicodeScalarSequence',
      'path': _bounded(rawPath),
    });
  }
  if (rawPath.isEmpty) {
    return const _PathResult.failure(<String, Object?>{'reason': 'emptyPath'});
  }
  if (rawPath.startsWith('/') ||
      rawPath.startsWith(r'\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(rawPath)) {
    return _PathResult.failure(<String, Object?>{
      'reason': 'absolutePath',
      'path': _bounded(rawPath),
    });
  }

  final converted = rawPath.replaceAll(r'\', '/');
  final rawSegments = converted.split('/');
  if (rawSegments.any((segment) => segment.isEmpty)) {
    return _PathResult.failure(<String, Object?>{
      'reason': 'emptyPathSegment',
      'path': _bounded(rawPath),
    });
  }

  final normalizedSegments = <String>[];
  for (final rawSegment in rawSegments) {
    if (rawSegment == '.' || rawSegment == '..') {
      return _PathResult.failure(<String, Object?>{
        'reason': 'pathTraversal',
        'path': _bounded(rawPath),
      });
    }
    final segment = unicode.nfc(rawSegment);
    final invalidReason = _invalidSegmentReason(segment);
    if (invalidReason != null) {
      return _PathResult.failure(<String, Object?>{
        'reason': invalidReason,
        'path': _bounded(rawPath),
        'segment': _bounded(segment),
      });
    }
    normalizedSegments.add(segment);
  }
  return _PathResult.success(normalizedSegments.join('/'));
}

String? _invalidSegmentReason(String segment) {
  if (segment.endsWith(' ') || segment.endsWith('.')) {
    return 'windowsTrailingDotOrSpace';
  }
  for (final rune in segment.runes) {
    if (rune == 0 ||
        rune < 0x20 ||
        '<>:"|?*'.contains(String.fromCharCode(rune))) {
      return 'windowsInvalidCharacter';
    }
  }
  final key = _portableCollisionKey(segment);
  if (key == '.GIT') {
    return 'gitMetadataNotAllowed';
  }
  final basename = key.split('.').first;
  if (_windowsReservedBasenames.contains(basename)) {
    return 'windowsReservedName';
  }
  return null;
}

const Set<String> _windowsReservedBasenames = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'COM¹',
  'COM²',
  'COM³',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
  'LPT¹',
  'LPT²',
  'LPT³',
};

String _portableCollisionKey(String path) =>
    unicode.nfkc(unicode.nfc(path).toUpperCase());

String _hash(List<NormalizedSkillFile> files) {
  final digestSink = _SingleDigestSink();
  final input = sha256.startChunkedConversion(digestSink);
  input.add(_hashDomain);
  _addUint64(input, files.length);
  for (final file in files) {
    _addFrame(input, utf8.encode(file.relativePath));
    input.add(<int>[file.isExecutable ? 1 : 0]);
    _addFrame(input, file.bytes);
  }
  input.close();
  return digestSink.value.toString();
}

void _addFrame(ByteConversionSink sink, List<int> bytes) {
  _addUint64(sink, bytes.length);
  sink.add(bytes);
}

void _addUint64(ByteConversionSink sink, int value) {
  final frame = ByteData(8)..setUint64(0, value, Endian.big);
  sink.add(frame.buffer.asUint8List());
}

final class _SingleDigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value => _digest ?? (throw StateError('Digest was not produced.'));

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}

SkillContentFailure<NormalizedSkillTree> _invalidFailure(
  String reason, {
  String? path,
  String? rawPath,
  String? conflictingPath,
}) => SkillContentFailure<NormalizedSkillTree>(
  code: SkillContentFailureCode.invalidContent,
  context: <String, Object?>{
    'reason': reason,
    if (path != null) 'path': _bounded(path),
    if (rawPath != null) 'path': _bounded(rawPath),
    if (conflictingPath != null) 'conflictingPath': _bounded(conflictingPath),
  },
);

String? _safeDecode(List<int> bytes) {
  try {
    return _bounded(utf8.decode(bytes, allowMalformed: false));
  } on FormatException {
    return null;
  }
}

String _bounded(String value) =>
    value.length <= 256 ? value : '${value.substring(0, 253)}...';

bool _hasWellFormedUtf16(String value) {
  for (var index = 0; index < value.length; index += 1) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= value.length) {
        return false;
      }
      final next = value.codeUnitAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) {
        return false;
      }
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

bool _neverCancelled() => false;
