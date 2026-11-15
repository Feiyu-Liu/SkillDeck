import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import '../auth/client_test.dart' show cloudError;

void main() {
  test(
    'timed-out TLS openings remain bounded across transport instances',
    () async {
      final stalled = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      stalled.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {}, onError: (Object _) {});
      });
      final clients = List.generate(
        5,
        (_) => HttpsCloudTransport(
          baseUri: Uri.parse('https://127.0.0.1:${stalled.port}'),
          timeout: const Duration(milliseconds: 50),
        ),
      );
      try {
        await Future.wait(
          clients
              .take(4)
              .map(
                (client) => expectLater(
                  client.request(
                    CloudRequest(method: 'GET', path: '/v1/stall'),
                  ),
                  throwsA(cloudError(CloudErrorCode.timeout)),
                ),
              ),
        );
        expect(sockets, hasLength(4));
        await expectLater(
          clients.last.request(CloudRequest(method: 'GET', path: '/v1/stall')),
          throwsA(cloudError(CloudErrorCode.unavailable)),
        );
        expect(sockets, hasLength(4));
      } finally {
        for (final client in clients) {
          client.close();
        }
        for (final socket in sockets) {
          socket.destroy();
        }
        await stalled.close();
        await Future<void>.delayed(Duration.zero);
      }
    },
  );
  late Directory temporary;
  late SecurityContext serverTLS, clientTLS;
  late HttpServer server, redirectTarget;
  var redirected = 0;
  String? receivedAuthorization;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skilldeck-cloud-dart-tls-',
    );
    final key = '${temporary.path}/key.pem',
        cert = '${temporary.path}/cert.pem';
    final caKey = '${temporary.path}/ca.key', ca = '${temporary.path}/ca.pem';
    final csr = '${temporary.path}/leaf.csr',
        extensions = '${temporary.path}/extensions.cnf';
    await File(extensions).writeAsString(
      'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n',
    );
    for (final arguments in [
      [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        caKey,
        '-out',
        ca,
        '-subj',
        '/CN=SkillDeck Local Test CA',
        '-addext',
        'basicConstraints=critical,CA:TRUE',
        '-addext',
        'keyUsage=critical,keyCertSign,cRLSign',
        '-days',
        '1',
      ],
      [
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        key,
        '-out',
        csr,
        '-subj',
        '/CN=localhost',
      ],
      [
        'x509',
        '-req',
        '-in',
        csr,
        '-CA',
        ca,
        '-CAkey',
        caKey,
        '-CAcreateserial',
        '-out',
        cert,
        '-days',
        '1',
        '-extfile',
        extensions,
      ],
    ]) {
      final generated = await Process.run('openssl', arguments);
      expect(
        generated.exitCode,
        0,
        reason: 'temporary local CA and leaf generation',
      );
    }
    serverTLS = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    clientTLS = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(ca);
    redirectTarget = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    redirectTarget.listen((request) {
      redirected++;
      unawaited(request.response.close());
    });
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverTLS,
    );
    server.listen((request) {
      unawaited(() async {
        try {
          receivedAuthorization = request.headers.value(
            HttpHeaders.authorizationHeader,
          );
          final response = request.response;
          response.headers.contentType = ContentType.json;
          switch (request.uri.path) {
            case '/v1/redirect':
              response.statusCode = 302;
              response.headers.set(
                HttpHeaders.locationHeader,
                'http://127.0.0.1:${redirectTarget.port}/capture',
              );
            case '/v1/stall':
              response.write('{');
              await response.flush();
              return;
            case '/v1/large':
              response.write('x' * 1024);
            case '/v1/invalid':
              response.add([0xff, 0xfe]);
            case '/v1/invalid-json':
              response.write('{PRIVATE_REMOTE_ERROR');
            case '/v1/array':
              response.write('[]');
            default:
              response.write(
                jsonEncode({
                  'protocolVersion': 1,
                  'data': {'ok': true},
                }),
              );
          }
          await response.close();
        } catch (_) {
          /* Client cancellation intentionally closes test sockets. */
        }
      }());
    });
  });
  tearDownAll(() async {
    await server.close(force: true);
    await redirectTarget.close(force: true);
    await temporary.delete(recursive: true);
  });
  HttpsCloudTransport transport({
    Duration timeout = const Duration(milliseconds: 250),
    int maximum = 4096,
  }) => HttpsCloudTransport(
    baseUri: Uri.parse('https://127.0.0.1:${server.port}'),
    securityContext: clientTLS,
    timeout: timeout,
    maximumResponseBytes: maximum,
  );

  test('only HTTPS origins and API-relative paths are accepted', () {
    for (final value in [
      'http://example.invalid',
      'https://u:p@example.invalid',
      'https://example.invalid/path',
      'https://example.invalid?token=secret',
      'https://example.invalid#fragment',
    ]) {
      expect(
        () => HttpsCloudTransport(baseUri: Uri.parse(value)),
        throwsA(cloudError(CloudErrorCode.invalidConfiguration)),
      );
    }
    expect(
      () => CloudRequest(method: 'GET', path: '//evil.invalid/path'),
      throwsA(cloudError(CloudErrorCode.invalidRequest)),
    );
    expect(
      () => CloudRequest(method: 'GET', path: '/v1/../private'),
      throwsA(cloudError(CloudErrorCode.invalidRequest)),
    );
    expect(
      () => CloudRequest(method: 'GET', path: '/v1/test?token=secret'),
      throwsA(cloudError(CloudErrorCode.invalidRequest)),
    );
  });
  test(
    'real verified local TLS returns bounded JSON and trusted bearer headers',
    () async {
      final probe = HttpClient(context: clientTLS);
      try {
        final native = await (await probe.getUrl(
          Uri.parse('https://127.0.0.1:${server.port}/v1/ok'),
        )).close();
        expect(native.statusCode, 200);
        await native.drain<void>();
      } finally {
        probe.close(force: true);
      }
      final client = transport();
      addTearDown(client.close);
      final response = await client.request(
        CloudRequest(method: 'GET', path: '/v1/ok'),
        credential: CloudCredential('local-secret'),
      );
      expect(response.body['data'], {'ok': true});
      expect(receivedAuthorization, 'Bearer local-secret');
      expect(response.toString(), isNot(contains('local-secret')));
      client.close();
      await expectLater(
        client.request(CloudRequest(method: 'GET', path: '/v1/ok')),
        throwsA(cloudError(CloudErrorCode.cancelled)),
      );
    },
  );
  test('redirects never send credentials to the HTTP destination', () async {
    final client = transport();
    addTearDown(client.close);
    await expectLater(
      client.request(
        CloudRequest(method: 'GET', path: '/v1/redirect'),
        credential: CloudCredential('local-secret'),
      ),
      throwsA(cloudError(CloudErrorCode.redirectRejected)),
    );
    expect(redirected, 0);
  });
  test(
    'invalid UTF8/JSON and array bodies fail as non-retryable invalidResponse',
    () async {
      final client = transport();
      addTearDown(client.close);
      for (final path in ['invalid', 'invalid-json', 'array']) {
        await expectLater(
          client.request(CloudRequest(method: 'GET', path: '/v1/$path')),
          throwsA(cloudError(CloudErrorCode.invalidResponse)),
        );
      }
    },
  );
  test('encoded request and streaming response budgets fail before unbounded buffering', () async {
    final client = transport(maximum: 32);
    addTearDown(client.close);
    await expectLater(
      client.request(CloudRequest(method: 'GET', path: '/v1/large')),
      throwsA(cloudError(CloudErrorCode.responseTooLarge)),
    );
    final small = HttpsCloudTransport(
      baseUri: client.baseUri,
      maximumRequestBytes: 8,
    );
    addTearDown(small.close);
    await expectLater(
      small.request(
        CloudRequest(method: 'POST', path: '/v1/ok', body: {'large': 'x' * 30}),
      ),
      throwsA(cloudError(CloudErrorCode.invalidRequest)),
    );
  });
  test(
    'headers followed by a body that never emits again obey the total deadline',
    () async {
      final client = transport(timeout: const Duration(milliseconds: 80));
      addTearDown(client.close);
      final elapsed = Stopwatch()..start();
      await expectLater(
        client.request(CloudRequest(method: 'GET', path: '/v1/stall')),
        throwsA(cloudError(CloudErrorCode.timeout)),
      );
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );
  test('cancellation closes a stalled response instead of waiting for another chunk', () async {
    final client = transport(timeout: const Duration(seconds: 2));
    addTearDown(client.close);
    final cancellation = CloudCancellation();
    final result = client.request(
      CloudRequest(method: 'GET', path: '/v1/stall'),
      cancellation: cancellation,
    );
    final expectation = expectLater(
      result,
      throwsA(cloudError(CloudErrorCode.cancelled)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    cancellation.cancel();
    await expectation;
  });
  test(
    'pending TCP/TLS opening honors request deadline and cancellation',
    () async {
      final stalled = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final closed = Completer<void>();
      stalled.listen((socket) {
        sockets.add(socket);
        socket.listen(
          (_) {},
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
          onError: (Object _) {},
        );
      });
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await stalled.close();
      });
      final client = HttpsCloudTransport(
        baseUri: Uri.parse('https://127.0.0.1:${stalled.port}'),
        timeout: const Duration(milliseconds: 80),
      );
      addTearDown(client.close);
      await expectLater(
        client.request(CloudRequest(method: 'GET', path: '/v1/never')),
        throwsA(cloudError(CloudErrorCode.timeout)),
      );
      final cancellation = CloudCancellation();
      final request = client.request(
        CloudRequest(method: 'GET', path: '/v1/never'),
        cancellation: cancellation,
      );
      final check = expectLater(
        request,
        throwsA(cloudError(CloudErrorCode.cancelled)),
      );
      cancellation.cancel();
      await check;
    },
  );
}
