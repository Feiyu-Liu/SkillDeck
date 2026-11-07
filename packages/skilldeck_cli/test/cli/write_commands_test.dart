import 'dart:async';
import 'dart:convert';

import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skilldeck_cli/src/cli/command_line.dart';
import 'package:skilldeck_cli/src/cli/human_output.dart';
import 'package:skilldeck_cli/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  SkilldeckCommandLine parse(List<String> args) =>
      parseSkilldeckCommandLine(args, cwd: '/work/nested', isWindows: false);
  for (final command in ['activate', 'deactivate']) {
    test(
      '$command wire shape separates destination from selection and normalizes project',
      () {
        final line = parse([
          '--wait',
          '12',
          command,
          'opaque',
          '--agent',
          'codex',
          '--agent',
          'claude',
          '--project',
          '../demo',
          '--dry-run',
          '--keep-going',
          '--json',
        ]);
        expect(line.command, command);
        expect(line.json, true);
        expect(
          CommandRequest.fromJson(
            CommandRequest(
              command: line.command,
              arguments: line.requestArguments,
            ).toJson(),
          ).arguments,
          {
            'selection': SkillSelection(refs: ['opaque']).toJson(),
            'agents': ['codex', 'claude'],
            'projectPath': '/work/demo',
            'dryRun': true,
            'keepGoing': true,
            'wait': 12,
          },
        );
      },
    );
  }
  test('favorite off and every selection filter are available on writes', () {
    final line = parse([
      'favorite',
      '--all',
      '--off',
      '--tag',
      'Testing',
      '--untagged',
      '--favorite',
      '--source',
      'https://example.test',
      '--active-for',
      'codex',
      '--project',
      '.',
      '--has-update',
      '--dry-run',
      '--keep-going',
    ]);
    expect(line.requestArguments['favorite'], false);
    expect(
      line.requestArguments['selection'],
      SkillSelection(
        all: true,
        tags: ['Testing'],
        untagged: true,
        favorite: true,
        sourcePrefix: 'https://example.test',
        activeFor: 'codex',
        projectPath: '/work/nested',
        hasUpdate: true,
      ).toJson(),
    );
  });
  test('note set and clear preserve text only in structured arguments', () {
    expect(
      parse(['note', 'opaque', '--set', 'private\ntext'])
          .requestArguments['note'],
      {'set': 'private\ntext'},
    );
    expect(parse(['note', 'opaque', '--clear']).requestArguments['note'], {
      'clear': true,
    });
  });
  for (final action in ['add', 'remove']) {
    test('tag $action repeats tags without confusing them with filters', () {
      final line = parse([
        '--json',
        'tag',
        '--no-launch',
        action,
        '--all',
        '--tag',
        'One,Two',
        '--tag',
        'Three',
        '--dry-run',
        '--keep-going',
        '--wait',
        '9',
      ]);
      expect(line.command, 'tag $action');
      expect(line.noLaunch, true);
      expect(line.requestArguments['tags'], ['One,Two', 'Three']);
      expect(
        line.requestArguments['selection'],
        SkillSelection(all: true).toJson(),
      );
      expect(line.requestArguments['wait'], 9);
    });
  }
  test('tag rename carries one rename object', () {
    final line = parse(['tag', 'rename', 'old', 'new', '--dry-run']);
    expect(line.command, 'tag rename');
    expect(line.requestArguments, {
      'rename': {'from': 'old', 'to': 'new'},
      'dryRun': true,
      'keepGoing': false,
      'wait': 30,
    });
  });
  for (final args in <List<String>>[
    ['activate', '--all'],
    ['activate', '--agent', 'codex'],
    ['deactivate', '--all'],
    ['favorite'],
    ['note', 'id'],
    ['note', 'id', '--set', 'text', '--clear'],
    ['tag'],
    ['tag', 'add', '--all'],
    ['tag', 'remove', '--tag', 'Name'],
    ['tag', 'rename', 'old'],
    ['tag', 'rename', 'old', 'new', 'extra'],
  ]) {
    test(
      'invalid write arguments fail usage: $args',
      () => expect(() => parse(args), throwsFormatException),
    );
  }
  test(
    'batch exit matrix includes actionRequired, partial and cancellation',
    () {
      for (final entry in {
        'ioFailure': 1,
        'partialBatch': 3,
        'activationTargetOccupied': 5,
        'agentRootOwnershipRepairRequired': 5,
        'actionRequired': 5,
        'operationCancelled': 130,
        'unknownAgent': 2,
      }.entries) {
        expect(
          commandExitCode(
            CommandResult.failure('activate', entry.key, 'Failed.'),
          ),
          entry.value,
        );
      }
      for (final outcome in [
        'succeeded',
        'unchanged',
        'committedFinalizationPending',
      ]) {
        expect(
          commandExitCode(
            CommandResult(
              ok: true,
              command: 'activate',
              results: [
                {'outcome': outcome},
              ],
            ),
          ),
          0,
        );
      }
    },
  );
  test('human batch names each Skill with its outcome and a summary', () {
    final text = renderHumanResult(
      CommandResult(
        ok: false,
        command: 'activate',
        results: [
          for (final (index, outcome) in [
            'succeeded',
            'unchanged',
            'failed',
            'notAttempted',
            'committedFinalizationPending',
            'cancelled',
          ].indexed)
            {
              'id': 'id-$index',
              'slotKey': 'skill-$index',
              'outcome': outcome,
              if (outcome == 'failed')
                'error': {'code': 'activationTargetOccupied'},
            },
        ],
      ),
    );
    final lines = text.split('\n');
    expect(lines[0], '✓ skill-0  activated');
    expect(lines[1], '= skill-1  unchanged');
    expect(lines[2], '✗ skill-2  failed (activationTargetOccupied)');
    expect(lines[3], '– skill-3  not attempted');
    expect(lines[4], '… skill-4  activated, cleanup pending');
    expect(lines[5], '× skill-5  cancelled');
    expect(lines.last, startsWith('1 activated, 1 unchanged, 1 failed'));
    expect(text, isNot(contains('id-')));
  });
  test('human dry run and unfavorite use their own wording', () {
    final dryRun = renderHumanResult(
      CommandResult(
        ok: true,
        command: 'favorite',
        data: const {'dryRun': true},
        results: const [
          {'id': 'a', 'slotKey': 'alpha', 'outcome': 'wouldSucceed'},
        ],
      ),
      arguments: const {'favorite': false},
    );
    expect(
      dryRun,
      '→ alpha  would be unfavorited\n'
      '1 would be unfavorited (dry run, nothing changed)',
    );
  });
  test(
    'SIGINT closes the active connection and emits one cancelled JSON result',
    () async {
      final connection = _Connection();
      final interrupts = StreamController<void>();
      final out = StringBuffer();
      final err = StringBuffer();
      final running = runSkilldeck(
        ['favorite', '--all', '--json'],
        environment: {'HOME': '/unused'},
        isWindows: false,
        cwd: '/work',
        out: out,
        err: err,
        interrupts: interrupts.stream,
        appLauncher: AppLauncher(
          runDirectory: '/unused',
          connect: ({timeout}) async => connection,
        ),
      );
      await connection.started.future;
      interrupts.add(null);
      expect(await running, 130);
      expect(connection.closed, true);
      expect(
        (jsonDecode(out.toString()) as Map)['error']['code'],
        'operationCancelled',
      );
      expect(out.toString().trim().split('\n'), hasLength(1));
      expect(err.toString(), isEmpty);
      await interrupts.close();
    },
  );
}

final class _Connection implements CommandHostConnection {
  final started = Completer<void>();
  final result = Completer<CommandResult>();
  bool closed = false;
  @override
  Future<CommandResult> execute(CommandRequest request) {
    started.complete();
    return result.future;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!result.isCompleted) {
      result.complete(
        CommandResult.failure('favorite', 'operationCancelled', 'Cancelled.'),
      );
    }
  }
}
