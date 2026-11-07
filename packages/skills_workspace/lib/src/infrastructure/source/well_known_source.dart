import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as paths;

import '../../application/ports/revision_content_worker_ports.dart';
import '../../domain/slot_key.dart';
import '../../domain/source_descriptor.dart';
import '../content/content_result.dart';
import '../content/direct_revision_content_worker.dart';
import '../content/normalized_skill_tree.dart';
import 'frontmatter_parser.dart';
import 'source_models.dart';
import 'source_result.dart';
import 'well_known_archive.dart';
import 'well_known_http.dart';
import 'well_known_index.dart';

const int _maximumIndexByteSize = 1024 * 1024;
const List<String> _wellKnownPaths = <String>[
  '.well-known/agent-skills',
  '.well-known/skills',
];

/// Resolves well-known catalogs and returns normalized Skill trees.
///
/// Catalog parsing, HTTP transport, digest verification, archive extraction,
/// and content normalization remain separate steps so a future marketplace
/// index cannot become coupled to well-known byte acquisition.
final class WellKnownSourceAdapter {
  WellKnownSourceAdapter({
    WellKnownHttpClient? httpClient,
    WellKnownArchiveExtractor? archiveExtractor,
    RevisionContentWorkerPort contentWorker =
        const DirectRevisionContentWorker(),
    this.maximumFileCount = maximumNormalizedSkillFileCount,
    this.maximumByteSize = maximumNormalizedSkillByteSize,
  }) : assert(maximumFileCount > 0),
       assert(maximumByteSize > 0),
       _httpClient = httpClient ?? WellKnownHttpClient(),
       _archiveExtractor =
           archiveExtractor ??
           WellKnownArchiveExtractor(
             maximumFileCount: maximumFileCount,
             maximumByteSize: maximumByteSize,
           ),
       _contentWorker = contentWorker;

  final WellKnownHttpClient _httpClient;
  final WellKnownArchiveExtractor _archiveExtractor;
  final RevisionContentWorkerPort _contentWorker;
  final int maximumFileCount;
  final int maximumByteSize;

  Future<SourceResult<WellKnownIndex>> inspectIndex(
    WellKnownSourceDescriptor source, {
    SourceCancellationSignal cancellation = const NoSourceCancellationSignal(),
  }) async {
    final endpoint = _parseEndpoint(source.locator);
    if (endpoint == null) {
      return SourceFailure<WellKnownIndex>(
        code: SourceFailureCode.rejected,
        context: const <String, Object?>{
          'reason': 'invalidOrCredentialBearingWellKnownEndpoint',
        },
      );
    }
    return _fetchIndex(endpoint, cancellation);
  }

  Future<SourceResult<AcquiredSource>> acquire(
    WellKnownSourceDescriptor source, {
    Iterable<String> selectedSkills = const <String>[],
    SkillDiscoveryOptions options = const SkillDiscoveryOptions(),
    SourceCancellationSignal cancellation = const NoSourceCancellationSignal(),
  }) async {
    if (cancellation.isCancelled) {
      return SourceFailure<AcquiredSource>(code: SourceFailureCode.cancelled);
    }
    final indexResult = await inspectIndex(source, cancellation: cancellation);
    final index = indexResult.valueOrNull;
    if (index == null) {
      return copySourceFailure<WellKnownIndex, AcquiredSource>(
        indexResult.failureOrNull!,
      );
    }

    final suppliedSelectors = selectedSkills.toList(growable: false);
    final selectors = suppliedSelectors.isNotEmpty
        ? suppliedSelectors
        : source.skillPath.isEmpty
        ? const <String>[]
        : <String>[source.skillPath];
    final selectionResult = _selectEntries(index.entries, selectors);
    final selected = selectionResult.valueOrNull;
    if (selected == null) {
      return copySourceFailure<List<WellKnownIndexEntry>, AcquiredSource>(
        selectionResult.failureOrNull!,
      );
    }

    final acquired = <AcquiredSourceSkill>[];
    final warnings = <SourceWarning>[];
    SourceFailure<AcquiredSourceSkill>? firstFailure;
    for (final entry in selected) {
      if (cancellation.isCancelled) {
        return SourceFailure<AcquiredSource>(
          code: SourceFailureCode.cancelled,
          warnings: warnings,
        );
      }
      final result = await _acquireEntry(index, entry, options, cancellation);
      final skill = result.valueOrNull;
      if (skill != null) {
        acquired.add(skill);
        continue;
      }
      final failure = result.failureOrNull!;
      if (failure.code == SourceFailureCode.cancelled || selectors.isNotEmpty) {
        return SourceFailure<AcquiredSource>(
          code: failure.code,
          context: failure.context,
          warnings: warnings,
        );
      }
      firstFailure ??= failure;
      warnings.add(
        SourceWarning(
          code: SourceWarningCode.sourceEntrySkipped,
          context: <String, Object?>{
            'entry': entry.name,
            'code': failure.code.name,
          },
        ),
      );
    }
    if (acquired.isEmpty) {
      final failure = firstFailure;
      return SourceFailure<AcquiredSource>(
        code: failure?.code ?? SourceFailureCode.notFound,
        context:
            failure?.context ??
            const <String, Object?>{'reason': 'noValidSkills'},
        warnings: warnings,
      );
    }

    final canonicalLocator = _withoutQueryOrFragment(
      index.indexUri,
    ).normalizePath().toString();
    return SourceSuccess<AcquiredSource>(
      value: AcquiredSource(
        canonicalSource: WellKnownSourceDescriptor(
          locator: canonicalLocator,
          skillPath: source.skillPath,
        ),
        skills: acquired,
      ),
      warnings: warnings,
    );
  }

  Future<SourceResult<WellKnownIndex>> _fetchIndex(
    Uri endpoint,
    SourceCancellationSignal cancellation,
  ) async {
    SourceFailure<WellKnownIndex>? lastFailure;
    for (final candidate in _indexCandidates(endpoint)) {
      final response = await _httpClient.get(
        candidate.uri,
        maximumBytes: _maximumIndexByteSize,
        cancellation: cancellation,
      );
      final value = response.valueOrNull;
      if (value == null) {
        final failure = response.failureOrNull!;
        if (failure.code == SourceFailureCode.rejected ||
            failure.code == SourceFailureCode.cancelled) {
          return copySourceFailure<WellKnownHttpResponse, WellKnownIndex>(
            failure,
          );
        }
        lastFailure = copySourceFailure<WellKnownHttpResponse, WellKnownIndex>(
          failure,
        );
        continue;
      }
      final parsed = parseWellKnownIndex(
        value.bytes,
        indexUri: value.uri,
        wellKnownPath: candidate.wellKnownPath,
      );
      if (parsed.valueOrNull != null) {
        return parsed;
      }
      lastFailure = parsed.failureOrNull;
    }
    return lastFailure ??
        SourceFailure<WellKnownIndex>(
          code: SourceFailureCode.unavailable,
          context: const <String, Object?>{
            'reason': 'wellKnownIndexUnavailable',
          },
        );
  }

  Future<SourceResult<AcquiredSourceSkill>> _acquireEntry(
    WellKnownIndex index,
    WellKnownIndexEntry entry,
    SkillDiscoveryOptions options,
    SourceCancellationSignal cancellation,
  ) async {
    final entriesResult = switch (entry.type) {
      WellKnownArtifactType.declaredFiles => _fetchDeclaredFiles(
        index,
        entry,
        cancellation,
      ),
      WellKnownArtifactType.skillMarkdown => _fetchSkillMarkdown(
        entry,
        cancellation,
      ),
      WellKnownArtifactType.archive => _fetchArchive(entry, cancellation),
    };
    final resolvedEntries = await entriesResult;
    final entries = resolvedEntries.valueOrNull;
    if (entries == null) {
      return copySourceFailure<List<SkillContentEntry>, AcquiredSourceSkill>(
        resolvedEntries.failureOrNull!,
      );
    }
    final normalized = await _contentWorker.normalizeContent(
      entries,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
      isCancelled: () => cancellation.isCancelled,
    );
    final tree = normalized.valueOrNull;
    if (tree == null) {
      return _mapContentFailure<NormalizedSkillTree, AcquiredSourceSkill>(
        normalized.failureOrNull!,
      );
    }
    return _validatedSkill(index, entry, tree, options);
  }

  Future<SourceResult<List<SkillContentEntry>>> _fetchDeclaredFiles(
    WellKnownIndex index,
    WellKnownIndexEntry entry,
    SourceCancellationSignal cancellation,
  ) async {
    final declaredFiles = <String>[
      'SKILL.md',
      ...entry.files.where((file) => file.toLowerCase() != 'skill.md'),
    ];
    if (declaredFiles.length > maximumFileCount) {
      return _limitFailure('fileCount', declaredFiles.length);
    }
    final base = index.indexUri.resolve('${entry.name}/');
    final entries = <SkillContentEntry>[];
    final seen = <String>{};
    var totalBytes = 0;
    for (final relativePath in declaredFiles) {
      if (!seen.add(relativePath.toUpperCase())) {
        return SourceFailure<List<SkillContentEntry>>(
          code: SourceFailureCode.invalidSource,
          context: const <String, Object?>{
            'reason': 'duplicateDeclaredFilePath',
          },
        );
      }
      final response = await _httpClient.get(
        _declaredFileUri(base, relativePath),
        maximumBytes: maximumByteSize - totalBytes,
        cancellation: cancellation,
      );
      final value = response.valueOrNull;
      if (value == null) {
        return copySourceFailure<
          WellKnownHttpResponse,
          List<SkillContentEntry>
        >(response.failureOrNull!);
      }
      totalBytes += value.bytes.length;
      entries.add(
        SkillContentEntry.file(path: relativePath, bytes: value.bytes),
      );
    }
    return SourceSuccess<List<SkillContentEntry>>(value: entries);
  }

  Future<SourceResult<List<SkillContentEntry>>> _fetchSkillMarkdown(
    WellKnownIndexEntry entry,
    SourceCancellationSignal cancellation,
  ) async {
    final response = await _httpClient.get(
      entry.artifactUri!,
      maximumBytes: maximumByteSize,
      cancellation: cancellation,
    );
    final value = response.valueOrNull;
    if (value == null) {
      return copySourceFailure<WellKnownHttpResponse, List<SkillContentEntry>>(
        response.failureOrNull!,
      );
    }
    final digestFailure = _verifyDigest(value.bytes, entry.digest!);
    if (digestFailure != null) {
      return digestFailure;
    }
    return SourceSuccess<List<SkillContentEntry>>(
      value: <SkillContentEntry>[
        SkillContentEntry.file(path: 'SKILL.md', bytes: value.bytes),
      ],
    );
  }

  Future<SourceResult<List<SkillContentEntry>>> _fetchArchive(
    WellKnownIndexEntry entry,
    SourceCancellationSignal cancellation,
  ) async {
    final maximumArtifactBytes =
        maximumByteSize + maximumFileCount * 8192 + 2048;
    final response = await _httpClient.get(
      entry.artifactUri!,
      maximumBytes: maximumArtifactBytes,
      cancellation: cancellation,
    );
    final value = response.valueOrNull;
    if (value == null) {
      return copySourceFailure<WellKnownHttpResponse, List<SkillContentEntry>>(
        response.failureOrNull!,
      );
    }
    final digestFailure = _verifyDigest(value.bytes, entry.digest!);
    if (digestFailure != null) {
      return digestFailure;
    }
    return _archiveExtractor.extract(
      value.bytes,
      artifactUri: value.uri,
      contentType: value.contentType,
    );
  }

  SourceResult<AcquiredSourceSkill> _validatedSkill(
    WellKnownIndex index,
    WellKnownIndexEntry entry,
    NormalizedSkillTree tree,
    SkillDiscoveryOptions options,
  ) {
    final skillMarkdown = tree.files
        .where((file) => file.relativePath == 'SKILL.md')
        .firstOrNull;
    if (skillMarkdown == null) {
      return SourceFailure<AcquiredSourceSkill>(
        code: SourceFailureCode.invalidSource,
        context: const <String, Object?>{'reason': 'missingSkillMarkdown'},
      );
    }
    SkillFrontmatter? frontmatter;
    try {
      frontmatter = parseSkillFrontmatter(
        utf8.decode(skillMarkdown.bytes, allowMalformed: false),
      );
    } on FormatException {
      frontmatter = null;
    }
    if (frontmatter == null) {
      return SourceFailure<AcquiredSourceSkill>(
        code: SourceFailureCode.invalidSource,
        context: const <String, Object?>{'reason': 'invalidSkillFrontmatter'},
      );
    }
    if (frontmatter.isInternal && !options.includeInternal) {
      return SourceFailure<AcquiredSourceSkill>(
        code: SourceFailureCode.notFound,
        context: const <String, Object?>{'reason': 'internalSkillExcluded'},
      );
    }
    if (frontmatter.declaredName.toLowerCase() != entry.name.toLowerCase()) {
      return SourceFailure<AcquiredSourceSkill>(
        code: SourceFailureCode.invalidSource,
        context: const <String, Object?>{
          'reason': 'indexAndFrontmatterNameMismatch',
        },
      );
    }
    final slotKey = deriveSlotKeyValue(frontmatter.declaredName).value;
    if (slotKey == null) {
      return SourceFailure<AcquiredSourceSkill>(
        code: SourceFailureCode.invalidSource,
        context: const <String, Object?>{'reason': 'unsupportedSkillName'},
      );
    }
    final canonicalLocator = _withoutQueryOrFragment(
      index.indexUri,
    ).normalizePath().toString();
    return SourceSuccess<AcquiredSourceSkill>(
      value: AcquiredSourceSkill(
        provenance: WellKnownSourceDescriptor(
          locator: canonicalLocator,
          skillPath: entry.name,
        ),
        declaredName: frontmatter.declaredName,
        description: frontmatter.description,
        slotKey: slotKey,
        skillPath: entry.name,
        frontmatter: frontmatter.values,
        tree: tree,
      ),
    );
  }

  SourceFailure<List<SkillContentEntry>>? _verifyDigest(
    List<int> bytes,
    String expected,
  ) {
    final actual = 'sha256:${sha256.convert(bytes)}';
    if (actual == expected) {
      return null;
    }
    return SourceFailure<List<SkillContentEntry>>(
      code: SourceFailureCode.digestMismatch,
      context: const <String, Object?>{'algorithm': 'sha256'},
    );
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

Uri? _parseEndpoint(String value) {
  final endpoint = Uri.tryParse(value);
  if (endpoint == null ||
      !endpoint.isAbsolute ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      (endpoint.scheme != 'https' && endpoint.scheme != 'http')) {
    return null;
  }
  return endpoint;
}

SourceResult<List<WellKnownIndexEntry>> _selectEntries(
  List<WellKnownIndexEntry> entries,
  List<String> selectors,
) {
  if (entries.isEmpty) {
    return SourceFailure<List<WellKnownIndexEntry>>(
      code: SourceFailureCode.notFound,
      context: const <String, Object?>{'reason': 'noValidSkills'},
    );
  }
  if (selectors.isEmpty) {
    return SourceSuccess<List<WellKnownIndexEntry>>(value: entries);
  }
  final requested = selectors.map((value) => value.toLowerCase()).toSet();
  final selected = entries
      .where((entry) => requested.contains(entry.name.toLowerCase()))
      .toList(growable: false);
  if (selected.length != requested.length) {
    return SourceFailure<List<WellKnownIndexEntry>>(
      code: SourceFailureCode.notFound,
      context: <String, Object?>{
        'requestedSelectors': List<String>.unmodifiable(selectors),
      },
    );
  }
  return SourceSuccess<List<WellKnownIndexEntry>>(value: selected);
}

List<_IndexCandidate> _indexCandidates(Uri endpoint) {
  final normalizedPath = endpoint.path.endsWith('/')
      ? endpoint.path.substring(0, endpoint.path.length - 1)
      : endpoint.path;
  for (final wellKnownPath in _wellKnownPaths) {
    final suffix = '/$wellKnownPath/index.json';
    if (normalizedPath.endsWith(suffix)) {
      return <_IndexCandidate>[
        _IndexCandidate(
          uri: _withoutQueryOrFragment(endpoint),
          wellKnownPath: wellKnownPath,
        ),
      ];
    }
  }

  final candidates = <_IndexCandidate>[];
  final seen = <String>{};
  for (final wellKnownPath in _wellKnownPaths) {
    final relativePath = '$normalizedPath/$wellKnownPath/index.json';
    final relativeUri = endpoint.replace(
      path: relativePath.startsWith('/') ? relativePath : '/$relativePath',
    );
    if (seen.add(relativeUri.toString())) {
      candidates.add(
        _IndexCandidate(uri: relativeUri, wellKnownPath: wellKnownPath),
      );
    }
    if (normalizedPath.isNotEmpty && normalizedPath != '/') {
      final rootUri = endpoint.replace(path: '/$wellKnownPath/index.json');
      if (seen.add(rootUri.toString())) {
        candidates.add(
          _IndexCandidate(uri: rootUri, wellKnownPath: wellKnownPath),
        );
      }
    }
  }
  return candidates;
}

Uri _declaredFileUri(Uri base, String relativePath) => _withoutQueryOrFragment(
  base,
).replace(path: paths.posix.join(base.path, relativePath));

Uri _withoutQueryOrFragment(Uri uri) {
  final withoutQuery = uri.hasQuery
      ? uri.replace(queryParameters: const <String, String>{})
      : uri;
  return withoutQuery.hasFragment
      ? withoutQuery.removeFragment()
      : withoutQuery;
}

SourceFailure<TTarget> _mapContentFailure<TSource, TTarget>(
  SkillContentFailure<TSource> failure,
) => SourceFailure<TTarget>(
  code: switch (failure.code) {
    SkillContentFailureCode.cancelled => SourceFailureCode.cancelled,
    SkillContentFailureCode.unavailable => SourceFailureCode.unavailable,
    SkillContentFailureCode.invalidContent => SourceFailureCode.contentInvalid,
    SkillContentFailureCode.limitExceeded =>
      SourceFailureCode.contentLimitExceeded,
  },
  context: failure.context,
);

final class _IndexCandidate {
  const _IndexCandidate({required this.uri, required this.wellKnownPath});

  final Uri uri;
  final String wellKnownPath;
}
