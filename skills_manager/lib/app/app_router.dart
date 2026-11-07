import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skills_manager/app/app_providers.dart';
import 'package:skills_manager/shared/navigation/app_routes.dart';
import 'package:skills_manager/app/app_shell.dart';
import 'package:skills_manager/app/dialog_page.dart';
import 'package:skills_manager/features/skills/presentation/views/skill_acquisition_dialog.dart';
import 'package:skills_manager/features/skills/presentation/views/external_skills_dialog.dart';
import 'package:skills_manager/features/skills/presentation/views/skill_browser_screen.dart';
import 'package:skills_manager/features/skills/presentation/views/skill_workspace_panel.dart';
import 'package:skills_manager/features/skills/presentation/views/skill_drift_review_dialog.dart';
import 'package:skills_manager/features/skills/presentation/views/source_replacement_dialog.dart';
import 'package:skills_manager/features/skills/presentation/views/project_roots_dialog.dart';
import 'package:skills_manager/features/settings/presentation/views/settings_screen.dart';
import 'package:skills_manager/features/settings/presentation/settings_section.dart';
import 'package:skills_manager/features/updates/presentation/views/updates_panel.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _installedNavigatorKey = GlobalKey<NavigatorState>();
final _favoritesNavigatorKey = GlobalKey<NavigatorState>();
final _updatesNavigatorKey = GlobalKey<NavigatorState>();
final _settingsNavigatorKey = GlobalKey<NavigatorState>();

final skillsRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: ref.read(appInitialLocationProvider),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => AppRoutePaths.installed),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            SkillsManagerShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _installedNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutePaths.installed,
                name: AppRouteNames.installed,
                pageBuilder: (context, state) => NoTransitionPage<void>(
                  key: state.pageKey,
                  child: const SkillBrowserScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'add',
                    name: AppRouteNames.addSkill,
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => const DialogPage<void>(
                      barrierDismissible: false,
                      child: SkillAcquisitionDialog(),
                    ),
                  ),
                  GoRoute(
                    path: 'discover',
                    name: AppRouteNames.discoverExternalSkills,
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => const DialogPage<void>(
                      barrierDismissible: false,
                      child: ExternalSkillsDialog(),
                    ),
                  ),
                  GoRoute(
                    path: 'projects',
                    name: AppRouteNames.projectRoots,
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => const DialogPage<void>(
                      barrierDismissible: true,
                      child: ProjectRootsDialog(),
                    ),
                  ),
                  GoRoute(
                    path: ':skillId',
                    name: AppRouteNames.skillDetail,
                    pageBuilder: (context, state) => NoTransitionPage<void>(
                      key: state.pageKey,
                      child: SkillWorkspacePanel(
                        skillId: WorkspaceSkillId(
                          state.pathParameters['skillId']!,
                        ),
                        openSettings:
                            state.uri.queryParameters['tab'] == 'settings',
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'activate',
                        name: AppRouteNames.activateSkill,
                        redirect: (context, state) =>
                            '/installed/${Uri.encodeComponent(state.pathParameters['skillId']!)}?tab=settings',
                      ),
                      GoRoute(
                        path: 'external-changes',
                        name: AppRouteNames.reviewSkillDrift,
                        parentNavigatorKey: rootNavigatorKey,
                        pageBuilder: (context, state) => DialogPage<void>(
                          barrierDismissible: false,
                          child: SkillDriftReviewDialog(
                            skillId: WorkspaceSkillId(
                              state.pathParameters['skillId']!,
                            ),
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'remove',
                        name: AppRouteNames.removeSkill,
                        parentNavigatorKey: rootNavigatorKey,
                        pageBuilder: (context, state) => DialogPage<void>(
                          barrierDismissible: false,
                          child: RemoveSkillDialogRoute(
                            skillId: WorkspaceSkillId(
                              state.pathParameters['skillId']!,
                            ),
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'replace-source',
                        name: AppRouteNames.replaceSource,
                        parentNavigatorKey: rootNavigatorKey,
                        pageBuilder: (context, state) => DialogPage<void>(
                          barrierDismissible: false,
                          child: SourceReplacementDialogRoute(
                            skillId: WorkspaceSkillId(
                              state.pathParameters['skillId']!,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _favoritesNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutePaths.favorites,
                name: AppRouteNames.favorites,
                pageBuilder: (context, state) => NoTransitionPage<void>(
                  key: state.pageKey,
                  child: const SkillBrowserScreen(favoritesOnly: true),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _updatesNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutePaths.updates,
                name: AppRouteNames.updates,
                pageBuilder: (context, state) => NoTransitionPage<void>(
                  key: state.pageKey,
                  child: const UpdatesPanel(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _settingsNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutePaths.settings,
                name: AppRouteNames.settings,
                pageBuilder: (context, state) => NoTransitionPage<void>(
                  key: const ValueKey('settings-page'),
                  child: SettingsScreen(
                    selectedSection: parseSettingsSection(
                      state.uri.queryParameters['section'],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
