import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/settings/data/workspace_validation_history_store.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/skills/data/services/directory_picker.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/translation/data/services/translation_settings_store.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_cupertino_controls.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_header.dart';
import 'package:skills_manager/features/settings/presentation/view_models/open_source_licenses.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_translation/skills_translation.dart';

import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_app_translation_repository.dart';
import '../../../../support/fake_skill_acquisition_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/scripted_translation_provider.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  testWidgets('lists the grouped sections in a narrow window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        initialLocation: '/settings',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-page-title')), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.byKey(const Key('settings-section-list')), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    for (final id in [
      'appearance',
      'general',
      'agents',
      'translation',
      'maintenance',
      'about',
    ]) {
      expect(find.byKey(Key('settings-section-$id')), findsOneWidget);
    }
    expect(find.byKey(const Key('settings-section-environment')), findsNothing);
    expect(find.byKey(const Key('general-settings')), findsNothing);
  });

  testWidgets('opens the first section by default in a wide window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: FakeSkillsWorkspaceRepository(
          snapshot: _snapshotWithRoots(['/workspace/project']),
        ),
        initialLocation: '/settings',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-section-list')), findsOneWidget);
    expect(find.byKey(const Key('appearance-settings')), findsOneWidget);
    expect(find.byKey(const Key('general-settings')), findsNothing);

    await tester.tap(find.byKey(const Key('settings-section-general')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('general-settings')), findsOneWidget);
    expect(find.text('Interface language'), findsOneWidget);
    expect(find.text('/workspace/project'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-manage-project-roots')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('settings-section-translation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('translation-settings')), findsOneWidget);
    expect(find.byKey(const Key('general-settings')), findsNothing);
  });

  testWidgets('maps section links from earlier releases', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final (legacy, content) in [
      ('project-roots', 'general-settings'),
      ('language', 'general-settings'),
      ('custom-agents', 'agents-settings'),
      ('workspace-validation', 'maintenance-settings'),
      ('environment', 'maintenance-settings'),
      ('updates', 'about-skilldeck-settings'),
    ]) {
      // A fresh App per link, so each one starts its own router.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(),
          initialLocation: '/settings?section=$legacy',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(Key(content)), findsOneWidget, reason: legacy);
    }
  });

  testWidgets('routes to a setting detail page in a narrow window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        initialLocation: '/settings',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-section-translation')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-detail-back')), findsOneWidget);
    expect(find.byKey(const Key('translation-settings')), findsOneWidget);
    expect(find.byKey(const Key('settings-section-list')), findsNothing);

    await tester.tap(find.byKey(const Key('settings-detail-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-section-list')), findsOneWidget);
  });

  testWidgets('renders SkillDeck about settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        initialLocation: '/settings?section=about',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('about-skilldeck-settings')), findsOneWidget);
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.byKey(const Key('self-update-settings')), findsOneWidget);
    expect(find.byKey(const Key('settings-official-website')), findsOneWidget);
    expect(find.byKey(const Key('settings-changelog')), findsOneWidget);
    expect(find.byKey(const Key('settings-privacy-policy')), findsOneWidget);
    expect(find.byKey(const Key('settings-terms-of-service')), findsOneWidget);
    expect(find.byKey(const Key('settings-licenses')), findsOneWidget);
    expect(find.byKey(const Key('analytics-enabled-switch')), findsNothing);
  });

  testWidgets('reads a component license in the open source licenses dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The real registry reads bundled assets and parses Flutter's notices on
    // another isolate, which a widget test's fake clock never completes, so
    // the dialog is fed two packages directly; the loader has its own test.
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        initialLocation: '/settings?section=about',
        overrides: [
          openSourceLicensesProvider.overrideWith(
            (ref) async => [
              OpenSourceLicensePackage(
                name: 'libgit2',
                licenses: [
                  const LicenseEntryWithLineBreaks(['libgit2'], 'GPLv2'),
                  const LicenseEntryWithLineBreaks(['libgit2'], 'zlib'),
                ],
              ),
              OpenSourceLicensePackage(
                name: 'SQLite',
                licenses: [
                  const LicenseEntryWithLineBreaks([
                    'SQLite',
                  ], 'SQLite is in the public domain.'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-licenses')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('open-source-licenses-dialog')),
      findsOneWidget,
    );
    expect(find.text('2 licenses'), findsOneWidget);
    expect(find.text('Open source licenses'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-source-license-SQLite')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-source-license-detail')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('open-source-license-title')))
          .data,
      'SQLite',
    );
    expect(find.textContaining('public domain'), findsWidgets);

    await tester.tap(find.byKey(const Key('open-source-licenses-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('open-source-licenses-dialog')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-source-licenses-dialog')), findsNothing);
  });

  testWidgets('chooses the interface language and activation method', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        initialLocation: '/settings?section=general',
      ),
    );
    await tester.pumpAndSettle();
    final control = find.byKey(const Key('global-activation-method-control'));
    final description = find.byKey(
      const Key('global-activation-method-description'),
    );
    final l10n = tester.element(control).l10n;

    expect(
      tester
          .widget<AppSegmentedControl<WorkspaceActivationMethod>>(control)
          .value,
      WorkspaceActivationMethod.automatic,
    );
    expect(
      tester.widget<Text>(description).data,
      l10n.settingsActivationMethodAutomaticDescription,
    );

    await tester.tap(
      find.descendant(
        of: control,
        matching: find.text(l10n.settingsActivationMethodCopy),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(control));
    expect(
      container.read(globalActivationMethodProvider),
      WorkspaceActivationMethod.copy,
    );
    expect(
      tester.widget<Text>(description).data,
      l10n.settingsActivationMethodCopyDescription,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('interface-language-control')),
        matching: find.text('中文'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(appSettingsViewModelProvider).settings.localePreference,
      AppLocalePreference.zh,
    );
  });

  testWidgets('adds and removes project roots from General', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = FakeSkillsWorkspaceRepository(
      snapshot: _snapshotWithRoots(['/workspace/old']),
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: workspace,
        directoryPicker: const _FixedDirectoryPicker('/workspace/new'),
        initialLocation: '/settings?section=general',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-project-root-add')));
    await tester.pumpAndSettle();
    expect(find.text('/workspace/new'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('settings-project-root-remove-project-0')),
    );
    await tester.pumpAndSettle();
    expect(find.text('/workspace/old'), findsNothing);
    expect(find.text('/workspace/new'), findsOneWidget);
  });

  testWidgets('switches built-in Agents and lists custom Agents', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: FakeSkillAcquisitionRepository(
          agents: const [
            AgentOption(
              id: 'codex',
              displayName: 'Codex',
              location: '/global/codex/skills',
            ),
            AgentOption(
              id: 'cursor',
              displayName: 'Cursor',
              location: '/global/cursor/skills',
              detected: false,
            ),
          ],
        ),
        initialLocation: '/settings?section=agents',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agents-settings')), findsOneWidget);
    expect(find.byKey(const Key('managed-agent-cursor')), findsNothing);
    await tester.tap(find.byKey(const Key('settings-agents-show-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('managed-agent-cursor')), findsOneWidget);
    expect(find.byKey(const Key('settings-manage-agents')), findsNothing);
    expect(find.byKey(const Key('settings-add-agent')), findsOneWidget);
    expect(
      find.byKey(const Key('settings-custom-agents-empty')),
      findsOneWidget,
    );

    final membership = find.byKey(const Key('agent-membership-codex'));
    expect(tester.widget<CupertinoSwitch>(membership).value, isTrue);
    await tester.tap(membership);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(membership));
    expect(
      container
          .read(appSettingsViewModelProvider)
          .settings
          .builtInAgentVisibilityOverrides['codex'],
      isFalse,
    );
  });

  testWidgets('collapses the settings title under the global top blur', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        workspaceRepository: FakeSkillsWorkspaceRepository(
          snapshot: _snapshotWithRoots([
            for (var index = 0; index < 24; index++)
              '/workspace/project-$index',
          ]),
        ),
        initialLocation: '/settings?section=general',
      ),
    );
    await tester.pumpAndSettle();

    final scroll = find.byKey(const Key('settings-page-scroll'));
    final title = find.byKey(const Key('settings-page-title'));
    final blur = find.byKey(const Key('settings-top-blur'));
    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.expandedTitleFontSize,
    );
    expect(find.descendant(of: blur, matching: title), findsNothing);

    await tester.drag(scroll, const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(title).style!.fontSize,
      AppCollapsingHeaderMetrics.collapsedTitleFontSize,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the last validation and records a new one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final history = InMemoryWorkspaceValidationHistoryStore(
      WorkspaceValidationRecord(
        completedAt: DateTime(2026, 10, 1, 9, 5),
        failed: false,
        checkedSkillCount: 3,
      ),
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        validationHistoryStore: history,
        initialLocation: '/settings?section=maintenance',
      ),
    );
    await tester.pumpAndSettle();

    final status = find.byKey(const Key('workspace-validation-status'));
    expect(tester.widget<Text>(status).data, contains('2026-10-01 09:05'));
    expect(tester.widget<Text>(status).data, contains('Checked 3'));

    await tester.tap(find.byKey(const Key('settings-validate-workspace')));
    await tester.pumpAndSettle();

    final recorded = await history.readLast();
    expect(recorded!.completedAt.isAfter(DateTime.utc(2026, 10, 2)), isTrue);
    expect(tester.widget<Text>(status).data, contains('Checked 0'));
    expect(find.byKey(const Key('environment-settings')), findsOneWidget);
  });

  testWidgets('tests the connection with the unsaved form', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final factory = ScriptedTranslationProviderFactory();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        translationRepository: fakeAppTranslationRepository(
          providerFactory: factory,
        ),
        initialLocation: '/settings?section=translation',
      ),
    );
    await tester.pumpAndSettle();
    final title = find.byKey(const Key('translation-status-title'));
    expect(tester.widget<Text>(title).data, 'Configured · OpenAI compatible');

    await tester.enterText(
      find.byKey(const Key('translation-model-field')),
      'draft-model',
    );
    await tester.enterText(
      find.byKey(const Key('translation-api-key-field')),
      'typed-key',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('translation-test-connection')));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(title).data, 'Connection works');
    expect(factory.profiles.single.model, 'draft-model');
    expect(factory.apiKeys.single, 'typed-key');

    factory.outcome = TranslationFailure(
      code: TranslationFailureCode.authenticationFailed,
      reason: 'Rejected key.',
    );
    await tester.tap(find.byKey(const Key('translation-test-connection')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(title).data, 'Connection failed');
    expect(
      find.text('The API key was rejected or has no access to this model.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('translation-model-field')),
      'edited-again',
    );
    await tester.pump();
    expect(tester.widget<Text>(title).data, 'Configured · OpenAI compatible');
  });

  testWidgets('marks unsaved translation edits and reverts them', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        initialLocation: '/settings?section=translation',
      ),
    );
    await tester.pumpAndSettle();
    final unsaved = find.byKey(const Key('translation-unsaved-changes'));
    final revert = find.byKey(const Key('translation-settings-revert'));
    final model = find.byKey(const Key('translation-model-field'));
    expect(unsaved, findsNothing);
    expect(tester.widget<AppButton>(revert).onPressed, isNull);

    await tester.enterText(model, 'draft-model');
    await tester.pump();
    expect(unsaved, findsOneWidget);

    await tester.ensureVisible(revert);
    await tester.tap(revert);
    await tester.pumpAndSettle();
    expect(unsaved, findsNothing);
    expect(tester.widget<CupertinoTextField>(model).controller!.text, isEmpty);
  });

  testWidgets(
    'persists defaults and a replacement API key without plaintext JSON',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1360, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settingsStore = MemoryTranslationSettingsStore();
      final credentialStore = MemoryTranslationCredentialStore();
      final presenter = _RecordingPresenter();
      final repository = fakeAppTranslationRepository(
        settingsStore: settingsStore,
        credentialStore: credentialStore,
      );
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(),
          translationRepository: repository,
          notificationPresenter: presenter,
          initialLocation: '/settings?section=translation',
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('settings-page-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      final advanced = find.byKey(const Key('translation-advanced-toggle'));
      await tester.scrollUntilVisible(advanced, 220, scrollable: scrollable);
      await tester.ensureVisible(advanced);
      await tester.pumpAndSettle();
      await tester.tap(advanced);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const Key('translation-budget-field')),
            )
            .controller!
            .text,
        isEmpty,
      );
      final modelField = tester.widget<CupertinoTextField>(
        find.byKey(const Key('translation-model-field')),
      );
      expect(modelField.controller!.text, isEmpty);
      expect(modelField.placeholder, 'gpt-5.4-mini');
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const Key('translation-concurrency-field')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const Key('translation-max-output-field')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.byKey(const Key('translation-prompt-only-switch')),
        findsNothing,
      );
      expect(
        tester
            .widget<CupertinoSwitch>(
              find.byKey(const Key('translation-reasoning-switch')),
            )
            .value,
        isFalse,
      );

      await tester.enterText(
        find.byKey(const Key('translation-api-key-field')),
        'widget-secret',
      );
      final save = find.byKey(const Key('translation-settings-save'));
      expect(tester.widget<AppButton>(save).style, NeoButtonVariant.primary);
      await tester.drag(scrollable, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(settingsStore.value.toString(), isNot(contains('widget-secret')));
      expect(credentialStore.values.values, contains('widget-secret'));
      final credentialId =
          (await repository.loadSettings()).activeProfile.credentialId;
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const Key('translation-api-key-field')),
            )
            .controller!
            .text,
        '••••••••',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        (await repository.loadSettings()).activeProfile.credentialId,
        credentialId,
      );
      expect(credentialStore.values, {credentialId: 'widget-secret'});
      expect(
        presenter.presentations,
        contains(
          predicate<AppNotificationPresentation>(
            (presentation) =>
                presentation.content.message == 'Translation settings saved.',
          ),
        ),
      );
    },
  );

  testWidgets('saving an empty Provider form clears its configuration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settingsStore = MemoryTranslationSettingsStore(
      value: AppTranslationSettings.defaults().toJson(),
    );
    final repository = fakeAppTranslationRepository(
      settingsStore: settingsStore,
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        translationRepository: repository,
        initialLocation: '/settings?section=translation',
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('settings-page-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final save = find.byKey(const Key('translation-settings-save'));
    await tester.scrollUntilVisible(save, 220, scrollable: scrollable);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();

    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(settingsStore.value, isNull);
    expect((await repository.loadSettings()).isConfigured, isFalse);
  });

  testWidgets('replacing and clearing the masked API key updates Keychain', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settingsStore = MemoryTranslationSettingsStore();
    final credentialStore = MemoryTranslationCredentialStore();
    final repository = fakeAppTranslationRepository(
      settingsStore: settingsStore,
      credentialStore: credentialStore,
    );
    final initial = await repository.saveProfile(
      TranslationProviderProfile.defaults().copyWith(
        endpoint: 'http://localhost:11434/v1',
      ),
      replacementApiKey: 'stored-secret',
    );
    final credentialId = initial.activeProfile.credentialId!;
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        translationRepository: repository,
        initialLocation: '/settings?section=translation',
      ),
    );
    await tester.pumpAndSettle();
    final keyField = find.byKey(const Key('translation-api-key-field'));
    final controller = tester.widget<CupertinoTextField>(keyField).controller!;
    expect(controller.text, '••••••••');
    expect(controller.text, isNot(contains('stored-secret')));

    await tester.enterText(keyField, 'replacement-secret');
    await tester.pump();
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('settings-page-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final save = find.byKey(const Key('translation-settings-save'));
    await tester.scrollUntilVisible(save, 220, scrollable: scrollable);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final replaced = await repository.loadSettings();
    final replacementId = replaced.activeProfile.credentialId!;
    expect(replacementId, isNot(credentialId));
    expect(credentialStore.values.containsKey(credentialId), isFalse);
    expect(credentialStore.values[replacementId], 'replacement-secret');
    expect(controller.text, '••••••••');

    await tester.scrollUntilVisible(keyField, -220, scrollable: scrollable);
    await tester.enterText(keyField, '•••••••');
    await tester.pump();
    expect(controller.text, isEmpty);
    await tester.scrollUntilVisible(save, 220, scrollable: scrollable);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final saved = await repository.loadSettings();
    expect(saved.isConfigured, isTrue);
    expect(saved.activeProfile.endpoint, 'http://localhost:11434/v1');
    expect(saved.activeProfile.credentialId, isNull);
    expect(credentialStore.values, isEmpty);
  });

  testWidgets('disables translation save while publication is in flight', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settingsStore = _BlockingSettingsStore();
    addTearDown(() {
      if (!settingsStore.allowWrite.isCompleted) {
        settingsStore.allowWrite.complete();
      }
    });
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        translationRepository: fakeAppTranslationRepository(
          settingsStore: settingsStore,
        ),
        initialLocation: '/settings?section=translation',
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find.byKey(const Key('settings-page-scroll'));
    await tester.enterText(
      find.byKey(const Key('translation-endpoint-field')),
      'http://localhost:11434/v1',
    );
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('settings-page-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    final save = find.byKey(const Key('translation-settings-save'));
    await tester.scrollUntilVisible(save, 220, scrollable: scrollable);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.drag(scroll, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.widget<AppButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await tester.pump();
    expect(settingsStore.writeStarted.isCompleted, isTrue);
    await settingsStore.writeStarted.future;
    await tester.pump();

    expect(tester.widget<AppButton>(save).onPressed, isNull);
    settingsStore.allowWrite.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(save).onPressed, isNotNull);
  });

  testWidgets('shows the Environment check in a narrow window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        initialLocation: '/settings?section=maintenance',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('environment-settings')), findsOneWidget);
    expect(find.text('Not checked yet'), findsOneWidget);
    expect(find.byKey(const Key('environment-check-recheck')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

SkillsWorkspaceSnapshot _snapshotWithRoots(List<String> paths) =>
    SkillsWorkspaceSnapshot(
      revision: 1,
      projectRoots: [
        for (final (index, path) in paths.indexed)
          SkillProjectRoot(id: 'project-$index', path: path),
      ],
      skills: const [],
    );

final class _FixedDirectoryPicker implements DirectoryPicker {
  const _FixedDirectoryPicker(this.path);

  final String path;

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async => path;
}

final class _RecordingPresenter implements AppNotificationPresenter {
  final presentations = <AppNotificationPresentation>[];

  @override
  void present(AppNotificationPresentation presentation) {
    presentations.add(presentation);
  }

  @override
  void dismissAll() {}

  @override
  void dispose() {}
}

final class _BlockingSettingsStore implements TranslationSettingsStore {
  final writeStarted = Completer<void>();
  final allowWrite = Completer<void>();
  Map<String, Object?>? value;

  @override
  Future<Map<String, Object?>?> read() async => value;

  @override
  Future<void> write(Map<String, Object?> value) async {
    writeStarted.complete();
    await allowWrite.future;
    this.value = value;
  }

  @override
  Future<void> delete() async => value = null;
}
