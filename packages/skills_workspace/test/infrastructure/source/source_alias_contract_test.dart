import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/source/skill_discovery.dart';
import 'package:test/test.dart';

import '../../support/source/source_alias_fixture.dart';

const _real = sourceAliasRealPath;
const _alias = sourceAliasLinkPath;
const _body = sourceAliasSkillBody;

void main() {
  for (final git in [false, true]) {
    final kind = git ? 'Git' : 'Local';
    for (final fullDepth in [false, true]) {
      test('$kind merges plugin aliases, fullDepth=$fullDepth', () async {
        final fixture = await SourceAliasFixture.create();
        final result = await fixture.acquire(git: git, fullDepth: fullDepth);
        expect(result.failureOrNull, isNull);
        final skills = result.valueOrNull!.skills;
        expect(skills, hasLength(1));
        expect(skills.single.skillPath, _real);
        expect(skills.single.pluginName, 'building');
      });
    }

    test('$kind identifies a Skill at the Source root', () async {
      final fixture = await SourceAliasFixture.create(
        extraFiles: {'SKILL.md': _body.replaceAll('demo', 'root')},
      );
      final result = await fixture.acquire(git: git);
      expect(result.failureOrNull, isNull);
      final skill = result.valueOrNull!.skills.single;
      expect(skill.skillPath, isEmpty);
      expect(skill.declaredName, 'root');
    });

    test('$kind name selection returns canonical path', () async {
      final fixture = await SourceAliasFixture.create();
      final result = await fixture.acquire(git: git, names: {'demo'});
      expect(result.failureOrNull, isNull);
      expect(result.valueOrNull!.skills.single.skillPath, _real);
    });

    for (final direct in [false, true]) {
      test(
        '$kind grouping is deterministic with canonical declaration=$direct',
        () async {
          final fixture = await SourceAliasFixture.create(
            extraLinks: {'plugins/another/skills/demo': '../../../skills/demo'},
            extraPlugins: [
              {
                'name': 'a-plugin',
                'source': './plugins/another',
                'skills': ['./skills/demo'],
              },
              if (direct)
                {
                  'name': 'z-canonical',
                  'source': './skills',
                  'skills': ['./demo'],
                },
            ],
          );
          final result = await fixture.acquire(git: git);
          expect(result.failureOrNull, isNull);
          expect(
            result.valueOrNull!.skills.single.pluginName,
            direct ? 'z-canonical' : 'a-plugin',
          );
        },
      );
    }

    test('$kind explicit alias retains provenance on reacquisition', () async {
      final fixture = await SourceAliasFixture.create();
      final first = await fixture.acquire(git: git, names: {_alias});
      expect(first.failureOrNull, isNull);
      final source = first.valueOrNull!.skills.single.provenance;
      expect(first.valueOrNull!.skills.single.skillPath, _alias);
      final again = await fixture.coordinator.acquire(
        source: source,
        selectedSkillNames: const {},
        options: const SourceAcquisitionOptions(),
      );
      expect(again.failureOrNull, isNull);
      expect(
        again.valueOrNull!.canonicalSource.hasSameIdentity(source),
        isTrue,
      );
      expect(
        again.valueOrNull!.skills.single.provenance.hasSameIdentity(source),
        isTrue,
      );
    });

    test(
      '$kind finds a target reachable only through a plugin alias',
      () async {
        final fixture = await SourceAliasFixture.create(
          target: 'vendor/deep/library/demo',
          extraFiles: {
            'skills/other/SKILL.md': _body.replaceAll('demo', 'other'),
          },
        );
        final result = await fixture.acquire(git: git);
        expect(result.failureOrNull, isNull);
        expect(
          result.valueOrNull!.skills.map((skill) => skill.skillPath),
          containsAll(['vendor/deep/library/demo', 'skills/other']),
        );
      },
    );

    test('$kind follows links in intermediate target segments', () async {
      final fixture = await SourceAliasFixture.create(
        aliasTarget: '../../../bridge/demo',
        extraLinks: {'bridge': 'skills'},
      );
      final result = await fixture.acquire(git: git);
      expect(result.failureOrNull, isNull);
      expect(result.valueOrNull!.skills, hasLength(1));
      expect(result.valueOrNull!.skills.single.skillPath, _real);
    });

    test('$kind rejects independent identical same-name directories', () async {
      final fixture = await SourceAliasFixture.create(
        extraFiles: {'skills/copy/SKILL.md': _body},
      );
      final result = await fixture.acquire(git: git);
      expect(
        result.failureOrNull?.code,
        SourceAcquisitionFailureCode.duplicateSkillSlot,
      );
      expect(
        result.failureOrNull?.context['reason'],
        'duplicateSlotsWithinSource',
      );
    });

    test(
      '$kind sharing only SKILL.md does not merge directory identity',
      () async {
        final fixture = await SourceAliasFixture.create(
          extraLinks: {'skills/copy/SKILL.md': '../demo/SKILL.md'},
        );
        if (!git) {
          // Local content validation rejects file links escaping the selected
          // Skill. Check discovery before that independent content boundary.
          final discovery = await const SkillDiscovery().inspect(
            fixture.root.path,
            followDirectoryLinks: true,
          );
          expect(discovery.valueOrNull!.candidates, hasLength(2));
          return;
        }
        final result = await fixture.coordinator.inspect(
          source: fixture.source(git),
          options: const SourceAcquisitionOptions(),
        );
        expect(
          result.failureOrNull?.code,
          SourceAcquisitionFailureCode.duplicateSkillSlot,
        );
      },
    );

    test(
      '$kind alias removal preserves canonical selection, not alias selection',
      () async {
        final fixture = await SourceAliasFixture.create();
        final canonical = (await fixture.acquire(
          git: git,
        )).valueOrNull!.skills.single.provenance;
        final alias = (await fixture.acquire(
          git: git,
          names: {_alias},
        )).valueOrNull!.skills.single.provenance;
        await Link(
          p.joinAll([fixture.root.path, ...p.posix.split(_alias)]),
        ).rename(
          p.join(
            fixture.root.parent.path,
            '${p.basename(fixture.root.path)}-retired-link',
          ),
        );
        await fixture.commit();
        for (final source in [canonical, alias]) {
          final result = await fixture.coordinator.acquire(
            source: source,
            selectedSkillNames: const {},
            options: const SourceAcquisitionOptions(),
          );
          if (identical(source, canonical)) {
            expect(result.failureOrNull, isNull);
            expect(
              result.valueOrNull!.skills.single.provenance.hasSameIdentity(
                canonical,
              ),
              isTrue,
            );
          } else {
            expect(result.failureOrNull, isNotNull);
          }
        }
      },
    );
  }

  for (final subpath in [_real, _alias, 'bridge/demo']) {
    test('Git repository subpath $subpath reads a contained target', () async {
      final fixture = await SourceAliasFixture.create(
        extraLinks: {'bridge': 'skills', 'unrelated-unsafe-link': '../outside'},
      );
      final source = GitSourceDescriptor(
        locator: fixture.root.path,
        repositorySubpath: subpath,
      );
      final result = await fixture.coordinator.acquire(
        source: source,
        selectedSkillNames: const {},
        options: const SourceAcquisitionOptions(),
      );
      expect(result.failureOrNull, isNull);
      expect(result.valueOrNull!.skills, hasLength(1));
      expect(
        result.valueOrNull!.skills.single.provenance.hasSameIdentity(source),
        isTrue,
      );
    });
  }

  test(
    'Local discovery warns for invalid links; explicit selection fails',
    () async {
      final fixture = await SourceAliasFixture.create(
        extraLinks: {
          'skills/missing': '../absent',
          'skills/cycle': 'cycle',
          'skills/outside': '../../outside',
        },
      );
      final result = await fixture.acquire(git: false);
      expect(result.failureOrNull, isNull);
      expect(result.warnings, isNotEmpty);
      for (final name in ['missing', 'cycle', 'outside']) {
        final explicit = await fixture.coordinator.acquire(
          source: LocalSourceDescriptor(
            locator: fixture.root.path,
            skillPath: 'skills/$name',
          ),
          selectedSkillNames: const {},
          options: const SourceAcquisitionOptions(),
        );
        expect(explicit.failureOrNull, isNotNull);
      }
    },
  );
}
