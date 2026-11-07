import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_mutation_models.dart';
import 'package:skills_workspace/src/infrastructure/activation/activation_target_expectation.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  test('managed expectation does not inspect an unmanaged target', () async {
    final occupancy = RecordingActivationOccupancyProbe();
    final result =
        await ActivationTargetExpectationProbe(
          occupancyProbe: occupancy,
        ).matches(
          skill: activationSkill(),
          target: activationTarget(),
          targetPath: '/agents/skills/example',
          expectation: const ActivationTargetExpectation.managed(),
        );

    expect(result, isTrue);
    expect(occupancy.inspectedPaths, isEmpty);
  });

  test(
    'vacant and reviewed fingerprint expectations use canonical probe',
    () async {
      final occupancy = RecordingActivationOccupancyProbe();
      final adapter = ActivationTargetExpectationProbe(
        occupancyProbe: occupancy,
      );
      final target = activationTarget();
      const targetPath = '/agents/skills/example';

      expect(
        await adapter.matches(
          skill: activationSkill(),
          target: target,
          targetPath: targetPath,
          expectation: const ActivationTargetExpectation.vacant(),
        ),
        isTrue,
      );

      occupancy.results[targetPath] = InspectedActivationOccupancy(
        managedSkillId: activationSkill().id,
        slotKey: 'example',
        target: target,
        targetPath: targetPath,
        kind: InspectedActivationOccupancyKind.file,
        contentRelation: InspectedActivationContentRelation.indeterminate,
        fingerprint: 'file:reviewed',
        replaceable: true,
      );
      expect(
        await adapter.matches(
          skill: activationSkill(),
          target: target,
          targetPath: targetPath,
          expectation: ActivationTargetExpectation.occupied('file:reviewed'),
        ),
        isTrue,
      );
      expect(
        await adapter.matches(
          skill: activationSkill(),
          target: target,
          targetPath: targetPath,
          expectation: ActivationTargetExpectation.occupied('file:changed'),
        ),
        isFalse,
      );
    },
  );
}
