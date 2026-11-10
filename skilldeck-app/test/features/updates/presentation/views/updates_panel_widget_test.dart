import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_header.dart';

import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  testWidgets('renders every update status and updates available slots only', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshot([
        _skill('current'),
        _skill('available-one'),
        _skill('available-two'),
        _skill('unavailable'),
        _skill('unsupported'),
      ]),
      updateReports: [
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('current'),
          status: WorkspaceUpdateStatus.current,
        ),
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('available-one'),
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('available-two'),
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('unavailable'),
          status: WorkspaceUpdateStatus.sourceUnavailable,
          failureReason: WorkspaceUpdateCheckFailureReason.timedOut,
        ),
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('unsupported'),
          status: WorkspaceUpdateStatus.updateUnsupported,
        ),
      ],
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        startupUpdateSweep: true,
        initialLocation: '/updates',
      ),
    );
    await tester.pump();
    for (var index = 0; index < 100; index += 1) {
      await tester.pump(const Duration(milliseconds: 10));
      if (find.byKey(const Key('updates-check-progress')).evaluate().isEmpty) {
        break;
      }
    }
    expect(find.byKey(const Key('updates-check-progress')), findsNothing);

    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Update available'), findsNWidgets(2));
    expect(find.text('Git update check timed out'), findsOneWidget);
    expect(find.text('Updates unsupported for this source'), findsOneWidget);
    final checkButton = tester.widget<AppIconButton>(
      find.byKey(const Key('updates-check')),
    );
    final updateAllButton = tester.widget<AppIconButton>(
      find.byKey(const Key('updates-update-all')),
    );
    expect(checkButton.style, NeoButtonVariant.secondary);
    expect(checkButton.size, AppSizes.pageCommandBarHeight);
    expect(checkButton.iconSize, AppSizes.iconMd);
    expect(updateAllButton.style, NeoButtonVariant.primary);
    expect(updateAllButton.size, AppSizes.pageCommandBarHeight);
    expect(updateAllButton.iconSize, AppSizes.iconMd);
    // Matches the Installed page's header action spacing.
    expect(
      tester.getTopLeft(find.byKey(const Key('updates-update-all'))).dx -
          tester.getTopRight(find.byKey(const Key('updates-check'))).dx,
      AppSpacing.sm,
    );

    await tester.tap(find.byKey(const Key('updates-update-available-one')));
    await tester.pumpAndSettle();
    expect(workspace.updateRequests.first, {'available-one'});

    await tester.tap(find.byKey(const Key('updates-update-all')));
    await tester.pumpAndSettle();
    // `available-one` was just updated, so its state is derived from the
    // committed Snapshot rather than staying `updateAvailable`.
    expect(workspace.updateRequests.last, {'available-two'});
    // One request per shared fetch; these local Skills share none. Opening the
    // page did not restart a sweep that had already completed.
    expect(workspace.checkUpdatesCalls, 5);
  });

  testWidgets('opening the page does not restart a completed sweep', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshot([_skill('alpha')]),
      updateReports: [
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('alpha'),
          status: WorkspaceUpdateStatus.current,
        ),
      ],
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        startupUpdateSweep: true,
        initialLocation: '/updates',
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.checkUpdatesCalls, 1);

    // Only the explicit action forces a refresh.
    await tester.tap(find.byKey(const Key('updates-check')));
    await tester.pumpAndSettle();
    expect(workspace.checkUpdatesCalls, 2);
  });

  testWidgets('collapses the title beneath fixed update commands', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshot([
        for (var index = 0; index < 24; index++) _skill('skill-$index'),
      ]),
      updateReports: [
        for (var index = 0; index < 24; index++)
          WorkspaceUpdateReport(
            skillId: WorkspaceSkillId('skill-$index'),
            status: index.isEven
                ? WorkspaceUpdateStatus.current
                : WorkspaceUpdateStatus.updateAvailable,
          ),
      ],
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        startupUpdateSweep: true,
        initialLocation: '/updates',
      ),
    );
    await tester.pumpAndSettle();

    final scroll = find.byKey(const Key('updates-page-scroll'));
    final title = find.byKey(const Key('updates-page-title'));
    final check = find.byKey(const Key('updates-check'));
    final blur = find.byKey(const Key('updates-top-blur'));
    final header = find.byKey(const Key('updates-header-column'));
    final checkPosition = tester.getTopLeft(check);
    expect(find.descendant(of: blur, matching: header), findsNothing);
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.expandedTitleFontSize,
    );

    await tester.drag(scroll, const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.collapsedTitleFontSize,
    );
    expect(tester.getTopLeft(check), checkPosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows resolution distinctly and lets the user abandon a candidate',
    (tester) async {
      final skillId = WorkspaceSkillId('managed-alpha');
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: _snapshot([
          _skill(
            'alpha',
            id: skillId,
            updateCandidate: WorkspaceUpdateCandidateSummary(
              status: WorkspaceUpdateCandidateStatus.conflicted,
              conflictPaths: const ['SKILL.md'],
              createdAt: DateTime.utc(2026),
            ),
          ),
        ]),
      );

      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(),
          workspaceRepository: workspace,
          startupUpdateSweep: true,
          initialLocation: '/updates',
        ),
      );
      await tester.pumpAndSettle();

      // Resolution state is read from the Snapshot, not awaited from a report,
      // so it renders without spending a network round trip.
      expect(find.text('Update candidate needs resolution'), findsOneWidget);
      final abandon = find.byKey(const Key('updates-abandon-candidate-alpha'));
      expect(abandon, findsOneWidget);

      await tester.tap(abandon);
      await tester.pumpAndSettle();
      expect(workspace.abandonedUpdateCandidates, [skillId]);
    },
  );

  testWidgets('shows localized recovery copy and disables an isolated update', (
    tester,
  ) async {
    final skillId = WorkspaceSkillId('managed-corrupt');
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshot([
        _skill(
          'corrupt',
          id: skillId,
          integrity: WorkspaceSkillIntegrityStatus.revisionStoreCorrupt,
        ),
      ]),
      updateReports: [
        WorkspaceUpdateReport(
          skillId: skillId,
          status: WorkspaceUpdateStatus.updateAvailable,
        ),
      ],
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        startupUpdateSweep: true,
        initialLocation: '/updates',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Recovery required before this skill can be changed.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('updates-update-corrupt')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a failed check stays per-Skill and can be retried alone', (
    tester,
  ) async {
    final workspace =
        FakeSkillsWorkspaceRepository(snapshot: _snapshot([_skill('alpha')]))
          ..checkUpdatesError = WorkspaceException(
            code: WorkspaceErrorCode.sourceUnavailable,
            operation: WorkspaceOperationKind.checkUpdates,
          );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        startupUpdateSweep: true,
        initialLocation: '/updates',
      ),
    );
    await tester.pumpAndSettle();

    // A failed check is distinct from a Source that was reached and reported
    // itself unavailable, and it does not blank the whole page.
    expect(find.text('The check could not be completed.'), findsOneWidget);
    expect(find.text('Source unavailable'), findsNothing);
    expect(find.text('All skills are up to date.'), findsNothing);

    workspace
      ..checkUpdatesError = null
      ..updateReports = [
        WorkspaceUpdateReport(
          skillId: WorkspaceSkillId('alpha'),
          status: WorkspaceUpdateStatus.current,
        ),
      ];
    await tester.tap(find.byKey(const Key('updates-check-alpha')));
    await tester.pumpAndSettle();
    expect(workspace.checkUpdatesCalls, 2);
    expect(find.text('Current'), findsOneWidget);
  });

  testWidgets('shows mutation warnings and forwards cancellation', (
    tester,
  ) async {
    final result = Completer<WorkspaceCompletion<WorkspaceMutationReceipt>>();
    final cancelled = Completer<void>();
    final snapshot = _snapshot([_skill('available')]);
    final workspace =
        FakeSkillsWorkspaceRepository(
            snapshot: snapshot,
            updateReports: [
              WorkspaceUpdateReport(
                skillId: WorkspaceSkillId('available'),
                status: WorkspaceUpdateStatus.updateAvailable,
              ),
            ],
          )
          ..updateTask = WorkspaceTask(
            current: WorkspaceOperationProgress(
              operationId: 'update-1',
              kind: WorkspaceOperationKind.update,
              phase: WorkspaceOperationPhase.waitingForLock,
              warnings: [
                WorkspaceWarning(code: WorkspaceWarningCode.agentUndetected),
              ],
            ),
            states: const Stream.empty(),
            completed: result.future,
            cancel: () async => cancelled.complete(),
          );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        startupUpdateSweep: true,
        initialLocation: '/updates',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates-update-available')));
    await tester.pump();

    expect(find.byKey(const Key('operation-feedback')), findsOneWidget);
    expect(find.text('Updating available'), findsOneWidget);
    expect(find.text('Waiting for the repository…'), findsOneWidget);
    expect(
      find.text('A selected agent was not detected on this device.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('operation-cancel')));
    await tester.pump();
    expect(cancelled.isCompleted, isTrue);

    result.complete(
      WorkspaceCompleted(value: WorkspaceMutationReceipt(snapshot: snapshot)),
    );
    await tester.pump();
    await tester.pump();
  });

  testWidgets('names the Skill being updated instead of its identifier', (
    tester,
  ) async {
    const opaqueId = '46a61128-44b3-4c4d-a77d-22a5330187ed';
    final result = Completer<WorkspaceCompletion<WorkspaceMutationReceipt>>();
    final snapshot = _snapshot([
      _skill('frontend-design', id: WorkspaceSkillId(opaqueId)),
    ]);
    final workspace =
        FakeSkillsWorkspaceRepository(
            snapshot: snapshot,
            updateReports: [
              WorkspaceUpdateReport(
                skillId: WorkspaceSkillId(opaqueId),
                status: WorkspaceUpdateStatus.updateAvailable,
              ),
            ],
          )
          ..updateTask = WorkspaceTask(
            current: WorkspaceOperationProgress(
              operationId: 'update-1',
              kind: WorkspaceOperationKind.update,
              phase: WorkspaceOperationPhase.inspecting,
              currentItem: opaqueId,
              total: 1,
            ),
            states: const Stream.empty(),
            completed: result.future,
            cancel: () async {},
          );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        startupUpdateSweep: true,
        initialLocation: '/updates',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates-update-frontend-design')));
    await tester.pump();

    final feedback = find.byKey(const Key('operation-feedback'));
    expect(
      find.descendant(
        of: feedback,
        matching: find.text('Updating frontend-design'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: feedback,
        matching: find.text('Fetching the new version…'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining(opaqueId), findsNothing);

    result.complete(
      WorkspaceCompleted(value: WorkspaceMutationReceipt(snapshot: snapshot)),
    );
    await tester.pump();
    await tester.pump();
  });

  testWidgets('a bulk update counts its Skills and names the current one', (
    tester,
  ) async {
    final result = Completer<WorkspaceCompletion<WorkspaceMutationReceipt>>();
    final snapshot = _snapshot([_skill('alpha'), _skill('beta')]);
    final workspace =
        FakeSkillsWorkspaceRepository(
            snapshot: snapshot,
            updateReports: [
              for (final id in ['alpha', 'beta'])
                WorkspaceUpdateReport(
                  skillId: WorkspaceSkillId(id),
                  status: WorkspaceUpdateStatus.updateAvailable,
                ),
            ],
          )
          ..updateTask = WorkspaceTask(
            current: WorkspaceOperationProgress(
              operationId: 'update-all',
              kind: WorkspaceOperationKind.update,
              phase: WorkspaceOperationPhase.inspecting,
              currentItem: 'beta',
              completed: 1,
              total: 2,
            ),
            states: const Stream.empty(),
            completed: result.future,
            cancel: () async {},
          );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        startupUpdateSweep: true,
        initialLocation: '/updates',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updates-update-all')));
    await tester.pump();

    expect(find.text('Updating 2 Skills'), findsOneWidget);
    expect(find.text('beta · Fetching the new version…'), findsOneWidget);

    result.complete(
      WorkspaceCompleted(value: WorkspaceMutationReceipt(snapshot: snapshot)),
    );
    await tester.pump();
    await tester.pump();
  });

  testWidgets('orders rows by urgency rather than Workspace order', (
    tester,
  ) async {
    // Deliberately handed back in the least useful order: the settled, quiet
    // rows first and the ones needing a decision buried at the end.
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshot([
        _skill('zeta-current'),
        _skill('beta-unsupported'),
        _skill('alpha-unavailable'),
        _skill('zulu-available'),
        _skill('alpha-available'),
        _skill(
          'candidate',
          updateCandidate: WorkspaceUpdateCandidateSummary(
            status: WorkspaceUpdateCandidateStatus.conflicted,
            conflictPaths: const ['SKILL.md'],
            createdAt: DateTime.utc(2026),
          ),
        ),
        _skill(
          'corrupt',
          integrity: WorkspaceSkillIntegrityStatus.revisionStoreCorrupt,
        ),
      ]),
      updateReports: [
        for (final entry in const {
          'zeta-current': WorkspaceUpdateStatus.current,
          'beta-unsupported': WorkspaceUpdateStatus.updateUnsupported,
          'alpha-unavailable': WorkspaceUpdateStatus.sourceUnavailable,
          'zulu-available': WorkspaceUpdateStatus.updateAvailable,
          'alpha-available': WorkspaceUpdateStatus.updateAvailable,
          'corrupt': WorkspaceUpdateStatus.current,
        }.entries)
          WorkspaceUpdateReport(
            skillId: WorkspaceSkillId(entry.key),
            status: entry.value,
          ),
      ],
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        startupUpdateSweep: true,
        initialLocation: '/updates',
      ),
    );
    await tester.pumpAndSettle();

    // Recovery outranks everything, then resolution, then the two available
    // updates — which tie on urgency and fall back to Slot Key order. A Source
    // that cannot be updated at all sits below even the already-current rows.
    final rendered =
        <String>[
              'corrupt',
              'candidate',
              'alpha-available',
              'zulu-available',
              'alpha-unavailable',
              'zeta-current',
              'beta-unsupported',
            ]
            .map(
              (slotKey) => (slotKey, tester.getTopLeft(find.text(slotKey)).dy),
            )
            .toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));

    expect(rendered.map((row) => row.$1), [
      'corrupt',
      'candidate',
      'alpha-available',
      'zulu-available',
      'alpha-unavailable',
      'zeta-current',
      'beta-unsupported',
    ]);
  });
}

SkillsWorkspaceSnapshot _snapshot(List<WorkspaceSkill> skills) =>
    SkillsWorkspaceSnapshot(
      revision: 1,
      projectRoots: const [],
      skills: skills,
    );

WorkspaceSkill _skill(
  String slotKey, {
  WorkspaceSkillId? id,
  WorkspaceUpdateCandidateSummary? updateCandidate,
  WorkspaceSkillIntegrityStatus integrity =
      WorkspaceSkillIntegrityStatus.healthy,
}) => WorkspaceSkill(
  id: id ?? WorkspaceSkillId(slotKey),
  slotKey: slotKey,
  declaredName: slotKey,
  displayName: slotKey,
  description: 'Test skill',
  source: SkillSourceProvenance(
    kind: WorkspaceSourceKind.local,
    locator: '/skills/$slotKey',
  ),
  currentRevision: SkillRevision(
    contentHash: 'hash-$slotKey',
    fileCount: 1,
    byteSize: 1,
    acquiredAt: DateTime.utc(2026),
  ),
  activations: const [],
  integrity: integrity,
  updateCandidate: updateCandidate,
);
