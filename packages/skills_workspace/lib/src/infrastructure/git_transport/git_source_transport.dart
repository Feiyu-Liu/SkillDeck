import 'dart:typed_data';

import '../../domain/source_descriptor.dart';
import 'git_transport_result.dart';

/// A cancellation signal consumed only by the private Git transport.
abstract interface class GitCancellationSignal {
  bool get isCancelled;

  Future<void> get whenCancelled;
}

/// A fetched source that exists only as an object database, never a checkout.
final class GitBareSource {
  GitBareSource({
    required this.repositoryPath,
    required this.resolvedRevision,
    required this.disabledHooksPath,
  }) {
    if (repositoryPath.trim().isEmpty) {
      throw ArgumentError.value(
        repositoryPath,
        'repositoryPath',
        'must not be empty',
      );
    }
    if (disabledHooksPath.trim().isEmpty) {
      throw ArgumentError.value(
        disabledHooksPath,
        'disabledHooksPath',
        'must not be empty',
      );
    }
    _requireObjectId(resolvedRevision, 'resolvedRevision');
  }

  final String repositoryPath;
  final String resolvedRevision;
  final String disabledHooksPath;
}

const maximumGitRepositoryEntryCount = 50000;

enum GitTreeEntryKind { blob, symbolicLink, tree, gitlink }

/// Metadata returned by `git ls-tree`; gitlinks are retained for selected-root validation.
final class GitTreeEntry {
  GitTreeEntry({
    required this.relativePath,
    required this.objectId,
    required this.kind,
    required this.executable,
  }) {
    _requireSafeRelativePath(relativePath);
    _requireObjectId(objectId, 'objectId');
  }

  final String relativePath;
  final String objectId;
  final GitTreeEntryKind kind;
  final bool executable;
}

final class GitBlobRequest {
  GitBlobRequest({required this.objectId, required this.relativePath}) {
    _requireObjectId(objectId, 'objectId');
    _requireSafeRelativePath(relativePath);
  }

  final String objectId;
  final String relativePath;
}

final class GitBlobChunk {
  GitBlobChunk({
    required this.request,
    required this.bytes,
    required this.isLast,
  });

  final GitBlobRequest request;
  final Uint8List bytes;
  final bool isLast;
}

typedef GitBlobChunkConsumer = Future<void> Function(GitBlobChunk chunk);

/// Private seam for the future bare/no-checkout source implementation.
///
/// Implementations acquire with system Git, enumerate with `ls-tree`, and
/// stream blobs through one `cat-file --batch` session. They must never expose
/// a working-tree checkout or execute content from the source.
abstract interface class GitSourceTransport {
  Future<GitTransportResult<GitBareSource>> fetchBare(
    GitSourceDescriptor source, {
    required String repositoryPath,
    required String disabledHooksPath,
    required GitCancellationSignal cancellation,
  });

  /// Lists the selection with repository-relative paths. A selection may name
  /// a link itself, so acquisition can resolve its contained dependencies.
  Future<GitTransportResult<List<GitTreeEntry>>> listTree(
    GitBareSource source, {
    required String repositorySubpath,
    required GitCancellationSignal cancellation,
  });

  Future<GitTransportResult<void>> streamBlobs(
    GitBareSource source, {
    required List<GitBlobRequest> requests,
    required GitBlobChunkConsumer onChunk,
    required GitCancellationSignal cancellation,
  });

  Future<void> dispose(GitBareSource source);
}

void _requireObjectId(String value, String name) {
  if (!RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a Git object ID');
  }
}

void _requireSafeRelativePath(String value) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.startsWith(r'\') ||
      value.contains(r'\') ||
      value.split('/').any((segment) => segment.isEmpty || segment == '..')) {
    throw ArgumentError.value(
      value,
      'relativePath',
      'must be a normalized POSIX relative path',
    );
  }
}
