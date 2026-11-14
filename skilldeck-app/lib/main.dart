import 'dart:async';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:next_ui/next_ui.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:skills_manager/features/settings/presentation/view_models/appearance_mode.dart';
import 'package:skills_manager/app/skills_manager_app.dart';
import 'package:skills_manager/app/app_router.dart';
import 'package:skills_manager/features/command_host/presentation/command_host_providers.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';
import 'package:skills_manager/features/skills/agent_root_ownership_providers.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/data/repositories/ownership_gated_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_grouping.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_source_input_mode.dart';
import 'package:skills_manager/features/skills/data/services/agent_root_ownership_repair_service.dart';
import 'package:skills_manager/features/skills/presentation/views/agent_root_ownership_review_dialog.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/presentation/view_models/skill_translation_view_model.dart';
import 'package:skills_manager/features/translation/presentation/view_models/translation_scope_preference.dart';
import 'package:skills_manager/features/whats_new/whats_new_catalog.dart';
import 'package:skills_manager/features/whats_new/whats_new_store.dart';
import 'package:skills_manager/features/translation/data/services/translation_credential_store.dart';
import 'package:skills_manager/features/translation/data/services/translation_settings_store.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/features/settings/data/app_settings_store.dart';
import 'package:skills_manager/features/settings/data/skills_manager_runtime.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';
import 'package:skills_manager/shared/analytics/matomo_app_analytics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/licenses/native_licenses.dart';
import 'package:skills_manager/shared/platform/app_tray.dart';
import 'package:skills_manager/shared/platform/app_launch_mode.dart';
import 'package:skills_manager/shared/platform/platform_providers.dart';
import 'package:skills_manager/shared/platform/window_lifecycle.dart';
import 'package:skills_manager/shared/theme/app_palette.dart';
import 'package:skills_manager/shared/theme/app_metrics.dart';
import 'package:skills_translation/skills_translation.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main(List<String> args) async {
  final launchMode = AppLaunchMode.fromArguments(args);
  final diagnostics = kDebugMode
      ? AppDiagnostics.debug(writer: debugPrintSynchronously)
      : AppDiagnostics.disabled();
  diagnostics.info('app.launch', context: {'mode': launchMode.name});
  diagnostics.info('app.bootstrap.started', context: {'platform': _platform});
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeLicenses();
  await MyTopProgressiveBlur.precache();
  final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  if (isDesktop) {
    await windowManager.ensureInitialized();
    // Keep the native window from becoming smaller than the layouts can
    // support. This applies to all desktop targets supported by
    // window_manager; the macOS title-bar setup below remains unchanged.
    await windowManager.setMinimumSize(AppSizes.minimumWindowSize);
  }
  if (Platform.isMacOS || Platform.isWindows) {
    // Closing the window puts SkillDeck away instead of ending it, so update
    // checks keep running.
    await BackgroundWindowLifecycle().attach();
  }
  // Configured here but deliberately not shown: the window stays hidden until
  // after `runApp`, once Flutter has a frame. See `_showMacOsWindow`.
  final appearanceModeStore = AppearanceModeStore();
  final initialAppearanceMode = await appearanceModeStore.read();
  Future<void>? macOsWindowConfigured;
  if (Platform.isMacOS) {
    final configured = Completer<void>();
    windowManager.waitUntilReadyToShow(
      WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        minimumSize: AppSizes.minimumWindowSize,
        backgroundColor: AppPalette.forBrightness(
          initialAppearanceMode.resolve(
            PlatformDispatcher.instance.platformBrightness,
          ),
        ).canvas,
      ),
      configured.complete,
    );
    macOsWindowConfigured = configured.future;
  }
  final bundleIdentifier = Platform.isMacOS
      ? (await PackageInfo.fromPlatform()).packageName
      : null;
  final supportDirectory = await getApplicationSupportDirectory();
  final repositoryRoot = p.join(
    supportDirectory.path,
    'agent_skills',
    'workspace',
  );
  final appDataRoot = Directory(p.join(supportDirectory.path, 'agent_skills'));
  final appSettingsStore = SharedPreferencesAppSettingsStore();
  final appSettings = await appSettingsStore.read() ?? const AppSettings();
  final translationScopePreferenceStore = TranslationScopePreferenceStore();
  final initialTranslationScope = await translationScopePreferenceStore.read();
  final skillListLayoutStore = SkillListLayoutStore();
  final initialSkillListLayout = await skillListLayoutStore.read();
  final skillListGroupingStore = SkillListGroupingStore();
  final initialSkillListGrouping = await skillListGroupingStore.read();
  final skillSourceInputModeStore = SkillSourceInputModeStore();
  final initialSkillSourceInputMode = await skillSourceInputModeStore.read();
  final whatsNewStore = WhatsNewStore();
  final lastSeenVersion = await whatsNewStore.readLastSeenVersion();
  final pendingWhatsNew = whatsNewFor(
    // A Workspace from before this preference existed is an upgrade, not a
    // fresh install, so it still hears what is new.
    lastSeen:
        lastSeenVersion ??
        (Directory(repositoryRoot).existsSync() ? '0.0.0' : null),
    current: appVersion,
  );
  // Recorded before anything shows, so each version's news appears once.
  await whatsNewStore.writeLastSeenVersion(appVersion);
  Future<void> Function() stopCommandHost = () async {};
  AsyncCallback? windowsQuitRequest;
  if (Platform.isWindows) {
    // macOS reaches a hidden window through the Dock; Windows has no Dock, so
    // the tray icon is the only way back in. Labels are resolved once here
    // because the tray outlives the widget tree — changing the language takes
    // effect on the next launch.
    windowsQuitRequest = await _attachWindowsTray(
      appSettings.localePreference,
      beforeQuit: () => stopCommandHost(),
    );
  }
  final analytics = await MatomoAppAnalytics.create(
    configuration: const MatomoAnalyticsConfiguration.fromEnvironment(),
    platform: _platform,
    enabled: true,
    diagnostics: diagnostics,
  );
  analytics.track(const AppAnalyticsEvent.appStarted());
  final failureReporter = AppFailureReporter(diagnostics);
  final userHomePath = _userHomePath();
  diagnostics.info('app.bootstrap.ready', context: {'platform': _platform});

  runApp(
    ProviderScope(
      overrides: [
        commandHostConfigurationProvider.overrideWithValue(
          CommandHostConfiguration(
            environment: Platform.environment,
            isWindows: Platform.isWindows,
            bundleIdentifier: bundleIdentifier,
          ),
        ),
        commandHostShutdownRegistrarProvider.overrideWithValue(
          (stop) => stopCommandHost = stop,
        ),
        windowsQuitRequestProvider.overrideWithValue(windowsQuitRequest),
        appDiagnosticsProvider.overrideWithValue(diagnostics),
        appFailureReporterProvider.overrideWithValue(failureReporter),
        appAnalyticsProvider.overrideWith((ref) {
          ref.onDispose(analytics.dispose);
          return analytics;
        }),
        appSettingsStoreProvider.overrideWithValue(appSettingsStore),
        translationScopePreferenceStoreProvider.overrideWithValue(
          translationScopePreferenceStore,
        ),
        initialTranslationScopeProvider.overrideWithValue(
          initialTranslationScope,
        ),
        skillSourceInputModeStoreProvider.overrideWithValue(
          skillSourceInputModeStore,
        ),
        initialSkillSourceInputModeProvider.overrideWithValue(
          initialSkillSourceInputMode,
        ),
        pendingWhatsNewProvider.overrideWithValue(pendingWhatsNew),
        appearanceModeStoreProvider.overrideWithValue(appearanceModeStore),
        initialAppearanceModeProvider.overrideWithValue(initialAppearanceMode),
        skillListLayoutStoreProvider.overrideWithValue(skillListLayoutStore),
        skillListGroupingStoreProvider.overrideWithValue(
          skillListGroupingStore,
        ),
        initialSkillListGroupingProvider.overrideWithValue(
          initialSkillListGrouping,
        ),
        initialSkillListLayoutProvider.overrideWithValue(
          initialSkillListLayout,
        ),
        skillsManagerRuntimeFactoryProvider.overrideWithValue(
          () => SkillsManagerRuntime(
            repositoryRoot: repositoryRoot,
            settings: appSettings,
            diagnostics: diagnostics,
            failureReporter: failureReporter,
          ),
        ),
        rawSkillsWorkspaceRepositoryProvider.overrideWith(
          (ref) => ref.watch(skillsManagerRuntimeProvider).workspace,
        ),
        skillsWorkspaceRepositoryProvider.overrideWith(
          (ref) => OwnershipGatedSkillsWorkspaceRepository(
            delegate: ref.watch(rawSkillsWorkspaceRepositoryProvider),
            coordinator: ref.watch(agentRootOwnershipCoordinatorProvider),
          ),
        ),
        agentRootOwnershipRepairServiceProvider.overrideWithValue(
          MacOsAgentRootOwnershipRepairService(userHomePath: userHomePath),
        ),
        agentRootOwnershipReviewPresenterProvider.overrideWithValue(
          CupertinoAgentRootOwnershipReviewPresenter(
            navigatorKey: rootNavigatorKey,
          ),
        ),
        skillBrowserRepositoryProvider.overrideWith(
          (ref) => WorkspaceSkillBrowserRepository(
            ref.watch(skillsWorkspaceRepositoryProvider),
          ),
        ),
        skillAcquisitionRepositoryProvider.overrideWith((ref) {
          final runtime = ref.watch(skillsManagerRuntimeProvider);
          return WorkspaceSkillAcquisitionRepository(
            workspace: ref.watch(skillsWorkspaceRepositoryProvider),
            resolver: SkillSourceLocatorResolver(),
            targetInspection: (scope, projectRootId) => ref.read(
              activationTargetsProvider((
                scope: scope,
                projectRootId: projectRootId,
              )).future,
            ),
            agentIconName: (id) =>
                runtime.settings.customAgents
                    .where((agent) => agent.id == id)
                    .map((agent) => agent.iconName)
                    .firstOrNull ??
                'bot',
          );
        }),
        appTranslationRepositoryProvider.overrideWith((ref) {
          String? currentHash(String slotKey) {
            final snapshot = ref.read(workspaceSnapshotProvider).value;
            if (snapshot == null) return null;
            for (final skill in snapshot.skills) {
              if (skill.slotKey == slotKey) {
                return skill.currentRevision.contentHash;
              }
            }
            return null;
          }

          return AppTranslationRepository(
            settingsStore: SharedPreferencesTranslationSettingsStore(),
            credentialStore: const SecureTranslationCredentialStore(),
            cache: FileTranslationCache(
              rootDirectory: Directory(
                p.join(appDataRoot.path, 'translations'),
              ),
            ),
            currentContentHash: currentHash,
            isCurrentContent: (slotKey, contentHash) {
              final snapshot = ref.read(workspaceSnapshotProvider).value;
              return snapshot == null || currentHash(slotKey) == contentHash;
            },
            onCacheDeleted: () =>
                ref.invalidate(cachedSkillDescriptionProvider),
          );
        }),
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
        desktopSupportedProvider.overrideWithValue(
          Platform.isMacOS || Platform.isWindows || Platform.isLinux,
        ),
      ],
      child: const SkillsManagerApp(captureUnhandledErrors: true),
    ),
  );

  if (macOsWindowConfigured != null) {
    await revealBootstrapWindow(
      launchMode,
      showWindow: () => _showMacOsWindow(macOsWindowConfigured!),
    );
  }
}

/// Reveals the main window only once there is something to look at.
///
/// `MainFlutterWindow` launches fully transparent, so the window that AppKit
/// puts on screen immediately is invisible while `main` reads settings and
/// opens stores. Previously that window was visible and empty for the whole
/// bootstrap, which read as a flash of black before the UI snapped in.
///
/// The timeout is a safety valve, not a delay: it only matters if the engine
/// never reports a rasterized frame, in which case an unpainted window still
/// beats an invisible one. `AppDelegate` carries the same backstop natively for
/// the case where Dart never reaches this at all.
Future<void> _showMacOsWindow(Future<void> configured) async {
  await configured;
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized.timeout(
    const Duration(seconds: 3),
    onTimeout: () {},
  );
  await windowManager.setOpacity(1);
  await windowManager.show();
  await windowManager.focus();
}

/// Installs the Windows tray icon that reaches a hidden window.
///
/// Quitting from the tray calls [exit] rather than closing the window:
/// `setPreventClose` makes `close()` a no-op, and the Windows runner no longer
/// turns `WM_DESTROY` into `WM_QUIT`, so destroying the window would leave a
/// headless process behind. This matches how SkillDeck already ends on Alt-F4
/// and Cmd-Q — there is no graceful-shutdown hook today, and the Workspace
/// writer lock is an OS file lock the kernel releases on process exit.
Future<AsyncCallback> _attachWindowsTray(
  AppLocalePreference preference, {
  required Future<void> Function() beforeQuit,
}) async {
  final l10n = appLocalizationsFor(_trayLocale(preference));
  late final AppTray tray;
  Future<void>? quitting;
  Future<void> quit() => quitting ??= Future<void>(() async {
    try {
      await beforeQuit();
      await tray.detach().timeout(const Duration(seconds: 2));
    } finally {
      // Removal of the notification icon is best-effort. Neither a failed
      // Shell call nor a hidden window may leave the installer waiting.
      exit(0);
    }
  });
  tray = AppTray(onQuit: quit);
  await tray.attach(
    tooltip: l10n.appTitle,
    showWindowLabel: l10n.trayShowWindow,
    quitLabel: l10n.trayQuit,
  );
  return quit;
}

/// Mirrors the locale resolution in `SkillsManagerApp`, which is not reachable
/// from here because the tray is installed before the widget tree exists.
Locale _trayLocale(AppLocalePreference preference) {
  switch (preference) {
    case AppLocalePreference.zh:
      return const Locale('zh');
    case AppLocalePreference.en:
      return const Locale('en');
    case AppLocalePreference.system:
      for (final locale in PlatformDispatcher.instance.locales) {
        if (locale.languageCode == 'zh') return const Locale('zh');
        if (locale.languageCode == 'en') return const Locale('en');
      }
      return const Locale('en');
  }
}

String get _platform {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return Platform.operatingSystem;
}

String _userHomePath() {
  final value = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];
  if (value == null || value.trim().isEmpty) {
    throw StateError('The current user Home directory is unavailable.');
  }
  return p.normalize(p.absolute(value));
}
