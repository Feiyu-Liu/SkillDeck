import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_source_input_mode.dart';
import 'package:skills_manager/l10n/app_failure_l10n.dart';
import 'package:skills_manager/l10n/generated/app_localizations_en.dart';
import 'package:skills_manager/l10n/generated/app_localizations_zh.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_acquisition_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';

import '../../../../support/fake_skill_acquisition_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/recording_app_analytics.dart';
import '../../../../support/skill_drift_test_support.dart';

void main() {
  final originalPlatform = SharedPreferencesAsyncPlatform.instance;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDownAll(() {
    SharedPreferencesAsyncPlatform.instance = originalPlatform;
  });
  const source = ResolvedSkillSource(
    kind: SkillSourceKind.git,
    value: 'owner/repository',
  );
  final inspection = SkillSourceInspection(
    source: source,
    candidates: const [
      SkillCandidate(
        slotKey: 'alpha',
        declaredName: 'Alpha',
        description: 'Alpha description',
        skillPath: 'skills/alpha',
      ),
      SkillCandidate(
        slotKey: 'beta',
        declaredName: 'Beta',
        description: 'Beta description',
        skillPath: 'skills/beta',
      ),
    ],
  );

  test(
    'inspection uses the explicit draft and selects every candidate',
    () async {
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection;
      final analytics = RecordingAppAnalytics();
      final container = _container(repository, analytics: analytics);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillAcquisitionViewModelProvider.notifier,
      );
      viewModel
        ..selectSourceKind(SkillSourceKind.git)
        ..updateLocator(source.value)
        ..updateSourceRef('release/v2')
        ..updateRepositorySubpath('packages/skills');

      await viewModel.inspect();

      final state = container.read(skillAcquisitionViewModelProvider);
      expect(state.step, AcquisitionStep.skills);
      expect(viewModel.status, AcquisitionStatus.ready);
      expect(viewModel.selectedSlots, {'alpha', 'beta'});
      expect(repository.inspectedDraft?.kind, SkillSourceKind.git);
      expect(repository.inspectedDraft?.locator, source.value);
      expect(repository.inspectedDraft?.sourceRef, 'release/v2');
      expect(repository.inspectedDraft?.repositorySubpath, 'packages/skills');
      expect(analytics.events.single.action, 'source_inspection');
      expect(analytics.events.single.name, 'success');
    },
  );

  test('inspection retains terminal-only warnings', () async {
    final terminalWarning = WorkspaceWarning(
      code: WorkspaceWarningCode.sourceEntrySkipped,
      context: const {'entry': 'unsupported.txt'},
    );
    final repository = FakeSkillAcquisitionRepository()
      ..inspectHandler = (_) => AcquisitionTask(
        current: const AcquisitionProgress(phase: AcquisitionPhase.inspecting),
        states: const Stream.empty(),
        completed: Future.value(
          WorkspaceCompleted(value: inspection, warnings: [terminalWarning]),
        ),
        cancel: () async {},
      );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);

    await viewModel.inspect();

    expect(viewModel.status, AcquisitionStatus.ready);
    expect(viewModel.warnings, [terminalWarning]);
  });

  test(
    'inspection retains terminal-only warnings while finalization is pending',
    () async {
      final terminalWarning = WorkspaceWarning(
        code: WorkspaceWarningCode.finalizationDeferred,
        context: const {'operationId': 'pending-inspection'},
      );
      final repository = FakeSkillAcquisitionRepository()
        ..inspectHandler = (_) => AcquisitionTask(
          current: const AcquisitionProgress(
            phase: AcquisitionPhase.inspecting,
          ),
          states: const Stream.empty(),
          completed: Future.value(
            WorkspaceCommittedPending(
              operationId: 'pending-inspection',
              committedRevision: 1,
              warnings: [terminalWarning],
            ),
          ),
          cancel: () async {},
        );
      final workspace = FakeSkillsWorkspaceRepository();
      final container = _container(repository, workspace: workspace);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillAcquisitionViewModelProvider.notifier,
      );
      viewModel.updateLocator(source.value);

      await viewModel.inspect();

      expect(viewModel.status, AcquisitionStatus.idle);
      expect(viewModel.warnings, [terminalWarning]);
      await Future<void>.delayed(Duration.zero);
      expect(workspace.finalizationRecoveryCalls, 1);
    },
  );

  test('source switching preserves form and invalidates inspection', () async {
    final repository = FakeSkillAcquisitionRepository()
      ..inspection = inspection;
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel
      ..updateLocator(source.value)
      ..updateSourceRef('main')
      ..updateRepositorySubpath('skills');
    await viewModel.inspect();

    viewModel.selectSourceKind(SkillSourceKind.wellKnown);

    final state = container.read(skillAcquisitionViewModelProvider);
    expect(state.step, AcquisitionStep.source);
    expect(state.status, AcquisitionStatus.idle);
    expect(state.sourceDraft.kind, SkillSourceKind.wellKnown);
    expect(state.sourceDraft.locator, source.value);
    expect(state.sourceDraft.sourceRef, 'main');
    expect(state.sourceDraft.repositorySubpath, 'skills');
    expect(state.inspection, isNull);
    expect(state.selectedSlots, isEmpty);
  });

  test(
    'back from candidates preserves form and requires fresh inspect',
    () async {
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection;
      final analytics = RecordingAppAnalytics();
      final container = _container(repository, analytics: analytics);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillAcquisitionViewModelProvider.notifier,
      );
      viewModel
        ..updateLocator(source.value)
        ..updateSourceRef('main')
        ..updateRepositorySubpath('skills');
      await viewModel.inspect();

      viewModel.back();

      final state = container.read(skillAcquisitionViewModelProvider);
      expect(state.step, AcquisitionStep.source);
      expect(state.status, AcquisitionStatus.idle);
      expect(state.sourceDraft.locator, source.value);
      expect(state.sourceDraft.sourceRef, 'main');
      expect(state.sourceDraft.repositorySubpath, 'skills');
      expect(state.inspection, isNull);
      expect(state.selectedSlots, isEmpty);
    },
  );

  test('selected skills and inspected source are submitted without Browser writeback', () async {
    final catalog = InstalledSkillCatalog(revision: 2, skills: const []);
    final repository = FakeSkillAcquisitionRepository()
      ..inspection = inspection
      ..receipt = InstallReceipt(catalog: catalog, affectedSlotKeys: {'alpha'});
    final analytics = RecordingAppAnalytics();
    final container = _container(repository, analytics: analytics);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);
    await viewModel.inspect();
    viewModel.toggleSkill('beta', false);
    await viewModel.continueToActivation(const []);

    await viewModel.install();

    final selection = repository.installSelection!;
    expect(selection.installAllSkills, isFalse);
    expect(selection.activationMethod, WorkspaceActivationMethod.automatic);
    expect(selection.selectedSkillNames, {'Alpha'});
    expect(selection.selectedAgentIds, {'codex'});
    expect(identical(selection.source, inspection.source), isTrue);
    expect(viewModel.status, AcquisitionStatus.success);
    final notification = container.read(appNotificationControllerProvider);
    expect(notification?.sequence, 1);
    expect(
      notification?.notification.message,
      AppNotificationMessage.skillsInstalled,
    );
    expect(
      notification?.notification.severity,
      AppNotificationSeverity.success,
    );
    expect(analytics.events.map((event) => event.action), [
      'source_inspection',
      'skill_install',
    ]);
    expect(analytics.events.last.name, 'success');
  });

  test('all selected candidates preserve install-all semantics', () async {
    final repository = FakeSkillAcquisitionRepository()
      ..inspection = inspection
      ..receipt = InstallReceipt(
        catalog: InstalledSkillCatalog(revision: 1, skills: const []),
        affectedSlotKeys: {'alpha', 'beta'},
      );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);
    await viewModel.inspect();
    await viewModel.continueToActivation(const []);

    await viewModel.install();

    expect(repository.installSelection!.installAllSkills, isTrue);
  });

  test('skill selection tracks none, partial, and all states', () async {
    final repository = FakeSkillAcquisitionRepository()
      ..inspection = inspection;
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);
    await viewModel.inspect();

    expect(viewModel.skillSelectionState, SkillSelectionState.all);

    viewModel.toggleSkill('beta', false);

    expect(viewModel.selectedSlots, {'alpha'});
    expect(viewModel.skillSelectionState, SkillSelectionState.partial);

    viewModel.toggleAllSkills(true);

    expect(viewModel.selectedSlots, {'alpha', 'beta'});
    expect(viewModel.skillSelectionState, SkillSelectionState.all);

    viewModel.toggleAllSkills(false);

    expect(viewModel.selectedSlots, isEmpty);
    expect(viewModel.skillSelectionState, SkillSelectionState.none);
  });

  test('reconciles project roots and reloads targets', () async {
    final repository = FakeSkillAcquisitionRepository()
      ..inspection = inspection;
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);
    await viewModel.inspect();
    await viewModel.continueToActivation(const []);
    await viewModel.selectScope(SkillActivationScope.project, const []);

    expect(viewModel.canInstall, isFalse);
    expect(repository.targetInspections, hasLength(1));

    const firstRoot = SkillProjectRoot(id: 'one', path: '/projects/one');
    await viewModel.reconcileProjectRoots(const [firstRoot]);

    var state = container.read(skillAcquisitionViewModelProvider);
    expect(state.projectRootId, firstRoot.id);
    expect(
      repository.targetInspections.last.scope,
      SkillActivationScope.project,
    );
    expect(repository.targetInspections.last.projectRootId, firstRoot.id);
    expect(viewModel.canInstall, isTrue);

    const secondRoot = SkillProjectRoot(id: 'two', path: '/projects/two');
    await viewModel.reconcileProjectRoots(const [firstRoot, secondRoot]);
    state = container.read(skillAcquisitionViewModelProvider);
    expect(state.projectRootId, firstRoot.id);
  });

  test(
    'target inspection keeps an expected failure in typed UI state',
    () async {
      final warning = WorkspaceWarning(
        code: WorkspaceWarningCode.agentUndetected,
        context: const {'agentId': 'missing'},
      );
      final targetFailure = WorkspaceException(
        operation: WorkspaceOperationKind.inspectActivationTargets,
        code: WorkspaceErrorCode.activationUnavailable,
        warnings: [warning],
      );
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection
        ..inspectTargetsError = targetFailure;
      final container = _container(repository);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillAcquisitionViewModelProvider.notifier,
      );
      viewModel.updateLocator(source.value);
      await viewModel.inspect();

      await viewModel.continueToActivation(const []);

      expect(viewModel.failure, same(targetFailure));
      expect(viewModel.agents, isEmpty);
      expect(viewModel.warnings, [warning]);
      expect(
        container.read(appNotificationControllerProvider)?.notification.failure,
        same(targetFailure),
      );
    },
  );

  test(
    'install merges terminal-only warnings and notifies with a warning',
    () async {
      final progressWarning = WorkspaceWarning(
        code: WorkspaceWarningCode.agentUndetected,
        context: const {'agentId': 'unavailable'},
      );
      final terminalWarning = WorkspaceWarning(
        code: WorkspaceWarningCode.noActivationTarget,
        context: const {'agentId': 'unavailable'},
      );
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection
        ..installHandler = (_) => AcquisitionTask(
          current: AcquisitionProgress(
            phase: AcquisitionPhase.applying,
            warnings: [progressWarning],
          ),
          states: const Stream.empty(),
          completed: Future.value(
            WorkspaceCompleted(
              value: AcquisitionInstallCompleted(
                InstallReceipt(
                  catalog: InstalledSkillCatalog(revision: 1, skills: const []),
                  affectedSlotKeys: {'alpha', 'beta'},
                ),
              ),
              warnings: [progressWarning, terminalWarning],
            ),
          ),
          cancel: () async {},
        );
      final container = _container(repository);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillAcquisitionViewModelProvider.notifier,
      );
      viewModel.updateLocator(source.value);
      await viewModel.inspect();
      await viewModel.continueToActivation(const []);

      await viewModel.install();

      expect(viewModel.status, AcquisitionStatus.success);
      expect(viewModel.warnings.map((warning) => warning.code), [
        WorkspaceWarningCode.agentUndetected,
        WorkspaceWarningCode.noActivationTarget,
      ]);
      final notification = container.read(appNotificationControllerProvider);
      expect(notification?.sequence, 1);
      expect(
        notification?.notification.message,
        AppNotificationMessage.completedWithWarnings,
      );
      expect(
        notification?.notification.severity,
        AppNotificationSeverity.warning,
      );
    },
  );

  test('install takeover waits for confirmation and then completes', () async {
    final draft = FakeWorkspaceInstallTakeoverDraft(
      targets: [
        WorkspaceOccupiedActivationTarget(
          slotKey: 'alpha',
          location: '/global/.agents/skills',
          targetPath: '/global/.agents/skills/alpha',
          agentIds: const ['codex'],
          kind: WorkspaceActivationTargetOccupancyKind.brokenSymbolicLink,
          contentRelation: WorkspaceActivationContentRelation.indeterminate,
          linkTarget: '/legacy/alpha',
        ),
      ],
    );
    final receipt = InstallReceipt(
      catalog: InstalledSkillCatalog(revision: 1, skills: const []),
      affectedSlotKeys: {'alpha'},
    );
    final repository =
        FakeSkillAcquisitionRepository(
            agents: const [
              AgentOption(
                id: 'codex',
                displayName: 'Codex',
                location: '/global/.agents/skills',
              ),
            ],
          )
          ..inspection = inspection
          ..installAttempt = AcquisitionInstallTakeoverRequired(draft)
          ..receipt = receipt;
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);
    await viewModel.inspect();
    await viewModel.continueToActivation(const []);

    await viewModel.install();

    expect(viewModel.status, AcquisitionStatus.ready);
    expect(viewModel.installTakeover, same(draft));
    expect(container.read(appNotificationControllerProvider), isNull);
    expect(repository.confirmedInstallTakeovers, isEmpty);

    await viewModel.confirmInstallTakeover();

    expect(repository.confirmedInstallTakeovers, [same(draft)]);
    expect(viewModel.status, AcquisitionStatus.success);
    expect(viewModel.installTakeover, isNull);
  });

  test('dismissed Install takeover leaves acquisition retryable', () async {
    final draft = FakeWorkspaceInstallTakeoverDraft(targets: const []);
    final repository = FakeSkillAcquisitionRepository()
      ..inspection = inspection
      ..installAttempt = AcquisitionInstallTakeoverRequired(draft);
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);
    await viewModel.inspect();
    await viewModel.continueToActivation(const []);
    await viewModel.install();

    viewModel.dismissInstallTakeover();

    expect(viewModel.status, AcquisitionStatus.ready);
    expect(viewModel.installTakeover, isNull);
    expect(viewModel.canInstall, isTrue);
    expect(repository.confirmedInstallTakeovers, isEmpty);
  });

  test(
    'install failure stays retryable and publishes the typed failure',
    () async {
      final installFailure = WorkspaceException(
        operation: WorkspaceOperationKind.install,
        code: WorkspaceErrorCode.repositoryBusy,
      );
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection
        ..installError = installFailure;
      final container = _container(repository);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillAcquisitionViewModelProvider.notifier,
      );
      viewModel.updateLocator(source.value);
      await viewModel.inspect();
      await viewModel.continueToActivation(const []);

      await viewModel.install();

      expect(viewModel.status, AcquisitionStatus.ready);
      expect(viewModel.canInstall, isTrue);
      expect(viewModel.failure, same(installFailure));
      final notification = container.read(appNotificationControllerProvider);
      expect(notification?.sequence, 1);
      expect(notification?.notification.failure, same(installFailure));
      expect(
        notification?.notification.severity,
        AppNotificationSeverity.error,
      );
    },
  );

  test('an unprepared host fails inline without publishing a toast', () async {
    final failure = WorkspaceException(
      operation: WorkspaceOperationKind.inspectSource,
      code: WorkspaceErrorCode.developerToolsRequired,
    );
    final repository = FakeSkillAcquisitionRepository()..inspectError = failure;
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);

    await viewModel.inspect();

    // The dialog keeps the guidance on screen; a toast would vanish behind
    // the operating system's own install dialog with nowhere to go next.
    expect(viewModel.status, AcquisitionStatus.failure);
    expect(viewModel.failure, same(failure));
    expect(container.read(appNotificationControllerProvider), isNull);
  });

  test('an ordinary source failure still publishes its toast', () async {
    final failure = WorkspaceException(
      operation: WorkspaceOperationKind.inspectSource,
      code: WorkspaceErrorCode.gitFailed,
    );
    final repository = FakeSkillAcquisitionRepository()..inspectError = failure;
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);

    await viewModel.inspect();

    expect(
      container.read(appNotificationControllerProvider)?.notification.failure,
      same(failure),
    );
  });

  test('install failure retains terminal-only warnings', () async {
    final terminalWarning = WorkspaceWarning(
      code: WorkspaceWarningCode.activationTargetSkipped,
      context: const {'agentId': 'unavailable'},
    );
    final installFailure = WorkspaceException(
      operation: WorkspaceOperationKind.install,
      code: WorkspaceErrorCode.repositoryBusy,
    );
    final repository = FakeSkillAcquisitionRepository()
      ..inspection = inspection
      ..installHandler = (_) => AcquisitionTask(
        current: const AcquisitionProgress(phase: AcquisitionPhase.applying),
        states: const Stream.empty(),
        completed: Future.value(
          WorkspaceFailed(failure: installFailure, warnings: [terminalWarning]),
        ),
        cancel: () async {},
      );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);
    await viewModel.inspect();
    await viewModel.continueToActivation(const []);

    await viewModel.install();

    expect(viewModel.status, AcquisitionStatus.ready);
    expect(viewModel.failure, same(installFailure));
    expect(viewModel.warnings, [terminalWarning]);
  });

  test(
    'install failure analytics reports an allowlisted revision code',
    () async {
      final analytics = RecordingAppAnalytics();
      final failure = WorkspaceException(
        code: WorkspaceErrorCode.operationFailed,
        operation: WorkspaceOperationKind.install,
        context: const {'revisionCode': 'ioFailure'},
      );
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection
        ..installHandler = (_) => AcquisitionTask(
          current: const AcquisitionProgress(phase: AcquisitionPhase.applying),
          states: const Stream.empty(),
          completed: Future.value(WorkspaceFailed(failure: failure)),
          cancel: () async {},
        );
      final container = _container(repository, analytics: analytics);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillAcquisitionViewModelProvider.notifier,
      );
      viewModel.updateLocator(source.value);
      await viewModel.inspect();
      await viewModel.continueToActivation(const []);

      await viewModel.install();

      final event = analytics.events.singleWhere(
        (event) => event.action == 'skill_install',
      );
      expect(event.name, 'failed');
      expect(event.errorCode, 'operationFailed:ioFailure');
    },
  );

  test(
    'safe failure is exposed and notified without raw exception details',
    () async {
      final repository = FakeSkillAcquisitionRepository()
        ..inspectError = StateError('raw filesystem details');
      final container = _container(repository);
      addTearDown(container.dispose);
      final viewModel = container.read(
        skillAcquisitionViewModelProvider.notifier,
      );
      viewModel.updateLocator(source.value);

      await viewModel.inspect();

      expect(viewModel.status, AcquisitionStatus.failure);
      final failure = viewModel.failure;
      expect(failure, isA<UnexpectedAppFailure>());
      expect(
        failure?.operationKey,
        SkillAcquisitionOperation.inspectSource.name,
      );
      expect(failure?.message, AppFailureMessage.inspectSource);
      expect(failure.toString(), isNot(contains('raw filesystem details')));
      final notification = container.read(appNotificationControllerProvider);
      expect(notification?.sequence, 1);
      expect(notification?.notification.failure, same(failure));
      expect(
        notification?.notification.severity,
        AppNotificationSeverity.error,
      );
    },
  );

  test('cancel forwards to the active operation', () async {
    final result = Completer<WorkspaceCompletion<SkillSourceInspection>>();
    var cancelCalls = 0;
    final repository = FakeSkillAcquisitionRepository()
      ..inspectHandler = (_) => AcquisitionTask<SkillSourceInspection>(
        current: const AcquisitionProgress(phase: AcquisitionPhase.inspecting),
        states: const Stream.empty(),
        completed: result.future,
        cancel: () async {
          cancelCalls += 1;
          result.complete(
            WorkspaceFailed(
              failure: WorkspaceException(
                operation: WorkspaceOperationKind.inspectSource,
                code: WorkspaceErrorCode.operationCancelled,
              ),
            ),
          );
        },
      );
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel.updateLocator(source.value);
    final inspectionFuture = viewModel.inspect();

    await viewModel.cancel();
    await inspectionFuture;

    expect(cancelCalls, 1);
    expect(viewModel.status, AcquisitionStatus.idle);
    expect(viewModel.failure, isNull);
    final notification = container.read(appNotificationControllerProvider);
    expect(notification?.sequence, 1);
    expect(
      notification?.notification.message,
      AppNotificationMessage.operationCancelled,
    );
    expect(notification?.notification.severity, AppNotificationSeverity.info);
  });

  test('an empty or blank locator cannot start an inspection', () async {
    final repository = FakeSkillAcquisitionRepository()
      ..inspection = inspection;
    final analytics = RecordingAppAnalytics();
    final container = _container(repository, analytics: analytics);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );

    expect(viewModel.canInspect, isFalse, reason: 'no kind chosen yet');
    viewModel.selectSourceKind(SkillSourceKind.git);
    expect(viewModel.canInspect, isFalse, reason: 'empty locator');
    viewModel.updateLocator('   ');
    expect(viewModel.canInspect, isFalse, reason: 'blank locator');

    await viewModel.inspect();

    expect(repository.inspectedDraft, isNull);
    expect(analytics.events, isEmpty);
    expect(viewModel.status, AcquisitionStatus.idle);

    viewModel.updateLocator(source.value);
    expect(viewModel.canInspect, isTrue);
  });

  test('switching between a folder and a URL kind clears the locator', () {
    final container = _container(FakeSkillAcquisitionRepository());
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );

    viewModel
      ..selectSourceKind(SkillSourceKind.git)
      ..updateLocator('owner/repository')
      ..selectSourceKind(SkillSourceKind.local);
    expect(
      container.read(skillAcquisitionViewModelProvider).sourceDraft.locator,
      isEmpty,
    );

    viewModel
      ..updateLocator('/Users/me/skills')
      ..selectSourceKind(SkillSourceKind.wellKnown);
    expect(
      container.read(skillAcquisitionViewModelProvider).sourceDraft.locator,
      isEmpty,
    );
  });

  test(
    'already-installed candidates are marked and left out of the selection',
    () async {
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection;
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: driftWidgetSnapshot(
          integrity: WorkspaceSkillIntegrityStatus.healthy,
        ),
      );
      final container = _container(repository, workspace: workspace);
      addTearDown(container.dispose);
      await container.read(workspaceSnapshotProvider.future);
      final viewModel = container.read(
        skillAcquisitionViewModelProvider.notifier,
      );
      viewModel
        ..selectSourceKind(SkillSourceKind.git)
        ..updateLocator(source.value);

      await viewModel.inspect();

      expect(viewModel.installedSlotKeys, {'alpha'});
      expect(viewModel.selectedSlots, {'beta'});
      expect(viewModel.skillSelectionState, SkillSelectionState.all);
      expect(viewModel.installedSkill('alpha')?.id, driftWidgetSkillId);

      viewModel.toggleSkill('alpha', true);
      expect(viewModel.selectedSlots, {'beta'});
      viewModel.toggleAllSkills(false);
      expect(viewModel.selectedSlots, isEmpty);
      viewModel.toggleAllSkills(true);
      expect(viewModel.selectedSlots, {'beta'});
    },
  );

  test('reinspect returns to the source step and inspects again', () async {
    final repository = FakeSkillAcquisitionRepository()
      ..inspection = inspection;
    final container = _container(repository);
    addTearDown(container.dispose);
    final viewModel = container.read(
      skillAcquisitionViewModelProvider.notifier,
    );
    viewModel
      ..selectSourceKind(SkillSourceKind.git)
      ..updateLocator(source.value);
    await viewModel.inspect();
    await viewModel.continueToActivation(const []);
    repository.inspectedDraft = null;

    await viewModel.reinspect();

    final state = container.read(skillAcquisitionViewModelProvider);
    expect(repository.inspectedDraft?.locator, source.value);
    expect(state.step, AcquisitionStep.skills);
    expect(state.selectedSlots, {'alpha', 'beta'});
  });

  group('smart input', () {
    for (final (input, kind, locator, detection, sourceRef, subpath) in [
      (
        '/tmp/my-skills',
        SkillSourceKind.local,
        '/tmp/my-skills',
        SkillSourceDetection.local,
        '',
        '',
      ),
      (
        'owner/repo/skills/alpha',
        SkillSourceKind.git,
        'owner/repo',
        SkillSourceDetection.gitShorthand,
        '',
        'skills/alpha',
      ),
      (
        'github.com/owner/repo/tree/main/skills',
        SkillSourceKind.git,
        'https://github.com/owner/repo',
        SkillSourceDetection.gitHostedUrl,
        'main',
        'skills',
      ),
      (
        'git@host:owner/repo.git',
        SkillSourceKind.git,
        'git@host:owner/repo.git',
        SkillSourceDetection.gitRemote,
        '',
        '',
      ),
      (
        'https://example.com/skills',
        SkillSourceKind.wellKnown,
        'https://example.com/skills',
        SkillSourceDetection.webUrl,
        '',
        '',
      ),
    ]) {
      test(
        '$detection inspects the normalized draft and stays on source',
        () async {
          final repository = FakeSkillAcquisitionRepository()
            ..inspection = inspection;
          final container = _container(
            repository,
            inputMode: SkillSourceInputMode.smart,
          );
          addTearDown(container.dispose);
          final vm = container.read(skillAcquisitionViewModelProvider.notifier);
          vm.updateRawInput(input);
          expect(
            container.read(skillAcquisitionViewModelProvider).detection,
            detection,
          );
          expect(vm.canInspect, isTrue);
          await vm.inspect();
          final draft = repository.inspectedDraft!;
          expect(draft.kind, kind);
          expect(draft.locator, locator);
          expect(draft.sourceRef, sourceRef);
          expect(draft.repositorySubpath, subpath);
          final state = container.read(skillAcquisitionViewModelProvider);
          expect(state.step, AcquisitionStep.source);
          expect(state.smartInspected, isTrue);
          expect(state.status, AcquisitionStatus.ready);
          vm.continueFromSmartResult();
          expect(
            container.read(skillAcquisitionViewModelProvider).step,
            AcquisitionStep.skills,
          );
        },
      );
    }

    test(
      'web fallback emits two real kinds and a friendly host-only failure',
      () async {
        final drafts = <SkillSourceDraft>[];
        final repository = FakeSkillAcquisitionRepository()
          ..inspectHandler = (draft) {
            drafts.add(draft);
            return _inspectionTask(
              WorkspaceFailed(
                failure: WorkspaceFailure(
                  code: drafts.length == 1
                      ? WorkspaceErrorCode.httpFailure
                      : WorkspaceErrorCode.gitFailed,
                  operation: WorkspaceOperationKind.inspectSource,
                  context: drafts.length == 1
                      ? const {'reason': 'unexpectedStatus', 'statusCode': 404}
                      : const {},
                ),
              ),
            );
          };
        final analytics = RecordingAppAnalytics();
        final container = _container(
          repository,
          inputMode: SkillSourceInputMode.smart,
          analytics: analytics,
        );
        addTearDown(container.dispose);
        final vm = container.read(skillAcquisitionViewModelProvider.notifier);
        vm.updateRawInput('https://example.com/blog/private?value=hidden#page');
        await vm.inspect();
        expect(drafts.map((draft) => draft.kind), [
          SkillSourceKind.wellKnown,
          SkillSourceKind.git,
        ]);
        expect(drafts.last.locator, drafts.first.locator);
        expect(vm.status, AcquisitionStatus.failure);
        final failure = vm.failure!;
        expect(failure.codeKey, 'webSourceHasNoSkills');
        expect(failure.context, {'locatorHost': 'example.com'});
        expect(failure.recoveryPolicy, AppRecoveryPolicy.none);
        expect(analytics.events.map((event) => event.action), [
          'source_inspection',
          'source_inspection',
        ]);
        expect(analytics.events.map((event) => event.sourceKind), [
          'well_known',
          'git',
        ]);
        expect(analytics.events.map((event) => event.errorCode), [
          'httpFailure',
          'webSourceHasNoSkills',
        ]);
        expect(
          localizeAppFailure(AppLocalizationsEn(), failure),
          AppLocalizationsEn().acquisitionErrorWebSourceHasNoSkillsBody,
        );
        expect(
          localizeAppFailure(AppLocalizationsZh(), failure),
          AppLocalizationsZh().acquisitionErrorWebSourceHasNoSkillsBody,
        );
      },
    );

    for (final firstCode in [
      WorkspaceErrorCode.invalidSkill,
      WorkspaceErrorCode.skillNotFound,
    ]) {
      test('$firstCode falls back and can succeed as Git', () async {
        final drafts = <SkillSourceDraft>[];
        final repository = FakeSkillAcquisitionRepository()
          ..inspectHandler = (draft) {
            drafts.add(draft);
            return _inspectionTask(
              drafts.length == 1
                  ? WorkspaceFailed(
                      failure: WorkspaceFailure(
                        code: firstCode,
                        operation: WorkspaceOperationKind.inspectSource,
                      ),
                    )
                  : WorkspaceCompleted(value: inspection),
            );
          };
        final container = _container(
          repository,
          inputMode: SkillSourceInputMode.smart,
        );
        addTearDown(container.dispose);
        final vm = container.read(skillAcquisitionViewModelProvider.notifier);
        vm.updateRawInput('https://example.com/skills');
        await vm.inspect();
        expect(drafts.length, 2);
        expect(vm.failure, isNull);
        expect(vm.inspection, same(inspection));
      });
    }

    for (final code in [
      WorkspaceErrorCode.sourceAuthenticationRequired,
      WorkspaceErrorCode.transportRejected,
    ]) {
      test(
        '$code from the Git fallback becomes the friendly failure',
        () async {
          var attempts = 0;
          final repository = FakeSkillAcquisitionRepository()
            ..inspectHandler = (_) => _inspectionTask(
              WorkspaceFailed(
                failure: WorkspaceFailure(
                  code: ++attempts == 1
                      ? WorkspaceErrorCode.invalidSkill
                      : code,
                  operation: WorkspaceOperationKind.inspectSource,
                ),
              ),
            );
          final container = _container(
            repository,
            inputMode: SkillSourceInputMode.smart,
          );
          addTearDown(container.dispose);
          final vm = container.read(skillAcquisitionViewModelProvider.notifier);
          vm.updateRawInput('https://example.com/skills');
          await vm.inspect();
          expect(attempts, 2);
          expect(vm.failure?.codeKey, 'webSourceHasNoSkills');
        },
      );
    }

    for (final (code, reason) in [
      (WorkspaceErrorCode.httpFailure, 'timeout'),
      (WorkspaceErrorCode.httpFailure, 'transportFailure'),
      (WorkspaceErrorCode.sourceUnavailable, 'destinationResolutionFailed'),
      (WorkspaceErrorCode.transportRejected, 'unsupportedTransport'),
    ]) {
      test('$code/$reason never triggers fallback', () async {
        var attempts = 0;
        final failure = WorkspaceFailure(
          code: code,
          operation: WorkspaceOperationKind.inspectSource,
          context: {'reason': reason},
        );
        final repository = FakeSkillAcquisitionRepository()
          ..inspectHandler = (_) {
            attempts++;
            return _inspectionTask(WorkspaceFailed(failure: failure));
          };
        final analytics = RecordingAppAnalytics();
        final container = _container(
          repository,
          inputMode: SkillSourceInputMode.smart,
          analytics: analytics,
        );
        addTearDown(container.dispose);
        final vm = container.read(skillAcquisitionViewModelProvider.notifier);
        vm.updateRawInput('https://example.com/skills');
        await vm.inspect();
        expect(attempts, 1);
        expect(vm.failure, same(failure));
        expect(analytics.events.length, 1);
      });
    }

    test('other Git fallback failures are surfaced unchanged', () async {
      var attempts = 0;
      final failure = WorkspaceFailure(
        code: WorkspaceErrorCode.sourceUnavailable,
        operation: WorkspaceOperationKind.inspectSource,
      );
      final repository = FakeSkillAcquisitionRepository()
        ..inspectHandler = (_) => _inspectionTask(
          WorkspaceFailed(
            failure: ++attempts == 1
                ? WorkspaceFailure(
                    code: WorkspaceErrorCode.invalidSkill,
                    operation: WorkspaceOperationKind.inspectSource,
                  )
                : failure,
          ),
        );
      final container = _container(
        repository,
        inputMode: SkillSourceInputMode.smart,
      );
      addTearDown(container.dispose);
      final vm = container.read(skillAcquisitionViewModelProvider.notifier);
      vm.updateRawInput('https://example.com/skills');
      await vm.inspect();
      expect(attempts, 2);
      expect(vm.failure, same(failure));
    });

    for (final cancelAttempt in [1, 2]) {
      test(
        'progress and cancellation follow inspection attempt $cancelAttempt',
        () async {
          final firstCompleted =
              Completer<WorkspaceCompletion<SkillSourceInspection>>();
          final secondCompleted =
              Completer<WorkspaceCompletion<SkillSourceInspection>>();
          final secondStarted = Completer<void>();
          final firstProgress = StreamController<AcquisitionProgress>.broadcast(
            sync: true,
          );
          final secondProgress =
              StreamController<AcquisitionProgress>.broadcast(sync: true);
          addTearDown(firstProgress.close);
          addTearDown(secondProgress.close);
          var attempts = 0;
          final cancelled = <int>[];
          final repository = FakeSkillAcquisitionRepository()
            ..inspectHandler = (_) {
              final attempt = ++attempts;
              if (attempt == 2) secondStarted.complete();
              final completed = attempt == 1 ? firstCompleted : secondCompleted;
              return AcquisitionTask(
                current: AcquisitionProgress(
                  phase: AcquisitionPhase.preparing,
                  currentItem: 'attempt-$attempt',
                ),
                states: attempt == 1
                    ? firstProgress.stream
                    : secondProgress.stream,
                completed: completed.future,
                cancel: () async {
                  cancelled.add(attempt);
                  completed.complete(
                    WorkspaceFailed(
                      failure: WorkspaceFailure(
                        code: WorkspaceErrorCode.operationCancelled,
                        operation: WorkspaceOperationKind.inspectSource,
                      ),
                    ),
                  );
                },
              );
            };
          final analytics = RecordingAppAnalytics();
          final container = _container(
            repository,
            inputMode: SkillSourceInputMode.smart,
            analytics: analytics,
          );
          addTearDown(container.dispose);
          final vm = container.read(skillAcquisitionViewModelProvider.notifier);
          vm.updateRawInput('https://example.com/skills');
          final pending = vm.inspect();
          expect(vm.progress?.currentItem, 'attempt-1');
          firstProgress.add(
            const AcquisitionProgress(
              phase: AcquisitionPhase.inspecting,
              completed: 1,
              total: 2,
            ),
          );
          expect(vm.progress?.completed, 1);
          if (cancelAttempt == 2) {
            final warning = WorkspaceWarning(
              code: WorkspaceWarningCode.sourceEntrySkipped,
            );
            firstCompleted.complete(
              WorkspaceFailed(
                failure: WorkspaceFailure(
                  code: WorkspaceErrorCode.invalidSkill,
                  operation: WorkspaceOperationKind.inspectSource,
                ),
                warnings: [warning],
              ),
            );
            await secondStarted.future;
            expect(vm.progress?.currentItem, 'attempt-2');
            expect(vm.warnings, contains(warning));
            firstProgress.add(
              const AcquisitionProgress(
                phase: AcquisitionPhase.inspecting,
                completed: 99,
              ),
            );
            secondProgress.add(
              const AcquisitionProgress(
                phase: AcquisitionPhase.inspecting,
                completed: 2,
                total: 3,
              ),
            );
            expect(vm.progress?.completed, 2);
          }
          await vm.cancel();
          await pending;
          expect(attempts, cancelAttempt);
          expect(cancelled, [cancelAttempt]);
          expect(vm.status, AcquisitionStatus.idle);
          expect(vm.progress, isNull);
          expect(vm.failure, isNull);
          expect(analytics.events.length, cancelAttempt);
          expect(analytics.events.last.name, 'cancelled');
        },
      );
    }

    test('typed web failures do not fall back', () async {
      var attempts = 0;
      final repository = FakeSkillAcquisitionRepository()
        ..inspectHandler = (_) {
          attempts++;
          return _inspectionTask(
            WorkspaceFailed(
              failure: WorkspaceFailure(
                code: WorkspaceErrorCode.invalidSkill,
                operation: WorkspaceOperationKind.inspectSource,
              ),
            ),
          );
        };
      final container = _container(repository);
      addTearDown(container.dispose);
      final vm = container.read(skillAcquisitionViewModelProvider.notifier);
      vm.selectSourceKind(SkillSourceKind.wellKnown);
      vm.updateLocator('https://example.com/skills');
      await vm.inspect();
      expect(attempts, 1);
      expect(vm.failure?.codeKey, 'invalidSkill');
    });

    for (final (flag, selected, unmatched, preselected) in [
      ('--skill aLpHa missing', {'alpha'}, ['missing'], {'alpha'}),
      ("--skill '*'", {'alpha', 'beta'}, <String>[], {'alpha', 'beta'}),
      ('--skill missing', {'alpha', 'beta'}, ['missing'], <String>{}),
      ('', {'alpha', 'beta'}, <String>[], <String>{}),
    ]) {
      test(
        '$flag selects matches or defaults and reports unmatched names',
        () async {
          final repository = FakeSkillAcquisitionRepository()
            ..inspection = inspection;
          final container = _container(
            repository,
            inputMode: SkillSourceInputMode.smart,
          );
          addTearDown(container.dispose);
          final vm = container.read(skillAcquisitionViewModelProvider.notifier);
          vm.updateRawInput('npx skills add owner/repo $flag');
          await vm.inspect();
          final state = container.read(skillAcquisitionViewModelProvider);
          expect(state.selectedSlots, selected);
          expect(state.preselectedSlots, preselected);
          expect(state.unmatchedSkillNames, unmatched);
        },
      );
    }

    test(
      'matches declared names and slot keys, excluding installed matches',
      () async {
        final repository = FakeSkillAcquisitionRepository()
          ..inspection = SkillSourceInspection(
            source: source,
            candidates: [
              const SkillCandidate(
                slotKey: 'alpha',
                declaredName: 'Long Alpha',
                description: '',
                skillPath: 'alpha',
              ),
              inspection.candidates.last,
            ],
          );
        final workspace = FakeSkillsWorkspaceRepository(
          snapshot: driftWidgetSnapshot(
            integrity: WorkspaceSkillIntegrityStatus.healthy,
          ),
        );
        final container = _container(
          repository,
          inputMode: SkillSourceInputMode.smart,
          workspace: workspace,
        );
        addTearDown(container.dispose);
        await container.read(workspaceSnapshotProvider.future);
        final vm = container.read(skillAcquisitionViewModelProvider.notifier);
        vm.updateRawInput(
          'npx skills add owner/repo --skill "LONG ALPHA" ALPHA',
        );
        await vm.inspect();
        final state = container.read(skillAcquisitionViewModelProvider);
        expect(state.selectedSlots, isEmpty);
        expect(state.preselectedSlots, isEmpty);
        expect(state.unmatchedSkillNames, isEmpty);
      },
    );

    test('back keeps the smart result and edits invalidate it', () async {
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection;
      final container = _container(
        repository,
        inputMode: SkillSourceInputMode.smart,
      );
      addTearDown(container.dispose);
      final vm = container.read(skillAcquisitionViewModelProvider.notifier);
      vm.continueFromSmartResult();
      expect(
        container.read(skillAcquisitionViewModelProvider).step,
        AcquisitionStep.source,
      );
      vm.updateRawInput('npx skills add owner/repo --skill Alpha');
      await vm.inspect();
      vm.continueFromSmartResult();
      vm.toggleSkill('beta', true);
      vm.toggleSkill('alpha', false);
      vm.back();
      var state = container.read(skillAcquisitionViewModelProvider);
      expect(state.inspection, same(inspection));
      expect(state.smartInspected, isTrue);
      expect(state.status, AcquisitionStatus.ready);
      expect(state.selectedSlots, {'beta'});
      expect(state.preselectedSlots, isEmpty);
      vm.updateSourceRef('release');
      state = container.read(skillAcquisitionViewModelProvider);
      expect(state.smartInspected, isFalse);
      expect(state.inspection, isNull);
      expect(state.preselectedSlots, isEmpty);
    });

    test('advanced fields merge when parsing leaves them empty', () async {
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection;
      final container = _container(
        repository,
        inputMode: SkillSourceInputMode.smart,
      );
      addTearDown(container.dispose);
      final vm = container.read(skillAcquisitionViewModelProvider.notifier);
      vm.updateRawInput('github.com/owner/repo/tree/main/skills');
      expect(
        container.read(skillAcquisitionViewModelProvider).advancedExpanded,
        isTrue,
      );
      vm.updateSourceRef('custom');
      vm.updateRepositorySubpath('custom/path');
      vm.updateRawInput('owner/other');
      await vm.inspect();
      expect(repository.inspectedDraft?.sourceRef, 'custom');
      expect(repository.inspectedDraft?.repositorySubpath, 'custom/path');
      vm.toggleAdvanced();
      expect(
        container.read(skillAcquisitionViewModelProvider).advancedExpanded,
        isFalse,
      );
      vm.updateRawInput(' ');
      final state = container.read(skillAcquisitionViewModelProvider);
      expect(state.parsed, isNull);
      expect(state.detection, SkillSourceDetection.empty);
      expect(state.requestedSkillNames, isEmpty);
      expect(state.smartInspected, isFalse);
      expect(state.failure, isNull);
      expect(vm.canInspect, isFalse);
    });

    test('-g overrides a project scope before loading targets', () async {
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection;
      final container = _container(
        repository,
        inputMode: SkillSourceInputMode.smart,
      );
      addTearDown(container.dispose);
      final vm = container.read(skillAcquisitionViewModelProvider.notifier);
      await vm.selectScope(SkillActivationScope.project, const []);
      vm.updateRawInput('npx skills add owner/repo -g');
      await vm.inspect();
      vm.continueFromSmartResult();
      await vm.continueToActivation(const []);
      expect(
        container.read(skillAcquisitionViewModelProvider).scope,
        SkillActivationScope.global,
      );
      expect(
        repository.targetInspections.last.scope,
        SkillActivationScope.global,
      );
    });

    for (final (ids, expected, unknown) in [
      ('codex unknown', {'codex'}, ['unknown']),
      ('unknown', {'codex', 'claude-code'}, ['unknown']),
      ("'*'", {'codex', 'claude-code'}, <String>[]),
    ]) {
      test(
        '-a $ids prefills locations once and preserves user toggles',
        () async {
          final repository = FakeSkillAcquisitionRepository(
            agents: const [
              AgentOption(
                id: 'codex',
                displayName: 'Codex',
                location: '/global/codex',
              ),
              AgentOption(
                id: 'claude-code',
                displayName: 'Claude',
                location: '/global/claude',
              ),
            ],
          )..inspection = inspection;
          final container = _container(
            repository,
            inputMode: SkillSourceInputMode.smart,
          );
          addTearDown(container.dispose);
          final vm = container.read(skillAcquisitionViewModelProvider.notifier);
          vm.updateRawInput('npx skills add owner/repo -a $ids');
          await vm.inspect();
          vm.continueFromSmartResult();
          await vm.continueToActivation(const []);
          var state = container.read(skillAcquisitionViewModelProvider);
          expect(state.selectedAgentIds, expected);
          expect(state.unknownAgentIds, unknown);
          final claude = state.locationGroups.firstWhere(
            (group) => group.requestAgentIds.contains('claude-code'),
          );
          vm.toggleLocation(claude.key, !expected.contains('claude-code'));
          final afterToggle = container
              .read(skillAcquisitionViewModelProvider)
              .selectedLocations;
          await vm.loadTargets(scope: state.scope);
          state = container.read(skillAcquisitionViewModelProvider);
          expect(state.selectedLocations, afterToggle);
          expect(state.unknownAgentIds, unknown);
        },
      );
    }

    test('typed commands harvest flags while ordinary locators retain raw text', () async {
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection;
      final container = _container(repository);
      addTearDown(container.dispose);
      final vm = container.read(skillAcquisitionViewModelProvider.notifier);
      vm.selectSourceKind(SkillSourceKind.git);
      vm.updateLocator('  github.com/owner/repo  ');
      expect(
        container.read(skillAcquisitionViewModelProvider).sourceDraft.locator,
        '  github.com/owner/repo  ',
      );
      vm.updateLocator(
        'npx skills add github.com/owner/repo --skill Beta -a codex -g --copy',
      );
      var state = container.read(skillAcquisitionViewModelProvider);
      expect(state.sourceDraft.locator, 'https://github.com/owner/repo');
      expect(state.requestedSkillNames, {'Beta'});
      expect(state.requestedAgentIds, ['codex']);
      expect(state.requestGlobalScope, isTrue);
      expect(state.ignoredFlags, ['--copy']);
      await vm.inspect();
      state = container.read(skillAcquisitionViewModelProvider);
      expect(state.step, AcquisitionStep.skills);
      expect(state.smartInspected, isFalse);
      expect(state.selectedSlots, {'beta'});
    });

    test('mode switch carries drafts both ways, saves preference, and reset reads it', () async {
      final store = SkillSourceInputModeStore(
        preferences: SharedPreferencesAsync(),
      );
      final repository = FakeSkillAcquisitionRepository()
        ..inspection = inspection;
      final container = _container(
        repository,
        inputMode: SkillSourceInputMode.smart,
        inputModeStore: store,
      );
      addTearDown(container.dispose);
      final vm = container.read(skillAcquisitionViewModelProvider.notifier);
      vm.updateRawInput('github.com/owner/repo/tree/main/skills');
      await vm.inspect();
      vm.selectInputMode(SkillSourceInputMode.typed);
      var state = container.read(skillAcquisitionViewModelProvider);
      expect(state.inputMode, SkillSourceInputMode.typed);
      expect(state.sourceKindChosen, isTrue);
      expect(state.sourceDraft.kind, SkillSourceKind.git);
      expect(state.sourceDraft.locator, 'https://github.com/owner/repo');
      expect(state.sourceDraft.sourceRef, 'main');
      expect(state.sourceDraft.repositorySubpath, 'skills');
      expect(state.inspection, isNull);
      expect(state.smartInspected, isFalse);
      await pumpEventQueue();
      expect(await store.read(), SkillSourceInputMode.typed);
      vm.reset();
      state = container.read(skillAcquisitionViewModelProvider);
      expect(state.inputMode, SkillSourceInputMode.typed);
      expect(state.rawInput, isEmpty);
      expect(state.parsed, isNull);
      expect(state.sourceKindChosen, isFalse);
      vm.updateLocator('owner/new');
      vm.updateSourceRef('release');
      vm.selectInputMode(SkillSourceInputMode.smart);
      state = container.read(skillAcquisitionViewModelProvider);
      expect(state.rawInput, 'owner/new');
      expect(state.sourceDraft.locator, 'owner/new');
      expect(state.sourceDraft.sourceRef, 'release');
      expect(state.detection, SkillSourceDetection.gitShorthand);
      vm.selectInputMode(SkillSourceInputMode.smart);
      await pumpEventQueue();
      expect(await store.read(), SkillSourceInputMode.smart);
      vm.reset();
      state = container.read(skillAcquisitionViewModelProvider);
      expect(state.inputMode, SkillSourceInputMode.smart);
      expect(state.rawInput, isEmpty);
      expect(state.requestedSkillNames, isEmpty);
      expect(state.advancedExpanded, isFalse);
    });

    test(
      'initial state reads the provider and blank smart input does not inspect',
      () async {
        final repository = FakeSkillAcquisitionRepository()
          ..inspection = inspection;
        final container = ProviderContainer(
          overrides: [
            skillAcquisitionRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        final vm = container.read(skillAcquisitionViewModelProvider.notifier);
        expect(
          container.read(skillAcquisitionViewModelProvider).inputMode,
          SkillSourceInputMode.smart,
        );
        vm.updateRawInput('   ');
        await vm.inspect();
        expect(repository.inspectedDraft, isNull);
        expect(vm.canInspect, isFalse);
      },
    );
  });

  group('input mode preference', () {
    test('defaults, invalid values, and persisted choice', () async {
      final preferences = SharedPreferencesAsync();
      final store = SkillSourceInputModeStore(preferences: preferences);
      expect(await store.read(), SkillSourceInputMode.smart);
      await preferences.setString(
        SkillSourceInputModeStore.preferenceKey,
        'unknown',
      );
      expect(await store.read(), SkillSourceInputMode.smart);
      await store.write(SkillSourceInputMode.typed);
      expect(await store.read(), SkillSourceInputMode.typed);
    });

    test('storage errors keep the session choice usable', () async {
      final store = SkillSourceInputModeStore(
        preferences: _FailingInputModePreferences(),
      );
      expect(await store.read(), SkillSourceInputMode.smart);
      final container = ProviderContainer(
        overrides: [skillSourceInputModeStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      container
          .read(skillSourceInputModeProvider.notifier)
          .select(SkillSourceInputMode.typed);
      await pumpEventQueue();
      expect(
        container.read(skillSourceInputModeProvider),
        SkillSourceInputMode.typed,
      );
    });

    test('rapid selections serialize writes so the last choice wins', () async {
      final preferences = _DelayedInputModePreferences();
      final store = SkillSourceInputModeStore(preferences: preferences);
      final container = ProviderContainer(
        overrides: [skillSourceInputModeStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final controller = container.read(skillSourceInputModeProvider.notifier);
      controller.select(SkillSourceInputMode.typed);
      controller.select(SkillSourceInputMode.smart);
      await pumpEventQueue();
      expect(preferences.writes, ['typed']);
      preferences.firstWrite.complete();
      await pumpEventQueue();
      expect(preferences.writes, ['typed', 'smart']);
      expect(await store.read(), SkillSourceInputMode.smart);
    });
  });
}

ProviderContainer _container(
  FakeSkillAcquisitionRepository acquisition, {
  FakeSkillsWorkspaceRepository? workspace,
  // Existing cases exercise the original typed form contract.
  SkillSourceInputMode inputMode = SkillSourceInputMode.typed,
  SkillSourceInputModeStore? inputModeStore,
  AppAnalytics analytics = const NoopAppAnalytics(),
  WorkspaceActivationMethod activationMethod =
      WorkspaceActivationMethod.automatic,
}) {
  return ProviderContainer(
    overrides: [
      initialSkillSourceInputModeProvider.overrideWithValue(inputMode),
      if (inputModeStore != null)
        skillSourceInputModeStoreProvider.overrideWithValue(inputModeStore),
      appAnalyticsProvider.overrideWithValue(analytics),
      globalActivationMethodProvider.overrideWithValue(activationMethod),
      skillAcquisitionRepositoryProvider.overrideWithValue(acquisition),
      deviceAgentMembersProvider.overrideWithValue(
        AsyncData({
          for (final agent in acquisition.agents)
            if (agent.detected) agent.id,
        }),
      ),
      if (workspace != null)
        skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
    ],
  );
}

AcquisitionTask<SkillSourceInspection> _inspectionTask(
  WorkspaceCompletion<SkillSourceInspection> completion,
) => AcquisitionTask(
  current: const AcquisitionProgress(phase: AcquisitionPhase.inspecting),
  states: const Stream.empty(),
  completed: Future.value(completion),
  cancel: () async {},
);

final class _FailingInputModePreferences extends SharedPreferencesAsync {
  @override
  Future<String?> getString(String key) async =>
      throw StateError('read failed');

  @override
  Future<void> setString(String key, String value) async =>
      throw StateError('write failed');
}

final class _DelayedInputModePreferences extends SharedPreferencesAsync {
  final firstWrite = Completer<void>();
  final writes = <String>[];

  @override
  Future<void> setString(String key, String value) async {
    writes.add(value);
    if (writes.length == 1) await firstWrite.future;
    await super.setString(key, value);
  }
}
