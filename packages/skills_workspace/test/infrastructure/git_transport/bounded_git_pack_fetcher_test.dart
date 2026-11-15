import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:skills_workspace/src/application/ports/repository_transport_native_port.dart';
import 'package:skills_workspace/src/infrastructure/revision_transfer/bounded_git_pack_fetcher.dart';
import 'package:test/test.dart';

const _root = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
List<int> _pkt(List<int> bytes) => [
  ...ascii.encode((bytes.length + 4).toRadixString(16).padLeft(4, '0')),
  ...bytes,
];
List<int> _line(String value) => _pkt(ascii.encode(value));
Matcher _failure(RepositoryTransportStatus status) =>
    isA<BoundedGitFetchFailure>().having(
      (failure) => failure.status,
      'status',
      status,
    );

void main() {
  late Directory temporary;
  setUp(
    () async =>
        temporary = await Directory.systemTemp.createTemp('bounded-git-fetch-'),
  );
  tearDown(() async => temporary.delete(recursive: true));

  for (final scenario in [
    'mime',
    'sha256',
    'duplicateRef',
    'advertisementLimit',
    'progressPacketCount',
    'progressWireBytes',
  ]) {
    test('rejects $scenario before unbounded transport work', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        try {
          if (request.method == 'GET') {
            request.response.headers.contentType = scenario == 'mime'
                ? ContentType.text
                : ContentType('application', 'x-git-upload-pack-advertisement');
            if (scenario == 'advertisementLimit') {
              request.response.add(Uint8List(1024 * 1024 + 1));
            } else {
              request.response.add([
                ..._line('version 2\n'),
                ..._line('ls-refs=unborn\n'),
                ..._line('fetch=shallow wait-for-done\n'),
                ..._line(
                  'object-format=${scenario == 'sha256' ? 'sha256' : 'sha1'}\n',
                ),
                ...ascii.encode('0000'),
              ]);
            }
          } else {
            final body = await request
                .cast<List<int>>()
                .transform(ascii.decoder)
                .join();
            request.response.headers.contentType = ContentType(
              'application',
              'x-git-upload-pack-result',
            );
            if (body.contains('command=ls-refs')) {
              expect(
                body,
                contains('ref-prefix refs/skilldeck/commits/$_root'),
              );
              request.response.add([
                ..._line('$_root refs/skilldeck/commits/$_root\n'),
                if (scenario == 'duplicateRef')
                  ..._line('${'b' * 40} refs/skilldeck/commits/$_root\n'),
                ...ascii.encode('0000'),
              ]);
            } else {
              expect(body, contains('command=fetch'));
              expect(body, isNot(contains('thin-pack')));
              request.response.add(_line('packfile\n'));
              final packet = _pkt([
                2,
                ...List.filled(scenario == 'progressWireBytes' ? 8192 : 1, 46),
              ]);
              for (
                var i = 0;
                i < (scenario == 'progressWireBytes' ? 1100 : 100001);
                i++
              ) {
                request.response.add(packet);
                if (i % 32 == 0) await request.response.flush();
              }
              request.response.add(ascii.encode('0000'));
            }
          }
          await request.response.close();
        } on Object {
          /* A bounded client intentionally disconnects early. */
        }
      });
      final expected = switch (scenario) {
        'sha256' => RepositoryTransportStatus.unsupported,
        'advertisementLimit' ||
        'progressPacketCount' ||
        'progressWireBytes' => RepositoryTransportStatus.limitExceeded,
        _ => RepositoryTransportStatus.networkFailure,
      };
      await expectLater(
        const BoundedGitPackFetcher().fetch(
          remote: 'http://127.0.0.1:${server.port}/repository.git',
          roots: [_root],
          headers: [],
          outputPath: '${temporary.path}/received.pack',
          allowLoopbackHttpForTesting: true,
          maximumPackBytes: scenario == 'progressWireBytes'
              ? 32
              : 64 * 1024 * 1024,
          isCancelled: () => false,
        ),
        throwsA(_failure(expected)),
      );
    });
  }

  test(
    'late connection completion aborts without consulting a released native cancellation source',
    () async {
      final client = _DelayedClient();
      var cancellationReads = 0;
      final fetcher = BoundedGitPackFetcher(
        createClient: () => client,
        connectTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        fetcher.fetch(
          remote: 'https://example.invalid/repository.git',
          roots: [_root],
          headers: [],
          outputPath: '${temporary.path}/unused',
          allowLoopbackHttpForTesting: false,
          isCancelled: () {
            cancellationReads++;
            return false;
          },
        ),
        throwsA(_failure(RepositoryTransportStatus.timedOut)),
      );
      final readsAtRelease = cancellationReads;
      final request = _LateRequest();
      client.opened.complete(request);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(request.aborts, greaterThan(0));
      expect(cancellationReads, readsAtRelease);
      expect(client.closes, greaterThan(0));
      expect(await File('${temporary.path}/unused').exists(), isFalse);
    },
  );

  test('loopback qualification requires an explicit port', () async {
    await expectLater(
      const BoundedGitPackFetcher().fetch(
        remote: 'http://127.0.0.1/repository.git',
        roots: [_root],
        headers: [],
        outputPath: '${temporary.path}/unused',
        allowLoopbackHttpForTesting: true,
        isCancelled: () => false,
      ),
      throwsA(_failure(RepositoryTransportStatus.invalidArgument)),
    );
  });
}

final class _DelayedClient implements HttpClient {
  final opened = Completer<HttpClientRequest>();
  int closes = 0;
  @override
  Future<HttpClientRequest> getUrl(Uri url) => opened.future;
  @override
  void close({bool force = false}) {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _LateRequest implements HttpClientRequest {
  int aborts = 0;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
