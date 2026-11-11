import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_sort.dart';

void main() {
  final older = DateTime.utc(2026, 1, 1);
  final newer = DateTime.utc(2026, 2, 1);

  test('sorts by display name in both directions', () {
    final skills = [
      _skill('zeta', 'Zeta'),
      _skill('alpha', 'alpha'),
      _skill('middle', 'Middle'),
    ];

    skills.sort(
      (left, right) =>
          compareInstalledSkills(left, right, SkillListSortMode.nameAscending),
    );
    expect(skills.map((skill) => skill.slotKey), ['alpha', 'middle', 'zeta']);

    skills.sort(
      (left, right) =>
          compareInstalledSkills(left, right, SkillListSortMode.nameDescending),
    );
    expect(skills.map((skill) => skill.slotKey), ['zeta', 'middle', 'alpha']);
  });

  test('sorts by added time and uses name as a stable tie breaker', () {
    final skills = [
      _skill('newer', 'Newer', createdAt: newer),
      _skill('older', 'Older', createdAt: older),
      _skill('same-b', 'Same', createdAt: older),
      _skill('same-a', 'Same', createdAt: older),
    ];

    skills.sort(
      (left, right) =>
          compareInstalledSkills(left, right, SkillListSortMode.recentlyAdded),
    );
    expect(skills.map((skill) => skill.slotKey), [
      'newer',
      'older',
      'same-a',
      'same-b',
    ]);

    skills.sort(
      (left, right) =>
          compareInstalledSkills(left, right, SkillListSortMode.oldestAdded),
    );
    expect(skills.map((skill) => skill.slotKey), [
      'older',
      'same-a',
      'same-b',
      'newer',
    ]);
  });

  test('updates do not move a previously added Skill', () {
    for (final mode in [
      SkillListSortMode.recentlyAdded,
      SkillListSortMode.oldestAdded,
    ]) {
      final before = [
        _skill('a', 'A', createdAt: older, acquiredAt: older),
        _skill('b', 'B', createdAt: newer, acquiredAt: newer),
      ]..sort((a, b) => compareInstalledSkills(a, b, mode));
      final after = [
        _skill('a', 'A', createdAt: older, acquiredAt: DateTime.utc(2026, 3)),
        _skill('b', 'B', createdAt: newer, acquiredAt: newer),
      ]..sort((a, b) => compareInstalledSkills(a, b, mode));
      expect(after.map((skill) => skill.id), before.map((skill) => skill.id));
    }
  });

  test('places a skill without added time after dated skills', () {
    final skills = [
      // A revision time cannot recover a missing first-added time.
      _skill('unknown', 'Unknown', acquiredAt: DateTime.utc(2027)),
      _skill('dated', 'Dated', createdAt: older),
    ];

    skills.sort(
      (left, right) =>
          compareInstalledSkills(left, right, SkillListSortMode.recentlyAdded),
    );

    expect(skills.map((skill) => skill.slotKey), ['dated', 'unknown']);
  });
}

InstalledSkill _skill(
  String slotKey,
  String displayName, {
  DateTime? createdAt,
  DateTime? acquiredAt,
}) => InstalledSkill(
  id: WorkspaceSkillId(slotKey),
  slotKey: slotKey,
  displayName: displayName,
  description: '$displayName description',
  contentHash: 'hash-$slotKey',
  activationCount: 0,
  createdAt: createdAt,
  currentRevision: acquiredAt == null
      ? null
      : SkillRevision(
          contentHash: 'hash-$slotKey',
          fileCount: 1,
          byteSize: 1,
          acquiredAt: acquiredAt,
        ),
);
