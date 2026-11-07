import 'dart:convert';

import 'source_result.dart';

const String wellKnownDiscoverySchemaV2 =
    'https://schemas.agentskills.io/discovery/0.2.0/schema.json';

enum WellKnownEntryVersion { v0_1, v0_2 }

enum WellKnownArtifactType { declaredFiles, skillMarkdown, archive }

final class WellKnownIndexEntry {
  WellKnownIndexEntry._({
    required this.version,
    required this.name,
    required this.description,
    required this.type,
    required List<String> files,
    this.artifactUri,
    this.digest,
  }) : files = List<String>.unmodifiable(files);

  final WellKnownEntryVersion version;
  final String name;
  final String description;
  final WellKnownArtifactType type;
  final List<String> files;
  final Uri? artifactUri;
  final String? digest;
}

final class WellKnownIndex {
  WellKnownIndex({
    required this.indexUri,
    required this.wellKnownPath,
    required List<WellKnownIndexEntry> entries,
  }) : entries = List<WellKnownIndexEntry>.unmodifiable(entries);

  final Uri indexUri;
  final String wellKnownPath;
  final List<WellKnownIndexEntry> entries;
}

/// Parses only the well-known catalog. Fetching, digest verification and
/// extraction are intentionally separate operations.
SourceResult<WellKnownIndex> parseWellKnownIndex(
  List<int> bytes, {
  required Uri indexUri,
  required String wellKnownPath,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
  } on FormatException {
    return _invalidIndex('invalidWellKnownIndex');
  }
  if (decoded is! Map<String, Object?>) {
    return _invalidIndex('indexMustBeObject');
  }
  final rawSkills = decoded['skills'];
  if (rawSkills is! List<Object?> || rawSkills.isEmpty) {
    return _invalidIndex('skillsMustBeNonEmptyArray');
  }
  final schema = decoded[r'$schema'];
  if (schema == wellKnownDiscoverySchemaV2) {
    return _parseV2(rawSkills, indexUri, wellKnownPath);
  }
  if (schema != null) {
    return _invalidIndex('unsupportedSchema');
  }
  return _parseV1(rawSkills, indexUri, wellKnownPath);
}

SourceResult<WellKnownIndex> _parseV1(
  List<Object?> rawSkills,
  Uri indexUri,
  String wellKnownPath,
) {
  final entries = <WellKnownIndexEntry>[];
  final names = <String>{};
  for (final rawEntry in rawSkills) {
    if (rawEntry is! Map<String, Object?>) {
      return _invalidIndex('invalidLegacyEntry');
    }
    final name = rawEntry['name'];
    final description = rawEntry['description'];
    final rawFiles = rawEntry['files'];
    if (!_isValidName(name) ||
        description is! String ||
        description.trim().isEmpty ||
        rawFiles is! List<Object?> ||
        rawFiles.isEmpty) {
      return _invalidIndex('invalidLegacyEntry');
    }
    final files = <String>[];
    final identities = <String>{};
    for (final rawFile in rawFiles) {
      if (!_isSafeDeclaredFilePath(rawFile)) {
        return _invalidIndex('unsafeDeclaredFilePath');
      }
      final file = rawFile! as String;
      if (!identities.add(file.toUpperCase())) {
        return _invalidIndex('duplicateDeclaredFilePath');
      }
      files.add(file);
    }
    if (!files.any((file) => file.toLowerCase() == 'skill.md')) {
      return _invalidIndex('legacyEntryMissingSkillMarkdown');
    }
    final declaredName = name! as String;
    if (!names.add(declaredName.toLowerCase())) {
      return _invalidIndex('duplicateEntryName');
    }
    entries.add(
      WellKnownIndexEntry._(
        version: WellKnownEntryVersion.v0_1,
        name: declaredName,
        description: description,
        type: WellKnownArtifactType.declaredFiles,
        files: files,
      ),
    );
  }
  return _success(indexUri, wellKnownPath, entries);
}

SourceResult<WellKnownIndex> _parseV2(
  List<Object?> rawSkills,
  Uri indexUri,
  String wellKnownPath,
) {
  final entries = <WellKnownIndexEntry>[];
  final names = <String>{};
  for (final rawEntry in rawSkills) {
    if (rawEntry is! Map<String, Object?>) {
      continue;
    }
    final name = rawEntry['name'];
    final description = rawEntry['description'];
    final rawType = rawEntry['type'];
    final rawUrl = rawEntry['url'];
    final digest = rawEntry['digest'];
    if (!_isValidName(name) ||
        description is! String ||
        description.trim().isEmpty ||
        description.length > 1024 ||
        (rawType != 'skill-md' && rawType != 'archive') ||
        rawUrl is! String ||
        rawUrl.trim().isEmpty ||
        digest is! String ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) {
      continue;
    }
    Uri artifactUri;
    try {
      artifactUri = indexUri.resolve(rawUrl);
    } on FormatException {
      continue;
    }
    final declaredName = name! as String;
    if (!names.add(declaredName.toLowerCase())) {
      return _invalidIndex('duplicateEntryName');
    }
    entries.add(
      WellKnownIndexEntry._(
        version: WellKnownEntryVersion.v0_2,
        name: declaredName,
        description: description,
        type: rawType == 'skill-md'
            ? WellKnownArtifactType.skillMarkdown
            : WellKnownArtifactType.archive,
        files: const <String>[],
        artifactUri: artifactUri,
        digest: digest,
      ),
    );
  }
  if (entries.isEmpty) {
    return _invalidIndex('noValidV2Entries');
  }
  return _success(indexUri, wellKnownPath, entries);
}

SourceResult<WellKnownIndex> _success(
  Uri indexUri,
  String wellKnownPath,
  List<WellKnownIndexEntry> entries,
) => SourceSuccess<WellKnownIndex>(
  value: WellKnownIndex(
    indexUri: indexUri,
    wellKnownPath: wellKnownPath,
    entries: entries,
  ),
);

bool _isValidName(Object? value) {
  if (value is! String || value.isEmpty || value.length > 64) {
    return false;
  }
  return RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(value) &&
      !value.contains('--');
}

bool _isSafeDeclaredFilePath(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.startsWith('/') ||
      value.startsWith(r'\') ||
      value.contains(r'\') ||
      value.contains('\x00') ||
      utf8.encode(value).length > 4096) {
    return false;
  }
  final segments = value.split('/');
  return segments.every(
    (segment) =>
        segment.isNotEmpty &&
        utf8.encode(segment).length <= 255 &&
        segment != '.' &&
        segment != '..' &&
        !segment.contains(':') &&
        !segment.endsWith('.') &&
        !segment.endsWith(' ') &&
        segment.toUpperCase() != '.GIT' &&
        !_isWindowsReservedName(segment),
  );
}

bool _isWindowsReservedName(String segment) {
  final base = segment.split('.').first.toUpperCase();
  return const <String>{
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
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  }.contains(base);
}

SourceFailure<WellKnownIndex> _invalidIndex(String reason) =>
    SourceFailure<WellKnownIndex>(
      code: SourceFailureCode.invalidSource,
      context: <String, Object?>{'reason': reason},
    );
