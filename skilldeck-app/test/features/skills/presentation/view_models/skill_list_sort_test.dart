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
      _skill('newer', 'Newer', acquiredAt: newer),
      _skill('older', 'Older', acquiredAt: older),
      _skill('same-b', 'Same', acquiredAt: older),
      _skill('same-a', 'Same', acquiredAt: older),
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

  test('places a skill without added time after dated skills', () {
    final skills = [
      _skill('unknown', 'Unknown'),
      _skill('dated', 'Dated', acquiredAt: older),
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
  DateTime? acquiredAt,
}) => InstalledSkill(
  id: WorkspaceSkillId(slotKey),
  slotKey: slotKey,
  displayName: displayName,
  description: '$displayName description',
  contentHash: 'hash-$slotKey',
  activationCount: 0,
  currentRevision: acquiredAt == null
      ? null
      : SkillRevision(
          contentHash: 'hash-$slotKey',
          fileCount: 1,
          byteSize: 1,
          acquiredAt: acquiredAt,
        ),
);
