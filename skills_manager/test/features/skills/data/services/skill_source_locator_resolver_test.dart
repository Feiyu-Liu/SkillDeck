import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';

void main() {
  final home = p.normalize(p.absolute('test-home'));
  final resolver = SkillSourceLocatorResolver(homePath: home);

  test('resolves explicit local absolute, home, and file URI sources', () {
    final absolute = p.normalize(p.absolute('test-skills'));

    for (final draft in [
      SkillSourceDraft(kind: SkillSourceKind.local, locator: absolute),
      const SkillSourceDraft(kind: SkillSourceKind.local, locator: '~/skills'),
      SkillSourceDraft(
        kind: SkillSourceKind.local,
        locator: Uri.file(absolute).toString(),
      ),
    ]) {
      final resolved = resolver.resolve(draft);
      expect(resolved.kind, SkillSourceKind.local);
      expect(p.isAbsolute(resolved.value), isTrue);
      expect(resolved.ref, isNull);
      expect(resolved.repositorySubpath, isEmpty);
    }

    expect(
      resolver
          .resolve(
            const SkillSourceDraft(
              kind: SkillSourceKind.local,
              locator: '~/skills',
            ),
          )
          .value,
      p.join(home, 'skills'),
    );
  });

  test('keeps every nonempty explicit Git locator opaque', () {
    for (final locator in [
      'https://git.example.com/group/repository',
      'ssh://git@example.com/group/repository.git',
      'git@example.com:group/repository.git',
      'owner/repository',
      'github:owner/repository',
      'gitlab:group/repository',
    ]) {
      final resolved = resolver.resolve(
        SkillSourceDraft(
          kind: SkillSourceKind.git,
          locator: ' $locator ',
          sourceRef: ' release/v2 ',
          repositorySubpath: ' packages/skills ',
        ),
      );
      expect(resolved.kind, SkillSourceKind.git, reason: locator);
      expect(resolved.value, locator, reason: locator);
      expect(resolved.ref, 'release/v2', reason: locator);
      expect(resolved.repositorySubpath, 'packages/skills', reason: locator);
    }
  });

  test('keeps explicit well-known sources and strips Git options', () {
    for (final locator in [
      'https://skills.example.com',
      'https://github.com/owner/repository',
      'http://loopback.invalid',
    ]) {
      final resolved = resolver.resolve(
        SkillSourceDraft(
          kind: SkillSourceKind.wellKnown,
          locator: locator,
          sourceRef: 'ignored',
          repositorySubpath: 'ignored',
        ),
      );
      expect(resolved.kind, SkillSourceKind.wellKnown, reason: locator);
      expect(resolved.value, locator, reason: locator);
      expect(resolved.ref, isNull, reason: locator);
      expect(resolved.repositorySubpath, isEmpty, reason: locator);
    }
  });

  test('never reclassifies a locator across selected source kinds', () {
    final genericHttps = resolver.resolve(
      const SkillSourceDraft(
        kind: SkillSourceKind.git,
        locator: 'https://git.example.com/group/repository',
      ),
    );
    final githubWeb = resolver.resolve(
      const SkillSourceDraft(
        kind: SkillSourceKind.wellKnown,
        locator: 'https://github.com/owner/repository',
      ),
    );

    expect(genericHttps.kind, SkillSourceKind.git);
    expect(githubWeb.kind, SkillSourceKind.wellKnown);
    expect(
      () => resolver.resolve(
        const SkillSourceDraft(
          kind: SkillSourceKind.local,
          locator: 'https://skills.example.com',
        ),
      ),
      throwsA(isA<SkillAcquisitionException>()),
    );
  });

  test('rejects empty locators without exposing the input', () {
    for (final kind in SkillSourceKind.values) {
      expect(
        () => resolver.resolve(SkillSourceDraft(kind: kind, locator: '  ')),
        throwsA(
          isA<SkillAcquisitionException>()
              .having(
                (error) => error.operation,
                'operation',
                SkillAcquisitionOperation.resolveSource,
              )
              .having(
                (error) => error.toString(),
                'safe description',
                isNot(contains('  ')),
              ),
        ),
      );
    }
  });

  test('cleans pasted Git locators into the form the Workspace parses', () {
    const cases = {
      'npx skills add owner/repository': 'owner/repository',
      'npx skills add owner/repository --skill pdf': 'owner/repository',
      'npx -y skills@latest add https://github.com/owner/repository':
          'https://github.com/owner/repository',
      'pnpm dlx skills add owner/repository': 'owner/repository',
      'github.com/owner/repository': 'https://github.com/owner/repository',
      'www.github.com/owner/repository':
          'https://www.github.com/owner/repository',
      'gitlab.com/group/repository': 'https://gitlab.com/group/repository',
      'https://github.com/owner/repository?tab=readme-ov-file':
          'https://github.com/owner/repository',
      'https://github.com/owner/repository#readme':
          'https://github.com/owner/repository',
      'https://github.com/owner/repository/tree/main/skills/pdf?plain=1':
          'https://github.com/owner/repository/tree/main/skills/pdf',
      'https://github.com/owner/repository#release':
          'https://github.com/owner/repository#release',
      // Other hosts keep their query so the Workspace still rejects it.
      'https://git.example.com/group/repository?token=x':
          'https://git.example.com/group/repository?token=x',
      'owner/repository': 'owner/repository',
    };
    for (final MapEntry(key: input, value: expected) in cases.entries) {
      expect(
        resolver
            .resolve(
              SkillSourceDraft(kind: SkillSourceKind.git, locator: input),
            )
            .value,
        expected,
        reason: input,
      );
    }
  });

  test(
    'keeps userinfo on a pasted GitHub address for the Workspace to reject',
    () {
      expect(
        SkillSourceLocatorResolver.normalizeGitLocatorInput(
          'https://user:secret@github.com/owner/repository?tab=x',
        ),
        'https://user:secret@github.com/owner/repository',
      );
    },
  );

  test('strips Skill selectors without losing refs or SSH userinfo', () {
    const cases = {
      'owner/repository@skill': 'owner/repository',
      'owner/repository/sub/path@Name%20With%20Spaces':
          'owner/repository/sub/path',
      'owner/repository#v1@skill': 'owner/repository#v1',
      'https://github.com/owner/repository#v1@skill':
          'https://github.com/owner/repository#v1',
      'npx skills add owner/repository@skill --skill other': 'owner/repository',
      'bunx skills i owner/repository@skill': 'owner/repository',
      'pnpx skills a owner/repository@skill': 'owner/repository',
      'yarn dlx skills install owner/repository@skill': 'owner/repository',
      'git@github.com:owner/repository.git':
          'git@github.com:owner/repository.git',
      'ssh://git@host/owner/repository.git':
          'ssh://git@host/owner/repository.git',
      'https://user:secret@github.com/owner/repository':
          'https://user:secret@github.com/owner/repository',
    };
    for (final entry in cases.entries) {
      expect(
        SkillSourceLocatorResolver.normalizeGitLocatorInput(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('turns a typed repository subpath into a relative path', () {
    for (final MapEntry(key: input, value: expected) in {
      ' skills/pdf/ ': 'skills/pdf',
      '/skills/pdf': 'skills/pdf',
      './skills': 'skills',
      r'skills\pdf': 'skills/pdf',
      '': '',
    }.entries) {
      expect(
        resolver
            .resolve(
              SkillSourceDraft(
                kind: SkillSourceKind.git,
                locator: 'owner/repository',
                repositorySubpath: input,
              ),
            )
            .repositorySubpath,
        expected,
        reason: input,
      );
    }
  });

  test('accepts a quoted folder path copied from Windows Explorer', () {
    final absolute = p.normalize(p.absolute('test-skills'));
    expect(
      resolver
          .resolve(
            SkillSourceDraft(
              kind: SkillSourceKind.local,
              locator: '"$absolute"',
            ),
          )
          .value,
      absolute,
    );
  });

  test('rejects a Git locator that is only an install command prefix', () {
    expect(
      () => resolver.resolve(
        const SkillSourceDraft(kind: SkillSourceKind.git, locator: '   '),
      ),
      throwsA(
        isA<SkillAcquisitionException>().having(
          (error) => error.code,
          'code',
          SkillAcquisitionErrorCode.emptyLocator,
        ),
      ),
    );
  });
}
