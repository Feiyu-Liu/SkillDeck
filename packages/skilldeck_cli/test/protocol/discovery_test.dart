import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sd-discovery-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('run directory uses only injected environment', () {
    expect(
      commandHostRunDirectory(environment: {'HOME': '/test'}, isWindows: false),
      '/test/.skilldeck/run',
    );
    expect(
      commandHostRunDirectory(
        environment: {'USERPROFILE': r'C:\test'},
        isWindows: true,
      ),
      r'C:\test\.skilldeck\run',
    );
    for (final windows in [false, true]) {
      expect(
        () => commandHostRunDirectory(environment: {}, isWindows: windows),
        throwsA(
          isA<ClientFailure>().having(
            (e) => e.code,
            'code',
            ClientFailureCode.missingHome,
          ),
        ),
      );
    }
  });
  test('discovery round trips each endpoint and secure atomic file', () async {
    final run = p.join(temp.path, 'run');
    await ensurePrivateDirectory(run);
    for (final endpoint in [
      CommandHostEndpoint.unixSocket(p.join(run, 'host.sock')),
      const CommandHostEndpoint.loopbackTcp(1234),
    ]) {
      final discovery = CommandHostDiscovery(
        protocolVersion: 1,
        appVersion: '1.0',
        pid: 123,
        endpoint: endpoint,
        secret: base64Url.encode(List.filled(32, 1)),
      );
      final path = p.join(run, commandHostDiscoveryFileName);
      await writePrivateFileAtomically(
        path,
        utf8.encode(jsonEncode(discovery.toJson())),
      );
      expect((await readDiscovery(run)).toJson(), discovery.toJson());
      if (!Platform.isWindows) {
        expect((await File(path).stat()).mode & 511, 384);
        expect((await Directory(run).stat()).mode & 511, 448);
      }
    }
    expect((await Directory(run).list().toList()).length, 1);
  });
  test('rejects group/other readable discovery', () async {
    final path = p.join(temp.path, commandHostDiscoveryFileName);
    await File(path).writeAsString('{}');
    await Process.run('chmod', ['0644', path]);
    await expectLater(
      readDiscovery(temp.path),
      throwsA(
        isA<ClientFailure>().having(
          (e) => e.code,
          'code',
          ClientFailureCode.insecureDiscovery,
        ),
      ),
    );
  }, skip: Platform.isWindows);
  test('missing discovery is unavailable', () async {
    await expectLater(
      readDiscovery(temp.path),
      throwsA(
        isA<ClientFailure>().having(
          (e) => e.code,
          'code',
          ClientFailureCode.appUnavailable,
        ),
      ),
    );
  });
  test('malformed discovery has safe typed failure', () async {
    await writePrivateFileAtomically(
      p.join(temp.path, commandHostDiscoveryFileName),
      [123],
    );
    await expectLater(
      readDiscovery(temp.path),
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
