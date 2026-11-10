import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/presentation/view_models/installed_agent_filter.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_location_label.dart';
import 'package:skills_manager/features/skills/presentation/widgets/agent_logo.dart';
import 'package:skills_manager/features/skills/presentation/widgets/skill_document_browser_popover.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_manager/features/translation/presentation/view_models/translation_scope_preference.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/platform/file_location_opener.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_frame.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_header.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';
import 'package:skills_translation/skills_translation.dart';

import '../../../../support/fake_skill_acquisition_repository.dart';
import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_app_translation_repository.dart';
import '../../../../support/fake_directory_picker.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/skills_manager_test_app.dart';
import '../../../../support/skill_drift_test_support.dart';

final class _TranslationWarningPresenter implements AppNotificationPresenter {
  final presentations = <AppNotificationPresentation>[];

  @override
  void present(AppNotificationPresentation presentation) =>
      presentations.add(presentation);

  @override
  void dismissAll() {}

  @override
  void dispose() {}
}

void main() {
  final commandLineCatalog = InstalledSkillCatalog(
    revision: 1,
    skills: [
      for (final slotKey in ['alpha', 'beta', 'gamma'])
        testSkill(
          slotKey: slotKey,
          displayName: slotKey,
          activations: globalActivation(),
        ),
    ],
  );

  Future<CommandLineActivitySession> beginActivating(
    WidgetTester tester,
    SkillListLayout layout,
  ) async {
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: commandLineCatalog,
        ),
        initialSkillListLayout: layout,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('skill-alpha'))),
    );
    return container
        .read(commandLineActivityProvider.notifier)
        .begin(
          kind: CommandLineActivityKind.activate,
          items: const [
            CommandLineActivityItem(skillId: 'alpha', slotKey: 'alpha'),
            CommandLineActivityItem(skillId: 'beta', slotKey: 'beta'),
          ],
        );
  }

  for (final layout in SkillListLayout.values) {
    testWidgets('in the ${layout.name} layout, a card glows while the command '
        'line works on its Skill, and finishes arriving before it fades', (
      tester,
    ) async {
      List<BoxShadow> shadowsOf(String slotKey) {
        final frame = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byKey(Key('skill-$slotKey')),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (frame.decoration as ShapeDecoration).shadows ?? const [];
      }

      final glowCount = AppShadows.commandLineGlow(opacity: 1).length;
      final session = await beginActivating(tester, layout);
      session.start('beta');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(shadowsOf('beta'), hasLength(glowCount));
      expect(shadowsOf('alpha'), isEmpty);
      expect(shadowsOf('gamma'), isEmpty);

      // Finished at once, the glow still finishes arriving.
      session.finish('beta', CommandLineItemStatus.succeeded);
      session.end();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(shadowsOf('beta'), hasLength(glowCount));

      // Fully arrived after 1s, it fades over 0.8s.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 800));
      expect(shadowsOf('beta'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  final originalPreferencesPlatform = SharedPreferencesAsyncPlatform.instance;
  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDownAll(() {
    SharedPreferencesAsyncPlatform.instance = originalPreferencesPlatform;
  });

  testWidgets(
    'unconfigured translate button shows a warning instead of consent',
    (tester) async {
      final presenter = _TranslationWarningPresenter();
      final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha');
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
            documents: {'alpha': '# Alpha'},
          ),
          translationRepository: fakeAppTranslationRepository(
            settingsStore: MemoryTranslationSettingsStore(),
          ),
          notificationPresenter: presenter,
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill-language-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('translation-confirmation')), findsNothing);
      expect(presenter.presentations, hasLength(1));
      expect(
        presenter.presentations.single.content.message,
        'Configure a Translation Provider in Settings first.',
      );
      expect(
        presenter.presentations.single.content.severity,
        AppNotificationSeverity.warning,
      );
    },
  );

  testWidgets('shows loading and then the empty repository state', (
    tester,
  ) async {
    final completer = Completer<InstalledSkillCatalog>();
    final repository = FakeSkillBrowserRepository()
      ..openHandler = () => completer.future;

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );

    expect(find.byKey(const Key('browser-loading')), findsOneWidget);
    expect(find.byType(Shimmer), findsWidgets);

    completer.complete(InstalledSkillCatalog(revision: 0, skills: const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('browser-empty')), findsOneWidget);
  });

  testWidgets('uses the compact desktop content column width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha Skill')],
      ),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('installed-header-column'))).width,
      AppSizes.contentColumnWidth,
    );
  });

  testWidgets('shows the cached translated description in the Skill list', (
    tester,
  ) async {
    final skill = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      activations: globalActivation(),
    );
    final cache = MemoryTranslationCache();
    final cacheReads = <TranslationCacheKey>[];
    cache.readHandler = (key) async {
      cacheReads.add(key);
      return cache.values[key];
    };
    cache.values[TranslationCacheKey(
      slotKey: skill.slotKey,
      contentHash: skill.contentHash,
      documentIdentifier: 'SKILL.md',
      targetLanguage: TargetLanguage('zh-Hans'),
    )] = CompletedTranslation(
      slotKey: skill.slotKey,
      contentHash: skill.contentHash,
      documentIdentifier: 'SKILL.md',
      targetLanguage: TargetLanguage('zh-Hans'),
      translatedContent: '''---
description: 已翻译的描述
---
# 已翻译的正文''',
      provenance: TranslationProvenance(providerIdentifier: 'cache'),
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
        ),
        translationRepository: fakeAppTranslationRepository(cache: cache),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('skill-alpha')), findsOneWidget);
    expect(cacheReads, hasLength(1));
    expect(find.text('已翻译的描述'), findsOneWidget);
    expect(find.text('Alpha Skill description'), findsNothing);
  });

  testWidgets('preloads every catalog description before the grid scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skills = List.generate(40, (index) {
      final suffix = index.toString().padLeft(2, '0');
      return testSkill(
        slotKey: 'catalog-$suffix',
        displayName: 'Skill $suffix',
        activations: globalActivation(),
      );
    });
    final cache = MemoryTranslationCache();
    for (final skill in skills) {
      cache.values.addAll(
        _cachedTranslationFor(skill, '''---
description: 缓存描述 ${skill.slotKey}
---
# 已翻译的正文''').values,
      );
    }

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: skills),
        ),
        translationRepository: fakeAppTranslationRepository(cache: cache),
        initialSkillListLayout: SkillListLayout.cards,
      ),
    );
    await tester.pumpAndSettle();

    final grid = find.byKey(const Key('skill-card-grid'));
    final bottomCard = find.byKey(Key('skill-${skills.last.slotKey}'));
    expect(grid, findsOneWidget);
    expect(bottomCard, findsNothing);
    expect(
      cache.readKeys.map((key) => key.slotKey).toSet(),
      unorderedEquals(skills.map((skill) => skill.slotKey)),
    );
    final readCount = cache.readKeys.length;
    final scrollable = find.ancestor(
      of: grid,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(bottomCard, 400, scrollable: scrollable);
    await tester.pumpAndSettle();

    expect(cache.readKeys, hasLength(readCount));
    expect(bottomCard.hitTestable(), findsOneWidget);
    expect(
      find.descendant(
        of: bottomCard,
        matching: find.text('缓存描述 ${skills.last.slotKey}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hovering a card lifts it and leaving restores its scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(
            revision: 1,
            skills: [
              testSkill(
                slotKey: 'alpha',
                displayName: 'Alpha Skill',
                activations: globalActivation(),
              ),
            ],
          ),
        ),
        initialSkillListLayout: SkillListLayout.cards,
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('skill-alpha'));
    final transform = find
        .descendant(of: card, matching: find.byType(Transform))
        .first;
    expect(tester.widget<Transform>(transform).transform.entry(0, 0), 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(card));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Transform>(transform).transform.entry(0, 0),
      greaterThan(1),
    );

    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(tester.widget<Transform>(transform).transform.entry(0, 0), 1);
  });

  testWidgets(
    'pressing a card holds it half lifted, but not through its switch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(
              revision: 1,
              skills: [
                testSkill(
                  slotKey: 'alpha',
                  displayName: 'Alpha Skill',
                  activations: globalActivation(),
                ),
              ],
            ),
          ),
          workspaceRepository: FakeSkillsWorkspaceRepository(
            globalTargets: _sharedGlobalTargets,
          ),
          initialSkillListLayout: SkillListLayout.cards,
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('skill-alpha'));
      final transform = find
          .descendant(of: card, matching: find.byType(Transform))
          .first;
      double scale() =>
          tester.widget<Transform>(transform).transform.entry(0, 0);

      // Hovered, then held: the card settles to half its lift before the tap's
      // press timeout, instead of waiting for release.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(card));
      await tester.pumpAndSettle();
      expect(scale(), greaterThan(1));
      await mouse.down(tester.getCenter(card));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      // Cards lift by 2%, so a press holds them at 1%.
      expect(scale(), closeTo(1.01, 0.0001));
      await mouse.cancel();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(scale(), 1);

      // A press on the activation switch presses the switch, not the card.
      await tester.tap(find.byKey(const Key('agent-selector')));
      await tester.pumpAndSettle();
      await tester.tap(_locationOption('/global/.agents/skills'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('skill-activation-toggle-alpha'));
      final press = await tester.startGesture(tester.getCenter(toggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(scale(), 1);
      await press.cancel();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('filters Favorites from the authoritative Installed projection', (
    tester,
  ) async {
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [
          testSkill(
            slotKey: 'alpha',
            displayName: 'Alpha Favorite',
            isFavorite: true,
            activations: globalActivation(),
          ),
          testSkill(
            slotKey: 'beta',
            displayName: 'Beta Regular',
            activations: globalActivation(),
          ),
        ],
      ),
      documents: const {'alpha': '# Alpha', 'beta': '# Beta'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        workspaceRepository: FakeSkillsWorkspaceRepository(
          globalTargets: _sharedGlobalTargets,
        ),
        initialLocation: '/favorites',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha Favorite'), findsOneWidget);
    expect(find.text('Beta Regular'), findsNothing);
    expect(find.byKey(const Key('agent-selector')), findsOneWidget);
    expect(find.byKey(const Key('scope-selector')), findsOneWidget);

    await tester.tap(find.byKey(const Key('agent-selector')));
    await tester.pumpAndSettle();
    await tester.tap(_locationOption('/global/.agents/skills'));
    await tester.pumpAndSettle();
    // A favorite enabled at another Global location remains manageable;
    // selecting an Agent must not include non-favorites.
    expect(find.byKey(const Key('skill-alpha')), findsOneWidget);
    expect(find.byKey(const Key('skill-beta')), findsNothing);
    expect(
      tester
          .widget<AgentActivationSwitch>(
            find.byKey(const Key('skill-activation-toggle-alpha')),
          )
          .on,
      isFalse,
    );
  });

  testWidgets('marks favorite and updatable Skills in the list', (
    tester,
  ) async {
    final alpha = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Favorite',
      isFavorite: true,
      activations: globalActivation(),
    );
    final beta = testSkill(
      slotKey: 'beta',
      displayName: 'Beta Regular',
      activations: globalActivation(),
    );
    WorkspaceSkill managed(InstalledSkill skill) => WorkspaceSkill(
      id: skill.id,
      slotKey: skill.slotKey,
      declaredName: skill.slotKey,
      displayName: skill.displayName,
      description: 'Test skill',
      source: SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/skills/${skill.slotKey}',
      ),
      currentRevision: SkillRevision(
        contentHash: 'hash-${skill.slotKey}',
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime.utc(2026),
      ),
      activations: const [],
      isFavorite: skill.isFavorite,
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 5, skills: [alpha, beta]),
          documents: const {'alpha': '# Alpha', 'beta': '# Beta'},
        ),
        workspaceRepository: FakeSkillsWorkspaceRepository(
          globalTargets: _sharedGlobalTargets,
          snapshot: SkillsWorkspaceSnapshot(
            revision: 5,
            projectRoots: const [],
            skills: [managed(alpha), managed(beta)],
          ),
          updateReports: [
            WorkspaceUpdateReport(
              skillId: beta.id,
              status: WorkspaceUpdateStatus.updateAvailable,
            ),
          ],
        ),
        startupUpdateSweep: true,
      ),
    );
    await tester.pumpAndSettle();

    Icon iconOf(String key) => tester.widget<Icon>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Icon)),
    );
    expect(iconOf('skill-favorite-alpha').icon, LucideIcons.star);
    expect(iconOf('skill-favorite-alpha').color, AppColors.warning);
    expect(find.byKey(const Key('skill-favorite-beta')), findsNothing);
    expect(
      iconOf('skill-update-available-beta').icon,
      LucideIcons.circleArrowUp,
    );
    expect(iconOf('skill-update-available-beta').color, AppColors.success);
    expect(find.byKey(const Key('skill-update-available-alpha')), findsNothing);
  });

  testWidgets('matches page breadcrumbs to their sidebar destinations', (
    tester,
  ) async {
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [
          testSkill(
            slotKey: 'alpha',
            displayName: 'Alpha Favorite',
            isFavorite: true,
            activations: globalActivation(),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );
    await tester.pumpAndSettle();

    final breadcrumb = find.byKey(const Key('installed-breadcrumb'));
    expect(
      find.descendant(of: breadcrumb, matching: find.text('Workspace')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: breadcrumb,
        matching: find.byIcon(LucideIcons.squareLibrary),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('nav-item-favorites')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: breadcrumb, matching: find.text('Workspace')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: breadcrumb, matching: find.byIcon(LucideIcons.star)),
      findsOneWidget,
    );
  });

  testWidgets('filters a shared activation as Universal Agents', (
    tester,
  ) async {
    final skill = WorkspaceSkill(
      id: WorkspaceSkillId('shared'),
      slotKey: 'shared',
      declaredName: 'Shared',
      displayName: 'Shared Skill',
      description: 'Shared description',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/source/shared',
      ),
      currentRevision: SkillRevision(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime.utc(2026),
      ),
      activations: [
        SkillActivationLocation(
          location: '/global/.agents/skills',
          scope: WorkspaceScope.global,
          mode: WorkspaceActivationMode.copy,
          agentIds: const ['codex'],
        ),
      ],
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 1,
        projectRoots: const [],
        skills: [skill],
      ),
      globalTargets: const [
        WorkspaceActivationTarget(
          agentId: 'codex',
          displayName: 'Codex',
          detected: true,
          location: '/global/.agents/skills',
          scope: WorkspaceScope.global,
        ),
        WorkspaceActivationTarget(
          agentId: 'opencode',
          displayName: 'OpenCode',
          detected: true,
          location: '/global/.agents/skills',
          scope: WorkspaceScope.global,
        ),
        WorkspaceActivationTarget(
          agentId: 'universal',
          displayName: 'Universal',
          detected: false,
          location: '/global/.agents/skills',
          scope: WorkspaceScope.global,
        ),
      ],
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        catalogAuthority: SkillBrowserCatalogAuthority.workspaceSnapshot,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-selector')));
    await tester.pumpAndSettle();

    final options = tester
        .widgetList<AppMorphingMenuOption>(find.byType(AppMorphingMenuOption))
        .map((option) => option.label)
        .toList();
    expect(options, containsAll(['All Agents', 'Universal Agents']));
    // Inactive is a Scope bucket now, so the Agent menu never offers it.
    expect(options, isNot(contains('Inactive')));
    expect(options, isNot(contains('Codex')));
    expect(options, isNot(contains('Universal')));
  });

  testWidgets('counts Activation Locations, not the conventions sharing one', (
    tester,
  ) async {
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 1,
        projectRoots: const [],
        skills: [
          // The record names every convention mapped to the directory; only
          // Codex and OpenCode are installed on this machine.
          _sharedDirectorySkill(
            slotKey: 'shared',
            displayName: 'Shared Skill',
            agentIds: const [
              'codex',
              'opencode',
              'universal',
              'aider',
              'cline',
            ],
          ),
          _sharedDirectorySkill(
            slotKey: 'everywhere',
            displayName: 'Everywhere Skill',
            agentIds: const ['codex', 'opencode'],
            alsoClaudeCode: true,
          ),
        ],
      ),
      globalTargets: _sharedGlobalTargets,
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        catalogAuthority: SkillBrowserCatalogAuthority.workspaceSnapshot,
      ),
    );
    await tester.pumpAndSettle();

    // One of the Scope's two Activation Locations, which is one switch. The
    // five conventions recorded against that one directory are not five
    // switches, so the badge never reports them as reach.
    expect(_activationBadge('1/2 active'), findsOneWidget);
    expect(_activationBadge('5/5 active'), findsNothing);

    Icon badgeIcon(String label) => tester.widget<Icon>(
      find.descendant(of: _activationBadge(label), matching: find.byType(Icon)),
    );

    // Partial reach dims the robot; full reach draws it in ink.
    expect(find.text('1/2'), findsOneWidget);
    expect(badgeIcon('1/2 active').icon, LucideIcons.bot);
    expect(badgeIcon('1/2 active').color, AppColors.bodyContent);
    expect(_activationBadge('2/2 active'), findsOneWidget);
    expect(badgeIcon('2/2 active').color, AppColors.textPrimary);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('skill-shared'))),
    );
    final settings = container.read(appSettingsViewModelProvider.notifier);
    await settings.setBuiltInAgentMembership('codex', false);
    await settings.setBuiltInAgentMembership('opencode', false);
    await tester.pumpAndSettle();
    expect(_activationBadge('0/1 active'), findsOneWidget);
    expect(_activationBadge('1/1 active'), findsOneWidget);
    expect(workspace.deactivations, isEmpty);
    await settings.setBuiltInAgentMembership('claude-code', false);
    await tester.pumpAndSettle();
    expect(container.read(installedAgentGroupsProvider), isEmpty);
    expect(_activationBadge('0/0 active'), findsNothing);
    expect(find.byKey(const Key('skill-shared')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('skill-shared')),
        matching: find.text('Inactive'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'filters Skills for the selected Agent within the current Scope',
    (tester) async {
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 1,
          projectRoots: const [],
          skills: [
            _sharedDirectorySkill(
              slotKey: 'shared',
              displayName: 'Shared Skill',
              agentIds: const ['codex', 'opencode'],
            ),
            _sharedDirectorySkill(
              slotKey: 'stored',
              displayName: 'Stored Skill',
              agentIds: const [],
            ),
            _sharedDirectorySkill(
              slotKey: 'other',
              displayName: 'Other Agent Skill',
              agentIds: const [],
              alsoClaudeCode: true,
            ),
          ],
        ),
        globalTargets: _sharedGlobalTargets,
      );

      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(),
          workspaceRepository: workspace,
          catalogAuthority: SkillBrowserCatalogAuthority.workspaceSnapshot,
        ),
      );
      await tester.pumpAndSettle();

      // Under All Agents the never-activated Skill is filtered out of Global.
      expect(find.byKey(const Key('skill-shared')), findsOneWidget);
      expect(find.byKey(const Key('skill-stored')), findsNothing);

      await tester.tap(find.byKey(const Key('agent-selector')));
      await tester.pumpAndSettle();
      await tester.tap(_locationOption('/global/.agents/skills'));
      await tester.pumpAndSettle();

      // Selecting one Agent manages Skills inside the Global Scope. An
      // inactive Skill and another Agent's Global Skill are both available
      // to enable for this target.
      expect(find.byKey(const Key('skill-shared')), findsOneWidget);
      expect(find.byKey(const Key('skill-stored')), findsOneWidget);
      expect(find.byKey(const Key('skill-other')), findsOneWidget);
      expect(
        tester
            .widget<AgentActivationSwitch>(
              find.byKey(const Key('skill-activation-toggle-other')),
            )
            .on,
        isFalse,
      );
      expect(
        tester
            .widget<AgentActivationSwitch>(
              find.byKey(const Key('skill-activation-toggle-shared')),
            )
            .on,
        isTrue,
      );
      expect(
        find.byKey(const Key('skill-activation-toggle-shared')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('skill-activation-toggle-stored')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('skill-activation-toggle-stored')));
      await tester.pumpAndSettle();
      expect(workspace.activations, hasLength(1));
      expect(workspace.activations.single.slotKeys, {'stored'});
      expect(workspace.activations.single.scope, WorkspaceScope.global);
      // The Universal convention names the directory; the request names
      // Agents sharing it.
      expect(workspace.activations.single.agentIds, {'codex', 'opencode'});

      await tester.tap(find.byKey(const Key('skill-activation-toggle-shared')));
      await tester.pumpAndSettle();
      expect(workspace.deactivations, hasLength(1));
      expect(workspace.deactivations.single.slotKeys, {'shared'});
      // Deactivation removes the shared directory, never a single Agent.
      expect(workspace.deactivations.single.locations, {
        '/global/.agents/skills',
      });

      await tester.tap(find.byKey(const Key('skill-activation-toggle-other')));
      await tester.pumpAndSettle();
      expect(workspace.activations, hasLength(2));
      expect(workspace.activations.last.slotKeys, {'other'});
      expect(workspace.activations.last.scope, WorkspaceScope.global);
      expect(workspace.activations.last.projectRootId, isNull);
      expect(workspace.activations.last.agentIds, {'codex', 'opencode'});
      // Enabling this target must not deactivate the existing Claude target.
      expect(workspace.deactivations, hasLength(1));
    },
  );

  testWidgets('matches the Installed page controls from the design', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [
          testSkill(
            slotKey: 'alpha',
            displayName: 'Alpha Skill',
            activationCount: 5,
            activations: [
              for (final agentId in [
                'claude',
                'cursor',
                'codex',
                'copilot',
                'gemini',
              ])
                SkillActivationLocation(
                  location: '/global/skills/alpha/$agentId',
                  scope: WorkspaceScope.global,
                  mode: WorkspaceActivationMode.symbolicLink,
                  agentIds: [agentId],
                ),
            ],
          ),
        ],
      ),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        acquisitionRepository: FakeSkillAcquisitionRepository(
          agents: [
            for (final agentId in [
              'claude',
              'cursor',
              'codex',
              'copilot',
              'gemini',
            ])
              AgentOption(
                id: agentId,
                displayName: agentId,
                location: '/global/skills/alpha/$agentId',
              ),
          ],
        ),
        workspaceRepository: FakeSkillsWorkspaceRepository(
          globalTargets: [
            for (final agentId in [
              'claude',
              'cursor',
              'codex',
              'copilot',
              'gemini',
            ])
              WorkspaceActivationTarget(
                agentId: agentId,
                displayName: agentId,
                detected: true,
                location: '/global/skills/alpha/$agentId',
                scope: WorkspaceScope.global,
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final refreshAction = tester.widget<AppIconButton>(
      find.byKey(const Key('installed-refresh-scan-action')),
    );
    expect(refreshAction.icon, LucideIcons.refreshCw);
    expect(refreshAction.style, NeoButtonVariant.secondary);
    expect(refreshAction.size, AppSizes.pageCommandBarHeight);
    expect(refreshAction.iconSize, AppSizes.iconMd);
    expect(
      tester.getSize(find.byKey(const Key('installed-refresh-scan-action'))),
      const Size.square(AppSizes.pageCommandBarHeight),
    );
    expect(refreshAction.onPressed, isNotNull);

    final button = tester.widget<AppIconButton>(
      find.byKey(const Key('add-skills')),
    );
    expect(button.icon, LucideIcons.plus);
    expect(button.style, NeoButtonVariant.primary);
    expect(button.size, AppSizes.pageCommandBarHeight);
    expect(button.iconSize, AppSizes.iconLg);
    expect(
      tester.getSize(find.byKey(const Key('add-skills'))),
      const Size.square(AppSizes.pageCommandBarHeight),
    );
    // Breadcrumb and title are separate Text widgets, never a single
    // combined string. "Installed" also labels the sidebar nav item, so
    // read the page header's own title Text rather than searching by text.
    expect(find.text('Workspace'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('installed-title'))).data,
      'Installed',
    );
    expect(find.byKey(const Key('installed-filter-row')), findsOneWidget);
    expect(find.byKey(const Key('installed-search-control')), findsOneWidget);
    expect(find.byKey(const Key('skill-sort-button')), findsOneWidget);
    expect(find.byKey(const Key('installed-search-field')), findsNothing);
    expect(find.text('Name'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('agent-selector'))).dy -
          tester.getBottomLeft(find.byKey(const Key('installed-title'))).dy,
      // Compact header metrics place the filter row 15.78pt below the
      // title's painted bottom.
      closeTo(15.78, 0.5),
    );
    expect(
      tester.getSize(find.byKey(const Key('agent-selector'))),
      const Size(164, AppSizes.controlHeight),
    );

    // The activation badge is a robot with the reach count beside it.
    final badge = _activationBadge('5/5 active');
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('5/5')),
      findsOneWidget,
    );
  });

  testWidgets('opens the four Skill sorting choices', (tester) async {
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [
          testSkill(
            slotKey: 'alpha',
            displayName: 'Alpha Skill',
            activations: globalActivation(),
          ),
        ],
      ),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('skill-sort-button')));
    await tester.pumpAndSettle();

    for (final mode in [
      'nameAscending',
      'nameDescending',
      'recentlyAdded',
      'oldestAdded',
    ]) {
      expect(find.byKey(Key('skill-sort-option-$mode')), findsOneWidget);
    }
    expect(find.text('Enabled first'), findsNothing);
    expect(find.text('Inactive first'), findsNothing);
  });

  testWidgets('shows Installed and Favorites in the layout set in Settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [
          testSkill(
            slotKey: 'alpha',
            displayName: 'Alpha Skill',
            isFavorite: true,
            activations: globalActivation(),
          ),
          testSkill(
            slotKey: 'beta',
            displayName: 'Beta Skill',
            activations: globalActivation(),
          ),
        ],
      ),
      documents: const {'alpha': '# Alpha', 'beta': '# Beta'},
    );

    final layoutStore = SkillListLayoutStore(
      preferences: SharedPreferencesAsync(),
    );
    // A fresh install defaults to cards.
    expect(await layoutStore.read(), SkillListLayout.cards);

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/settings?section=appearance',
        skillListLayoutStore: layoutStore,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();

    // A fresh app restores the stored choice on both pages.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        skillListLayoutStore: layoutStore,
        initialSkillListLayout: await layoutStore.read(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-card-grid')), findsOneWidget);
    // Cards sit side by side rather than stacking like rows.
    expect(
      tester.getTopLeft(find.byKey(const Key('skill-alpha'))).dy,
      tester.getTopLeft(find.byKey(const Key('skill-beta'))).dy,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/favorites',
        skillListLayoutStore: layoutStore,
        initialSkillListLayout: await layoutStore.read(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-card-grid')), findsOneWidget);
    expect(find.byKey(const Key('skill-alpha')), findsOneWidget);
    expect(find.byKey(const Key('skill-beta')), findsNothing);

    await tester.tap(find.byKey(const Key('skill-alpha')));
    await tester.pumpAndSettle();
    // Opening a card leaves the grid for the Skill detail page.
    expect(find.byKey(const Key('skill-card-grid')), findsNothing);
  });

  testWidgets('search grows in place from its button and keeps the query', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [
          testSkill(
            slotKey: 'alpha',
            displayName: 'Alpha Skill',
            activations: globalActivation(),
          ),
          testSkill(
            slotKey: 'beta',
            displayName: 'Beta Skill',
            activations: globalActivation(),
          ),
        ],
      ),
      documents: {'alpha': '# Alpha', 'beta': '# Beta'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );
    await tester.pumpAndSettle();

    final searchControl = find.byKey(const Key('installed-search-control'));
    final searchField = find.byKey(const Key('installed-search-field'));
    final surface = find.byKey(
      const ValueKey<String>('morphing-menu-button-surface'),
    );
    final anchor = tester.getRect(searchControl);
    expect(anchor.width, AppSizes.controlHeight);
    expect(searchField, findsNothing);

    // The field is there and focused while the capsule is still growing.
    await tester.tap(searchControl);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(searchField, findsOneWidget);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(
      tester.getRect(surface).width,
      inExclusiveRange(AppSizes.controlHeight, 260),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    final open = tester.getRect(surface);
    expect(open.width, 220);
    expect(open.top, anchor.top);
    expect(open.height, anchor.height);
    expect(open.right, anchor.right);

    await tester.enterText(searchField, 'Alpha');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-alpha')), findsOneWidget);
    expect(find.byKey(const Key('skill-beta')), findsNothing);

    // Escape closes the field but keeps the query, which the button shows.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(searchField, findsNothing);
    expect(
      find.descendant(of: searchControl, matching: find.text('Alpha')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('skill-beta')), findsNothing);

    await tester.tap(searchControl);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CupertinoTextField>(searchField).controller?.text,
      'Alpha',
    );
    await tester.enterText(searchField, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.getSize(searchControl).width, AppSizes.controlHeight);
    expect(find.byKey(const Key('skill-beta')), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(760, 900));
    await tester.pumpAndSettle();
    await tester.tap(searchControl);
    await tester.pumpAndSettle();
    expect(tester.getRect(surface).width, 140);
    expect(tester.takeException(), isNull);
  });

  testWidgets('places browser actions in the top-right command bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha Skill')],
      ),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        acquisitionRepository: FakeSkillAcquisitionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final headerTop = tester
        .getTopLeft(find.byKey(const Key('installed-header-column')))
        .dy;
    final refreshTop = tester
        .getTopLeft(find.byKey(const Key('installed-refresh-scan-action')))
        .dy;
    expect(refreshTop - headerTop, AppInsets.pageHeader.top);
    expect(
      tester.getCenter(find.byKey(const Key('add-skills'))).dy,
      tester
          .getCenter(find.byKey(const Key('installed-refresh-scan-action')))
          .dy,
    );
    expect(
      tester.getTopRight(find.byKey(const Key('add-skills'))).dx,
      tester.getTopRight(find.byKey(const Key('installed-header-column'))).dx,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('add-skills'))).dx -
          tester
              .getTopRight(
                find.byKey(const Key('installed-refresh-scan-action')),
              )
              .dx,
      AppSpacing.sm,
    );
    expect(
      refreshTop,
      lessThan(tester.getTopLeft(find.byKey(const Key('installed-title'))).dy),
    );
  });

  testWidgets('pins browser commands while filters scroll with the list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skills = [
      for (var index = 0; index < 24; index++)
        testSkill(
          slotKey: 'skill-$index',
          displayName: 'Skill $index',
          activations: globalActivation(),
        ),
    ];
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: skills),
      documents: {for (final skill in skills) skill.slotKey: '# Skill'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        acquisitionRepository: FakeSkillAcquisitionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    final scroll = find.byKey(const Key('skill-list'));
    final title = find.byKey(const Key('installed-title'));
    final filter = find.byKey(const Key('installed-filter-row'));
    final refresh = find.byKey(const Key('installed-refresh-scan-action'));
    final blur = find.byKey(const Key('installed-top-blur'));
    final header = find.byKey(const Key('installed-header-column'));
    final refreshTop = tester.getTopLeft(refresh).dy;
    final expandedFilterTop = tester.getTopLeft(filter).dy;

    expect(find.descendant(of: blur, matching: header), findsNothing);
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.expandedTitleFontSize,
    );

    await tester.drag(scroll, const Offset(0, -180));
    await tester.pumpAndSettle();
    final collapsedFilterTop = tester.getTopLeft(filter).dy;
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.collapsedTitleFontSize,
    );
    expect(tester.getTopLeft(refresh).dy, refreshTop);
    expect(collapsedFilterTop, lessThan(expandedFilterTop));

    await tester.drag(scroll, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(refresh).dy, refreshTop);
    expect(filter, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows open failure and retries explicitly', (tester) async {
    var attempt = 0;
    final repository = FakeSkillBrowserRepository()
      ..openHandler = () async {
        attempt += 1;
        if (attempt == 1) {
          throw WorkspaceException(
            code: WorkspaceErrorCode.stateCorrupt,
            operation: WorkspaceOperationKind.open,
          );
        }
        return InstalledSkillCatalog(revision: 0, skills: const []);
      };

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('browser-failure')), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-open')));
    await tester.pumpAndSettle();

    expect(repository.openCalls, 2);
    expect(find.byKey(const Key('browser-empty')), findsOneWidget);
  });

  testWidgets('navigates from the installed list to a routed detail preview', (
    tester,
  ) async {
    final alpha = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      activations: [
        SkillActivationLocation(
          location: '~/.claude/skills/alpha',
          scope: WorkspaceScope.global,
          mode: WorkspaceActivationMode.symbolicLink,
          agentIds: const ['claude'],
        ),
        SkillActivationLocation(
          location: '/project/.cursor/skills/alpha',
          scope: WorkspaceScope.project,
          mode: WorkspaceActivationMode.copy,
          agentIds: const ['cursor'],
          projectRootId: 'project',
          projectRootPath: '/project',
        ),
      ],
    );
    final beta = testSkill(
      slotKey: 'beta',
      displayName: 'Beta Skill',
      activations: globalActivation(),
    );
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 7, skills: [alpha, beta]),
      documents: {
        'alpha': '# Alpha Guide\n\nRead the alpha instructions.',
        'beta': '# Beta Guide\n\nRead the beta instructions.',
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('skill-list')), findsOneWidget);
    expect(find.byKey(const Key('skill-detail')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('skill-beta')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const Key('skill-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('skill-beta')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('skill-detail')), findsOneWidget);
    expect(_markdownData(tester), contains('Beta Guide'));
    expect(repository.documentReads, ['alpha', 'beta']);
  });

  testWidgets('opens a direct detail route', (tester) async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-detail')), findsOneWidget);
    expect(_markdownData(tester), '# Alpha');
  });

  testWidgets('legacy activate route opens the detail settings tab', (
    tester,
  ) async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
          documents: const {'alpha': '# Alpha'},
        ),
        initialLocation: '/installed/alpha/activate',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('skill-activation-dialog')), findsNothing);
    expect(find.byKey(const Key('detail-scope-selector')), findsOneWidget);
    expect(find.byKey(const Key('detail-manage-agents')), findsOneWidget);
  });

  testWidgets('shows source before version with a source-kind tag', (
    tester,
  ) async {
    final skill = InstalledSkill(
      id: WorkspaceSkillId('alpha'),
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      description: 'Alpha description',
      contentHash: List.filled(64, 'a').join(),
      activationCount: 0,
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.git,
        locator: 'https://github.com/example/alpha',
      ),
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: const {'alpha': '# Alpha'},
        ),
        initialLocation: '/installed/alpha/activate',
      ),
    );
    await tester.pumpAndSettle();

    final sourceMeta = find.byKey(const Key('skill-source-meta'));
    final versionMeta = find.byKey(const Key('skill-version-meta'));
    final sourceTag = find.byKey(const Key('skill-source-kind-tag'));
    expect(
      tester.getTopLeft(sourceMeta).dx,
      lessThan(tester.getTopLeft(versionMeta).dx),
    );
    expect(sourceTag, findsOneWidget);
    expect(find.text('Git'), findsOneWidget);
    expect(
      find.descendant(
        of: sourceTag,
        matching: find.byIcon(LucideIcons.gitBranch),
      ),
      findsOneWidget,
    );
    expect(find.text('https://github.com/example/alpha'), findsOneWidget);
  });

  testWidgets('scrolls wide Markdown tables inside the detail preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: const {
        'alpha':
            '# Alpha\n\n'
            '| Provider | Model | Notes |\n'
            '| --- | --- | --- |\n'
            '| Anthropic | anthropic/claude-sonnet-4 | LongUnbrokenCapabilityDescriptionThatCannotWrap |',
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    final markdown = find.byKey(const Key('skill-markdown'));
    final tableScroll = find.descendant(
      of: markdown,
      matching: find.byType(SingleChildScrollView),
    );
    expect(tableScroll, findsOneWidget);

    final scrollables = tester
        .stateList<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('skill-preview-scroll')),
            matching: find.byType(Scrollable),
          ),
        )
        .toList();
    final horizontal = scrollables.singleWhere(
      (state) =>
          state.position.axisDirection == AxisDirection.left ||
          state.position.axisDirection == AxisDirection.right,
    );
    final vertical = scrollables.singleWhere(
      (state) =>
          state.position.axisDirection == AxisDirection.up ||
          state.position.axisDirection == AxisDirection.down,
    );
    final verticalOffset = vertical.position.pixels;

    expect(horizontal.position.maxScrollExtent, greaterThan(0));
    await tester.drag(tableScroll, const Offset(-160, 0));
    await tester.pumpAndSettle();

    expect(horizontal.position.pixels, greaterThan(0));
    expect(vertical.position.pixels, verticalOffset);
  });

  testWidgets('shows the detail frame while its document is still loading', (
    tester,
  ) async {
    final document = Completer<String>();
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
    )..readDocumentHandler = (_) => document.future;

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('skill-detail')).evaluate().isNotEmpty,
    );

    expect(find.byKey(const Key('skill-detail-title')), findsOneWidget);
    expect(find.byKey(const Key('document-loading')), findsOneWidget);
    expect(find.byKey(const Key('skill-markdown')), findsNothing);
    expect(find.byKey(const Key('skill-description-card')), findsNothing);

    document.complete('# Alpha');
    await tester.pumpAndSettle();
    expect(_markdownData(tester), '# Alpha');
  });

  testWidgets('selects the title and the document as separate regions', (
    tester,
  ) async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('skill-markdown')).evaluate().isNotEmpty,
    );

    Element regionOf(Key key) => find
        .ancestor(of: find.byKey(key), matching: find.byType(SelectableRegion))
        .evaluate()
        .single;
    expect(
      regionOf(const Key('skill-markdown')),
      isNot(regionOf(const Key('skill-detail-title'))),
    );
  });

  testWidgets('omits SKILL.md frontmatter from the detail preview', (
    tester,
  ) async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {
        'alpha': '''---
name: alpha
description: Reviews code
---

# Alpha

Instructions.
''',
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    final markdown = _markdownData(tester);
    expect(markdown, contains('# Alpha'));
    expect(markdown, contains('Instructions.'));
    expect(markdown, isNot(contains('name: alpha')));
    expect(markdown, isNot(contains('description: Reviews code')));
  });

  testWidgets('browses nested Markdown files and switches the preview', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1360, 700);
    addTearDown(tester.view.reset);
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
      additionalDocuments: const {
        'alpha': {
          'references/guide.md': '''---
title: Guide
---

# Nested Guide
''',
          'references/deeper/details.md': '# Details',
        },
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<MorphingMenuButton>(
            find.byKey(const Key('skill-file-picker')),
          )
          .enabled,
      isTrue,
    );
    await tester.tap(_documentPickerTrigger);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('skill-document-browser-panel')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('skill-document-browser-panel')))
          .width,
      greaterThan(457),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('skill-document-browser-panel')))
          .height,
      lessThan(250),
    );
    expect(
      find.byKey(const Key('skill-document-directory-references')),
      findsOneWidget,
    );
    expect(
      _isDocumentBrowserRowSelected(
        tester,
        const Key('skill-document-file-SKILL.md'),
      ),
      isTrue,
    );

    await tester.tap(
      find.byKey(const Key('skill-document-directory-references')),
    );
    await tester.pumpAndSettle();
    expect(
      _isDocumentBrowserRowSelected(
        tester,
        const Key('skill-document-directory-references'),
      ),
      isTrue,
    );
    expect(
      _isDocumentBrowserRowSelected(
        tester,
        const Key('skill-document-file-SKILL.md'),
      ),
      isFalse,
    );
    await tester.tap(
      find.byKey(const Key('skill-document-file-references/guide.md')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('skill-document-browser-panel')), findsNothing);
    expect(find.text('guide.md'), findsOneWidget);
    expect(_markdownData(tester), contains('title: Guide'));
    expect(_markdownData(tester), contains('# Nested Guide'));
  });

  testWidgets('dismisses the document browser with Escape and page scroll', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1360, 700);
    addTearDown(tester.view.reset);
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {
        'alpha': [
          '# Alpha',
          for (var index = 0; index < 40; index++) 'Paragraph $index.',
        ].join('\n\n'),
      },
      additionalDocuments: const {
        'alpha': {'guide.md': '# Guide'},
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_documentPickerTrigger);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-document-browser-panel')), findsNothing);

    await tester.tap(_documentPickerTrigger);
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(1100, 650), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-document-browser-panel')), findsNothing);
  });

  testWidgets('adapts the document browser width to available space', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 700);
    addTearDown(tester.view.reset);
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
      additionalDocuments: const {
        'alpha': {'references/guide.md': '# Guide'},
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_documentPickerTrigger);
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('skill-document-browser-panel'));
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, lessThanOrEqualTo(457));
    await tester.tap(
      find.byKey(const Key('skill-document-directory-references')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('skill-document-browser-back')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('skill-document-file-references/guide.md')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapses the detail header while all preview content scrolls', (
    tester,
  ) async {
    // This test is about the blur, so it pays for the shader.
    AppCollapsingPageFrame.blurEnabled = true;
    addTearDown(() => AppCollapsingPageFrame.blurEnabled = false);
    await tester.binding.setSurfaceSize(const Size(1360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final longMarkdown = [
      '# Alpha',
      for (var index = 0; index < 40; index++)
        'Paragraph $index with enough content to make the preview scroll.',
    ].join('\n\n');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': longMarkdown},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    final edgeBlur = find.byKey(const Key('skill-detail-top-blur'));
    final previewScroll = find.byKey(const Key('skill-preview-scroll'));
    final header = find.byKey(const Key('skill-detail-header-column'));
    final title = find.byKey(const Key('skill-detail-title'));
    final back = find.byKey(const Key('skill-detail-back'));
    final update = find.byKey(const Key('check-skill-update'));
    final filePicker = find.byKey(const Key('skill-file-picker'));
    final description = find.byKey(const Key('skill-description-card'));
    final markdown = find.byKey(const Key('skill-markdown'));
    expect(edgeBlur, findsOneWidget);
    final blur = tester.widget<MyTopProgressiveBlur>(edgeBlur);
    expect(blur.sigma, 36);
    expect(blur.blurTextureDimensions, 384);
    expect(blur.tintColor, AppColors.surfaceTransparent);
    expect(
      blur.blurExtent,
      AppCollapsingHeaderMetrics.collapsedHeight +
          AppCollapsingPageFrame.blurFadeExtension,
    );
    expect(find.descendant(of: edgeBlur, matching: header), findsNothing);
    expect(
      find.descendant(of: previewScroll, matching: filePicker),
      findsOneWidget,
    );
    expect(
      find.descendant(of: previewScroll, matching: description),
      findsOneWidget,
    );
    final descriptionCard = tester.widget<Container>(description);
    final descriptionDecoration =
        descriptionCard.decoration! as ShapeDecoration;
    expect(descriptionDecoration.color, AppColors.surfaceMuted);
    expect(
      find.descendant(of: previewScroll, matching: markdown),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: previewScroll,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Padding &&
              widget.padding == const EdgeInsets.only(bottom: 84),
        ),
      ),
      findsOneWidget,
    );

    final expandedTitle = tester.widget<Text>(title);
    expect(
      expandedTitle.style!.fontSize,
      AppCollapsingHeaderMetrics.expandedTitleFontSize,
    );
    expect(tester.getTopLeft(title).dx, tester.getTopLeft(header).dx);
    final actionPosition = tester.getTopLeft(update);
    expect(
      tester.getCenter(update).dy,
      closeTo(tester.getCenter(title).dy, 0.5),
    );
    expect(
      tester.getTopRight(title).dx,
      lessThanOrEqualTo(tester.getTopLeft(update).dx - 16),
    );
    final pickerTopBefore = tester.getTopLeft(filePicker).dy;
    final descriptionTopBefore = tester.getTopLeft(description).dy;
    await tester.drag(previewScroll, const Offset(0, -54));
    await tester.pumpAndSettle();
    final midTitleSize = tester.widget<Text>(title).style!.fontSize!;
    final midActionTop = tester.getTopLeft(update).dy;
    expect(
      midTitleSize,
      inExclusiveRange(
        AppCollapsingHeaderMetrics.collapsedTitleFontSize,
        AppCollapsingHeaderMetrics.expandedTitleFontSize,
      ),
    );
    expect(midActionTop, lessThan(actionPosition.dy));
    expect(
      tester.getCenter(update).dy,
      closeTo(tester.getCenter(title).dy, 0.5),
    );
    expect(
      find.byKey(const Key('check-skill-update')).hitTestable(),
      findsOneWidget,
    );

    await tester.drag(previewScroll, const Offset(0, -126));
    await tester.pumpAndSettle();
    final pickerDelta = tester.getTopLeft(filePicker).dy - pickerTopBefore;
    final descriptionDelta =
        tester.getTopLeft(description).dy - descriptionTopBefore;
    expect(pickerDelta, lessThan(0));
    expect(descriptionDelta, closeTo(pickerDelta, 0.1));
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.collapsedTitleFontSize,
    );
    expect(
      tester.getTopLeft(title).dx - tester.getTopRight(back).dx,
      closeTo(12, 0.1),
    );
    expect(tester.getTopLeft(update).dx, actionPosition.dx);
    expect(tester.getTopLeft(update).dy, lessThan(midActionTop));
    expect(
      tester.getCenter(update).dy,
      closeTo(tester.getCenter(back).dy, 0.5),
    );
    expect(
      tester.getCenter(update).dy,
      closeTo(tester.getCenter(title).dy, 0.5),
    );
    expect(
      tester.getTopRight(title).dx,
      lessThanOrEqualTo(tester.getTopLeft(update).dx - 16),
    );

    final markdownTop = tester.getTopLeft(markdown).dy;
    await tester.drag(previewScroll, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(markdown).dy, lessThan(markdownTop));
  });

  testWidgets('moves the title row with top overscroll and restores it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {
        'alpha': [
          '# Alpha',
          for (var index = 0; index < 30; index++) 'Paragraph $index.',
        ].join('\n\n'),
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    final scroll = find.byKey(const Key('skill-preview-scroll'));
    final title = find.byKey(const Key('skill-detail-title'));
    final breadcrumb = find.byKey(const Key('skill-detail-breadcrumb'));
    final update = find.byKey(const Key('check-skill-update'));
    final back = find.byKey(const Key('skill-detail-back'));
    final filePicker = find.byKey(const Key('skill-file-picker'));
    final titleTop = tester.getTopLeft(title).dy;
    final breadcrumbTop = tester.getTopLeft(breadcrumb).dy;
    final updateTop = tester.getTopLeft(update).dy;
    final backTop = tester.getTopLeft(back).dy;
    final filePickerTop = tester.getTopLeft(filePicker).dy;

    // macOS overscroll comes from the trackpad; a pointer drag on the
    // document belongs to text selection.
    final gesture = await tester.startGesture(
      tester.getCenter(scroll),
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();

    final titleDelta = tester.getTopLeft(title).dy - titleTop;
    final breadcrumbDelta = tester.getTopLeft(breadcrumb).dy - breadcrumbTop;
    final updateDelta = tester.getTopLeft(update).dy - updateTop;
    final contentDelta = tester.getTopLeft(filePicker).dy - filePickerTop;
    expect(titleDelta, greaterThan(0));
    expect(titleDelta, closeTo(contentDelta * 0.35, 0.5));
    expect(breadcrumbDelta, closeTo(contentDelta * 0.20, 0.5));
    expect(breadcrumbDelta, lessThan(titleDelta));
    expect(updateDelta, closeTo(titleDelta, 0.5));
    expect(tester.getTopLeft(back).dy, backTop);

    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    final extendedTitleDelta = tester.getTopLeft(title).dy - titleTop;
    final extendedContentDelta =
        tester.getTopLeft(filePicker).dy - filePickerTop;
    expect(extendedTitleDelta, greaterThan(titleDelta));
    expect(extendedTitleDelta, closeTo(extendedContentDelta * 0.35, 0.5));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dy, closeTo(titleTop, 0.5));
    expect(tester.getTopLeft(breadcrumb).dy, closeTo(breadcrumbTop, 0.5));
    expect(tester.getTopLeft(update).dy, closeTo(updateTop, 0.5));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('preserves independent tab offsets across switches and resize', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {
        'alpha': [
          '# Alpha',
          for (var index = 0; index < 40; index++)
            'Paragraph $index with enough content to make the preview scroll.',
        ].join('\n\n'),
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    final previewScroll = find.byKey(const Key('skill-preview-scroll'));
    final title = find.byKey(const Key('skill-detail-title'));
    final filePicker = find.byKey(const Key('skill-file-picker'));
    await tester.drag(previewScroll, const Offset(0, -180));
    await tester.pumpAndSettle();
    final previewPickerTop = tester.getTopLeft(filePicker).dy;
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.collapsedTitleFontSize,
    );

    await tester.tap(_findSkillSectionTab(LucideIcons.settings));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.expandedTitleFontSize,
    );

    await tester.tap(_findSkillSectionTab(LucideIcons.fileText));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.collapsedTitleFontSize,
    );
    expect(tester.getTopLeft(filePicker).dy, closeTo(previewPickerTop, 0.1));

    await tester.binding.setSurfaceSize(const Size(1120, 700));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.collapsedTitleFontSize,
    );
    expect(tester.getTopLeft(filePicker).dy, closeTo(previewPickerTop, 0.1));
  });

  testWidgets('adapts the detail header without hiding actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(760, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longName = List.filled(12, 'Long Skill Name').join(' ');
    final alpha = testSkill(slotKey: 'alpha', displayName: longName);
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    final back = find.byKey(const Key('skill-detail-back'));
    final title = tester.widget<Text>(
      find.byKey(const Key('skill-detail-title')),
    );
    expect(tester.widget<AppIconButton>(back).icon, LucideIcons.arrowLeft);
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.byKey(const Key('check-skill-update')), findsOneWidget);
    expect(find.byKey(const Key('remove-skill')), findsOneWidget);
    expect(find.byKey(const Key('skill-language-button')), findsOneWidget);
    expect(find.byKey(const Key('favorite-skill')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1050, 700));
    await tester.pumpAndSettle();
    expect(tester.widget<AppIconButton>(back).icon, LucideIcons.arrowLeft);
    expect(
      tester.getSize(back),
      const Size.square(AppSizes.pageCommandBarHeight),
    );
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1360, 700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('snaps the header at the reduced-motion threshold', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.binding.setSurfaceSize(const Size(1360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {
        'alpha': [
          '# Alpha',
          for (var index = 0; index < 30; index++) 'Paragraph $index.',
        ].join('\n\n'),
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    final scroll = find.byKey(const Key('skill-preview-scroll'));
    final title = find.byKey(const Key('skill-detail-title'));
    expect(_descriptionAnimation(), findsNothing);
    // Drag amounts are expressed relative to collapseDistance, not as fixed
    // pixels, so this stays correct as the header's own metrics change: the
    // first drag must stay under the reduced-motion snap threshold, the
    // second must push well past it.
    const collapseDistance = AppCollapsingHeaderMetrics.collapseDistance;
    await tester.drag(scroll, Offset(0, -collapseDistance / 2));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.expandedTitleFontSize,
    );
    expect(
      tester.getCenter(find.byKey(const Key('check-skill-update'))).dy,
      closeTo(tester.getCenter(title).dy, 0.5),
    );

    await tester.drag(scroll, Offset(0, -collapseDistance * 2));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.collapsedTitleFontSize,
    );
    expect(
      tester.getCenter(find.byKey(const Key('check-skill-update'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const Key('skill-detail-back'))).dy,
        0.5,
      ),
    );
  });

  testWidgets('matches the compact detail hierarchy from the design', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final alpha = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      activations: [
        SkillActivationLocation(
          location: '~/.claude/skills/alpha',
          scope: WorkspaceScope.global,
          mode: WorkspaceActivationMode.symbolicLink,
          agentIds: const ['claude'],
        ),
        SkillActivationLocation(
          location: '/project/.cursor/skills/alpha',
          scope: WorkspaceScope.project,
          mode: WorkspaceActivationMode.copy,
          agentIds: const ['cursor'],
          projectRootId: 'project',
          projectRootPath: '/project',
        ),
      ],
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 1,
        projectRoots: const [SkillProjectRoot(id: 'project', path: '/project')],
        skills: [
          WorkspaceSkill(
            id: WorkspaceSkillId('alpha'),
            slotKey: alpha.slotKey,
            declaredName: alpha.slotKey,
            displayName: alpha.displayName,
            description: alpha.description,
            source: const SkillSourceProvenance(
              kind: WorkspaceSourceKind.local,
              locator: '/source/alpha',
            ),
            currentRevision: SkillRevision(
              contentHash: alpha.contentHash,
              fileCount: 1,
              byteSize: 1,
              acquiredAt: DateTime(2026),
              resolvedSourceRevision: 'local',
            ),
            activations: alpha.activations,
          ),
        ],
      ),
      documents: const {'alpha': '# Alpha'},
      globalTargets: const [
        WorkspaceActivationTarget(
          agentId: 'claude',
          displayName: 'claude',
          detected: true,
          location: '~/.claude/skills/alpha',
          scope: WorkspaceScope.global,
        ),
      ],
      projectTargets: const {
        'project': [
          WorkspaceActivationTarget(
            agentId: 'cursor',
            displayName: 'cursor',
            detected: true,
            location: '/project/.cursor/skills/alpha',
            scope: WorkspaceScope.project,
            projectRootId: 'project',
            projectRootPath: '/project',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: WorkspaceSkillBrowserRepository(workspace),
        workspaceRepository: workspace,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    final header = find.byKey(const Key('skill-detail-header-column'));
    final breadcrumb = find.byKey(const Key('skill-detail-breadcrumb'));
    final back = find.byKey(const Key('skill-detail-back'));
    final backButton = tester.widget<AppIconButton>(back);
    final title = find.byKey(const Key('skill-detail-title'));
    final update = find.byKey(const Key('check-skill-update'));
    final replaceSource = find.byKey(const Key('replace-skill-source'));
    final remove = find.byKey(const Key('remove-skill'));
    final language = find.byKey(const Key('skill-language-button'));
    final favorite = find.byKey(const Key('favorite-skill'));
    final filePicker = find.byKey(const Key('skill-file-picker'));
    expect(tester.getSize(header).width, 820);
    expect(
      find.descendant(
        of: breadcrumb,
        matching: find.byIcon(LucideIcons.squareLibrary),
      ),
      findsOneWidget,
    );
    expect(backButton.style, NeoButtonVariant.secondary);
    expect(
      tester.getTopLeft(back).dy - tester.getTopLeft(header).dy,
      AppInsets.pageHeader.top,
    );
    expect(filePicker, findsOneWidget);
    expect(tester.getSize(filePicker).height, AppSizes.controlHeight);
    expect(tester.getSize(filePicker).width, greaterThan(120));
    expect(find.byKey(const Key('skill-description-card')), findsOneWidget);
    expect(tester.getSize(update), const Size.square(AppSizes.buttonHeight));
    expect(
      tester.getSize(replaceSource),
      const Size.square(AppSizes.buttonHeight),
    );
    expect(tester.getSize(remove), const Size.square(AppSizes.buttonHeight));
    final languageSize = tester.getSize(language);
    expect(languageSize, const Size.square(AppSizes.buttonHeight));
    expect(
      tester
          .widget<MorphingMenuButton>(
            find.descendant(
              of: language,
              matching: find.byType(MorphingMenuButton),
            ),
          )
          .style!
          .buttonHeight,
      AppSizes.buttonHeight,
    );
    expect(favorite, findsOneWidget);
    expect(tester.getSize(favorite), const Size.square(AppSizes.buttonHeight));
    final favoriteButton = tester.widget<AppIconButton>(favorite);
    expect(favoriteButton.icon, LucideIcons.star);
    expect(favoriteButton.buttonSize, NeoButtonSize.medium);
    expect(favoriteButton.foregroundColor, AppColors.textSecondary);
    expect(favoriteButton.onPressed, isNotNull);
    expect(
      tester.getTopLeft(remove).dx - tester.getTopRight(update).dx,
      AppSpacing.sm,
    );
    expect(
      tester.getTopLeft(replaceSource).dx - tester.getTopRight(remove).dx,
      AppSpacing.sm,
    );
    expect(
      tester.getTopLeft(language).dx - tester.getTopRight(replaceSource).dx,
      AppSpacing.sm,
    );
    expect(
      tester.getTopLeft(favorite).dx - tester.getTopRight(language).dx,
      AppSpacing.sm,
    );
    expect(
      tester.getCenter(title).dy,
      closeTo(tester.getCenter(remove).dy, 0.5),
    );
    expect(
      tester.getTopLeft(remove).dy,
      greaterThan(tester.getBottomLeft(back).dy),
    );

    await tester.tap(favorite);
    await tester.pumpAndSettle();
    final favoritedButton = tester.widget<AppIconButton>(favorite);
    expect(favoritedButton.foregroundColor, AppColors.warning);

    await tester.tap(_findSkillSectionTab(LucideIcons.settings));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('skill-file-picker')), findsNothing);
    expect(find.byKey(const Key('skill-description-card')), findsNothing);
    expect(find.text('VERSION'), findsOneWidget);
    expect(find.text('SOURCE'), findsOneWidget);
    final scopeSelector = find.byKey(const Key('detail-scope-selector'));
    expect(
      tester.getTopRight(scopeSelector).dx,
      closeTo(tester.getTopRight(header).dx, 0.5),
    );
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('detail-manage-agents')))
          .style,
      NeoButtonVariant.primary,
    );
    expect(
      tester.getCenter(find.byKey(const Key('detail-manage-agents'))).dx,
      closeTo(tester.getCenter(header).dx, 0.5),
    );
    expect(find.text('claude'), findsOneWidget);
    expect(find.text('cursor'), findsNothing);
    expect(find.text('~/.claude/skills/alpha'), findsOneWidget);
    expect(find.text('copy'), findsNothing);

    await tester.tap(find.byKey(const Key('detail-scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('detail-scope-option-project-project')),
    );
    await tester.pumpAndSettle();
    expect(find.text('cursor'), findsOneWidget);
    expect(find.text('/project/.cursor/skills/alpha'), findsOneWidget);
    expect(find.text('copy'), findsOneWidget);
  });

  testWidgets('handles a missing direct detail route safely', (tester) async {
    final repository = FakeSkillBrowserRepository();

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/missing',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Skill not found'), findsOneWidget);
  });

  testWidgets('shows document failure and supports explicit retry', (
    tester,
  ) async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository =
        FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
            documents: {'alpha': '# Alpha'},
          )
          ..documentErrors['alpha'] = WorkspaceException(
            code: WorkspaceErrorCode.documentUnavailable,
            operation: WorkspaceOperationKind.readDocument,
          );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('document-failure')), findsOneWidget);
    repository.documentErrors.remove('alpha');
    await tester.tap(find.byKey(const Key('retry-document')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('skill-markdown')), findsOneWidget);
    expect(_markdownData(tester), '# Alpha');
  });

  testWidgets('refreshes the repository', (tester) async {
    final alpha = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      activations: globalActivation(),
    );
    final repository =
        FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
            documents: {'alpha': '# Alpha'},
          )
          ..refreshHandler = () async =>
              InstalledSkillCatalog(revision: 9, skills: [alpha]);

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('installed-refresh-scan-action')));
    await tester.pumpAndSettle();

    expect(repository.refreshCalls, 1);
    expect(find.byKey(const Key('skill-alpha')), findsOneWidget);
  });

  testWidgets(
    'refreshes the workspace catalog without a Riverpod circular dependency',
    (tester) async {
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: _workspaceRefreshSnapshot(),
        documents: const {'alpha': '# Alpha'},
      );

      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: WorkspaceSkillBrowserRepository(workspace),
          workspaceRepository: workspace,
          catalogAuthority: SkillBrowserCatalogAuthority.workspaceSnapshot,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('installed-refresh-scan-action')));
      await tester.pumpAndSettle();

      expect(workspace.refreshCalls, 1);
      expect(workspace.discoverExternalSkillsCalls, 2);
      expect(
        find.byKey(const Key('installed-refresh-scan-action')),
        findsOneWidget,
      );
    },
  );

  testWidgets('opens source add and remove dialogs through routed entries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final alpha = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      activations: globalActivation(),
    );
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        acquisitionRepository: FakeSkillAcquisitionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-skills')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('acquisition-dialog')), findsOneWidget);
    expect(find.byKey(const Key('discover-existing-skills')), findsNothing);
    await tester.tap(find.byKey(const Key('close-acquisition')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('acquisition-dialog')), findsNothing);

    await tester.tap(find.byKey(const Key('skill-alpha')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-skill')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remove-skill-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remove-skill-dialog')), findsNothing);
  });

  testWidgets('localizes the source replacement dialog in Chinese', (
    tester,
  ) async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        initialSourceInputMode: SkillSourceInputMode.typed,
        browserRepository: repository,
        locale: const Locale('zh'),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replace-skill-source')));
    await tester.pumpAndSettle();

    // The dialog now shares the Add Skill wizard's Source controls, so it is
    // those labels that must be localized. It also opens with no kind chosen,
    // so the locator and its Git options only appear after a card is tapped.
    expect(find.text('本地文件夹'), findsOneWidget);
    expect(find.text('Git 仓库'), findsOneWidget);
    expect(find.text('网页来源 URL'), findsOneWidget);
    expect(find.text('仓库 URL'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('source-replacement-kind-git')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-replacement-kind-git')));
    await tester.pumpAndSettle();

    expect(find.text('仓库 URL'), findsOneWidget);
    expect(find.text('GIT 引用'), findsOneWidget);
    expect(find.text('仓库子路径'), findsOneWidget);
    expect(find.text('Local Folder'), findsNothing);
    expect(find.text('REPOSITORY URL'), findsNothing);
  });

  testWidgets('source replacement opens with no Source kind chosen', (
    tester,
  ) async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        initialSourceInputMode: SkillSourceInputMode.typed,
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replace-skill-source')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-replacement-locator')), findsNothing);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const Key('inspect-replacement-source')),
          )
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(
      find.byKey(const Key('source-replacement-kind-local')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-replacement-kind-local')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-replacement-locator')), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const Key('inspect-replacement-source')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('submits Git source details through source replacement flow', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 12, skills: [skill]),
      documents: {'alpha': '# Alpha'},
    );
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: const SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://github.com/example/skills.git',
        ),
        candidates: const [
          WorkspaceSourceCandidate(
            declaredName: 'Alpha Skill',
            description: '',
            slotKey: 'alpha',
            skillPath: 'skills/alpha',
            contentHash: 'hash-alpha',
            fileCount: 1,
            byteSize: 10,
          ),
        ],
      );

    await tester.pumpWidget(
      skillsManagerTestApp(
        initialSourceInputMode: SkillSourceInputMode.typed,
        browserRepository: browser,
        workspaceRepository: workspace,
        acquisitionRepository: WorkspaceSkillAcquisitionRepository(
          workspace: workspace,
          resolver: SkillSourceLocatorResolver(),
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replace-skill-source')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('source-replacement-kind-git')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-replacement-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-replacement-locator')),
      'https://github.com/example/skills.git',
    );
    await tester.enterText(
      find.byKey(const Key('source-replacement-ref')),
      'main',
    );
    await tester.enterText(
      find.byKey(const Key('source-replacement-subpath')),
      'skills/alpha',
    );
    await tester.tap(find.byKey(const Key('inspect-replacement-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-source-replacement')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-source-replacement')));
    await tester.pumpAndSettle();

    expect(workspace.replaceSourceRequests, hasLength(1));
    final request = workspace.replaceSourceRequests.single;
    expect(request.slotKey, 'alpha');
    expect(request.expectedRevision, 12);
    expect(request.source.kind, WorkspaceSourceKind.git);
    expect(request.source.locator, 'https://github.com/example/skills.git');
    expect(request.source.ref, 'main');
    expect(request.source.repositorySubpath, 'skills/alpha');
  });

  testWidgets('refreshes the catalog when source replacement is stale', (
    tester,
  ) async {
    final localSourcePath = p.join(Directory.systemTemp.path, 'alpha');
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 12, skills: [skill]),
      documents: {'alpha': '# Alpha'},
    );
    final workspace = FakeSkillsWorkspaceRepository()
      ..sourceInspection = WorkspaceSourceInspection(
        source: SkillSourceInput(
          kind: WorkspaceSourceKind.local,
          locator: localSourcePath,
        ),
        candidates: const [
          WorkspaceSourceCandidate(
            declaredName: 'Alpha Skill',
            description: '',
            slotKey: 'alpha',
            skillPath: 'skills/alpha',
            contentHash: 'hash-alpha',
            fileCount: 1,
            byteSize: 10,
          ),
        ],
      )
      ..replaceSourceError = WorkspaceException(
        code: WorkspaceErrorCode.staleSnapshot,
        operation: WorkspaceOperationKind.replaceSource,
      );

    await tester.pumpWidget(
      skillsManagerTestApp(
        initialSourceInputMode: SkillSourceInputMode.typed,
        browserRepository: browser,
        workspaceRepository: workspace,
        acquisitionRepository: WorkspaceSkillAcquisitionRepository(
          workspace: workspace,
          resolver: SkillSourceLocatorResolver(),
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replace-skill-source')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('source-replacement-kind-local')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-replacement-kind-local')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-replacement-locator')),
      localSourcePath,
    );
    await tester.tap(find.byKey(const Key('inspect-replacement-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-source-replacement')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-source-replacement')));
    await tester.pumpAndSettle();

    expect(workspace.replaceSourceRequests, hasLength(1));
    expect(browser.refreshCalls, 1);
    expect(find.byKey(const Key('source-replacement-error')), findsNothing);

    workspace.replaceSourceError = null;
    await tester.tap(find.byKey(const Key('confirm-source-replacement')));
    await tester.pumpAndSettle();

    expect(workspace.replaceSourceRequests, hasLength(2));
    expect(workspace.replaceSourceRequests.last.expectedRevision, 12);
    expect(find.byKey(const Key('source-replacement-dialog')), findsNothing);
  });

  testWidgets('registers and unregisters a Project Root', (tester) async {
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha Skill')],
      ),
      documents: {'alpha': '# Alpha'},
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 1,
        projectRoots: const [],
        skills: const [],
      ),
    );
    final picker = FakeDirectoryPicker('/workspace/project');

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
        directoryPicker: picker,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('scope-option-manage-project-roots')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-roots-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('project-root-add')));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(workspace.registrations.single.path, '/workspace/project');
    expect(find.text('/workspace/project'), findsOneWidget);

    await tester.tap(find.byKey(const Key('project-root-remove-project-1')));
    await tester.pumpAndSettle();
    expect(workspace.unregistrations, ['project-1']);
    expect(find.text('/workspace/project'), findsNothing);
  });

  testWidgets('filters by scope and location, defaults to global', (
    tester,
  ) async {
    final global = testSkill(
      slotKey: 'global',
      displayName: 'Global Skill',
      activations: [
        SkillActivationLocation(
          location: '/global/skills/global',
          scope: WorkspaceScope.global,
          mode: WorkspaceActivationMode.symbolicLink,
          agentIds: const ['claude'],
        ),
      ],
    );
    final projectOne = testSkill(
      slotKey: 'project-one',
      displayName: 'Project One Skill',
      activations: [
        SkillActivationLocation(
          location: '/project-one/.cursor/skills/project-one',
          scope: WorkspaceScope.project,
          mode: WorkspaceActivationMode.copy,
          agentIds: const ['cursor'],
          projectRootId: 'one',
          projectRootPath: '/project-one',
        ),
      ],
    );
    final projectTwo = testSkill(
      slotKey: 'project-two',
      displayName: 'Project Two Skill',
      activations: [
        SkillActivationLocation(
          location: '/project-two/.codex/skills/project-two',
          scope: WorkspaceScope.project,
          mode: WorkspaceActivationMode.copy,
          agentIds: const ['codex'],
          projectRootId: 'two',
          projectRootPath: '/project-two',
        ),
      ],
    );
    final stored = testSkill(slotKey: 'stored', displayName: 'Stored Skill');
    final workspace = FakeSkillsWorkspaceRepository(
      globalTargets: const [
        WorkspaceActivationTarget(
          agentId: 'claude',
          displayName: 'Claude',
          detected: true,
          location: '/global/skills/global',
          scope: WorkspaceScope.global,
        ),
      ],
      projectTargets: const {
        'one': [
          WorkspaceActivationTarget(
            agentId: 'cursor',
            displayName: 'C',
            detected: true,
            location: '/project-one/.cursor/skills/project-one',
            scope: WorkspaceScope.project,
            projectRootId: 'one',
            projectRootPath: '/project-one',
          ),
        ],
      },
    );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 3,
        projectRoots: const [
          SkillProjectRoot(id: 'one', path: '/project-one'),
          SkillProjectRoot(id: 'two', path: '/project-two'),
          SkillProjectRoot(id: 'empty', path: '/empty-project'),
        ],
        skills: [global, projectOne, projectTwo, stored],
      ),
      documents: {
        'global': '# Global',
        'project-one': '# Project one',
        'project-two': '# Project two',
        'stored': '# Stored',
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
      ),
    );
    await tester.pumpAndSettle();
    final agentTrigger = find.descendant(
      of: find.byKey(const Key('agent-selector')),
      matching: find.byKey(
        const ValueKey<String>('morphing-menu-button-trigger-surface'),
      ),
    );
    final allAgentsButtonWidth = tester.getSize(agentTrigger).width;
    expect(find.byKey(const Key('skill-global')), findsOneWidget);
    expect(find.byKey(const Key('skill-project-one')), findsNothing);
    expect(find.byKey(const Key('skill-project-two')), findsNothing);
    expect(find.byKey(const Key('skill-stored')), findsNothing);

    await tester.tap(find.byKey(const Key('scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scope-option-project-one')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MorphingMenuButton>(find.byKey(const Key('scope-selector')))
          .icon,
      LucideIcons.folder,
    );
    expect(find.byKey(const Key('skill-global')), findsNothing);
    expect(find.byKey(const Key('skill-project-one')), findsOneWidget);
    expect(find.byKey(const Key('skill-project-two')), findsNothing);
    await tester.tap(find.byKey(const Key('agent-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-option-all')), findsOneWidget);
    expect(
      _locationOption('/project-one/.cursor/skills/project-one'),
      findsOneWidget,
    );
    expect(_locationOption('/global/skills/global'), findsNothing);
    expect(
      _locationOption('/project-two/.codex/skills/project-two'),
      findsNothing,
    );
    await tester.tap(
      _locationOption('/project-one/.cursor/skills/project-one'),
    );
    await tester.pumpAndSettle();
    final agentLeading = tester
        .widget<MorphingMenuButton>(find.byKey(const Key('agent-selector')))
        .leading;
    expect(agentLeading, isA<AgentLogo>());
    expect((agentLeading! as AgentLogo).agentId, 'cursor');
    expect(
      tester
          .widget<MorphingMenuButton>(find.byKey(const Key('agent-selector')))
          .label,
      'C',
    );
    expect(tester.getSize(agentTrigger).width, lessThan(allAgentsButtonWidth));
    expect(find.byKey(const Key('skill-project-one')), findsOneWidget);
    expect(find.byKey(const Key('scope-option-all')), findsNothing);
    await tester.tap(find.byKey(const Key('agent-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-option-all')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scope-option-project-empty')));
    await tester.pumpAndSettle();
    expect(find.text('No skills yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scope-option-global')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MorphingMenuButton>(find.byKey(const Key('scope-selector')))
          .icon,
      LucideIcons.globe2,
    );
    expect(find.byKey(const Key('skill-global')), findsOneWidget);
    expect(find.byKey(const Key('skill-project-one')), findsNothing);
    await tester.tap(find.byKey(const Key('agent-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-option-all')), findsOneWidget);
    expect(_locationOption('/global/skills/global'), findsOneWidget);
    expect(
      _locationOption('/project-one/.cursor/skills/project-one'),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('agent-option-all')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scope-option-inactive')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-stored')), findsOneWidget);
    expect(find.byKey(const Key('skill-global')), findsNothing);
    expect(find.byKey(const Key('skill-project-one')), findsNothing);
    expect(find.byKey(const Key('skill-project-two')), findsNothing);
    expect(find.byKey(const Key('agent-selector')), findsNothing);
  });

  testWidgets(
    'moves a fully deactivated Skill into the Inactive Scope bucket',
    (tester) async {
      final activeSkill = WorkspaceSkill(
        id: WorkspaceSkillId('managed-alpha'),
        slotKey: 'alpha',
        declaredName: 'alpha',
        displayName: 'Alpha Skill',
        description: 'Alpha description',
        source: const SkillSourceProvenance(
          kind: WorkspaceSourceKind.local,
          locator: '/source/alpha',
        ),
        currentRevision: SkillRevision(
          contentHash: 'a' * 64,
          fileCount: 1,
          byteSize: 7,
          acquiredAt: DateTime(2026),
        ),
        activations: [
          SkillActivationLocation(
            location: '/global/shared/alpha',
            scope: WorkspaceScope.global,
            mode: WorkspaceActivationMode.symbolicLink,
            agentIds: ['claude', 'codex'],
          ),
        ],
      );
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 1,
          projectRoots: const [],
          skills: [activeSkill],
        ),
        documents: const {'alpha': '# Alpha'},
      );

      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: WorkspaceSkillBrowserRepository(workspace),
          workspaceRepository: workspace,
          catalogAuthority: SkillBrowserCatalogAuthority.workspaceSnapshot,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agent-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agent-option-all')));
      await tester.pumpAndSettle();

      workspace.publish(
        SkillsWorkspaceSnapshot(
          revision: 2,
          projectRoots: const [],
          skills: [
            WorkspaceSkill(
              id: activeSkill.id,
              slotKey: activeSkill.slotKey,
              declaredName: activeSkill.declaredName,
              displayName: activeSkill.displayName,
              description: activeSkill.description,
              source: activeSkill.source,
              currentRevision: activeSkill.currentRevision,
              activations: const [],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Nothing reaches an Agent from Global any more, so the row leaves it.
      expect(find.byKey(const Key('skill-alpha')), findsNothing);
      await tester.tap(find.byKey(const Key('agent-selector')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('agent-option-all')), findsOneWidget);
      expect(_locationOption('/global/shared/alpha'), findsNothing);
      await tester.tap(find.byKey(const Key('agent-option-all')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scope-option-inactive')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill-alpha')), findsOneWidget);
      expect(find.text('Inactive'), findsWidgets);
      // No Agent can reach an inactive Skill, so the Agent filter is hidden.
      expect(find.byKey(const Key('agent-selector')), findsNothing);

      await tester.tap(find.byKey(const Key('skill-alpha')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill-detail')), findsOneWidget);
      await tester.tap(_findSkillSectionTab(LucideIcons.settings));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activate-skill')), findsNothing);
      expect(find.byKey(const Key('detail-scope-selector')), findsOneWidget);
      expect(find.byKey(const Key('remove-skill')), findsOneWidget);
    },
  );

  testWidgets('keeps Agent and scope selectors visually aligned', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skill = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      activations: [
        for (final agentId in ['claude', 'codex', 'cursor'])
          SkillActivationLocation(
            location: '/global/skills/alpha/$agentId',
            scope: WorkspaceScope.global,
            mode: WorkspaceActivationMode.symbolicLink,
            agentIds: [agentId],
          ),
      ],
    );
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );
    await tester.pumpAndSettle();

    final agentSelector = find.byKey(const Key('agent-selector'));
    final scopeSelector = find.byKey(const Key('scope-selector'));
    expect(
      tester.getSize(agentSelector),
      const Size(164, AppSizes.controlHeight),
    );
    expect(tester.getSize(scopeSelector).height, AppSizes.controlHeight);
    expect(tester.getSize(scopeSelector).width, lessThanOrEqualTo(420));
    expect(
      tester.getCenter(agentSelector).dy,
      tester.getCenter(scopeSelector).dy,
    );
  });

  testWidgets('keeps a long selected Project Root within the filter bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const longProjectPath =
        '/Users/example/Workspace/Clients/International/Research/'
        'A-Project-With-An-Exceptionally-Long-Directory-Name/'
        'packages/desktop/application';
    final skill = testSkill(
      slotKey: 'project-skill',
      displayName: 'Project Skill',
      activations: [
        SkillActivationLocation(
          location: '$longProjectPath/.claude/skills/project-skill',
          scope: WorkspaceScope.project,
          mode: WorkspaceActivationMode.symbolicLink,
          agentIds: ['claude'],
          projectRootId: 'long-project',
          projectRootPath: longProjectPath,
        ),
      ],
    );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        projectRoots: const [
          SkillProjectRoot(id: 'long-project', path: longProjectPath),
        ],
        skills: [skill],
      ),
      documents: {'project-skill': '# Project Skill'},
    );

    await tester.pumpWidget(skillsManagerTestApp(browserRepository: browser));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scope-selector')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('morphing-menu-button-surface')),
          )
          .width,
      320,
    );
    final projectOption = find.byKey(
      const Key('scope-option-project-long-project'),
    );
    expect(
      find.descendant(of: projectOption, matching: find.text('application')),
      findsOneWidget,
    );
    expect(find.text(longProjectPath), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(projectOption));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(longProjectPath), findsOneWidget);
    final optionRect = tester.getRect(projectOption);
    final tooltipRect = tester.getRect(
      find.byKey(const ValueKey<String>('app-tooltip-surface')),
    );
    expect(tooltipRect.right, closeTo(optionRect.right, 0.1));
    expect(tooltipRect.top, closeTo(optionRect.bottom + 8, 0.1));

    await tester.tap(projectOption);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final selector = find.byKey(const Key('scope-selector'));
    final selectedButton = tester.widget<MorphingMenuButton>(selector);
    expect(selectedButton.label, 'application');
    expect(
      find.ancestor(of: selector, matching: find.byType(AppTooltip)),
      findsNothing,
    );
    final header = find.byKey(const Key('installed-header-column'));
    expect(tester.getSize(selector).width, lessThanOrEqualTo(320));
    expect(
      tester.getBottomRight(selector).dx,
      lessThanOrEqualTo(tester.getBottomRight(header).dx),
    );
  });

  testWidgets('keeps a long Skill name to one ellipsized line', (tester) async {
    const longName =
        'A Skill Name That Is Intentionally Long Enough To Exceed The '
        'Available Width Of A Single Installed Skill Row';
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [
          testSkill(
            slotKey: 'long-name',
            displayName: longName,
            activations: globalActivation(),
          ),
        ],
      ),
      documents: {'long-name': '# Long name'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(browserRepository: repository),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text(longName));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('lists many Agents in the selector without horizontal overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const agentIds = [
      'aider',
      'claude-code',
      'codeium',
      'codex',
      'continue',
      'copilot',
      'cursor',
      'gemini',
      'windsurf',
    ];
    final skill = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      activations: [
        for (final agentId in agentIds)
          SkillActivationLocation(
            location: '/global/skills/alpha/$agentId',
            scope: WorkspaceScope.global,
            mode: WorkspaceActivationMode.symbolicLink,
            agentIds: [agentId],
          ),
      ],
    );
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        workspaceRepository: FakeSkillsWorkspaceRepository(
          globalTargets: [
            for (final agentId in agentIds)
              WorkspaceActivationTarget(
                agentId: agentId,
                displayName: agentId,
                detected: true,
                location: '/global/skills/alpha/$agentId',
                scope: WorkspaceScope.global,
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final headerRight = tester
        .getBottomRight(find.byKey(const Key('installed-header-column')))
        .dx;
    final selector = find.byKey(const Key('agent-selector'));
    expect(tester.getSize(selector).width, lessThanOrEqualTo(164));
    expect(tester.getSize(selector).height, AppSizes.controlHeight);
    expect(
      tester.getBottomRight(find.byKey(const Key('scope-selector'))).dx,
      lessThanOrEqualTo(headerRight),
    );
    expect(tester.getBottomRight(selector).dx, lessThanOrEqualTo(headerRight));

    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-option-all')), findsOneWidget);
    for (final agentId in agentIds) {
      expect(_locationOption('/global/skills/alpha/$agentId'), findsOneWidget);
    }
  });

  testWidgets('groups Activation targets by location and mutates that group', (
    tester,
  ) async {
    final skill = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      activations: [
        SkillActivationLocation(
          location: '/global/shared/alpha',
          scope: WorkspaceScope.global,
          mode: WorkspaceActivationMode.symbolicLink,
          agentIds: const ['claude-code', 'codex'],
        ),
      ],
    );
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 5,
        projectRoots: const [SkillProjectRoot(id: 'project', path: '/project')],
        skills: [skill],
      ),
      documents: {'alpha': '# Alpha'},
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 5,
        projectRoots: const [SkillProjectRoot(id: 'project', path: '/project')],
        skills: [
          WorkspaceSkill(
            id: skill.id,
            slotKey: 'alpha',
            declaredName: 'Alpha Skill',
            displayName: 'Alpha Skill',
            description: 'Alpha Skill description',
            source: const SkillSourceProvenance(
              kind: WorkspaceSourceKind.local,
              locator: '/source/alpha',
            ),
            currentRevision: SkillRevision(
              contentHash: skill.contentHash,
              fileCount: 1,
              byteSize: 10,
              acquiredAt: DateTime.utc(2026),
            ),
            activations: skill.activations,
          ),
        ],
      ),
      globalTargets: const [
        WorkspaceActivationTarget(
          agentId: 'claude-code',
          displayName: 'Claude',
          detected: true,
          location: '/global/shared/alpha',
          scope: WorkspaceScope.global,
        ),
        WorkspaceActivationTarget(
          agentId: 'codex',
          displayName: 'Codex',
          detected: true,
          location: '/global/shared/alpha',
          scope: WorkspaceScope.global,
        ),
      ],
      projectTargets: const {
        'project': [
          WorkspaceActivationTarget(
            agentId: 'cursor',
            displayName: 'Cursor',
            detected: true,
            location: '/project/.cursor/skills/alpha',
            scope: WorkspaceScope.project,
            projectRootId: 'project',
            projectRootPath: '/project',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_findSkillSectionTab(LucideIcons.settings));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const Key('activation-group-global-global-/global/shared/alpha'),
      ),
      findsOneWidget,
    );
    expect(find.text('Claude, Codex'), findsOneWidget);
    expect(find.byKey(const Key('agent-logo-stack')), findsNothing);
    expect(find.byKey(const Key('agent-logo-claude-code')), findsOneWidget);
    expect(find.byKey(const Key('agent-logo-codex')), findsNothing);
    expect(
      find.byKey(
        const Key(
          'activation-group-project-project-/project/.cursor/skills/alpha',
        ),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const Key('activation-toggle-global-global-/global/shared/alpha'),
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.deactivations.single.slotKeys, {'alpha'});
    expect(workspace.deactivations.single.locations, {'/global/shared/alpha'});

    await tester.tap(find.byKey(const Key('detail-scope-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('detail-scope-option-project-project')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const Key(
          'activation-group-project-project-/project/.cursor/skills/alpha',
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const Key(
          'activation-toggle-project-project-/project/.cursor/skills/alpha',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.activations.single.slotKeys, {'alpha'});
    expect(workspace.activations.single.scope, WorkspaceScope.project);
    expect(workspace.activations.single.projectRootId, 'project');
    expect(workspace.activations.single.agentIds, {'cursor'});
  });

  testWidgets(
    'a master switch activates every Agent target when it has none active',
    (tester) async {
      final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 5,
          projectRoots: const [],
          skills: const [],
        ),
        globalTargets: const [
          WorkspaceActivationTarget(
            agentId: 'claude-code',
            displayName: 'Claude',
            detected: true,
            location: '/global/claude/skills',
            scope: WorkspaceScope.global,
          ),
          WorkspaceActivationTarget(
            agentId: 'codex',
            displayName: 'Codex',
            detected: true,
            location: '/global/codex/skills',
            scope: WorkspaceScope.global,
          ),
        ],
      );

      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 5, skills: [skill]),
            documents: {'alpha': '# Alpha'},
          ),
          workspaceRepository: workspace,
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_findSkillSectionTab(LucideIcons.settings));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<AgentActivationSwitch>(
              find.byKey(const Key('activation-toggle-all')),
            )
            .on,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('activation-toggle-all')));
      await tester.pumpAndSettle();

      expect(workspace.activations, hasLength(1));
      expect(workspace.activations.single.agentIds, {'claude-code', 'codex'});
      expect(workspace.deactivations, isEmpty);
    },
  );

  testWidgets(
    'a master switch deactivates every Agent target when all are active',
    (tester) async {
      final skill = testSkill(
        slotKey: 'alpha',
        displayName: 'Alpha Skill',
        activations: [
          SkillActivationLocation(
            location: '/global/claude/skills',
            scope: WorkspaceScope.global,
            mode: WorkspaceActivationMode.symbolicLink,
            agentIds: const ['claude-code'],
          ),
          SkillActivationLocation(
            location: '/global/codex/skills',
            scope: WorkspaceScope.global,
            mode: WorkspaceActivationMode.symbolicLink,
            agentIds: const ['codex'],
          ),
        ],
      );
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 5,
          projectRoots: const [],
          skills: const [],
        ),
        globalTargets: const [
          WorkspaceActivationTarget(
            agentId: 'claude-code',
            displayName: 'Claude',
            detected: true,
            location: '/global/claude/skills',
            scope: WorkspaceScope.global,
          ),
          WorkspaceActivationTarget(
            agentId: 'codex',
            displayName: 'Codex',
            detected: true,
            location: '/global/codex/skills',
            scope: WorkspaceScope.global,
          ),
        ],
      );

      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 5, skills: [skill]),
            documents: {'alpha': '# Alpha'},
          ),
          workspaceRepository: workspace,
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_findSkillSectionTab(LucideIcons.settings));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<AgentActivationSwitch>(
              find.byKey(const Key('activation-toggle-all')),
            )
            .on,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('activation-toggle-all')));
      await tester.pumpAndSettle();

      expect(workspace.deactivations, hasLength(1));
      expect(workspace.deactivations.single.locations, {
        '/global/claude/skills',
        '/global/codex/skills',
      });
      expect(workspace.activations, isEmpty);
    },
  );

  testWidgets(
    'the master switch confirms a duplicate project activation once',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final skill = testSkill(
        slotKey: 'alpha',
        displayName: 'Alpha Skill',
        activations: [
          SkillActivationLocation(
            location: '/global/shared/alpha',
            scope: WorkspaceScope.global,
            mode: WorkspaceActivationMode.symbolicLink,
            agentIds: const ['codex'],
          ),
        ],
      );
      final browser = FakeSkillBrowserRepository(
        catalog: InstalledSkillCatalog(
          revision: 5,
          projectRoots: const [
            SkillProjectRoot(id: 'project', path: '/workspace/project'),
          ],
          skills: [skill],
        ),
        documents: {'alpha': '# Alpha'},
      );
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 5,
          projectRoots: const [
            SkillProjectRoot(id: 'project', path: '/workspace/project'),
          ],
          skills: const [],
        ),
        globalTargets: const [
          WorkspaceActivationTarget(
            agentId: 'codex',
            displayName: 'Codex',
            detected: true,
            location: '/global/shared/alpha',
            scope: WorkspaceScope.global,
          ),
        ],
        projectTargets: const {
          'project': [
            WorkspaceActivationTarget(
              agentId: 'codex',
              displayName: 'Codex',
              detected: true,
              location: '/workspace/project/.codex/skills/alpha',
              scope: WorkspaceScope.project,
              projectRootId: 'project',
              projectRootPath: '/workspace/project',
            ),
            WorkspaceActivationTarget(
              agentId: 'cursor',
              displayName: 'Cursor',
              detected: true,
              location: '/workspace/project/.cursor/skills/alpha',
              scope: WorkspaceScope.project,
              projectRootId: 'project',
              projectRootPath: '/workspace/project',
            ),
          ],
        },
      );

      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: browser,
          workspaceRepository: workspace,
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_findSkillSectionTab(LucideIcons.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('detail-scope-option-project-project')),
      );
      await tester.pumpAndSettle();

      // Only the Codex row overlaps the global Activation, but the batch is
      // confirmed once rather than once per overlapping Agent.
      await tester.tap(find.byKey(const Key('activation-toggle-all')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('project-duplicate-activation-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('project-duplicate-activation-cancel')),
      );
      await tester.pumpAndSettle();
      expect(workspace.activations, isEmpty);

      await tester.tap(find.byKey(const Key('activation-toggle-all')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('project-duplicate-activation-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('project-duplicate-activation-confirm')),
      );
      await tester.pumpAndSettle();
      expect(workspace.activations, hasLength(1));
      expect(workspace.activations.single.scope, WorkspaceScope.project);
      expect(workspace.activations.single.projectRootId, 'project');
      expect(workspace.activations.single.agentIds, {'codex', 'cursor'});
    },
  );

  testWidgets('toggling an Agent never opens the detail progress card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final activating =
        Completer<WorkspaceCompletion<WorkspaceActivationAttempt>>();
    addTearDown(() {
      if (!activating.isCompleted) activating.completeError('abandoned');
    });
    final workspace =
        FakeSkillsWorkspaceRepository(
            snapshot: SkillsWorkspaceSnapshot(
              revision: 5,
              projectRoots: const [],
              skills: const [],
            ),
            globalTargets: const [
              WorkspaceActivationTarget(
                agentId: 'claude-code',
                displayName: 'Claude Code',
                detected: true,
                location: '/global/claude/skills',
                scope: WorkspaceScope.global,
              ),
            ],
          )
          ..activateTask = WorkspaceTask(
            current: WorkspaceOperationProgress(
              operationId: 'activate-1',
              kind: WorkspaceOperationKind.activate,
              phase: WorkspaceOperationPhase.waitingForLock,
            ),
            states: const Stream.empty(),
            completed: activating.future,
            cancel: () async {},
          );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 5, skills: [skill]),
          documents: {'alpha': '# Alpha'},
        ),
        workspaceRepository: workspace,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_findSkillSectionTab(LucideIcons.settings));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const Key('activation-toggle-global-global-/global/claude/skills'),
      ),
    );
    await tester.pump();

    // A switch settles in one step; a progress card would shove the whole page
    // down under the tapped control.
    expect(workspace.activations, hasLength(1));
    expect(find.byKey(const Key('operation-feedback')), findsNothing);
  });

  testWidgets(
    'removing and readding Agents preserves activation without historical rows',
    (tester) async {
      final skill = testSkill(
        slotKey: 'alpha',
        displayName: 'Alpha Skill',
        activations: [
          SkillActivationLocation(
            location: '/global/codex/skills',
            scope: WorkspaceScope.global,
            mode: WorkspaceActivationMode.symbolicLink,
            agentIds: const ['codex'],
          ),
        ],
      );
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 1,
          projectRoots: const [],
          skills: [
            WorkspaceSkill(
              id: skill.id,
              slotKey: skill.slotKey,
              declaredName: skill.displayName,
              displayName: skill.displayName,
              description: skill.description,
              source: const SkillSourceProvenance(
                kind: WorkspaceSourceKind.local,
                locator: '/source/alpha',
              ),
              currentRevision: SkillRevision(
                contentHash: skill.contentHash,
                fileCount: 1,
                byteSize: 1,
                acquiredAt: DateTime.utc(2026),
              ),
              activations: skill.activations,
            ),
          ],
        ),
        globalTargets: const [
          WorkspaceActivationTarget(
            agentId: 'codex',
            displayName: 'Codex',
            detected: true,
            location: '/global/codex/skills',
            scope: WorkspaceScope.global,
          ),
        ],
      );
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: WorkspaceSkillBrowserRepository(workspace),
          workspaceRepository: workspace,
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_findSkillSectionTab(LucideIcons.settings));
      await tester.pumpAndSettle();

      final toggle = find.byKey(
        const Key('activation-toggle-global-global-/global/codex/skills'),
      );
      expect(toggle, findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(toggle));
      final settings = container.read(appSettingsViewModelProvider.notifier);
      expect(container.read(installedAgentGroupsProvider), hasLength(1));
      expect(await settings.setBuiltInAgentMembership('codex', false), isTrue);
      await tester.pumpAndSettle();
      expect(toggle, findsNothing);
      expect(find.text('Existing activations'), findsNothing);
      expect(find.text('Outside the management list'), findsNothing);
      expect(container.read(installedAgentGroupsProvider), isEmpty);
      expect(workspace.deactivations, isEmpty);
      expect(await settings.setBuiltInAgentMembership('codex', true), isTrue);
      await tester.pumpAndSettle();
      expect(toggle, findsOneWidget);
      expect(container.read(installedAgentGroupsProvider), hasLength(1));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(workspace.deactivations.single.locations, {
        '/global/codex/skills',
      });
      await tester.tap(find.byKey(const Key('skill-detail-back')));
      await tester.pumpAndSettle();
      final group = container.read(installedAgentGroupsProvider).single;
      container
          .read(installedLocationFilterProvider.notifier)
          .select(InstalledLocationFilter.location(group.key));
      await tester.pumpAndSettle();
      expect(await settings.setBuiltInAgentMembership('codex', false), isTrue);
      await tester.pumpAndSettle();
      expect(
        container.read(installedLocationFilterProvider).kind,
        InstalledLocationFilterKind.all,
      );
      expect(
        container.read(installedScopeFilterProvider),
        InstalledScopeFilter.global,
      );
      await tester.tap(find.byKey(const Key('agent-selector')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(group.key)), findsNothing);
    },
  );

  testWidgets(
    'a running Skill update requests the update without an inline page banner',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
      final updating =
          Completer<WorkspaceCompletion<WorkspaceMutationReceipt>>();
      addTearDown(() {
        if (!updating.isCompleted) updating.completeError('abandoned');
      });
      final workspace =
          FakeSkillsWorkspaceRepository(
              // The shared update store derives its work list from the Snapshot,
              // so the managed Skill has to be in it.
              snapshot: SkillsWorkspaceSnapshot(
                revision: 5,
                projectRoots: const [],
                skills: [
                  WorkspaceSkill(
                    id: skill.id,
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
              updateReports: [
                WorkspaceUpdateReport(
                  skillId: skill.id,
                  status: WorkspaceUpdateStatus.updateAvailable,
                ),
              ],
            )
            ..updateTask = WorkspaceTask(
              current: WorkspaceOperationProgress(
                operationId: 'update-1',
                kind: WorkspaceOperationKind.update,
                phase: WorkspaceOperationPhase.waitingForLock,
              ),
              states: const Stream.empty(),
              completed: updating.future,
              cancel: () async {},
            );

      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 5, skills: [skill]),
            documents: {'alpha': '# Alpha'},
          ),
          workspaceRepository: workspace,
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('check-skill-update')));
      await tester.pumpAndSettle();

      // A known available update turns the action into the labelled Update form.
      final update = find.byKey(const Key('update-skill-now'));
      expect(update, findsOneWidget);
      await tester.tap(update);
      await tester.pump();

      // The request goes through; the detail page keeps no inline progress
      // banner between the title and the document picker while it runs.
      expect(workspace.updateRequests, hasLength(1));
      expect(find.byKey(const Key('operation-feedback')), findsNothing);
      expect(find.byKey(const Key('workspace-operation-error')), findsNothing);
    },
  );

  testWidgets('inline activation confirms takeover before replacing a target', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 5, skills: [skill]),
      documents: {'alpha': '# Alpha'},
    );
    final draft = FakeWorkspaceActivationTakeoverDraft(
      expectedRevision: 5,
      targets: [
        WorkspaceOccupiedActivationTarget(
          slotKey: 'alpha',
          location: '/global/claude/skills',
          targetPath: '/global/claude/skills/alpha',
          agentIds: const ['claude-code'],
          kind: WorkspaceActivationTargetOccupancyKind.brokenSymbolicLink,
          contentRelation: WorkspaceActivationContentRelation.indeterminate,
        ),
      ],
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 5,
        projectRoots: const [],
        skills: const [],
      ),
      globalTargets: const [
        WorkspaceActivationTarget(
          agentId: 'claude-code',
          displayName: 'Claude Code',
          detected: true,
          location: '/global/claude/skills',
          scope: WorkspaceScope.global,
        ),
      ],
    )..activateAttempt = WorkspaceActivationTakeoverRequired(draft);

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_findSkillSectionTab(LucideIcons.settings));
    await tester.pumpAndSettle();

    final toggle = find.byKey(
      const Key('activation-toggle-global-global-/global/claude/skills'),
    );
    await tester.tap(toggle);
    await _pumpUntilTakeoverDialog(tester);

    expect(find.byKey(const Key('activation-takeover-dialog')), findsOneWidget);
    expect(find.text('/global/claude/skills/alpha'), findsOneWidget);
    expect(workspace.confirmedTakeovers, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activation-takeover-dialog')), findsNothing);
    expect(workspace.confirmedTakeovers, isEmpty);

    await tester.tap(toggle);
    await _pumpUntilTakeoverDialog(tester);
    await tester.tap(find.byKey(const Key('activation-takeover-confirm')));
    await tester.pumpAndSettle();

    expect(workspace.confirmedTakeovers, [same(draft)]);
    expect(find.byKey(const Key('activation-takeover-dialog')), findsNothing);
  });

  testWidgets(
    'switches detail Scope and activates through the inline Agent list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final skill = testSkill(
        slotKey: 'alpha',
        displayName: 'Alpha Skill',
        activations: [
          SkillActivationLocation(
            location: '/global/existing/alpha',
            scope: WorkspaceScope.global,
            mode: WorkspaceActivationMode.symbolicLink,
            agentIds: const ['claude-code'],
          ),
          SkillActivationLocation(
            location: '/global/shared/alpha',
            scope: WorkspaceScope.global,
            mode: WorkspaceActivationMode.symbolicLink,
            agentIds: const ['codex'],
          ),
        ],
      );
      final browser = FakeSkillBrowserRepository(
        catalog: InstalledSkillCatalog(
          revision: 5,
          projectRoots: const [
            SkillProjectRoot(id: 'project', path: '/workspace/project'),
          ],
          skills: [skill],
        ),
        documents: {'alpha': '# Alpha'},
      );
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 5,
          projectRoots: const [
            SkillProjectRoot(id: 'project', path: '/workspace/project'),
          ],
          skills: const [],
        ),
        globalTargets: [
          const WorkspaceActivationTarget(
            agentId: 'claude-code',
            displayName: 'Claude',
            detected: true,
            location: '/global/existing/alpha',
            scope: WorkspaceScope.global,
          ),
          const WorkspaceActivationTarget(
            agentId: 'codex',
            displayName: 'Codex',
            detected: true,
            location: '/global/shared/alpha',
            scope: WorkspaceScope.global,
          ),
          const WorkspaceActivationTarget(
            agentId: 'cursor',
            displayName: 'Cursor',
            detected: false,
            location: '/global/shared/alpha',
            scope: WorkspaceScope.global,
          ),
          for (var index = 0; index < 8; index += 1)
            WorkspaceActivationTarget(
              agentId: 'filler-$index',
              displayName: 'Filler $index',
              detected: index.isEven,
              location: '/global/filler-$index/alpha',
              scope: WorkspaceScope.global,
            ),
        ],
        projectTargets: const {
          'project': [
            WorkspaceActivationTarget(
              agentId: 'codex',
              displayName: 'Codex',
              detected: true,
              location: '/workspace/project/.codex/skills/alpha',
              scope: WorkspaceScope.project,
              projectRootId: 'project',
              projectRootPath: '/workspace/project',
            ),
          ],
        },
      );

      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: browser,
          workspaceRepository: workspace,
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_findSkillSectionTab(LucideIcons.settings));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activate-skill')), findsNothing);
      expect(find.byKey(const Key('detail-scope-selector')), findsOneWidget);
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('skill-settings-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail-scope-selector')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('detail-scope-option-inactive')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('detail-scope-option-project-project')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const Key('activation-toggle-global-global-/global/shared/alpha'),
        ),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(
          const Key(
            'activation-toggle-project-project-/workspace/project/.codex/skills/alpha',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const Key(
            'activation-toggle-project-project-/workspace/project/.codex/skills/alpha',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('project-duplicate-activation-dialog')),
        findsOneWidget,
      );
      expect(find.byType(CupertinoCheckbox), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('project-duplicate-activation-dont-ask')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('project-duplicate-activation-cancel')),
      );
      await tester.pumpAndSettle();
      expect(workspace.activations, isEmpty);

      await tester.tap(
        find.byKey(
          const Key(
            'activation-toggle-project-project-/workspace/project/.codex/skills/alpha',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('project-duplicate-activation-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('project-duplicate-activation-confirm')),
      );
      await tester.pumpAndSettle();
      expect(workspace.activations, hasLength(1));
      expect(workspace.activations.single.scope, WorkspaceScope.project);
      expect(workspace.activations.single.projectRootId, 'project');
      expect(workspace.activations.single.agentIds, {'codex'});
    },
  );

  testWidgets('requires explicit confirmation before replacing an activation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 5, skills: [skill]),
      documents: {'alpha': '# Alpha'},
    );
    final draft = FakeWorkspaceActivationTakeoverDraft(
      expectedRevision: 5,
      targets: [
        WorkspaceOccupiedActivationTarget(
          slotKey: 'alpha',
          location: '/global/codex/skills',
          targetPath: '/global/codex/skills/alpha',
          agentIds: const ['codex'],
          kind: WorkspaceActivationTargetOccupancyKind.skillSymbolicLink,
          contentRelation:
              WorkspaceActivationContentRelation.differsFromCurrentRevision,
        ),
      ],
    );
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: SkillsWorkspaceSnapshot(
        revision: 5,
        projectRoots: const [],
        skills: const [],
      ),
      globalTargets: const [
        WorkspaceActivationTarget(
          agentId: 'codex',
          displayName: 'Codex',
          detected: true,
          location: '/global/codex/skills',
          scope: WorkspaceScope.global,
        ),
      ],
    )..activateAttempt = WorkspaceActivationTakeoverRequired(draft);

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_findSkillSectionTab(LucideIcons.settings));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('activation-toggle-global-global-/global/codex/skills'),
      ),
    );
    await _pumpUntilTakeoverDialog(tester);

    expect(find.byKey(const Key('activation-takeover-dialog')), findsOneWidget);
    expect(find.text('/global/codex/skills/alpha'), findsOneWidget);
    expect(find.text('Different from the selected Skill'), findsOneWidget);
    expect(workspace.confirmedTakeovers, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(workspace.confirmedTakeovers, isEmpty);
    expect(find.byKey(const Key('detail-scope-selector')), findsOneWidget);

    await tester.tap(
      find.byKey(
        const Key('activation-toggle-global-global-/global/codex/skills'),
      ),
    );
    await _pumpUntilTakeoverDialog(tester);
    await tester.tap(find.byKey(const Key('activation-takeover-confirm')));
    await tester.pumpAndSettle();

    expect(workspace.confirmedTakeovers, [same(draft)]);
    expect(find.byKey(const Key('detail-scope-selector')), findsOneWidget);
  });

  testWidgets('opens the occupied activation location from its target card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 5, skills: [skill]),
      documents: {'alpha': '# Alpha'},
    );
    final target = WorkspaceOccupiedActivationTarget(
      slotKey: 'alpha',
      location: '/global/codex/skills',
      targetPath: '/global/codex/skills/alpha',
      agentIds: const ['codex'],
      kind: WorkspaceActivationTargetOccupancyKind.skillSymbolicLink,
      contentRelation:
          WorkspaceActivationContentRelation.differsFromCurrentRevision,
    );
    final workspace =
        FakeSkillsWorkspaceRepository(
            snapshot: SkillsWorkspaceSnapshot(
              revision: 5,
              projectRoots: const [],
              skills: const [],
            ),
            globalTargets: const [
              WorkspaceActivationTarget(
                agentId: 'codex',
                displayName: 'Codex',
                detected: true,
                location: '/global/codex/skills',
                scope: WorkspaceScope.global,
              ),
            ],
          )
          ..activateAttempt = WorkspaceActivationTakeoverRequired(
            FakeWorkspaceActivationTakeoverDraft(
              expectedRevision: 5,
              targets: [target],
            ),
          );
    final opener = _RecordingFileLocationOpener();

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
        fileLocationOpener: opener,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_findSkillSectionTab(LucideIcons.settings));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('activation-toggle-global-global-/global/codex/skills'),
      ),
    );
    await _pumpUntilTakeoverDialog(tester);

    await tester.tap(
      find.byKey(
        const Key(
          'activation-takeover-open-location-/global/codex/skills/alpha',
        ),
      ),
    );
    await tester.pump();

    expect(opener.paths, ['/global/codex/skills/alpha']);
    expect(find.byKey(const Key('activation-takeover-dialog')), findsOneWidget);
  });

  testWidgets('keeps detail settings available after stale takeover failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final browser = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 5, skills: [skill]),
      documents: {'alpha': '# Alpha'},
    );
    final draft = FakeWorkspaceActivationTakeoverDraft(
      expectedRevision: 5,
      targets: [
        WorkspaceOccupiedActivationTarget(
          slotKey: 'alpha',
          location: '/global/codex/skills',
          targetPath: '/global/codex/skills/alpha',
          agentIds: const ['codex'],
          kind: WorkspaceActivationTargetOccupancyKind.skillDirectory,
          contentRelation:
              WorkspaceActivationContentRelation.differsFromCurrentRevision,
        ),
      ],
    );
    final workspace =
        FakeSkillsWorkspaceRepository(
            snapshot: SkillsWorkspaceSnapshot(
              revision: 5,
              projectRoots: const [],
              skills: const [],
            ),
            globalTargets: const [
              WorkspaceActivationTarget(
                agentId: 'codex',
                displayName: 'Codex',
                detected: true,
                location: '/global/codex/skills',
                scope: WorkspaceScope.global,
              ),
            ],
          )
          ..activateAttempt = WorkspaceActivationTakeoverRequired(draft)
          ..confirmActivationTakeoverError = WorkspaceException(
            code: WorkspaceErrorCode.staleActivationTakeover,
            operation: WorkspaceOperationKind.confirmActivationTakeover,
          );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_findSkillSectionTab(LucideIcons.settings));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('activation-toggle-global-global-/global/codex/skills'),
      ),
    );
    await _pumpUntilTakeoverDialog(tester);
    await tester.tap(find.byKey(const Key('activation-takeover-confirm')));
    await tester.pumpAndSettle();

    expect(workspace.confirmedTakeovers, [same(draft)]);
    expect(find.byKey(const Key('activation-takeover-dialog')), findsNothing);
    expect(find.byKey(const Key('detail-scope-selector')), findsOneWidget);

    await tester.tap(
      find.byKey(
        const Key('activation-toggle-global-global-/global/codex/skills'),
      ),
    );
    await _pumpUntilTakeoverDialog(tester);
    expect(find.byKey(const Key('activation-takeover-dialog')), findsOneWidget);
  });

  testWidgets('requires explicit reconfirmation after a stale removal', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final workspace =
        FakeSkillsWorkspaceRepository(
            snapshot: SkillsWorkspaceSnapshot(
              revision: 1,
              projectRoots: const [],
              skills: [
                WorkspaceSkill(
                  id: skill.id,
                  slotKey: 'alpha',
                  declaredName: 'Alpha Skill',
                  displayName: 'Alpha Skill',
                  description: 'Alpha Skill description',
                  source: const SkillSourceProvenance(
                    kind: WorkspaceSourceKind.local,
                    locator: '/source/alpha',
                  ),
                  currentRevision: SkillRevision(
                    contentHash: skill.contentHash,
                    fileCount: 1,
                    byteSize: 10,
                    acquiredAt: DateTime.utc(2026),
                  ),
                  activations: const [],
                ),
              ],
            ),
            documents: const {'alpha': '# Alpha'},
          )
          ..refreshSnapshot = SkillsWorkspaceSnapshot(
            revision: 2,
            projectRoots: const [],
            skills: [
              WorkspaceSkill(
                id: skill.id,
                slotKey: 'alpha',
                declaredName: 'Alpha Skill',
                displayName: 'Alpha Skill',
                description: 'Alpha Skill description',
                source: const SkillSourceProvenance(
                  kind: WorkspaceSourceKind.local,
                  locator: '/source/alpha',
                ),
                currentRevision: SkillRevision(
                  contentHash: skill.contentHash,
                  fileCount: 1,
                  byteSize: 10,
                  acquiredAt: DateTime.utc(2026),
                ),
                activations: const [],
              ),
            ],
          )
          ..removeError = WorkspaceException(
            code: WorkspaceErrorCode.staleSnapshot,
            operation: WorkspaceOperationKind.remove,
          );
    final browser = WorkspaceSkillBrowserRepository(workspace);

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        workspaceRepository: workspace,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-skill')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppButton>(find.byKey(const Key('remove-cancel'))).style,
      NeoButtonVariant.secondary,
    );
    expect(
      tester.widget<AppButton>(find.byKey(const Key('remove-confirm'))).style,
      NeoButtonVariant.danger,
    );
    await tester.tap(find.byKey(const Key('remove-confirm')));
    await tester.pumpAndSettle();

    expect(workspace.removals.single.expectedRevision, 1);
    expect(workspace.refreshCalls, 1);
    expect(find.text('Confirm again'), findsOneWidget);
    expect(find.textContaining('revision r2'), findsOneWidget);
    expect(find.byKey(const Key('remove-skill-dialog')), findsOneWidget);

    workspace.removeError = null;
    await tester.tap(find.byKey(const Key('remove-confirm')));
    await tester.pumpAndSettle();
    expect(workspace.removals, hasLength(2));
    expect(workspace.removals.last.expectedRevision, 2);
    expect(find.byKey(const Key('remove-skill-dialog')), findsNothing);
  });

  testWidgets('does not open Core on an unsupported platform', (tester) async {
    final repository = FakeSkillBrowserRepository();

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        desktopSupported: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('browser-unsupported')), findsOneWidget);
    expect(repository.openCalls, 0);
  });

  testWidgets('discloses Provider, Endpoint, and target before translation', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
      documents: {'alpha': '# Alpha'},
    );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('translation-confirmation')), findsOneWidget);
    expect(
      find.text('Skill text will be sent to this service.'),
      findsOneWidget,
    );
    expect(find.text('OpenAI compatible'), findsOneWidget);
    expect(find.text('api.openai.com'), findsOneWidget);
    expect(find.text('zh-Hans'), findsOneWidget);
    expect(find.byKey(const Key('confirm-translation')), findsOneWidget);
    expect(find.byKey(const Key('translation-feedback')), findsNothing);
  });

  testWidgets(
    'renders a cached Completed Translation without replay animation',
    (tester) async {
      final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
      final cache = MemoryTranslationCache();
      cache.values[TranslationCacheKey(
        slotKey: skill.slotKey,
        contentHash: skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
      )] = CompletedTranslation(
        slotKey: skill.slotKey,
        contentHash: skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: '''---
description: 已缓存描述
---
# 已缓存的译文''',
        provenance: TranslationProvenance(providerIdentifier: 'cache'),
      );
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
            documents: {'alpha': '# Original'},
          ),
          translationRepository: fakeAppTranslationRepository(cache: cache),
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();

      expect(_markdownData(tester), '# 已缓存的译文');
      final markdown = tester.widget<MarkdownWidget>(
        find.byKey(const Key('skill-markdown')),
      );
      expect(markdown.sourceDocument, isNull);
      expect(markdown.replacements, isEmpty);
      expect(find.text('已缓存描述'), findsOneWidget);
      expect(_descriptionAnimation(), findsNothing);
      expect(_descriptionImageFilter(), findsNothing);
    },
  );

  testWidgets('toggles between a cached translation and the original', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {'alpha': '# Original'},
        ),
        translationRepository: fakeAppTranslationRepository(
          cache: _cachedTranslationFor(skill, '# 已缓存的译文'),
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    expect(_markdownData(tester), '# 已缓存的译文');
    expect(_translateButtonFilled(tester), isTrue);

    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('translation-confirmation')),
      findsNothing,
      reason: 'showing the original uploads nothing, so it needs no consent',
    );
    expect(_markdownData(tester), '# Original');
    expect(_translateButtonFilled(tester), isFalse);

    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('translation-confirmation')), findsOneWidget);
    expect(find.byKey(const Key('delete-translation-cache')), findsOneWidget);
  });

  testWidgets('offers no cache deletion before a Skill has been translated', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {'alpha': '# Original'},
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    expect(_translateButtonFilled(tester), isFalse);
    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('translation-confirmation')), findsOneWidget);
    expect(find.byKey(const Key('delete-translation-cache')), findsNothing);
  });

  testWidgets('description-only cache changes the card but not the Markdown', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final cache = MemoryTranslationCache();
    cache.values[TranslationCacheKey(
      slotKey: skill.slotKey,
      contentHash: skill.contentHash,
      documentIdentifier: 'SKILL.md',
      targetLanguage: TargetLanguage('zh-Hans'),
      scope: TranslationScope.descriptionOnly,
    )] = CompletedTranslation(
      slotKey: skill.slotKey,
      contentHash: skill.contentHash,
      documentIdentifier: 'SKILL.md',
      targetLanguage: TargetLanguage('zh-Hans'),
      scope: TranslationScope.descriptionOnly,
      translatedContent: '简短说明',
      provenance: TranslationProvenance(providerIdentifier: 'cache'),
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {'alpha': '---\ndescription: Purpose.\n---\n# Original'},
        ),
        translationRepository: fakeAppTranslationRepository(cache: cache),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    expect(_markdownData(tester), '# Original');
    expect(find.text('简短说明'), findsOneWidget);
    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('translation-confirmation')), findsOneWidget);
    expect(find.byKey(const Key('retranslate-skill')), findsNothing);
    expect(find.byKey(const Key('delete-translation-cache')), findsOneWidget);
    await tester.tap(find.byKey(const Key('translation-scope-description')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-translation')));
    await tester.pumpAndSettle();
    expect(_markdownData(tester), '# Original');
    expect(find.text('简短说明'), findsOneWidget);
  });

  testWidgets('disables description scope without SKILL.md description', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {'alpha': '# Original'},
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();
    final scope = _translationScopeControl(tester);
    expect(scope.groupValue, TranslationScope.fullDocument);
    expect(scope.disabledChildren, {TranslationScope.descriptionOnly});
    expect(
      find.text('No translatable SKILL.md description is available.'),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('morphing-menu-button-surface')))
          .height,
      lessThan(300),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('translation-scope-description')));
    await tester.pumpAndSettle();
    expect(
      _translationScopeControl(tester).groupValue,
      TranslationScope.fullDocument,
    );
  });

  testWidgets('passes the selected description scope to the Provider', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final provider = _ControlledTranslationProvider();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {
            'alpha': '---\ndescription: Purpose.\n---\n# Private body',
          },
        ),
        translationRepository: fakeAppTranslationRepository(
          providerFactory: _ControlledTranslationFactory(provider),
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.byKey(const Key('morphing-menu-button-surface')))
          .height,
      lessThan(270),
    );
    final scopeControl = find.byKey(const Key('translation-scope-control'));
    expect(
      _translationScopeControl(tester).groupValue,
      TranslationScope.fullDocument,
    );
    expect(_translationScopeControl(tester).disabledChildren, isEmpty);
    expect(
      tester.getTopLeft(scopeControl).dy -
          tester.getBottomLeft(find.text('zh-Hans')).dy,
      lessThan(28),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('translation-scope-description')));
    await tester.pumpAndSettle();
    expect(
      _translationScopeControl(tester).groupValue,
      TranslationScope.descriptionOnly,
    );
    await tester.tap(find.byKey(const Key('confirm-translation')));
    await _pumpUntil(tester, () => provider.job != null);

    expect(provider.lastScope, TranslationScope.descriptionOnly);
    provider.job!.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('translates the full Skill by default', (tester) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final provider = _ControlledTranslationProvider();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {
            'alpha': '---\ndescription: Purpose.\n---\n# Private body',
          },
        ),
        translationRepository: fakeAppTranslationRepository(
          providerFactory: _ControlledTranslationFactory(provider),
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();
    expect(
      _translationScopeControl(tester).groupValue,
      TranslationScope.fullDocument,
    );
    await tester.tap(find.byKey(const Key('confirm-translation')));
    await _pumpUntil(tester, () => provider.job != null);

    expect(provider.lastScope, TranslationScope.fullDocument);
    provider.job!.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'remembers the selected translation scope across Skills and restarts',
    (tester) async {
      final originalPlatform = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      addTearDown(() {
        SharedPreferencesAsyncPlatform.instance = originalPlatform;
      });
      final preferenceStore = TranslationScopePreferenceStore(
        preferences: SharedPreferencesAsync(),
      );
      final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
      final noDescriptionSkill = testSkill(
        slotKey: 'beta',
        displayName: 'Beta Skill',
      );
      final anotherSkill = testSkill(
        slotKey: 'gamma',
        displayName: 'Gamma Skill',
      );

      Future<void> showSkill(InstalledSkill selected, String document) async {
        await tester.pumpWidget(
          skillsManagerTestApp(
            browserRepository: FakeSkillBrowserRepository(
              catalog: InstalledSkillCatalog(revision: 1, skills: [selected]),
              documents: {selected.slotKey: document},
            ),
            translationScopePreferenceStore: preferenceStore,
            initialTranslationScope: await preferenceStore.read(),
            initialLocation: '/installed/${selected.slotKey}',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('skill-language-button')));
        await tester.pumpAndSettle();
      }

      await showSkill(skill, '---\ndescription: Purpose.\n---\n# Body');
      await tester.tap(find.byKey(const Key('translation-scope-description')));
      await tester.pumpAndSettle();
      expect(
        _translationScopeControl(tester).groupValue,
        TranslationScope.descriptionOnly,
      );
      expect(await preferenceStore.read(), TranslationScope.descriptionOnly);

      await tester.pumpWidget(const SizedBox.shrink());
      await showSkill(noDescriptionSkill, '# No description');
      expect(
        _translationScopeControl(tester).groupValue,
        TranslationScope.fullDocument,
      );
      expect(await preferenceStore.read(), TranslationScope.descriptionOnly);

      await tester.pumpWidget(const SizedBox.shrink());
      await showSkill(anotherSkill, '---\ndescription: Purpose.\n---\n# Body');
      expect(
        _translationScopeControl(tester).groupValue,
        TranslationScope.descriptionOnly,
      );
    },
  );

  testWidgets('deleting the cache closes the card and restores the original', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final cache = _cachedTranslationFor(skill, '# 已缓存的译文');
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {'alpha': '# Original'},
        ),
        translationRepository: fakeAppTranslationRepository(cache: cache),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-language-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-translation-cache')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('translation-confirmation')), findsNothing);
    expect(cache.deletedSlotKeys, ['alpha']);
    expect(_markdownData(tester), '# Original');
    expect(_translateButtonFilled(tester), isFalse);
  });

  testWidgets('keeps the translate button cancellable while a Job runs', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final provider = _ControlledTranslationProvider();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {'alpha': '# Original'},
        ),
        translationRepository: fakeAppTranslationRepository(
          providerFactory: _ControlledTranslationFactory(provider),
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    final job = await _startTranslation(tester, provider);
    job.emitDraft(
      TranslationDraft(
        translatedBlocks: {const MarkdownBlockId(0, 10): '# 译文'},
        translatedDescription: null,
        completedBlockCount: 1,
        totalBlockCount: 1,
      ),
    );
    await tester.pump();

    expect(
      _translateButtonFilled(tester),
      isFalse,
      reason: 'a running Job must still read as cancellable',
    );

    job.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'waits for the matching cache and fades in only the cached translation',
    (tester) async {
      final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
      final cacheResult = Completer<CompletedTranslation?>();
      final cacheRead = Completer<void>();
      final cache = MemoryTranslationCache()
        ..readHandler = (key) {
          if (!cacheRead.isCompleted) cacheRead.complete();
          return cacheResult.future;
        };
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
            documents: {'alpha': '# Original'},
          ),
          translationRepository: fakeAppTranslationRepository(cache: cache),
          initialLocation: '/installed/alpha',
        ),
      );
      await _pumpUntil(tester, () => cacheRead.isCompleted);

      expect(find.byKey(const Key('skill-detail')), findsOneWidget);
      expect(find.byKey(const Key('document-loading')), findsOneWidget);
      expect(find.byKey(const Key('skill-markdown')), findsNothing);
      expect(find.byKey(const Key('skill-description-card')), findsNothing);

      cacheResult.complete(
        CompletedTranslation(
          slotKey: skill.slotKey,
          contentHash: skill.contentHash,
          documentIdentifier: 'SKILL.md',
          targetLanguage: TargetLanguage('zh-Hans'),
          translatedContent: '''---
description: Cached description
---
# Cached translation''',
          provenance: TranslationProvenance(providerIdentifier: 'cache'),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(_markdownData(tester), '# Cached translation');
      expect(find.text('Cached description'), findsOneWidget);
      expect(find.text('Original'), findsNothing);
      final animation = tester.widget<TweenAnimationBuilder<double>>(
        _contentRevealAnimation(),
      );
      expect(animation.duration, const Duration(milliseconds: 100));
      expect(animation.curve, Curves.easeOutCubic);
      expect(animation.tween.begin, 0);
      expect(animation.tween.end, 1);
      expect(
        tester.widget<Opacity>(_contentRevealOpacity()).opacity,
        closeTo(0, 0.001),
      );

      await tester.pump(const Duration(milliseconds: 90));
      final midpoint = tester.widget<Opacity>(_contentRevealOpacity()).opacity;
      expect(midpoint, greaterThan(0));
      expect(midpoint, lessThan(1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<Opacity>(_contentRevealOpacity()).opacity,
        closeTo(1, 0.001),
      );
    },
  );

  testWidgets('shows source content after an empty cache lookup resolves', (
    tester,
  ) async {
    final cacheResult = Completer<CompletedTranslation?>();
    final cache = MemoryTranslationCache()
      ..readHandler = (_) => cacheResult.future;
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(
            revision: 1,
            skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha Skill')],
          ),
          documents: {'alpha': '# Original'},
        ),
        translationRepository: fakeAppTranslationRepository(cache: cache),
        initialLocation: '/installed/alpha',
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('document-loading')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const Key('skill-markdown')), findsNothing);

    cacheResult.complete(null);
    await tester.pump();
    await tester.pump();

    expect(_markdownData(tester), '# Original');
    expect(_contentRevealAnimation(), findsOneWidget);
  });

  testWidgets('shows ready content without a reveal for reduced motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(
            revision: 1,
            skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha Skill')],
          ),
          documents: {'alpha': '# Original'},
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();

    expect(_markdownData(tester), '# Original');
    expect(find.byKey(const Key('skill-content-reveal')), findsOneWidget);
    expect(_contentRevealAnimation(), findsNothing);
    expect(_contentRevealOpacity(), findsNothing);
  });

  testWidgets('removes the old document while the new cache is unresolved', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final guideCache = Completer<CompletedTranslation?>();
    final cache = MemoryTranslationCache()
      ..readHandler = (key) => key.documentIdentifier == 'guide.md'
          ? guideCache.future
          : Future.value(null);
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {'alpha': '# Original'},
          additionalDocuments: const {
            'alpha': {'guide.md': '# Guide source'},
          },
        ),
        translationRepository: fakeAppTranslationRepository(cache: cache),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    expect(_markdownData(tester), '# Original');

    await tester.tap(find.byKey(const Key('skill-file-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-document-file-guide.md')));
    await _pumpUntil(
      tester,
      () => find.byKey(const Key('document-loading')).evaluate().isNotEmpty,
    );

    expect(find.byKey(const Key('skill-markdown')), findsNothing);
    expect(find.text('Original'), findsNothing);
    expect(find.text('Guide source'), findsNothing);

    guideCache.complete(
      CompletedTranslation(
        slotKey: skill.slotKey,
        contentHash: skill.contentHash,
        documentIdentifier: 'guide.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: '# Guide translation',
        provenance: TranslationProvenance(providerIdentifier: 'cache'),
      ),
    );
    await tester.pumpAndSettle();

    expect(_markdownData(tester), '# Guide translation');
    expect(find.text('Guide source'), findsNothing);
  });

  testWidgets('keeps the final live block replacement mounted to finish', (
    tester,
  ) async {
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    const source = '# Original';
    final blockId = const MarkdownSourceParser().parse(source).blocks.single.id;
    final provider = _ControlledTranslationProvider();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {'alpha': source},
        ),
        translationRepository: fakeAppTranslationRepository(
          providerFactory: _ControlledTranslationFactory(provider),
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    final job = await _startTranslation(tester, provider);
    job.emitDraft(
      TranslationDraft(
        translatedBlocks: {blockId: '# 译文'},
        translatedDescription: null,
        completedBlockCount: 1,
        totalBlockCount: 1,
      ),
    );
    await tester.pump();

    var markdown = tester.widget<MarkdownWidget>(
      find.byKey(const Key('skill-markdown')),
    );
    expect(markdown.sourceDocument, isNotNull);
    expect(markdown.replacements, {blockId: '# 译文'});

    job.complete(
      CompletedTranslation(
        slotKey: skill.slotKey,
        contentHash: skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: '# 译文',
        provenance: TranslationProvenance(providerIdentifier: 'controlled'),
      ),
    );
    await tester.pump();
    await tester.pump();

    markdown = tester.widget<MarkdownWidget>(
      find.byKey(const Key('skill-markdown')),
    );
    expect(markdown.sourceDocument, isNotNull);
    expect(markdown.replacements, {blockId: '# 译文'});

    await tester.pump(const Duration(milliseconds: 430));
    expect(
      tester
          .widget<MarkdownWidget>(find.byKey(const Key('skill-markdown')))
          .replacements,
      {blockId: '# 译文'},
    );
  });

  testWidgets('does not leak completed replacements across document switches', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1360, 700);
    addTearDown(tester.view.reset);
    final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    const source = '# Original long';
    final blockId = const MarkdownSourceParser().parse(source).blocks.single.id;
    final provider = _ControlledTranslationProvider();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: {'alpha': source},
          additionalDocuments: const {
            'alpha': {'guide.md': '# X'},
          },
        ),
        translationRepository: fakeAppTranslationRepository(
          providerFactory: _ControlledTranslationFactory(provider),
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    final job = await _startTranslation(tester, provider);
    job.emitDraft(
      TranslationDraft(
        translatedBlocks: {blockId: '# 译文'},
        translatedDescription: null,
        completedBlockCount: 1,
        totalBlockCount: 1,
      ),
    );
    await tester.pump();
    job.complete(
      CompletedTranslation(
        slotKey: skill.slotKey,
        contentHash: skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: '# 译文',
        provenance: TranslationProvenance(providerIdentifier: 'controlled'),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('skill-file-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-document-file-guide.md')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_markdownData(tester), '# X');
    final markdown = tester.widget<MarkdownWidget>(
      find.byKey(const Key('skill-markdown')),
    );
    expect(markdown.sourceDocument, isNull);
    expect(markdown.replacements, isEmpty);
  });

  testWidgets(
    'handles a synchronous translation Draft during a document switch',
    (tester) async {
      final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
      const source = '# Original long';
      final blockId = const MarkdownSourceParser()
          .parse(source)
          .blocks
          .single
          .id;
      final provider = _ControlledTranslationProvider();
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
            documents: {'alpha': source},
            additionalDocuments: const {
              'alpha': {'guide.md': '# Guide'},
            },
          ),
          translationRepository: fakeAppTranslationRepository(
            providerFactory: _ControlledTranslationFactory(provider),
          ),
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      final job = await _startTranslation(tester, provider);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('skill-detail'))),
      );

      job.emitDraft(
        TranslationDraft(
          translatedBlocks: {blockId: '# 译文'},
          translatedDescription: null,
          completedBlockCount: 1,
          totalBlockCount: 1,
        ),
      );
      final switchFuture = container
          .read(skillBrowserViewModelProvider.notifier)
          .selectDocument('guide.md');
      await tester.pump();

      expect(tester.takeException(), isNull);
      await switchFuture;
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('skill-markdown')).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_markdownData(tester), '# Guide');
    },
  );

  testWidgets(
    'animates a frontmatter Markdown file in full-document coordinates',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1360, 700);
      addTearDown(tester.view.reset);
      final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
      const guide = '''---
description: Guide metadata
---

# Guide
''';
      final display = parseTranslationDisplayDocument(
        documentIdentifier: 'references/guide.md',
        content: guide,
      );
      final bodyBlockId = display.blocks.last.id;
      final provider = _ControlledTranslationProvider();
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
            documents: {'alpha': '# Alpha'},
            additionalDocuments: const {
              'alpha': {'references/guide.md': guide},
            },
          ),
          translationRepository: fakeAppTranslationRepository(
            providerFactory: _ControlledTranslationFactory(provider),
          ),
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill-file-picker')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('skill-document-directory-references')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('skill-document-file-references/guide.md')),
      );
      await tester.pumpAndSettle();

      final job = await _startTranslation(tester, provider);
      job.emitDraft(
        TranslationDraft(
          translatedBlocks: {bodyBlockId: '# 指南'},
          translatedDescription: '元数据说明',
          completedBlockCount: 2,
          totalBlockCount: 2,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final markdown = tester.widget<MarkdownWidget>(
        find.byKey(const Key('skill-markdown')),
      );
      expect(markdown.sourceDocument?.source, guide);
      expect(markdown.replacements, {bodyBlockId: '# 指南'});
      expect(
        markdown.sourceDocument?.applyReplacements(markdown.replacements),
        '''---
description: Guide metadata
---

# 指南
''',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('skill-description-card')),
          matching: find.text('Alpha Skill description'),
        ),
        findsOneWidget,
      );
      expect(find.text('元数据说明'), findsNothing);

      job.complete(const TranslationJobCancellation());
      await tester.pump();
    },
  );

  testWidgets('animates only a live Draft description with blur and fade', (
    tester,
  ) async {
    final provider = _ControlledTranslationProvider();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(
            revision: 1,
            skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha Skill')],
          ),
          documents: {'alpha': '# Alpha'},
        ),
        translationRepository: fakeAppTranslationRepository(
          providerFactory: _ControlledTranslationFactory(provider),
        ),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    final job = await _startTranslation(tester, provider);
    expect(find.byKey(const Key('translation-feedback')), findsNothing);

    job.emitDraft(
      TranslationDraft(
        translatedBlocks: const {},
        translatedDescription: 'Live description',
        completedBlockCount: 1,
        totalBlockCount: 1,
      ),
    );
    await tester.pump();

    final animation = tester.widget<TweenAnimationBuilder<double>>(
      _descriptionAnimation(),
    );
    expect(animation.duration, const Duration(milliseconds: 420));
    expect(animation.curve, Curves.easeOutCubic);
    expect(animation.tween.begin, 0);
    expect(animation.tween.end, 1);
    expect(
      tester.widget<Opacity>(_descriptionOpacity()).opacity,
      closeTo(0.72, 0.001),
    );
    expect(_descriptionImageFilter(), findsOneWidget);
    expect(
      tester
          .widget<ImageFiltered>(_descriptionImageFilter())
          .imageFilter
          .toString(),
      contains('5.0'),
    );

    job.complete(const TranslationJobCancellation());
    await tester.pump();
  });

  testWidgets(
    'renders a live Draft description statically for reduced motion',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final provider = _ControlledTranslationProvider();
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(
              revision: 1,
              skills: [testSkill(slotKey: 'alpha', displayName: 'Alpha Skill')],
            ),
            documents: {'alpha': '# Alpha'},
          ),
          translationRepository: fakeAppTranslationRepository(
            providerFactory: _ControlledTranslationFactory(provider),
          ),
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      final job = await _startTranslation(tester, provider);

      job.emitDraft(
        TranslationDraft(
          translatedBlocks: const {},
          translatedDescription: 'Static live description',
          completedBlockCount: 1,
          totalBlockCount: 1,
        ),
      );
      await tester.pump();

      expect(find.text('Static live description'), findsOneWidget);
      expect(_descriptionAnimation(), findsNothing);
      expect(_descriptionImageFilter(), findsNothing);
      expect(_descriptionOpacity(), findsNothing);

      job.complete(const TranslationJobCancellation());
      await tester.pump();
    },
  );

  testWidgets(
    'a recovery-blocked Skill shows no banner between the title and the document picker',
    (tester) async {
      final workspace = FakeSkillsWorkspaceRepository(
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
              integrity: WorkspaceSkillIntegrityStatus.revisionStoreCorrupt,
            ),
          ],
        ),
      );

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
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('workspace-integrity-recovery')),
        findsNothing,
      );
      expect(find.byKey(const Key('workspace-operation-error')), findsNothing);
      expect(find.byKey(const Key('skill-integrity-label')), findsOneWidget);
      expect(find.byType(SkillDocumentBrowserPopover), findsOneWidget);
    },
  );
  for (final integrity in WorkspaceSkillIntegrityStatus.values) {
    testWidgets(
      'external change review action is drift-only for ${integrity.name}',
      (tester) async {
        final workspace = FakeSkillsWorkspaceRepository(
          snapshot: driftWidgetSnapshot(integrity: integrity),
        );
        await tester.pumpWidget(
          skillsManagerTestApp(
            browserRepository: FakeSkillBrowserRepository(
              catalog: InstalledSkillCatalog(
                revision: 1,
                skills: [
                  testSkill(slotKey: 'alpha', displayName: 'Alpha Skill'),
                ],
              ),
              documents: {'alpha': '# Alpha'},
            ),
            workspaceRepository: workspace,
            initialLocation: '/installed/alpha',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('skill-drift-review-action')),
          integrity == WorkspaceSkillIntegrityStatus.driftPending
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.byKey(const Key('workspace-operation-error')),
          findsNothing,
        );
        expect(find.byType(SkillDocumentBrowserPopover), findsOneWidget);
      },
    );
  }

  testWidgets(
    'external change action opens the routed review for the selected Skill',
    (tester) async {
      final workspace = driftWidgetWorkspace();
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
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.byKey(const Key('skill-drift-review-action')))
            .overlaps(tester.getRect(find.byKey(const Key('remove-skill')))),
        isFalse,
        reason: 'The drift action must preserve the remove action hit target.',
      );
      await tester.tap(find.byKey(const Key('skill-drift-review-action')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('skill-drift-review-dialog')),
        findsOneWidget,
      );
      expect(workspace.inspectedSkillDrifts, [driftWidgetSkillId]);
    },
  );

  testWidgets(
    'completed drift resolution clears the entry point through same-revision integrity only',
    (tester) async {
      final workspace = driftWidgetWorkspace()
        ..resolveSkillDriftIntegrity = WorkspaceSkillIntegrityStatus.healthy;
      final originalRevision = workspace.current.revision;
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
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('skill-drift-review-action')),
        findsOneWidget,
      );
      // The review action alone announces the drift; the title stays clean.
      expect(find.byKey(const Key('skill-integrity-label')), findsNothing);
      await tester.tap(find.byKey(const Key('skill-drift-review-action')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('skill-drift-select-restore')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('skill-drift-select-restore')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill-drift-restore')));
      await tester.pumpAndSettle();
      expect(
        workspace.current.skills.single.integrity,
        WorkspaceSkillIntegrityStatus.healthy,
      );
      expect(workspace.favoriteRequests.length, 0);
      expect(workspace.noteRequests.length, 0);
      expect(workspace.current.revision, originalRevision);
      expect(workspace.resolvedSkillDrifts, hasLength(1));
      expect(find.byKey(const Key('skill-drift-review-dialog')), findsNothing);
      expect(find.byKey(const Key('skill-drift-review-action')), findsNothing);
      expect(find.byKey(const Key('skill-integrity-label')), findsNothing);
      expect(find.byKey(const Key('skill-detail')), findsOneWidget);
    },
  );

  for (final integrity in [
    WorkspaceSkillIntegrityStatus.healthy,
    WorkspaceSkillIntegrityStatus.driftPending,
    WorkspaceSkillIntegrityStatus.repairFailed,
    WorkspaceSkillIntegrityStatus.revisionStoreCorrupt,
  ]) {
    testWidgets(
      'removal warns about external bytes only for ${integrity.name}',
      (tester) async {
        final workspace = FakeSkillsWorkspaceRepository(
          snapshot: driftWidgetSnapshot(integrity: integrity),
        );
        await tester.pumpWidget(
          skillsManagerTestApp(
            browserRepository: FakeSkillBrowserRepository(
              catalog: InstalledSkillCatalog(
                revision: 1,
                skills: [
                  testSkill(slotKey: 'alpha', displayName: 'Alpha Skill'),
                ],
              ),
              documents: {'alpha': '# Alpha'},
            ),
            workspaceRepository: workspace,
            initialLocation: '/installed/alpha',
          ),
        );
        await tester.pumpAndSettle();
        if (integrity == WorkspaceSkillIntegrityStatus.driftPending) {
          expect(
            tester
                .getRect(find.byKey(const Key('skill-drift-review-action')))
                .overlaps(
                  tester.getRect(find.byKey(const Key('remove-skill'))),
                ),
            isFalse,
            reason: 'Review and remove must remain independently clickable.',
          );
        }
        await tester.tap(find.byKey(const Key('remove-skill')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('remove-skill-dialog')), findsOneWidget);
        expect(
          find.byKey(const Key('remove-skill-drift-warning')),
          integrity == WorkspaceSkillIntegrityStatus.driftPending
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.byKey(const Key('remove-confirm')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        expect(workspace.removals, isEmpty);
      },
    );
  }
}

SkillsWorkspaceSnapshot _workspaceRefreshSnapshot() => SkillsWorkspaceSnapshot(
  revision: 1,
  projectRoots: const [],
  skills: [
    WorkspaceSkill(
      id: WorkspaceSkillId('managed-alpha'),
      slotKey: 'alpha',
      declaredName: 'alpha',
      displayName: 'Alpha Skill',
      description: 'Alpha description',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/source',
      ),
      currentRevision: SkillRevision(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 7,
        acquiredAt: DateTime(2026),
        resolvedSourceRevision: 'local',
      ),
      activations: const [],
    ),
  ],
);

Finder _descriptionAnimation() => find.descendant(
  of: find.byKey(const Key('skill-description-card')),
  matching: find.byWidgetPredicate(
    (widget) => widget is TweenAnimationBuilder<double>,
  ),
);

Finder _descriptionImageFilter() => find.descendant(
  of: find.byKey(const Key('skill-description-card')),
  matching: find.byType(ImageFiltered),
);

Finder _descriptionOpacity() => find.descendant(
  of: find.byKey(const Key('skill-description-card')),
  matching: find.byType(Opacity),
);

Finder _contentRevealAnimation() => find.descendant(
  of: find.byKey(const Key('skill-content-reveal')),
  matching: find.byWidgetPredicate(
    (widget) => widget is TweenAnimationBuilder<double>,
  ),
);

Finder _contentRevealOpacity() => find.descendant(
  of: find.byKey(const Key('skill-content-reveal')),
  matching: find.byType(Opacity),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.pump();
    if (condition()) return;
  }
  fail('Condition did not become true.');
}

Future<void> _pumpUntilTakeoverDialog(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find
        .byKey(const Key('activation-takeover-dialog'))
        .evaluate()
        .isNotEmpty,
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Future<_ControlledTranslationJob> _startTranslation(
  WidgetTester tester,
  _ControlledTranslationProvider provider,
) async {
  await tester.tap(find.byKey(const Key('skill-language-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-translation')));
  for (var attempt = 0; attempt < 30; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    final job = provider.job;
    if (job != null) return job;
  }
  fail('Translation Job did not start.');
}

final class _ControlledTranslationFactory
    implements AppTranslationProviderFactory {
  const _ControlledTranslationFactory(this.provider);

  final _ControlledTranslationProvider provider;

  @override
  TranslationProvider create({
    required TranslationProviderProfile profile,
    required String? apiKey,
  }) => provider;
}

final class _ControlledTranslationProvider implements TranslationProvider {
  _ControlledTranslationJob? job;
  TranslationScope? lastScope;

  @override
  TranslationJob start({
    required SourceDocument sourceDocument,
    required TargetLanguage targetLanguage,
    TranslationScope scope = TranslationScope.fullDocument,
  }) {
    lastScope = scope;
    return job = _ControlledTranslationJob();
  }
}

final class _ControlledTranslationJob implements TranslationJob {
  final _drafts = StreamController<TranslationDraft>.broadcast(sync: true);
  final _result = Completer<TranslationJobOutcome>();

  @override
  Stream<TranslationDraft> get drafts => _drafts.stream;

  @override
  Future<TranslationJobOutcome> get result => _result.future;

  void emitDraft(TranslationDraft draft) => _drafts.add(draft);

  void complete(TranslationJobOutcome outcome) {
    if (!_drafts.isClosed) unawaited(_drafts.close());
    if (!_result.isCompleted) _result.complete(outcome);
  }

  @override
  Future<void> cancel() async {
    if (!_drafts.isClosed) await _drafts.close();
    if (!_result.isCompleted) {
      _result.complete(const TranslationJobCancellation());
    }
  }
}

final class _RecordingFileLocationOpener implements FileLocationOpener {
  final List<String> paths = [];

  @override
  Future<bool> reveal(String path) async {
    paths.add(path);
    return true;
  }
}

Finder _findSkillSectionTab(IconData icon) => find.descendant(
  of: find.byKey(const Key('skill-section-tabs')),
  matching: find.byIcon(icon),
);

bool _isDocumentBrowserRowSelected(WidgetTester tester, Key key) => tester
    .widget<Semantics>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected != null,
        ),
      ),
    )
    .properties
    .selected!;

String _markdownData(WidgetTester tester) => tester
    .widget<MarkdownWidget>(find.byKey(const Key('skill-markdown')))
    .markdown
    .markdown;

Finder _locationOption(String path) => find.byWidgetPredicate((widget) {
  if (widget is! AppMorphingMenuOption) return false;
  final key = widget.key;
  return key is ValueKey && key.value is ActivationLocationKey
      ? (key.value as ActivationLocationKey).location == path
      : false;
});

const _sharedGlobalTargets = [
  WorkspaceActivationTarget(
    agentId: 'codex',
    displayName: 'Codex',
    detected: true,
    location: '/global/.agents/skills',
    scope: WorkspaceScope.global,
  ),
  WorkspaceActivationTarget(
    agentId: 'opencode',
    displayName: 'OpenCode',
    detected: true,
    location: '/global/.agents/skills',
    scope: WorkspaceScope.global,
  ),
  WorkspaceActivationTarget(
    agentId: 'universal',
    displayName: 'Universal',
    detected: false,
    location: '/global/.agents/skills',
    scope: WorkspaceScope.global,
  ),
  WorkspaceActivationTarget(
    agentId: 'aider',
    displayName: 'Aider',
    detected: false,
    location: '/global/.agents/skills',
    scope: WorkspaceScope.global,
  ),
  WorkspaceActivationTarget(
    agentId: 'cline',
    displayName: 'Cline',
    detected: false,
    location: '/global/.agents/skills',
    scope: WorkspaceScope.global,
  ),
  // Installed too, but reading its own directory: part of the denominator.
  WorkspaceActivationTarget(
    agentId: 'claude-code',
    displayName: 'Claude Code',
    detected: true,
    location: '/global/.claude/skills',
    scope: WorkspaceScope.global,
  ),
];

WorkspaceSkill _sharedDirectorySkill({
  required String slotKey,
  required String displayName,
  required List<String> agentIds,
  bool alsoClaudeCode = false,
}) => WorkspaceSkill(
  id: WorkspaceSkillId(slotKey),
  slotKey: slotKey,
  declaredName: slotKey,
  displayName: displayName,
  description: '$displayName description',
  source: SkillSourceProvenance(
    kind: WorkspaceSourceKind.local,
    locator: '/source/$slotKey',
  ),
  currentRevision: SkillRevision(
    contentHash: 'a' * 64,
    fileCount: 1,
    byteSize: 1,
    acquiredAt: DateTime.utc(2026),
  ),
  activations: [
    if (agentIds.isNotEmpty)
      SkillActivationLocation(
        location: '/global/.agents/skills',
        scope: WorkspaceScope.global,
        mode: WorkspaceActivationMode.copy,
        agentIds: agentIds,
      ),
    if (alsoClaudeCode)
      SkillActivationLocation(
        location: '/global/.claude/skills',
        scope: WorkspaceScope.global,
        mode: WorkspaceActivationMode.copy,
        agentIds: const ['claude-code'],
      ),
  ],
);

/// The collapsed trigger of the detail page's document picker.
///
/// The detail header now holds two morphing menus, so the shared trigger key
/// has to be scoped to the one under test.
final Finder _documentPickerTrigger = find.descendant(
  of: find.byKey(const Key('skill-file-picker')),
  matching: find.byKey(const ValueKey<String>('morphing-menu-button-trigger')),
);

/// Whether the translate control paints the filled "the translation is on
/// screen" surface rather than the default one.
bool _translateButtonFilled(WidgetTester tester) =>
    tester
        .widget<MorphingMenuButton>(
          find.descendant(
            of: find.byKey(const Key('skill-language-button')),
            matching: find.byType(MorphingMenuButton),
          ),
        )
        .style!
        .collapsedBackgroundColor ==
    AppColors.ink;

/// The full-Skill / description-only choice on the translation card.
CupertinoSlidingSegmentedControl<TranslationScope> _translationScopeControl(
  WidgetTester tester,
) => tester.widget(find.byKey(const Key('translation-scope-control')));

MemoryTranslationCache _cachedTranslationFor(
  InstalledSkill skill,
  String translatedContent,
) => MemoryTranslationCache()
  ..values[TranslationCacheKey(
    slotKey: skill.slotKey,
    contentHash: skill.contentHash,
    documentIdentifier: 'SKILL.md',
    targetLanguage: TargetLanguage('zh-Hans'),
  )] = CompletedTranslation(
    slotKey: skill.slotKey,
    contentHash: skill.contentHash,
    documentIdentifier: 'SKILL.md',
    targetLanguage: TargetLanguage('zh-Hans'),
    translatedContent: translatedContent,
    provenance: TranslationProvenance(providerIdentifier: 'cache'),
  );

Finder _activationBadge(String summary) => find.byWidgetPredicate(
  (widget) => widget is AppTooltip && widget.message == summary,
);
