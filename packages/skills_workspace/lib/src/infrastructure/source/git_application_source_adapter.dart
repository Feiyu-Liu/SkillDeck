import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../../application/ports/source_acquisition_ports.dart';
import '../../application/ports/revision_content_worker_ports.dart';
import '../../application/source/source_acquisition_models.dart' as app;
import '../../domain/cancellation.dart';
import '../../domain/source_descriptor.dart';
import '../content/content_result.dart';
import '../content/direct_revision_content_worker.dart';
import '../content/normalized_skill_tree.dart';
import '../git_transport/git_source_parser.dart';
import '../git_transport/git_source_transport.dart';
import '../git_transport/git_transport_result.dart';
import 'skill_discovery.dart';
import 'source_models.dart' as infrastructure;
import 'source_result.dart' as infrastructure;
import 'source_tree_symlink_resolver.dart';

typedef GitSourceTemporaryDirectoryFactory = Future<Directory> Function();

/// How far link aliases may multiply the discovery projection beyond the
/// repository metadata budget, independent of each selected Skill budget.
const _projectionExpansionFactor = 10;

/// Converts a bare/no-checkout system-Git export into normalized Skill trees.
///
/// The temporary filesystem projection contains only discovery metadata. Skill
/// bytes and executable intent are read from Git objects and normalized in
/// memory, so checkout hooks, filters, LFS, and source repository metadata are
/// never imported.
final class GitApplicationSourceAdapter implements GitSourceAcquisitionPort {
  GitApplicationSourceAdapter({
    required GitSourceTransport transport,
    SkillDiscovery discovery = const SkillDiscovery(),
    RevisionContentWorkerPort contentWorker =
        const DirectRevisionContentWorker(),
    GitSourceParser parser = const GitSourceParser(),
    GitSourceTemporaryDirectoryFactory? temporaryDirectoryFactory,
  }) : _transport = transport,
       _discovery = discovery,
       _contentWorker = contentWorker,
       _parser = parser,
       _temporaryDirectoryFactory =
           temporaryDirectoryFactory ??
           (() => Directory.systemTemp.createTemp('skills-git-source-'));

  final GitSourceTransport _transport;
  final SkillDiscovery _discovery;
  final RevisionContentWorkerPort _contentWorker;
  final GitSourceParser _parser;
  final GitSourceTemporaryDirectoryFactory _temporaryDirectoryFactory;

  @override
  Future<app.SourceAcquisitionResult<app.AcquiredSource>> acquireGit(
    GitSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required app.SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) async => (await acquireGitBatch(<app.SourceAcquisitionRequest>[
    app.SourceAcquisitionRequest(
      source: source,
      selectedSkillNames: selectedSkillNames,
      options: options,
    ),
  ], cancellationToken: cancellationToken)).single;

  @override
  Future<List<app.SourceAcquisitionResult<app.AcquiredSource>>> acquireGitBatch(
    List<app.SourceAcquisitionRequest> requests, {
    required CancellationToken cancellationToken,
    void Function(
      int index,
      app.SourceAcquisitionResult<app.AcquiredSource> result,
    )?
    onResult,
  }) async {
    if (requests.isEmpty) return const [];
    final results =
        List<app.SourceAcquisitionResult<app.AcquiredSource>?>.filled(
          requests.length,
          null,
        );
    final groups = <_GitFetchKey, List<_GitBatchItem>>{};
    for (var index = 0; index < requests.length; index += 1) {
      if (cancellationToken.isCancelled) {
        final result = _cancelled();
        results[index] = result;
        onResult?.call(index, result);
        continue;
      }
      final request = requests[index];
      final source = request.source;
      if (source is! GitSourceDescriptor) {
        final result = app.SourceAcquisitionFailure<app.AcquiredSource>(
          code: app.SourceAcquisitionFailureCode.transportRejected,
          context: const <String, Object?>{'reason': 'invalidGitSource'},
        );
        results[index] = result;
        onResult?.call(index, result);
        continue;
      }
      final normalized = _normalizeSource(source);
      if (normalized == null) {
        final result = app.SourceAcquisitionFailure<app.AcquiredSource>(
          code: app.SourceAcquisitionFailureCode.transportRejected,
          context: const <String, Object?>{'reason': 'invalidGitSource'},
        );
        results[index] = result;
        onResult?.call(index, result);
        continue;
      }
      groups
          .putIfAbsent(
            _GitFetchKey(normalized.locator, normalized.ref),
            () => <_GitBatchItem>[],
          )
          .add(
            _GitBatchItem(
              index: index,
              source: normalized,
              selectedSkillNames: request.selectedSkillNames,
              options: request.options,
            ),
          );
    }

    final pending = ListQueue<List<_GitBatchItem>>.from(groups.values);
    Future<void> worker() async {
      while (pending.isNotEmpty && !cancellationToken.isCancelled) {
        final group = pending.removeFirst();
        await _acquireGroup(group, results, cancellationToken, onResult);
      }
    }

    await Future.wait<void>([
      for (var index = 0; index < groups.length.clamp(0, 2); index += 1)
        worker(),
    ]);
    if (cancellationToken.isCancelled) {
      for (var index = 0; index < results.length; index += 1) {
        if (results[index] != null) continue;
        final result = _cancelled();
        results[index] = result;
        onResult?.call(index, result);
      }
    }
    return <app.SourceAcquisitionResult<app.AcquiredSource>>[
      for (final result in results) result ?? _cancelled(),
    ];
  }

  GitSourceDescriptor? _normalizeSource(GitSourceDescriptor source) {
    final parsed = _parser.parseWithSelection(source.locator).valueOrNull;
    if (parsed == null) return null;
    final normalized = GitSourceDescriptor(
      locator: parsed.descriptor.locator,
      ref: source.ref ?? parsed.descriptor.ref,
      repositorySubpath: source.repositorySubpath.isEmpty
          ? parsed.descriptor.repositorySubpath
          : source.repositorySubpath,
      skillPath: source.skillPath.isEmpty
          ? parsed.skillFilter ?? ''
          : source.skillPath,
    );
    if (!_safeSelectionPath(normalized.repositorySubpath) ||
        !_safeSelectionPath(normalized.skillPath)) {
      return null;
    }
    return normalized;
  }

  Future<void> _acquireGroup(
    List<_GitBatchItem> items,
    List<app.SourceAcquisitionResult<app.AcquiredSource>?> results,
    CancellationToken cancellationToken,
    void Function(
      int index,
      app.SourceAcquisitionResult<app.AcquiredSource> result,
    )?
    onResult,
  ) async {
    Directory temporary;
    try {
      temporary = await _temporaryDirectoryFactory();
    } on FileSystemException {
      for (final item in items) {
        final result = app.SourceAcquisitionFailure<app.AcquiredSource>(
          code: app.SourceAcquisitionFailureCode.ioFailure,
        );
        results[item.index] = result;
        onResult?.call(item.index, result);
      }
      return;
    }
    GitBareSource? bare;
    try {
      final hooks = Directory(path.join(temporary.path, 'disabled-hooks'));
      await hooks.create(recursive: true);
      final source = items.first.source;
      final fetched = await _transport.fetchBare(
        GitSourceDescriptor(locator: source.locator, ref: source.ref),
        repositoryPath: path.join(temporary.path, 'source.git'),
        disabledHooksPath: hooks.path,
        cancellation: _GitCancellation(cancellationToken),
      );
      bare = fetched.valueOrNull;
      if (bare == null) {
        for (final item in items) {
          final result = _mapGitFailure(fetched.failureOrNull!);
          results[item.index] = result;
          onResult?.call(item.index, result);
        }
        return;
      }
      for (final item in items) {
        if (cancellationToken.isCancelled) {
          final result = _cancelled();
          results[item.index] = result;
          onResult?.call(item.index, result);
          continue;
        }
        final selection = Directory(
          path.join(temporary.path, 'selection-${item.index}'),
        );
        app.SourceAcquisitionResult<app.AcquiredSource> result;
        // One selection's staging failure must not fail the others sharing
        // this fetch.
        try {
          result = await _acquireFromBare(
            bare,
            item,
            selection,
            cancellationToken,
          );
        } on FileSystemException {
          result = app.SourceAcquisitionFailure<app.AcquiredSource>(
            code: app.SourceAcquisitionFailureCode.ioFailure,
          );
        }
        // Release each projection as soon as it is read, so staging never
        // holds one copy of the tree per Skill in the group.
        try {
          if (await selection.exists()) await selection.delete(recursive: true);
        } on FileSystemException {
          // The whole temporary directory is removed below.
        }
        results[item.index] = result;
        onResult?.call(item.index, result);
      }
    } on FileSystemException {
      for (final item in items) {
        if (results[item.index] != null) continue;
        final result = app.SourceAcquisitionFailure<app.AcquiredSource>(
          code: app.SourceAcquisitionFailureCode.ioFailure,
        );
        results[item.index] = result;
        onResult?.call(item.index, result);
      }
    } finally {
      if (bare != null) await _transport.dispose(bare);
      try {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      } on FileSystemException {
        // Source staging is never authoritative. Cleanup is best effort.
      }
    }
  }

  Future<app.SourceAcquisitionResult<app.AcquiredSource>> _acquireFromBare(
    GitBareSource bare,
    _GitBatchItem item,
    Directory discoveryRoot,
    CancellationToken cancellationToken,
  ) async {
    final source = item.source;
    final sourceTree = await _readSourceTree(
      bare,
      source.repositorySubpath,
      cancellationToken,
      metadataOnly: true,
    );
    final sourceEntries = sourceTree.valueOrNull;
    if (sourceEntries == null) {
      return app.copySourceAcquisitionFailure<
        List<SourceTreeEntry>,
        app.AcquiredSource
      >(sourceTree.failureOrNull!);
    }
    final resolvedResult = const SourceTreeSymlinkResolver(
      maximumFileCount:
          maximumGitRepositoryEntryCount * _projectionExpansionFactor,
      maximumByteSize:
          maximumNormalizedSkillByteSize * _projectionExpansionFactor,
    ).resolveWithOrigins(sourceEntries, skipInvalidLinks: true);
    final resolvedTree = resolvedResult.valueOrNull;
    if (resolvedTree == null) {
      return _mapSourceFailure(resolvedResult.failureOrNull!);
    }
    final resolvedEntries = resolvedTree.files;

    await discoveryRoot.create(recursive: true);
    await _writeDiscoveryProjection(discoveryRoot, resolvedEntries);
    final inspectionResult = await _discovery.inspect(
      discoveryRoot.path,
      subpath: source.repositorySubpath,
      canonicalDirectory: resolvedTree.canonicalDirectory,
      options: infrastructure.SkillDiscoveryOptions(
        includeInternal: item.options.includeInternal,
        fullDepth: item.options.fullDepth,
      ),
      cancellation: _SourceCancellation(cancellationToken),
    );
    final inspection = inspectionResult.valueOrNull;
    if (inspection == null) {
      return _mapSourceFailure(inspectionResult.failureOrNull!);
    }
    final selectors = item.selectedSkillNames.isNotEmpty
        ? item.selectedSkillNames
        : source.skillPath.isEmpty
        ? const <String>{}
        : <String>{source.skillPath};
    final selectedResult = inspection.select(selectors);
    final selected = selectedResult.valueOrNull;
    if (selected == null) {
      return _mapSourceFailure(selectedResult.failureOrNull!);
    }

    final acquired = <app.AcquiredSourceSkill>[];
    for (final candidate in selected) {
      if (cancellationToken.isCancelled) return _cancelled();
      final repositoryPath = path.posix.join(
        source.repositorySubpath,
        candidate.sourceRelativePath,
      );
      final prefix = repositoryPath.isEmpty || repositoryPath == '.'
          ? ''
          : '$repositoryPath/';
      final selectedTree = await _readSourceTree(
        bare,
        repositoryPath == '.' ? '' : repositoryPath,
        cancellationToken,
      );
      if (selectedTree.failureOrNull case final failure?) {
        return app.copySourceAcquisitionFailure<
          List<SourceTreeEntry>,
          app.AcquiredSource
        >(failure);
      }
      final resolvedContent = const SourceTreeSymlinkResolver()
          .resolveWithOrigins(
            selectedTree.valueOrNull!,
            selectedRoots: {repositoryPath},
          );
      if (resolvedContent.failureOrNull case final failure?) {
        return _mapSourceFailure(failure);
      }
      final contentEntries = <SkillContentEntry>[];
      for (final entry in resolvedContent.valueOrNull!.files) {
        final entryPath = utf8.decode(entry.pathBytes);
        final relativePath = prefix.isEmpty
            ? entryPath
            : entryPath.startsWith(prefix)
            ? entryPath.substring(prefix.length)
            : null;
        if (relativePath == null || relativePath.isEmpty) continue;
        contentEntries.add(
          SkillContentEntry.file(
            path: relativePath,
            bytes: entry.bytes,
            isExecutable: entry.isExecutable,
          ),
        );
      }
      final normalized = await _contentWorker.normalizeContent(
        contentEntries,
        maximumFileCount: maximumNormalizedSkillFileCount,
        maximumByteSize: maximumNormalizedSkillByteSize,
        isCancelled: () => cancellationToken.isCancelled,
      );
      final tree = normalized.valueOrNull;
      if (tree == null) {
        return _mapContentFailure(normalized.failureOrNull!);
      }
      acquired.add(
        app.AcquiredSourceSkill(
          provenance: GitSourceDescriptor(
            locator: source.locator,
            ref: source.ref,
            repositorySubpath: source.repositorySubpath,
            skillPath: candidate.sourceRelativePath,
          ),
          declaredName: candidate.declaredName,
          description: candidate.description,
          slotKey: candidate.slotKey,
          skillPath: candidate.sourceRelativePath,
          frontmatter: candidate.frontmatter.values,
          tree: tree,
          pluginName: candidate.pluginName,
        ),
      );
    }
    return app.SourceAcquisitionSuccess<app.AcquiredSource>(
      value: app.AcquiredSource(
        canonicalSource: source,
        skills: acquired,
        resolvedSourceRevision: bare.resolvedRevision,
      ),
    );
  }

  /// Reads the selected subtree and only the dependencies of its links. All
  /// paths stay repository-relative until links have been resolved. Discovery
  /// reads metadata and link dependencies; acquisition bounds one candidate.
  Future<app.SourceAcquisitionResult<List<SourceTreeEntry>>> _readSourceTree(
    GitBareSource bare,
    String selection,
    CancellationToken token, {
    bool metadataOnly = false,
  }) async {
    final nodes = <String, SourceTreeEntry>{};
    final pending = Queue<String>()..add(selection);
    final queried = <String>{};
    final covered = <String>{};
    final metadataTargets = <String>{};
    final metadataLinkChains = <String, Set<String>>{};
    var fileCount = 0;
    var fileBytes = 0;
    void requireMetadata(String target, Set<String> chain) {
      if (!metadataTargets.add(target)) return;
      metadataLinkChains[target] = chain;
      // A path previously visited as a directory dependency may now be needed
      // as a linked metadata file. Revisit it with that stronger requirement.
      queried.remove(target);
      pending.add(target);
    }

    while (pending.isNotEmpty) {
      if (token.isCancelled) return _treeFailure(_cancelled());
      final requested = pending.removeFirst();
      if (metadataOnly && metadataTargets.contains(requested)) {
        final ancestors =
            nodes.values
                .where(
                  (node) =>
                      node.kind == SourceTreeEntryKind.symbolicLink &&
                      (node.path == requested ||
                          path.posix.isWithin(node.path, requested)),
                )
                .toList()
              ..sort((a, b) => b.path.length.compareTo(a.path.length));
        if (ancestors.isNotEmpty) {
          final link = ancestors.first;
          final target = resolveSourceLinkTarget(link).valueOrNull;
          final chain = metadataLinkChains[requested] ?? const <String>{};
          if (target != null && !chain.contains(link.path)) {
            final suffix = path.posix.relative(requested, from: link.path);
            requireMetadata(
              suffix == '.' ? target : path.posix.join(target, suffix),
              {...chain, link.path},
            );
          }
        }
      }
      if (!queried.add(requested) ||
          covered.any(
            (scope) =>
                scope.isEmpty ||
                scope == requested ||
                path.posix.isWithin(scope, requested),
          )) {
        continue;
      }
      final listed = await _listSelection(bare, requested, token);
      if (listed.failureOrNull case final failure?) {
        return _treeFailure(_mapGitFailure(failure));
      }
      final listing = listed.valueOrNull!;
      if (listing.direct && !metadataOnly) covered.add(requested);
      final entries = listing.entries
          .where((entry) => !nodes.containsKey(entry.relativePath))
          .where(
            (entry) =>
                !metadataOnly ||
                entry.kind == GitTreeEntryKind.symbolicLink ||
                (entry.kind == GitTreeEntryKind.blob &&
                    (_isDiscoveryMetadata(entry.relativePath) ||
                        metadataTargets.contains(entry.relativePath))),
          )
          .toList();
      if (!metadataOnly) {
        if (entries.any((entry) => entry.kind == GitTreeEntryKind.gitlink)) {
          return _treeFailure(
            app.SourceAcquisitionFailure(
              code: app.SourceAcquisitionFailureCode.invalidSkill,
              context: {'reason': 'gitlinkNotAllowed'},
            ),
          );
        }
        fileCount += entries
            .where((entry) => entry.kind == GitTreeEntryKind.blob)
            .length;
        if (fileCount > maximumNormalizedSkillFileCount) {
          return _contentLimitExceeded('fileCount', fileCount);
        }
      }
      if (entries.isEmpty) continue;
      final blobs = await _readBlobs(
        bare,
        entries,
        token,
        metadataOnly: metadataOnly,
        alreadyReadBytes: fileBytes,
      );
      if (blobs.failureOrNull case final failure?) {
        return _treeFailure(_mapGitFailure(failure));
      }
      for (final entry in entries) {
        final bytes = blobs.valueOrNull![entry.relativePath] ?? Uint8List(0);
        if (!metadataOnly && entry.kind == GitTreeEntryKind.blob) {
          fileBytes += bytes.length;
        }
        final node = switch (entry.kind) {
          GitTreeEntryKind.blob => SourceTreeEntry.file(
            path: entry.relativePath,
            bytes: bytes,
            isExecutable: entry.executable,
          ),
          GitTreeEntryKind.symbolicLink => SourceTreeEntry.symbolicLink(
            path: entry.relativePath,
            targetBytes: bytes,
          ),
          GitTreeEntryKind.gitlink || GitTreeEntryKind.tree =>
            SourceTreeEntry.directory(path: entry.relativePath),
        };
        nodes[entry.relativePath] = node;
        if (node.kind == SourceTreeEntryKind.symbolicLink) {
          final target = resolveSourceLinkTarget(node);
          if (target.failureOrNull case final failure?) {
            if (metadataOnly) {
              nodes.remove(node.path);
              continue;
            }
            return _treeFailure(_mapSourceFailure(failure));
          }
          if (metadataOnly &&
              (_isDiscoveryMetadata(node.path) ||
                  metadataTargets.contains(node.path))) {
            final chain = metadataLinkChains[node.path] ?? const <String>{};
            if (!chain.contains(node.path)) {
              requireMetadata(target.valueOrNull!, {...chain, node.path});
            }
          } else {
            pending.add(target.valueOrNull!);
          }
        }
      }
    }
    return app.SourceAcquisitionSuccess(value: nodes.values.toList());
  }

  /// Lists [requested], or, when it is missing, only the links among its
  /// nearest existing ancestor that may contain it. The deepest existing
  /// ancestor decides: if it is not such a link, the path does not exist. The
  /// repository root is never listed on behalf of a missing path.
  Future<GitTransportResult<({List<GitTreeEntry> entries, bool direct})>>
  _listSelection(
    GitBareSource bare,
    String requested,
    CancellationToken token,
  ) async {
    var lookup = requested;
    while (true) {
      final listed = await _transport.listTree(
        bare,
        repositorySubpath: lookup,
        cancellation: _GitCancellation(token),
      );
      if (listed.failureOrNull case final failure?) {
        return GitTransportFailure(
          code: failure.code,
          context: failure.context,
          diagnostic: failure.diagnostic,
        );
      }
      final entries = listed.valueOrNull!;
      if (lookup == requested && (entries.isNotEmpty || lookup.isEmpty)) {
        return GitTransportSuccess((entries: entries, direct: true));
      }
      if (entries.isNotEmpty) {
        return GitTransportSuccess((
          entries: [
            for (final entry in entries)
              if (entry.kind == GitTreeEntryKind.symbolicLink &&
                  path.posix.isWithin(entry.relativePath, requested))
                entry,
          ],
          direct: false,
        ));
      }
      final parent = path.posix.dirname(lookup);
      if (parent == '.') {
        return GitTransportSuccess((entries: const [], direct: false));
      }
      lookup = parent;
    }
  }

  Future<GitTransportResult<Map<String, Uint8List>>> _readBlobs(
    GitBareSource bare,
    List<GitTreeEntry> entries,
    CancellationToken cancellationToken, {
    bool metadataOnly = false,
    int alreadyReadBytes = 0,
  }) async {
    // Link targets are metadata, not normalized Skill bytes. Read them in a
    // separate batch so they cannot consume the candidate content budget.
    final links = entries
        .where((entry) => entry.kind == GitTreeEntryKind.symbolicLink)
        .toList();
    if (!metadataOnly && links.isNotEmpty) {
      final linkResult = await _readBlobs(
        bare,
        links,
        cancellationToken,
        metadataOnly: true,
      );
      if (linkResult.failureOrNull case final failure?) {
        return failure;
      }
      final fileResult = await _readBlobs(
        bare,
        entries
            .where((entry) => entry.kind != GitTreeEntryKind.symbolicLink)
            .toList(),
        cancellationToken,
        alreadyReadBytes: alreadyReadBytes,
      );
      if (fileResult.failureOrNull case final failure?) {
        return failure;
      }
      return GitTransportSuccess({
        ...linkResult.valueOrNull!,
        ...fileResult.valueOrNull!,
      });
    }
    // Metadata discovery is repository-wide. Batch requests up to the
    // transport's per-call limit, then isolate entry budgets only when their
    // aggregate bytes exceed the transport budget.
    if (metadataOnly && entries.length > 1) {
      final result = <String, Uint8List>{};
      for (
        var start = 0;
        start < entries.length;
        start += maximumNormalizedSkillFileCount
      ) {
        if (cancellationToken.isCancelled) {
          return GitTransportFailure(code: GitTransportFailureCode.cancelled);
        }
        final end = (start + maximumNormalizedSkillFileCount).clamp(
          0,
          entries.length,
        );
        final chunk = entries.sublist(start, end);
        final batch = await _readBlobBatch(
          bare,
          chunk,
          cancellationToken,
          metadataOnly: true,
        );
        if (batch.failureOrNull case final failure?) {
          if (failure.context['reason'] != 'blobBytesExceededLimit') {
            return failure;
          }
          // Discard any partial batch output and retry the whole chunk. Each
          // entry receives the same byte budget it had before batching.
          for (final entry in chunk) {
            if (cancellationToken.isCancelled) {
              return GitTransportFailure(
                code: GitTransportFailureCode.cancelled,
              );
            }
            final blob = await _readBlobs(
              bare,
              [entry],
              cancellationToken,
              metadataOnly: true,
            );
            if (blob.failureOrNull case final failure?) {
              return failure;
            }
            result.addAll(blob.valueOrNull!);
          }
        } else {
          result.addAll(batch.valueOrNull!);
        }
      }
      return GitTransportSuccess(result);
    }
    return _readBlobBatch(
      bare,
      entries,
      cancellationToken,
      metadataOnly: metadataOnly,
      alreadyReadBytes: alreadyReadBytes,
    );
  }

  Future<GitTransportResult<Map<String, Uint8List>>> _readBlobBatch(
    GitBareSource bare,
    List<GitTreeEntry> entries,
    CancellationToken cancellationToken, {
    required bool metadataOnly,
    int alreadyReadBytes = 0,
  }) async {
    final requests = [
      for (final entry in entries)
        if (entry.kind != GitTreeEntryKind.tree)
          GitBlobRequest(
            objectId: entry.objectId,
            relativePath: entry.relativePath,
          ),
    ];
    var byteCount = alreadyReadBytes;
    final limitCancellation = CancellationSource();
    int? exceededAt;
    final builders = <String, BytesBuilder>{};
    final completed = <String>{};
    final streamed = await _transport.streamBlobs(
      bare,
      requests: requests,
      cancellation: _GitCancellation(
        cancellationToken,
        limitCancellation.token,
      ),
      onChunk: (chunk) async {
        byteCount += chunk.bytes.length;
        if (!metadataOnly && byteCount > maximumNormalizedSkillByteSize) {
          exceededAt ??= byteCount;
          await limitCancellation.cancel();
          return;
        }
        builders
            .putIfAbsent(chunk.request.relativePath, () => BytesBuilder())
            .add(chunk.bytes);
        if (chunk.isLast) completed.add(chunk.request.relativePath);
      },
    );
    // Preserve the transport reason for aggregate metadata failures so the
    // caller can retry them entry by entry. Single-entry failures retain the
    // existing typed Skill content-limit mapping below.
    if (metadataOnly &&
        entries.length > 1 &&
        streamed.failureOrNull?.context['reason'] == 'blobBytesExceededLimit') {
      final failure = streamed.failureOrNull!;
      return GitTransportFailure(
        code: failure.code,
        context: failure.context,
        diagnostic: failure.diagnostic,
      );
    }
    if (exceededAt != null ||
        streamed.failureOrNull?.context['reason'] == 'blobBytesExceededLimit') {
      return GitTransportFailure(
        code: GitTransportFailureCode.invalidOutput,
        context: {
          'reason': 'skillContentLimitExceeded',
          'limit': 'byteSize',
          'actual': exceededAt ?? maximumNormalizedSkillByteSize + 1,
          'actualIsLowerBound': true,
          'maximumFileCount': maximumNormalizedSkillFileCount,
          'maximumByteSize': maximumNormalizedSkillByteSize,
        },
      );
    }
    if (streamed.failureOrNull case final failure?) {
      return GitTransportFailure<Map<String, Uint8List>>(
        code: failure.code,
        context: failure.context,
        diagnostic: failure.diagnostic,
      );
    }
    if (completed.length != requests.length) {
      return GitTransportFailure<Map<String, Uint8List>>(
        code: GitTransportFailureCode.invalidOutput,
        context: const <String, Object?>{'reason': 'incompleteBlobBatch'},
      );
    }
    return GitTransportSuccess<Map<String, Uint8List>>({
      for (final request in requests)
        request.relativePath: builders[request.relativePath]!.takeBytes(),
    });
  }

  Future<void> _writeDiscoveryProjection(
    Directory root,
    List<SkillContentEntry> entries,
  ) async {
    for (final entry in entries) {
      final entryPath = utf8.decode(entry.pathBytes);
      final segments = path.posix.split(entryPath);
      final isSkill = segments.last == 'SKILL.md';
      final isPluginMetadata =
          segments.contains('.claude-plugin') &&
          segments.last.endsWith('.json');
      if (!isSkill && !isPluginMetadata) continue;
      final destination = File(path.joinAll([root.path, ...segments]));
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(entry.bytes, flush: true);
    }
  }
}

app.SourceAcquisitionFailure<app.AcquiredSource> _mapGitFailure(
  GitTransportFailure<Object?> failure,
) => app.SourceAcquisitionFailure<app.AcquiredSource>(
  code: failure.context['reason'] == 'skillContentLimitExceeded'
      ? app.SourceAcquisitionFailureCode.skillContentLimitExceeded
      : switch (failure.code) {
          GitTransportFailureCode.rejected =>
            app.SourceAcquisitionFailureCode.transportRejected,
          GitTransportFailureCode.unavailable =>
            app.SourceAcquisitionFailureCode.gitUnavailable,
          GitTransportFailureCode.developerToolsRequired =>
            app.SourceAcquisitionFailureCode.developerToolsRequired,
          GitTransportFailureCode.authenticationRequired =>
            app.SourceAcquisitionFailureCode.sourceAuthenticationRequired,
          GitTransportFailureCode.cancelled =>
            app.SourceAcquisitionFailureCode.operationCancelled,
          GitTransportFailureCode.ioFailure =>
            app.SourceAcquisitionFailureCode.ioFailure,
          GitTransportFailureCode.timedOut =>
            app.SourceAcquisitionFailureCode.gitTimedOut,
          GitTransportFailureCode.commandFailed ||
          GitTransportFailureCode.invalidOutput =>
            app.SourceAcquisitionFailureCode.gitFailed,
        },
  context: failure.context,
);

app.SourceAcquisitionFailure<app.AcquiredSource> _mapSourceFailure(
  infrastructure.SourceFailure<Object?> failure,
) => app.SourceAcquisitionFailure<app.AcquiredSource>(
  code: switch (failure.code) {
    infrastructure.SourceFailureCode.cancelled =>
      app.SourceAcquisitionFailureCode.operationCancelled,
    infrastructure.SourceFailureCode.unavailable =>
      app.SourceAcquisitionFailureCode.sourceUnavailable,
    infrastructure.SourceFailureCode.rejected =>
      app.SourceAcquisitionFailureCode.transportRejected,
    infrastructure.SourceFailureCode.notFound =>
      app.SourceAcquisitionFailureCode.skillNotFound,
    infrastructure.SourceFailureCode.contentLimitExceeded =>
      app.SourceAcquisitionFailureCode.skillContentLimitExceeded,
    infrastructure.SourceFailureCode.httpFailure =>
      app.SourceAcquisitionFailureCode.httpFailure,
    infrastructure.SourceFailureCode.digestMismatch =>
      app.SourceAcquisitionFailureCode.digestMismatch,
    infrastructure.SourceFailureCode.archiveInvalid =>
      app.SourceAcquisitionFailureCode.archiveInvalid,
    infrastructure.SourceFailureCode.invalidSource ||
    infrastructure.SourceFailureCode.contentInvalid =>
      app.SourceAcquisitionFailureCode.invalidSkill,
    infrastructure.SourceFailureCode.ioFailure =>
      app.SourceAcquisitionFailureCode.ioFailure,
  },
  context: failure.context,
);

app.SourceAcquisitionFailure<app.AcquiredSource> _mapContentFailure(
  SkillContentFailure<Object?> failure,
) => app.SourceAcquisitionFailure<app.AcquiredSource>(
  code: switch (failure.code) {
    SkillContentFailureCode.cancelled =>
      app.SourceAcquisitionFailureCode.operationCancelled,
    SkillContentFailureCode.limitExceeded =>
      app.SourceAcquisitionFailureCode.skillContentLimitExceeded,
    SkillContentFailureCode.invalidContent =>
      app.SourceAcquisitionFailureCode.invalidSkill,
    SkillContentFailureCode.unavailable =>
      app.SourceAcquisitionFailureCode.sourceUnavailable,
  },
  context: failure.context,
);

app.SourceAcquisitionFailure<app.AcquiredSource> _cancelled() =>
    app.SourceAcquisitionFailure<app.AcquiredSource>(
      code: app.SourceAcquisitionFailureCode.operationCancelled,
    );

app.SourceAcquisitionFailure<List<SourceTreeEntry>> _treeFailure(
  app.SourceAcquisitionFailure<app.AcquiredSource> failure,
) =>
    app.copySourceAcquisitionFailure<app.AcquiredSource, List<SourceTreeEntry>>(
      failure,
    );

app.SourceAcquisitionFailure<List<SourceTreeEntry>> _contentLimitExceeded(
  String limit,
  int actual,
) => app.SourceAcquisitionFailure<List<SourceTreeEntry>>(
  code: app.SourceAcquisitionFailureCode.skillContentLimitExceeded,
  context: {
    'limit': limit,
    'actual': actual,
    'actualIsLowerBound': true,
    'maximumFileCount': maximumNormalizedSkillFileCount,
    'maximumByteSize': maximumNormalizedSkillByteSize,
  },
);

final class _GitFetchKey {
  const _GitFetchKey(this.locator, this.ref);

  final String locator;
  final String? ref;

  @override
  bool operator ==(Object other) =>
      other is _GitFetchKey && locator == other.locator && ref == other.ref;

  @override
  int get hashCode => Object.hash(locator, ref);
}

final class _GitBatchItem {
  const _GitBatchItem({
    required this.index,
    required this.source,
    required this.selectedSkillNames,
    required this.options,
  });

  final int index;
  final GitSourceDescriptor source;
  final Set<String> selectedSkillNames;
  final app.SourceAcquisitionOptions options;
}

final class _GitCancellation implements GitCancellationSignal {
  const _GitCancellation(this._token, [this._limitToken]);

  final CancellationToken _token;
  final CancellationToken? _limitToken;

  @override
  bool get isCancelled =>
      _token.isCancelled || (_limitToken?.isCancelled ?? false);

  @override
  Future<void> get whenCancelled => _limitToken == null
      ? _token.whenCancelled
      : Future.any([_token.whenCancelled, _limitToken.whenCancelled]);
}

final class _SourceCancellation
    implements infrastructure.SourceCancellationSignal {
  const _SourceCancellation(this._token);

  final CancellationToken _token;

  @override
  bool get isCancelled => _token.isCancelled;

  @override
  Future<void> get whenCancelled => _token.whenCancelled;
}

bool _safeSelectionPath(String value) =>
    value.isEmpty ||
    (!value.startsWith('/') &&
        !value.startsWith(r'\') &&
        !value.contains(r'\') &&
        !value.contains('\u0000') &&
        value
            .split('/')
            .every(
              (segment) =>
                  segment.isNotEmpty && segment != '.' && segment != '..',
            ));

bool _isDiscoveryMetadata(String entryPath) {
  final segments = path.posix.split(entryPath);
  return segments.last == 'SKILL.md' ||
      (segments.contains('.claude-plugin') && segments.last.endsWith('.json'));
}
