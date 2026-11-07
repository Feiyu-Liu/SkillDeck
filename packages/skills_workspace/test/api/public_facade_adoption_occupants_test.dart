import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  for (final shape in [
    'emptyDirectory',
    'danglingLink',
    'file',
    'invalidSkill',
    'validMarkdownEscapingLink',
    'directoryWithContent',
    'dsStore',
    'linkFile',
    'linkEmpty',
    'internal',
    'build',
    'rootSkill',
    'container',
    'compatEmpty',
    'compatFile',
    'reviewedLink',
  ]) {
    test('built-in catalog adoption: $shape', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final slot = shape == 'build' ? 'build' : 'alpha';
      var reviewed = path.join(
        f.claude,
        shape == 'build' ? 'builder' : 'alpha-v2',
      );
      final target = path.join(f.claude, slot);
      if (shape.startsWith('compat') || shape == 'rootSkill') {
        reviewed = path.join(f.codex, slot);
      } else if (shape == 'container') {
        reviewed = path.join(target, 'skills', slot);
      }
      await f.skill(reviewed, slot);
      String? referent;
      switch (shape) {
        case 'emptyDirectory':
        case 'compatEmpty':
          await Directory(target).create();
        case 'danglingLink':
          await Link(target).create('missing');
        case 'file':
        case 'compatFile':
          await File(target).writeAsString('keep');
        case 'validMarkdownEscapingLink':
          await f.skill(target, slot);
          final outside = File(path.join(f.root.path, 'outside.txt'));
          await outside.writeAsString('keep outside content');
          await Link(path.join(target, 'reference.txt')).create(outside.path);
        case 'invalidSkill':
          await Directory(target).create();
          await File(
            path.join(target, 'SKILL.md'),
          ).writeAsString('no frontmatter');
        case 'directoryWithContent':
        case 'dsStore':
          await Directory(target).create();
          await File(
            path.join(target, shape == 'dsStore' ? '.DS_Store' : 'notes'),
          ).writeAsString('keep');
        case 'linkFile':
        case 'linkEmpty':
          referent = path.join(f.root.path, 'referent');
          if (shape == 'linkFile') {
            await File(referent).writeAsString('keep');
          } else {
            await Directory(referent).create();
          }
          await Link(target).create(referent);
        case 'internal':
          await f.skill(target, slot, internal: true);
        case 'build':
          await f.skill(target, slot);
        case 'rootSkill':
          await f.skill(f.claude, 'container');
          await f.skill(target, slot);
        case 'reviewedLink':
          referent = path.join(f.root.path, 'referent');
          await Directory(reviewed).rename(referent);
          await Link(reviewed).create(referent);
          await Directory(target).create();
      }
      await f.open();
      final result = await f.adopt(slot);
      final expected = switch (shape) {
        'emptyDirectory' ||
        'danglingLink' ||
        'compatEmpty' ||
        'reviewedLink' => null,
        'dsStore' || 'container' => 'directoryWithContent',
        'linkFile' || 'linkEmpty' => 'link',
        'internal' || 'build' || 'rootSkill' => 'sameSlotSkill',
        'compatFile' => 'file',
        'validMarkdownEscapingLink' => 'invalidSkill',
        _ => shape,
      };
      if (expected == null) {
        final report = _success(result);
        final managed = report.snapshot.findSkill(
          report.affectedSkillIds.single,
        )!;
        expect(managed.activations, hasLength(1));
        expect(
          await Directory(
            managed.activations.single.location,
          ).resolveSymbolicLinks(),
          await Directory(f.claude).resolveSymbolicLinks(),
        );
        expect(await File(path.join(target, 'SKILL.md')).exists(), isTrue);
        expect(
          await FileSystemEntity.type(reviewed, followLinks: false),
          FileSystemEntityType.notFound,
        );
        if (referent != null) {
          expect(await File(path.join(referent, 'SKILL.md')).exists(), isTrue);
        }
      } else {
        final failure = result as SkillsFailure<MutationReport>;
        expect(failure.code, SkillsErrorCode.activationUnavailable);
        expect(failure.context['reason'], 'adoptionTargetOccupied');
        expect(failure.context['occupant'], expected);
        if (shape == 'validMarkdownEscapingLink' || shape == 'invalidSkill') {
          expect(failure.context['occupantFailureCode'], 'contentInvalid');
          expect(
            failure.context['occupantFailureReason'],
            shape == 'invalidSkill'
                ? 'invalidFrontmatter'
                : 'symbolicLinkEscapesSkillRoot',
          );
        }
        final occupants = failure.context['occupants']! as List<Object?>;
        final blocker = occupants.single! as Map<Object?, Object?>;
        expect(blocker['occupant'], expected);
        // `.agents/skills` links to `.claude/skills`. Which spelling the
        // resolver keeps depends on whether the temporary directory itself
        // sits behind a link (macOS `/var`), so compare physical folders.
        final blockerPath = blocker['targetPath']! as String;
        expect(path.basename(blockerPath), slot);
        expect(
          await Directory(path.dirname(blockerPath)).resolveSymbolicLinks(),
          await Directory(f.claude).resolveSymbolicLinks(),
        );
        expect(await File(path.join(reviewed, 'SKILL.md')).exists(), isTrue);
        // A rejected occupant is never touched.
        expect(
          await FileSystemEntity.type(target, followLinks: false),
          isNot(FileSystemEntityType.notFound),
        );
        if (referent != null) {
          expect(
            await FileSystemEntity.type(referent),
            isNot(FileSystemEntityType.notFound),
          );
        }
      }
    }, skip: Platform.isWindows ? 'POSIX shared-root/link layout' : false);
  }

  test('crossed names report otherSkill for both candidates', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    await f.skill(path.join(f.claude, 'alpha'), 'beta');
    await f.skill(path.join(f.claude, 'beta'), 'alpha');
    await f.open();
    for (final slot in ['alpha', 'beta']) {
      final failure = await f.adopt(slot) as SkillsFailure<MutationReport>;
      expect(failure.context['occupant'], 'otherSkill');
    }
  }, skip: Platform.isWindows);

  test('mixed device layout adopts all 13 Skills', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final slots = [
      'aaa-plain',
      for (var i = 0; i < 12; i++) 'skill-${i.toString().padLeft(2, '0')}',
    ];
    await f.skill(path.join(f.claude, slots.first), slots.first);
    for (final slot in slots.skip(1)) {
      await Directory(path.join(f.claude, slot)).create();
      await f.skill(path.join(f.codex, slot), slot);
    }
    await f.open();
    for (final slot in slots) {
      final report = _success(await f.adopt(slot));
      expect(
        report.snapshot.findSkill(report.affectedSkillIds.single)!.activations,
        hasLength(1),
      );
      expect(
        await File(path.join(f.claude, slot, 'SKILL.md')).exists(),
        isTrue,
      );
    }
  }, skip: Platform.isWindows);

  for (final inert in [false, true]) {
    test('all blockers sorted; inert target excluded: $inert', () async {
      final f = await _Fixture.create(shared: false);
      addTearDown(f.dispose);
      await f.skill(path.join(f.codex, 'alpha'), 'alpha');
      // Reviewing both roots requests both canonical destinations.
      await f.skill(path.join(f.claude, 'alpha-v2'), 'alpha');
      final universalTarget = path.join(f.home, '.agents', 'skills', 'alpha');
      await Directory(path.dirname(universalTarget)).create(recursive: true);
      if (inert) {
        await Directory(universalTarget).create();
      } else {
        await File(universalTarget).writeAsString('keep');
      }
      final claudeTarget = path.join(f.claude, 'alpha');
      await Directory(claudeTarget).create();
      await File(path.join(claudeTarget, 'SKILL.md')).writeAsString('invalid');
      await f.open();
      final failure = await f.adopt('alpha') as SkillsFailure<MutationReport>;
      expect(failure.context['occupant'], inert ? 'invalidSkill' : 'file');
      expect(
        failure.context['occupantFailureReason'],
        inert ? 'invalidFrontmatter' : null,
      );
      expect(
        failure.context['occupantFailureCode'],
        inert ? 'contentInvalid' : null,
      );
      expect(failure.context['occupants'], [
        if (!inert) {'targetPath': universalTarget, 'occupant': 'file'},
        {
          'targetPath': claudeTarget,
          'occupant': 'invalidSkill',
          'occupantFailureCode': 'contentInvalid',
          'occupantFailureReason': 'invalidFrontmatter',
        },
      ]);
    });
  }
}

T _success<T>(SkillsResult<T> result) {
  expect(result, isA<SkillsSuccess<T>>());
  return (result as SkillsSuccess<T>).value;
}

final class _Fixture {
  _Fixture(this.root);
  final Directory root;
  late final home = path.join(root.path, 'home');
  late final claude = path.join(home, '.claude', 'skills');
  late final codex = path.join(home, '.codex', 'skills');
  SkillsRepository? repository;

  static Future<_Fixture> create({bool shared = true}) async {
    final f = _Fixture(
      await Directory.systemTemp.createTemp('adoption-occupants-'),
    );
    await Directory(f.claude).create(recursive: true);
    await Directory(f.codex).create(recursive: true);
    await Directory(path.join(f.home, '.cursor')).create();
    if (shared) {
      await Directory(path.join(f.home, '.agents')).create();
      await Link(
        path.join(f.home, '.agents', 'skills'),
      ).create('../.claude/skills');
    }
    return f;
  }

  Future<void> skill(String at, String name, {bool internal = false}) async {
    await Directory(at).create(recursive: true);
    await File(path.join(at, 'SKILL.md')).writeAsString(
      '---\nname: $name\ndescription: Example\n${internal ? 'metadata: {internal: true}\n' : ''}---\nBody\n',
    );
  }

  Future<void> open() async {
    repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: path.join(root.path, 'workspace'),
        agentHomePath: home,
      ),
    );
    _success(await repository!.open().completed);
  }

  Future<SkillsResult<MutationReport>> adopt(String slot) async {
    final discovery = _success(
      await repository!
          .discoverExternalSkills(
            const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
          )
          .completed,
    );
    final candidate = discovery.candidates.singleWhere(
      (c) => c.slotKey == slot,
    );
    return repository!
        .adopt(
          AdoptRequest(
            selection: ExternalAdoptionSelection.fromCandidate(
              candidate,
              candidate.locations.first,
            ),
          ),
        )
        .completed;
  }

  Future<void> dispose() async {
    await repository?.close().completed;
    if (await root.exists()) {
      if (!Platform.isWindows) {
        await Process.run('chmod', ['-R', 'u+w', root.path]);
      }
      await root.delete(recursive: true);
    }
  }
}
