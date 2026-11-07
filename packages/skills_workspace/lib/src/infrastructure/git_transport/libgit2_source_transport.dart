import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../domain/source_descriptor.dart';
import '../../application/ports/source_transport_native_port.dart';
import 'git_proxy_choice.dart';
import 'git_redaction.dart';
import 'git_source_parser.dart';
import 'git_source_transport.dart';
import 'git_transport_result.dart';
import 'git_tree_listing.dart';

/// Source transport backed by the package's embedded, networked libgit2
/// (ADR-0106).
///
/// It fetches only canonical, credential-free `https://` locators, so public
/// Git Sources install on hosts without system Git. Like the system Git
/// transport it creates no working tree, runs no hooks or filters, fetches a
/// single commit at depth 1, and applies the shared Source tree rules.
final class Libgit2SourceTransport implements GitSourceTransport {
  Libgit2SourceTransport({
    required SourceTransportNativePort native,
    GitProxySelector proxySelector = directGitProxy,
    this.fetchTimeout = const Duration(minutes: 2),
    this.maximumFileCount = 1000,
    this.maximumRepositoryEntryCount = maximumGitRepositoryEntryCount,
    this.maximumByteSize = 50 * 1024 * 1024,
    this.allowLoopbackHttpForTesting = false,
  }) : _native = native,
       _proxySelector = proxySelector {
    if (fetchTimeout <= Duration.zero) {
      throw ArgumentError.value(fetchTimeout, 'fetchTimeout');
    }
    if (maximumRepositoryEntryCount <= 0 ||
        maximumFileCount <= 0 ||
        maximumByteSize <= 0) {
      throw ArgumentError('Git source limits must be positive.');
    }
  }

  final SourceTransportNativePort _native;
  final GitProxySelector _proxySelector;
  final Duration fetchTimeout;
  final int maximumFileCount;
  final int maximumRepositoryEntryCount;
  final int maximumByteSize;

  /// Also accepts `http://` loopback locators. Only tests serve Sources that
  /// way; production locators must be HTTPS.
  final bool allowLoopbackHttpForTesting;

  /// Whether this transport can fetch [locator].
  bool supportsLocator(String locator) => _remoteFor(locator) != null;

  @override
  Future<GitTransportResult<GitBareSource>> fetchBare(
    GitSourceDescriptor source, {
    required String repositoryPath,
    required String disabledHooksPath,
    required GitCancellationSignal cancellation,
  }) async {
    final locator = redactGitLocator(source.locator);
    if (cancellation.isCancelled) {
      return _fetchFailure(GitTransportFailureCode.cancelled, locator);
    }
    final remote = _remoteFor(source.locator);
    if (remote == null) {
      return _fetchFailure(
        GitTransportFailureCode.rejected,
        locator,
        reason: 'unsupportedLocator',
      );
    }

    final GitProxyChoice proxy;
    try {
      proxy = await _proxySelector(remote);
    } on Object {
      return _fetchFailure(
        GitTransportFailureCode.commandFailed,
        locator,
        reason: 'proxy',
      );
    }

    final cancelFlag = calloc<ffi.Int32>();
    var timedOut = false;
    final timer = Timer(fetchTimeout, () {
      timedOut = true;
      cancelFlag.value = 1;
    });
    final cancellationSubscription = cancellation.whenCancelled
        .asStream()
        .listen((_) => cancelFlag.value = 1, onError: (Object _) {});
    SourceTransportFetchOutcome outcome;
    try {
      outcome = await _native.fetch(
        repositoryPath: repositoryPath,
        url: source.locator,
        ref: source.ref,
        proxyMode: switch (proxy) {
          GitProxyDirect() => SourceTransportProxyMode.none,
          GitProxyFromEnvironment() => SourceTransportProxyMode.environment,
          GitProxySpecified() => SourceTransportProxyMode.specified,
        },
        proxyUrl: switch (proxy) {
          GitProxySpecified(:final url) => url,
          _ => null,
        },
        cancelFlagAddress: cancelFlag.address,
      );
    } on Object {
      outcome = (status: SourceTransportStatus.runtimeFailure, commit: null);
    } finally {
      timer.cancel();
      await cancellationSubscription.cancel();
    }
    // The native call has returned, so nothing reads the flag any more.
    calloc.free(cancelFlag);

    final commit = outcome.commit;
    if (outcome.status == SourceTransportStatus.ok &&
        commit != null &&
        isGitObjectId(commit)) {
      return GitTransportSuccess(
        GitBareSource(
          repositoryPath: repositoryPath,
          resolvedRevision: commit,
          disabledHooksPath: disabledHooksPath,
        ),
      );
    }
    await _deleteRepository(repositoryPath);
    if (outcome.status == SourceTransportStatus.cancelled) {
      return _fetchFailure(
        timedOut
            ? GitTransportFailureCode.timedOut
            : GitTransportFailureCode.cancelled,
        locator,
      );
    }
    return switch (outcome.status) {
      SourceTransportStatus.ok => _fetchFailure(
        GitTransportFailureCode.invalidOutput,
        locator,
        reason: 'invalidFetchedRevision',
      ),
      SourceTransportStatus.authenticationRequired => _fetchFailure(
        GitTransportFailureCode.authenticationRequired,
        locator,
      ),
      SourceTransportStatus.timedOut => _fetchFailure(
        GitTransportFailureCode.timedOut,
        locator,
      ),
      SourceTransportStatus.certificateFailure => _fetchFailure(
        GitTransportFailureCode.commandFailed,
        locator,
        reason: 'certificate',
      ),
      SourceTransportStatus.tlsFailure => _fetchFailure(
        GitTransportFailureCode.commandFailed,
        locator,
        reason: 'tls',
      ),
      SourceTransportStatus.networkFailure => _fetchFailure(
        GitTransportFailureCode.commandFailed,
        locator,
        reason: 'network',
      ),
      SourceTransportStatus.refNotFound => _fetchFailure(
        GitTransportFailureCode.commandFailed,
        locator,
        reason: 'refNotFound',
      ),
      SourceTransportStatus.invalidArgument => _fetchFailure(
        GitTransportFailureCode.rejected,
        locator,
        reason: 'invalidLocator',
      ),
      SourceTransportStatus.runtimeFailure => _fetchFailure(
        GitTransportFailureCode.unavailable,
        locator,
        reason: 'runtime',
      ),
      SourceTransportStatus.repositoryFailure => _fetchFailure(
        GitTransportFailureCode.ioFailure,
        locator,
        reason: 'repository',
      ),
      _ => _fetchFailure(
        GitTransportFailureCode.invalidOutput,
        locator,
        reason: outcome.status.name,
      ),
    };
  }

  @override
  Future<GitTransportResult<List<GitTreeEntry>>> listTree(
    GitBareSource source, {
    required String repositorySubpath,
    required GitCancellationSignal cancellation,
  }) async {
    if (cancellation.isCancelled) {
      return GitTransportFailure<List<GitTreeEntry>>(
        code: GitTransportFailureCode.cancelled,
        context: _context('listTree'),
      );
    }
    SourceTransportBytesOutcome outcome;
    try {
      outcome = await _native.listTree(
        repositoryPath: source.repositoryPath,
        commit: source.resolvedRevision,
        subpath: repositorySubpath,
      );
    } on Object {
      outcome = (status: SourceTransportStatus.runtimeFailure, bytes: null);
    }
    if (cancellation.isCancelled) {
      return GitTransportFailure<List<GitTreeEntry>>(
        code: GitTransportFailureCode.cancelled,
        context: _context('listTree'),
      );
    }
    final bytes = outcome.bytes;
    if (outcome.status != SourceTransportStatus.ok || bytes == null) {
      return GitTransportFailure<List<GitTreeEntry>>(
        code: GitTransportFailureCode.invalidOutput,
        context: _context('listTree', reason: 'treeUnavailable'),
      );
    }
    return parseGitTreeListing(
      bytes,
      repositorySubpath: repositorySubpath,
      maximumRepositoryEntryCount: maximumRepositoryEntryCount,
    );
  }

  @override
  Future<GitTransportResult<void>> streamBlobs(
    GitBareSource source, {
    required List<GitBlobRequest> requests,
    required GitBlobChunkConsumer onChunk,
    required GitCancellationSignal cancellation,
  }) async {
    if (cancellation.isCancelled) {
      return GitTransportFailure<void>(
        code: GitTransportFailureCode.cancelled,
        context: _context('readBlobs'),
      );
    }
    if (requests.isEmpty) return const GitTransportSuccess<void>(null);
    if (requests.length > maximumFileCount) {
      return GitTransportFailure<void>(
        code: GitTransportFailureCode.invalidOutput,
        context: <String, Object?>{
          ..._context('readBlobs', reason: 'fileCountExceeded'),
          'maximum': maximumFileCount,
        },
      );
    }

    final cancelFlag = calloc<ffi.Int32>();
    final cancellationSubscription = cancellation.whenCancelled
        .asStream()
        .listen((_) => cancelFlag.value = 1, onError: (Object _) {});
    SourceTransportBlobsOutcome outcome;
    try {
      outcome = await _native.readBlobs(
        repositoryPath: source.repositoryPath,
        objectIds: [for (final request in requests) request.objectId],
        maximumTotalBytes: maximumByteSize,
        cancelFlagAddress: cancelFlag.address,
      );
    } on Object {
      outcome = (status: SourceTransportStatus.runtimeFailure, blobs: null);
    } finally {
      await cancellationSubscription.cancel();
    }
    calloc.free(cancelFlag);

    final blobs = outcome.blobs;
    if (outcome.status == SourceTransportStatus.cancelled ||
        cancellation.isCancelled) {
      return GitTransportFailure<void>(
        code: GitTransportFailureCode.cancelled,
        context: _context('readBlobs'),
      );
    }
    if (outcome.status != SourceTransportStatus.ok ||
        blobs == null ||
        blobs.length != requests.length) {
      return GitTransportFailure<void>(
        code: GitTransportFailureCode.invalidOutput,
        context: _context(
          'readBlobs',
          reason: outcome.status == SourceTransportStatus.limitExceeded
              ? 'blobBytesExceededLimit'
              : 'blobUnavailable',
        ),
      );
    }

    try {
      for (var index = 0; index < requests.length; index += 1) {
        await _emitChunks(requests[index], blobs[index], onChunk, cancellation);
      }
    } on _ChunkingCancelled {
      return GitTransportFailure<void>(
        code: GitTransportFailureCode.cancelled,
        context: _context('readBlobs'),
      );
    } on Object {
      return GitTransportFailure<void>(
        code: GitTransportFailureCode.ioFailure,
        context: _context('readBlobs', reason: 'blobConsumerFailed'),
      );
    }
    return const GitTransportSuccess<void>(null);
  }

  @override
  Future<void> dispose(GitBareSource source) =>
      _deleteRepository(source.repositoryPath);

  Uri? _remoteFor(String locator) {
    final uri = Uri.tryParse(locator);
    if (uri == null || uri.userInfo.isNotEmpty || uri.hasQuery) return null;
    if (uri.scheme == 'https') {
      final parsed = const GitSourceParser().parse(locator).valueOrNull;
      return parsed != null && parsed.locator == locator ? uri : null;
    }
    if (allowLoopbackHttpForTesting &&
        uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' || uri.host == 'localhost')) {
      return uri;
    }
    return null;
  }

  Future<void> _emitChunks(
    GitBlobRequest request,
    Uint8List bytes,
    GitBlobChunkConsumer onChunk,
    GitCancellationSignal cancellation,
  ) async {
    const chunkSize = 64 * 1024;
    if (bytes.isEmpty) {
      await onChunk(GitBlobChunk(request: request, bytes: bytes, isLast: true));
      return;
    }
    for (var start = 0; start < bytes.length; start += chunkSize) {
      if (cancellation.isCancelled) throw const _ChunkingCancelled();
      final end = start + chunkSize < bytes.length
          ? start + chunkSize
          : bytes.length;
      await onChunk(
        GitBlobChunk(
          request: request,
          bytes: Uint8List.sublistView(bytes, start, end),
          isLast: end == bytes.length,
        ),
      );
    }
  }

  Future<void> _deleteRepository(String path) async {
    try {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Temporary source cleanup is best effort, as for system Git.
    }
  }
}

final class _ChunkingCancelled implements Exception {
  const _ChunkingCancelled();
}

Map<String, Object?> _context(String operation, {String? reason}) =>
    <String, Object?>{
      'operation': operation,
      'transport': 'libgit2',
      'reason': ?reason,
    };

GitTransportFailure<GitBareSource> _fetchFailure(
  GitTransportFailureCode code,
  String redactedLocator, {
  String? reason,
}) => GitTransportFailure<GitBareSource>(
  code: code,
  context: <String, Object?>{
    ..._context('fetch', reason: reason),
    'locator': redactedLocator,
  },
);
