import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skilldeck_cli/src/cli/command_line.dart';
import 'package:skilldeck_cli/src/cli/exit_code.dart';
import 'package:skilldeck_cli/src/cli/human_output.dart';
import 'package:test/test.dart';

void main() {
  SkilldeckCommandLine parse(List<String> args) => parseSkilldeckCommandLine(
    ['source', 'relink', ...args],
    cwd: '/work',
    isWindows: false,
  );

  test(
    'optional selection and default keep-going with explicit lock source',
    () {
      final result = parse(['--from-skills-lock', '--dry-run', '--json']);
      expect(result.command, 'source relink');
      expect(result.json, true);
      expect(result.requestArguments, {
        'fromSkillsLock': true,
        'dryRun': true,
        'keepGoing': true,
        'approvalTimeout': 90,
        'wait': 30,
      });
      final narrowed = parse([
        'alpha',
        '--from-skills-lock',
        '--no-keep-going',
        '--approval-timeout',
        '0',
      ]);
      expect(
        narrowed.requestArguments['selection'],
        SkillSelection(refs: ['alpha']).toJson(),
      );
      expect(narrowed.requestArguments['keepGoing'], false);
      expect(narrowed.requestArguments['approvalTimeout'], 0);
      expect(
        parse(['--from-skills-lock', '--source', 'old/repo', '--keep-going'])
            .requestArguments['selection'],
        SkillSelection(sourcePrefix: 'old/repo').toJson(),
      );
    },
  );

  test(
    'requires from-skills-lock and rejects replacement flags or bypasses',
    () {
      for (final args in [
        <String>[],
        ['alpha'],
        ['--no-from-skills-lock'],
        for (final flag in ['--to', '--ref', '--skill'])
          ['--from-skills-lock', flag, 'value'],
        ['--from-skills-lock', '--yes'],
        ['--from-skills-lock', '--approval-timeout', '601'],
      ]) {
        expect(() => parse(args), throwsFormatException);
      }
      expect(parse(['--help']).command, 'help');
    },
  );

  test('human output uses replacement verbs and counts inspected Sources', () {
    for (final dryRun in [true, false]) {
      final text = renderHumanResult(
        CommandResult(
          ok: true,
          command: 'source relink',
          data: {
            'dryRun': dryRun,
            'sources': ['one/repo', 'two/repo'],
          },
          results: [
            {
              'id': 'alpha',
              'slotKey': 'alpha',
              'outcome': dryRun ? 'wouldSucceed' : 'succeeded',
              'from': {'locator': 'adopted/alpha'},
              'to': {'locator': 'one/repo'},
            },
          ],
        ),
      );
      expect(text, contains(dryRun ? 'would be replaced' : 'replaced'));
      expect(text, contains('adopted/alpha → one/repo'));
      expect(text, endsWith(', 2 sources inspected'));
    }
  });

  test('skipped rows show their reason and come after what changed', () {
    final result = CommandResult(
      ok: true,
      command: 'source relink',
      data: {
        'dryRun': false,
        'sources': ['one/repo'],
      },
      results: [
        {
          'id': 'beta',
          'slotKey': 'beta',
          'outcome': 'skipped',
          'reason': {'code': 'lockEntryMissing', 'message': 'No hint.'},
        },
        {
          'id': 'alpha',
          'slotKey': 'alpha',
          'outcome': 'succeeded',
          'from': {'locator': 'adopted/alpha'},
          'to': {'locator': 'one/repo'},
        },
      ],
    );
    final lines = renderHumanResult(result).split('\n');
    expect(lines[0], startsWith('✓ alpha'));
    expect(lines[1], contains('skipped (lockEntryMissing)'));
    expect(lines.last, startsWith('1 replaced, 1 skipped'));
    expect(commandExitCode(result), 0);
  });

  test('lock and eligibility error codes use default failure exit code', () {
    for (final code in [
      'lockUnavailable',
      'lockEntryMissing',
      'lockSourceUnsupported',
      'notAdopted',
    ]) {
      expect(
        commandExitCode(
          CommandResult.failure('source relink', code, 'Failed.'),
        ),
        1,
      );
    }
  });
}
