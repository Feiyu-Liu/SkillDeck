import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/command_host/data/skill_selector_resolver.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import 'support/read_fixtures.dart';

void main() {
  final project = p.absolute('selector-project');
  final snapshot = testSnapshot(projectPath: project);
  List<String> resolve(
    SkillSelection selection, {
    SkillsWorkspaceSnapshot? current,
  }) => resolveSkillSelection(
    current ?? snapshot,
    selection,
    availableUpdateIds: {WorkspaceSkillId('skill-1')},
  ).map((s) => s.id.value).toList();
  final cases = <String, SkillSelection>{
    'case-insensitive tag': SkillSelection(tags: ['tEsTiNg']),
    'favorite': SkillSelection(favorite: true),
    'source display locator prefix': SkillSelection(
      sourcePrefix: 'https://example.test/',
    ),
    'active Agent': SkillSelection(activeFor: 'claude'),
    'project normalized path': SkillSelection(
      projectPath: p.join(project, 'child', '..'),
    ),
    'observed available update': SkillSelection(hasUpdate: true),
    'intersection': SkillSelection(
      tags: ['testing'],
      favorite: true,
      activeFor: 'codex',
      hasUpdate: true,
    ),
  };
  for (final entry in cases.entries) {
    test(entry.key, () => expect(resolve(entry.value), ['skill-1']));
  }
  test('untagged and all', () {
    expect(resolve(SkillSelection(untagged: true)), ['skill-2']);
    expect(resolve(SkillSelection(all: true)), ['skill-1', 'skill-2']);
  });
  test(
    'tags are ANDed, unknown tags and contradictory filters match nothing',
    () {
      final current = testSnapshot(
        skills: [
          testSkill(tags: ['tag-1', 'tag-2']),
        ],
      );
      expect(
        resolve(SkillSelection(tags: ['Testing', 'DART']), current: current),
        ['skill-1'],
      );
      expect(resolve(SkillSelection(tags: ['Testing', 'unknown'])), isEmpty);
      expect(
        resolve(SkillSelection(tags: ['Testing'], untagged: true)),
        isEmpty,
      );
      expect(resolve(SkillSelection(activeFor: 'missing')), isEmpty);
      expect(
        resolve(SkillSelection(projectPath: p.absolute('unregistered'))),
        isEmpty,
      );
      expect(resolve(SkillSelection(sourcePrefix: 'missing')), isEmpty);
    },
  );
  test('refs union all then intersect filters; refs alone stay bounded', () {
    expect(resolve(SkillSelection(refs: ['beta'])), ['skill-2']);
    expect(resolve(SkillSelection(refs: ['alpha'], untagged: true)), isEmpty);
    expect(resolve(SkillSelection(refs: ['beta'], all: true, favorite: true)), [
      'skill-1',
    ]);
    expect(resolve(SkillSelection(refs: ['beta'], favorite: true)), isEmpty);
  });
  test('id wins over Slot Key, and duplicate ids and refs collapse', () {
    final current = testSnapshot(
      skills: [
        testSkill(),
        testSkill(id: 'other', slot: 'skill-1'),
      ],
    );
    expect(
      resolve(
        SkillSelection(refs: ['skill-1', 'alpha', 'skill-1']),
        current: current,
      ),
      ['skill-1'],
    );
  });
  test('unknown ref fails entire selection, even with all and filters', () {
    expect(
      () => resolve(
        SkillSelection(refs: ['alpha', 'unknown'], all: true, favorite: true),
      ),
      throwsA(
        isA<SkillSelectionFailure>()
            .having((e) => e.code, 'code', 'skillNotFound')
            .having((e) => e.details, 'details', {'ref': 'unknown'}),
      ),
    );
  });
  test(
    'unknown ref details sanitize userinfo, controls and bound Unicode to 200',
    () {
      final ref = 'https://secret:credential@example.test/\n\u001b${'技' * 300}';
      try {
        resolve(SkillSelection(refs: [ref]));
        fail('Expected failure');
      } on SkillSelectionFailure catch (e) {
        final safe = e.details['ref'] as String;
        expect(safe.runes.length, 200);
        expect(safe, startsWith('https://example.test/'));
        expect(safe, isNot(contains('credential')));
        expect(safe, isNot(contains('\n')));
        expect(safe, isNot(contains('\u001b')));
      }
    },
  );
  test('empty selection and relative project paths are usage errors', () {
    for (final selection in [
      SkillSelection(),
      SkillSelection(projectPath: 'relative'),
    ]) {
      expect(
        () => resolve(selection),
        throwsA(
          isA<SkillSelectionFailure>().having((e) => e.code, 'code', 'usage'),
        ),
      );
    }
  });
  test(
    'order follows GUI name ascending then Slot Key, independent of refs',
    () {
      final current = testSnapshot(
        skills: [
          testSkill(id: 'z', slot: 'z', name: 'beta'),
          testSkill(id: 'b', slot: 'b', name: 'ALPHA'),
          testSkill(id: 'a', slot: 'a', name: 'alpha'),
        ],
      );
      expect(resolve(SkillSelection(refs: ['b', 'z', 'a']), current: current), [
        'a',
        'b',
        'z',
      ]);
    },
  );
  test('project path can come directly from activation and global paths do not match', () {
    final current = testSnapshot(
      skills: [
        testSkill(
          activations: [
            SkillActivationLocation(
              location: 'private',
              scope: WorkspaceScope.project,
              mode: WorkspaceActivationMode.copy,
              agentIds: ['codex'],
              projectRootPath: project,
            ),
          ],
        ),
      ],
    );
    expect(resolve(SkillSelection(projectPath: project), current: current), [
      'skill-1',
    ]);
  });
}
