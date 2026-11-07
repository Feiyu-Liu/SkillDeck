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
        cwd: windows ? r'C:\work' : '/work',
        isWindows: windows,
      );
  test('source replace preserves selectors and carries destination and approval controls', () {
    final result = parse([
      '--json',
      'source',
      'replace',
      '--source',
      'github.com/old/repo',
      '--to',
      '../new',
      '--ref',
      'next',
      '--keep-going',
      '--approval-timeout',
      '0',
      '--dry-run',
    ]);
    expect(result.command, 'source replace');
    expect(result.json, true);
    expect(result.requestArguments, {
      'selection': SkillSelection(sourcePrefix: 'github.com/old/repo').toJson(),
      'to': '/new',
      'ref': 'next',
      'dryRun': true,
      'keepGoing': true,
      'wait': 30,
      'approvalTimeout': 0,
    });
    expect(
      parse([
        'source',
        'replace',
        'alpha',
        '--to',
        'new/repo',
        '--skill',
        'beta',
      ]).requestArguments['skill'],
      'beta',
    );
    expect(
      parse(['source', 'replace', 'alpha', '--to', 'new/repo']).requestArguments
          .containsKey('ref'),
      false,
    );
    expect(
      parse([
        'source',
        'replace',
        '--all',
        '--to',
        r'..\new',
      ], windows: true).requestArguments['to'],
      r'C:\new',
    );
  });

  test('missing destination or selection, multi-ref --skill and bypasses are usage errors', () {
    for (final args in [
      ['source'],
      ['source', 'replace', '--all'],
      ['source', 'replace', '--to', 'new/repo'],
      ['source', 'replace', '--all', '--to', ''],
      [
        'source',
        'replace',
        'alpha',
        'beta',
        '--to',
        'new/repo',
        '--skill',
        'alpha',
      ],
      for (final flag in ['--yes', '--force', '--skip-approval'])
        ['source', 'replace', '--all', '--to', 'new/repo', flag],
      [
        'source',
        'replace',
        '--all',
        '--to',
        'new/repo',
        '--approval-timeout',
        '601',
      ],
    ]) {
      expect(() => parse(args), throwsFormatException, reason: '$args');
    }
    // A filter's cardinality is known only in the App, which validates it.
    expect(
      parse([
        'source',
        'replace',
        '--source',
        'old/repo',
        '--to',
        'new/repo',
        '--skill',
        'alpha',
      ]).requestArguments['skill'],
      'alpha',
    );
  });

  test('replacement exit-code matrix and human output', () {
    for (final entry in {
      'replacementCandidateAmbiguous': 2,
      'replacementCandidateNotFound': 1,
      'replacementSlotOccupied': 1,
      'partialBatch': 3,
      'approvalPending': 5,
      'actionRequired': 5,
      'operationCancelled': 130,
      'approvalDenied': 1,
    }.entries) {
      expect(
        commandExitCode(
          CommandResult.failure('source replace', entry.key, 'Failed.'),
        ),
        entry.value,
      );
    }
    for (final entry in {
      'succeeded': 'replaced',
      'wouldSucceed': 'would be replaced',
      'unchanged': 'unchanged',
      'skipped': 'skipped',
      'committedFinalizationPending': 'replaced, cleanup pending',
    }.entries) {
      final result = replacement(entry.key);
      final text = renderHumanResult(result);
      expect(text, contains(entry.value));
      expect(text, contains('old/repo → new/repo'));
      final status = CommandResult(
        ok: true,
        command: 'approvals wait',
        data: {'result': result.toJson()},
      );
      expect(renderHumanResult(status), text);
    }
  });

  test(
    'JSON contains one document with mappings and partial-batch exit code',
    () async {
      final result = CommandResult(
        ok: false,
        command: 'source replace',
        results: replacement('succeeded').results,
        error: CommandError(
          code: 'partialBatch',
          message: 'A later item failed.',
        ),
      );
      final out = StringBuffer();
      final err = StringBuffer();
      final connection = _Connection(result);
      final code = await runSkilldeck(
        ['source', 'replace', '--all', '--to', 'new/repo', '--json'],
        environment: const {'HOME': '/unused'},
        isWindows: false,
        cwd: '/work',
        out: out,
        err: err,
        interrupts: const Stream.empty(),
        appLauncher: AppLauncher(
          runDirectory: '/unused',
          connect: ({timeout}) async => connection,
        ),
      );
      expect(code, 3);
      expect(
        jsonDecode(out.toString()),
        Map.of(result.toJson())..remove('type'),
      );
      expect(err.toString(), isEmpty);
      expect(connection.request?.arguments['to'], 'new/repo');
    },
  );
}

CommandResult replacement(String outcome) => CommandResult(
  ok: true,
  command: 'source replace',
  results: [
    {
      'id': 'alpha',
      'slotKey': 'alpha',
      'outcome': outcome,
      'from': {'kind': 'git', 'locator': 'old/repo'},
      'to': {'kind': 'git', 'locator': 'new/repo'},
    },
  ],
);

final class _Connection implements CommandHostConnection {
  _Connection(this.result);
  final CommandResult result;
  CommandRequest? request;
  @override
  Future<CommandResult> execute(CommandRequest request) async {
    this.request = request;
    return result;
  }

  @override
  Future<void> close() async {}
}
