import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/app/skills_manager_app.dart';
import 'package:skills_manager/features/skills/data/repositories/package_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_location_label.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/notifications/app_notification_providers.dart';
import 'package:skills_manager/shared/platform/platform_providers.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';
import 'package:skills_workspace/skills_workspace.dart' as package_workspace;
import 'package:skills_translation/skills_translation.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/fake_app_translation_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // main.dart does this; without it the shell's window-button calls reach
  // window_manager before it has a main window and abort the process.
  setUpAll(windowManager.ensureInitialized);

  testWidgets(
    'real desktop UI acquires, activates, updates, and removes a local Skill',
    (tester) async {
      final environment = await _E2eEnvironment.create('ui');
      final workspace = environment.createWorkspace();
      addTearDown(() async {
        await _unmountApp(tester);
        await workspace.close();
        await environment.close();
      });
      final browser = WorkspaceSkillBrowserRepository(workspace);
      final acquisition = WorkspaceSkillAcquisitionRepository(
        workspace: workspace,
        resolver: SkillSourceLocatorResolver(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialSkillListLayoutProvider.overrideWithValue(
              SkillListLayout.list,
            ),
            skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
            skillBrowserRepositoryProvider.overrideWithValue(browser),
            skillAcquisitionRepositoryProvider.overrideWithValue(acquisition),
            desktopSupportedProvider.overrideWithValue(true),
            appNotificationPresenterProvider.overrideWithValue(
              const _NoopNotificationPresenter(),
            ),
            appTranslationRepositoryProvider.overrideWithValue(
              fakeAppTranslationRepository(),
            ),
            activeTranslationRequestProvider.overrideWith((ref) {
              return _activeTranslationRequest(
                ref.watch(skillBrowserViewModelProvider),
              );
            }),
          ],
          child: const SkillsManagerApp(locale: Locale('en')),
        ),
      );
      await _pumpUntilFound(tester, find.byKey(const Key('empty-add-skills')));

      await tester.tap(find.byKey(const Key('empty-add-skills')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('acquisition-dialog')),
      );
      // The wizard opens in smart mode: one box that detects the Source kind.
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('source-smart-input')),
      );
      await tester.enterText(
        find.byKey(const Key('source-smart-input')),
        environment.localSource.path,
      );
      await tester.pump();
      await _tapWhenReady(tester, find.byKey(const Key('inspect-source')));
      // Smart mode shows what it found before moving on to the candidates.
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('smart-source-result')),
      );
      await _tapWhenReady(
        tester,
        find.byKey(const Key('continue-acquisition')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('candidate-release-e2e')),
      );
      await _tapWhenReady(
        tester,
        find.byKey(const Key('continue-acquisition')),
      );
      await _tapWhenReady(tester, find.text('Store only'));
      await tester.pump();
      await _tapWhenReady(tester, find.byKey(const Key('install-skills')));
      await _pumpUntilGone(tester, find.byKey(const Key('acquisition-dialog')));
      // Store only leaves the Skill inactive, and the default All Agents view
      // lists only active Skills (9686b90c), so look for it under Inactive.
      await _selectMenuOption(
        tester,
        selector: find.byKey(const Key('scope-selector')),
        option: find.byKey(const Key('scope-option-inactive')),
      );
      await _pumpUntilFound(tester, find.byKey(const Key('skill-release-e2e')));

      expect(workspace.current?.skills.single.activations, isEmpty);
      final e2eGlobalTarget = (await _completedValue(
        workspace.inspectActivationTargets(scope: WorkspaceScope.global),
      )).singleWhere((target) => target.agentId == _E2eEnvironment.agentId);

      await tester.tap(find.byKey(const Key('skill-release-e2e')));
      await _pumpUntilFound(tester, find.byKey(const Key('skill-detail')));
      await _pumpUntilFound(tester, find.byKey(const Key('skill-markdown')));
      await _pumpUntil(
        tester,
        () => _visibleMarkdownContains(tester, 'Version one content'),
      );
      await tester.tap(find.byKey(const Key('skill-file-picker')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('skill-document-directory-references')),
      );
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-document-directory-references')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('skill-document-file-references/guide.md')),
      );
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('skill-document-file-references/guide.md')),
      );
      await _pumpUntil(
        tester,
        () => _visibleMarkdownContains(tester, 'Reference content'),
      );
      await _tapWhenHitTestable(
        tester,
        _findSkillSectionTab(LucideIcons.settings),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('detail-scope-selector')),
      );
      // Settings now activates each location inline, without an activation
      // dialog. Match the fixture's exact global location rather than another
      // detected Agent or the master switch.
      final activationToggle = find.byKey(
        Key(
          'activation-toggle-${e2eGlobalTarget.scope.name}-'
          '${e2eGlobalTarget.projectRootId ?? 'global'}-'
          '${e2eGlobalTarget.location}',
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            activationToggle.evaluate().isNotEmpty &&
            tester.widget<AgentActivationSwitch>(activationToggle).onChanged !=
                null,
      );
      expect(
        tester.widget<AgentActivationSwitch>(activationToggle).on,
        isFalse,
      );
      await _tapWhenHitTestable(tester, activationToggle);
      await _pumpUntil(
        tester,
        () =>
            workspace.current?.skills.single.activations.any(
              (activation) =>
                  activation.scope == e2eGlobalTarget.scope &&
                  activation.projectRootId == e2eGlobalTarget.projectRootId &&
                  activation.location == e2eGlobalTarget.location,
            ) ??
            false,
      );

      final activatedDocument = File(
        p.join(environment.globalSkills.path, 'release-e2e', 'SKILL.md'),
      );
      expect(await activatedDocument.readAsString(), contains('Version one'));
      expect(workspace.current?.skills.single.activations, hasLength(1));

      await environment.writeLocalVersion(2);
      final reports = await _completedValue(workspace.checkUpdates());
      expect(reports.single.status, WorkspaceUpdateStatus.updateAvailable);
      final managedId = workspace.current!.skills.single.id;
      await _completedValue(workspace.update(skillIds: {managedId}));
      expect(await activatedDocument.readAsString(), contains('Version two'));

      await environment.writeLocalVersion(3);
      final updateAllReports = await _completedValue(workspace.checkUpdates());
      expect(
        updateAllReports.single.status,
        WorkspaceUpdateStatus.updateAvailable,
      );
      await _completedValue(workspace.update());
      expect(await activatedDocument.readAsString(), contains('Version three'));

      await _tapWhenHitTestable(tester, find.byKey(const Key('remove-skill')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('remove-skill-dialog')),
      );
      await _tapWhenHitTestable(
        tester,
        find.byKey(const Key('remove-confirm')),
      );
      await _pumpUntilFound(tester, find.byKey(const Key('browser-empty')));
      expect(workspace.current?.skills, isEmpty);
      expect(await activatedDocument.exists(), isFalse);
    },
  );

  testWidgets(
    'real desktop UI confirms takeover of a dangling legacy activation link',
    (tester) async {
      final environment = await _E2eEnvironment.create('takeover-ui');
      final workspace = environment.createWorkspace();
      addTearDown(() async {
        await _unmountApp(tester);
        await workspace.close();
        await environment.close();
      });
      await _completionValue(workspace.open());
      await _completedValue(
        workspace.install(
          WorkspaceInstallRequest(
            source: SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: environment.localSource.path,
            ),
            scope: WorkspaceScope.global,
            storeOnly: true,
          ),
        ),
      );

      const slotKey = 'release-e2e';
      final activationPath = p.join(environment.globalSkills.path, slotKey);
      final legacyTarget = p.join(
        environment.root.path,
        'old-missing-repository',
        'skills',
        slotKey,
      );
      if (Platform.isWindows) {
        await _writeSkill(
          Directory(activationPath),
          name: 'Release E2E',
          description: 'Occupied Windows activation fixture.',
          body: 'Legacy occupied content.',
        );
      } else {
        await Link(activationPath).create(legacyTarget);
        expect(
          await FileSystemEntity.type(activationPath, followLinks: false),
          FileSystemEntityType.link,
        );
        expect(await Directory(legacyTarget).exists(), isFalse);
      }
      final e2eActivationTarget = (await _completedValue(
        workspace.inspectActivationTargets(scope: WorkspaceScope.global),
      )).singleWhere((target) => target.agentId == _E2eEnvironment.agentId);

      await _pumpWorkspaceApp(tester, workspace);
      // This fixture is stored but not activated, so it is listed in Inactive.
      await _selectMenuOption(
        tester,
        selector: find.byKey(const Key('scope-selector')),
        option: find.byKey(const Key('scope-option-inactive')),
      );
      await _tapWhenReady(tester, find.byKey(const Key('skill-$slotKey')));
      await _pumpUntilFound(tester, find.byKey(const Key('skill-detail')));
      await tester.tap(_findSkillSectionTab(LucideIcons.settings));
      final targetName = find.text(e2eActivationTarget.displayName);
      await _pumpUntilFound(tester, targetName);
      await tester.ensureVisible(targetName);
      await tester.pumpAndSettle();
      final activationGroup = find.ancestor(
        of: targetName,
        matching: find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('activation-group-');
        }),
      );
      final activationToggle = find
          .descendant(
            of: activationGroup,
            matching: find.byWidgetPredicate((widget) {
              final key = widget.key;
              return key is ValueKey<String> &&
                  key.value.startsWith('activation-toggle-');
            }),
          )
          .hitTestable();
      await _pumpUntilFound(tester, activationToggle);
      await tester.tap(activationToggle.first);
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('activation-takeover-dialog')),
      );

      expect(
        workspace.current?.findSkillBySlotKey(slotKey)?.activations,
        isEmpty,
      );
      if (Platform.isWindows) {
        expect(
          await File(p.join(activationPath, 'SKILL.md')).readAsString(),
          contains('Legacy occupied content'),
        );
      } else {
        expect(await Link(activationPath).target(), legacyTarget);
      }

      final takeoverConfirm = find.byKey(
        const Key('activation-takeover-confirm'),
      );
      await _pumpUntilFound(tester, takeoverConfirm.hitTestable());
      await tester.tap(takeoverConfirm);
      await _pumpUntilGone(
        tester,
        find.byKey(const Key('activation-takeover-dialog')),
      );
      await _pumpUntil(
        tester,
        () =>
            workspace.current
                ?.findSkillBySlotKey(slotKey)
                ?.activations
                .isNotEmpty ??
            false,
      );

      final activation = workspace.current
          ?.findSkillBySlotKey(slotKey)
          ?.activations
          .single;
      expect(activation?.location, environment.globalSkills.path);
      expect(
        await File(p.join(activationPath, 'SKILL.md')).readAsString(),
        contains('Version one'),
      );
    },
  );

  testWidgets(
    'real desktop UI adopts a read-only external Skill and reopens cleanly',
    (tester) async {
      final environment = await _E2eEnvironment.create('adopt-reopen-ui');
      if (Platform.isWindows) {
        await environment.writeExternalSkill();
      } else {
        await environment.writeReadOnlyExternalSkill();
      }
      final firstWorkspace = environment.createWorkspace();
      SkillsWorkspaceRepository? activeWorkspace = firstWorkspace;
      addTearDown(() async {
        await _unmountApp(tester);
        await activeWorkspace?.close();
        await environment.close();
      });

      await _pumpWorkspaceApp(tester, firstWorkspace);
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('empty-discover-skills')),
      );

      await tester.tap(find.byKey(const Key('empty-discover-skills')));
      // The review opens at a glance; the per-Skill list is one step away.
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('external-skills-ready')),
      );
      await _tapWhenReady(
        tester,
        find.byKey(const Key('external-skills-choose')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('external-candidate-external-release-e2e')),
      );
      final selection = find.byKey(
        const Key('external-select-external-release-e2e'),
      );
      await tester.tap(selection);
      await tester.pump();
      await tester.tap(selection);
      await tester.pump();
      const slotKey = 'external-release-e2e';
      // Taking over is the confirmation; there is no separate review page.
      await _tapWhenReady(
        tester,
        find.byKey(const Key('external-skills-adopt')),
      );
      final adoptionSuccess = find.byKey(const Key('external-skills-success'));
      final adoptionFailure = find.byKey(const Key('external-skills-failure'));
      await _pumpUntil(
        tester,
        () =>
            firstWorkspace.current?.findSkillBySlotKey(slotKey) != null ||
            adoptionFailure.evaluate().isNotEmpty,
        maxPumps: 800,
      );
      expect(
        adoptionFailure,
        findsNothing,
        reason: 'External adoption reached its explicit failure state.',
      );
      expect(
        firstWorkspace.current?.findSkillBySlotKey(slotKey),
        isNotNull,
        reason: 'External adoption did not publish a managed Skill.',
      );
      await _pumpUntilFound(tester, adoptionSuccess);

      final activatedDocument = File(
        p.join(environment.globalSkills.path, slotKey, 'SKILL.md'),
      );
      expect(
        await activatedDocument.readAsString(),
        contains('External content'),
      );
      expect(
        firstWorkspace.current?.findSkillBySlotKey(slotKey)?.source.kind,
        WorkspaceSourceKind.adoptedSnapshot,
      );
      expect(
        firstWorkspace.current?.findSkillBySlotKey(slotKey)?.activations,
        hasLength(1),
      );
      expect(adoptionFailure, findsNothing);

      await tester.tap(find.byKey(const Key('external-skills-done')));
      await _pumpUntilGone(
        tester,
        find.byKey(const Key('external-skills-dialog')),
      );
      await _pumpUntilFound(tester, find.byKey(const Key('skill-$slotKey')));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await firstWorkspace.close();
      activeWorkspace = null;

      final reopenedWorkspace = environment.createWorkspace();
      activeWorkspace = reopenedWorkspace;
      await _pumpWorkspaceApp(tester, reopenedWorkspace);
      await _pumpUntilFound(tester, find.byKey(const Key('skill-$slotKey')));

      expect(find.byKey(const Key('browser-failure')), findsNothing);
      expect(
        reopenedWorkspace.current?.findSkillBySlotKey(slotKey)?.source.kind,
        WorkspaceSourceKind.adoptedSnapshot,
      );
      expect(
        reopenedWorkspace.current?.findSkillBySlotKey(slotKey)?.activations,
        hasLength(1),
      );
      expect(
        await activatedDocument.readAsString(),
        contains('External content'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await reopenedWorkspace.close();
      activeWorkspace = null;
    },
  );

  testWidgets(
    'real App adapter handles project scope, adoption, and unmanaged collision',
    (tester) async {
      final environment = await _E2eEnvironment.create('adapter');
      final workspace = environment.createWorkspace();
      addTearDown(() async {
        await workspace.close();
        await environment.close();
      });
      await _completionValue(workspace.open());

      final installed = (await _completedValue(
        workspace.install(
          WorkspaceInstallRequest(
            source: SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: environment.localSource.path,
            ),
            scope: WorkspaceScope.global,
            storeOnly: true,
          ),
        ),
      ) as WorkspaceInstallCompleted).receipt;
      expect(installed.snapshot.skills.single.slotKey, 'release-e2e');

      await _completedValue(
        workspace.registerProjectRoot(
          path: environment.project.path,
          id: 'release-project',
        ),
      );
      final projectTarget = (await _completedValue(
        workspace.inspectActivationTargets(
          scope: WorkspaceScope.project,
          projectRootId: 'release-project',
        ),
      )).singleWhere((target) => target.agentId == _E2eEnvironment.agentId);
      final projectActivation = await _completedValue(
        workspace.activate(
          skillIds: {workspace.current!.findSkillBySlotKey('release-e2e')!.id},
          scope: WorkspaceScope.project,
          projectRootId: 'release-project',
          agentIds: {_E2eEnvironment.agentId},
        ),
      );
      final projectReceipt =
          (projectActivation as WorkspaceActivationCompleted).receipt;
      expect(projectReceipt.snapshot.skills.single.activations, hasLength(1));
      final projectDocument = File(
        p.join(projectTarget.location, 'release-e2e', 'SKILL.md'),
      );
      expect(await projectDocument.exists(), isTrue);

      final deactivated = await _completedValue(
        workspace.deactivate(
          skillIds: {workspace.current!.findSkillBySlotKey('release-e2e')!.id},
          locations: {projectTarget.location},
        ),
      );
      expect(deactivated.snapshot.skills.single.activations, isEmpty);
      expect(await projectDocument.exists(), isFalse);

      await environment.writeExternalSkill();
      final discovery = await _completedValue(
        workspace.discoverExternalSkills(),
      );
      final candidate = discovery.candidates.singleWhere(
        (candidate) => candidate.slotKey == 'external-release-e2e',
      );
      final adopted = await _completedValue(
        workspace.adopt(
          ExternalSkillAdoptionRequest(
            slotKey: candidate.slotKey,
            authoritativeLocation: candidate.locations.single,
            reviewedContentHashByLocation: {
              for (final location in candidate.locations)
                location: candidate.contentHash,
            },
          ),
        ),
      );
      expect(
        adopted.snapshot.findSkillBySlotKey(candidate.slotKey)?.source.kind,
        WorkspaceSourceKind.adoptedSnapshot,
      );

      final secondaryGlobalSkills = Directory(
        p.join(environment.root.path, 'secondary-conflict-skills'),
      );
      await secondaryGlobalSkills.create(recursive: true);
      await _completedValue(
        workspace.reconfigureAgentCatalog([
          _appAgentDefinition(
            id: _E2eEnvironment.agentId,
            displayName: 'Skills Manager Release E2E',
            globalSkillsPath: environment.globalSkills.path,
          ),
          _appAgentDefinition(
            id: 'skills-manager-conflict-e2e',
            displayName: 'Skills Manager Conflict E2E',
            globalSkillsPath: secondaryGlobalSkills.path,
          ),
        ]),
      );
      await _writeSkill(
        Directory(
          p.join(environment.globalSkills.path, 'divergent-release-e2e'),
        ),
        name: 'Divergent Release E2E',
        description: 'Authoritative divergent fixture.',
        body: 'Authoritative content A.',
      );
      await _writeSkill(
        Directory(p.join(secondaryGlobalSkills.path, 'divergent-release-e2e')),
        name: 'Divergent Release E2E',
        description: 'Secondary divergent fixture.',
        body: 'Secondary content B.',
      );
      final divergentDiscovery = await _completedValue(
        workspace.discoverExternalSkills(),
      );
      final divergentConflict = divergentDiscovery.conflicts.singleWhere(
        (conflict) => conflict.slotKey == 'divergent-release-e2e',
      );
      final authoritativeLocation = divergentConflict.locations.singleWhere(
        (location) => p.isWithin(environment.globalSkills.path, location),
      );
      final divergentAdoption = await _completedValue(
        workspace.adopt(
          ExternalSkillAdoptionRequest(
            slotKey: divergentConflict.slotKey,
            authoritativeLocation: authoritativeLocation,
            reviewedContentHashByLocation:
                divergentConflict.contentHashByLocation,
          ),
        ),
      );
      final divergentSkill = divergentAdoption.snapshot.findSkillBySlotKey(
        divergentConflict.slotKey,
      );
      expect(divergentSkill?.source.kind, WorkspaceSourceKind.adoptedSnapshot);
      expect(divergentSkill?.activations, hasLength(2));
      for (final location in divergentConflict.locations) {
        expect(
          await File(p.join(location, 'SKILL.md')).readAsString(),
          contains('Authoritative content A'),
        );
      }

      await environment.writeCollisionFixtures();
      final collision = await _completedValue(
        workspace.install(
          WorkspaceInstallRequest(
            source: SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: environment.collisionSource.path,
            ),
            scope: WorkspaceScope.global,
            agentIds: const {_E2eEnvironment.agentId},
          ),
        ),
      );
      // Occupied install targets now require an explicit takeover review.
      // Receiving the draft must not install the Skill or overwrite its target.
      expect(collision, isA<WorkspaceInstallTakeoverRequired>());
      final collisionTargets =
          (collision as WorkspaceInstallTakeoverRequired).draft.targets;
      expect(collisionTargets, hasLength(1));
      expect(collisionTargets.single.slotKey, 'collision-release-e2e');
      expect(
        collisionTargets.single.targetPath,
        p.join(environment.globalSkills.path, 'collision-release-e2e'),
      );
      expect(
        collisionTargets.single.kind,
        WorkspaceActivationTargetOccupancyKind.skillDirectory,
      );
      expect(
        workspace.current?.findSkillBySlotKey('collision-release-e2e'),
        isNull,
      );
      expect(
        await File(
          p.join(
            environment.globalSkills.path,
            'collision-release-e2e',
            'SKILL.md',
          ),
        ).readAsString(),
        contains('Existing content.'),
      );
      expect(
        await File(
          p.join(
            environment.globalSkills.path,
            'collision-release-e2e',
            'sentinel.txt',
          ),
        ).readAsString(),
        'preserve me',
      );

      final removed = await _completedValue(
        workspace.remove(
          skillIds: {
            workspace.current!.findSkillBySlotKey('release-e2e')!.id,
            workspace.current!.findSkillBySlotKey('external-release-e2e')!.id,
            workspace.current!.findSkillBySlotKey('divergent-release-e2e')!.id,
          },
          expectedRevision: workspace.current!.revision,
        ),
      );
      expect(removed.snapshot.skills, isEmpty);
    },
  );

  testWidgets(
    'real App adapter resumes committed finalization after reopening',
    (tester) async {
      final environment = await _E2eEnvironment.create('finalization-reopen');
      var workspace = environment.createWorkspace();
      addTearDown(() async {
        await workspace.close();
        await environment.close();
      });
      await _completionValue(workspace.open());
      final installed = (await _completedValue(
        workspace.install(
          WorkspaceInstallRequest(
            source: SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: environment.localSource.path,
            ),
            scope: WorkspaceScope.global,
            storeOnly: true,
          ),
        ),
      ) as WorkspaceInstallCompleted).receipt;
      final managedId = installed.snapshot.skills.single.id;

      final blocker = await environment.blockControlPlaneBackupPublication();
      final completion = await workspace
          .setFavorite(skillId: managedId, isFavorite: true)
          .completed;
      await blocker.restore();
      final pending = switch (completion) {
        WorkspaceCommittedPending<SkillsWorkspaceSnapshot>() => completion,
        WorkspaceCompleted<SkillsWorkspaceSnapshot>() => throw TestFailure(
          'The injected finalization fault did not produce committed-pending.',
        ),
        WorkspaceFailed<SkillsWorkspaceSnapshot>(:final failure) =>
          throw TestFailure(
            'The operation failed before commit: '
            '${failure.operation.name}/${failure.code.name} '
            '${failure.context}',
          ),
      };
      expect(pending.committedRevision, workspace.current!.revision);
      expect(workspace.current!.findSkillById(managedId)?.isFavorite, isTrue);

      await workspace.close();
      workspace = environment.createWorkspace();
      final reopened = await _completionValue(workspace.open());

      expect(
        reopened.revision,
        greaterThanOrEqualTo(pending.committedRevision),
      );
      expect(reopened.findSkillById(managedId)?.isFavorite, isTrue);
      await _completedValue(workspace.resumeFinalizationRecovery());
    },
  );

  testWidgets(
    'real App adapter persists Library data and preserves identity on source replacement',
    (tester) async {
      final environment = await _E2eEnvironment.create('library-replace');
      final replacementSource = Directory(
        p.join(environment.root.path, 'replacement-source'),
      );
      final secondarySkills = Directory(
        p.join(environment.root.path, 'secondary-global-skills'),
      );
      await secondarySkills.create(recursive: true);
      await _writeSkill(
        replacementSource,
        name: 'Release E2E',
        description: 'Replacement source fixture.',
        body: 'Replacement content.',
      );

      var workspace = environment.createWorkspace();
      addTearDown(() async {
        await workspace.close();
        await environment.close();
      });
      await _completionValue(workspace.open());
      final installed = (await _completedValue(
        workspace.install(
          WorkspaceInstallRequest(
            source: SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: environment.localSource.path,
            ),
            scope: WorkspaceScope.global,
            storeOnly: true,
          ),
        ),
      ) as WorkspaceInstallCompleted).receipt;
      final managedId = installed.snapshot.skills.single.id;

      await _completedValue(
        workspace.setFavorite(skillId: managedId, isFavorite: true),
      );
      await _completedValue(
        workspace.saveNote(skillId: managedId, note: 'Personal workflow note'),
      );
      final replaced = await _completedValue(
        workspace.replaceSource(
          skillId: managedId,
          source: SkillSourceInput(
            kind: WorkspaceSourceKind.local,
            locator: replacementSource.path,
          ),
          expectedRevision: workspace.current!.revision,
        ),
      );
      final replacedSkill = replaced.snapshot.findSkillById(managedId)!;
      expect(replacedSkill.id, managedId);
      expect(replacedSkill.isFavorite, isTrue);
      expect(replacedSkill.note, 'Personal workflow note');
      expect(
        await _completionValue(
          workspace.readSkillDocument(
            managedId,
            'SKILL.md',
            expectedContentHash: workspace.current!
                .findSkillById(managedId)!
                .currentRevision
                .contentHash,
          ),
        ),
        contains('Replacement content'),
      );

      await _completedValue(
        workspace.reconfigureAgentCatalog([
          _appAgentDefinition(
            id: _E2eEnvironment.agentId,
            displayName: 'Skills Manager Release E2E',
            globalSkillsPath: environment.globalSkills.path,
          ),
          _appAgentDefinition(
            id: 'skills-manager-secondary-e2e',
            displayName: 'Skills Manager Secondary E2E',
            globalSkillsPath: secondarySkills.path,
          ),
        ]),
      );
      final reconfiguredTargets = await _completedValue(
        workspace.inspectActivationTargets(scope: WorkspaceScope.global),
      );
      expect(
        reconfiguredTargets.map((target) => target.agentId),
        containsAll({_E2eEnvironment.agentId, 'skills-manager-secondary-e2e'}),
      );

      await workspace.close();
      workspace = environment.createWorkspace();
      final reopened = await _completionValue(workspace.open());
      final persisted = reopened.findSkillById(managedId)!;
      expect(persisted.id, managedId);
      expect(persisted.isFavorite, isTrue);
      expect(persisted.note, 'Personal workflow note');
      expect(
        await _completionValue(
          workspace.readSkillDocument(
            managedId,
            'SKILL.md',
            expectedContentHash: workspace.current!
                .findSkillById(managedId)!
                .currentRevision
                .contentHash,
          ),
        ),
        contains('Replacement content'),
      );

      final removed = await _completedValue(
        workspace.remove(
          skillIds: {managedId},
          expectedRevision: workspace.current!.revision,
        ),
      );
      expect(removed.snapshot.findSkillById(managedId), isNull);

      await workspace.close();
      workspace = environment.createWorkspace();
      final reopenedAfterRemoval = await _completionValue(workspace.open());
      expect(reopenedAfterRemoval.findSkillById(managedId), isNull);

      final reinstalled = (await _completedValue(
        workspace.install(
          WorkspaceInstallRequest(
            source: SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: environment.localSource.path,
            ),
            scope: WorkspaceScope.global,
            storeOnly: true,
          ),
        ),
      ) as WorkspaceInstallCompleted).receipt;
      final freshSkill = reinstalled.snapshot.skills.single;
      expect(freshSkill.id, isNot(managedId));
      expect(freshSkill.isFavorite, isFalse);
      expect(freshSkill.note, isNull);
    },
  );
}

WorkspaceAgentDefinition _appAgentDefinition({
  required String id,
  required String displayName,
  required String globalSkillsPath,
}) => WorkspaceAgentDefinition(
  id: id,
  displayName: displayName,
  platforms: {
    for (final platform in WorkspaceDesktopPlatform.values)
      platform: WorkspaceAgentPlatformDefinition(
        globalSkillsPath: globalSkillsPath,
      ),
  },
);

Future<T> _completedValue<T>(WorkspaceTask<T> task) async {
  final completion = await task.completed;
  return switch (completion) {
    WorkspaceCompleted(:final value) => value,
    WorkspaceFailed(:final failure) => throw TestFailure(
      'Workspace operation failed: ${failure.operation.name}/'
      '${failure.code.name} ${failure.context}',
    ),
    WorkspaceCommittedPending(:final operationId, :final committedRevision) =>
      throw TestFailure(
        'Workspace operation $operationId committed revision '
        '$committedRevision but finalization is pending.',
      ),
  };
}

Future<T> _completionValue<T>(Future<WorkspaceCompletion<T>> completion) async {
  return switch (await completion) {
    WorkspaceCompleted(:final value) => value,
    WorkspaceFailed(:final failure) => throw TestFailure(
      'Workspace operation failed: ${failure.operation.name}/'
      '${failure.code.name} ${failure.context}',
    ),
    WorkspaceCommittedPending(:final operationId, :final committedRevision) =>
      throw TestFailure(
        'Workspace operation $operationId committed revision '
        '$committedRevision but finalization is pending.',
      ),
  };
}

Future<void> _pumpWorkspaceApp(
  WidgetTester tester,
  SkillsWorkspaceRepository workspace,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialSkillListLayoutProvider.overrideWithValue(SkillListLayout.list),
        skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
        skillBrowserRepositoryProvider.overrideWithValue(
          WorkspaceSkillBrowserRepository(workspace),
        ),
        skillAcquisitionRepositoryProvider.overrideWithValue(
          WorkspaceSkillAcquisitionRepository(
            workspace: workspace,
            resolver: SkillSourceLocatorResolver(),
          ),
        ),
        desktopSupportedProvider.overrideWithValue(true),
        appNotificationPresenterProvider.overrideWithValue(
          const _NoopNotificationPresenter(),
        ),
        appTranslationRepositoryProvider.overrideWithValue(
          fakeAppTranslationRepository(),
        ),
        activeTranslationRequestProvider.overrideWith((ref) {
          return _activeTranslationRequest(
            ref.watch(skillBrowserViewModelProvider),
          );
        }),
      ],
      child: const SkillsManagerApp(locale: Locale('en')),
    ),
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 800,
}) async {
  for (var attempt = 0; attempt < maxPumps; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 25));
    if (finder.evaluate().isNotEmpty) return;
  }
  // Name what is on screen instead, so a CI-only timeout can be diagnosed
  // without a widget tree dump.
  final keys =
      find
          .byWidgetPredicate((widget) => widget.key is ValueKey<String>)
          .evaluate()
          .map((element) => (element.widget.key! as ValueKey<String>).value)
          .toSet()
          .toList()
        ..sort();
  final barriers = find.byType(ModalBarrier).evaluate().length;
  final texts = find
      .byType(Text)
      .hitTestable()
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .toSet()
      .toList();
  throw TestFailure(
    'Timed out waiting for $finder.\n'
    'Modal barriers: $barriers. Visible texts: $texts\n'
    'Keyed widgets on screen: $keys',
  );
}

/// Opens the menu behind [selector] and taps [option]. Right after a cold
/// launch the browser can rebuild while the menu is opening, which closes it
/// again, so the menu is reopened when the option never shows up.
Future<void> _selectMenuOption(
  WidgetTester tester, {
  required Finder selector,
  required Finder option,
}) async {
  for (var attempt = 0; attempt < 5; attempt += 1) {
    await _tapWhenReady(tester, selector);
    for (var pumps = 0; pumps < 80; pumps += 1) {
      await tester.pump(const Duration(milliseconds: 25));
      if (option.evaluate().isNotEmpty) {
        await _tapWhenReady(tester, option);
        // The menu closes with a morph; a tap that lands on the list before
        // it is gone only dismisses the menu and never reaches the row.
        await _pumpUntilGone(tester, option);
        return;
      }
    }
  }
  throw TestFailure('The menu never offered $option.');
}

/// Taps once [finder] can receive the tap. The acquisition dialog grows with
/// AnimatedSize as each step appears, so a button can exist before it is
/// inside the dialog's clip. Unlike [_tapWhenHitTestable] it never settles,
/// so it is safe while a spinner is still animating.
Future<void> _tapWhenReady(WidgetTester tester, Finder finder) async {
  await _pumpUntilFound(tester, finder.hitTestable());
  await tester.tap(finder);
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 800,
}) async {
  for (var attempt = 0; attempt < maxPumps; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 25));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('Timed out waiting for the widget to close.');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 400,
}) async {
  for (var attempt = 0; attempt < maxPumps; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 25));
    if (condition()) return;
  }
  throw TestFailure('Timed out waiting for the expected state.');
}

Future<void> _tapWhenHitTestable(WidgetTester tester, Finder finder) async {
  await _pumpUntilFound(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final target = finder.hitTestable();
  await _pumpUntilFound(tester, target);
  await tester.tap(target.first);
  await tester.pump();
}

Future<void> _unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Finder _findSkillSectionTab(IconData icon) => find.descendant(
  of: find.byKey(const Key('skill-section-tabs')),
  matching: find.byIcon(icon),
);

bool _visibleMarkdownContains(WidgetTester tester, String text) {
  final finder = find.byKey(const Key('skill-markdown'));
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<MarkdownWidget>(finder).markdown.markdown.contains(text);
}

SourceDocument? _activeTranslationRequest(SkillBrowserState browser) {
  final skill = browser.selectedSkill;
  final document = browser.document;
  final path = browser.selectedDocumentPath;
  if (skill == null || document == null || path == null) return null;
  return SourceDocument(
    slotKey: skill.slotKey,
    contentHash: skill.contentHash,
    documentIdentifier: path,
    content: document,
  );
}

final class _NoopNotificationPresenter implements AppNotificationPresenter {
  const _NoopNotificationPresenter();

  @override
  void present(AppNotificationPresentation presentation) {}

  @override
  void dismissAll() {}

  @override
  void dispose() {}
}

final class _E2eEnvironment {
  _E2eEnvironment._({
    required this.root,
    required this.workspaceRoot,
    required this.agentHome,
    required this.globalSkills,
    required this.project,
    required this.localSource,
    required this.collisionSource,
    required this.detectionMarker,
    required this.agent,
  });

  static const agentId = 'skills-manager-release-e2e';

  final Directory root;
  final Directory workspaceRoot;
  final Directory agentHome;
  final Directory globalSkills;
  final Directory project;
  final Directory localSource;
  final Directory collisionSource;
  final File detectionMarker;
  final package_workspace.AgentDefinition agent;

  static Future<_E2eEnvironment> create(String suffix) async {
    final root = await Directory.systemTemp.createTemp(
      'skills-manager-release-$suffix-',
    );
    final workspaceRoot = Directory(p.join(root.path, 'workspace'));
    final agentHome = Directory(p.join(root.path, 'agent-home'));
    final globalSkills = Directory(p.join(root.path, 'global-skills'));
    final project = Directory(p.join(root.path, 'project'));
    final localSource = Directory(p.join(root.path, 'local-source'));
    final collisionSource = Directory(p.join(root.path, 'collision-source'));
    final detectionMarker = File(p.join(root.path, 'agent-detected'));
    await Future.wait([
      globalSkills.create(recursive: true),
      project.create(recursive: true),
      detectionMarker.writeAsString('detected'),
    ]);
    await Directory(p.join(project.path, '.agent-skills')).create();
    await _writeSkill(
      localSource,
      name: 'Release E2E',
      description: 'Real Skills Manager desktop integration fixture.',
      body: 'Version one content.',
    );
    final reference = File(p.join(localSource.path, 'references', 'guide.md'));
    await reference.parent.create(recursive: true);
    await reference.writeAsString(
      '# Reference Guide\n\nReference content.\n',
      flush: true,
    );
    final platform = package_workspace.AgentPlatformDefinition(
      globalSkillsPath: globalSkills.path,
      projectSkillsPath: p.join('.agent-skills', 'skills'),
      detectionPaths: [
        package_workspace.AgentDetectionPath.absolute(detectionMarker.path),
        package_workspace.AgentDetectionPath.projectRelative('.agent-skills'),
      ],
    );
    final agent = package_workspace.AgentDefinition(
      id: agentId,
      displayName: 'Skills Manager Release E2E',
      platforms: {
        for (final desktop in package_workspace.DesktopPlatform.values)
          desktop: platform,
      },
    );
    return _E2eEnvironment._(
      root: root,
      workspaceRoot: workspaceRoot,
      agentHome: agentHome,
      globalSkills: globalSkills,
      project: project,
      localSource: localSource,
      collisionSource: collisionSource,
      detectionMarker: detectionMarker,
      agent: agent,
    );
  }

  PackageSkillsWorkspaceRepository createWorkspace() =>
      PackageSkillsWorkspaceRepository.create(
        configuration: package_workspace.SkillsRepositoryConfiguration(
          rootPath: workspaceRoot.absolute.path,
          agentHomePath: agentHome.absolute.path,
          defaultLockWaitPolicy: package_workspace.LockWaitPolicy.wait(
            timeout: const Duration(seconds: 10),
          ),
          additionalAgents: [agent],
        ),
      );

  Future<void> writeLocalVersion(int version) => _writeSkill(
    localSource,
    name: 'Release E2E',
    description: 'Real Skills Manager desktop integration fixture.',
    body:
        'Version ${switch (version) {
          1 => 'one',
          2 => 'two',
          3 => 'three',
          _ => throw ArgumentError.value(version, 'version'),
        }} content.',
  );

  Future<_ControlPlaneBackupBlocker>
  blockControlPlaneBackupPublication() async {
    final epochDirectory = Directory(
      p.join(workspaceRoot.path, 'control-plane-backups', '0'),
    );
    final parkedDirectory = Directory('${epochDirectory.path}.e2e-parked');
    expect(await epochDirectory.exists(), isTrue);
    await epochDirectory.rename(parkedDirectory.path);
    final blocker = File(epochDirectory.path);
    await blocker.writeAsString('finalization fault fixture', flush: true);
    return _ControlPlaneBackupBlocker(
      blocker: blocker,
      parkedDirectory: parkedDirectory,
      restoredDirectory: epochDirectory,
    );
  }

  Future<void> writeExternalSkill() => _writeSkill(
    Directory(p.join(globalSkills.path, 'external-release-e2e')),
    name: 'External Release E2E',
    description: 'External Skill adoption fixture.',
    body: 'External content.',
  );

  Future<void> writeReadOnlyExternalSkill() async {
    await writeExternalSkill();
    final directory = Directory(
      p.join(globalSkills.path, 'external-release-e2e'),
    );
    final document = File(p.join(directory.path, 'SKILL.md'));
    await _runChmod(['0444', document.path], targetPath: document.path);
    await _runChmod(['0555', directory.path], targetPath: directory.path);
    expect((await document.stat()).mode & 0x1ff, 0x124);
    expect((await directory.stat()).mode & 0x1ff, 0x16d);
  }

  Future<void> writeCollisionFixtures() async {
    await _writeSkill(
      collisionSource,
      name: 'Collision Release E2E',
      description: 'Incoming managed Skill.',
      body: 'Incoming content.',
    );
    final occupied = Directory(
      p.join(globalSkills.path, 'collision-release-e2e'),
    );
    await _writeSkill(
      occupied,
      name: 'Collision Release E2E',
      description: 'Existing unmanaged Skill.',
      body: 'Existing content.',
    );
    await File(p.join(occupied.path, 'sentinel.txt'))
        .writeAsString('preserve me');
  }

  Future<void> close() async {
    if (!await root.exists()) return;
    if (Platform.isWindows) {
      await _makeWindowsTreeWritable(root.path);
    } else {
      await _runChmod(['-R', 'u+w', root.path], targetPath: root.path);
    }
    FileSystemException? lastFailure;
    final attempts = Platform.isWindows ? 20 : 1;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      try {
        if (await root.exists()) await root.delete(recursive: true);
        return;
      } on FileSystemException catch (error) {
        lastFailure = error;
        if (!Platform.isWindows) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw lastFailure!;
  }
}

final class _ControlPlaneBackupBlocker {
  _ControlPlaneBackupBlocker({
    required this.blocker,
    required this.parkedDirectory,
    required this.restoredDirectory,
  });

  final File blocker;
  final Directory parkedDirectory;
  final Directory restoredDirectory;
  bool _restored = false;

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    if (await blocker.exists()) await blocker.delete();
    if (await parkedDirectory.exists()) {
      await parkedDirectory.rename(restoredDirectory.path);
    }
  }
}

Future<void> _makeWindowsTreeWritable(String rootPath) async {
  final rootResult = await Process.run('attrib', ['-R', rootPath]);
  if (rootResult.exitCode != 0) {
    throw FileSystemException(
      'Unable to make the temporary root writable.',
      rootPath,
    );
  }
  final treeResult = await Process.run('attrib', [
    '-R',
    p.join(rootPath, '*'),
    '/S',
    '/D',
  ]);
  if (treeResult.exitCode != 0) {
    throw FileSystemException(
      'Unable to make temporary files writable.',
      rootPath,
    );
  }
}

Future<void> _runChmod(
  List<String> arguments, {
  required String targetPath,
}) async {
  final result = await Process.run('chmod', arguments);
  if (result.exitCode != 0) {
    throw FileSystemException('chmod failed: ${result.stderr}', targetPath);
  }
}

Future<void> _writeSkill(
  Directory directory, {
  required String name,
  required String description,
  required String body,
}) async {
  await directory.create(recursive: true);
  await File(p.join(directory.path, 'SKILL.md')).writeAsString(
    '---\n'
    'name: $name\n'
    'description: $description\n'
    '---\n\n'
    '# $name\n\n'
    '$body\n',
    flush: true,
  );
}
