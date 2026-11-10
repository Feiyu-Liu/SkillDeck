import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/app/app_router.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_unhandled_error_boundary.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/navigation/app_routes.dart';
import 'package:skills_manager/shared/platform/mac_app_menu.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_notification_host.dart';
import 'package:skills_manager/shared/widgets/app_notification_scope.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/presentation/view_models/appearance_mode.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/command_host/presentation/command_host_providers.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/features/translation/translation_cache_maintenance.dart';

class SkillsManagerApp extends ConsumerStatefulWidget {
  const SkillsManagerApp({
    this.locale,
    this.captureUnhandledErrors = false,
    super.key,
  });

  /// Test and embedding override. Production uses the persisted preference.
  final Locale? locale;
  final bool captureUnhandledErrors;

  @override
  ConsumerState<SkillsManagerApp> createState() => _SkillsManagerAppState();
}

class _SkillsManagerAppState extends ConsumerState<SkillsManagerApp>
    with WidgetsBindingObserver {
  AppUnhandledErrorBoundary? _errorBoundary;
  final MacAppMenu _appMenu = MacAppMenu();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Settings is a route rather than a native window, so the macOS App menu
    // item reaches it the same way the sidebar does. The router is read at
    // call time so the menu never pins a router instance of its own.
    _appMenu.attach(
      onOpenSettings: () {
        if (!mounted) return;
        ref.read(skillsRouterProvider).goNamed(AppRouteNames.settings);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(appUpdateCoordinatorProvider)?.initialize());
      // The Skill update sweep is scheduled after the first frame and is never
      // awaited, so it cannot delay rendering, navigation, the installed list,
      // or Skill content. It is a no-op while the 24h TTL is unexpired.
      unawaited(_scheduleSkillUpdateSweep());
      unawaited(_startTranslationCacheMaintenance());
    });
    if (widget.captureUnhandledErrors) {
      _errorBoundary = AppUnhandledErrorBoundary(
        diagnostics: ref.read(appDiagnosticsProvider),
        onFailure: (failure) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref
                .read(appNotificationControllerProvider.notifier)
                .publish(AppNotification.failure(failure));
          });
        },
      )..install();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appMenu.detach();
    _errorBoundary?.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  /// Waits for the first ready Workspace Snapshot, then sweeps at most once.
  ///
  /// Failures stay silent: the coordinator records them as state only. Raising
  /// them through the notification path would show a failure toast on every
  /// offline launch.
  Future<void> _scheduleSkillUpdateSweep() async {
    try {
      await ref.read(workspaceSnapshotProvider.future);
    } on Object {
      return;
    }
    if (!mounted) return;
    await ref.read(skillUpdateStatusProvider.notifier).startupSweep();
  }

  Future<void> _startTranslationCacheMaintenance() async {
    try {
      await ref.read(workspaceSnapshotProvider.future);
    } on Object {
      return;
    }
    if (mounted) ref.read(translationCacheMaintenanceProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appUpdateCoordinatorProvider);
    ref.watch(workspaceSnapshotProvider);
    ref.watch(commandHostProvider);
    final finalization = ref.watch(workspaceFinalizationCoordinatorProvider);
    final settings = ref.watch(appSettingsViewModelProvider);
    final resolvedLocale =
        widget.locale ??
        switch (settings.settings.localePreference) {
          AppLocalePreference.system => null,
          AppLocalePreference.zh => const Locale('zh'),
          AppLocalePreference.en => const Locale('en'),
        };
    final brightness = ref
        .watch(appearanceModeProvider)
        .resolve(View.of(context).platformDispatcher.platformBrightness);
    return AppNotificationScope(
      child: CupertinoApp.router(
        debugShowCheckedModeBanner: false,
        locale: resolvedLocale,
        localeListResolutionCallback: (locales, supported) {
          for (final locale in locales ?? const <Locale>[]) {
            if (locale.languageCode == 'zh') return const Locale('zh');
            if (locale.languageCode == 'en') return const Locale('en');
          }
          return const Locale('en');
        },
        onGenerateTitle: (context) => context.l10n.appTitle,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SkillsTheme.forBrightness(brightness),
        routerConfig: ref.watch(skillsRouterProvider),
        // A fixed appearance stands in for the platform's: the palette and the
        // next_ui widgets all resolve from the platform brightness below.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
          child: NeoButtonTheme(
            data: SkillsButtonTheme.neo,
            child: Builder(
              builder: (context) => MorphingMenuButtonTheme(
                data: SkillsButtonTheme.morphingMenuFor(context),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppNotificationHost(
                      child: child ?? const SizedBox.shrink(),
                    ),
                    if (finalization.canRetry)
                      _WorkspaceFinalizationRetryBanner(
                        recovering: finalization.isRecovering,
                        onRetry: () => ref
                            .read(
                              workspaceFinalizationCoordinatorProvider.notifier,
                            )
                            .retryFailed(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _WorkspaceFinalizationRetryBanner extends StatelessWidget {
  const _WorkspaceFinalizationRetryBanner({
    required this.recovering,
    required this.onRetry,
  });

  final bool recovering;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Positioned(
    right: 16,
    bottom: 16,
    child: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Container(
        key: const Key('workspace-finalization-retry'),
        width: 420,
        padding: const EdgeInsets.all(16),
        decoration: AppCorners.smooth(
          color: AppPalette.of(context).surface,
          radius: AppRadii.lg,
          side: BorderSide(color: AppPalette.of(context).border),
          shadows: AppShadows.of(context).floatingControl,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                LucideIcons.triangleAlert,
                size: 18,
                color: AppPalette.of(context).warning,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.workspaceFinalizationRetryTitle,
                    style: AppTypography.of(context).control,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.workspaceFinalizationRetryMessage,
                    style: AppTypography.of(context).caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            AppButton(
              label: context.l10n.workspaceFinalizationRetryAction,
              key: const Key('workspace-finalization-retry-button'),
              icon: LucideIcons.rotateCcw,
              size: NeoButtonSize.small,
              style: NeoButtonVariant.secondary,
              onPressed: recovering ? null : onRetry,
            ),
          ],
        ),
      ),
    ),
  );
}
