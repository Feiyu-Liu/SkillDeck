import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/command_host/data/command_line_distribution.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_distribution_providers.dart';
import 'package:skills_manager/features/skills/presentation/widgets/smart_source_controls.dart';
import 'package:skills_manager/l10n/l10n.dart';

void main() {
  testWidgets('with the command line and Skill ready, the card copies the '
      'prompt', (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(_host(toolReady: true, skillActive: true));
    final l10n = tester.element(find.byType(SmartSourceAgentPrompt)).l10n;

    await tester.tap(find.byKey(const Key('agent-install-prompt-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-install-setup')), findsNothing);
    expect(find.byKey(const Key('agent-install-prompt')), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy-agent-install-prompt')));
    await tester.pump();
    expect(copied, l10n.acquisitionAgentPrompt);
    expect(find.text(l10n.acquisitionAgentPromptCopied), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(l10n.acquisitionAgentPromptCopy), findsOneWidget);
  });

  testWidgets('until the Skill is active, the card lists the setup steps '
      'instead of the prompt', (tester) async {
    await tester.pumpWidget(_host(toolReady: true, skillActive: false));

    await tester.tap(find.byKey(const Key('agent-install-prompt-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-install-setup')), findsOneWidget);
    expect(find.byKey(const Key('agent-install-prompt')), findsNothing);
    expect(
      find.byKey(const Key('agent-install-prompt-settings')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('agent-install-setup-tool')),
        matching: find.byIcon(LucideIcons.circleCheck),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('agent-install-setup-skill')),
        matching: find.byIcon(LucideIcons.circle),
      ),
      findsOneWidget,
    );
  });
}

Widget _host({required bool toolReady, required bool skillActive}) =>
    ProviderScope(
      overrides: [
        commandLineToolProvider.overrideWith(
          (ref) async => CommandLineToolState(
            status: toolReady
                ? CommandLineToolStatus.ready
                : CommandLineToolStatus.notBundled,
            path: '/Users/me/.skilldeck/bin/skilldeck',
          ),
        ),
        skillDeckAgentSkillProvider.overrideWithValue(
          skillActive
              ? SkillDeckAgentSkillState(
                  installed: true,
                  activeAgentIds: const {'codex'},
                )
              : const SkillDeckAgentSkillState.notInstalled(),
        ),
      ],
      child: const CupertinoApp(
        locale: Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: SmartSourceAgentPrompt(),
          ),
        ),
      ),
    );
