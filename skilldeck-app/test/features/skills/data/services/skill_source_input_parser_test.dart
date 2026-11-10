import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/data/services/skill_source_input_parser.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';

void main() {
  final home = p.normalize(p.absolute('parser-home'));
  final parser = SkillSourceInputParser(homePath: home);

  ParsedSkillSourceInput smart(String input) =>
      parser.parse(input, mode: SkillSourceInputMode.smart);

  group('smart detection, in precedence order', () {
    final localCases = {
      '/x': '/x',
      '~': home,
      '~/x': p.join(home, 'x'),
      './x': './x',
      '../x': '../x',
      r'C:\x': r'C:\x',
      r'"C:\x y"': r'C:\x y',
      'file:///x': 'file:///x',
      '/x/repo.git': '/x/repo.git',
      './owner/repo@skill': './owner/repo@skill',
      r'\\server\share\skills': r'\\server\share\skills',
    };
    for (final entry in localCases.entries) {
      test('local: ${entry.key}', () {
        final parsed = smart(entry.key);
        expect(parsed.detection, SkillSourceDetection.local);
        expect(parsed.draft.kind, SkillSourceKind.local);
        expect(parsed.draft.locator, entry.value);
        expect(parsed.draft.sourceRef, isEmpty);
        expect(parsed.draft.repositorySubpath, isEmpty);
        expect(parsed.requestedSkillNames, isEmpty);
        expect(parsed.fromInstallCommand, isFalse);
      });
    }

    for (final (input, subpath, names) in [
      ('owner/repo', '', <String>{}),
      ('owner/repo/sub/path', 'sub/path', <String>{}),
      ('owner/repo@skill', '', {'skill'}),
      (
        'owner/repo/sub/path@Name%20With%20Spaces',
        'sub/path',
        {'Name With Spaces'},
      ),
    ]) {
      test('shorthand: $input', () {
        final parsed = smart(input);
        expect(parsed.detection, SkillSourceDetection.gitShorthand);
        expect(parsed.draft.kind, SkillSourceKind.git);
        expect(parsed.draft.locator, 'owner/repo');
        expect(parsed.draft.repositorySubpath, subpath);
        expect(parsed.requestedSkillNames, names);
      });
    }

    for (final (input, locator, ref, subpath) in [
      ('github.com/o/r', 'https://github.com/o/r', '', ''),
      ('gitlab.com/g/r', 'https://gitlab.com/g/r', '', ''),
      (
        'https://github.com/o/r?tab=readme-ov-file#readme',
        'https://github.com/o/r',
        '',
        '',
      ),
      (
        'https://github.com/o/r/tree/main/skills/x',
        'https://github.com/o/r',
        'main',
        'skills/x',
      ),
      (
        'https://gitlab.com/g/sub/r/-/tree/dev/skills',
        'https://gitlab.com/g/sub/r',
        'dev',
        'skills',
      ),
      ('https://github.com/o/r.git', 'https://github.com/o/r', '', ''),
      (
        'github.com/o/r.git/tree/main/skills/x?plain=1',
        'https://github.com/o/r',
        'main',
        'skills/x',
      ),
      ('https://gitlab.com/g/sub/r.git', 'https://gitlab.com/g/sub/r', '', ''),
      (
        'https://github.com/o/r#release%2Fv1',
        'https://github.com/o/r',
        'release/v1',
        '',
      ),
    ]) {
      test('hosted URL: $input', () {
        final parsed = smart(input);
        expect(parsed.detection, SkillSourceDetection.gitHostedUrl);
        expect(parsed.draft.kind, SkillSourceKind.git);
        expect(parsed.draft.locator, locator);
        expect(parsed.draft.sourceRef, ref);
        expect(parsed.draft.repositorySubpath, subpath);
      });
    }

    for (final input in [
      'git@github.com:o/r.git',
      'ssh://git@host/o/r.git',
      'https://host/o/r.git',
      'github:o/r',
      'gitlab:g/r',
      'foo',
    ]) {
      test('opaque Git remote or fallback: $input', () {
        final parsed = smart(input);
        expect(parsed.detection, SkillSourceDetection.gitRemote);
        expect(parsed.draft.kind, SkillSourceKind.git);
        expect(parsed.draft.locator, input);
        expect(parsed.requestedSkillNames, isEmpty);
      });
    }

    for (final input in [
      'https://example.com/blog/x',
      'http://localhost:8080/x',
      'https://example.com/blog/x#section@name',
    ]) {
      test('web URL: $input', () {
        final parsed = smart(input);
        expect(parsed.detection, SkillSourceDetection.webUrl);
        expect(parsed.draft.kind, SkillSourceKind.wellKnown);
        expect(parsed.draft.locator, input);
        expect(parsed.draft.sourceRef, isEmpty);
        expect(parsed.requestedSkillNames, isEmpty);
      });
    }

    test('blank input', () {
      for (final input in ['', '  \n\t  ']) {
        final parsed = smart(input);
        expect(parsed.detection, SkillSourceDetection.empty);
        expect(parsed.draft.locator, isEmpty);
        expect(parsed.requestedSkillNames, isEmpty);
        expect(parsed.requestedAgentIds, isEmpty);
        expect(parsed.ignoredFlags, isEmpty);
        expect(parsed.requestGlobalScope, isFalse);
        expect(parsed.fromInstallCommand, isFalse);
      }
    });

    test('extracts fragments only from Git-looking sources', () {
      for (final (input, locator) in [
        ('owner/repo#v1', 'owner/repo'),
        ('https://host/o/r.git#v1', 'https://host/o/r.git'),
        ('git@github.com:o/r.git#v1', 'git@github.com:o/r.git'),
      ]) {
        final parsed = smart(input);
        expect(parsed.draft.locator, locator);
        expect(parsed.draft.sourceRef, 'v1');
      }
    });
  });

  group('install commands', () {
    test('merges repeatable skill flags', () {
      final parsed = smart('npx skills add o/r --skill a --skill b');
      expect(parsed.draft.locator, 'o/r');
      expect(parsed.requestedSkillNames, {'a', 'b'});
      expect(parsed.fromInstallCommand, isTrue);
      expect(parsed.requestGlobalScope, isFalse);
    });

    test('consumes greedy skill and agent values and global scope', () {
      final parsed = smart(
        'npx skills add o/r -s a b -g -a claude-code cursor',
      );
      expect(parsed.draft.locator, 'o/r');
      expect(parsed.requestedSkillNames, {'a', 'b'});
      expect(parsed.requestedAgentIds, ['claude-code', 'cursor']);
      expect(parsed.requestGlobalScope, isTrue);
      expect(parsed.ignoredFlags, isEmpty);
    });

    test('handles versioned packages, quoted names, and ignored flags', () {
      final parsed = smart(
        'pnpm dlx skills@latest add https://github.com/o/r '
        '--skill "Name With Spaces" -y',
      );
      expect(parsed.draft.locator, 'https://github.com/o/r');
      expect(parsed.requestedSkillNames, {'Name With Spaces'});
      expect(parsed.ignoredFlags, ['-y']);
      expect(parsed.fromInstallCommand, isTrue);
    });

    test('all requests every skill and agent with global scope', () {
      for (final input in [
        'bunx skills i o/r --all',
        'bunx skills i o/r -s one --all -a cursor',
        'bunx skills i o/r --all -s one',
      ]) {
        final parsed = smart(input);
        expect(parsed.draft.locator, 'o/r');
        expect(parsed.requestedSkillNames, {'*'});
        expect(parsed.requestedAgentIds, ['*']);
        expect(parsed.requestGlobalScope, isTrue);
      }
    });

    test('ignores equals-style flags', () {
      final parsed = smart('npx skills add o/r --skill=x');
      expect(parsed.requestedSkillNames, isEmpty);
      expect(parsed.ignoredFlags, ['--skill=x']);
    });

    test('ignores extra positionals', () {
      final parsed = smart('npx skills add o/r second/src');
      expect(parsed.draft.locator, 'o/r');
      expect(parsed.ignoredFlags, ['second/src']);
    });

    test('a leading greedy flag can consume the would-be source', () {
      // Upstream parseAddOptions consumes all non-flag tokens after -s;
      // o/r is a second Skill name here, so no Source remains.
      final parsed = smart('npx skills add -s foo o/r');
      expect(parsed.requestedSkillNames, {'foo', 'o/r'});
      expect(parsed.draft.locator, isEmpty);
      expect(parsed.detection, SkillSourceDetection.empty);
      expect(parsed.fromInstallCommand, isTrue);
    });

    test('metadata consumes exactly one token and subagent is greedy', () {
      final parsed = smart(
        'npx skills add o/r --metadata \'{"a":1}\' extra '
        '--subagent first "Second Agent" -g',
      );
      expect(parsed.draft.locator, 'o/r');
      expect(parsed.ignoredFlags, [
        '--metadata',
        '{"a":1}',
        'extra',
        '--subagent',
        'first',
        'Second Agent',
      ]);
      expect(parsed.requestedAgentIds, isEmpty);
      expect(parsed.requestGlobalScope, isTrue);
    });

    test('merges shorthand selection and explicit skill flags', () {
      final parsed = smart('npx skills add o/r@x -s y');
      expect(parsed.draft.locator, 'o/r');
      expect(parsed.requestedSkillNames, {'x', 'y'});
    });

    test('extracts a quoted fragment ref and skill selection', () {
      final parsed = smart("npx skills add 'https://github.com/o/r#v1@x'");
      expect(parsed.draft.locator, 'https://github.com/o/r');
      expect(parsed.draft.sourceRef, 'v1');
      expect(parsed.requestedSkillNames, {'x'});
    });

    test('URI-decodes shorthand and fragment selections', () {
      for (final input in [
        'npx skills add o/r@Name%20With%20Spaces',
        'npx skills add https://github.com/o/r#v1@Name%20With%20Spaces',
      ]) {
        expect(smart(input).requestedSkillNames, {'Name With Spaces'});
      }
    });

    test(
      'supports each runner, command alias, and case-insensitive prefix',
      () {
        for (final prefix in [
          'npx skills add',
          'pnpx -y skills@1.0 add',
          'bunx --yes skills a',
          'pnpm dlx skills install',
          'yarn dlx skills i',
          'NPX SKILLS ADD',
        ]) {
          final parsed = smart('  $prefix o/r');
          expect(parsed.fromInstallCommand, isTrue, reason: prefix);
          expect(parsed.draft.locator, 'o/r', reason: prefix);
        }
        expect(smart('npm skills add o/r').fromInstallCommand, isFalse);
        expect(smart('npx skills remove o/r').fromInstallCommand, isFalse);
      },
    );

    test('supports single quotes, escaped spaces, and literal commas', () {
      final parsed = smart(
        r'''npx skills add o/r -s 'One Name' Another\ Name a,b --agent cursor --agent codex --global''',
      );
      expect(parsed.requestedSkillNames, {'One Name', 'Another Name', 'a,b'});
      expect(parsed.requestedAgentIds, ['cursor', 'codex']);
      expect(parsed.requestGlobalScope, isTrue);
    });

    test('preserves backslashes in quoted Windows sources', () {
      final parsed = smart(r'npx skills add "C:\x y" --skill one');
      expect(parsed.detection, SkillSourceDetection.local);
      expect(parsed.draft.locator, r'C:\x y');
      expect(parsed.requestedSkillNames, {'one'});
    });

    test('records every unsupported flag without interpreting it', () {
      final parsed = smart(
        'npx skills add o/r -y --yes -l --list --copy --full-depth '
        '-h --help --unknown',
      );
      expect(parsed.ignoredFlags, [
        '-y',
        '--yes',
        '-l',
        '--list',
        '--copy',
        '--full-depth',
        '-h',
        '--help',
        '--unknown',
      ]);
      expect(parsed.requestGlobalScope, isFalse);
    });

    test('missing flag values leave an empty draft without throwing', () {
      for (final flag in ['--metadata', '--subagent', '-s', '-a']) {
        final parsed = smart('npx skills add $flag');
        expect(parsed.detection, SkillSourceDetection.empty);
        expect(parsed.draft.locator, isEmpty);
      }
    });
  });

  group('typed mode', () {
    test('requires an explicit kind at runtime', () {
      expect(
        () => parser.parse('o/r', mode: SkillSourceInputMode.typed),
        throwsArgumentError,
      );
    });

    test('forces Git for a generic web URL', () {
      final parsed = parser.parse(
        'https://example.com',
        mode: SkillSourceInputMode.typed,
        typedKind: SkillSourceKind.git,
      );
      expect(parsed.draft.kind, SkillSourceKind.git);
      expect(parsed.draft.locator, 'https://example.com');
      expect(parsed.detection, SkillSourceDetection.webUrl);
    });

    test('harvests flags while keeping the chosen kind', () {
      final parsed = parser.parse(
        'npx skills add o/r --skill x',
        mode: SkillSourceInputMode.typed,
        typedKind: SkillSourceKind.git,
      );
      expect(parsed.draft.kind, SkillSourceKind.git);
      expect(parsed.draft.locator, 'o/r');
      expect(parsed.requestedSkillNames, {'x'});
      expect(parsed.fromInstallCommand, isTrue);
    });

    test('uses only the selected kinds existing normalizer', () {
      for (final (input, kind, expected) in [
        (r' "C:\x y" ', SkillSourceKind.local, r'C:\x y'),
        (' ~/x ', SkillSourceKind.local, '~/x'),
        (
          'github.com/o/r#readme',
          SkillSourceKind.git,
          'https://github.com/o/r',
        ),
        ('o/r/sub/path@skill', SkillSourceKind.git, 'o/r/sub/path'),
        ('o/r#v1@skill', SkillSourceKind.git, 'o/r#v1'),
        (
          ' https://github.com/o/r#readme ',
          SkillSourceKind.wellKnown,
          'https://github.com/o/r#readme',
        ),
        (
          ' "https://example.com" ',
          SkillSourceKind.wellKnown,
          '"https://example.com"',
        ),
        ('https://example.com', SkillSourceKind.local, 'https://example.com'),
      ]) {
        final parsed = parser.parse(
          input,
          mode: SkillSourceInputMode.typed,
          typedKind: kind,
        );
        expect(parsed.draft.kind, kind, reason: input);
        expect(parsed.draft.locator, expected, reason: input);
        expect(parsed.draft.sourceRef, isEmpty, reason: input);
        expect(parsed.draft.repositorySubpath, isEmpty, reason: input);
      }
    });

    test('keeps typed kinds on empty input', () {
      for (final kind in SkillSourceKind.values) {
        final parsed = parser.parse(
          ' ',
          mode: SkillSourceInputMode.typed,
          typedKind: kind,
        );
        expect(parsed.draft.kind, kind);
        expect(parsed.draft.locator, isEmpty);
        expect(parsed.detection, SkillSourceDetection.empty);
      }
    });
  });

  test(
    'parsed collections are immutable snapshots with a readable description',
    () {
      final skills = {'one'};
      final agents = ['cursor'];
      final ignored = ['--copy'];
      final parsed = ParsedSkillSourceInput(
        draft: const SkillSourceDraft(locator: 'o/r'),
        detection: SkillSourceDetection.gitShorthand,
        requestedSkillNames: skills,
        requestedAgentIds: agents,
        ignoredFlags: ignored,
      );
      skills.clear();
      agents.clear();
      ignored.clear();
      expect(parsed.requestedSkillNames, {'one'});
      expect(parsed.requestedAgentIds, ['cursor']);
      expect(parsed.ignoredFlags, ['--copy']);
      expect(
        () => parsed.requestedSkillNames.add('two'),
        throwsUnsupportedError,
      );
      expect(
        () => parsed.requestedAgentIds.add('codex'),
        throwsUnsupportedError,
      );
      expect(() => parsed.ignoredFlags.clear(), throwsUnsupportedError);
      expect(parsed.toString(), contains('gitShorthand'));
      expect(parsed.toString(), contains('o/r'));
    },
  );
}
