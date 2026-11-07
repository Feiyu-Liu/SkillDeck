import 'dart:convert';

import 'package:path/path.dart' as paths;
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../content/normalized_skill_tree.dart';
import 'source_result.dart';

enum SourceTreeEntryKind { file, directory, symbolicLink }

/// Expanded bytes together with the directory identities lost by expansion.
final class ResolvedSourceTree {
  ResolvedSourceTree({
    required List<SkillContentEntry> files,
    required Map<String, String> directoryOrigins,
  }) : files = List.unmodifiable(files),
       directoryOrigins = Map.unmodifiable(directoryOrigins);

  final List<SkillContentEntry> files;
  final Map<String, String> directoryOrigins;

  String canonicalDirectory(String directory) {
    var ancestor = directory;
    while (ancestor.isNotEmpty && ancestor != '.') {
      final origin = directoryOrigins[ancestor];
      if (origin != null) {
        final suffix = paths.posix.relative(directory, from: ancestor);
        return suffix == '.' ? origin : paths.posix.join(origin, suffix);
      }
      ancestor = paths.posix.dirname(ancestor);
    }
    return directory;
  }
}

/// One untrusted source entry before symbolic links become regular files.
final class SourceTreeEntry {
  SourceTreeEntry.file({
    required this.path,
    required List<int> bytes,
    this.isExecutable = false,
  }) : kind = SourceTreeEntryKind.file,
       bytes = List<int>.unmodifiable(bytes),
       symbolicLinkTargetBytes = null;

  SourceTreeEntry.directory({required this.path})
    : kind = SourceTreeEntryKind.directory,
      bytes = const <int>[],
      isExecutable = false,
      symbolicLinkTargetBytes = null;

  SourceTreeEntry.symbolicLink({
    required this.path,
    required List<int> targetBytes,
  }) : kind = SourceTreeEntryKind.symbolicLink,
       bytes = const <int>[],
       isExecutable = false,
       symbolicLinkTargetBytes = List<int>.unmodifiable(targetBytes);

  final String path;
  final SourceTreeEntryKind kind;
  final List<int> bytes;
  final bool isExecutable;
  final List<int>? symbolicLinkTargetBytes;
}

/// Dereferences contained, acyclic source links into regular file entries.
///
/// Link targets use POSIX semantics and are resolved relative to the link's
/// parent. A directory link materializes every regular file reachable below
/// the target directory. Source entries are never executed or written to disk.
final class SourceTreeSymlinkResolver {
  const SourceTreeSymlinkResolver({
    this.maximumFileCount = maximumNormalizedSkillFileCount,
    this.maximumByteSize = maximumNormalizedSkillByteSize,
  }) : assert(maximumFileCount > 0),
       assert(maximumByteSize > 0);

  final int maximumFileCount;
  final int maximumByteSize;

  SourceResult<List<SkillContentEntry>> resolve(
    Iterable<SourceTreeEntry> entries,
  ) {
    final result = resolveWithOrigins(entries);
    final tree = result.valueOrNull;
    return tree == null
        ? copySourceFailure<ResolvedSourceTree, List<SkillContentEntry>>(
            result.failureOrNull!,
          )
        : SourceSuccess(value: tree.files);
  }

  SourceResult<ResolvedSourceTree> resolveWithOrigins(
    Iterable<SourceTreeEntry> entries, {
    Set<String>? selectedRoots,
    bool skipInvalidLinks = false,
  }) {
    final nodes = <String, SourceTreeEntry>{};
    for (final entry in entries) {
      if (!_isSafeSourcePath(entry.path)) {
        return _failure('unsafeSourcePath', path: entry.path);
      }
      if (nodes.containsKey(entry.path)) {
        return _failure('duplicateSourcePath', path: entry.path);
      }
      nodes[entry.path] = entry;
    }

    final pathsInTree = nodes.keys.toList(growable: false);
    for (final entry in nodes.values) {
      if (entry.kind == SourceTreeEntryKind.directory) continue;
      final prefix = '${entry.path}/';
      final descendant = pathsInTree.where((path) => path.startsWith(prefix));
      if (descendant.isNotEmpty) {
        return _failure(
          'sourcePathTypeConflict',
          path: descendant.first,
          conflictingPath: entry.path,
        );
      }
    }

    final state = _ResolutionState(
      nodes: nodes,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
    );
    final ordered = nodes.values.toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final entry in ordered) {
      if (entry.kind == SourceTreeEntryKind.directory) continue;
      if (selectedRoots != null &&
          !selectedRoots.any(
            (root) =>
                root.isEmpty ||
                root == '.' ||
                entry.path == root ||
                entry.path.startsWith('$root/'),
          )) {
        continue;
      }
      final optionalLink =
          skipInvalidLinks && entry.kind == SourceTreeEntryKind.symbolicLink;
      final beforePaths = optionalLink
          ? state.files.keys.toSet()
          : const <String>{};
      final beforeOrigins = optionalLink
          ? Map<String, String>.of(state.directoryOrigins)
          : const <String, String>{};
      state.resolveEntity(entry.path, entry.path, <String>{});
      if (state.failure != null &&
          skipInvalidLinks &&
          entry.kind == SourceTreeEntryKind.symbolicLink &&
          !state.failure!.limit) {
        state.files.removeWhere((key, value) => !beforePaths.contains(key));
        state._portablePaths.removeWhere(
          (key, value) => !beforePaths.contains(value),
        );
        state._byteSize = state.files.values.fold(
          0,
          (total, entry) => total + entry.bytes.length,
        );
        state.directoryOrigins
          ..clear()
          ..addAll(beforeOrigins);
        state.failure = null;
      }
      if (state.failure != null) break;
    }
    if (state.failure case final failure?) {
      return SourceFailure<ResolvedSourceTree>(
        code: failure.limit
            ? SourceFailureCode.contentLimitExceeded
            : SourceFailureCode.contentInvalid,
        context: failure.context,
      );
    }
    final resolved = state.files.values.toList()
      ..sort((left, right) {
        final leftPath = utf8.decode(left.pathBytes);
        final rightPath = utf8.decode(right.pathBytes);
        return leftPath.compareTo(rightPath);
      });
    return SourceSuccess<ResolvedSourceTree>(
      value: ResolvedSourceTree(
        files: resolved,
        directoryOrigins: state.directoryOrigins,
      ),
    );
  }

  SourceFailure<ResolvedSourceTree> _failure(
    String reason, {
    String? path,
    String? conflictingPath,
  }) => SourceFailure<ResolvedSourceTree>(
    code: SourceFailureCode.contentInvalid,
    context: <String, Object?>{
      'reason': reason,
      if (path != null) 'path': _bounded(path),
      if (conflictingPath != null) 'conflictingPath': _bounded(conflictingPath),
    },
  );
}

final class _ResolutionState {
  _ResolutionState({
    required this.nodes,
    required this.maximumFileCount,
    required this.maximumByteSize,
  });

  final Map<String, SourceTreeEntry> nodes;
  final int maximumFileCount;
  final int maximumByteSize;
  final Map<String, SkillContentEntry> files = {};
  final Map<String, String> directoryOrigins = {};
  final Map<String, String> _portablePaths = {};
  _ResolutionFailure? failure;
  var _byteSize = 0;

  void resolveEntity(
    String sourcePath,
    String outputPath,
    Set<String> resolvingLinks,
  ) {
    if (failure != null) return;
    final node = nodes[sourcePath];
    if (node == null) {
      // A link may occur in the middle of another link's target path.
      var ancestor = paths.posix.dirname(sourcePath);
      while (ancestor != '.' && ancestor.isNotEmpty) {
        final link = nodes[ancestor];
        if (link?.kind == SourceTreeEntryKind.symbolicLink) {
          if (!resolvingLinks.add(ancestor)) {
            _fail('symbolicLinkCycle', path: ancestor);
            return;
          }
          final target = _resolveLinkTarget(link!);
          if (target != null) {
            resolveEntity(
              paths.posix.join(
                target,
                paths.posix.relative(sourcePath, from: ancestor),
              ),
              outputPath,
              resolvingLinks,
            );
          }
          resolvingLinks.remove(ancestor);
          return;
        }
        ancestor = paths.posix.dirname(ancestor);
      }
      if (_isDirectory(sourcePath)) {
        _resolveDirectory(sourcePath, outputPath, resolvingLinks);
      } else {
        _fail('symbolicLinkUnresolved', path: outputPath);
      }
      return;
    }
    switch (node.kind) {
      case SourceTreeEntryKind.file:
        _addFile(outputPath, node);
      case SourceTreeEntryKind.directory:
        _resolveDirectory(sourcePath, outputPath, resolvingLinks);
      case SourceTreeEntryKind.symbolicLink:
        if (!resolvingLinks.add(sourcePath)) {
          _fail('symbolicLinkCycle', path: sourcePath);
          return;
        }
        final target = _resolveLinkTarget(node);
        if (target != null) {
          resolveEntity(target, outputPath, resolvingLinks);
        }
        resolvingLinks.remove(sourcePath);
    }
  }

  void _resolveDirectory(
    String sourceDirectory,
    String outputDirectory,
    Set<String> resolvingLinks,
  ) {
    directoryOrigins[outputDirectory] = sourceDirectory;
    final prefix = sourceDirectory.isEmpty ? '' : '$sourceDirectory/';
    final descendants =
        nodes.values
            .where(
              (entry) =>
                  entry.kind != SourceTreeEntryKind.directory &&
                  entry.path.startsWith(prefix) &&
                  entry.path.length > prefix.length,
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final descendant in descendants) {
      final suffix = descendant.path.substring(prefix.length);
      resolveEntity(
        descendant.path,
        paths.posix.join(outputDirectory, suffix),
        resolvingLinks,
      );
      if (failure != null) return;
    }
  }

  String? _resolveLinkTarget(SourceTreeEntry link) {
    final result = resolveSourceLinkTarget(link);
    if (result.failureOrNull case final error?) {
      failure ??= _ResolutionFailure(error.context);
    }
    return result.valueOrNull;
  }

  bool _isDirectory(String sourcePath) {
    final prefix = sourcePath.isEmpty ? '' : '$sourcePath/';
    return nodes.values.any(
      (entry) => entry.path.startsWith(prefix) && entry.path != sourcePath,
    );
  }

  void _addFile(String outputPath, SourceTreeEntry source) {
    final existing = files[outputPath];
    if (existing != null) {
      _fail('symbolicLinkOutputCollision', path: outputPath);
      return;
    }
    for (final existingPath in files.keys) {
      if (existingPath.startsWith('$outputPath/') ||
          outputPath.startsWith('$existingPath/')) {
        _fail(
          'fileDirectoryCollision',
          path: outputPath,
          conflictingPath: existingPath,
        );
        return;
      }
    }
    final portableKey = _portableCollisionKey(outputPath);
    final portableConflict = _portablePaths[portableKey];
    if (portableConflict != null) {
      _fail(
        'portablePathCollision',
        path: outputPath,
        conflictingPath: portableConflict,
      );
      return;
    }
    if (files.length >= maximumFileCount) {
      _failLimit('fileCount', files.length + 1);
      return;
    }
    if (source.bytes.length > maximumByteSize - _byteSize) {
      _failLimit('byteSize', _byteSize + source.bytes.length);
      return;
    }
    _byteSize += source.bytes.length;
    files[outputPath] = SkillContentEntry.file(
      path: outputPath,
      bytes: source.bytes,
      isExecutable: source.isExecutable,
    );
    _portablePaths[portableKey] = outputPath;
  }

  void _fail(String reason, {String? path, String? conflictingPath}) {
    failure ??= _ResolutionFailure(<String, Object?>{
      'reason': reason,
      if (path != null) 'path': _bounded(path),
      if (conflictingPath != null) 'conflictingPath': _bounded(conflictingPath),
    });
  }

  void _failLimit(String limit, int actual) {
    failure ??= _ResolutionFailure(<String, Object?>{
      'limit': limit,
      'actual': actual,
      'maximumFileCount': maximumFileCount,
      'maximumByteSize': maximumByteSize,
    }, limit: true);
  }
}

/// Resolves a link lexically within a repository/archive without reading bytes
/// from outside that source. Used before fetching linked Git dependencies.
SourceResult<String> resolveSourceLinkTarget(SourceTreeEntry link) {
  SourceFailure<String> invalid(String reason, {String? target}) =>
      SourceFailure(
        code: SourceFailureCode.contentInvalid,
        context: {
          'reason': reason,
          'path': _bounded(link.path),
          if (target != null) 'target': _bounded(target),
        },
      );
  String target;
  try {
    target = utf8.decode(link.symbolicLinkTargetBytes!, allowMalformed: false);
  } on FormatException {
    return invalid('symbolicLinkTargetNotUtf8');
  }
  if (target.isEmpty ||
      target.contains('\x00') ||
      target.contains(r'\') ||
      utf8.encode(target).length > 4096) {
    return invalid('symbolicLinkTargetInvalid', target: target);
  }
  final windows = paths.Context(style: paths.Style.windows);
  if (paths.posix.isAbsolute(target) || windows.isAbsolute(target)) {
    return invalid('symbolicLinkEscapesSource', target: target);
  }
  final parent = paths.posix.dirname(link.path);
  final candidate = paths.posix.normalize(
    paths.posix.join(parent == '.' ? '' : parent, target),
  );
  if (candidate == '..' ||
      candidate.startsWith('../') ||
      paths.posix.isAbsolute(candidate)) {
    return invalid('symbolicLinkEscapesSource', target: target);
  }
  return SourceSuccess(value: candidate == '.' ? '' : candidate);
}

final class _ResolutionFailure {
  const _ResolutionFailure(this.context, {this.limit = false});

  final Map<String, Object?> context;
  final bool limit;
}

bool _isSafeSourcePath(String value) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.startsWith(r'\') ||
      value.contains(r'\') ||
      value.contains('\x00')) {
    return false;
  }
  final windows = paths.Context(style: paths.Style.windows);
  if (windows.isAbsolute(value)) return false;
  final segments = value.split('/');
  return !segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  );
}

String _portableCollisionKey(String value) =>
    unicode.nfkc(unicode.nfc(value).toUpperCase());

String _bounded(String value) =>
    value.length <= 256 ? value : '${value.substring(0, 253)}...';
