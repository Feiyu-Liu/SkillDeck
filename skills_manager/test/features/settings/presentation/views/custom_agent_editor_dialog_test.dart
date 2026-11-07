import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/presentation/views/custom_agent_editor_dialog.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';

import '../../../../support/fake_directory_picker.dart';

void main() {
  testWidgets('configures only the current device and hides advanced paths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final picker = FakeDirectoryPicker('/Users/me/.agents/skills');
    CustomAgentSettings? saved;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [directoryPickerProvider.overrideWithValue(picker)],
        child: CupertinoApp(
          locale: const Locale('en'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => CupertinoButton(
              child: const Text('Open'),
              onPressed: () async {
                saved = await AppDialogMotion.show<CustomAgentSettings>(
                  context: context,
                  builder: (context) => const CustomAgentEditorDialog(
                    platform: AppDesktopPlatform.macos,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Global Skills directory'), findsOneWidget);
    expect(find.text('Project Skills relative directory'), findsOneWidget);
    expect(find.byKey(const Key('custom-agent-windows-global')), findsNothing);
    expect(find.byKey(const Key('custom-agent-linux-global')), findsNothing);
    expect(find.byKey(const Key('custom-agent-advanced-fields')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('custom-agent-name')),
      'Reviewer',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('custom-agent-choose-global-directory')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('custom-agent-choose-global-directory')),
    );
    await tester.pumpAndSettle();
    expect(picker.calls, 1);

    await tester.ensureVisible(
      find.byKey(const Key('custom-agent-advanced-toggle')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('custom-agent-advanced-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('custom-agent-macos-global-discovery')),
      '/Users/me/.reviewer/skills\n'
      '/Users/me/.reviewer/skills\n'
      '/Users/me/.legacy/skills',
    );
    await tester.ensureVisible(find.byKey(const Key('custom-agent-save')));
    await tester.pumpAndSettle();
    tester
        .widget<AppButton>(find.byKey(const Key('custom-agent-save')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(saved!.platforms.keys, <AppDesktopPlatform>[
      AppDesktopPlatform.macos,
    ]);
    final platform = saved!.platforms[AppDesktopPlatform.macos]!;
    expect(platform.globalSkillsPath, '/Users/me/.agents/skills');
    expect(platform.globalDiscoverySkillsPaths, <String>[
      '/Users/me/.reviewer/skills',
      '/Users/me/.legacy/skills',
    ]);
  });

  testWidgets('preserves configurations saved for other platforms', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const windows = CustomAgentPlatformSettings(
      globalSkillsPath: r'C:\Users\me\.reviewer\skills',
    );
    const agent = CustomAgentSettings(
      id: 'custom-reviewer',
      displayName: 'Reviewer',
      iconName: 'bot',
      platforms: {
        AppDesktopPlatform.macos: CustomAgentPlatformSettings(
          globalSkillsPath: '/Users/me/.reviewer/skills',
        ),
        AppDesktopPlatform.windows: windows,
      },
    );
    CustomAgentSettings? saved;
    await tester.pumpWidget(
      ProviderScope(
        child: CupertinoApp(
          locale: const Locale('en'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => CupertinoButton(
              child: const Text('Open'),
              onPressed: () async {
                saved = await AppDialogMotion.show<CustomAgentSettings>(
                  context: context,
                  builder: (context) => const CustomAgentEditorDialog(
                    agent: agent,
                    platform: AppDesktopPlatform.macos,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('custom-agent-macos-global')),
      '/Users/me/.reviewer-v2/skills',
    );
    tester
        .widget<AppButton>(find.byKey(const Key('custom-agent-save')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(saved!.platforms[AppDesktopPlatform.windows], same(windows));
    expect(
      saved!.platforms[AppDesktopPlatform.macos]!.globalSkillsPath,
      '/Users/me/.reviewer-v2/skills',
    );
  });
}
