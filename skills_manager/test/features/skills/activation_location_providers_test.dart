import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';

import '../../support/fake_skills_workspace_repository.dart';

void main() {
  const global = (scope: WorkspaceScope.global, projectRootId: null);
  test(
    'inspection is shared, refreshable and does not mutate skills',
    () async {
      final workspace = FakeSkillsWorkspaceRepository();
      final container = ProviderContainer(
        overrides: [
          skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
        ],
      );
      addTearDown(container.dispose);
      final first = container.read(activationTargetsProvider(global).future);
      final second = container.read(activationTargetsProvider(global).future);
      await Future.wait([first, second]);
      expect(workspace.openCalls, 1);
      expect(workspace.targetInspections, [global]);
      workspace.publish(
        SkillsWorkspaceSnapshot(
          revision: 1,
          projectRoots: const [],
          skills: const [],
        ),
      );
      await container.pump();
      await container.read(activationTargetsProvider(global).future);
      expect(workspace.targetInspections, [global]);
      container.read(activationCatalogRevisionProvider.notifier).refresh();
      await container.read(activationTargetsProvider(global).future);
      expect(workspace.targetInspections, [global, global]);
      expect(workspace.installRequests, isEmpty);
      expect(workspace.activations, isEmpty);
    },
  );

  test(
    'target failure is retryable without retaining failed cached result',
    () async {
      final workspace = FakeSkillsWorkspaceRepository()
        ..inspectActivationTargetsError = WorkspaceException(
          code: WorkspaceErrorCode.ioFailure,
          operation: WorkspaceOperationKind.inspectActivationTargets,
        );
      final container = ProviderContainer(
        overrides: [
          skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
        ],
      );
      addTearDown(container.dispose);
      final vm = container.read(skillOperationsViewModelProvider.notifier);
      await vm.loadTargets();
      expect(container.read(skillOperationsViewModelProvider).error, isNotNull);
      workspace.inspectActivationTargetsError = null;
      final settled = _untilTargets(
        container,
        (state) =>
            !state.loadingTargets &&
            state.error == null &&
            workspace.targetInspections.length >= 2,
      );
      vm.retryTargets();
      await settled;
      expect(container.read(skillOperationsViewModelProvider).error, isNull);
      expect(
        container.read(skillOperationsViewModelProvider).loadingTargets,
        isFalse,
      );
    },
  );

  test(
    'new registered projects become available to loaded detail controls',
    () async {
      final workspace = FakeSkillsWorkspaceRepository();
      final container = ProviderContainer(
        overrides: [
          skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
        ],
      );
      addTearDown(container.dispose);
      final vm = container.read(skillOperationsViewModelProvider.notifier);
      await vm.loadTargets();
      final settled = _untilTargets(
        container,
        (state) =>
            !state.loadingTargets &&
            workspace.targetInspections.any((s) => s.projectRootId == 'p'),
      );
      workspace.publish(
        SkillsWorkspaceSnapshot(
          revision: 1,
          skills: const [],
          projectRoots: const [SkillProjectRoot(id: 'p', path: '/project')],
        ),
      );
      await settled;
      expect(
        workspace.targetInspections,
        contains((scope: WorkspaceScope.project, projectRootId: 'p')),
      );
      expect(
        container.read(skillOperationsViewModelProvider).loadingTargets,
        isFalse,
      );
    },
  );
}

Future<void> _untilTargets(
  ProviderContainer container,
  bool Function(SkillOperationsState) ready,
) async {
  final complete = Completer<void>();
  final subscription = container.listen(skillOperationsViewModelProvider, (
    _,
    state,
  ) {
    if (ready(state) && !complete.isCompleted) complete.complete();
  }, fireImmediately: true);
  try {
    await complete.future.timeout(const Duration(seconds: 2));
  } finally {
    subscription.close();
  }
}
