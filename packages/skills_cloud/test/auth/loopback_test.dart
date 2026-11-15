import 'dart:io';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

import 'client_test.dart' show cloudError;

Future<int> call(Uri uri, {String? host, String method = 'GET'}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 200);
  try {
    final request = await client.openUrl(method, uri);
    if (host != null) request.headers.set(HttpHeaders.hostHeader, host);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('RFC S256 vector and cryptographic state shape', () {
    expect(
      cloudPKCEChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
    final tokens = List.generate(5, (_) => randomCloudToken());
    expect(tokens.toSet(), hasLength(5));
    expect(
      tokens.every((token) => RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)),
      isTrue,
    );
  });
  test('listener rejects wrong host port, state, path, duplicate parameters and method', () async {
    final state = randomCloudToken(), code = randomCloudToken();
    final listener = await LoopbackLoginListener.bind(state: state);
    addTearDown(listener.cancel);
    final uri = listener.redirectUri.replace(
      queryParameters: {'state': state, 'code': code},
    );
    expect(await call(uri, host: '127.0.0.1:49150'), 400);
    expect(await call(uri.replace(path: '/other')), 400);
    expect(
      await call(
        uri.replace(
          queryParameters: {'state': randomCloudToken(), 'code': code},
        ),
      ),
      400,
    );
    expect(await call(Uri.parse('$uri&state=$state')), 400);
    expect(await call(Uri.parse('$uri&extra=1')), 400);
    expect(await call(uri, method: 'POST'), 400);
    expect(await call(uri), 200);
    final result = await listener.result;
    expect(result.code, code);
    expect(result.toString(), isNot(contains(code)));
    await expectLater(call(uri), throwsA(isA<SocketException>()));
  });
  test('timeout and cancellation both close the real bound socket', () async {
    final timed = await LoopbackLoginListener.bind(
      state: randomCloudToken(),
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      timed.result,
      throwsA(cloudError(CloudErrorCode.timeout)),
    );
    await expectLater(call(timed.redirectUri), throwsA(isA<SocketException>()));
    await timed.cancel();
    final cancellation = CloudCancellation();
    final cancelled = await LoopbackLoginListener.bind(
      state: randomCloudToken(),
      cancellation: cancellation,
    );
    final expectation = expectLater(
      cancelled.result,
      throwsA(cloudError(CloudErrorCode.cancelled)),
    );
    cancellation.cancel();
    await expectation;
    await expectLater(
      call(cancelled.redirectUri),
      throwsA(isA<SocketException>()),
    );
    await cancelled.cancel();
    await expectLater(
      LoopbackLoginListener.bind(
        state: randomCloudToken(),
        cancellation: cancellation,
      ),
      throwsA(cloudError(CloudErrorCode.cancelled)),
    );
  });
  test('invalid state or deadline never binds a listener', () async {
    await expectLater(
      LoopbackLoginListener.bind(state: 'short'),
      throwsA(cloudError(CloudErrorCode.invalidRequest)),
    );
    await expectLater(
      LoopbackLoginListener.bind(
        state: randomCloudToken(),
        timeout: Duration.zero,
      ),
      throwsA(cloudError(CloudErrorCode.invalidRequest)),
    );
  });
}
