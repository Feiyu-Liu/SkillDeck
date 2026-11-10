import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/settings/data/skills_manager_runtime.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

import '../../../support/fake_skills_workspace_repository.dart';

void main() {
  test(
    'owns one package Workspace and reconfigures its Agent catalog in place',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'skills-manager-runtime-',
      );
      final diagnostics = AppDiagnostics.disabled();
      final runtime = SkillsManagerRuntime(
        repositoryRoot: temporary.path,
        settings: const AppSettings(),
        diagnostics: diagnostics,
        failureReporter: AppFailureReporter(diagnostics),
      );
      addTearDown(() async {
        await runtime.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      final workspace = runtime.workspace;
      final completion = await workspace.open();
      final opened = switch (completion) {
        WorkspaceCompleted(:final value) => value,
        WorkspaceFailed(:final failure) => fail('Unexpected failure: $failure'),
        WorkspaceCommittedPending(:final operationId) => fail(
          'Unexpected committed-pending operation: $operationId',
        ),
      };
      expect(opened.revision, 0);

      const nextSettings = AppSettings(
        localePreference: AppLocalePreference.zh,
      );
      await runtime.reconfigureAgentCatalog(nextSettings);

      expect(identical(runtime.workspace, workspace), isTrue);
      expect(runtime.settings.localePreference, AppLocalePreference.zh);

      await runtime.close();
      await runtime.close();
    },
  );

  test(
    'retains committed Custom Agent settings while finalization is pending',
    () async {
      final diagnostics = AppDiagnostics.disabled();
      final workspace = FakeSkillsWorkspaceRepository()
        ..reconfigureAgentCatalogTask = _pendingTask();
      final runtime = SkillsManagerRuntime(
        repositoryRoot: '/unused-injected-workspace',
        settings: const AppSettings(),
        diagnostics: diagnostics,
        failureReporter: AppFailureReporter(diagnostics),
        workspace: workspace,
      );
      addTearDown(runtime.close);

      const nextSettings = AppSettings(
        localePreference: AppLocalePreference.zh,
      );
      final completion = await runtime.reconfigureAgentCatalog(nextSettings);

      expect(
        completion,
        isA<WorkspaceCommittedPending<SkillsWorkspaceSnapshot>>(),
      );
      expect(runtime.settings.localePreference, AppLocalePreference.zh);
      expect(workspace.agentCatalogReconfigurations, hasLength(1));
    },
  );

  test(
    'maps Custom Agent compatibility discovery paths into Workspace',
    () async {
      final diagnostics = AppDiagnostics.disabled();
      final workspace = FakeSkillsWorkspaceRepository();
      final runtime = SkillsManagerRuntime(
        repositoryRoot: '/unused-injected-workspace',
        settings: const AppSettings(),
        diagnostics: diagnostics,
        failureReporter: AppFailureReporter(diagnostics),
        workspace: workspace,
      );
      addTearDown(runtime.close);
      const nextSettings = AppSettings(
        customAgents: <CustomAgentSettings>[
          CustomAgentSettings(
            id: 'custom-reviewer-1234',
            displayName: 'Reviewer',
            iconName: 'bot',
            platforms: <AppDesktopPlatform, CustomAgentPlatformSettings>{
              AppDesktopPlatform.linux: CustomAgentPlatformSettings(
                globalSkillsPath: '/opt/reviewer/skills',
                projectSkillsPath: '.reviewer/skills',
                globalDiscoverySkillsPaths: <String>[
                  '/opt/reviewer/legacy-skills',
                ],
                projectDiscoverySkillsPaths: <String>[
                  '.reviewer/legacy-skills',
                ],
              ),
            },
          ),
        ],
      );

      await runtime.reconfigureAgentCatalog(nextSettings);

      final platform = workspace
          .agentCatalogReconfigurations
          .single
          .single
          .platforms[WorkspaceDesktopPlatform.linux]!;
      expect(platform.globalSkillsPath, '/opt/reviewer/skills');
      expect(platform.projectSkillsPath, '.reviewer/skills');
      expect(platform.globalDiscoverySkillsPaths, <String>[
        '/opt/reviewer/legacy-skills',
      ]);
      expect(platform.projectDiscoverySkillsPaths, <String>[
        '.reviewer/legacy-skills',
      ]);
    },
  );
}

WorkspaceTask<SkillsWorkspaceSnapshot> _pendingTask() => WorkspaceTask(
  current: WorkspaceOperationProgress(
    operationId: 'settings-pending',
    kind: WorkspaceOperationKind.reconfigureAgentCatalog,
    phase: WorkspaceOperationPhase.finalizing,
  ),
  states: const Stream.empty(),
  completed: Future.value(
    WorkspaceCommittedPending(
      operationId: 'settings-pending',
      committedRevision: 3,
    ),
  ),
  cancel: () async {},
);
