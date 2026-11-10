import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  testWidgets('entering a detail page never starts a check of its own', (
    tester,
  ) async {
    final workspace = _workspace();

    await tester.pumpWidget(_app(workspace));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('check-skill-update')), findsOneWidget);
    expect(find.byKey(const Key('update-skill-now')), findsNothing);
    // Collapsed it is the same circle as the icon buttons beside it, so the
    // row reads as one set of controls rather than one odd one out.
    expect(
      tester.getSize(find.byKey(const Key('check-skill-update'))),
      const Size(AppSizes.buttonHeight, AppSizes.buttonHeight),
    );
    // The startup sweep is TTL-suppressed here, and the page itself checks
    // nothing: the last known result is all it renders.
    expect(workspace.checkUpdatesCalls, 0);
  });

  testWidgets('the action keeps its check form until an update is known', (
    tester,
  ) async {
    final workspace = _workspace()
      ..updateReports = [
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('alpha'),
          status: WorkspaceUpdateStatus.sourceUnavailable,
        ),
      ];

    await tester.pumpWidget(_app(workspace));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('check-skill-update')));
    await tester.pumpAndSettle();

    expect(workspace.checkUpdatesCalls, 1);
    // sourceUnavailable is not an available update, so the action must not
    // turn into something the user could mistake for one.
    expect(find.byKey(const Key('check-skill-update')), findsOneWidget);
    expect(find.byKey(const Key('update-skill-now')), findsNothing);
  });

  testWidgets('a known available update becomes a labelled Update action', (
    tester,
  ) async {
    final workspace = _workspace()
      ..updateReports = [
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('alpha'),
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
      ];

    await tester.pumpWidget(_app(workspace));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-skill-update')));
    await tester.pumpAndSettle();

    final action = find.byKey(const Key('update-skill-now'));
    expect(action, findsOneWidget);
    expect(find.byKey(const Key('check-skill-update')), findsNothing);
    expect(
      find.descendant(of: action, matching: find.text('Update available')),
      findsOneWidget,
    );
    // The same control, widened to carry the label, rather than a different
    // button put in its place.
    expect(tester.getSize(action).height, AppSizes.buttonHeight);
    expect(tester.getSize(action).width, greaterThan(AppSizes.buttonHeight));

    // Pressing it updates the Skill rather than rechecking it.
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(workspace.updateRequests, [
      {'alpha'},
    ]);
    expect(workspace.checkUpdatesCalls, 1);
  });

  testWidgets('the action widens into its labelled form rather than jumping', (
    tester,
  ) async {
    final workspace = _workspace()
      ..updateReports = [
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('alpha'),
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
      ];

    await tester.pumpWidget(_app(workspace));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-skill-update')));
    await tester.pump();

    final action = find.byKey(const Key('update-skill-now'));
    await tester.pump(AppMotion.controlMorphDuration ~/ 3);
    final midWidth = tester.getSize(action).width;
    await tester.pumpAndSettle();
    final settledWidth = tester.getSize(action).width;

    // Part way through the morph the control is strictly between its two
    // settled widths, which is only true if it grew rather than swapped.
    expect(midWidth, greaterThan(AppSizes.buttonHeight));
    expect(midWidth, lessThan(settledWidth));
    // Its height never moves, so the row of controls stays on one baseline.
    expect(tester.getSize(action).height, AppSizes.buttonHeight);
  });
}

Widget _app(FakeSkillsWorkspaceRepository workspace) => skillsManagerTestApp(
  browserRepository: FakeSkillBrowserRepository(
    catalog: InstalledSkillCatalog(
      revision: 1,
      skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha Skill')],
    ),
    documents: const {'alpha': '# Alpha'},
  ),
  workspaceRepository: workspace,
  initialLocation: '/installed/alpha',
  // An unexpired TTL, so the background sweep cannot confuse these assertions.
  lastUpdateSweepAt: DateTime.now().toUtc(),
);

FakeSkillsWorkspaceRepository _workspace() => FakeSkillsWorkspaceRepository(
  snapshot: SkillsWorkspaceSnapshot(
    revision: 1,
    projectRoots: const [],
    skills: [
      WorkspaceSkill(
        id: WorkspaceSkillId('alpha'),
        slotKey: 'alpha',
        declaredName: 'alpha',
        displayName: 'Alpha Skill',
        description: 'Test skill',
        source: const SkillSourceProvenance(
          kind: WorkspaceSourceKind.local,
          locator: '/skills/alpha',
        ),
        currentRevision: SkillRevision(
          contentHash: 'hash-alpha',
          fileCount: 1,
          byteSize: 1,
          acquiredAt: DateTime.utc(2026),
        ),
        activations: const [],
      ),
    ],
  ),
);
