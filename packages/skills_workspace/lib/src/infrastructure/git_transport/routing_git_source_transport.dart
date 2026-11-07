import '../../domain/source_descriptor.dart';
import 'git_source_transport.dart';
import 'git_transport_result.dart';
import 'libgit2_source_transport.dart';
import 'system_git_availability.dart';

/// Routes each Git Source to the embedded libgit2 or to system Git
/// (ADR-0106).
///
/// HTTPS locators go to libgit2 first, so public Sources need no system Git.
/// SSH, scp-style, and local-path locators go to system Git. When libgit2
/// fails for a reason system Git may overcome — the server wants credentials,
/// or the network, TLS, proxy, or requested ref failed — the fetch is retried
/// with system Git, which reuses the user's own credentials and Git
/// configuration, provided system Git is available and the operation was not
/// cancelled.
final class RoutingGitSourceTransport implements GitSourceTransport {
  RoutingGitSourceTransport({
    required Libgit2SourceTransport libgit2,
    required GitSourceTransport systemGit,
    required SystemGitAvailability systemGitAvailability,
  }) : _libgit2 = libgit2,
       _systemGit = systemGit,
       _systemGitAvailability = systemGitAvailability;

  final Libgit2SourceTransport _libgit2;
  final GitSourceTransport _systemGit;
  final SystemGitAvailability _systemGitAvailability;
  final _owners = <String, GitSourceTransport>{};

  static const _fallbackReasons = <String>{
    'network',
    'certificate',
    'tls',
    'proxy',
    'refNotFound',
    'runtime',
  };

  @override
  Future<GitTransportResult<GitBareSource>> fetchBare(
    GitSourceDescriptor source, {
    required String repositoryPath,
    required String disabledHooksPath,
    required GitCancellationSignal cancellation,
  }) async {
    if (!_libgit2.supportsLocator(source.locator)) {
      return _fetchWith(
        _systemGit,
        source,
        repositoryPath: repositoryPath,
        disabledHooksPath: disabledHooksPath,
        cancellation: cancellation,
      );
    }
    final primary = await _fetchWith(
      _libgit2,
      source,
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      cancellation: cancellation,
    );
    final failure = primary.failureOrNull;
    if (failure == null ||
        cancellation.isCancelled ||
        !_permitsFallback(failure) ||
        !await _systemGitAvailability.isAvailable()) {
      return primary;
    }
    final fallback = await _fetchWith(
      _systemGit,
      source,
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      cancellation: cancellation,
    );
    final secondary = fallback.failureOrNull;
    if (secondary != null &&
        secondary.context['reason'] == null &&
        failure.context['reason'] != null) {
      return GitTransportFailure(
        code: secondary.code,
        context: {
          ...secondary.context,
          'reason': failure.context['reason'],
          'transport': 'systemGit',
          'primaryTransport': 'libgit2',
        },
        diagnostic: secondary.diagnostic,
      );
    }
    return fallback;
  }

  @override
  Future<GitTransportResult<List<GitTreeEntry>>> listTree(
    GitBareSource source, {
    required String repositorySubpath,
    required GitCancellationSignal cancellation,
  }) => _ownerOf(source).listTree(
    source,
    repositorySubpath: repositorySubpath,
    cancellation: cancellation,
  );

  @override
  Future<GitTransportResult<void>> streamBlobs(
    GitBareSource source, {
    required List<GitBlobRequest> requests,
    required GitBlobChunkConsumer onChunk,
    required GitCancellationSignal cancellation,
  }) => _ownerOf(source).streamBlobs(
    source,
    requests: requests,
    onChunk: onChunk,
    cancellation: cancellation,
  );

  @override
  Future<void> dispose(GitBareSource source) {
    final owner = _ownerOf(source);
    _owners.remove(source.repositoryPath);
    return owner.dispose(source);
  }

  Future<GitTransportResult<GitBareSource>> _fetchWith(
    GitSourceTransport transport,
    GitSourceDescriptor source, {
    required String repositoryPath,
    required String disabledHooksPath,
    required GitCancellationSignal cancellation,
  }) async {
    final result = await transport.fetchBare(
      source,
      repositoryPath: repositoryPath,
      disabledHooksPath: disabledHooksPath,
      cancellation: cancellation,
    );
    final fetched = result.valueOrNull;
    if (fetched != null) _owners[fetched.repositoryPath] = transport;
    return result;
  }

  // A bare Source this router did not fetch can only be a system Git export.
  GitSourceTransport _ownerOf(GitBareSource source) =>
      _owners[source.repositoryPath] ?? _systemGit;

  static bool _permitsFallback(GitTransportFailure<GitBareSource> failure) =>
      switch (failure.code) {
        GitTransportFailureCode.authenticationRequired ||
        GitTransportFailureCode.timedOut => true,
        GitTransportFailureCode.commandFailed ||
        GitTransportFailureCode.unavailable => _fallbackReasons.contains(
          failure.context['reason'],
        ),
        _ => false,
      };
}
