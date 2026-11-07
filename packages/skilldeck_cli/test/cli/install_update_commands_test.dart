import 'dart:async';
import 'dart:convert';

import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skilldeck_cli/src/cli/command_line.dart';
import 'package:skilldeck_cli/src/cli/human_output.dart';
import 'package:skilldeck_cli/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  SkilldeckCommandLine parse(List<String> args, {bool windows = false}) =>
      parseSkilldeckCommandLine(
        args,
        cwd: windows ? r'C:\work\nested' : '/work/nested',
        isWindows: windows,
      );
  test(
    'install flags and relative source and project paths use injected cwd',
    () {
      final line = parse([
        'install',
        '../source',
        '--skill',
        'One',
        '--skill',
        'Two',
        '--agent',
        'codex',
        '--agent',
        'claude',
        '--project',
        '../project',
        '--dry-run',
        '--keep-going',
        '--json',
        '--no-launch',
        '--wait',
        '8',
      ]);
      expect(line.json, true);
      expect(line.noLaunch, true);
      expect(line.requestArguments, {
        'source': '/work/source',
        'skills': ['One', 'Two'],
        'allSkills': false,
        'agents': ['codex', 'claude'],
        'projectPath': '/work/project',
        'dryRun': true,
        'keepGoing': true,
        'wait': 8,
      });
      expect(
        parse([
          'install',
          r'..\source',
        ], windows: true).requestArguments['source'],
        r'C:\work\source',
      );
      expect(
        parse(['install', '.', '--all-skills']).requestArguments['allSkills'],
        true,
      );
    },
  );
  test('remote source spellings reach the GUI parser intact', () {
    for (final source in [
      'owner/repo',
      'https://example.test/catalog',
      'git@github.com:owner/repo.git',
      'file:///fixture/source',
      '~/skills',
    ]) {
      expect(parse(['install', source]).requestArguments['source'], source);
    }
  });
  test('update accepts checks, writes and every normal selection filter', () {
    final line = parse([
      'update',
      'opaque',
      '--all',
      '--tag',
      'Dart',
      '--favorite',
      '--untagged',
      '--source',
      'https://example.test',
      '--active-for',
      'codex',
      '--project',
      '..',
      '--has-update',
      '--check',
      '--dry-run',
      '--keep-going',
    ]);
    expect(line.requestArguments, {
      'selection': SkillSelection(
        refs: ['opaque'],
        all: true,
        tags: ['Dart'],
        favorite: true,
        untagged: true,
        sourcePrefix: 'https://example.test',
        activeFor: 'codex',
        projectPath: '/work',
        hasUpdate: true,
      ).toJson(),
      'check': true,
      'dryRun': true,
      'keepGoing': true,
      'wait': 30,
    });
    expect(parse(['update', '--all']).requestArguments['check'], false);
  });
  for (final args in <List<String>>[
    ['install'],
    ['install', 'a', 'b'],
    ['install', 'owner/repo', '--skill', 'a', '--all-skills'],
    ['install', 'owner/repo', '--project', '.'],
    ['update'],
  ]) {
    test(
      'invalid flags: $args',
      () => expect(() => parse(args), throwsFormatException),
    );
  }
  test(
    'human verbs name each installed, updated, planned or checked Skill',
    () {
      for (final (command, outcome, verb) in [
        ('install', 'succeeded', 'installed'),
        ('update', 'succeeded', 'updated'),
        ('install', 'wouldSucceed', 'would be installed'),
        ('update', 'wouldSucceed', 'would be updated'),
        ('install', 'alreadyInstalled', 'already installed'),
        ('update', 'updateAvailable', 'update available'),
        ('update', 'upToDate', 'up to date'),
        ('update', 'checkFailed', 'check failed'),
      ]) {
        final text = renderHumanResult(
          CommandResult(
            ok: true,
            command: command,
            results: [
              {'slotKey': 'alpha', 'outcome': outcome},
            ],
          ),
        );
        expect(text, contains('alpha  $verb'));
        expect(text, contains('1 $verb'));
      }
    },
  );
  test('ambiguousSource lists candidates in human runner output, and JSON stays one document', () async {
    for (final json in [false, true]) {
      final result = CommandResult(
        ok: false,
        command: 'install',
        error: CommandError(
          code: 'ambiguousSource',
          message: 'Select a candidate.',
          details: {
            'candidates': [
              {'name': 'Alpha', 'slotKey': 'alpha', 'description': 'A'},
              {'name': 'Beta', 'slotKey': 'beta', 'description': 'B'},
            ],
          },
        ),
      );
      final out = StringBuffer();
      final err = StringBuffer();
      expect(
        await runSkilldeck(
          ['install', 'owner/repo', if (json) '--json'],
          environment: {'HOME': '/unused'},
          isWindows: false,
          cwd: '/fixture',
          out: out,
          err: err,
          interrupts: const Stream.empty(),
          appLauncher: AppLauncher(
            runDirectory: '/unused',
            connect: ({timeout}) async => _Connection(result),
          ),
        ),
        2,
      );
      if (json) {
        expect(
          (jsonDecode(out.toString()) as Map)['error']['code'],
          'ambiguousSource',
        );
        expect(out.toString().trim().split('\n'), hasLength(1));
        expect(err.toString(), isEmpty);
      } else {
        expect(
          out.toString().trim(),
          'Pass --skill <name> or --all-skills. Candidates: alpha, beta',
        );
      }
    }
  });
}

final class _Connection implements CommandHostConnection {
  _Connection(this.result);
  final CommandResult result;
  @override
  Future<CommandResult> execute(CommandRequest request) async => result;
  @override
  Future<void> close() async {}
}
