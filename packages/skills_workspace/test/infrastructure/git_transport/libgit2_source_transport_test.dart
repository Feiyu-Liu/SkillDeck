import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/ports/source_transport_native_port.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_proxy_choice.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/libgit2_source_transport.dart';
import 'package:skills_workspace/src/native/source_transport/source_transport_native.dart';
import 'package:test/test.dart';

import '../../support/git_transport/git_http_backend_server.dart';
import '../../support/git_transport/git_source_fixture.dart';
import '../../support/git_transport/git_source_transport_contract.dart';

const _github = 'https://github.com/owner/repo.git';
const _oid = 'abcdefabcdefabcdefabcdefabcdefabcdefabcd';

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp(
      'skills-libgit2-transport-',
    );
  });
  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  String repository() => path.join(scratch.path, 'source.git');

  GitBareSource bare() => GitBareSource(
    repositoryPath: repository(),
    resolvedRevision: _oid,
    disabledHooksPath: scratch.path,
  );

  Future<GitTransportResult<GitBareSource>> fetch(
    Libgit2SourceTransport transport, {
    String locator = _github,
    String? ref,
    GitCancellationSignal cancellation = const NeverGitCancellation(),
  }) => transport.fetchBare(
    GitSourceDescriptor(locator: locator, ref: ref),
    repositoryPath: repository(),
    disabledHooksPath: scratch.path,
    cancellation: cancellation,
  );

  group('locator policy', () {
    test('accepts only canonical credential-free HTTPS locators', () {
      final transport = Libgit2SourceTransport(
        native: const SourceTransportNative(),
      );
      expect(transport.supportsLocator(_github), isTrue);
      expect(
        transport.supportsLocator('https://gitlab.com/group/sub/repo.git'),
        isTrue,
      );
      for (final locator in const <String>[
        'https://user:secret@github.com/owner/repo.git',
        'https://github.com/owner/repo.git?token=1',
        'git@github.com:owner/repo.git',
        'ssh://git@github.com/owner/repo.git',
        '/Users/someone/skills',
        'http://example.com/repo.git',
        'http://127.0.0.1:9/repo.git',
      ]) {
        expect(transport.supportsLocator(locator), isFalse, reason: locator);
      }
      expect(
        Libgit2SourceTransport(
          native: const SourceTransportNative(),
          allowLoopbackHttpForTesting: true,
        ).supportsLocator('http://127.0.0.1:9/repo.git'),
        isTrue,
      );
    });

    test(
      'rejects an unsupported locator without reaching native code',
      () async {
        final native = _FakeNative();
        final result = await fetch(
          Libgit2SourceTransport(native: native),
          locator: 'git@github.com:owner/repo.git',
        );

        expect(result.failureOrNull?.code, GitTransportFailureCode.rejected);
        expect(result.failureOrNull?.context['reason'], 'unsupportedLocator');
        expect(native.fetchCalls, 0);
      },
    );
  });

  group('fetch outcomes', () {
    test('returns the fetched commit as a bare Source', () async {
      final native = _FakeNative(
        onFetch: (_) async => (status: SourceTransportStatus.ok, commit: _oid),
      );
      final source = (await fetch(
        Libgit2SourceTransport(native: native),
        ref: 'v1',
      )).valueOrNull!;

      expect(source.resolvedRevision, _oid);
      expect(native.lastRef, 'v1');
      expect(native.lastUrl, _github);
    });

    test(
      'maps every native status and removes the partial repository',
      () async {
        final expected =
            <SourceTransportStatus, (GitTransportFailureCode, String?)>{
              SourceTransportStatus.authenticationRequired: (
                GitTransportFailureCode.authenticationRequired,
                null,
              ),
              SourceTransportStatus.timedOut: (
                GitTransportFailureCode.timedOut,
                null,
              ),
              SourceTransportStatus.certificateFailure: (
                GitTransportFailureCode.commandFailed,
                'certificate',
              ),
              SourceTransportStatus.tlsFailure: (
                GitTransportFailureCode.commandFailed,
                'tls',
              ),
              SourceTransportStatus.networkFailure: (
                GitTransportFailureCode.commandFailed,
                'network',
              ),
              SourceTransportStatus.refNotFound: (
                GitTransportFailureCode.commandFailed,
                'refNotFound',
              ),
              SourceTransportStatus.invalidArgument: (
                GitTransportFailureCode.rejected,
                'invalidLocator',
              ),
              SourceTransportStatus.runtimeFailure: (
                GitTransportFailureCode.unavailable,
                'runtime',
              ),
              SourceTransportStatus.repositoryFailure: (
                GitTransportFailureCode.ioFailure,
                'repository',
              ),
              SourceTransportStatus.objectFailure: (
                GitTransportFailureCode.invalidOutput,
                'objectFailure',
              ),
              SourceTransportStatus.cancelled: (
                GitTransportFailureCode.cancelled,
                null,
              ),
            };
        for (final MapEntry(key: status, value: (code, reason))
            in expected.entries) {
          await Directory(repository()).create(recursive: true);
          final result = await fetch(
            Libgit2SourceTransport(
              native: _FakeNative(
                onFetch: (_) async => (status: status, commit: null),
              ),
            ),
          );
          final failure = result.failureOrNull!;
          expect(failure.code, code, reason: status.name);
          expect(failure.context['reason'], reason, reason: status.name);
          expect(failure.context['transport'], 'libgit2');
          expect(failure.context['locator'], _github);
          expect(Directory(repository()).existsSync(), isFalse);
        }
      },
    );

    test('treats a malformed success as invalid output', () async {
      final result = await fetch(
        Libgit2SourceTransport(
          native: _FakeNative(
            onFetch: (_) async =>
                (status: SourceTransportStatus.ok, commit: 'nope'),
          ),
        ),
      );
      expect(result.failureOrNull?.context['reason'], 'invalidFetchedRevision');
    });

    test('redacts the locator it reports', () async {
      final result = await fetch(
        Libgit2SourceTransport(native: _FakeNative()),
        locator: 'https://user:secret@github.com/owner/repo.git',
      );
      expect(
        result.failureOrNull?.context['locator'],
        isNot(contains('secret')),
      );
    });

    test('times out by raising the cancel flag', () async {
      final native = _FakeNative(onFetch: (flag) => _waitForFlag(flag));
      final result = await fetch(
        Libgit2SourceTransport(
          native: native,
          fetchTimeout: const Duration(milliseconds: 50),
        ),
      );
      expect(result.failureOrNull?.code, GitTransportFailureCode.timedOut);
    });

    test('raises the cancel flag when the operation is cancelled', () async {
      final cancellation = _ManualCancellation();
      final native = _FakeNative(onFetch: (flag) => _waitForFlag(flag));
      final pending = fetch(
        Libgit2SourceTransport(native: native),
        cancellation: cancellation,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cancellation.cancel();

      expect(
        (await pending).failureOrNull?.code,
        GitTransportFailureCode.cancelled,
      );
    });

    test('passes the selected proxy to the native fetch', () async {
      final native = _FakeNative(
        onFetch: (_) async => (status: SourceTransportStatus.ok, commit: _oid),
      );
      Uri? selectedFor;
      await fetch(
        Libgit2SourceTransport(
          native: native,
          proxySelector: (remote) async {
            selectedFor = remote;
            return const GitProxySpecified('http://proxy.example:8080');
          },
        ),
      );
      expect(selectedFor?.host, 'github.com');
      expect(native.lastProxyMode, SourceTransportProxyMode.specified);
      expect(native.lastProxyUrl, 'http://proxy.example:8080');

      await fetch(
        Libgit2SourceTransport(
          native: native,
          proxySelector: (_) async => const GitProxyFromEnvironment(),
        ),
      );
      expect(native.lastProxyMode, SourceTransportProxyMode.environment);
      expect(native.lastProxyUrl, isNull);

      final failed = await fetch(
        Libgit2SourceTransport(
          native: native,
          proxySelector: (_) async => throw StateError('no proxy'),
        ),
      );
      expect(failed.failureOrNull?.context['reason'], 'proxy');
    });
  });

  group('reading', () {
    test('maps tree read failures and honours cancellation', () async {
      final transport = Libgit2SourceTransport(
        native: _FakeNative(
          onListTree: () async =>
              (status: SourceTransportStatus.objectFailure, bytes: null),
        ),
      );
      final failed = await transport.listTree(
        bare(),
        repositorySubpath: '',
        cancellation: const NeverGitCancellation(),
      );
      expect(failed.failureOrNull?.context['reason'], 'treeUnavailable');

      final cancelled = await transport.listTree(
        bare(),
        repositorySubpath: '',
        cancellation: const AlreadyCancelledGitSignal(),
      );
      expect(cancelled.failureOrNull?.code, GitTransportFailureCode.cancelled);
    });

    test('streams blobs in bounded chunks', () async {
      final large = Uint8List(150 * 1024)..fillRange(0, 150 * 1024, 7);
      final transport = Libgit2SourceTransport(
        native: _FakeNative(
          onReadBlobs: (_) async =>
              (status: SourceTransportStatus.ok, blobs: [large, Uint8List(0)]),
        ),
      );
      final chunks = <GitBlobChunk>[];
      final result = await transport.streamBlobs(
        bare(),
        requests: [
          GitBlobRequest(objectId: _oid, relativePath: 'large.bin'),
          GitBlobRequest(objectId: _oid, relativePath: 'empty'),
        ],
        onChunk: (chunk) async => chunks.add(chunk),
        cancellation: const NeverGitCancellation(),
      );

      expect(result.failureOrNull, isNull);
      expect(
        [
          for (final chunk in chunks)
            (chunk.request.relativePath, chunk.bytes.length, chunk.isLast),
        ],
        [
          ('large.bin', 64 * 1024, false),
          ('large.bin', 64 * 1024, false),
          ('large.bin', 22 * 1024, true),
          ('empty', 0, true),
        ],
      );
    });

    test('maps blob read failures', () async {
      Future<GitTransportResult<void>> stream(
        SourceTransportBlobsOutcome outcome, {
        GitBlobChunkConsumer? onChunk,
        int requests = 1,
      }) =>
          Libgit2SourceTransport(
            native: _FakeNative(onReadBlobs: (_) async => outcome),
            maximumFileCount: 2,
          ).streamBlobs(
            bare(),
            requests: [
              for (var index = 0; index < requests; index += 1)
                GitBlobRequest(objectId: _oid, relativePath: 'file$index'),
            ],
            onChunk: onChunk ?? (_) async {},
            cancellation: const NeverGitCancellation(),
          );

      expect(
        (await stream((
          status: SourceTransportStatus.limitExceeded,
          blobs: null,
        ))).failureOrNull?.context['reason'],
        'blobBytesExceededLimit',
      );
      expect(
        (await stream((
          status: SourceTransportStatus.ok,
          blobs: <Uint8List>[],
        ))).failureOrNull?.context['reason'],
        'blobUnavailable',
      );
      expect(
        (await stream((
          status: SourceTransportStatus.cancelled,
          blobs: null,
        ))).failureOrNull?.code,
        GitTransportFailureCode.cancelled,
      );
      expect(
        (await stream(
          (status: SourceTransportStatus.ok, blobs: [Uint8List(1)]),
          onChunk: (_) async => throw StateError('consumer'),
        )).failureOrNull?.context['reason'],
        'blobConsumerFailed',
      );
      expect(
        (await stream((
          status: SourceTransportStatus.ok,
          blobs: null,
        ), requests: 3)).failureOrNull?.context['reason'],
        'fileCountExceeded',
      );
      expect(
        (await stream((
          status: SourceTransportStatus.ok,
          blobs: null,
        ), requests: 0)).failureOrNull,
        isNull,
      );
    });
  });

  group('native smart HTTP', () {
    test('reports a server that requires credentials', () async {
      final fixture = await GitSourceFixture.create();
      addTearDown(fixture.dispose);
      final server = await GitHttpBackendServer.start(
        projectRoot: fixture.root.path,
        requireAuthentication: true,
      );
      addTearDown(server.close);

      final result = await fetch(
        Libgit2SourceTransport(
          native: const SourceTransportNative(),
          allowLoopbackHttpForTesting: true,
        ),
        locator: server.locatorFor('source'),
      );

      expect(
        result.failureOrNull?.code,
        GitTransportFailureCode.authenticationRequired,
      );
      expect(Directory(repository()).existsSync(), isFalse);
    });

    test(
      'refuses integrated authentication without sending credentials',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var requestCount = 0;
        var sentAuthorization = false;
        server.listen((request) async {
          requestCount += 1;
          sentAuthorization |=
              request.headers.value(HttpHeaders.authorizationHeader) != null;
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..headers.set(HttpHeaders.wwwAuthenticateHeader, 'Negotiate');
          await request.response.close();
        });

        final result = await fetch(
          Libgit2SourceTransport(
            native: const SourceTransportNative(),
            allowLoopbackHttpForTesting: true,
          ),
          locator: 'http://127.0.0.1:${server.port}/source',
        );

        expect(
          result.failureOrNull?.code,
          GitTransportFailureCode.authenticationRequired,
        );
        expect(result.failureOrNull?.context['reason'], isNull);
        expect(requestCount, greaterThan(0));
        expect(sentAuthorization, isFalse);
        expect(Directory(repository()).existsSync(), isFalse);
      },
    );

    for (final status in [HttpStatus.forbidden, HttpStatus.notFound]) {
      test(
        'does not classify HTTP $status as authentication required',
        () async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(() => server.close(force: true));
          server.listen((request) async {
            request.response.statusCode = status;
            await request.response.close();
          });

          final result = await fetch(
            Libgit2SourceTransport(
              native: const SourceTransportNative(),
              allowLoopbackHttpForTesting: true,
            ),
            locator: 'http://127.0.0.1:${server.port}/source',
          );

          expect(
            result.failureOrNull?.code,
            GitTransportFailureCode.commandFailed,
          );
          expect(result.failureOrNull?.context['reason'], 'network');
          expect(Directory(repository()).existsSync(), isFalse);
        },
      );
    }

    test('classifies an unreachable server as a network failure', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();

      final result = await fetch(
        Libgit2SourceTransport(
          native: const SourceTransportNative(),
          allowLoopbackHttpForTesting: true,
        ),
        locator: 'http://127.0.0.1:$port/source',
      );

      expect(result.failureOrNull?.code, GitTransportFailureCode.commandFailed);
      expect(result.failureOrNull?.context['reason'], 'network');
    });
  });
}

Future<SourceTransportFetchOutcome> _waitForFlag(int flagAddress) async {
  final flag = ffi.Pointer<ffi.Int32>.fromAddress(flagAddress);
  while (flag.value == 0) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return (status: SourceTransportStatus.cancelled, commit: null);
}

final class _ManualCancellation implements GitCancellationSignal {
  final _completer = Completer<void>();

  void cancel() => _completer.complete();

  @override
  bool get isCancelled => _completer.isCompleted;

  @override
  Future<void> get whenCancelled => _completer.future;
}

final class _FakeNative implements SourceTransportNativePort {
  _FakeNative({this.onFetch, this.onListTree, this.onReadBlobs});

  final Future<SourceTransportFetchOutcome> Function(int flagAddress)? onFetch;
  final Future<SourceTransportBytesOutcome> Function()? onListTree;
  final Future<SourceTransportBlobsOutcome> Function(int flagAddress)?
  onReadBlobs;

  var fetchCalls = 0;
  String? lastUrl;
  String? lastRef;
  SourceTransportProxyMode? lastProxyMode;
  String? lastProxyUrl;

  @override
  Future<SourceTransportFetchOutcome> fetch({
    required String repositoryPath,
    required String url,
    required String? ref,
    required SourceTransportProxyMode proxyMode,
    required String? proxyUrl,
    required int cancelFlagAddress,
  }) {
    fetchCalls += 1;
    lastUrl = url;
    lastRef = ref;
    lastProxyMode = proxyMode;
    lastProxyUrl = proxyUrl;
    return onFetch?.call(cancelFlagAddress) ??
        Future.value((
          status: SourceTransportStatus.networkFailure,
          commit: null,
        ));
  }

  @override
  Future<SourceTransportBytesOutcome> listTree({
    required String repositoryPath,
    required String commit,
    required String subpath,
  }) =>
      onListTree?.call() ??
      Future.value((status: SourceTransportStatus.ok, bytes: Uint8List(0)));

  @override
  Future<SourceTransportBlobsOutcome> readBlobs({
    required String repositoryPath,
    required List<String> objectIds,
    required int maximumTotalBytes,
    required int cancelFlagAddress,
  }) =>
      onReadBlobs?.call(cancelFlagAddress) ??
      Future.value((status: SourceTransportStatus.ok, blobs: <Uint8List>[]));

  @override
  Future<({SourceTransportStatus status, String? value})> windowsProxy() =>
      Future.value((status: SourceTransportStatus.unsupported, value: null));
}
