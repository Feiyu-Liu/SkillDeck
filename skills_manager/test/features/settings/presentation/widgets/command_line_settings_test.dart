import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/command_host/data/command_line_distribution.dart';
import 'package:skills_manager/features/command_host/data/command_line_path_link_service.dart';
import 'package:skills_manager/features/command_host/presentation/command_host_providers.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_distribution_providers.dart';
import 'package:skills_manager/features/settings/presentation/widgets/command_line_settings.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

import '../../../command_host/support/read_fixtures.dart';

final class _RecordingService implements SkillDeckAgentSkillService {
  final installs = <Set<String>>[];

  @override
  Future<AppFailure?> install({required Set<String> agentIds}) async {
    installs.add(agentIds);
    return null;
  }
}

final class _FakePathLink implements CommandLinePathLink {
  _FakePathLink(this.current);

  CommandLinePathLinkStatus current;
  var installs = 0;

  @override
  String get linkPath => '/usr/local/bin/skilldeck';

  @override
  Future<CommandLinePathLinkStatus> status() async => current;

  @override
  Future<CommandLinePathLinkOutcome> install() async {
    installs++;
    current = CommandLinePathLinkStatus.installed;
    return CommandLinePathLinkOutcome.succeeded;
  }

  @override
  Future<CommandLinePathLinkOutcome> remove() async {
    current = CommandLinePathLinkStatus.notInstalled;
    return CommandLinePathLinkOutcome.succeeded;
  }
}

void main() {
  late _RecordingService service;
  setUp(() => service = _RecordingService());

  Future<void> pump(
    WidgetTester tester, {
    SkillDeckAgentSkillState skill =
        const SkillDeckAgentSkillState.notInstalled(),
    CommandLineToolStatus tool = CommandLineToolStatus.ready,
    CommandLinePathLink? pathLink,
    Set<String> members = const {'codex', 'claude'},
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commandHostProvider.overrideWith((ref) async => null),
          commandHostAppVersionProvider.overrideWith((ref) async => '1.2.3'),
          commandLineToolProvider.overrideWith(
            (ref) async => CommandLineToolState(
              status: tool,
              path: '/Users/me/.skilldeck/bin/skilldeck',
            ),
          ),
          commandLinePathLinkServiceProvider.overrideWithValue(pathLink),
          skillDeckAgentSkillProvider.overrideWithValue(skill),
          skillDeckAgentSkillServiceProvider.overrideWithValue(service),
          deviceAgentCatalogProvider.overrideWith(
            (ref) async => [
              testAgent(),
              testAgent(id: 'claude', name: 'Claude Code'),
              testAgent(id: 'cursor', name: 'Cursor'),
            ],
          ),
          deviceAgentMembersProvider.overrideWithValue(AsyncData(members)),
        ],
        child: const CupertinoApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CupertinoPageScaffold(
            child: SingleChildScrollView(
              child: CommandLineSettings(showSectionHeader: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('installs the Agent Skill for every Agent on this device', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Command-line service status'), findsOneWidget);
    expect(find.text('Not running'), findsOneWidget);
    expect(find.text('/Users/me/.skilldeck/bin/skilldeck'), findsOneWidget);

    await tester.tap(find.byKey(const Key('command-line-agent-skill-install')));
    await tester.pumpAndSettle();

    expect(service.installs, [
      {'codex', 'claude'},
    ], reason: 'Cursor is in the catalog but not set up on this device');
  });

  testWidgets('with no Agent set up, installing activates nothing', (
    tester,
  ) async {
    await pump(tester, members: const {});

    await tester.tap(find.byKey(const Key('command-line-agent-skill-install')));
    await tester.pumpAndSettle();

    expect(service.installs, [<String>{}]);
  });

  testWidgets('describes an installed Agent Skill and where it is active', (
    tester,
  ) async {
    await pump(
      tester,
      skill: SkillDeckAgentSkillState(
        installed: true,
        skillId: WorkspaceSkillId('skilldeck-id'),
        activeAgentIds: const {'codex', 'claude'},
      ),
    );

    expect(find.text('Active'), findsOneWidget);
    expect(
      find.byKey(const Key('command-line-agent-skill-open')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('command-line-agent-skill-install')),
      findsNothing,
    );
  });

  testWidgets('hides the path when this build ships no CLI', (tester) async {
    await pump(tester, tool: CommandLineToolStatus.notBundled);

    expect(find.byKey(const Key('command-line-tool-path')), findsNothing);
    expect(
      find.text(
        'This build of SkillDeck doesn’t include the command-line tool.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('installs the terminal command with one click', (tester) async {
    final link = _FakePathLink(CommandLinePathLinkStatus.notInstalled);
    await pump(tester, pathLink: link);

    expect(find.byKey(const Key('command-line-path-line')), findsNothing);
    await tester.tap(find.byKey(const Key('command-line-path-link-install')));
    await tester.pumpAndSettle();

    expect(link.installs, 1);
    expect(
      find.byKey(const Key('command-line-path-link-remove')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Installed at /usr/local/bin/skilldeck'),
      findsOneWidget,
    );
  });

  testWidgets('offers the manual PATH line when the link path is taken', (
    tester,
  ) async {
    await pump(
      tester,
      pathLink: _FakePathLink(CommandLinePathLinkStatus.conflict),
    );

    expect(find.byKey(const Key('command-line-path-line')), findsOneWidget);
    expect(
      find.byKey(const Key('command-line-path-link-install')),
      findsNothing,
    );
  });

  testWidgets('falls back to the manual PATH line without a link service', (
    tester,
  ) async {
    await pump(tester);

    if (Platform.isWindows) {
      final l10n = AppLocalizations.of(
        tester.element(find.byType(CommandLineSettings)),
      );
      expect(find.text(l10n.commandLinePathWindows), findsOneWidget);
      expect(find.byKey(const Key('command-line-path-line')), findsNothing);
    } else {
      expect(find.byKey(const Key('command-line-path-line')), findsOneWidget);
    }
    expect(find.byKey(const Key('command-line-path-link')), findsNothing);
  });
}
