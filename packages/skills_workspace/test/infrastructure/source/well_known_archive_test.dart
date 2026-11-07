import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/infrastructure/source/source_result.dart';
import 'package:skills_workspace/src/infrastructure/source/well_known_archive.dart';
import 'package:test/test.dart';

void main() {
  group('supported containers', () {
    test('exports sorted Zip entries and executable intent', () {
      final executable = ArchiveFile.string('bin/run.sh', '#!/bin/sh\n')
        ..mode = 0x1ed;
      final bytes = ZipEncoder().encode(
        Archive()
          ..addFile(executable)
          ..addFile(_skillFile()),
      );

      final result = const WellKnownArchiveExtractor().extract(
        bytes,
        artifactUri: Uri.parse('https://example.com/download'),
        contentType: 'application/zip; charset=binary',
      );

      expect(result.valueOrNull, hasLength(2));
      final normalized = const SkillContentNormalizer().normalize(
        result.valueOrNull!,
      );
      expect(
        normalized.valueOrNull?.files.map((file) => file.relativePath),
        <String>['SKILL.md', 'bin/run.sh'],
      );
      expect(normalized.valueOrNull?.files.last.isExecutable, isTrue);
    });

    test('detects Zip by extension and magic bytes', () {
      final bytes = _zip(Archive()..addFile(_skillFile()));

      for (final input in <({Uri uri, String type})>[
        (uri: Uri.parse('https://example.com/skill.ZIP'), type: ''),
        (uri: Uri.parse('https://example.com/artifact'), type: ''),
      ]) {
        final result = const WellKnownArchiveExtractor().extract(
          bytes,
          artifactUri: input.uri,
          contentType: input.type,
        );
        expect(result.valueOrNull, hasLength(1));
      }
    });

    test('extracts plain Tar by type, extension, and ustar magic', () {
      final bytes = _tar(Archive()..addFile(_skillFile()));

      for (final input in <({Uri uri, String type})>[
        (
          uri: Uri.parse('https://example.com/artifact'),
          type: 'application/x-tar',
        ),
        (uri: Uri.parse('https://example.com/skill.tar'), type: ''),
        (uri: Uri.parse('https://example.com/artifact'), type: ''),
      ]) {
        final artifactBytes =
            input.type.isEmpty && !input.uri.path.toLowerCase().endsWith('.tar')
            ? _withUstarMagic(bytes)
            : bytes;
        final result = const WellKnownArchiveExtractor().extract(
          artifactBytes,
          artifactUri: input.uri,
          contentType: input.type,
        );
        expect(result.valueOrNull, hasLength(1));
      }
    });

    test('extracts gzip Tar by type, extension, and magic bytes', () {
      final bytes = gzip.encode(_tar(Archive()..addFile(_skillFile())));

      for (final input in <({Uri uri, String type})>[
        (
          uri: Uri.parse('https://example.com/artifact'),
          type: 'application/x-gzip',
        ),
        (uri: Uri.parse('https://example.com/skill.tgz'), type: ''),
        (uri: Uri.parse('https://example.com/artifact'), type: ''),
      ]) {
        final result = const WellKnownArchiveExtractor().extract(
          bytes,
          artifactUri: input.uri,
          contentType: input.type,
        );
        expect(result.valueOrNull, hasLength(1));
      }
    });
  });

  group('container validation', () {
    test('rejects unsupported and malformed archives distinctly', () {
      final unsupported = const WellKnownArchiveExtractor().extract(
        utf8.encode('not an archive'),
        artifactUri: Uri.parse('https://example.com/artifact'),
        contentType: 'application/octet-stream',
      );
      final malformed = const WellKnownArchiveExtractor().extract(
        const <int>[0x1f, 0x8b, 0x00, 0x00],
        artifactUri: Uri.parse('https://example.com/artifact.gz'),
        contentType: 'application/gzip',
      );

      expect(
        unsupported.failureOrNull?.context['reason'],
        'unsupportedArchiveFormat',
      );
      expect(malformed.failureOrNull?.context['reason'], 'archiveDecodeFailed');
    });

    test('bounds decompressed gzip container bytes before Tar decode', () {
      final oversized = Archive()
        ..addFile(ArchiveFile.bytes('SKILL.md', List<int>.filled(30000, 65)));
      final compressed = gzip.encode(_tar(oversized));
      final result =
          const WellKnownArchiveExtractor(
            maximumFileCount: 1,
            maximumByteSize: 1,
          ).extract(
            compressed,
            artifactUri: Uri.parse('https://example.com/skill.tar.gz'),
            contentType: 'application/gzip',
          );

      expect(
        result.failureOrNull?.code,
        SourceFailureCode.contentLimitExceeded,
      );
      expect(
        result.failureOrNull?.context['limit'],
        'archiveContainerByteSize',
      );
      expect(result.failureOrNull?.context['maximum'], 10241);
    });

    test('rejects case-insensitive duplicate archive paths', () {
      final result = _extractZip(
        Archive()
          ..addFile(_skillFile())
          ..addFile(ArchiveFile.string('skill.md', 'duplicate')),
      );

      expect(result.failureOrNull?.context['reason'], 'duplicateArchivePath');
    });

    test('dereferences TAR file and directory symbolic links', () {
      final executable = ArchiveFile.string('assets/run.sh', '#!/bin/sh\n')
        ..mode = 0x1ed;
      final result = _extractTar(
        Archive()
          ..addFile(_skillFile())
          ..addFile(executable)
          ..addFile(ArchiveFile.symlink('README.md', 'SKILL.md'))
          ..addFile(ArchiveFile.symlink('bin', 'assets')),
      );

      final files = _archiveFiles(result.valueOrNull!);
      expect(files.keys, [
        'README.md',
        'SKILL.md',
        'assets/run.sh',
        'bin/run.sh',
      ]);
      expect(files['bin/run.sh']!.isExecutable, isTrue);
    });

    test('dereferences ZIP file and directory symbolic links', () {
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'metadata.md',
            '---\nname: example\ndescription: Description\n---\n',
          ),
        )
        ..addFile(ArchiveFile.string('assets/icon.txt', 'icon'))
        ..addFile(_zipSymlink('SKILL.md', 'metadata.md'))
        ..addFile(_zipSymlink('docs', 'assets'));
      final result = const WellKnownArchiveExtractor().extract(
        _zipWithUnixMetadata(archive),
        artifactUri: Uri.parse('https://example.com/example.zip'),
        contentType: 'application/zip',
      );

      expect(result.failureOrNull?.context, isNull);
      expect(_archiveFiles(result.valueOrNull!).keys, [
        'SKILL.md',
        'assets/icon.txt',
        'docs/icon.txt',
        'metadata.md',
      ]);
    });

    test('rejects special Unix file modes', () {
      final specialFile = ArchiveFile.string('device', 'x')..mode = 0x2000;
      final special = _extractTar(
        Archive()
          ..addFile(_skillFile())
          ..addFile(specialFile),
      );

      expect(
        special.failureOrNull?.context['reason'],
        'archiveSpecialFilesUnsupported',
      );
    });

    for (final fixture in <({String name, Archive archive, String reason})>[
      (
        name: 'escaping',
        archive: Archive()
          ..addFile(_skillFile())
          ..addFile(ArchiveFile.symlink('alias', '../outside')),
        reason: 'symbolicLinkEscapesSource',
      ),
      (
        name: 'cyclic',
        archive: Archive()
          ..addFile(_skillFile())
          ..addFile(ArchiveFile.symlink('a', 'b'))
          ..addFile(ArchiveFile.symlink('b', 'a')),
        reason: 'symbolicLinkCycle',
      ),
      (
        name: 'unresolved',
        archive: Archive()
          ..addFile(_skillFile())
          ..addFile(ArchiveFile.symlink('alias', 'missing')),
        reason: 'symbolicLinkUnresolved',
      ),
    ]) {
      test('rejects ${fixture.name} archive symbolic links', () {
        final result = _extractTar(fixture.archive);

        expect(result.failureOrNull?.code, SourceFailureCode.archiveInvalid);
        expect(result.failureOrNull?.context['reason'], fixture.reason);
      });
    }

    test('rejects a portable collision introduced by an archive link', () {
      final result = _extractTar(
        Archive()
          ..addFile(_skillFile())
          ..addFile(ArchiveFile.string('assets/icon.txt', 'one'))
          ..addFile(ArchiveFile.string('ALIAS/icon.txt', 'two'))
          ..addFile(ArchiveFile.symlink('alias', 'assets')),
      );

      expect(result.failureOrNull?.code, SourceFailureCode.archiveInvalid);
      expect(result.failureOrNull?.context['reason'], 'portablePathCollision');
    });

    test('rejects a file that is also an ancestor directory', () {
      final result = _extractZip(
        Archive()
          ..addFile(_skillFile())
          ..addFile(ArchiveFile.string('assets', 'file'))
          ..addFile(ArchiveFile.string('assets/icon.txt', 'nested')),
      );

      expect(
        result.failureOrNull?.context['reason'],
        'archivePathTypeConflict',
      );
    });

    test('requires root SKILL.md after safe extraction', () {
      final result = _extractZip(
        Archive()..addFile(ArchiveFile.string('nested/SKILL.md', '# nested')),
      );

      expect(
        result.failureOrNull?.context['reason'],
        'archiveMissingRootSkillMarkdown',
      );
    });
  });

  group('portable paths and limits', () {
    for (final rawPath in <String>[
      '../SKILL.md',
      '/SKILL.md',
      r'C:\SKILL.md',
      r'nested\SKILL.md',
      './SKILL.md',
      'nested//SKILL.md',
      'SKILL.md\x00suffix',
      '${'a' * 256}/SKILL.md',
      '${'a' * 4097}.md',
    ]) {
      test('rejects unsafe archive path ${_label(rawPath)}', () {
        final actualPath = rawPath.contains(r'\x00')
            ? rawPath.replaceFirst(r'\x00', '\x00')
            : rawPath;
        final archive = Archive()
          ..addFile(ArchiveFile.string(actualPath, 'content'));
        final result = actualPath.contains(r'\')
            ? _extractTar(archive)
            : _extractZip(archive);

        expect(result.failureOrNull?.code, SourceFailureCode.archiveInvalid);
        expect(result.failureOrNull?.context['reason'], 'unsafeArchivePath');
      });
    }

    test('normalizes trailing directory separators safely', () {
      final archive = Archive()
        ..addFile(ArchiveFile.directory('assets/'))
        ..addFile(_skillFile());
      final result = _extractTar(archive);

      expect(result.valueOrNull, hasLength(1));
    });

    test('enforces file-count and aggregate byte-size limits', () {
      final archive = Archive()
        ..addFile(_skillFile('x'))
        ..addFile(ArchiveFile.string('extra.txt', 'yy'));
      final fileCount =
          WellKnownArchiveExtractor(
            maximumFileCount: 1,
            maximumByteSize: 100,
          ).extract(
            _zip(archive),
            artifactUri: Uri.parse('https://example.com/skill.zip'),
            contentType: 'application/zip',
          );
      final byteSize =
          WellKnownArchiveExtractor(
            maximumFileCount: 3,
            maximumByteSize: 2,
          ).extract(
            _zip(archive),
            artifactUri: Uri.parse('https://example.com/skill.zip'),
            contentType: 'application/zip',
          );

      expect(
        fileCount.failureOrNull?.code,
        SourceFailureCode.contentLimitExceeded,
      );
      expect(fileCount.failureOrNull?.context['limit'], 'fileCount');
      expect(fileCount.failureOrNull?.context['actual'], 2);
      expect(
        byteSize.failureOrNull?.code,
        SourceFailureCode.contentLimitExceeded,
      );
      expect(byteSize.failureOrNull?.context['limit'], 'byteSize');
      expect(byteSize.failureOrNull?.context['actual'], greaterThan(2));
    });
  });
}

ArchiveFile _skillFile([
  String body = '---\nname: example\ndescription: Description\n---\n',
]) => ArchiveFile.string('SKILL.md', body);

ArchiveFile _zipSymlink(String name, String target) =>
    ArchiveFile.string(name, target)..mode = 0xa1ff;

Map<String, SkillContentEntry> _archiveFiles(List<SkillContentEntry> entries) =>
    {for (final entry in entries) utf8.decode(entry.pathBytes): entry};

List<int> _zip(Archive archive) => ZipEncoder().encode(archive);

List<int> _zipWithUnixMetadata(Archive archive) {
  final bytes = List<int>.of(_zip(archive));
  for (var index = 0; index + 6 <= bytes.length; index += 1) {
    if (bytes[index] == 0x50 &&
        bytes[index + 1] == 0x4b &&
        bytes[index + 2] == 0x01 &&
        bytes[index + 3] == 0x02) {
      bytes[index + 5] = 3;
    }
  }
  return bytes;
}

List<int> _tar(Archive archive) => TarEncoder().encode(archive);

SourceResult<List<SkillContentEntry>> _extractZip(Archive archive) =>
    const WellKnownArchiveExtractor().extract(
      _zip(archive),
      artifactUri: Uri.parse('https://example.com/example.zip'),
      contentType: 'application/zip',
    );

SourceResult<List<SkillContentEntry>> _extractTar(Archive archive) =>
    const WellKnownArchiveExtractor().extract(
      _tar(archive),
      artifactUri: Uri.parse('https://example.com/example.tar'),
      contentType: 'application/x-tar',
    );

String _label(String value) =>
    value.replaceAll('\x00', r'<NUL>').replaceAll('\\', r'<backslash>');

List<int> _withUstarMagic(List<int> input) {
  final bytes = List<int>.of(input);
  bytes.setRange(257, 262, ascii.encode('ustar'));
  for (var index = 148; index < 156; index += 1) {
    bytes[index] = 32;
  }
  final checksum = bytes.take(512).fold<int>(0, (sum, byte) => sum + byte);
  final encoded = checksum.toRadixString(8).padLeft(6, '0');
  bytes.setRange(148, 154, ascii.encode(encoded));
  bytes[154] = 0;
  bytes[155] = 32;
  return bytes;
}
