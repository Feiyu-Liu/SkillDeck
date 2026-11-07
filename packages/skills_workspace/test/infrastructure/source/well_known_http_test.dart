import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skills_workspace/src/infrastructure/source/source_result.dart';
import 'package:skills_workspace/src/infrastructure/source/well_known_http.dart';
import 'package:test/test.dart';

void main() {
  group('destination policy', () {
    test('rejects a negative byte bound and pre-cancelled request', () async {
      final cancellation = _Cancellation()..cancel();
      final client = _client((_) async => http.Response('unused', 200));

      expect(
        () => client.get(Uri.parse('http://127.0.0.1'), maximumBytes: -1),
        throwsArgumentError,
      );
      final cancelled = await client.get(
        Uri.parse('http://127.0.0.1'),
        maximumBytes: 0,
        cancellation: cancellation,
      );
      expect(cancelled.failureOrNull?.code, SourceFailureCode.cancelled);
    });

    for (final uri in <String>[
      'file:///tmp/skill',
      'https://user:secret@example.com/skill',
      'relative/path',
    ]) {
      test('rejects unsupported destination $uri before sending', () async {
        var sent = false;
        final client = _client((_) async {
          sent = true;
          return http.Response('unused', 200);
        });

        final result = await client.get(Uri.parse(uri), maximumBytes: 64);

        expect(result.failureOrNull?.code, SourceFailureCode.rejected);
        expect(
          result.failureOrNull?.context['reason'],
          'unsupportedOrCredentialBearingTransport',
        );
        expect(sent, isFalse);
      });
    }

    test('maps resolver exception and empty result to unavailable', () async {
      final throwing = WellKnownHttpClient(
        client: MockClient((_) async => http.Response('unused', 200)),
        addressResolver: (_) => throw StateError('resolver failed'),
      );
      final empty = WellKnownHttpClient(
        client: MockClient((_) async => http.Response('unused', 200)),
        addressResolver: (_) async => <InternetAddress>[],
      );

      for (final client in <WellKnownHttpClient>[throwing, empty]) {
        final result = await client.get(
          Uri.parse('https://example.com/skill'),
          maximumBytes: 64,
        );
        expect(result.failureOrNull?.code, SourceFailureCode.unavailable);
        expect(
          result.failureOrNull?.context['reason'],
          'destinationResolutionFailed',
        );
      }
    });

    test('rechecks cancellation after destination resolution', () async {
      final cancellation = _Cancellation();
      var sent = false;
      final client = WellKnownHttpClient(
        client: MockClient((_) async {
          sent = true;
          return http.Response('unused', 200);
        }),
        addressResolver: (_) async {
          cancellation.cancel();
          return <InternetAddress>[InternetAddress.loopbackIPv4];
        },
      );

      final result = await client.get(
        Uri.parse('http://127.0.0.1/skill'),
        maximumBytes: 64,
        cancellation: cancellation,
      );

      expect(result.failureOrNull?.code, SourceFailureCode.cancelled);
      expect(sent, isFalse);
    });

    test('plain HTTP requires every resolved address to be loopback', () async {
      var sent = false;
      final client = WellKnownHttpClient(
        client: MockClient((_) async {
          sent = true;
          return http.Response('unused', 200);
        }),
        addressResolver: (_) async => <InternetAddress>[
          InternetAddress.loopbackIPv4,
          InternetAddress('93.184.216.34'),
        ],
      );

      final result = await client.get(
        Uri.parse('http://example.com/skill'),
        maximumBytes: 64,
      );

      expect(result.failureOrNull?.code, SourceFailureCode.rejected);
      expect(
        result.failureOrNull?.context['reason'],
        'plainHttpRequiresLoopback',
      );
      expect(sent, isFalse);
    });

    test('HTTPS accepts public IPv4 and IPv6 destinations', () async {
      for (final address in <InternetAddress>[
        InternetAddress('93.184.216.34'),
        InternetAddress('2606:2800:220:1:248:1893:25c8:1946'),
      ]) {
        final client = WellKnownHttpClient(
          client: MockClient((_) async => http.Response('ok', 200)),
          addressResolver: (_) async => <InternetAddress>[address],
        );

        final result = await client.get(
          Uri.parse('https://example.com/skill'),
          maximumBytes: 64,
        );

        expect(result.valueOrNull?.bytes, <int>[111, 107]);
      }
    });

    for (final address in <String>[
      '10.0.0.1',
      '127.0.0.1',
      '169.254.1.1',
      '172.16.0.1',
      '192.168.0.1',
      '198.51.100.1',
      '::1',
      'fc00::1',
      'fe80::1',
      'ff02::1',
      '2001:db8::1',
      '::ffff:192.168.0.1',
    ]) {
      test('HTTPS rejects non-public destination $address', () async {
        final client = WellKnownHttpClient(
          client: MockClient((_) async => http.Response('unused', 200)),
          addressResolver: (_) async => <InternetAddress>[
            InternetAddress(address),
          ],
        );

        final result = await client.get(
          Uri.parse('https://example.com/skill'),
          maximumBytes: 64,
        );

        expect(result.failureOrNull?.code, SourceFailureCode.rejected);
        expect(
          result.failureOrNull?.context['reason'],
          'httpsRequiresPublicDestination',
        );
      });
    }
  });

  group('redirect and response handling', () {
    for (final status in <int>[301, 302, 303, 307, 308]) {
      test('follows status $status without delegating redirects', () async {
        final requested = <Uri>[];
        final client = _client((request) async {
          requested.add(request.url);
          if (requested.length == 1) {
            expect(request.followRedirects, isFalse);
            expect(request.persistentConnection, isFalse);
            return http.Response(
              '',
              status,
              headers: <String, String>{'location': '../final'},
            );
          }
          return http.Response(
            'done',
            200,
            headers: <String, String>{'content-type': 'text/markdown'},
          );
        });

        final result = await client.get(
          Uri.parse('http://127.0.0.1/a/start'),
          maximumBytes: 64,
        );

        expect(requested.map((uri) => uri.path), <String>[
          '/a/start',
          '/final',
        ]);
        expect(result.valueOrNull?.uri.path, '/final');
        expect(result.valueOrNull?.contentType, 'text/markdown');
        expect(result.valueOrNull?.bytes, <int>[100, 111, 110, 101]);
      });
    }

    test('revalidates every redirect destination', () async {
      final client = WellKnownHttpClient(
        client: MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: <String, String>{'location': 'http://192.168.1.1/private'},
          ),
        ),
        addressResolver: (host) async => <InternetAddress>[
          host == '127.0.0.1'
              ? InternetAddress.loopbackIPv4
              : InternetAddress('192.168.1.1'),
        ],
      );

      final result = await client.get(
        Uri.parse('http://127.0.0.1/start'),
        maximumBytes: 64,
      );

      expect(result.failureOrNull?.code, SourceFailureCode.rejected);
    });

    test('rejects redirect overflow and missing location', () async {
      final overflow = WellKnownHttpClient(
        client: MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: <String, String>{'location': '/again'},
          ),
        ),
        addressResolver: _loopback,
        maximumRedirects: 0,
      );
      final missing = _client((_) async => http.Response('', 302));

      final overflowResult = await overflow.get(
        Uri.parse('http://127.0.0.1/start'),
        maximumBytes: 64,
      );
      final missingResult = await missing.get(
        Uri.parse('http://127.0.0.1/start'),
        maximumBytes: 64,
      );

      expect(
        overflowResult.failureOrNull?.context['reason'],
        'tooManyRedirects',
      );
      expect(
        missingResult.failureOrNull?.context['reason'],
        'redirectMissingLocation',
      );
    });

    test('reports unexpected status with a credential-free origin', () async {
      final client = _client((_) async => http.Response('secret', 503));

      final result = await client.get(
        Uri.parse('http://127.0.0.1:18080/private?q=secret'),
        maximumBytes: 64,
      );

      expect(result.failureOrNull?.code, SourceFailureCode.httpFailure);
      expect(result.failureOrNull?.context, <String, Object?>{
        'reason': 'unexpectedStatus',
        'statusCode': 503,
        'destination': 'http://127.0.0.1:18080',
      });
    });

    test('rejects declared and streamed byte overflow', () async {
      final declared = WellKnownHttpClient(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            http.ByteStream.fromBytes(<int>[1]),
            200,
            contentLength: 10,
          ),
        ),
        addressResolver: _loopback,
      );
      final streamed = WellKnownHttpClient(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            http.ByteStream(
              Stream<List<int>>.fromIterable(<List<int>>[
                <int>[1, 2],
                <int>[3, 4],
              ]),
            ),
            200,
          ),
        ),
        addressResolver: _loopback,
      );

      final declaredResult = await declared.get(
        Uri.parse('http://127.0.0.1/skill'),
        maximumBytes: 3,
      );
      final streamedResult = await streamed.get(
        Uri.parse('http://127.0.0.1/skill'),
        maximumBytes: 3,
      );

      for (final result in <SourceResult<WellKnownHttpResponse>>[
        declaredResult,
        streamedResult,
      ]) {
        expect(
          result.failureOrNull?.code,
          SourceFailureCode.contentLimitExceeded,
        );
        expect(result.failureOrNull?.context['limit'], 'downloadByteSize');
        expect(result.failureOrNull?.context['maximum'], 3);
      }
    });
  });

  group('transport and stream failures', () {
    test('maps request abort, timeout, and transport exception', () async {
      final abort = _streamingClient((_, _) async {
        throw http.RequestAbortedException();
      });
      final timeout = WellKnownHttpClient(
        client: MockClient.streaming(
          (_, _) => Completer<http.StreamedResponse>().future,
        ),
        addressResolver: _loopback,
        requestTimeout: const Duration(milliseconds: 5),
      );
      final transport = _streamingClient((_, _) async {
        throw const SocketException('offline');
      });

      final aborted = await abort.get(
        Uri.parse('http://127.0.0.1/skill'),
        maximumBytes: 64,
      );
      final timedOut = await timeout.get(
        Uri.parse('http://127.0.0.1/skill'),
        maximumBytes: 64,
      );
      final failed = await transport.get(
        Uri.parse('http://127.0.0.1/skill'),
        maximumBytes: 64,
      );

      expect(aborted.failureOrNull?.code, SourceFailureCode.cancelled);
      expect(timedOut.failureOrNull?.context['reason'], 'timeout');
      expect(failed.failureOrNull?.context['reason'], 'transportFailure');
    });

    test(
      'transport exception observes cancellation requested by client',
      () async {
        final cancellation = _Cancellation();
        final client = _streamingClient((_, _) async {
          cancellation.cancel();
          throw const SocketException('aborted');
        });

        final result = await client.get(
          Uri.parse('http://127.0.0.1/skill'),
          maximumBytes: 64,
          cancellation: cancellation,
        );

        expect(result.failureOrNull?.code, SourceFailureCode.cancelled);
      },
    );

    test('maps response abort, timeout, and read exception', () async {
      WellKnownHttpClient responseClient(Stream<List<int>> stream) =>
          WellKnownHttpClient(
            client: MockClient.streaming(
              (_, _) async =>
                  http.StreamedResponse(http.ByteStream(stream), 200),
            ),
            addressResolver: _loopback,
            requestTimeout: const Duration(milliseconds: 5),
          );

      final aborted = await responseClient(
        Stream<List<int>>.error(http.RequestAbortedException()),
      ).get(Uri.parse('http://127.0.0.1/skill'), maximumBytes: 64);
      final timedOut = await responseClient(
        StreamController<List<int>>().stream,
      ).get(Uri.parse('http://127.0.0.1/skill'), maximumBytes: 64);
      final failed = await responseClient(
        Stream<List<int>>.error(const FileSystemException('read failed')),
      ).get(Uri.parse('http://127.0.0.1/skill'), maximumBytes: 64);

      expect(aborted.failureOrNull?.code, SourceFailureCode.cancelled);
      expect(timedOut.failureOrNull?.context['reason'], 'timeout');
      expect(failed.failureOrNull?.context['reason'], 'responseReadFailed');
    });

    test('stream loop and read exception both observe cancellation', () async {
      final duringChunk = _Cancellation();
      final chunkClient = _streamingClient((_, _) async {
        return http.StreamedResponse(
          http.ByteStream(
            Stream<List<int>>.multi((controller) {
              duringChunk.cancel();
              controller
                ..add(<int>[1])
                ..close();
            }),
          ),
          200,
        );
      });
      final duringError = _Cancellation();
      final errorClient = _streamingClient((_, _) async {
        return http.StreamedResponse(
          http.ByteStream(
            Stream<List<int>>.multi((controller) {
              duringError.cancel();
              controller.addError(const FileSystemException('aborted read'));
              controller.close();
            }),
          ),
          200,
        );
      });

      final chunkResult = await chunkClient.get(
        Uri.parse('http://127.0.0.1/skill'),
        maximumBytes: 64,
        cancellation: duringChunk,
      );
      final errorResult = await errorClient.get(
        Uri.parse('http://127.0.0.1/skill'),
        maximumBytes: 64,
        cancellation: duringError,
      );

      expect(chunkResult.failureOrNull?.code, SourceFailureCode.cancelled);
      expect(errorResult.failureOrNull?.code, SourceFailureCode.cancelled);
    });
  });

  test('default pinned client can read from a loopback server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final served = Completer<void>();
    server.listen((request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.write('pinned');
      await request.response.close();
      served.complete();
    });
    final client = WellKnownHttpClient(
      addressResolver: (_) async => <InternetAddress>[
        InternetAddress.loopbackIPv4,
      ],
    );

    final result = await client.get(
      Uri.parse('http://loopback.invalid:${server.port}/skill'),
      maximumBytes: 64,
    );

    await served.future;
    expect(result.valueOrNull?.bytes, 'pinned'.codeUnits);
  });
}

WellKnownHttpClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => WellKnownHttpClient(
  client: MockClient(handler),
  addressResolver: _loopback,
);

WellKnownHttpClient _streamingClient(MockClientStreamHandler handler) =>
    WellKnownHttpClient(
      client: MockClient.streaming(handler),
      addressResolver: _loopback,
    );

Future<List<InternetAddress>> _loopback(String _) async => <InternetAddress>[
  InternetAddress.loopbackIPv4,
];

final class _Cancellation implements SourceCancellationSignal {
  final Completer<void> _cancelled = Completer<void>();

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;
}
