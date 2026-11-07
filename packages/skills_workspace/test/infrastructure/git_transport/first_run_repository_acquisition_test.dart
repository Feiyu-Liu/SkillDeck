import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/ports/source_transport_native_port.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/libgit2_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/routing_git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_availability.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/source/git_application_source_adapter.dart';
import 'package:skills_workspace/src/native/source_transport/source_transport_native.dart';
import 'package:test/test.dart';

import '../../support/git_transport/git_http_backend_server.dart';
import '../../support/git_transport/git_source_fixture.dart';

void main() {
  for (final mode in ['systemGit', 'libgit2', 'fallback']) {
    test('$mode applies content limits to each selected Skill', () async {
      final fixture = await GitSourceFixture.create();
      addTearDown(fixture.dispose);
      final noise = Directory(path.join(fixture.workingPath, 'noise'));
      await noise.create();
      final bytes = Uint8List(50 * 1024);
      for (var i = 0; i < 1100; i++) {
        await File(path.join(noise.path, 'f$i')).writeAsBytes(bytes);
      }
      await fixture.git(['add', 'noise']);
      final head = await fixture.revParse('HEAD');
      await fixture.git([
        'update-index',
        '--add',
        '--cacheinfo',
        '160000,$head,vendor',
      ]);
      for (final link in {
        'unsafe': '/outside',
        'dangling': 'missing',
      }.entries) {
        final object = await fixture.hashObject(link.value);
        await fixture.git([
          'update-index',
          '--add',
          '--cacheinfo',
          '120000,$object,${link.key}',
        ]);
      }
      await fixture.git(['commit', '-m', 'large repository']);
      final server = await GitHttpBackendServer.start(
        projectRoot: fixture.root.path,
      );
      addTearDown(server.close);
      final system = SystemGitSourceTransport();
      final GitSourceTransport transport = switch (mode) {
        'systemGit' => system,
        'libgit2' => Libgit2SourceTransport(
          native: const SourceTransportNative(),
          allowLoopbackHttpForTesting: true,
        ),
        _ => RoutingGitSourceTransport(
          libgit2: Libgit2SourceTransport(
            native: const _FailingNative(),
            allowLoopbackHttpForTesting: true,
          ),
          systemGit: _FixtureLocatorTransport(system, fixture.workingPath),
          systemGitAvailability: const _Available(),
        ),
      };
      final adapter = GitApplicationSourceAdapter(transport: transport);
      final locator = mode == 'systemGit'
          ? fixture.workingPath
          : server.locatorFor('source');
      // The loopback HTTP server is a transport-only fixture: the adapter's
      // production parser correctly disallows plain HTTP. Supply HTTPS in the
      // descriptor and translate it only at this test transport boundary.
      final source = GitSourceDescriptor(
        locator: mode == 'systemGit'
            ? locator
            : 'https://fixture.invalid/source.git',
      );
      final subject = mode == 'systemGit'
          ? adapter
          : GitApplicationSourceAdapter(
              transport: _FixtureLocatorTransport(transport, locator),
            );
      Future<SourceAcquisitionResult<AcquiredSource>> acquire([
        String skillPath = '',
      ]) => subject.acquireGit(
        GitSourceDescriptor(locator: source.locator, skillPath: skillPath),
        selectedSkillNames: const {},
        options: const SourceAcquisitionOptions(),
        cancellationToken: CancellationToken.none(),
      );
      final small = await acquire();
      expect(small.failureOrNull, isNull);
      expect(small.valueOrNull!.skills.single.slotKey, 'demo');

      final large = Directory(
        path.join(fixture.workingPath, 'skills', 'large'),
      );
      await large.create();
      await File(
        path.join(large.path, 'SKILL.md'),
      ).writeAsString('---\nname: large\ndescription: Large\n---\n');
      for (var i = 0; i < 1000; i++) {
        await File(path.join(large.path, 'f$i')).writeAsString('x');
      }
      await fixture.git(['add', 'skills/large']);
      await fixture.git(['commit', '-m', 'oversized Skill']);
      expect((await acquire('skills/demo')).failureOrNull, isNull);
      final oversized = await acquire('skills/large');
      expect(
        oversized.failureOrNull?.code,
        SourceAcquisitionFailureCode.skillContentLimitExceeded,
      );
      expect(
        oversized.failureOrNull?.context,
        containsPair('limit', 'fileCount'),
      );
      expect(oversized.failureOrNull?.context, containsPair('actual', 1001));

      await File(
        path.join(large.path, 'f0'),
      ).writeAsBytes(Uint8List(50 * 1024 * 1024 + 1));
      await fixture.git(['add', 'skills/large/f0']);
      await fixture.git(['commit', '-m', 'oversized blob']);
      // Remove the extra files so the byte limit is the first failure.
      await fixture.git([
        'rm',
        '--cached',
        ...[for (var i = 1; i < 1000; i++) 'skills/large/f$i'],
      ]);
      await fixture.git(['commit', '-m', 'byte limit fixture']);
      final sized = await acquire('skills/large');
      expect(
        sized.failureOrNull?.code,
        SourceAcquisitionFailureCode.skillContentLimitExceeded,
      );
      expect(sized.failureOrNull?.context, containsPair('limit', 'byteSize'));
      expect(
        sized.failureOrNull?.context,
        containsPair('maximumByteSize', 50 * 1024 * 1024),
      );
      expect(
        sized.failureOrNull?.context['actual'],
        greaterThan(50 * 1024 * 1024),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}

final class _Available implements SystemGitAvailability {
  const _Available();
  @override
  Future<bool> isAvailable() async => true;
}

final class _FailingNative implements SourceTransportNativePort {
  const _FailingNative();
  @override
  Future<SourceTransportFetchOutcome> fetch({
    required String repositoryPath,
    required String url,
    required String? ref,
    required SourceTransportProxyMode proxyMode,
    required String? proxyUrl,
    required int cancelFlagAddress,
  }) async => (status: SourceTransportStatus.networkFailure, commit: null);
  @override
  Future<SourceTransportBytesOutcome> listTree({
    required String repositoryPath,
    required String commit,
    required String subpath,
  }) async => (status: SourceTransportStatus.runtimeFailure, bytes: null);
  @override
  Future<SourceTransportBlobsOutcome> readBlobs({
    required String repositoryPath,
    required List<String> objectIds,
    required int maximumTotalBytes,
    required int cancelFlagAddress,
  }) async => (status: SourceTransportStatus.runtimeFailure, blobs: null);
  @override
  Future<({SourceTransportStatus status, String? value})>
  windowsProxy() async =>
      (status: SourceTransportStatus.unsupported, value: null);
}

final class _FixtureLocatorTransport implements GitSourceTransport {
  _FixtureLocatorTransport(this.delegate, this.locator);
  final GitSourceTransport delegate;
  final String locator;
  @override
  Future<GitTransportResult<GitBareSource>> fetchBare(
    GitSourceDescriptor source, {
    required String repositoryPath,
    required String disabledHooksPath,
    required GitCancellationSignal cancellation,
  }) => delegate.fetchBare(
    GitSourceDescriptor(locator: locator, ref: source.ref),
    repositoryPath: repositoryPath,
    disabledHooksPath: disabledHooksPath,
    cancellation: cancellation,
  );
  @override
  Future<GitTransportResult<List<GitTreeEntry>>> listTree(
    GitBareSource source, {
    required String repositorySubpath,
    required GitCancellationSignal cancellation,
  }) => delegate.listTree(
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
  }) => delegate.streamBlobs(
    source,
    requests: requests,
    onChunk: onChunk,
    cancellation: cancellation,
  );
  @override
  Future<void> dispose(GitBareSource source) => delegate.dispose(source);
}
