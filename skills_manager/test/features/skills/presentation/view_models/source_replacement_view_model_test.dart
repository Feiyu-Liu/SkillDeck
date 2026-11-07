import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/source_replacement_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

import '../../../../support/fake_app_translation_repository.dart';
import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';

void main() {
  final localSourcePath = p.join(Directory.systemTemp.path, 'alpha');
  final target = InstalledSkill(
    id: WorkspaceSkillId('alpha'),
    slotKey: 'alpha',
    displayName: 'Alpha Skill',
    description: '',
    contentHash: 'hash-alpha',
    activationCount: 0,
  );

  const candidateAlpha = WorkspaceSourceCandidate(
    declaredName: 'Alpha Skill',
    description: 'The Alpha Skill',
    slotKey: 'alpha',
    skillPath: 'skills/alpha',
    contentHash: 'hash-alpha',
    fileCount: 1,
    byteSize: 10,
  );

  const candidateBeta = WorkspaceSourceCandidate(
    declaredName: 'Beta Skill',
    description: 'A different Skill',
    slotKey: 'beta',
    skillPath: 'skills/beta',
    contentHash: 'hash-beta',
    fileCount: 1,
    byteSize: 10,
  );

  test('inspecting a source preselects the matching Skill', () async {
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://example.com/skills.git',
        ),
        candidates: const [candidateBeta, candidateAlpha],
      );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    vm.selectSourceKind(SkillSourceKind.git);
    vm.updateLocator('https://example.com/skills.git');
    await vm.inspect();

    final state = container.read(sourceReplacementViewModelProvider);
    expect(state.step, ReplacementStep.select);
    expect(state.status, ReplacementStatus.ready);
    expect(state.selectedSlotKey, 'alpha');
  });

  test('a pasted Source is detected and inspected in smart mode', () async {
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://github.com/acme/skills',
        ),
        candidates: const [candidateAlpha],
      );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    expect(
      container.read(sourceReplacementViewModelProvider).inputMode,
      SkillSourceInputMode.smart,
    );
    expect(
      container.read(sourceReplacementViewModelProvider).canInspect,
      isFalse,
    );
    vm.updateRawInput('https://github.com/acme/skills');
    expect(
      container.read(sourceReplacementViewModelProvider).canInspect,
      isTrue,
    );
    await vm.inspect();

    final state = container.read(sourceReplacementViewModelProvider);
    expect(workspace.inspectedSources.single.kind, WorkspaceSourceKind.git);
    expect(state.step, ReplacementStep.select);
    expect(state.selectedSlotKey, 'alpha');
  });

  test('switching to typed mode carries the pasted Source across', () {
    final container = _container(FakeSkillsWorkspaceRepository());
    addTearDown(container.dispose);
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    vm.updateRawInput('https://github.com/acme/skills');
    vm.selectInputMode(SkillSourceInputMode.typed);

    final state = container.read(sourceReplacementViewModelProvider);
    expect(state.inputMode, SkillSourceInputMode.typed);
    expect(state.sourceKindChosen, isTrue);
    expect(state.sourceDraft.kind, SkillSourceKind.git);
    expect(state.sourceDraft.locator, 'https://github.com/acme/skills');
  });

  test('editing the source after inspecting returns to step one', () async {
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://example.com/skills.git',
        ),
        candidates: const [candidateAlpha],
      );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    vm.selectSourceKind(SkillSourceKind.git);
    vm.updateLocator('https://example.com/skills.git');
    await vm.inspect();
    expect(
      container.read(sourceReplacementViewModelProvider).step,
      ReplacementStep.select,
    );

    vm.updateLocator('https://example.com/other.git');

    final state = container.read(sourceReplacementViewModelProvider);
    expect(state.step, ReplacementStep.source);
    expect(state.status, ReplacementStatus.idle);
    expect(state.inspection, isNull);
    expect(state.selectedSlotKey, isNull);
  });

  test('a candidate for a different Skill cannot be selected', () async {
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://example.com/skills.git',
        ),
        candidates: const [candidateBeta],
      );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    vm.selectSourceKind(SkillSourceKind.git);
    vm.updateLocator('https://example.com/skills.git');
    await vm.inspect();

    var state = container.read(sourceReplacementViewModelProvider);
    expect(state.selectedSlotKey, isNull);
    expect(state.canContinueToReplace, isFalse);

    vm.selectCandidate('beta');

    state = container.read(sourceReplacementViewModelProvider);
    expect(state.selectedSlotKey, isNull);
  });

  test('replace forwards the resolved source and reviewed revision', () async {
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://example.com/skills.git',
        ),
        candidates: const [candidateAlpha],
      );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 12, skills: [target]),
    );
    final container = _container(workspace, browser: browser);
    addTearDown(container.dispose);
    await container.read(skillBrowserViewModelProvider.notifier).load();
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    vm.selectSourceKind(SkillSourceKind.git);
    vm.updateLocator('https://example.com/skills.git');
    vm.updateSourceRef('main');
    vm.updateRepositorySubpath('skills/alpha');
    await vm.inspect();
    vm.continueToReplace();

    final outcome = await vm.replace();

    expect(outcome, ReplaceSourceOutcome.replaced);
    expect(workspace.replaceSourceRequests, hasLength(1));
    final request = workspace.replaceSourceRequests.single;
    expect(request.slotKey, 'alpha');
    expect(request.expectedRevision, 12);
    expect(request.source.kind, WorkspaceSourceKind.git);
    expect(request.source.locator, 'https://example.com/skills.git');
    expect(request.source.ref, 'main');
    expect(request.source.repositorySubpath, 'skills/alpha');
    expect(request.source.skillPath, 'skills/alpha');
  });

  test('a multi-Skill source is narrowed to the selected candidate', () async {
    // Replacement preparation rejects a Source that resolves to more than one
    // Skill, so the request must carry the chosen candidate's skillPath
    // rather than the whole repository the user typed.
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://example.com/marketingskills.git',
        ),
        candidates: const [candidateBeta, candidateAlpha],
      );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 12, skills: [target]),
    );
    final container = _container(workspace, browser: browser);
    addTearDown(container.dispose);
    await container.read(skillBrowserViewModelProvider.notifier).load();
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    vm.selectSourceKind(SkillSourceKind.git);
    vm.updateLocator('https://example.com/marketingskills.git');
    await vm.inspect();
    vm.continueToReplace();

    final outcome = await vm.replace();

    expect(outcome, ReplaceSourceOutcome.replaced);
    final request = workspace.replaceSourceRequests.single;
    expect(request.source.locator, 'https://example.com/marketingskills.git');
    expect(request.source.repositorySubpath, '');
    expect(request.source.skillPath, 'skills/alpha');
  });

  test('a failed source inspection reaches the user as a toast', () async {
    // The wizard renders no inline failure surface, so the notification is the
    // only place a failed inspection can surface. Losing it would fail
    // silently on step one.
    final workspace = FakeSkillsWorkspaceRepository()
      ..inspectSourceError = WorkspaceException(
        code: WorkspaceErrorCode.sourceUnavailable,
        operation: WorkspaceOperationKind.inspectSource,
      );
    final container = _container(workspace);
    addTearDown(container.dispose);
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    vm.selectSourceKind(SkillSourceKind.git);
    vm.updateLocator('https://example.com/skills.git');
    await vm.inspect();

    final state = container.read(sourceReplacementViewModelProvider);
    expect(state.step, ReplacementStep.source);
    expect(state.status, ReplacementStatus.failure);
    expect(state.failure, isNotNull);

    final event = container.read(appNotificationControllerProvider)!;
    expect(event.notification.severity, AppNotificationSeverity.error);
  });

  test('a stale replacement refreshes the browser catalog', () async {
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: SkillSourceInput(
          kind: WorkspaceSourceKind.local,
          locator: localSourcePath,
        ),
        candidates: const [candidateAlpha],
      )
      ..replaceSourceError = WorkspaceException(
        code: WorkspaceErrorCode.staleSnapshot,
        operation: WorkspaceOperationKind.replaceSource,
      );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 12, skills: [target]),
    );
    final container = _container(workspace, browser: browser);
    addTearDown(container.dispose);
    await container.read(skillBrowserViewModelProvider.notifier).load();
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    vm.selectSourceKind(SkillSourceKind.local);
    vm.updateLocator(localSourcePath);
    await vm.inspect();
    vm.continueToReplace();

    final outcome = await vm.replace();

    expect(outcome, ReplaceSourceOutcome.stale);
    expect(browser.refreshCalls, 1);
  });

  test('a cancelled replacement is not reported as a failure', () async {
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: SkillSourceInput(
          kind: WorkspaceSourceKind.local,
          locator: localSourcePath,
        ),
        candidates: const [candidateAlpha],
      )
      ..replaceSourceError = WorkspaceException(
        code: WorkspaceErrorCode.operationCancelled,
        operation: WorkspaceOperationKind.replaceSource,
      );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 12, skills: [target]),
    );
    final container = _container(workspace, browser: browser);
    addTearDown(container.dispose);
    await container.read(skillBrowserViewModelProvider.notifier).load();
    final vm = container.read(sourceReplacementViewModelProvider.notifier);

    vm.begin(target);
    vm.selectSourceKind(SkillSourceKind.local);
    vm.updateLocator(localSourcePath);
    await vm.inspect();
    vm.continueToReplace();

    final outcome = await vm.replace();

    expect(outcome, ReplaceSourceOutcome.cancelled);
  });

  test(
    'a failed replacement is reported through the operation state',
    () async {
      final workspace = FakeSkillsWorkspaceRepository()
        ..sourceInspection = WorkspaceSourceInspection(
          source: SkillSourceInput(
            kind: WorkspaceSourceKind.local,
            locator: localSourcePath,
          ),
          candidates: const [candidateAlpha],
        )
        ..replaceSourceError = WorkspaceException(
          code: WorkspaceErrorCode.sourceUnavailable,
          operation: WorkspaceOperationKind.replaceSource,
        );
      final browser = FakeSkillBrowserRepository(
        catalog: InstalledSkillCatalog(revision: 12, skills: [target]),
      );
      final container = _container(workspace, browser: browser);
      addTearDown(container.dispose);
      await container.read(skillBrowserViewModelProvider.notifier).load();
      final vm = container.read(sourceReplacementViewModelProvider.notifier);

      vm.begin(target);
      vm.selectSourceKind(SkillSourceKind.local);
      vm.updateLocator(localSourcePath);
      await vm.inspect();
      vm.continueToReplace();

      final outcome = await vm.replace();

      expect(outcome, isNull);
      expect(container.read(skillOperationsViewModelProvider).error, isNotNull);
    },
  );
}

ProviderContainer _container(
  FakeSkillsWorkspaceRepository workspace, {
  FakeSkillBrowserRepository? browser,
}) {
  return ProviderContainer(
    overrides: [
      skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
      skillAcquisitionRepositoryProvider.overrideWithValue(
        WorkspaceSkillAcquisitionRepository(
          workspace: workspace,
          resolver: SkillSourceLocatorResolver(),
        ),
      ),
      skillBrowserRepositoryProvider.overrideWithValue(
        browser ?? FakeSkillBrowserRepository(),
      ),
      skillBrowserCatalogAuthorityProvider.overrideWithValue(
        SkillBrowserCatalogAuthority.repository,
      ),
      appTranslationRepositoryProvider.overrideWithValue(
        fakeAppTranslationRepository(),
      ),
    ],
  );
}
