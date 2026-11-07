import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as paths;

import '../content/normalized_skill_tree.dart';
import 'source_result.dart';
import 'source_tree_symlink_resolver.dart';

/// Decodes a remote archive into untrusted entries for the shared normalizer.
final class WellKnownArchiveExtractor {
  const WellKnownArchiveExtractor({
    this.maximumFileCount = maximumNormalizedSkillFileCount,
    this.maximumByteSize = maximumNormalizedSkillByteSize,
  }) : assert(maximumFileCount > 0),
       assert(maximumByteSize > 0);

  final int maximumFileCount;
  final int maximumByteSize;

  SourceResult<List<SkillContentEntry>> extract(
    List<int> bytes, {
    required Uri artifactUri,
    required String contentType,
  }) {
    Archive archive;
    try {
      if (_isZip(bytes, artifactUri, contentType)) {
        archive = ZipDecoder().decodeBytes(bytes, verify: true);
      } else if (_isGzippedTar(bytes, artifactUri, contentType)) {
        final maximumTarSize = maximumByteSize + maximumFileCount * 8192 + 2048;
        archive = TarDecoder().decodeBytes(
          _decodeGzipBounded(bytes, maximumTarSize),
          verify: true,
        );
      } else if (_isTar(bytes, artifactUri, contentType)) {
        archive = TarDecoder().decodeBytes(bytes, verify: true);
      } else {
        return _archiveFailure('unsupportedArchiveFormat');
      }
    } on _ArchiveLimitException catch (error) {
      return SourceFailure<List<SkillContentEntry>>(
        code: SourceFailureCode.contentLimitExceeded,
        context: <String, Object?>{
          'limit': 'archiveContainerByteSize',
          'actual': error.actual,
          'maximum': error.maximum,
        },
      );
    } on Object {
      return _archiveFailure('archiveDecodeFailed');
    }

    final sourceEntries = <SourceTreeEntry>[];
    final seen = <String>{};
    var regularFileCount = 0;
    var totalBytes = 0;
    for (final entry in archive) {
      final relativePath = _safeArchivePath(entry.name);
      if (relativePath == null) {
        return _archiveFailure('unsafeArchivePath');
      }
      final identity = relativePath.toUpperCase();
      if (!seen.add(identity)) {
        return _archiveFailure('duplicateArchivePath');
      }
      if (entry.isSymbolicLink) {
        sourceEntries.add(
          SourceTreeEntry.symbolicLink(
            path: relativePath,
            targetBytes: utf8.encode(entry.symbolicLink!),
          ),
        );
        continue;
      }
      if (_isSpecialEntry(entry)) {
        return _archiveFailure('archiveSpecialFilesUnsupported');
      }
      if (entry.isDirectory) {
        sourceEntries.add(SourceTreeEntry.directory(path: relativePath));
        continue;
      }
      if (!entry.isFile) {
        return _archiveFailure('archiveSpecialFilesUnsupported');
      }
      if (regularFileCount >= maximumFileCount) {
        return _limitFailure('fileCount', regularFileCount + 1);
      }
      if (entry.size > maximumByteSize - totalBytes) {
        return _limitFailure('byteSize', totalBytes + entry.size);
      }

      Uint8List content;
      try {
        content = entry.content;
      } on Object {
        return _archiveFailure('archiveEntryDecodeFailed');
      }
      if (content.length > maximumByteSize - totalBytes) {
        return _limitFailure('byteSize', totalBytes + content.length);
      }
      totalBytes += content.length;
      regularFileCount += 1;
      sourceEntries.add(
        SourceTreeEntry.file(
          path: relativePath,
          bytes: content,
          isExecutable: entry.mode & 0x49 != 0,
        ),
      );
    }

    final resolved = SourceTreeSymlinkResolver(
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
    ).resolve(sourceEntries);
    final result = resolved.valueOrNull;
    if (result == null) {
      final failure = resolved.failureOrNull!;
      if (failure.code == SourceFailureCode.contentLimitExceeded) {
        return SourceFailure<List<SkillContentEntry>>(
          code: failure.code,
          context: failure.context,
        );
      }
      final reason = failure.context['reason'] == 'sourcePathTypeConflict'
          ? 'archivePathTypeConflict'
          : failure.context['reason'] as String? ?? 'archiveLinkInvalid';
      return SourceFailure<List<SkillContentEntry>>(
        code: SourceFailureCode.archiveInvalid,
        context: <String, Object?>{...failure.context, 'reason': reason},
      );
    }
    if (!result.any(
      (entry) => utf8.decode(entry.pathBytes).toUpperCase() == 'SKILL.MD',
    )) {
      return _archiveFailure('archiveMissingRootSkillMarkdown');
    }
    return SourceSuccess<List<SkillContentEntry>>(value: result);
  }

  SourceFailure<List<SkillContentEntry>> _limitFailure(
    String limit,
    int actual,
  ) => SourceFailure<List<SkillContentEntry>>(
    code: SourceFailureCode.contentLimitExceeded,
    context: <String, Object?>{
      'limit': limit,
      'actual': actual,
      'maximumFileCount': maximumFileCount,
      'maximumByteSize': maximumByteSize,
    },
  );
}

String? _safeArchivePath(String rawPath) {
  if (rawPath.isEmpty ||
      rawPath.startsWith('/') ||
      rawPath.startsWith(r'\') ||
      rawPath.contains(r'\') ||
      rawPath.contains('\x00') ||
      utf8.encode(rawPath).length > 4096) {
    return null;
  }
  final segments = rawPath.split('/');
  while (segments.isNotEmpty && segments.last.isEmpty) {
    segments.removeLast();
  }
  if (segments.isEmpty ||
      segments.any(
        (segment) =>
            segment.isEmpty ||
            utf8.encode(segment).length > 255 ||
            segment == '.' ||
            segment == '..',
      )) {
    return null;
  }
  final normalized = paths.posix.joinAll(segments);
  final windows = paths.Context(style: paths.Style.windows);
  if (paths.posix.isAbsolute(normalized) || windows.isAbsolute(normalized)) {
    return null;
  }
  return normalized;
}

bool _isZip(List<int> bytes, Uri uri, String contentType) {
  final lowerType = contentType.toLowerCase();
  return lowerType.contains('application/zip') ||
      uri.path.toLowerCase().endsWith('.zip') ||
      (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b);
}

bool _isGzippedTar(List<int> bytes, Uri uri, String contentType) {
  final lowerType = contentType.toLowerCase();
  final lowerPath = uri.path.toLowerCase();
  return lowerType.contains('application/gzip') ||
      lowerType.contains('application/x-gzip') ||
      lowerPath.endsWith('.tar.gz') ||
      lowerPath.endsWith('.tgz') ||
      (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b);
}

bool _isTar(List<int> bytes, Uri uri, String contentType) {
  final lowerType = contentType.toLowerCase();
  return lowerType.contains('application/x-tar') ||
      lowerType.contains('application/tar') ||
      uri.path.toLowerCase().endsWith('.tar') ||
      (bytes.length >= 262 &&
          utf8.decode(bytes.sublist(257, 262), allowMalformed: true) ==
              'ustar');
}

Uint8List _decodeGzipBounded(List<int> bytes, int maximumBytes) {
  final sink = _BoundedByteSink(maximumBytes);
  final decoder = gzip.decoder.startChunkedConversion(sink);
  decoder
    ..add(bytes)
    ..close();
  return sink.bytes;
}

bool _isSpecialEntry(ArchiveFile entry) {
  final type = entry.mode & 0xf000;
  return type != 0 && type != 0x4000 && type != 0x8000;
}

SourceFailure<List<SkillContentEntry>> _archiveFailure(String reason) =>
    SourceFailure<List<SkillContentEntry>>(
      code: SourceFailureCode.archiveInvalid,
      context: <String, Object?>{'reason': reason},
    );

final class _BoundedByteSink extends ByteConversionSinkBase {
  _BoundedByteSink(this.maximumBytes);

  final int maximumBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  var _length = 0;

  Uint8List get bytes => _builder.takeBytes();

  @override
  void add(List<int> chunk) {
    _length += chunk.length;
    if (_length > maximumBytes) {
      throw _ArchiveLimitException(actual: _length, maximum: maximumBytes);
    }
    _builder.add(chunk);
  }

  @override
  void close() {}
}

final class _ArchiveLimitException implements Exception {
  const _ArchiveLimitException({required this.actual, required this.maximum});

  final int actual;
  final int maximum;
}
