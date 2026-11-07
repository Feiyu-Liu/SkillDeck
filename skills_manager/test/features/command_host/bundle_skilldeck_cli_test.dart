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
      await File('macos/scripts/skilldeck_cli.entitlements')
          .copy(p.join(project, 'scripts', 'skilldeck_cli.entitlements'));
      final commandDirectory = await Directory(
        p.join(temp.path, 'commands', 'bin'),
      ).create(recursive: true);
      final dart = File(p.join(commandDirectory.path, 'dart'));
      await dart.writeAsString(r'''#!/bin/bash
set -eu
if [[ "$1" == --suppress-analytics ]]; then shift; fi
if [[ "$1" == --version ]]; then echo 'test Dart version'; exit 0; fi
printf '%s\n' "$1" >> "$TEST_CALLS"
if [[ -f "$TEST_FAILURE" && "$(cat "$TEST_FAILURE")" == "$1" ]]; then
  echo 'private tool output which must not enter the build log' >&2
  exit 1
fi
if [[ "$1" == compile ]]; then
  [[ "$*" == *"--target-arch=$TEST_ARCH"* ]]
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
