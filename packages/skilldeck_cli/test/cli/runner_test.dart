import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/src/cli/runner.dart';
import 'package:skilldeck_cli/src/cli/exit_code.dart';
import 'package:test/test.dart';

import '../support/test_host.dart';

void main() {
  late Directory temp;
  late StringBuffer out;
  late StringBuffer err;
  late Map<String, String> environment;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sd-cli-');
    out = StringBuffer();
    err = StringBuffer();
    environment = {'HOME': temp.path, 'USERPROFILE': temp.path};
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<int> run(List<String> args) => runSkilldeck(
    args,
    environment: environment,
    isWindows: Platform.isWindows,
    out: out,
    err: err,
  );
  Map<String, Object?> document() =>
      jsonDecode(out.toString()) as Map<String, Object?>;
  test('status JSON succeeds with exactly one output document', () async {
    final host = TestHost(p.join(temp.path, '.skilldeck', 'run'));
    await host.start();
    try {
      expect(await run(['status', '--json', '--no-launch', '--wait', '10']), 0);
      expect(document(), containsPair('ok', true));
      expect(document(), containsPair('schemaVersion', 1));
      expect(document(), containsPair('results', []));
      expect(document(), containsPair('command', 'status'));
      expect(document()['error'], isNull);
      expect(err.toString(), isEmpty);
    } finally {
      await host.close();
    }
  });
  test('unavailable emits one JSON failure and exits 4', () async {
    expect(await run(['--json', '--no-launch', 'status']), 4);
    expect(document()['ok'], false);
    expect((document()['error'] as Map)['code'], 'appUnavailable');
    expect(err.toString(), isEmpty);
  });
  for (final args in [
    ['--json', 'invalid'],
    ['status', '--bogus', '--json'],
    ['--json'],
    ['status', '--wait', '-1', '--json'],
  ]) {
    test('usage emits JSON and exits 2: $args', () async {
      expect(await run(args), 2);
      expect(document()['ok'], false);
      expect((document()['error'] as Map)['code'], 'usage');
      expect(err.toString(), isEmpty);
    });
  }
  test('human errors go only to stderr', () async {
    expect(await run(['status', '--no-launch']), 4);
    expect(out.toString(), isEmpty);
    expect(err.toString(), contains('Open SkillDeck'));
  });
  test('help and version work without discovery', () async {
    expect(await run(['--version']), 0);
    expect(out.toString().trim(), '0.1.0');
    out.clear();
    expect(await run(['--help', '--json']), 0);
    expect(document()['command'], 'help');
  });
  test('binary entry point returns exit code and JSON', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['bin/skilldeck.dart', 'status', '--json'],
      environment: environment,
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 4);
    expect((jsonDecode(result.stdout as String) as Map)['ok'], false);
    expect(result.stderr, isEmpty);
  });
  test('binary SIGINT during a pending handshake flushes one JSON result and exits 130', () async {
    final host = TestHost(p.join(temp.path, '.skilldeck', 'run'), silent: true);
    await host.start();
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['bin/skilldeck.dart', 'favorite', '--all', '--json', '--no-launch'],
      environment: environment,
      includeParentEnvironment: false,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      for (var i = 0; i < 500 && host.sockets.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(host.sockets, isNotEmpty);
      expect(process.kill(ProcessSignal.sigint), true);
      expect(await process.exitCode.timeout(const Duration(seconds: 3)), 130);
      final output = await stdout;
      expect(
        (jsonDecode(output) as Map)['error']['code'],
        'operationCancelled',
      );
      expect(output.trim().split('\n'), hasLength(1));
      expect(await stderr, isEmpty);
    } finally {
      process.kill();
      await host.close();
    }
  }, skip: Platform.isWindows);
  test('exit code values are stable', () {
    expect(CliExitCode.values.map((v) => v.value), [0, 1, 2, 3, 4, 5, 130]);
  });
}
