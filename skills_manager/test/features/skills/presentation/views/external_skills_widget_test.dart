import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/platform/file_location_opener.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

import '../../../../support/fake_skill_acquisition_repository.dart';
import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  testWidgets('shows scanning and then an empty discovery', (tester) async {
    final completer = Completer<WorkspaceCompletion<ExternalSkillsDiscovery>>();
    final workspace = FakeSkillsWorkspaceRepository()
      ..discoverExternalSkillsTask = WorkspaceTask(
        current: _progress(WorkspaceOperationPhase.inspecting),
        states: const Stream.empty(),
        completed: completer.future,
        cancel: () async {},
      );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        initialLocation: '/installed/discover',
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('external-skills-scanning')), findsOneWidget);

    completer.complete(
      WorkspaceCompleted(value: ExternalSkillsDiscovery.empty()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('external-skills-empty')), findsOneWidget);
  });

  testWidgets('reviews at a glance, picks a version, and takes over without a '
      'confirmation page', (tester) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _candidateAndConflict(),
    );
    await _pumpDialog(tester, workspace);

    expect(find.byKey(const Key('external-skills-ready')), findsOneWidget);
    expect(find.text('Found 2 existing Skills'), findsOneWidget);
    expect(find.byKey(const Key('external-conflict-beta')), findsOneWidget);
    expect(find.text('2 copies differ'), findsOneWidget);
    expect(find.text('1 more can be taken over directly'), findsOneWidget);
    // Copies are named by Agent; paths stay out of the review.
    expect(find.textContaining('/agents/'), findsNothing);
    // Until beta has a version, only alpha would be taken over.
    expect(find.text('Take over 1'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('external-version-beta')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('external-version-beta')));
    await tester.pumpAndSettle();
    expect(find.text('Keep the version from'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('external-authority-beta-/agents/b/beta')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Take over all 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('external-skills-adopt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('external-skills-success')), findsOneWidget);
    expect(workspace.adoptionRequests.map((request) => request.slotKey), [
      'alpha',
      'beta',
    ]);
    expect(
      workspace.adoptionRequests.last.authoritativeLocation,
      '/agents/b/beta',
    );
  });

  testWidgets('a rescan keeps the review usable and only holds take over', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _candidateAndConflict(),
    );
    await _pumpDialog(tester, workspace);
    final completer = Completer<WorkspaceCompletion<ExternalSkillsDiscovery>>();
    workspace.discoverExternalSkillsTask = WorkspaceTask(
      current: _progress(WorkspaceOperationPhase.inspecting),
      states: const Stream.empty(),
      completed: completer.future,
      cancel: () async {},
    );

    await tester.tap(find.byKey(const Key('external-skills-rescan')));
    await tester.pump();
    expect(
      find.byKey(const Key('external-skills-scanning-indicator')),
      findsOneWidget,
    );
    expect(find.text('Checking for changes…'), findsOneWidget);

    // The scan spinner never settles, so step frames through the menu's
    // open and close instead of settling.
    Future<void> frames() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.ensureVisible(find.byKey(const Key('external-version-beta')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('external-version-beta')));
    await frames();
    await tester.tap(
      find.byKey(const Key('external-authority-beta-/agents/b/beta')),
    );
    await frames();

    completer.complete(WorkspaceCompleted(value: _candidateAndConflict()));
    await tester.pumpAndSettle();
    expect(find.text('Take over all 2'), findsOneWidget);
  });

  testWidgets('choosing individually can leave a Skill out', (tester) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _twoCandidates(),
    );
    await _pumpDialog(tester, workspace);

    await tester.tap(find.byKey(const Key('external-skills-choose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('external-skills-list')), findsOneWidget);
    expect(find.byKey(const Key('external-candidate-zeta')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('external-select-zeta')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('external-select-zeta')));
    await tester.pumpAndSettle();
    expect(find.text('Take over 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('external-skills-adopt')));
    await tester.pumpAndSettle();
    expect(workspace.adoptionRequests.map((request) => request.slotKey), [
      'alpha',
    ]);
  });

  testWidgets('the version menu reveals a copy without choosing it', (
    tester,
  ) async {
    final opener = _RecordingOpener();
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _candidateAndConflict(),
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        initialLocation: '/installed/discover',
        fileLocationOpener: opener,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('external-version-beta')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('external-version-beta')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('external-open-beta-/agents/a/beta')),
    );
    await tester.pumpAndSettle();

    expect(opener.revealed, [p.join('/agents/a/beta', 'SKILL.md')]);
    // Revealing a folder does not pick that copy: beta still has no version.
    expect(find.text('Take over 1'), findsOneWidget);
  });

  testWidgets('shows a typed adoption failure', (tester) async {
    final workspace =
        FakeSkillsWorkspaceRepository(externalSkillsDiscovery: _oneCandidate())
          ..adoptError = WorkspaceException(
            code: WorkspaceErrorCode.externalConflict,
            operation: WorkspaceOperationKind.adopt,
          );
    await _pumpDialog(tester, workspace);

    await tester.tap(find.byKey(const Key('external-skills-adopt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('external-skills-failure')), findsOneWidget);
    expect(
      find.text(
        'An unmanaged skill already occupies this activation target. '
        'Refresh and review it before continuing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('lists every blocked Agent folder and offers to check again', (
    tester,
  ) async {
    final workspace =
        FakeSkillsWorkspaceRepository(externalSkillsDiscovery: _oneCandidate())
          ..adoptError = WorkspaceException(
            code: WorkspaceErrorCode.agentRootOwnership,
            operation: WorkspaceOperationKind.adopt,
            context: const {
              'reason': 'agentRootOwnershipBlocked',
              'issueReason': 'inspectionFailed',
              'rootPath': '/Users/me/.legacy/skills',
              'issueCount': 2,
              'issues': [
                {
                  'issueReason': 'inspectionFailed',
                  'rootPath': '/Users/me/.legacy/skills',
                },
                {
                  'issueReason': 'notDirectory',
                  'rootPath': '/Users/me/.agent/skills',
                },
              ],
            },
          );
    await _pumpDialog(tester, workspace);

    await tester.tap(find.byKey(const Key('external-skills-adopt')));
    await tester.pumpAndSettle();

    final failure = find.byKey(const Key('external-skills-failure'));
    expect(failure, findsOneWidget);
    expect(
      find.descendant(
        of: failure,
        matching: find.textContaining('/Users/me/.legacy/skills'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: failure,
        matching: find.textContaining('/Users/me/.agent/skills'),
      ),
      findsOneWidget,
    );
    // Retrying cannot clear a folder the user has to fix, so neither button
    // offers it.
    expect(find.text('Retry'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('external-skills-retry')),
        matching: find.text('Refresh and review'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('labels a failed rescan as discovery failure', (tester) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _oneCandidate(),
    );
    await _pumpDialog(tester, workspace);
    workspace.discoverExternalSkillsError = WorkspaceException(
      code: WorkspaceErrorCode.ioFailure,
      operation: WorkspaceOperationKind.discoverExternalSkills,
    );

    await tester.tap(find.byKey(const Key('external-skills-rescan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('external-skills-failure')), findsOneWidget);
    expect(find.text('Scan failed'), findsOneWidget);
    expect(find.text('Adoption failed'), findsNothing);
  });

  testWidgets('shows cancellation without an error state', (tester) async {
    final workspace =
        FakeSkillsWorkspaceRepository(externalSkillsDiscovery: _oneCandidate())
          ..adoptError = WorkspaceException(
            code: WorkspaceErrorCode.operationCancelled,
            operation: WorkspaceOperationKind.adopt,
          );
    await _pumpDialog(tester, workspace);

    await tester.tap(find.byKey(const Key('external-skills-adopt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('external-skills-cancelled')), findsOneWidget);
    expect(find.byKey(const Key('external-skills-failure')), findsNothing);
  });

  for (final (locale, title, failedTitle, reason) in [
    (
      const Locale('en'),
      'Adoption partially completed',
      '1 Skill could not be taken over',
      "Something else is already in this Skill's folder. Move it away, then "
          'try again.',
    ),
    (
      const Locale('zh'),
      '部分 Skills 已完成接管',
      '1 个 Skill 未能接管',
      '此 Skill 的目标文件夹已被其他内容占用，请移走后重试。',
    ),
  ]) {
    testWidgets('names the Skill that failed when others were taken over '
        '(${locale.languageCode})', (tester) async {
      final workspace = FakeSkillsWorkspaceRepository(
        externalSkillsDiscovery: _twoCandidates(),
      );
      workspace.adoptTaskBuilder = (request) {
        if (request.slotKey == 'alpha') {
          return failedWorkspaceTask(
            kind: WorkspaceOperationKind.adopt,
            error: WorkspaceException(
              code: WorkspaceErrorCode.activationUnavailable,
              operation: WorkspaceOperationKind.adopt,
              context: const {'reason': 'adoptionTargetOccupied'},
            ),
          );
        }
        return completedWorkspaceTask(
          kind: WorkspaceOperationKind.adopt,
          value: WorkspaceMutationReceipt(
            snapshot: workspace.current,
            affectedSkillIds: const {},
          ),
        );
      };
      await _pumpDialog(tester, workspace, locale: locale);

      await tester.tap(find.byKey(const Key('external-skills-adopt')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('external-skills-partial')), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(find.text(failedTitle), findsOneWidget);
      final row = find.byKey(const Key('external-skills-failed-alpha'));
      expect(
        find.descendant(of: row, matching: find.text('Alpha')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(reason)),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('external-skills-failed-zeta')),
        findsNothing,
      );
    });
  }

  testWidgets('lists every Skill when none could be taken over', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _twoCandidates(),
    );
    workspace.adoptTaskBuilder = (request) => failedWorkspaceTask(
      kind: WorkspaceOperationKind.adopt,
      error: WorkspaceException(
        code: WorkspaceErrorCode.ioFailure,
        operation: WorkspaceOperationKind.adopt,
      ),
    );
    await _pumpDialog(tester, workspace);

    await tester.tap(find.byKey(const Key('external-skills-adopt')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('external-skills-failure')), findsOneWidget);
    expect(find.text('Adoption failed'), findsOneWidget);
    expect(find.text('2 Skills could not be taken over'), findsOneWidget);
    expect(
      find.byKey(const Key('external-skills-failed-alpha')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('external-skills-failed-zeta')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('external-skills-retry')), findsOneWidget);
  });

  testWidgets('Installed disables the merged action while scanning', (
    tester,
  ) async {
    final completer = Completer<WorkspaceCompletion<ExternalSkillsDiscovery>>();
    final workspace = FakeSkillsWorkspaceRepository()
      ..discoverExternalSkillsTask = WorkspaceTask(
        current: _progress(WorkspaceOperationPhase.inspecting),
        states: const Stream.empty(),
        completed: completer.future,
        cancel: () async {},
      );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [testSkill(slotKey: 'installed', displayName: 'Installed')],
      ),
      documents: {'installed': '# Installed'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
      ),
    );
    await tester.pump();

    final action = tester.widget<AppIconButton>(
      find.byKey(const Key('installed-refresh-scan-action')),
    );
    expect(action.icon, LucideIcons.scanSearch);
    expect(action.onPressed, isNull);

    await tester.tap(find.byKey(const Key('installed-refresh-scan-action')));
    await tester.pump();
    expect(browser.refreshCalls, 0);
    expect(workspace.discoverExternalSkillsCalls, 1);

    completer.complete(
      WorkspaceCompleted(value: ExternalSkillsDiscovery.empty()),
    );
    await tester.pumpAndSettle();

    final settledAction = tester.widget<AppIconButton>(
      find.byKey(const Key('installed-refresh-scan-action')),
    );
    expect(settledAction.icon, LucideIcons.refreshCw);
    expect(settledAction.onPressed, isNotNull);
  });

  testWidgets('merged action stays disabled through refresh and scan', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: ExternalSkillsDiscovery.empty(),
    );
    final skill = testSkill(slotKey: 'installed', displayName: 'Installed');
    final refreshCompleter = Completer<InstalledSkillCatalog>();
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
      documents: {'installed': '# Installed'},
    )..refreshHandler = () => refreshCompleter.future;

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
      ),
    );
    await tester.pumpAndSettle();

    final scanCompleter =
        Completer<WorkspaceCompletion<ExternalSkillsDiscovery>>();
    workspace.discoverExternalSkillsTask = WorkspaceTask(
      current: _progress(WorkspaceOperationPhase.inspecting),
      states: const Stream.empty(),
      completed: scanCompleter.future,
      cancel: () async {},
    );
    await tester.tap(find.byKey(const Key('installed-refresh-scan-action')));
    await tester.pump();

    var action = tester.widget<AppIconButton>(
      find.byKey(const Key('installed-refresh-scan-action')),
    );
    expect(action.icon, LucideIcons.scanSearch);
    expect(action.onPressed, isNull);
    expect(workspace.discoverExternalSkillsCalls, 1);

    refreshCompleter.complete(
      InstalledSkillCatalog(revision: 2, skills: [skill]),
    );
    await tester.pump();
    await tester.pump();

    action = tester.widget<AppIconButton>(
      find.byKey(const Key('installed-refresh-scan-action')),
    );
    expect(action.icon, LucideIcons.scanSearch);
    expect(action.onPressed, isNull);
    expect(workspace.discoverExternalSkillsCalls, 2);

    scanCompleter.complete(
      WorkspaceCompleted(value: ExternalSkillsDiscovery.empty()),
    );
    await tester.pumpAndSettle();

    action = tester.widget<AppIconButton>(
      find.byKey(const Key('installed-refresh-scan-action')),
    );
    expect(action.icon, LucideIcons.refreshCw);
    expect(action.onPressed, isNotNull);
  });

  testWidgets('Installed exposes unmanaged Skills in the merged action', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _oneCandidate(),
    );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [testSkill(slotKey: 'installed', displayName: 'Installed')],
      ),
      documents: {'installed': '# Installed'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
        acquisitionRepository: FakeSkillAcquisitionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final action = tester.widget<AppButton>(
      find.byKey(const Key('installed-refresh-scan-action')),
    );
    expect(action.icon, LucideIcons.scanSearch);
    expect(action.label, '1 unmanaged Skills found');
    expect(action.style, NeoButtonVariant.secondary);
    expect(action.height, AppSizes.pageCommandBarHeight);
    final actionSize = tester.getSize(
      find.byKey(const Key('installed-refresh-scan-action')),
    );
    expect(actionSize.height, AppSizes.pageCommandBarHeight);
    expect(actionSize.width, greaterThan(40));
    expect(actionSize.width, lessThanOrEqualTo(260));

    await tester.tap(find.byKey(const Key('installed-refresh-scan-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('external-skills-dialog')), findsOneWidget);
    expect(find.byKey(const Key('external-skills-ready')), findsOneWidget);
    // Opening the review rescans instead of reusing the launch scan.
    expect(workspace.discoverExternalSkillsCalls, 2);
  });

  testWidgets('unmanaged action fits a narrow command bar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _oneCandidate(),
    );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [testSkill(slotKey: 'installed', displayName: 'Installed')],
      ),
      documents: {'installed': '# Installed'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
        acquisitionRepository: FakeSkillAcquisitionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final semanticsFinder = find.semantics.byLabel('1 unmanaged Skills found');
    expect(semanticsFinder, findsOneWidget);
    expect(
      semanticsFinder.evaluate().single.getSemanticsData().hasAction(
        SemanticsAction.tap,
      ),
      isTrue,
    );
    expect(
      tester
          .getTopRight(find.byKey(const Key('installed-refresh-scan-action')))
          .dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('add-skills'))).dx),
    );
    expect(
      tester.getTopRight(find.byKey(const Key('add-skills'))).dx,
      lessThanOrEqualTo(
        tester.getTopRight(find.byKey(const Key('installed-header-column'))).dx,
      ),
    );

    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('1 unmanaged Skills found'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('external-skills-dialog')), findsOneWidget);
  });

  testWidgets('Installed falls back to refresh after a failed rescan', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _oneCandidate(),
    );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [testSkill(slotKey: 'installed', displayName: 'Installed')],
      ),
      documents: {'installed': '# Installed'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 unmanaged Skills found'), findsOneWidget);

    workspace.discoverExternalSkillsError = WorkspaceException(
      code: WorkspaceErrorCode.ioFailure,
      operation: WorkspaceOperationKind.discoverExternalSkills,
    );
    // Opening the review rescans, and that rescan fails.
    await tester.tap(find.byKey(const Key('installed-refresh-scan-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('external-skills-failure')), findsOneWidget);
    await tester.tap(find.byKey(const Key('external-skills-close')));
    await tester.pumpAndSettle();

    expect(find.text('1 unmanaged Skills found'), findsNothing);
    final action = tester.widget<AppIconButton>(
      find.byKey(const Key('installed-refresh-scan-action')),
    );
    expect(action.icon, LucideIcons.refreshCw);
    expect(action.onPressed, isNotNull);
  });

  testWidgets('empty Installed state exposes both acquisition paths', (
    tester,
  ) async {
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: FakeSkillAcquisitionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empty-add-skills')), findsOneWidget);
    expect(find.byKey(const Key('empty-discover-skills')), findsOneWidget);
  });

  testWidgets('empty Installed state leads with existing Skills when found', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _oneCandidate(),
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        acquisitionRepository: FakeSkillAcquisitionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('browser-empty-description')))
          .data,
      'Found 1 skill already in your Agent folders. '
      'Take them over without reinstalling.',
    );
    final takeOver = tester.widget<AppButton>(
      find.byKey(const Key('empty-discover-skills')),
    );
    expect(takeOver.style, NeoButtonVariant.primary);
    expect(
      tester.widget<AppButton>(find.byKey(const Key('empty-add-skills'))).style,
      isNot(NeoButtonVariant.primary),
    );

    await tester.tap(find.byKey(const Key('empty-discover-skills')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('external-skills-ready')), findsOneWidget);
    // Opening the review always rescans, so it never adopts from a scan
    // taken at launch.
    expect(workspace.discoverExternalSkillsCalls, 2);
  });

  testWidgets('startup and refresh scan without lifecycle rescans', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: ExternalSkillsDiscovery.empty(),
    );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [testSkill(slotKey: 'installed', displayName: 'Installed')],
      ),
      documents: {'installed': '# Installed'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.discoverExternalSkillsCalls, 1);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(workspace.discoverExternalSkillsCalls, 1);

    await tester.tap(find.byKey(const Key('installed-refresh-scan-action')));
    await tester.pumpAndSettle();
    expect(workspace.discoverExternalSkillsCalls, 2);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(workspace.discoverExternalSkillsCalls, 2);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester,
  FakeSkillsWorkspaceRepository workspace, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    skillsManagerTestApp(
      browserRepository: FakeSkillBrowserRepository(),
      workspaceRepository: workspace,
      initialLocation: '/installed/discover',
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
}

ExternalSkillsDiscovery _candidateAndConflict() => ExternalSkillsDiscovery(
  candidates: [
    ExternalSkillCandidate(
      slotKey: 'alpha',
      declaredName: 'Alpha',
      description: 'Alpha description',
      contentHash: 'hash-alpha',
      locations: const ['/agents/a/alpha', '/agents/z/alpha'],
      agentIds: const ['agent-a', 'agent-z'],
      destinationLocations: const ['/canonical/alpha'],
    ),
  ],
  conflicts: [
    ExternalSkillConflict(
      slotKey: 'beta',
      contentHashByLocation: const {
        '/agents/a/beta': 'hash-a',
        '/agents/b/beta': 'hash-b',
      },
      destinationLocations: const ['/canonical/beta'],
      agentIdsByLocation: const {
        '/agents/a/beta': ['agent-a'],
        '/agents/b/beta': ['agent-b'],
      },
    ),
  ],
);

ExternalSkillsDiscovery _oneCandidate() => ExternalSkillsDiscovery(
  candidates: [
    ExternalSkillCandidate(
      slotKey: 'alpha',
      declaredName: 'Alpha',
      description: '',
      contentHash: 'hash-alpha',
      locations: const ['/agents/alpha'],
      agentIds: const ['agent'],
      destinationLocations: const ['/canonical/alpha'],
    ),
  ],
  conflicts: const [],
);

ExternalSkillsDiscovery _twoCandidates() => ExternalSkillsDiscovery(
  candidates: [
    ..._oneCandidate().candidates,
    ExternalSkillCandidate(
      slotKey: 'zeta',
      declaredName: 'Zeta',
      description: '',
      contentHash: 'hash-zeta',
      locations: const ['/agents/zeta'],
      agentIds: const ['agent'],
      destinationLocations: const ['/canonical/zeta'],
    ),
  ],
  conflicts: const [],
);

WorkspaceOperationProgress _progress(WorkspaceOperationPhase phase) =>
    WorkspaceOperationProgress(
      operationId: 'external-scan',
      kind: WorkspaceOperationKind.discoverExternalSkills,
      phase: phase,
    );

final class _RecordingOpener implements FileLocationOpener {
  final revealed = <String>[];

  @override
  Future<bool> reveal(String path) async {
    revealed.add(path);
    return true;
  }
}
