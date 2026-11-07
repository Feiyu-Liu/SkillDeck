import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skilldeck_cli/src/cli/command_line.dart';
import 'package:skilldeck_cli/src/cli/runner.dart';
import 'package:test/test.dart';

import '../support/test_host.dart';

Matcher fails(ClientFailureCode code) => throwsA(
  isA<ClientFailure>().having((failure) => failure.code, 'code', code),
);

final class FakeConnection implements CommandHostConnection {
  int commands = 0;
  int closes = 0;
  ClientFailureCode? commandFailure;
  @override
  Future<CommandResult> execute(CommandRequest request) async {
    commands++;
    if (commandFailure != null) throw ClientFailure(commandFailure!);
    return CommandResult(ok: true, command: request.command);
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  late Directory temp;
  late FakeConnection connection;
  late List<({String executable, List<String> args, ProcessStartMode mode})>
  starts;
  late List<Duration> delays;
  late Duration now;
  late int attempts;
  late int availableAfter;
  late AppLocation location;
  late bool executablePresent;
  late bool locationPresent;
  late int bundleStatus;
  late int pathStatus;
  late int notices;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sd-launch-');
    connection = FakeConnection();
    starts = [];
    delays = [];
    now = Duration.zero;
    attempts = 0;
    availableAfter = 3;
    location = const AppLocation(
      executablePath: '/Applications/SkillDeck.app/Contents/MacOS/SkillDeck',
      appVersion: '1.2.3',
      bundleIdentifier: 'test.skilldeck',
    );
    executablePresent = true;
    locationPresent = true;
    bundleStatus = 0;
    pathStatus = 0;
    notices = 0;
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<CommandHostConnection> connect({Duration? timeout}) async {
    attempts++;
    if (attempts < availableAfter) {
      throw const ClientFailure(ClientFailureCode.appUnavailable);
    }
    return connection;
  }

  Future<int> start(
    String executable,
    List<String> args, {
    required ProcessStartMode mode,
    required Duration timeout,
  }) async {
    starts.add((executable: executable, args: args, mode: mode));
    return args.contains('-a') ? pathStatus : bundleStatus;
  }

  AppLauncher launcher({String os = 'macos', HostConnector? connector}) =>
      AppLauncher(
        runDirectory: temp.path,
        operatingSystem: os,
        connect: connector ?? connect,
        startProcess: start,
        clock: () => now,
        delay: (duration) async {
          delays.add(duration);
          now += duration;
        },
        readLocation: () async {
          if (!locationPresent) {
            throw const ClientFailure(ClientFailureCode.appNotInstalled);
          }
          return location;
        },
        executableExists: (_) async => executablePresent,
      );
  Future<CommandResult> execute(
    AppLauncher launcher, {
    bool noLaunch = false,
  }) => launcher.execute(
    CommandRequest(command: 'status'),
    noLaunch: noLaunch,
    onStarting: () => notices++,
  );

  test(
    'first host answers: no launch, command once and connection closed',
    () async {
      availableAfter = 1;
      expect((await execute(launcher())).ok, isTrue);
      expect(starts, isEmpty);
      expect(attempts, 1);
      expect(notices, 0);
      expect(connection.commands, 1);
      expect(connection.closes, 1);
    },
  );
  test('no-launch never locks, reads location or launches', () async {
    expect(await Directory(p.join(temp.path, 'run')).exists(), isFalse);
    await expectLater(
      execute(launcher(), noLaunch: true),
      fails(ClientFailureCode.appUnavailable),
    );
    expect(starts, isEmpty);
    expect(await File(p.join(temp.path, 'launch.lock')).exists(), isFalse);
    expect(attempts, 1);
  });
  test('host appears after N polls with capped backoff', () async {
    availableAfter = 8;
    expect((await execute(launcher())).ok, isTrue);
    expect(starts, hasLength(1));
    expect(notices, 1);
    expect(connection.commands, 1);
    expect(delays.map((d) => d.inMilliseconds), [100, 200, 400, 500, 500]);
  });
  test('deadline uses fake clock, never sleeps beyond 30 seconds', () async {
    availableAfter = 10000;
    await expectLater(
      execute(launcher()),
      fails(ClientFailureCode.appLaunchTimeout),
    );
    expect(now, const Duration(seconds: 30));
    expect(starts, hasLength(1));
    expect(connection.commands, 0);
  });
  test(
    'missing location and vanished executable are appNotInstalled',
    () async {
      locationPresent = false;
      await expectLater(
        execute(launcher()),
        fails(ClientFailureCode.appNotInstalled),
      );
      locationPresent = true;
      executablePresent = false;
      attempts = 0;
      await expectLater(
        execute(launcher()),
        fails(ClientFailureCode.appNotInstalled),
      );
      expect(starts, isEmpty);
    },
  );
  test('missing app-location.json is typed without accessing home', () async {
    final app = AppLauncher(
      runDirectory: temp.path,
      operatingSystem: 'macos',
      connect: connect,
    );
    await expectLater(execute(app), fails(ClientFailureCode.appNotInstalled));
  });
  test(
    'invalid or non-private location metadata never starts a process',
    () async {
      for (final content in ['not json', '{}', '{"executablePath":42}']) {
        await writePrivateFileAtomically(
          p.join(temp.path, appLocationFileName),
          utf8.encode(content),
        );
        attempts = 0;
        final app = AppLauncher(
          runDirectory: temp.path,
          operatingSystem: 'macos',
          connect: connect,
          startProcess: start,
          executableExists: (_) async => true,
        );
        await expectLater(
          execute(app),
          fails(ClientFailureCode.appNotInstalled),
        );
      }
      if (!Platform.isWindows) {
        final file = File(p.join(temp.path, appLocationFileName));
        await file.delete();
        await file.writeAsString(jsonEncode(location.toJson()));
        // chmod is intentionally not applied: a regular user file is untrusted.
        if ((await file.stat()).mode & 63 != 0) {
          await expectLater(
            readAppLocation(temp.path),
            fails(ClientFailureCode.appNotInstalled),
          );
        }
      }
      expect(starts, isEmpty);
    },
  );
  test('process failures and deadlines expose only stable messages', () async {
    for (final error in [
      ProcessException('sensitive-path', [], 'sensitive-output'),
      TimeoutException('sensitive-output'),
    ]) {
      attempts = 0;
      final app = AppLauncher(
        runDirectory: temp.path,
        operatingSystem: 'macos',
        connect: connect,
        readLocation: () async => location,
        executableExists: (_) async => true,
        startProcess: (exe, args, {required mode, required timeout}) async =>
            throw error,
      );
      final out = StringBuffer();
      final err = StringBuffer();
      expect(
        await runSkilldeck(
          ['status', '--json'],
          environment: {'HOME': temp.path},
          isWindows: false,
          out: out,
          err: err,
          appLauncher: app,
        ),
        4,
      );
      final code = (jsonDecode(out.toString()) as Map)['error']['code'];
      expect(
        code,
        error is ProcessException ? 'appUnavailable' : 'appLaunchTimeout',
      );
      expect(out.toString(), isNot(contains('sensitive')));
      expect(err.toString(), isEmpty);
    }
  });
  test(
    'macOS opens the recorded bundle hidden and without activation',
    () async {
      await execute(launcher());
      expect(starts.single.executable, '/usr/bin/open');
      expect(starts.single.args, [
        '-g',
        '-j',
        '-a',
        '/Applications/SkillDeck.app',
        '--args',
        '--skilldeck-background',
      ]);
      expect(starts.single.mode, ProcessStartMode.normal);
    },
  );
  test(
    'macOS falls back to the bundle id only when the recorded path fails',
    () async {
      pathStatus = 1;
      await execute(launcher());
      expect(starts, hasLength(2));
      expect(starts.last.args, [
        '-g',
        '-j',
        '-b',
        'test.skilldeck',
        '--args',
        '--skilldeck-background',
      ]);
      starts.clear();
      attempts = 0;
      location = const AppLocation(
        executablePath: '/not/a/bundle/SkillDeck',
        appVersion: '1',
        bundleIdentifier: 'test.skilldeck',
      );
      await execute(launcher());
      expect(starts.single.args[2], '-b');
    },
  );
  test('Windows uses detached executable with background argument', () async {
    location = const AppLocation(
      executablePath: r'C:\SkillDeck\SkillDeck.exe',
      appVersion: '1',
    );
    await execute(launcher(os: 'windows'));
    expect(starts.single.executable, location.executablePath);
    expect(starts.single.args, ['--skilldeck-background']);
    expect(starts.single.mode, ProcessStartMode.detached);
  });
  test('Linux never launches', () async {
    await expectLater(
      execute(launcher(os: 'linux')),
      fails(ClientFailureCode.appUnavailable),
    );
    expect(starts, isEmpty);
  });
  test('non-availability handshake failures never launch', () async {
    for (final code in ClientFailureCode.values.where(
      (code) => code != ClientFailureCode.appUnavailable,
    )) {
      await expectLater(
        execute(
          launcher(
            connector: ({Duration? timeout}) async => throw ClientFailure(code),
          ),
        ),
        fails(code),
      );
    }
    expect(starts, isEmpty);
  });
  test('command failure is never retried or relaunched', () async {
    availableAfter = 1;
    connection.commandFailure = ClientFailureCode.appUnavailable;
    await expectLater(
      execute(launcher()),
      fails(ClientFailureCode.appUnavailable),
    );
    expect(connection.commands, 1);
    expect(connection.closes, 1);
    expect(starts, isEmpty);
  });
  test(
    'lock spans startup: concurrent launcher rechecks and does not relaunch',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var running = false;
      var secondAttempts = 0;
      Future<CommandHostConnection> host({Duration? timeout}) async {
        if (!running) {
          throw const ClientFailure(ClientFailureCode.appUnavailable);
        }
        return FakeConnection();
      }

      AppLauncher app({bool second = false}) => AppLauncher(
        runDirectory: temp.path,
        operatingSystem: 'macos',
        connect: ({Duration? timeout}) {
          if (second) secondAttempts++;
          return host(timeout: timeout);
        },
        readLocation: () async => location,
        executableExists: (_) async => true,
        startProcess: (exe, args, {required mode, required timeout}) async {
          starts.add((executable: exe, args: args, mode: mode));
          entered.complete();
          await release.future;
          running = true;
          return 0;
        },
      );
      final first = execute(app());
      await entered.future;
      final second = execute(app(second: true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(secondAttempts, 1);
      expect(starts, hasLength(1));
      release.complete();
      await Future.wait([first, second]);
      expect(secondAttempts, 2);
      expect(starts, hasLength(1));
    },
  );
  test(
    'OS launch lock excludes a separate process and rechecks after release',
    () async {
      final child = await Process.start(
        Platform.resolvedExecutable,
        [
          'test/support/launch_lock_holder.dart',
          p.join(temp.path, 'launch.lock'),
        ],
        environment: {'HOME': temp.path, 'USERPROFILE': temp.path},
        includeParentEnvironment: false,
      );
      final output = StreamIterator(
        child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      unawaited(child.stderr.drain<void>());
      try {
        expect(await output.moveNext(), isTrue);
        expect(output.current, 'locked');
        var running = false;
        final pending = execute(
          launcher(
            connector: ({Duration? timeout}) async {
              attempts++;
              if (!running) {
                throw const ClientFailure(ClientFailureCode.appUnavailable);
              }
              return connection;
            },
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(attempts, 1);
        expect(starts, isEmpty);
        running = true;
        child.stdin.writeln('release');
        expect(await child.exitCode, 0);
        expect((await pending).ok, isTrue);
        expect(attempts, 2);
        expect(starts, isEmpty);
      } finally {
        child.kill();
        await child.stdin.close();
        await output.cancel();
        await child.exitCode;
      }
    },
  );
  test(
    'stale discovery is not yet: real connection succeeds after launch',
    () async {
      final host = TestHost(temp.path);
      await host.start();
      await host.close(); // Leaves a private stale discovery file.
      var launches = 0;
      final app = AppLauncher(
        runDirectory: temp.path,
        operatingSystem: 'macos',
        readLocation: () async => location,
        executableExists: (_) async => true,
        startProcess: (exe, args, {required mode, required timeout}) async {
          launches++;
          await host.start();
          return 0;
        },
      );
      try {
        expect((await execute(app)).ok, isTrue);
        expect(launches, 1);
      } finally {
        await host.close();
      }
    },
  );
  test(
    'polling handshake timeout exhausts bounded budget and cleans sockets',
    () async {
      final host = TestHost(temp.path, silent: true);
      final app = AppLauncher(
        runDirectory: temp.path,
        operatingSystem: 'macos',
        launchTimeout: const Duration(milliseconds: 80),
        readLocation: () async => location,
        executableExists: (_) async => true,
        startProcess: (exe, args, {required mode, required timeout}) async {
          await host.start();
          return 0;
        },
      );
      try {
        await expectLater(
          execute(app),
          fails(ClientFailureCode.appLaunchTimeout),
        );
      } finally {
        await host.close();
      }
    },
  );
  test(
    'runner injects launcher, maps new errors to exit 4, JSON stays silent',
    () async {
      for (final code in [
        ClientFailureCode.appNotInstalled,
        ClientFailureCode.appLaunchTimeout,
      ]) {
        final app = AppLauncher(
          runDirectory: temp.path,
          connect: ({Duration? timeout}) async => throw ClientFailure(code),
        );
        final out = StringBuffer();
        final err = StringBuffer();
        expect(
          await runSkilldeck(
            ['status', '--json'],
            environment: {'HOME': temp.path},
            isWindows: false,
            out: out,
            err: err,
            appLauncher: app,
          ),
          4,
        );
        expect((jsonDecode(out.toString()) as Map)['error']['code'], code.name);
        expect(err.toString(), isEmpty);
      }
    },
  );
  test(
    'runner prints starting notice once in human mode and never in JSON',
    () async {
      for (final json in [false, true]) {
        attempts = 0;
        starts.clear();
        final out = StringBuffer();
        final err = StringBuffer();
        expect(
          await runSkilldeck(
            ['status', if (json) '--json'],
            environment: {'HOME': temp.path},
            isWindows: false,
            out: out,
            err: err,
            appLauncher: launcher(),
          ),
          0,
        );
        expect(
          err.toString(),
          json ? '' : 'Starting SkillDeck in the background…\n',
        );
        if (json) expect(jsonDecode(out.toString()), isA<Map>());
      }
    },
  );
  test('no-launch is respected before and after every app command', () async {
    for (final command in ['status', 'agents', 'list', 'show']) {
      final args = [
        command,
        if (command == 'list' || command == 'show') '--all',
      ];
      for (final options in [
        ['--no-launch', ...args],
        [...args, '--no-launch'],
      ]) {
        expect(
          parseSkilldeckCommandLine(
            options,
            cwd: temp.path,
            isWindows: false,
          ).noLaunch,
          isTrue,
        );
        attempts = 0;
        final out = StringBuffer();
        final err = StringBuffer();
        expect(
          await runSkilldeck(
            [...options, '--json'],
            environment: {'HOME': temp.path},
            isWindows: false,
            out: out,
            err: err,
            appLauncher: launcher(),
          ),
          4,
        );
        expect(
          (jsonDecode(out.toString()) as Map)['error']['code'],
          'appUnavailable',
        );
      }
    }
    expect(starts, isEmpty);
  });
}
