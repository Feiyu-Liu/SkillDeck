import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:test/test.dart';

import '../support/test_host.dart';

void main() {
  late Directory temp;
  late TestHost host;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sd-client-');
  });
  tearDown(() async {
    await host.close();
    await temp.delete(recursive: true);
  });
  Future<void> start({
    HostRejectCode? reject,
    bool silent = false,
    bool malformed = false,
  }) async {
    host = TestHost(
      temp.path,
      reject: reject,
      silent: silent,
      malformed: malformed,
    );
    await host.start();
  }

  Future<CommandResult> status({
    Duration timeout = const Duration(seconds: 5),
  }) => CommandHostClient(
    runDirectory: temp.path,
    handshakeTimeout: timeout,
  ).execute(CommandRequest(command: 'status'));
  test('accepts handshake and one result', () async {
    await start();
    expect((await status()).data['appVersion'], '2.0.0');
  });
  test('wrong discovery secret is unauthorized', () async {
    await start();
    final discovery = (await readDiscovery(temp.path)).toJson();
    discovery['secret'] = base64Url.encode(List.filled(32, 8));
    await writePrivateFileAtomically(
      p.join(temp.path, commandHostDiscoveryFileName),
      utf8.encode(jsonEncode(discovery)),
    );
    await expectLater(
      status(),
      throwsA(
        isA<ClientFailure>().having(
          (e) => e.code,
          'code',
          ClientFailureCode.unauthorized,
        ),
      ),
    );
  });
  test('host rejects protocol mismatch', () async {
    await start(reject: HostRejectCode.protocolMismatch);
    await expectLater(
      status(),
      throwsA(
        isA<ClientFailure>().having(
          (e) => e.code,
          'code',
          ClientFailureCode.protocolMismatch,
        ),
      ),
    );
  });
  test('incompatible discovery fails before connecting', () async {
    await start();
    final discovery = (await readDiscovery(temp.path)).toJson()
      ..['protocolVersion'] = 2;
    await writePrivateFileAtomically(
      p.join(temp.path, commandHostDiscoveryFileName),
      utf8.encode(jsonEncode(discovery)),
    );
    await expectLater(
      status(),
      throwsA(
        isA<ClientFailure>().having(
          (e) => e.code,
          'code',
          ClientFailureCode.protocolMismatch,
        ),
      ),
    );
  });
  test('stale socket without listener is unavailable', () async {
    await start();
    final socketPath = p.join(temp.path, 'host.sock');
    final parked = p.join(temp.path, 'parked.sock');
    if (!Platform.isWindows) await File(socketPath).rename(parked);
    await host.close();
    if (!Platform.isWindows) await File(parked).rename(socketPath);
    await expectLater(
      status(),
      throwsA(
        isA<ClientFailure>().having(
          (e) => e.code,
          'code',
          ClientFailureCode.appUnavailable,
        ),
      ),
    );
  });
  test('handshake timeout is typed', () async {
    await start(silent: true);
    await expectLater(
      status(timeout: const Duration(milliseconds: 50)),
      throwsA(
        isA<ClientFailure>().having(
          (e) => e.code,
          'code',
          ClientFailureCode.timeout,
        ),
      ),
    );
  });
  test('malformed host response is typed', () async {
    await start(malformed: true);
    await expectLater(
      status(),
      throwsA(
        isA<ClientFailure>().having(
          (e) => e.code,
          'code',
          ClientFailureCode.protocolViolation,
        ),
      ),
    );
  });
}
