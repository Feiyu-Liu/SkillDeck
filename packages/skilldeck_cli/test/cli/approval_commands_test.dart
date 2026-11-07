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
      parseSkilldeckCommandLine(args, cwd: '/work', isWindows: false);

  test(
    'destructive commands carry selectors, dry run, and approval timeout',
    () {
      final removal = parse([
        'remove',
        'alpha',
        '--tag',
        'Testing',
        '--dry-run',
        '--approval-timeout',
        '0',
      ]);
      expect(removal.command, 'remove');
      expect(removal.requestArguments, {
        'selection': SkillSelection(
          refs: ['alpha'],
          tags: ['Testing'],
        ).toJson(),
        'dryRun': true,
        'wait': 30,
        'approvalTimeout': 0,
      });
      final deletion = parse([
        'tag',
        'delete',
        'Testing',
        '--approval-timeout',
        '600',
        '--dry-run',
      ]);
      expect(deletion.command, 'tag delete');
      expect(deletion.requestArguments, {
        'tag': 'Testing',
        'dryRun': true,
        'wait': 30,
        'approvalTimeout': 600,
      });
      expect(
        parse(['remove', '--all']).requestArguments['approvalTimeout'],
        90,
      );
      expect(
        parse(['tag', 'delete', 'Testing']).requestArguments['approvalTimeout'],
        90,
      );
    },
  );

  test('approval commands operate by id without a Skill selection', () {
    for (final action in ['wait', 'status', 'cancel']) {
      final command = parse(['--json', 'approvals', action, 'ap_abcdefgh']);
      expect(command.command, 'approvals $action');
      expect(command.json, true);
      expect(command.requestArguments, {
        'id': 'ap_abcdefgh',
        if (action == 'wait') 'approvalTimeout': 90,
      });
    }
    expect(
      parse(['approvals', 'wait', 'id', '--approval-timeout', '0'])
          .requestArguments['approvalTimeout'],
      0,
    );
  });

  test(
    'invalid timeouts, argument counts and approval bypass flags fail usage',
    () {
      for (final args in [
        ['remove'],
        ['tag', 'delete'],
        ['tag', 'delete', 'a', 'b'],
        ['approvals'],
        ['approvals', 'wait'],
        ['approvals', 'status', 'a', 'b'],
        ['approvals', 'cancel', 'id', '--dry-run'],
        ['approvals', 'status', 'id', '--approval-timeout', '90'],
        for (final command in [
          ['remove', '--all'],
          ['tag', 'delete', 'tag'],
          ['approvals', 'wait', 'id'],
        ])
          for (final seconds in ['-1', '601', '1.5', 'no'])
            [...command, '--approval-timeout', seconds],
        for (final bypass in [
          '--yes',
          '--force',
          '--skip-approval',
          '--keep-going',
        ])
          ['remove', '--all', bypass],
      ]) {
        expect(() => parse(args), throwsFormatException, reason: '$args');
      }
    },
  );

  test('approval codes have stable exit mappings', () {
    for (final entry in {
      'approvalPending': 5,
      'approvalAlreadyPending': 5,
      'approvalDenied': 1,
      'approvalExpired': 1,
      'approvalCancelled': 1,
      'approvalNotFound': 1,
    }.entries) {
      expect(
        commandExitCode(CommandResult.failure('remove', entry.key, 'Failed.')),
        entry.value,
      );
    }
  });

  test('human removal and dry-run disclosures use removal wording', () {
    expect(renderHumanResult(_removed), '✓ alpha  removed\n1 removed');
    final text = renderHumanResult(
      CommandResult(
        ok: true,
        command: 'remove',
        data: const {'dryRun': true},
        results: const [
          {
            'id': 'a',
            'slotKey': 'alpha',
            'outcome': 'wouldSucceed',
            'activatedAgents': ['Codex'],
            'unpublishedDraft': true,
          },
        ],
      ),
    );
    expect(text, contains('would be removed'));
    expect(text, contains('(active in Codex; has an unpublished Draft)'));
    expect(text, contains('dry run, nothing changed'));
  });

  test('approval status and wait render the original terminal result', () {
    for (final action in ['wait', 'status']) {
      final result = CommandResult(
        ok: true,
        command: 'approvals $action',
        results: _removed.results,
        data: {'state': 'terminal', 'result': _removed.toJson()},
      );
      expect(
        renderHumanResult(
          CommandResult.fromJson(
            jsonDecode(jsonEncode(result.toJson())) as Map<String, Object?>,
          ),
        ),
        renderHumanResult(_removed),
      );
      final tag = CommandResult(
        ok: true,
        command: 'tag delete',
        data: const {'outcome': 'succeeded'},
      );
      expect(
        renderHumanResult(
          CommandResult(
            ok: true,
            command: 'approvals $action',
            data: {'result': tag.toJson()},
          ),
        ),
        'Tag deleted.',
      );
    }
    expect(
      renderHumanResult(
        CommandResult(
          ok: true,
          command: 'approvals status',
          data: const {'id': 'ap_abcdefgh', 'state': 'executing'},
        ),
      ),
      'Approval ap_abcdefgh: executing.',
    );
  });

  test('human tag deletion dry run includes assignment count', () {
    final text = renderHumanResult(
      CommandResult(
        ok: true,
        command: 'tag delete',
        data: const {'dryRun': true, 'tag': 'Testing', 'assignedSkillCount': 3},
      ),
    );
    expect(text, contains('Testing would be deleted'));
    expect(text, contains('3 Skills would be unassigned'));
  });

  test('pending response exits 5 with the exact human resume message', () async {
    const message =
        'Waiting for approval in SkillDeck… (approval ap_abcdefgh; resume with: skilldeck approvals wait ap_abcdefgh)';
    final response = CommandResult(
      ok: false,
      command: 'remove',
      error: CommandError(
        code: 'approvalPending',
        message: message,
        details: const {
          'id': 'ap_abcdefgh',
          'expiresAt': '2026-10-20T00:10:00.000Z',
        },
      ),
    );
    expect(renderHumanResult(response), message);
    final out = StringBuffer();
    final err = StringBuffer();
    expect(
      await runSkilldeck(
        ['remove', '--all', '--approval-timeout', '0'],
        environment: const {'HOME': '/unused'},
        isWindows: false,
        cwd: '/work',
        out: out,
        err: err,
        interrupts: const Stream.empty(),
        appLauncher: AppLauncher(
          runDirectory: '/unused',
          connect: ({timeout}) async => _Connection(response),
        ),
      ),
      5,
    );
    expect(out.toString(), isEmpty);
    expect(err.toString(), '$message\n');
  });
}

final _removed = CommandResult(
  ok: true,
  command: 'remove',
  results: const [
    {'id': 'a', 'slotKey': 'alpha', 'outcome': 'succeeded'},
  ],
);

final class _Connection implements CommandHostConnection {
  _Connection(this.result);
  final CommandResult result;
  @override
  Future<CommandResult> execute(CommandRequest request) async => result;
  @override
  Future<void> close() async {}
}
