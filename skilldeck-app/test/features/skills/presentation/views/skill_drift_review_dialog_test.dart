import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_drift_review_view_model.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';

import '../../../../support/fake_directory_picker.dart';
import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/skill_drift_test_support.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  testWidgets(
    'loading inspection disables review actions until evidence arrives',
    (tester) async {
      final completion =
          Completer<WorkspaceCompletion<WorkspaceSkillDriftReview>>();
      final workspace = driftWidgetWorkspace()
        ..inspectSkillDriftTasks.clear()
        ..inspectSkillDriftTasks.add(
          pendingDriftWidgetTask(
            kind: WorkspaceOperationKind.inspectSkillDrift,
            completion: completion,
          ),
        );
      await _pumpDialog(tester, workspace, settle: false);
      expect(_state(tester).status, SkillDriftReviewStatus.loading);
      expect(
        tester
            .widget<AppIconButton>(find.byKey(const Key('skill-drift-close')))
            .onPressed,
        isNotNull,
      );
      expect(_confirmAction(tester).onPressed, isNull);
      expect(find.byKey(const Key('skill-drift-keep')), findsNothing);
      expect(find.byKey(const Key('skill-drift-restore')), findsNothing);
      completion.complete(WorkspaceCompleted(value: driftWidgetReview()));
      await tester.pumpAndSettle();
      expect(_state(tester).status, SkillDriftReviewStatus.loaded);
      expect(
        find.byKey(const Key('skill-drift-artifact-repositoryCopy')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'inspection failure keeps the dialog open without resolution evidence',
    (tester) async {
      final workspace = driftWidgetWorkspace()
        ..inspectSkillDriftTasks.clear()
        ..inspectSkillDriftTasks.add(
          failedWorkspaceTask(
            kind: WorkspaceOperationKind.inspectSkillDrift,
            error: WorkspaceException(
              code: WorkspaceErrorCode.revisionStoreCorrupt,
              operation: WorkspaceOperationKind.inspectSkillDrift,
            ),
          ),
        );
      await _pumpDialog(tester, workspace);
      expect(_state(tester).status, SkillDriftReviewStatus.failed);
      expect(_state(tester).review, isNull);
      expect(find.byType(AppFailureView), findsOneWidget);
      expect(_confirmAction(tester).onPressed, isNull);
      expect(workspace.resolvedSkillDrifts, isEmpty);
    },
  );

  testWidgets('shows what changed and offers capability-specific options', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace(
      review: driftWidgetReview(
        artifacts: [
          driftWidgetArtifact(),
          driftWidgetArtifact(
            artifactId: 'activation:copy',
            locationKind: WorkspaceDriftLocationKind.copyActivation,
          ),
          driftWidgetArtifact(
            artifactId: 'activation:link',
            locationKind: WorkspaceDriftLocationKind.symbolicLinkActivation,
            driftKind: WorkspaceDriftKind.wrongLinkTarget,
            canKeepExternal: false,
            canExport: false,
          ),
        ],
      ),
    );
    await _pumpDialog(tester, workspace);
    for (final id in ['repositoryCopy', 'activation:copy', 'activation:link']) {
      expect(find.byKey(Key('skill-drift-artifact-$id')), findsOneWidget);
    }
    expect(
      find.byKey(const Key('skill-drift-select-repositoryCopy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('skill-drift-select-activation:copy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('skill-drift-select-activation:link')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('skill-drift-export-repositoryCopy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('skill-drift-export-activation:link')),
      findsNothing,
    );
    final l10n = tester
        .element(find.byKey(const Key('skill-drift-review-dialog')))
        .l10n;
    expect(
      find.text(l10n.skillDriftLocationRepositoryCopy),
      findsOneWidget,
      reason: 'The stored copy has a change row but no path to show.',
    );
    expect(
      find.text(
        l10n.skillDriftKeepOption(l10n.skillDriftLocationRepositoryCopy),
      ),
      findsOneWidget,
    );
    expect(
      find.text(l10n.skillDriftKeepOption(l10n.activationUnknownAgent)),
      findsOneWidget,
    );
    expect(
      find.textContaining(l10n.skillDriftContentChanged),
      findsNWidgets(2),
    );
    expect(find.textContaining(l10n.skillDriftWrongLinkTarget), findsOneWidget);
    expect(find.textContaining('/agents/codex/alpha'), findsWidgets);
    expect(find.byKey(const Key('skill-drift-keep-unavailable')), findsNothing);

    // Nothing is chosen up front, and the consequences stay folded away.
    expect(_confirmAction(tester).onPressed, isNull);
    expect(find.text(l10n.skillDriftRestoreWarning), findsNothing);
    expect(find.text(l10n.skillDriftKeepOptionDetail), findsNothing);

    const copyOption = Key('skill-drift-select-activation:copy');
    await tester.ensureVisible(find.byKey(copyOption));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(copyOption));
    await tester.pumpAndSettle();
    expect(find.text(l10n.skillDriftKeepOptionDetail), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byKey(const Key('skill-drift-keep'))).style,
      NeoButtonVariant.primary,
    );

    await _chooseRestore(tester);
    expect(find.byKey(const Key('skill-drift-keep')), findsNothing);
    expect(find.text(l10n.skillDriftKeepOptionDetail), findsNothing);
    expect(find.text(l10n.skillDriftRestoreWarning), findsOneWidget);
    final restore = tester.widget<AppButton>(
      find.byKey(const Key('skill-drift-restore')),
    );
    expect(restore.style, NeoButtonVariant.danger);
    expect(restore.onPressed, isNotNull);
  });

  testWidgets('wrong entry types describe what replaced the managed entry', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace(
      review: driftWidgetReview(
        artifacts: [
          driftWidgetArtifact(
            artifactId: 'activation:link',
            locationKind: WorkspaceDriftLocationKind.symbolicLinkActivation,
            driftKind: WorkspaceDriftKind.wrongEntryType,
            canKeepExternal: false,
          ),
          driftWidgetArtifact(
            artifactId: 'activation:copy',
            locationKind: WorkspaceDriftLocationKind.copyActivation,
            driftKind: WorkspaceDriftKind.wrongEntryType,
            canKeepExternal: false,
          ),
        ],
      ),
    );
    await _pumpDialog(tester, workspace);
    final l10n = tester
        .element(find.byKey(const Key('skill-drift-review-dialog')))
        .l10n;
    expect(find.text(l10n.skillDriftLinkReplaced), findsOneWidget);
    expect(find.text(l10n.skillDriftFolderReplaced), findsOneWidget);
  });

  testWidgets(
    'activation rows use catalog display names and localized unknown agents',
    (tester) async {
      final workspace =
          FakeSkillsWorkspaceRepository(
              snapshot: driftWidgetSnapshot(),
              globalTargets: const [
                WorkspaceActivationTarget(
                  agentId: 'codex',
                  displayName: 'Codex Desktop',
                  detected: true,
                  location: '/agents/codex',
                  scope: WorkspaceScope.global,
                ),
              ],
            )
            ..inspectSkillDriftTasks.add(
              completedWorkspaceTask(
                kind: WorkspaceOperationKind.inspectSkillDrift,
                value: driftWidgetReview(
                  artifacts: [
                    driftWidgetArtifact(
                      locationKind: WorkspaceDriftLocationKind.copyActivation,
                      agentIds: ['codex', 'retired-agent', 'universal'],
                    ),
                  ],
                ),
              ),
            );
      await _pumpDialog(tester, workspace);
      final l10n = tester
          .element(find.byKey(const Key('skill-drift-review-dialog')))
          .l10n;
      expect(
        find.text(
          'Codex Desktop, ${l10n.activationUnknownAgent}, ${l10n.activationUniversalAgents}',
        ),
        findsOneWidget,
      );
      expect(find.text('codex, retired-agent, universal'), findsNothing);
    },
  );

  testWidgets('keeps the explicitly selected external location and closes', (
    tester,
  ) async {
    final review = driftWidgetReview(
      artifacts: [
        driftWidgetArtifact(),
        driftWidgetArtifact(
          artifactId: 'activation:copy',
          locationKind: WorkspaceDriftLocationKind.copyActivation,
        ),
      ],
    );
    final workspace = driftWidgetWorkspace(review: review);
    await _pumpDialog(tester, workspace);
    await tester.ensureVisible(
      find.byKey(const Key('skill-drift-select-activation:copy')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('skill-drift-select-activation:copy')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('skill-drift-keep')));
    await tester.pumpAndSettle();
    expect(workspace.resolvedSkillDrifts, hasLength(1));
    final request = workspace.resolvedSkillDrifts.single;
    expect(request.review, same(review));
    expect(
      (request.resolution as WorkspaceKeepExternalSkillDrift).artifactId,
      'activation:copy',
    );
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
  });

  testWidgets('restores managed bytes without a keepable location and closes', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace(
      review: driftWidgetReview(
        artifacts: [
          driftWidgetArtifact(
            driftKind: WorkspaceDriftKind.wrongEntryType,
            canKeepExternal: false,
          ),
        ],
      ),
    );
    await _pumpDialog(tester, workspace);
    expect(
      find.byKey(const Key('skill-drift-select-repositoryCopy')),
      findsNothing,
    );
    expect(find.byKey(const Key('skill-drift-keep')), findsNothing);
    expect(
      find.byKey(const Key('skill-drift-keep-unavailable')),
      findsOneWidget,
    );
    // Restoring is the only resolution, so it starts out chosen.
    expect(_state(tester).restoreSelected, isTrue);
    await tester.tap(find.byKey(const Key('skill-drift-restore')));
    await tester.pumpAndSettle();
    expect(
      workspace.resolvedSkillDrifts.single.resolution,
      isA<WorkspaceRestoreManagedSkillDrift>(),
    );
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
  });

  testWidgets('exports through the picker and leaves the review open', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace();
    final picker = FakeDirectoryPicker('/chosen-export');
    await _pumpDialog(tester, workspace, picker: picker);
    await tester.ensureVisible(
      find.byKey(const Key('skill-drift-export-repositoryCopy')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('skill-drift-export-repositoryCopy')),
    );
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(
      workspace.exportedSkillDriftArtifacts.single.artifactId,
      'repositoryCopy',
    );
    expect(
      workspace.exportedSkillDriftArtifacts.single.destinationDirectory,
      '/chosen-export',
    );
    expect(
      find.byKey(const Key('skill-drift-exported-repositoryCopy')),
      findsOneWidget,
    );
    expect(find.textContaining('/chosen-export/external'), findsOneWidget);
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsOneWidget);
    expect(workspace.resolvedSkillDrifts, isEmpty);
  });

  testWidgets('cancelling the directory picker leaves the review unchanged', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace();
    final picker = FakeDirectoryPicker(null);
    await _pumpDialog(tester, workspace, picker: picker);
    await tester.ensureVisible(
      find.byKey(const Key('skill-drift-export-repositoryCopy')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('skill-drift-export-repositoryCopy')),
    );
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(workspace.exportedSkillDriftArtifacts, isEmpty);
    expect(
      find.byKey(const Key('skill-drift-exported-repositoryCopy')),
      findsNothing,
    );
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsOneWidget);
    expect(_state(tester).status, SkillDriftReviewStatus.loaded);
  });

  testWidgets('a stale resolution disables actions until refreshed review', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace()
      ..resolveSkillDriftTasks.add(
        failedWorkspaceTask(
          kind: WorkspaceOperationKind.resolveSkillDrift,
          error: WorkspaceException(
            code: WorkspaceErrorCode.staleSnapshot,
            operation: WorkspaceOperationKind.resolveSkillDrift,
            context: const {'reason': 'artifactChanged'},
          ),
        ),
      );
    await _pumpDialog(tester, workspace);
    await tester.ensureVisible(
      find.byKey(const Key('skill-drift-select-repositoryCopy')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('skill-drift-select-repositoryCopy')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('skill-drift-keep')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-drift-stale')), findsOneWidget);
    expect(_confirmAction(tester).onPressed, isNull);
    expect(_state(tester).selectedArtifactId, isNull);
    expect(_state(tester).restoreSelected, isFalse);
    final nextReview = driftWidgetReview(
      artifacts: [driftWidgetArtifact(artifactId: 'reviewed-again')],
    );
    workspace.inspectSkillDriftTasks.add(
      completedWorkspaceTask(
        kind: WorkspaceOperationKind.inspectSkillDrift,
        value: nextReview,
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('skill-drift-reload')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skill-drift-reload')));
    await tester.pumpAndSettle();
    expect(workspace.inspectedSkillDrifts, hasLength(2));
    expect(workspace.refreshCalls, greaterThanOrEqualTo(1));
    expect(_state(tester).review, same(nextReview));
    expect(find.byKey(const Key('skill-drift-stale')), findsNothing);
    expect(
      find.byKey(const Key('skill-drift-artifact-reviewed-again')),
      findsOneWidget,
    );
  });

  testWidgets('resolve failure stays open and leaves Skill drift pending', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace()
      ..resolveSkillDriftTasks.add(
        failedWorkspaceTask(
          kind: WorkspaceOperationKind.resolveSkillDrift,
          error: WorkspaceException(
            code: WorkspaceErrorCode.ioFailure,
            operation: WorkspaceOperationKind.resolveSkillDrift,
          ),
        ),
      );
    await _pumpDialog(tester, workspace);
    await _chooseRestore(tester);
    await tester.tap(find.byKey(const Key('skill-drift-restore')));
    await tester.pumpAndSettle();
    expect(find.byType(AppFailureView), findsOneWidget);
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsOneWidget);
    expect(
      workspace.current.findSkillById(driftWidgetSkillId)?.integrity,
      WorkspaceSkillIntegrityStatus.driftPending,
    );
    expect(_state(tester).status, SkillDriftReviewStatus.failed);
  });

  testWidgets('export failure remains in the review without resolving drift', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace()
      ..exportSkillDriftArtifactTasks.add(
        failedWorkspaceTask(
          kind: WorkspaceOperationKind.exportSkillDriftArtifact,
          error: WorkspaceException(
            code: WorkspaceErrorCode.ioFailure,
            operation: WorkspaceOperationKind.exportSkillDriftArtifact,
          ),
        ),
      );
    await _pumpDialog(
      tester,
      workspace,
      picker: FakeDirectoryPicker('/chosen-export'),
    );
    await tester.ensureVisible(
      find.byKey(const Key('skill-drift-export-repositoryCopy')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('skill-drift-export-repositoryCopy')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppFailureView), findsOneWidget);
    expect(
      find.byKey(const Key('skill-drift-exported-repositoryCopy')),
      findsNothing,
    );
    expect(workspace.resolvedSkillDrifts, isEmpty);
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsOneWidget);
  });

  testWidgets('an empty no-op review can restore successfully and close', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace(
      review: driftWidgetReview(artifacts: const []),
    );
    await _pumpDialog(tester, workspace);
    final l10n = tester
        .element(find.byKey(const Key('skill-drift-review-dialog')))
        .l10n;
    final action = tester.widget<AppButton>(
      find.byKey(const Key('skill-drift-restore')),
    );
    expect(action.style, NeoButtonVariant.primary);
    expect(action.label, l10n.commonDone);
    expect(find.byKey(const Key('skill-drift-cancel')), findsNothing);
    expect(find.text(l10n.skillDriftRestoreWarning), findsNothing);
    expect(find.byKey(const Key('skill-drift-keep')), findsNothing);
    workspace.resolveSkillDriftTasks.add(
      completedWorkspaceTask(
        kind: WorkspaceOperationKind.resolveSkillDrift,
        value: WorkspaceMutationReceipt(snapshot: workspace.current),
      ),
    );
    await tester.tap(find.byKey(const Key('skill-drift-restore')));
    await tester.pumpAndSettle();
    expect(workspace.resolvedSkillDrifts, hasLength(1));
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
  });

  testWidgets('missing-only review shows the repair count and can restore', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace(
      review: driftWidgetReview(artifacts: const [], missingArtifactCount: 3),
    );
    await _pumpDialog(tester, workspace);
    final l10n = tester
        .element(find.byKey(const Key('skill-drift-review-dialog')))
        .l10n;
    expect(find.text(l10n.skillDriftMissingArtifacts(3)), findsOneWidget);
    expect(find.text(l10n.skillDriftNoChanges), findsNothing);
    final action = tester.widget<AppButton>(
      find.byKey(const Key('skill-drift-restore')),
    );
    expect(action.style, NeoButtonVariant.primary);
    expect(action.label, l10n.skillDriftRestoreMissing);
    expect(find.byKey(const Key('skill-drift-cancel')), findsOneWidget);
    expect(find.text(l10n.skillDriftRestoreWarning), findsNothing);
    expect(find.byKey(const Key('skill-drift-keep')), findsNothing);
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('skill-drift-restore')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('skill-drift-restore')));
    await tester.pumpAndSettle();
    expect(
      workspace.resolvedSkillDrifts.single.resolution,
      isA<WorkspaceRestoreManagedSkillDrift>(),
    );
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
  });

  testWidgets('busy resolution disables close and prevents barrier dismissal', (
    tester,
  ) async {
    final completion =
        Completer<WorkspaceCompletion<WorkspaceMutationReceipt>>();
    final workspace = driftWidgetWorkspace()
      ..resolveSkillDriftTasks.add(
        pendingDriftWidgetTask(
          kind: WorkspaceOperationKind.resolveSkillDrift,
          completion: completion,
        ),
      );
    await _pumpDialog(tester, workspace);
    await _chooseRestore(tester);
    await tester.tap(find.byKey(const Key('skill-drift-restore')));
    await tester.pump();
    expect(_state(tester).status, SkillDriftReviewStatus.busy);
    expect(
      tester
          .widget<AppIconButton>(find.byKey(const Key('skill-drift-close')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('skill-drift-restore')))
          .onPressed,
      isNull,
    );
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsOneWidget);
    completion.complete(
      WorkspaceCompleted(
        value: WorkspaceMutationReceipt(snapshot: workspace.current),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
  });

  testWidgets('loaded review cannot be dismissed by its modal barrier', (
    tester,
  ) async {
    final workspace = driftWidgetWorkspace();
    await _pumpDialog(tester, workspace);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('skill-drift-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
    expect(workspace.resolvedSkillDrifts, isEmpty);
  });

  testWidgets('cancel closes the review without resolving', (tester) async {
    final workspace = driftWidgetWorkspace();
    await _pumpDialog(tester, workspace);
    await tester.tap(find.byKey(const Key('skill-drift-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
    expect(workspace.resolvedSkillDrifts, isEmpty);
  });

  testWidgets(
    'committed pending closes the dialog and registers root recovery',
    (tester) async {
      final recovery =
          Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
      final workspace = driftWidgetWorkspace()
        ..resolveSkillDriftTasks.add(
          WorkspaceTask(
            current: WorkspaceOperationProgress(
              operationId: 'drift-pending',
              kind: WorkspaceOperationKind.resolveSkillDrift,
              phase: WorkspaceOperationPhase.finalizing,
            ),
            states: const Stream.empty(),
            completed: Future.value(
              WorkspaceCommittedPending<WorkspaceMutationReceipt>(
                operationId: 'drift-pending',
                committedRevision: 2,
              ),
            ),
            cancel: () async {},
          ),
        )
        ..finalizationRecoveryTasks.add(
          pendingDriftWidgetTask(
            kind: WorkspaceOperationKind.resumeFinalizationRecovery,
            completion: recovery,
          ),
        );
      await _pumpDialog(tester, workspace);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('skill-drift-review-dialog'))),
        listen: false,
      );
      await _chooseRestore(tester);
      await tester.tap(find.byKey(const Key('skill-drift-restore')));
      await tester.pumpAndSettle();
      expect(
        container.exists(skillDriftReviewViewModelProvider(driftWidgetSkillId)),
        isFalse,
      );
      expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
      expect(
        container
            .read(workspaceFinalizationCoordinatorProvider)
            .pendingOperationIds,
        contains('drift-pending'),
      );
      expect(workspace.finalizationRecoveryCalls, 1);
      final recovered = driftWidgetSnapshot(
        revision: 2,
        integrity: WorkspaceSkillIntegrityStatus.healthy,
      );
      workspace.publish(recovered);
      recovery.complete(WorkspaceCompleted(value: recovered));
      await tester.pumpAndSettle();
      expect(
        container
            .read(workspaceFinalizationCoordinatorProvider)
            .pendingOperationIds,
        isEmpty,
      );
    },
  );

  testWidgets(
    'reopening starts fresh without old review selection or exports',
    (tester) async {
      final workspace = driftWidgetWorkspace();
      await _pumpDialog(
        tester,
        workspace,
        picker: FakeDirectoryPicker('/exports'),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('skill-drift-review-dialog'))),
        listen: false,
      );
      await tester.ensureVisible(
        find.byKey(const Key('skill-drift-select-repositoryCopy')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('skill-drift-select-repositoryCopy')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('skill-drift-export-repositoryCopy')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('skill-drift-export-repositoryCopy')),
      );
      await tester.pumpAndSettle();
      expect(_state(tester).selectedArtifactId, 'repositoryCopy');
      expect(_state(tester).exportedPaths, isNotEmpty);
      // The header scrolls with the content, so bring the close button back.
      await tester.ensureVisible(find.byKey(const Key('skill-drift-close')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('skill-drift-close')));
      await tester.pumpAndSettle();
      expect(
        container.exists(skillDriftReviewViewModelProvider(driftWidgetSkillId)),
        isFalse,
      );

      final next = Completer<WorkspaceCompletion<WorkspaceSkillDriftReview>>();
      workspace.inspectSkillDriftTasks.add(
        pendingDriftWidgetTask(
          kind: WorkspaceOperationKind.inspectSkillDrift,
          completion: next,
        ),
      );
      await tester.tap(find.byKey(const Key('skill-drift-review-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final fresh = _state(tester);
      expect(fresh.status, SkillDriftReviewStatus.loading);
      expect(fresh.review, isNull);
      expect(fresh.selectedArtifactId, isNull);
      expect(fresh.exportedPaths, isEmpty);
      expect(
        find.byKey(const Key('skill-drift-artifact-repositoryCopy')),
        findsNothing,
      );
      expect(_confirmAction(tester).onPressed, isNull);
      next.complete(
        WorkspaceCompleted(
          value: driftWidgetReview(
            artifacts: [driftWidgetArtifact(artifactId: 'fresh-artifact')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('skill-drift-artifact-fresh-artifact')),
        findsOneWidget,
      );
      expect(workspace.inspectedSkillDrifts, hasLength(2));
    },
  );

  testWidgets(
    'can close during post-stale refresh and ignores its late result',
    (tester) async {
      final refresh = Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
      final workspace = driftWidgetWorkspace()
        ..refreshCompleter = refresh
        ..resolveSkillDriftTasks.add(
          failedWorkspaceTask(
            kind: WorkspaceOperationKind.resolveSkillDrift,
            error: WorkspaceException(
              code: WorkspaceErrorCode.staleDriftReview,
              operation: WorkspaceOperationKind.resolveSkillDrift,
            ),
          ),
        );
      await _pumpDialog(tester, workspace);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('skill-drift-review-dialog'))),
        listen: false,
      );
      await _chooseRestore(tester);
      await tester.tap(find.byKey(const Key('skill-drift-restore')));
      await tester.pumpAndSettle();
      final l10n = tester
          .element(find.byKey(const Key('skill-drift-review-dialog')))
          .l10n;
      expect(
        tester
            .widget<AppButton>(find.byKey(const Key('skill-drift-reload')))
            .label,
        l10n.skillDriftRefreshReview,
      );
      await tester.ensureVisible(find.byKey(const Key('skill-drift-reload')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('skill-drift-reload')));
      await tester.pump();
      expect(_state(tester).status, SkillDriftReviewStatus.loading);
      expect(workspace.refreshCalls, 1);
      expect(
        tester
            .widget<AppIconButton>(find.byKey(const Key('skill-drift-close')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('skill-drift-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
      expect(
        container.exists(skillDriftReviewViewModelProvider(driftWidgetSkillId)),
        isFalse,
      );
      refresh.complete(WorkspaceCompleted(value: workspace.current));
      await tester.pumpAndSettle();
      expect(workspace.inspectedSkillDrifts, hasLength(1));
      expect(workspace.resolvedSkillDrifts, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpDialog(
  WidgetTester tester,
  FakeSkillsWorkspaceRepository workspace, {
  FakeDirectoryPicker? picker,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    skillsManagerTestApp(
      browserRepository: FakeSkillBrowserRepository(
        catalog: InstalledSkillCatalog(
          revision: 1,
          skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha Skill')],
        ),
        documents: {'alpha': '# Alpha'},
      ),
      workspaceRepository: workspace,
      directoryPicker: picker,
      initialLocation: '/installed/alpha/external-changes',
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

SkillDriftReviewState _state(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byKey(const Key('skill-drift-review-dialog'))),
  listen: false,
).read(skillDriftReviewViewModelProvider(driftWidgetSkillId));

AppButton _confirmAction(WidgetTester tester) =>
    tester.widget<AppButton>(find.byKey(const Key('skill-drift-confirm')));

Future<void> _chooseRestore(WidgetTester tester) async {
  const option = Key('skill-drift-select-restore');
  await tester.ensureVisible(find.byKey(option));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(option));
  await tester.pumpAndSettle();
}
