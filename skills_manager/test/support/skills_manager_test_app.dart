import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:skills_manager/features/settings/presentation/view_models/appearance_mode.dart';
import 'package:skills_manager/app/app_providers.dart';
import 'package:skills_manager/app/skills_manager_app.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/services/directory_picker.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_source_input_mode.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/features/translation/presentation/view_models/translation_scope_preference.dart';
import 'package:skills_manager/features/updates/data/update_sweep_store.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/shared/platform/platform_providers.dart';
import 'package:skills_manager/shared/platform/file_location_opener.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/notifications/app_notification_providers.dart';
import 'package:skills_translation/skills_translation.dart';

import 'fake_skills_workspace_repository.dart';
import 'fake_app_translation_repository.dart';

import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/data/workspace_validation_history_store.dart';
import 'package:skills_manager/features/settings/presentation/view_models/workspace_validation_view_model.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';

import 'fake_skill_acquisition_repository.dart';
import 'memory_app_settings_store.dart';

Widget skillsManagerTestApp({
  required SkillBrowserRepository browserRepository,
  SkillAcquisitionRepository? acquisitionRepository,
  SkillsWorkspaceRepository? workspaceRepository,
  SkillBrowserCatalogAuthority catalogAuthority =
      SkillBrowserCatalogAuthority.repository,
  DirectoryPicker? directoryPicker,
  bool desktopSupported = true,
  String initialLocation = '/installed',
  Locale locale = const Locale('en'),
  AppNotificationPresenter? notificationPresenter,
  AppTranslationRepository? translationRepository,
  TranslationScopePreferenceStore? translationScopePreferenceStore,
  TranslationScope initialTranslationScope = TranslationScope.fullDocument,
  // Most browser tests assert row geometry, so they pin the list layout
  // rather than inheriting the App default.
  SkillListLayout initialSkillListLayout = SkillListLayout.list,
  SkillListLayoutStore? skillListLayoutStore,
  AppearanceModeStore? appearanceModeStore,
  SkillSourceInputModeStore? skillSourceInputModeStore,
  SkillSourceInputMode initialSourceInputMode = SkillSourceInputMode.smart,
  FileLocationOpener? fileLocationOpener,
  AppSettings initialSettings = const AppSettings(),
  DateTime? lastUpdateSweepAt,
  bool startupUpdateSweep = false,
  WorkspaceValidationHistoryStore? validationHistoryStore,
  // Extra root overrides for a test's own providers.
  List<Override> overrides = const [],
}) {
  final workspace = workspaceRepository ?? FakeSkillsWorkspaceRepository();
  final presenter = notificationPresenter ?? const _NoopNotificationPresenter();
  return ProviderScope(
    overrides: [
      ...overrides,
      appSettingsStoreProvider.overrideWithValue(
        MemoryAppSettingsStore(initialSettings),
      ),
      workspaceValidationHistoryStoreProvider.overrideWithValue(
        validationHistoryStore ?? InMemoryWorkspaceValidationHistoryStore(),
      ),
      if (acquisitionRepository is FakeSkillAcquisitionRepository)
        deviceAgentCatalogProvider.overrideWith((ref) async {
          return [
            for (final agent in acquisitionRepository.agents)
              if (agent.id != 'universal')
                WorkspaceAgentInfo(
                  id: agent.id,
                  displayName: agent.displayName,
                  isBuiltIn: true,
                  supportedScopes: {
                    WorkspaceScope.global,
                    WorkspaceScope.project,
                  },
                  detectedGlobally: agent.detected,
                  detectedProjectRootIds: {},
                ),
          ];
        }),
      skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
      // Shared preferences are unavailable in widget tests, and the sweep TTL
      // must be explicit per test rather than inherited from the host.
      //
      // The startup sweep is suppressed by default with a fresh TTL, so an
      // unrelated widget test never races a background check that rewrites the
      // update action under it. Tests that exercise the sweep opt in.
      skillUpdateSweepStoreProvider.overrideWithValue(
        InMemoryUpdateSweepStore(
          lastUpdateSweepAt ??
              (startupUpdateSweep ? null : DateTime.now().toUtc()),
        ),
      ),
      if (directoryPicker != null)
        directoryPickerProvider.overrideWithValue(directoryPicker),
      if (fileLocationOpener != null)
        fileLocationOpenerProvider.overrideWithValue(fileLocationOpener),
      skillBrowserRepositoryProvider.overrideWithValue(browserRepository),
      skillBrowserCatalogAuthorityProvider.overrideWithValue(catalogAuthority),
      skillAcquisitionRepositoryProvider.overrideWithValue(
        acquisitionRepository,
      ),
      desktopSupportedProvider.overrideWithValue(desktopSupported),
      appInitialLocationProvider.overrideWithValue(initialLocation),
      appNotificationPresenterProvider.overrideWithValue(presenter),
      appTranslationRepositoryProvider.overrideWithValue(
        translationRepository ?? fakeAppTranslationRepository(),
      ),
      initialTranslationScopeProvider.overrideWithValue(
        initialTranslationScope,
      ),
      initialSkillSourceInputModeProvider.overrideWithValue(
        initialSourceInputMode,
      ),
      if (skillSourceInputModeStore != null)
        skillSourceInputModeStoreProvider.overrideWithValue(
          skillSourceInputModeStore,
        ),
      initialSkillListLayoutProvider.overrideWithValue(initialSkillListLayout),
      if (skillListLayoutStore != null)
        skillListLayoutStoreProvider.overrideWithValue(skillListLayoutStore),
      if (appearanceModeStore != null)
        appearanceModeStoreProvider.overrideWithValue(appearanceModeStore),
      if (translationScopePreferenceStore != null)
        translationScopePreferenceStoreProvider.overrideWithValue(
          translationScopePreferenceStore,
        ),
      activeTranslationRequestProvider.overrideWith((ref) {
        final browser = ref.watch(skillBrowserViewModelProvider);
        final skill = browser.selectedSkill;
        final document = browser.document;
        final path = browser.selectedDocumentPath;
        final contentHash = browser.documentContentHash;
        if (skill == null ||
            document == null ||
            path == null ||
            contentHash == null) {
          return null;
        }
        return SourceDocument(
          slotKey: skill.slotKey,
          contentHash: contentHash,
          documentIdentifier: path,
          content: document,
        );
      }),
    ],
    child: SkillsManagerApp(locale: locale),
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
