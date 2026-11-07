import 'dart:convert';
import 'dart:io';

import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skilldeck_cli/src/cli/command_line.dart';
import 'package:skilldeck_cli/src/cli/human_output.dart';
import 'package:skilldeck_cli/src/cli/runner.dart';
import 'package:test/test.dart';

void main() {
  SkilldeckCommandLine parse(
    List<String> args, {
    String cwd = '/work/nested',
    bool windows = false,
  }) => parseSkilldeckCommandLine(args, cwd: cwd, isWindows: windows);
  for (final command in ['list', 'show']) {
    test('$command parses all selector flags without resolving refs', () {
      final line = parse([
        '--json',
        command,
        'opaque',
        'slot',
        '--tag',
        'One,Two',
        '--tag',
        '技能',
        '--untagged',
        '--favorite',
        '--source',
        'https://source.test',
        '--active-for',
        'codex',
        '--project',
        '../demo/./root/..',
        '--has-update',
        '--all',
      ]);
      expect(line.json, isTrue);
      expect(line.requestArguments, {
        'selection': {
          'refs': ['opaque', 'slot'],
          'tags': ['One,Two', '技能'],
          'untagged': true,
          'favorite': true,
          'sourcePrefix': 'https://source.test',
          'activeFor': 'codex',
          'projectPath': '/work/demo',
          'hasUpdate': true,
          'all': true,
        },
      });
    });
  }
  test('project resolution uses injected Windows cwd on any host', () {
    final line = parse(
      ['list', '--project', r'..\demo\.\root\..'],
      cwd: r'C:\work\nested',
      windows: true,
    );
    expect(
      (line.requestArguments['selection'] as Map)['projectPath'],
      r'C:\work\demo',
    );
  });
  test('global options before or after a command preserve JSON mode', () {
    for (final args in [
      ['--json', 'list', '--all'],
      ['list', '--all', '--json'],
    ]) {
      expect(parse(args).json, isTrue);
    }
    expect(
      parse(['show', 'slot', '--document', 'docs/guide.md'])
          .requestArguments['document'],
      'docs/guide.md',
    );
  });
  test('empty selections, extra arguments and invalid help fail usage', () {
    for (final args in <List<String>>[
      ['list'],
      ['show'],
      ['agents', 'extra'],
      ['status', 'extra'],
      ['list', '--all', '--document', 'SKILL.md'],
      ['help', 'unknown'],
      ['help', 'show', 'extra'],
      ['list', '--all', '--wait', '-1'],
    ]) {
      expect(() => parse(args), throwsFormatException);
    }
  });
  test('help JSON matches the local catalog golden, without a home', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    expect(
      await runSkilldeck(
        ['help', '--json'],
        environment: const {},
        isWindows: false,
        cwd: '/work',
        out: out,
        err: err,
      ),
      0,
    );
    final golden = jsonDecode(
      await File('test/fixtures/help.json').readAsString(),
    );
    expect(jsonDecode(out.toString()), golden);
    expect(err.toString(), isEmpty);
    out.clear();
    expect(
      await runSkilldeck(
        ['help', 'show', '--json'],
        environment: const {},
        isWindows: false,
        out: out,
        err: err,
      ),
      0,
    );
    final data = (jsonDecode(out.toString()) as Map)['data'] as Map;
    expect((data['commands'] as Map).keys, ['show']);
    expect(data['exitCodes'], (golden as Map)['data']['exitCodes']);
    expect(data['errorCodes'], (golden)['data']['errorCodes']);
  });
  test('human list and agents are plain aligned tables', () {
    expect(
      renderHumanResult(
        CommandResult(
          ok: true,
          command: 'list',
          data: {
            'skills': [cannedSkill],
          },
        ),
      ),
      'Name   Slot Key  Active Agents  Tags     ★\nAlpha  alpha     codex          Testing  ★',
    );
    expect(
      renderHumanResult(
        CommandResult(
          ok: true,
          command: 'agents',
          data: {
            'agents': [
              {
                'name': 'Codex',
                'id': 'codex',
                'enabled': true,
                'globalRoots': ['/agents/codex'],
              },
              {
                'name': 'Other',
                'id': 'other',
                'enabled': false,
                'globalRoots': [],
              },
            ],
          },
        ),
      ),
      'Name   ID     Enabled  Global root\nCodex  codex  yes      /agents/codex\nOther  other  no',
    );
    expect(
      renderHumanResult(
        CommandResult(ok: true, command: 'list', data: {'skills': []}),
      ),
      'Name  Slot Key  Active Agents  Tags  ★',
    );
  });
  test('human show renders key/value details and document text verbatim', () {
    final text = renderHumanResult(
      CommandResult(
        ok: true,
        command: 'show',
        data: {
          'skill': cannedSkill,
          'documents': ['SKILL.md'],
        },
      ),
    );
    expect(
      text,
      'name          Alpha\nid            skill-1\nslotKey       alpha\n'
      'declaredName  alpha\ndescription   Full description\ncontentHash   hash\n'
      'favorite      true\nnote          Note\nintegrity     healthy\n'
      'source        https://example.test/repo\ntags          Testing\n'
      'activations   codex (global, copy), codex (project: /projects/demo, symbolicLink)\n'
      'update        notChecked\ndraft         false\ndocuments     SKILL.md',
    );
    const document = '# Skill\n\nUnicode 技能\n';
    expect(
      renderHumanResult(
        CommandResult(
          ok: true,
          command: 'show',
          data: {
            'document': {'path': 'SKILL.md', 'text': document},
          },
        ),
      ),
      document,
    );
  });
  test('table cells are bounded and terminal control characters removed', () {
    final text = renderHumanResult(
      CommandResult(
        ok: true,
        command: 'list',
        data: {
          'skills': [
            {...cannedSkill, 'name': 'x' * 100, 'slotKey': 'a\nb\u001b'},
          ],
        },
      ),
    );
    expect(text, contains('${'x' * 59}…'));
    expect(text, isNot(contains('x' * 61)));
    expect(text, isNot(contains('\u001b')));
    expect(text.split('\n'), hasLength(2));
  });
}

const cannedSkill = <String, Object?>{
  'id': 'skill-1',
  'slotKey': 'alpha',
  'name': 'Alpha',
  'declaredName': 'alpha',
  'description': 'Full description',
  'source': {'kind': 'git', 'locator': 'https://example.test/repo'},
  'contentHash': 'hash',
  'favorite': true,
  'note': 'Note',
  'tags': ['Testing'],
  'activations': [
    {'agent': 'codex', 'scope': 'global', 'mode': 'copy'},
    {
      'agent': 'codex',
      'scope': 'project',
      'projectPath': '/projects/demo',
      'mode': 'symbolicLink',
    },
  ],
  'update': {'status': 'notChecked'},
  'draft': {'present': false},
  'integrity': 'healthy',
};
