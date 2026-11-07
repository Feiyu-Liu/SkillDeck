import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_planner.dart';
import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  test('materialization maps concrete modes to immutable mutations', () {
    final warning = ActivationWarning(
      code: ActivationWarningCode.duplicateExposure,
    );
    final resolved = ResolvedActivationTargets(
      targets: <ResolvedActivationTarget>[
        ResolvedActivationTarget(
          location: '/global/skills',
          scope: ActivationScope.global,
          mode: ActivationMode.symbolicLink,
          agentIds: const <String>['global-agent'],
        ),
        ResolvedActivationTarget(
          location: '/project/.agents/skills',
          scope: ActivationScope.project,
          mode: ActivationMode.copy,
          agentIds: const <String>['project-agent'],
          projectRootId: 'project',
          projectRootPath: '/project',
        ),
      ],
      warnings: <ActivationWarning>[warning],
    );

    final plan = const ActivationPlanner().materialize(
      slotKey: 'example',
      copySourcePath: '/staging/example',
      repositoryCopyPath: '/repository/skills/example',
      resolvedTargets: resolved,
    );

    expect(plan.activations, hasLength(2));
    expect(plan.mutations, hasLength(2));
    final link = plan.mutations.first as PlannedActivationSymbolicLink;
    expect(link.targetPath, path.join('/global/skills', 'example'));
    expect(link.linkTarget, '/repository/skills/example');
    final copy = plan.mutations.last as PlannedActivationCopy;
    expect(copy.targetPath, path.join('/project/.agents/skills', 'example'));
    expect(copy.sourcePath, '/staging/example');
    expect(plan.warnings, <ActivationWarning>[warning]);
    expect(
      () => plan.activations.add(plan.activations.first),
      throwsUnsupportedError,
    );
    expect(() => plan.mutations.add(copy), throwsUnsupportedError);
  });

  test(
    'update replaces copies and validates links without rewriting them',
    () async {
      final validator = RecordingActivationUpdateValidator();
      final skill = _skill(
        activations: <SkillActivation>[
          SkillActivation(
            location: '/project/.agents/skills',
            scope: ActivationScope.project,
            mode: ActivationMode.copy,
            agentIds: const <String>['copy-agent'],
            projectRootId: 'project',
            projectRootPath: '/project',
          ),
          SkillActivation(
            location: '/global/skills',
            scope: ActivationScope.global,
            mode: ActivationMode.symbolicLink,
            agentIds: const <String>['link-agent'],
          ),
        ],
      );

      final result = await ActivationUpdatePlanner(validator: validator).plan(
        skill: skill,
        preparedSkillPath: '/staging/example',
        repositoryCopyPath: '/repository/skills/example',
      );

      final plan = result.valueOrNull!;
      expect(plan.activations, skill.activations);
      expect(plan.mutations, hasLength(1));
      expect(
        (plan.mutations.single as PlannedActivationCopy).targetPath,
        path.join('/project/.agents/skills', 'example'),
      );
      expect(plan.validatedSymbolicLinks, hasLength(1));
      expect(
        plan.validatedSymbolicLinks.single.targetPath,
        path.join('/global/skills', 'example'),
      );
      expect(validator.copyProjectRootIds, <String?>['project']);
      expect(validator.symbolicLinkTargets, <String>[
        '/repository/skills/example',
      ]);
    },
  );

  test('one unavailable Activation blocks the entire update plan', () async {
    final validator = RecordingActivationUpdateValidator(
      failLocation: '/second',
    );
    final result = await ActivationUpdatePlanner(validator: validator).plan(
      skill: _skill(
        activations: <SkillActivation>[
          SkillActivation(
            location: '/first',
            scope: ActivationScope.global,
            mode: ActivationMode.copy,
            agentIds: const <String>['first'],
          ),
          SkillActivation(
            location: '/second',
            scope: ActivationScope.global,
            mode: ActivationMode.copy,
            agentIds: const <String>['second'],
          ),
        ],
      ),
      preparedSkillPath: '/staging/example',
      repositoryCopyPath: '/repository/skills/example',
    );

    expect(
      result.failureOrNull?.code,
      ActivationFailureCode.activationUnavailable,
    );
    expect(result.failureOrNull?.context['location'], '/second');
  });

  test('platform path joining keeps the target beneath its location', () {
    final resolved = ResolvedActivationTargets(
      targets: <ResolvedActivationTarget>[
        ResolvedActivationTarget(
          location: path.absolute('activation'),
          scope: ActivationScope.global,
          mode: ActivationMode.copy,
          agentIds: const <String>['agent'],
        ),
      ],
    );

    final plan = const ActivationPlanner().materialize(
      slotKey: 'example',
      copySourcePath: '/staging/example',
      repositoryCopyPath: '/repository/skills/example',
      resolvedTargets: resolved,
    );

    expect(
      plan.mutations.single.targetPath,
      path.join(path.absolute('activation'), 'example'),
    );
  });
}

ManagedSkill _skill({List<SkillActivation> activations = const []}) =>
    ManagedSkill(
      id: ManagedSkillId('00000000-0000-4000-8000-000000000001'),
      slotKey: 'example',
      declaredName: 'example',
      displayName: 'Example',
      description: 'Example Skill',
      source: LocalSourceDescriptor(locator: '/source'),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        publishedAt: DateTime.utc(2026),
      ),
      activations: activations,
    );
