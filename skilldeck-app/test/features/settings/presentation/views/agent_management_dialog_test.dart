import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/features/settings/presentation/views/agent_management_dialog.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/memory_app_settings_store.dart';

void main() {
  testWidgets('removes a detected built-in Agent and adds it again', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemoryAppSettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsStoreProvider.overrideWithValue(store),
          skillsWorkspaceRepositoryProvider.overrideWithValue(
            FakeSkillsWorkspaceRepository(),
          ),
          deviceAgentCatalogProvider.overrideWithValue(
            AsyncData([
              WorkspaceAgentInfo(
                id: 'codex',
                displayName: 'Codex',
                isBuiltIn: true,
                supportedScopes: const {
                  WorkspaceScope.global,
                  WorkspaceScope.project,
                },
                detectedGlobally: true,
                detectedProjectRootIds: const {},
              ),
              WorkspaceAgentInfo(
                id: 'cursor',
                displayName: 'Cursor',
                isBuiltIn: true,
                supportedScopes: const {WorkspaceScope.global},
                detectedGlobally: false,
                detectedProjectRootIds: const {},
              ),
            ]),
          ),
        ],
        child: CupertinoApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: SkillsTheme.theme,
          home: CupertinoPageScaffold(
            child: NeoButtonTheme(
              data: SkillsButtonTheme.neo,
              child: MorphingMenuButtonTheme(
                data: SkillsButtonTheme.morphingMenu,
                child: const AgentManagementDialog(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('managed-agent-codex')), findsOneWidget);
    expect(find.byKey(const Key('managed-agent-cursor')), findsNothing);
    final removeButton = tester.widget<NeoIconButton>(
      find.descendant(
        of: find.byKey(const Key('exclude-agent-codex')),
        matching: find.byType(NeoIconButton),
      ),
    );
    expect(removeButton.icon, LucideIcons.trash2);
    expect(removeButton.tint, AppColors.danger);

    await tester.tap(find.byKey(const Key('exclude-agent-codex')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('managed-agent-codex')), findsNothing);
    expect(store.value!.builtInAgentVisibilityOverrides, {'codex': false});

    await tester.tap(find.byKey(const Key('agent-management-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-add-built-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('include-agent-codex')), findsOneWidget);
    expect(find.byKey(const Key('include-agent-cursor')), findsOneWidget);
    final backRect = tester.getRect(
      find.byKey(const Key('agent-catalog-back')),
    );
    final titleRect = tester.getRect(
      find.byKey(const Key('agent-management-title')),
    );
    final closeRect = tester.getRect(
      find.byKey(const Key('agent-management-close')),
    );
    final addRect = tester.getRect(
      find.byKey(const Key('include-agent-codex')),
    );
    final footerRect = tester.getRect(find.byType(AppDialogFooter));
    // Back sits at the start of the footer, below the title; each Add button
    // lines up with the content edge, 16 inside the header's close button,
    // which sits out toward the corner.
    expect(backRect.top, greaterThan(titleRect.bottom));
    expect(backRect.left, closeTo(footerRect.left + 20, 0.01));
    expect(closeRect.right - addRect.right, closeTo(16, 0.01));

    await tester.tap(find.byKey(const Key('include-agent-codex')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('managed-agent-codex')), findsOneWidget);
    expect(store.value!.builtInAgentVisibilityOverrides, {'codex': true});
    expect(tester.takeException(), isNull);
  });
}
