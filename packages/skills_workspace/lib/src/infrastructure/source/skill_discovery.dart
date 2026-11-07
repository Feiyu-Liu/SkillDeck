// Portions derived from vercel-labs/skills (MIT), Copyright (c) 2026 Vercel, Inc. See THIRD_PARTY_NOTICES.md.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;

import '../../domain/slot_key.dart';
import 'frontmatter_parser.dart';
import 'plugin_manifest.dart';
import 'source_models.dart';
import 'source_result.dart';

const Set<String> _skippedDirectories = <String>{
  'node_modules',
  '.git',
  'dist',
  'build',
  '__pycache__',
};

const List<String> _agentProjectSkillDirectories = <String>[
  '.agents/skills',
  '.claude/skills',
  '.cline/skills',
  '.codebuddy/skills',
  '.codex/skills',
  '.commandcode/skills',
  '.continue/skills',
  '.github/skills',
  '.goose/skills',
  '.iflow/skills',
  '.junie/skills',
  '.kilocode/skills',
  '.kiro/skills',
  '.mux/skills',
  '.neovate/skills',
  '.opencode/skills',
  '.openhands/skills',
  '.pi/skills',
  '.qoder/skills',
  '.roo/skills',
  '.trae/skills',
  '.windsurf/skills',
  '.zcode/skills',
  '.zencoder/skills',
];

/// Locates valid `SKILL.md` roots without reading arbitrary Skill content.
final class SkillDiscovery {
  const SkillDiscovery({this.maximumFrontmatterReadBytes = 1024 * 1024})
    : assert(maximumFrontmatterReadBytes > 0);

  final int maximumFrontmatterReadBytes;

  Future<SourceResult<FilesystemSourceInspection>> inspect(
    String basePath, {
    String? subpath,
    SkillDiscoveryOptions options = const SkillDiscoveryOptions(),
    SourceCancellationSignal cancellation = const NoSourceCancellationSignal(),
    bool followDirectoryLinks = false,
    String Function(String relativePath)? canonicalDirectory,
  }) async {
    if (cancellation.isCancelled) {
      return _cancelled();
    }
    final sourceRoot = paths.normalize(paths.absolute(basePath));
    try {
      if (await FileSystemEntity.type(sourceRoot, followLinks: true) !=
          FileSystemEntityType.directory) {
        return _failure(
          SourceFailureCode.unavailable,
          'sourceRootNotDirectory',
          path: sourceRoot,
        );
      }
      final searchRoot = _resolveSearchRoot(sourceRoot, subpath);
      if (searchRoot == null) {
        return _failure(
          SourceFailureCode.rejected,
          'unsafeRepositorySubpath',
          path: sourceRoot,
        );
      }
      if (await FileSystemEntity.type(searchRoot, followLinks: true) !=
              FileSystemEntityType.directory ||
          !await _realPathIsContained(sourceRoot, searchRoot)) {
        return _failure(
          SourceFailureCode.unavailable,
          'searchRootUnavailable',
          path: searchRoot,
        );
      }

      final manifestResult = await readPluginManifestIndex(
        searchRoot,
        cancellation: cancellation,
      );
      final manifest = manifestResult.valueOrNull;
      if (manifest == null) {
        return copySourceFailure<
          PluginManifestIndex,
          FilesystemSourceInspection
        >(manifestResult.failureOrNull!);
      }

      final candidates = <DiscoveredSkill>[];
      final seenRoots = <String>{};
      final drops = <String, String>{};
      final warnings = <SourceWarning>[];
      final identities = <String, int>{};
      final physicalRoot = await Directory(sourceRoot).resolveSymbolicLinks();

      void skippedLink(String linkPath) {
        warnings.add(
          SourceWarning(
            code: SourceWarningCode.sourceEntrySkipped,
            context: {
              'reason': 'invalidDirectoryLink',
              'path': _bounded(_normalizedRelativePath(sourceRoot, linkPath)),
            },
          ),
        );
      }

      final links = followDirectoryLinks
          ? _DirectoryLinkPolicy(
              containmentRoot: sourceRoot,
              onSkippedLink: skippedLink,
            )
          : null;

      Future<List<_DirectoryEntry>> entriesAt(String directory) =>
          _directoryEntries(
            directory,
            traversalRoot: searchRoot,
            cancellation: cancellation,
            links: links,
          );

      Future<bool> tryAdd(String skillRoot) async {
        if (cancellation.isCancelled) {
          throw const _DiscoveryCancelled();
        }
        final skillFile = File(paths.join(skillRoot, 'SKILL.md'));
        if (!await _isRegularFile(skillFile.path)) {
          return false;
        }
        final parsed = await _readFrontmatter(
          skillFile,
          maximumBytes: maximumFrontmatterReadBytes,
        );
        if (cancellation.isCancelled) {
          throw const _DiscoveryCancelled();
        }
        final frontmatter = parsed.frontmatter;
        final relativeFile = _normalizedRelativePath(
          sourceRoot,
          skillFile.path,
        );
        if (frontmatter == null) {
          drops[relativeFile] = parsed.reason ?? 'invalidFrontmatter';
          return true;
        }
        if (frontmatter.isInternal && !options.includeInternal) {
          return true;
        }
        final aliasRoot = paths.normalize(paths.absolute(skillRoot));
        if (!seenRoots.add(aliasRoot)) {
          return true;
        }
        final identity = await _candidateIdentity(
          aliasRoot,
          sourceRoot: sourceRoot,
          physicalRoot: physicalRoot,
          followDirectoryLinks: links != null,
          canonicalDirectory: canonicalDirectory,
        );
        if (identity == null) {
          skippedLink(aliasRoot);
          return true;
        }
        // Prefer the real path when the selection can address it.
        final selectedRoot =
            paths.equals(searchRoot, identity) ||
                paths.isWithin(searchRoot, identity)
            ? identity
            : aliasRoot;
        final derivation = deriveSlotKeyValue(frontmatter.declaredName);
        final slotKey = derivation.value;
        if (slotKey == null) {
          drops[relativeFile] =
              derivation.rejectionReason ?? 'unsupportedSkillName';
          return true;
        }
        final previousIndex = identities[identity];
        final previous = previousIndex == null
            ? null
            : candidates[previousIndex];
        final groupings = <String>{
          ?previous?.pluginName,
          ?manifest.groupings[aliasRoot],
        }.toList()..sort();
        final candidate = DiscoveredSkill(
          rootPath: selectedRoot,
          sourceRelativePath: _normalizedRelativePath(searchRoot, selectedRoot),
          slotKey: slotKey,
          frontmatter: frontmatter,
          pluginName: manifest.groupings[identity] ?? groupings.firstOrNull,
          aliasPaths: {
            _normalizedRelativePath(searchRoot, aliasRoot),
            ...?previous?.aliasPaths,
          },
        );
        if (previousIndex == null) {
          identities[identity] = candidates.length;
          candidates.add(candidate);
        } else {
          candidates[previousIndex] = candidate;
        }
        return true;
      }

      if (await _isRegularFile(paths.join(searchRoot, 'SKILL.md'))) {
        final found = await tryAdd(searchRoot);
        if (found && candidates.isNotEmpty && !options.fullDepth) {
          return _success(sourceRoot, searchRoot, candidates, warnings);
        }
      }

      final priorityDirectories = <String>[
        searchRoot,
        paths.join(searchRoot, 'skills'),
        paths.join(searchRoot, 'skills', '.curated'),
        paths.join(searchRoot, 'skills', '.experimental'),
        paths.join(searchRoot, 'skills', '.system'),
        ..._agentProjectSkillDirectories.map(
          (relative) => paths.join(searchRoot, relative),
        ),
        ...manifest.searchDirectories,
      ];
      final deepContainers = priorityDirectories.skip(1).toSet();
      for (final directory in _deduplicate(priorityDirectories)) {
        final entries = await entriesAt(directory);
        for (final entry in entries) {
          if (entry.type != FileSystemEntityType.directory ||
              _skippedDirectories.contains(entry.name)) {
            continue;
          }
          final child = paths.join(directory, entry.name);
          final foundAtChild = await tryAdd(child);
          if (foundAtChild || !deepContainers.contains(directory)) {
            continue;
          }
          for (final grandchild in await entriesAt(child)) {
            if (grandchild.type == FileSystemEntityType.directory &&
                !_skippedDirectories.contains(grandchild.name)) {
              await tryAdd(paths.join(child, grandchild.name));
            }
          }
        }
      }

      if (candidates.isEmpty || options.fullDepth) {
        final fallback = <String>[];
        await _findSkillDirectories(
          searchRoot,
          fallback,
          traversalRoot: searchRoot,
          cancellation: cancellation,
          links: links,
        );
        for (final skillRoot in fallback) {
          await tryAdd(skillRoot);
        }
      }
      if (candidates.isEmpty && drops.isNotEmpty) {
        final firstPath = (drops.keys.toList()..sort()).first;
        return SourceFailure<FilesystemSourceInspection>(
          code: SourceFailureCode.contentInvalid,
          context: {
            'reason': drops[firstPath],
            'path': firstPath,
            'droppedCount': drops.length,
          },
        );
      }
      candidates.sort(
        (left, right) =>
            left.sourceRelativePath.compareTo(right.sourceRelativePath),
      );
      return _success(sourceRoot, searchRoot, candidates, warnings);
    } on _DiscoveryCancelled {
      return _cancelled();
    } on FileSystemException {
      return _failure(
        SourceFailureCode.unavailable,
        'filesystemInspectionFailed',
        path: sourceRoot,
      );
    }
  }
}

SourceResult<FilesystemSourceInspection> _success(
  String sourceRoot,
  String searchRoot,
  List<DiscoveredSkill> candidates,
  List<SourceWarning> warnings,
) => SourceSuccess<FilesystemSourceInspection>(
  warnings: warnings,
  value: FilesystemSourceInspection(
    sourceRoot: sourceRoot,
    searchRoot: searchRoot,
    candidates: candidates,
  ),
);

SourceFailure<FilesystemSourceInspection> _cancelled() =>
    SourceFailure<FilesystemSourceInspection>(
      code: SourceFailureCode.cancelled,
    );

SourceFailure<FilesystemSourceInspection> _failure(
  SourceFailureCode code,
  String reason, {
  String? path,
}) => SourceFailure<FilesystemSourceInspection>(
  code: code,
  context: <String, Object?>{
    'reason': reason,
    if (path != null) 'path': _bounded(path),
  },
);

String? _resolveSearchRoot(String basePath, String? subpath) {
  if (subpath == null || subpath.isEmpty) {
    return basePath;
  }
  if (paths.isAbsolute(subpath) || subpath.contains(r'\')) {
    return null;
  }
  final target = paths.normalize(paths.absolute(paths.join(basePath, subpath)));
  if (!paths.equals(basePath, target) && !paths.isWithin(basePath, target)) {
    return null;
  }
  return target;
}

Future<bool> _realPathIsContained(String basePath, String targetPath) async {
  try {
    final realBase = paths.normalize(
      await Directory(basePath).resolveSymbolicLinks(),
    );
    final realTarget = paths.normalize(
      await Directory(targetPath).resolveSymbolicLinks(),
    );
    return paths.equals(realBase, realTarget) ||
        paths.isWithin(realBase, realTarget);
  } on FileSystemException {
    return false;
  }
}

/// The final directory a discovered Skill root identifies, or `null` when a
/// followed link leaves the physical Source root.
Future<String?> _candidateIdentity(
  String root, {
  required String sourceRoot,
  required String physicalRoot,
  required bool followDirectoryLinks,
  required String Function(String relativePath)? canonicalDirectory,
}) async {
  if (canonicalDirectory != null) {
    final canonical = canonicalDirectory(
      _normalizedRelativePath(sourceRoot, root),
    );
    return paths.normalize(
      paths.joinAll([sourceRoot, ...paths.posix.split(canonical)]),
    );
  }
  if (!followDirectoryLinks) return root;
  final physical = await Directory(root).resolveSymbolicLinks();
  if (!paths.equals(physicalRoot, physical) &&
      !paths.isWithin(physicalRoot, physical)) {
    return null;
  }
  return paths.normalize(
    paths.join(sourceRoot, paths.relative(physical, from: physicalRoot)),
  );
}

Future<({SkillFrontmatter? frontmatter, String? reason})> _readFrontmatter(
  File file, {
  required int maximumBytes,
}) async {
  try {
    final collected = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, maximumBytes)) {
      collected.add(chunk);
      final raw = utf8.decode(collected.toBytes(), allowMalformed: true);
      if (RegExp(
        r'^\uFEFF?(?:[ \t]*\r?\n)*---\r?\n[\s\S]*?\r?\n---(?:\r?\n|$)',
      ).hasMatch(raw)) {
        return inspectSkillFrontmatter(raw);
      }
    }
    return inspectSkillFrontmatter(utf8.decode(collected.takeBytes()));
  } on FileSystemException {
    return (frontmatter: null, reason: 'invalidFrontmatter');
  } on FormatException {
    return (frontmatter: null, reason: 'invalidFrontmatter');
  }
}

// Check the enumerated spelling, even on case-insensitive filesystems.
Future<bool> _isRegularFile(String path) async {
  final file = File(path);
  if (paths.basename(path) == 'SKILL.md') {
    if (!await file.parent.exists()) return false;
    var exact = false;
    await for (final entry in file.parent.list(followLinks: false)) {
      if (paths.basename(entry.path) == 'SKILL.md') {
        exact = true;
        break;
      }
    }
    if (!exact) return false;
  }
  return await FileSystemEntity.type(path, followLinks: true) ==
      FileSystemEntityType.file;
}

Future<List<_DirectoryEntry>> _directoryEntries(
  String path, {
  String? traversalRoot,
  required SourceCancellationSignal cancellation,
  _DirectoryLinkPolicy? links,
}) async {
  if (cancellation.isCancelled) {
    throw const _DiscoveryCancelled();
  }
  try {
    final lexicalType = await FileSystemEntity.type(path, followLinks: false);
    final trustedRootLink =
        traversalRoot != null &&
        paths.equals(path, traversalRoot) &&
        lexicalType == FileSystemEntityType.link &&
        await FileSystemEntity.type(path, followLinks: true) ==
            FileSystemEntityType.directory;
    final allowedLink =
        links != null && lexicalType == FileSystemEntityType.link;
    if (lexicalType != FileSystemEntityType.directory &&
        !trustedRootLink &&
        !allowedLink) {
      return const <_DirectoryEntry>[];
    }
    if (links == null &&
        traversalRoot != null &&
        await _hasLinkedPathSegment(traversalRoot, path)) {
      return const <_DirectoryEntry>[];
    }
    if (links != null &&
        !await _realPathIsContained(links.containmentRoot, path)) {
      links.onSkippedLink(path);
      return const [];
    }
    final entries = <_DirectoryEntry>[];
    await for (final entity in Directory(path).list(followLinks: false)) {
      if (cancellation.isCancelled) {
        throw const _DiscoveryCancelled();
      }
      var type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link && links != null) {
        final targetType = await FileSystemEntity.type(
          entity.path,
          followLinks: true,
        );
        if (targetType == FileSystemEntityType.directory &&
            await _realPathIsContained(links.containmentRoot, entity.path)) {
          type = FileSystemEntityType.directory;
        } else if (targetType != FileSystemEntityType.file) {
          links.onSkippedLink(entity.path);
        }
      }
      entries.add(
        _DirectoryEntry(name: paths.basename(entity.path), type: type),
      );
    }
    entries.sort((left, right) => left.name.compareTo(right.name));
    return entries;
  } on FileSystemException {
    return const <_DirectoryEntry>[];
  }
}

Future<bool> _hasLinkedPathSegment(String root, String target) async {
  if (!paths.equals(root, target) && !paths.isWithin(root, target)) {
    return true;
  }
  final relative = paths.relative(target, from: root);
  if (relative == '.') {
    return false;
  }
  var current = root;
  for (final segment in paths.split(relative)) {
    current = paths.join(current, segment);
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      return true;
    }
  }
  return false;
}

Future<void> _findSkillDirectories(
  String directory,
  List<String> result, {
  int depth = 0,
  int maximumDepth = 5,
  required String traversalRoot,
  required SourceCancellationSignal cancellation,
  _DirectoryLinkPolicy? links,
  Set<String>? ancestors,
}) async {
  if (cancellation.isCancelled) {
    throw const _DiscoveryCancelled();
  }
  if (depth > maximumDepth) {
    return;
  }
  final nextAncestors = <String>{...?ancestors};
  if (links != null) {
    try {
      final identity = await Directory(directory).resolveSymbolicLinks();
      if (!nextAncestors.add(identity)) {
        links.onSkippedLink(directory);
        return;
      }
    } on FileSystemException {
      links.onSkippedLink(directory);
      return;
    }
  }
  if (await _isRegularFile(paths.join(directory, 'SKILL.md'))) {
    result.add(directory);
  }
  for (final entry in await _directoryEntries(
    directory,
    traversalRoot: traversalRoot,
    cancellation: cancellation,
    links: links,
  )) {
    if (entry.type == FileSystemEntityType.directory &&
        !_skippedDirectories.contains(entry.name)) {
      await _findSkillDirectories(
        paths.join(directory, entry.name),
        result,
        depth: depth + 1,
        maximumDepth: maximumDepth,
        traversalRoot: traversalRoot,
        cancellation: cancellation,
        links: links,
        ancestors: nextAncestors,
      );
    }
  }
}

String _normalizedRelativePath(String base, String target) {
  final relative = paths.relative(target, from: base);
  return relative == '.' ? '' : paths.posix.joinAll(paths.split(relative));
}

List<String> _deduplicate(List<String> values) {
  final seen = <String>{};
  return values.where(seen.add).toList(growable: false);
}

String _bounded(String value) =>
    value.length <= 256 ? value : '${value.substring(0, 253)}...';

/// Contained directory links that discovery follows; the rest are reported.
final class _DirectoryLinkPolicy {
  const _DirectoryLinkPolicy({
    required this.containmentRoot,
    required this.onSkippedLink,
  });

  final String containmentRoot;
  final void Function(String path) onSkippedLink;
}

final class _DirectoryEntry {
  const _DirectoryEntry({required this.name, required this.type});

  final String name;
  final FileSystemEntityType type;
}

final class _DiscoveryCancelled implements Exception {
  const _DiscoveryCancelled();
}
