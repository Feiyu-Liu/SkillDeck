import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/ports/source_transport_native_port.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_commands.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/libgit2_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/routing_git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_availability.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_source_transport.dart';
import 'package:skills_workspace/src/native/source_transport/source_transport_native.dart';
import 'package:test/test.dart';

import '../../support/git_transport/git_http_backend_server.dart';
import '../../support/git_transport/git_source_fixture.dart';
import '../../support/git_transport/git_source_transport_contract.dart';

const _https = 'https://github.com/owner/repo.git';
const _oid = 'abcdefabcdefabcdefabcdefabcdefabcdefabcd';

void main() {
  late _RecordingTransport system;

  setUp(() => system = _RecordingTransport());

  RoutingGitSourceTransport router({
    required SourceTransportStatus libgit2Status,
    bool systemGitAvailable = true,
  }) => RoutingGitSourceTransport(
    libgit2: Libgit2SourceTransport(native: _StatusNative(libgit2Status)),
    systemGit: system,
    systemGitAvailability: _Availability(systemGitAvailable),
  );

  Future<GitTransportResult<GitBareSource>> fetch(
    RoutingGitSourceTransport transport, {
    String locator = _https,
    GitCancellationSignal cancellation = const NeverGitCancellation(),
  }) => transport.fetchBare(
    GitSourceDescriptor(locator: locator),
    repositoryPath: path.join(Directory.systemTemp.path, 'routing-unused.git'),
    disabledHooksPath: Directory.systemTemp.path,
    cancellation: cancellation,
  );

  test('preserves primary reason only when fallback has none', () async {
    for (final secondaryReason in [null, 'secondaryReason']) {
      system.failure = GitTransportFailure(
        code: GitTransportFailureCode.commandFailed,
        context: {'reason': ?secondaryReason},
      );
      final result = await fetch(
        router(libgit2Status: SourceTransportStatus.tlsFailure),
      );
      expect(result.failureOrNull!.context['reason'], secondaryReason ?? 'tls');
      if (secondaryReason == null) {
        expect(result.failureOrNull!.context['transport'], 'systemGit');
        expect(result.failureOrNull!.context['primaryTransport'], 'libgit2');
      }
    }
  });
  test('sends SSH, scp, and local locators straight to system Git', () async {
    final transport = router(libgit2Status: SourceTransportStatus.ok);
    for (final locator in const [
      'ssh://git@github.com/owner/repo.git',
      'git@github.com:owner/repo.git',
      '/Users/someone/skills',
    ]) {
      await fetch(transport, locator: locator);
    }
    expect(system.fetchedLocators, [
      'ssh://git@github.com/owner/repo.git',
      'git@github.com:owner/repo.git',
      '/Users/someone/skills',
    ]);
  });

  test(
    'uses libgit2 for HTTPS and keeps reads on the fetching transport',
    () async {
      final transport = router(libgit2Status: SourceTransportStatus.ok);
      final fetched = (await fetch(transport)).valueOrNull!;

      expect(system.fetchedLocators, isEmpty);
      await transport.listTree(
        fetched,
        repositorySubpath: '',
        cancellation: const NeverGitCancellation(),
      );
      await transport.streamBlobs(
        fetched,
        requests: const [],
        onChunk: (_) async {},
        cancellation: const NeverGitCancellation(),
      );
      await transport.dispose(fetched);
      expect(system.reads, 0);
    },
  );

  test('falls back to system Git for recoverable libgit2 failures', () async {
    for (final status in const [
      SourceTransportStatus.authenticationRequired,
      SourceTransportStatus.networkFailure,
      SourceTransportStatus.certificateFailure,
      SourceTransportStatus.tlsFailure,
      SourceTransportStatus.timedOut,
      SourceTransportStatus.refNotFound,
      SourceTransportStatus.runtimeFailure,
    ]) {
      system = _RecordingTransport();
      final transport = router(libgit2Status: status);
      final fetched = (await fetch(transport)).valueOrNull;

      expect(system.fetchedLocators, [_https], reason: status.name);
      await transport.listTree(
        fetched!,
        repositorySubpath: '',
        cancellation: const NeverGitCancellation(),
      );
      expect(system.reads, 1, reason: status.name);
    }
  });

  test('keeps the libgit2 failure when fallback cannot help', () async {
    final unavailable = await fetch(
      router(
        libgit2Status: SourceTransportStatus.authenticationRequired,
        systemGitAvailable: false,
      ),
    );
    expect(
      unavailable.failureOrNull?.code,
      GitTransportFailureCode.authenticationRequired,
    );

    for (final status in const [
      SourceTransportStatus.objectFailure,
      SourceTransportStatus.invalidArgument,
      SourceTransportStatus.repositoryFailure,
    ]) {
      final result = await fetch(router(libgit2Status: status));
      expect(result.failureOrNull, isNotNull, reason: status.name);
    }

    final cancelled = await fetch(
      router(libgit2Status: SourceTransportStatus.cancelled),
    );
    expect(cancelled.failureOrNull?.code, GitTransportFailureCode.cancelled);
    expect(system.fetchedLocators, isEmpty);
  });

  test(
    'installs a public HTTPS-style Source when system Git cannot run',
    () async {
      final fixture = await GitSourceFixture.create();
      addTearDown(fixture.dispose);
      final server = await GitHttpBackendServer.start(
        projectRoot: fixture.root.path,
      );
      addTearDown(server.close);
      final scratch = await Directory.systemTemp.createTemp('routing-no-git-');
      addTearDown(() => scratch.delete(recursive: true));

      // System Git is both reported unavailable and pointed at a missing
      // executable, so any attempt to use it would fail the acquisition.
      final transport = RoutingGitSourceTransport(
        libgit2: Libgit2SourceTransport(
          native: const SourceTransportNative(),
          allowLoopbackHttpForTesting: true,
        ),
        systemGit: SystemGitSourceTransport(
          commandBuilder: GitBareCommandBuilder(
            executable: path.join(scratch.path, 'missing-git'),
          ),
        ),
        systemGitAvailability: const _Availability(false),
      );
      final fetched = (await transport.fetchBare(
        GitSourceDescriptor(locator: server.locatorFor('source')),
        repositoryPath: path.join(scratch.path, 'source.git'),
        disabledHooksPath: scratch.path,
        cancellation: const NeverGitCancellation(),
      )).valueOrNull!;
      final entries = (await transport.listTree(
        fetched,
        repositorySubpath: 'skills/demo',
        cancellation: const NeverGitCancellation(),
      )).valueOrNull!;
      final contents = await readAll(transport, fetched, entries);

      expect(
        contents.keys,
        containsAll(['skills/demo/SKILL.md', 'skills/demo/run.sh']),
      );
      await transport.dispose(fetched);
      expect(Directory(fetched.repositoryPath).existsSync(), isFalse);
    },
  );
}

final class _Availability implements SystemGitAvailability {
  const _Availability(this.available);

  final bool available;

  @override
  Future<bool> isAvailable() async => available;
}

final class _StatusNative implements SourceTransportNativePort {
  const _StatusNative(this.status);

  final SourceTransportStatus status;

  @override
  Future<SourceTransportFetchOutcome> fetch({
    required String repositoryPath,
    required String url,
    required String? ref,
    required SourceTransportProxyMode proxyMode,
    required String? proxyUrl,
    required int cancelFlagAddress,
  }) async => (
    status: status,
    commit: status == SourceTransportStatus.ok ? _oid : null,
  );

  @override
  Future<SourceTransportBytesOutcome> listTree({
    required String repositoryPath,
    required String commit,
    required String subpath,
  }) async => (status: SourceTransportStatus.ok, bytes: Uint8List(0));

  @override
  Future<SourceTransportBlobsOutcome> readBlobs({
    required String repositoryPath,
    required List<String> objectIds,
    required int maximumTotalBytes,
    required int cancelFlagAddress,
  }) async => (status: SourceTransportStatus.ok, blobs: <Uint8List>[]);

  @override
  Future<({SourceTransportStatus status, String? value})>
  windowsProxy() async =>
      (status: SourceTransportStatus.unsupported, value: null);
}

final class _RecordingTransport implements GitSourceTransport {
  final fetchedLocators = <String>[];
  var reads = 0;
  GitTransportFailure<GitBareSource>? failure;

  @override
  Future<GitTransportResult<GitBareSource>> fetchBare(
    GitSourceDescriptor source, {
    required String repositoryPath,
    required String disabledHooksPath,
    required GitCancellationSignal cancellation,
  }) async {
    fetchedLocators.add(source.locator);
    if (failure != null) return failure!;
    return GitTransportSuccess(
      GitBareSource(
        repositoryPath: repositoryPath,
        resolvedRevision: _oid,
        disabledHooksPath: disabledHooksPath,
      ),
    );
  }

  @override
  Future<GitTransportResult<List<GitTreeEntry>>> listTree(
    GitBareSource source, {
    required String repositorySubpath,
    required GitCancellationSignal cancellation,
  }) async {
    reads += 1;
    return const GitTransportSuccess(<GitTreeEntry>[]);
  }

  @override
  Future<GitTransportResult<void>> streamBlobs(
    GitBareSource source, {
    required List<GitBlobRequest> requests,
    required GitBlobChunkConsumer onChunk,
    required GitCancellationSignal cancellation,
  }) async {
    reads += 1;
    return const GitTransportSuccess<void>(null);
  }

  @override
  Future<void> dispose(GitBareSource source) async {}
}
