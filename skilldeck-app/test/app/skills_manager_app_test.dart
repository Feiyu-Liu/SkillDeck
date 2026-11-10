import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/app/skills_manager_app.dart';
import 'package:skills_manager/features/settings/data/skills_manager_runtime.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

import '../support/fake_skill_browser_repository.dart';
import '../support/fake_skills_workspace_repository.dart';
import '../support/recording_app_diagnostic_sink.dart';
import '../support/skills_manager_test_app.dart';

void main() {
  test(
    'root Provider container closes its Runtime owner exactly once',
    () async {
      final workspace = FakeSkillsWorkspaceRepository();
      final diagnostics = AppDiagnostics.disabled();
      final runtime = SkillsManagerRuntime(
        repositoryRoot: '/unused-injected-workspace',
        settings: const AppSettings(),
        diagnostics: diagnostics,
        failureReporter: AppFailureReporter(diagnostics),
        workspace: workspace,
      );
      final container = ProviderContainer(
        overrides: [
          skillsManagerRuntimeFactoryProvider.overrideWithValue(() => runtime),
        ],
      );

      expect(container.read(skillsManagerRuntimeProvider), same(runtime));
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      await runtime.close();

      expect(workspace.closeCalls, 1);
    },
  );

  test('root Provider reports an asynchronous Runtime close failure', () async {
    final closeError = StateError('close failed');
    final workspace = FakeSkillsWorkspaceRepository()..closeError = closeError;
    addTearDown(workspace.dispose);
    final sink = RecordingAppDiagnosticSink();
    final diagnostics = AppDiagnostics(sink: sink);
    final runtime = SkillsManagerRuntime(
      repositoryRoot: '/unused-injected-workspace',
      settings: const AppSettings(),
      diagnostics: diagnostics,
      failureReporter: AppFailureReporter(diagnostics),
      workspace: workspace,
    );
    final container = ProviderContainer(
      overrides: [
        appDiagnosticsProvider.overrideWithValue(diagnostics),
        skillsManagerRuntimeFactoryProvider.overrideWithValue(() => runtime),
      ],
    );

    expect(container.read(skillsManagerRuntimeProvider), same(runtime));
    container.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(workspace.closeCalls, 1);
    expect(sink.events, hasLength(1));
    expect(sink.events.single.event, 'error.unhandled');
    expect(sink.events.single.operationKey, 'shutdownWorkspace');
    expect(sink.events.single.errorType, 'StateError');
  });

  testWidgets('failed finalization exposes a reachable retry action', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository()
      ..finalizationRecoveryTasks.addAll([
        _recoveryTask(
          'first-recovery',
          WorkspaceFailed(
            failure: WorkspaceFailure(
              code: WorkspaceErrorCode.finalizationRecoveryFailed,
              operation: WorkspaceOperationKind.resumeFinalizationRecovery,
            ),
          ),
        ),
        _recoveryTask(
          'second-recovery',
          WorkspaceCompleted(
            value: SkillsWorkspaceSnapshot(
              revision: 4,
              projectRoots: const [],
              skills: const [],
            ),
          ),
        ),
      ]);
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SkillsManagerApp)),
    );

    container
        .read(workspaceFinalizationCoordinatorProvider.notifier)
        .register(
          WorkspaceCommittedPending<void>(
            operationId: 'retry-visible',
            committedRevision: 4,
          ),
        );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('workspace-finalization-retry'))
          .evaluate()
          .isNotEmpty,
    );

    expect(
      find.byKey(const Key('workspace-finalization-retry-button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('workspace-finalization-retry-button')),
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const Key('workspace-finalization-retry'))
          .evaluate()
          .isEmpty,
    );

    expect(workspace.finalizationRecoveryCalls, 2);
  });
}

WorkspaceTask<SkillsWorkspaceSnapshot> _recoveryTask(
  String operationId,
  WorkspaceCompletion<SkillsWorkspaceSnapshot> completion,
) => WorkspaceTask(
  current: WorkspaceOperationProgress(
    operationId: operationId,
    kind: WorkspaceOperationKind.resumeFinalizationRecovery,
    phase: WorkspaceOperationPhase.finalizing,
  ),
  states: const Stream.empty(),
  completed: Future.value(completion),
  cancel: () async {},
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var index = 0; index < 40; index++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (predicate()) return;
  }
  fail('Condition did not become true.');
}
