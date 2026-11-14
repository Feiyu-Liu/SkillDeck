import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  // These are build-phase contract tests, using a tiny command stub, not an SDK.
  // They never compile Dart, access home, resolve dependencies or use a network.
  group('macOS CLI build phase', () {
    late Directory temp;
    late String project;
    late String package;
    late String script;
    late String output;
    late String mainExecutable;
    late File calls;
    late File failure;
    late Map<String, String> environment;
    // A stand-in helper that launches, so the signed-launch check passes.
    const compiledCli = '#!/bin/bash\nexit 0\n';

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('sd-cli-phase-');
      project = p.join(temp.path, 'app', 'macos');
      package = p.join(temp.path, 'packages', 'skilldeck_cli');
      await Directory(p.join(package, 'lib')).create(recursive: true);
      await Directory(p.join(package, 'bin')).create();
      await File(p.join(package, 'lib', 'client.dart')).writeAsString('client');
      await File(p.join(package, 'bin', 'skilldeck.dart'))
          .writeAsString('entry');
      await File(p.join(package, 'pubspec.yaml')).writeAsString('manifest');
      await File(p.join(package, 'pubspec.lock')).writeAsString('lock');
      await Directory(p.join(project, 'scripts')).create(recursive: true);
      script = p.join(project, 'scripts', 'bundle_skilldeck_cli.sh');
      await File('macos/scripts/bundle_skilldeck_cli.sh').copy(script);
      for (final name in [
        'bundle_skilldeck_universal_cli.sh',
        'universal_cli_launcher.c',
      ]) {
        await File('macos/scripts/$name')
            .copy(p.join(project, 'scripts', name));
      }
      await File('macos/scripts/skilldeck_cli.entitlements')
          .copy(p.join(project, 'scripts', 'skilldeck_cli.entitlements'));
      final commandDirectory = await Directory(
        p.join(temp.path, 'commands', 'bin'),
      ).create(recursive: true);
      final dart = File(p.join(commandDirectory.path, 'dart'));
      await dart.writeAsString(r'''#!/bin/bash
set -eu
if [[ "$1" == --suppress-analytics ]]; then shift; fi
if [[ "$1" == --version ]]; then echo 'Dart SDK version: 3.14.0 (stable)'; exit 0; fi
printf '%s\n' "$1" >> "$TEST_CALLS"
if [[ -f "$TEST_FAILURE" && "$(cat "$TEST_FAILURE")" == "$1" ]]; then
  echo 'private tool output which must not enter the build log' >&2
  exit 1
fi
if [[ "$1" == compile ]]; then
  if [[ "${TEST_EXPECT_AOT:-}" == 1 ]]; then
    [[ "$2" == aot-snapshot ]]
  else
    [[ "$*" == *"--target-arch=$TEST_ARCH"* ]]
  fi
  while [[ "$1" != -o ]]; do shift; done
  shift
  printf '%s' "$TEST_COMPILED_CLI" > "$1"
fi
''');
      // Signs nothing, but insists on the entitlements the helper launches with.
      final codesign = File(p.join(commandDirectory.path, 'codesign'));
      await codesign.writeAsString(r'''#!/bin/bash
set -eu
while [[ $# -gt 0 && "$1" != --entitlements ]]; do shift; done
[[ $# -ge 2 && -f "$2" ]]
grep -q allow-unsigned-executable-memory "$2"
''');
      final lipo = File(p.join(commandDirectory.path, 'lipo'));
      await lipo.writeAsString('#!/bin/bash\nuname -m\n');
      for (final command in [dart, codesign, lipo]) {
        expect(
          (await Process.run('/bin/chmod', ['755', command.path])).exitCode,
          0,
        );
      }
      calls = File(p.join(temp.path, 'calls'));
      failure = File(p.join(temp.path, 'failure'));
      final build = p.join(temp.path, 'build');
      output = p.join(
        build,
        'SkillDeck.app',
        'Contents',
        'Helpers',
        'skilldeck',
      );
      mainExecutable = p.join(
        build,
        'SkillDeck.app',
        'Contents',
        'MacOS',
        'SkillDeck',
      );
      environment = {
        'PROJECT_DIR': project,
        'ARCHS': 'arm64',
        'SKILLDECK_CLI_X86_64': '',
        'DESKTOP_RELEASE_ARCHITECTURE': 'universal',
        'ONLY_ACTIVE_ARCH': 'NO',
        'FLUTTER_ROOT': p.dirname(commandDirectory.path),
        'DERIVED_FILE_DIR': p.join(temp.path, 'derived'),
        'TARGET_BUILD_DIR': build,
        'EXECUTABLE_FOLDER_PATH': 'SkillDeck.app/Contents/MacOS',
        'CONTENTS_FOLDER_PATH': 'SkillDeck.app/Contents',
        'EXPANDED_CODE_SIGN_IDENTITY': '-',
        'TEST_CALLS': calls.path,
        'TEST_ARCH': 'arm64',
        'TEST_FAILURE': failure.path,
        'TEST_COMPILED_CLI': compiledCli,
        'PATH': '${commandDirectory.path}:${Platform.environment['PATH']}',
      };
    });
    tearDown(() async => temp.delete(recursive: true));

    Future<ProcessResult> run() =>
        Process.run('/bin/bash', [script], environment: environment);

    Future<void> universalInputs() async {
      environment['ARCHS'] = 'arm64 x86_64';
      environment['TEST_COMPILED_CLI'] = r'''#!/bin/bash
echo "${TEST_RUNTIME_HELP:-Usage: skilldeck <command>}"
''';
      final intel = File(p.join(temp.path, 'skilldeck.x86_64'));
      await intel.writeAsString(compiledCli);
      await Process.run('/bin/chmod', ['755', intel.path]);
      environment['SKILLDECK_CLI_X86_64'] = intel.path;
      final commands = p.join(environment['FLUTTER_ROOT']!, 'bin');
      await File(p.join(commands, 'lipo')).writeAsString(r'''#!/bin/bash
set -eu
[[ "$1" == -archs ]]
echo x86_64
''');
      final host = File(p.join(commands, 'uname'));
      await host.writeAsString('#!/bin/bash\necho arm64\n');
      await Process.run('/bin/chmod', ['755', host.path]);
      final compiler = File(p.join(commands, 'xcrun'));
      await compiler.writeAsString(r'''#!/bin/bash
set -eu
while [[ "$1" != -o ]]; do shift; done
cat > "$2" <<'LAUNCHER'
#!/bin/bash
exec "$(dirname "$0")/SkillDeckCLI/skilldeck.arm64" "$@"
LAUNCHER
''');
      await Process.run('/bin/chmod', ['755', compiler.path]);
    }

    test(
      'universal rejects missing Intel input before replacing a helper',
      () async {
        environment['ARCHS'] = 'arm64 x86_64';
        final result = await run();
        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains('native x86_64 SkillDeck executable'));
        expect(await File(output).exists(), isFalse);
      },
    );

    test(
      'universal bundles both CLIs, caches and restores deleted payloads',
      () async {
        await universalInputs();
        expect((await run()).exitCode, 0);
        final payload = Directory(p.join(p.dirname(output), 'SkillDeckCLI'));
        expect(
          File(p.join(payload.path, 'skilldeck.arm64')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(payload.path, 'skilldeck.x86_64')).existsSync(),
          isTrue,
        );
        await payload.delete(recursive: true);
        expect((await run()).exitCode, 0);
        expect(await calls.readAsLines(), ['pub', 'compile']);
        final help = await Process.run(output, ['--help']);
        expect(help.stdout, contains('Usage: skilldeck'));
        await File(environment['SKILLDECK_CLI_X86_64']!)
            .writeAsString('changed Intel executable');
        expect((await run()).exitCode, 0);
        expect(await calls.readAsLines(), ['pub', 'compile', 'pub', 'compile']);
      },
    );

    test('universal rejects VM help even when its exit code is zero', () async {
      await universalInputs();
      expect((await run()).exitCode, 0);
      await File(output).writeAsString('previous helper');
      environment['TEST_RUNTIME_HELP'] = 'Usage: dartvm [vm-flags]';
      final result = await run();
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('did not execute the SkillDeck CLI'));
      expect(await File(output).readAsString(), 'previous helper');
    });

    test(
      'bundles, caches compilation and restores a deleted bundle output',
      () async {
        expect((await run()).exitCode, 0);
        expect(await File(output).readAsString(), compiledCli);
        expect((await File(output).stat()).mode & 0x1ff, 0x1ed);
        await File(output).delete();
        expect((await run()).exitCode, 0);
        expect(await calls.readAsLines(), ['pub', 'compile']);
        expect(await File(output).readAsString(), compiledCli);
      },
    );

    test(
      'never touches the App executable beside a case-insensitive name',
      () async {
        // On the default macOS volume "skilldeck" and "SkillDeck" are one file.
        await File(mainExecutable).create(recursive: true);
        await File(mainExecutable).writeAsString('the App');

        expect((await run()).exitCode, 0);

        expect(await File(mainExecutable).readAsString(), 'the App');
        expect(await File(output).readAsString(), compiledCli);
      },
    );

    for (final input in [
      'lib/client.dart',
      'bin/skilldeck.dart',
      'pubspec.lock',
    ]) {
      test('recompiles when $input changes', () async {
        expect((await run()).exitCode, 0);
        await File(p.join(package, input)).writeAsString('changed');
        expect((await run()).exitCode, 0);
        expect(await calls.readAsLines(), ['pub', 'compile', 'pub', 'compile']);
      });
    }

    test('architecture changes invalidate the cached executable', () async {
      expect((await run()).exitCode, 0);
      environment['ARCHS'] = 'x86_64';
      environment['TEST_ARCH'] = 'x64';
      expect((await run()).exitCode, 0);
      expect(await calls.readAsLines(), ['pub', 'compile', 'pub', 'compile']);
    });

    test(
      'active-architecture debug builds compile only the active slice',
      () async {
        environment['ARCHS'] = 'arm64 x86_64';
        environment['ONLY_ACTIVE_ARCH'] = 'YES';
        environment['NATIVE_ARCH_ACTUAL'] = 'arm64';
        expect((await run()).exitCode, 0);
        expect(await calls.readAsLines(), ['pub', 'compile']);
      },
    );

    test('single-architecture release extraction keeps a thin CLI', () async {
      environment['ARCHS'] = 'arm64 x86_64';
      environment['DESKTOP_RELEASE_ARCHITECTURE'] = 'x86_64';
      environment['TEST_ARCH'] = 'x64';
      final stale = Directory(p.join(p.dirname(output), 'SkillDeckCLI'));
      await stale.create(recursive: true);
      await File(p.join(stale.path, 'skilldeck.arm64')).writeAsString('stale');
      expect((await run()).exitCode, 0);
      expect(await calls.readAsLines(), ['pub', 'compile']);
      expect(await stale.exists(), isFalse);
    });

    test('detects source additions and deletions', () async {
      expect((await run()).exitCode, 0);
      final extra = File(p.join(package, 'lib', 'extra.dart'));
      await extra.writeAsString('extra');
      expect((await run()).exitCode, 0);
      await extra.delete();
      expect((await run()).exitCode, 0);
      expect(
        (await calls.readAsLines()).where((line) => line == 'compile').length,
        3,
      );
    });

    test('a signed helper that does not launch fails the build', () async {
      environment['TEST_COMPILED_CLI'] = '#!/bin/bash\nkill -9 \$\$\n';
      final result = await run();
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('does not launch'));
      expect(File(output).existsSync(), isFalse);
    });

    for (final step in ['pub', 'compile']) {
      test(
        '$step failure fails the build and preserves the previous helper',
        () async {
          expect((await run()).exitCode, 0);
          await File(output).writeAsString('previous helper');
          await File(p.join(package, 'lib', 'client.dart'))
              .writeAsString('changed');
          await failure.writeAsString(step);
          final result = await run();
          expect(result.exitCode, isNot(0));
          expect(await File(output).readAsString(), 'previous helper');
          expect(result.stderr, isNot(contains('private tool output')));
          expect(result.stderr, isNot(contains(temp.path)));
          await failure.delete();
          expect((await run()).exitCode, 0);
          expect(await File(output).readAsString(), compiledCli);
        },
      );
    }
  }, skip: !Platform.isMacOS);
}
