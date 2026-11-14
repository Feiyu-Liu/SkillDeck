import 'package:skills_manager/l10n/l10n.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/app/app_router.dart';
import 'package:skills_manager/features/command_host/data/command_approval.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_approval.dart';
import 'package:skills_manager/features/command_host/presentation/widgets/command_line_approval_sheet.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';

import '../../support/fake_skills_workspace_repository.dart';
import 'support/read_fixtures.dart';

CommandApprovalRequest _removal({String id = 'ap_1', bool stale = false}) {
  final request = CommandApprovalRequest(
    id: id,
    subject: CommandApprovalRemoveSkills(const ['skill-1', 'skill-2']),
    expiresAt: DateTime.utc(2026, 10, 20, 12, 10),
  );
  return stale ? request.asStale() : request;
}

void main() {
  group('source label', () {
    String label(WorkspaceSourceKind kind, String locator) =>
        commandLineSourceLabel(SkillSourceInput(kind: kind, locator: locator))
            .$2;

    test('shortens GitHub to owner/repo and other hosts to host/path', () {
      const git = WorkspaceSourceKind.git;
      expect(
        label(git, 'https://github.com/wshobson/agents.git'),
        'wshobson/agents',
      );
      expect(label(git, 'https://user:pw@github.com/org/repo/'), 'org/repo');
      expect(label(git, 'git@github.com:org/repo.git'), 'org/repo');
      expect(
        label(git, 'https://gitlab.com/team/skills.git'),
        'gitlab.com/team/skills',
      );
    });

    test('names a local Source by its folder', () {
      expect(label(WorkspaceSourceKind.local, '/Users/me/skills/beta'), 'beta');
      expect(
        commandLineSourceLabel(
          const SkillSourceInput(
            kind: WorkspaceSourceKind.local,
            locator: '/Users/me/skills/beta',
          ),
        ).$1,
        LucideIcons.folder,
      );
    });
  });

  group('controller', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    CommandLineApprovalController controller() =>
        container.read(commandLineApprovalProvider.notifier);

    test('hands the reviewed revision back on approval', () async {
      final decision = controller().present(_removal());
      expect(container.read(commandLineApprovalProvider)?.id, 'ap_1');

      controller().approve(reviewedRevision: 7);

      expect(
        await decision,
        isA<CommandApprovalApproved>().having(
          (d) => d.reviewedRevision,
          'reviewedRevision',
          7,
        ),
      );
      expect(container.read(commandLineApprovalProvider), isNull);
    });

    test('deny and withdraw close the request', () async {
      final denied = controller().present(_removal());
      controller().deny();
      expect(await denied, isA<CommandApprovalDenied>());

      final withdrawn = controller().present(_removal(id: 'ap_2'));
      controller().withdraw('someone-else');
      expect(container.read(commandLineApprovalProvider), isNotNull);
      controller().withdraw('ap_2');
      expect(await withdrawn, isA<CommandApprovalWithdrawn>());
      expect(container.read(commandLineApprovalProvider), isNull);
    });

    test('a fresh review of the same request never closes the sheet', () async {
      final states = <CommandApprovalRequest?>[];
      container.listen(
        commandLineApprovalProvider,
        (_, next) => states.add(next),
      );
      final first = controller().present(_removal());
      final second = controller().present(_removal(stale: true));

      expect(await first, isA<CommandApprovalWithdrawn>());
      expect(states, everyElement(isNotNull));
      expect(states.last?.staleReview, isTrue);
      controller().deny();
      expect(await second, isA<CommandApprovalDenied>());
    });
  });

  group('sheet', () {
    late ProviderContainer container;
    late int attention;

    setUp(() {
      attention = 0;
      container = ProviderContainer(
        overrides: [
          skillsWorkspaceRepositoryProvider.overrideWithValue(
            FakeSkillsWorkspaceRepository(snapshot: testSnapshot()),
          ),
          deviceAgentCatalogProvider.overrideWith(
            (ref) async => [
              testAgent(),
              testAgent(id: 'claude', name: 'Claude Code'),
            ],
          ),
          commandLineApprovalAttentionProvider.overrideWithValue(
            () async => attention++,
          ),
        ],
      );
    });
    tearDown(() => container.dispose());

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp(
            navigatorKey: rootNavigatorKey,
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                listenForCommandLineApprovals(ref);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await container.read(workspaceSnapshotProvider.future);
      await container.read(deviceAgentCatalogProvider.future);
      await tester.pumpAndSettle();
    }

    CommandLineApprovalController controller() =>
        container.read(commandLineApprovalProvider.notifier);

    testWidgets('shows what removal does and approves at that revision', (
      tester,
    ) async {
      await pumpHost(tester);
      final decision = controller().present(_removal());
      await tester.pumpAndSettle();

      expect(attention, 1);
      expect(
        find.text('The command line wants to delete 2 Skills'),
        findsOneWidget,
      );
      expect(
        find.text('Removes activations in Codex, Claude Code'),
        findsOneWidget,
      );
      expect(find.text('Not active in any Agent'), findsOneWidget);

      await tester.tap(find.byKey(const Key('command-line-approval-confirm')));
      await tester.pumpAndSettle();

      expect(
        await decision,
        isA<CommandApprovalApproved>().having(
          (d) => d.reviewedRevision,
          'reviewedRevision',
          7,
        ),
      );
      expect(find.byKey(const Key('command-line-approval')), findsNothing);
    });

    testWidgets('slides up as the App modal and ignores the scrim', (
      tester,
    ) async {
      await pumpHost(tester);
      controller().present(_removal());
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is CupertinoPopupSurface),
        findsOneWidget,
      );
      expect(
        ModalRoute.of(
          tester.element(find.byKey(const Key('command-line-approval'))),
        ),
        isA<CupertinoModalPopupRoute<void>>(),
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('command-line-approval')),
        findsOneWidget,
        reason: 'only Deny or Confirm decides an approval',
      );
      controller().deny();
      await tester.pumpAndSettle();
    });

    testWidgets('denying or withdrawing closes the sheet', (tester) async {
      await pumpHost(tester);
      final denied = controller().present(_removal());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('command-line-approval-deny')));
      await tester.pumpAndSettle();
      expect(await denied, isA<CommandApprovalDenied>());
      expect(find.byKey(const Key('command-line-approval')), findsNothing);

      controller().present(_removal(id: 'ap_2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('command-line-approval')), findsOneWidget);
      controller().withdraw('ap_2');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('command-line-approval')), findsNothing);
    });

    testWidgets('a stale review updates the open sheet in place', (
      tester,
    ) async {
      await pumpHost(tester);
      controller().present(_removal());
      await tester.pumpAndSettle();
      controller().present(_removal(stale: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('command-line-approval')), findsOneWidget);
      expect(
        find.byKey(const Key('command-line-approval-stale')),
        findsOneWidget,
      );
      expect(attention, 1, reason: 'one request, one attention request');
      controller().deny();
      await tester.pumpAndSettle();
    });

    testWidgets('describes a Source Replacement per Skill', (tester) async {
      await pumpHost(tester);
      final decision = controller().present(
        CommandApprovalRequest(
          id: 'ap_src',
          subject: CommandApprovalReplaceSource([
            const CommandApprovalReplaceSourceItem(
              skillId: 'skill-1',
              source: SkillSourceInput(
                kind: WorkspaceSourceKind.git,
                locator: 'https://token@github.com/new-org/skills',
                skillPath: 'alpha',
              ),
              candidateDeclaredName: 'alpha',
            ),
            const CommandApprovalReplaceSourceItem(
              skillId: 'skill-2',
              source: SkillSourceInput(
                kind: WorkspaceSourceKind.git,
                locator: 'https://github.com/new-org/skills',
                skillPath: 'beta',
              ),
              candidateDeclaredName: 'beta',
            ),
            const CommandApprovalReplaceSourceItem(
              skillId: 'skill-gone',
              source: SkillSourceInput(
                kind: WorkspaceSourceKind.git,
                locator: 'https://github.com/new-org/skills',
              ),
              candidateDeclaredName: 'gamma',
            ),
          ]),
          expiresAt: DateTime.utc(2026, 10, 20, 12, 10),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The command line wants to replace the source of 3 Skills'),
        findsOneWidget,
      );
      expect(
        find.text('new-org/skills'),
        findsNWidgets(2),
        reason: 'each row names its new GitHub repository, without userinfo',
      );
      expect(find.textContaining('token'), findsNothing);
      expect(
        find.textContaining('example.test'),
        findsNothing,
        reason: 'the old Source is not shown',
      );
      expect(find.textContaining('/sources/local'), findsNothing);
      expect(find.textContaining('activations in'), findsNothing);
      expect(find.text('gamma'), findsOneWidget);
      expect(find.text('No longer installed'), findsOneWidget);
      expect(
        find.text(
          'The old source’s version history and local changes will be deleted '
          'for good.',
        ),
        findsOneWidget,
      );
      expect(find.text('Replace sources'), findsOneWidget);

      await tester.tap(find.byKey(const Key('command-line-approval-confirm')));
      await tester.pumpAndSettle();
      expect(
        await decision,
        isA<CommandApprovalApproved>().having(
          (d) => d.reviewedRevision,
          'reviewedRevision',
          7,
        ),
      );
    });

    CommandApprovalReplaceSourceItem relinkItem(String skillId, String repo) =>
        CommandApprovalReplaceSourceItem(
          skillId: skillId,
          source: SkillSourceInput(
            kind: WorkspaceSourceKind.git,
            locator: 'https://github.com/$repo.git',
            skillPath: 'skills/$skillId',
          ),
          candidateDeclaredName: skillId,
        );

    testWidgets('lists every Skill with its own new source, ungrouped', (
      tester,
    ) async {
      await pumpHost(tester);
      controller().present(
        CommandApprovalRequest(
          id: 'ap_relink',
          subject: CommandApprovalReplaceSource([
            relinkItem('skill-1', 'org-a/skills'),
            relinkItem('skill-2', 'org-b/skills'),
          ]),
          expiresAt: DateTime.utc(2026, 10, 20, 12, 10),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('org-a/skills'), findsOneWidget);
      expect(find.text('org-b/skills'), findsOneWidget);
      controller().deny();
      await tester.pumpAndSettle();
    });

    testWidgets('a long batch scrolls and keeps the buttons reachable', (
      tester,
    ) async {
      // The default 800×600 test window leaves the sheet 480 points.
      await pumpHost(tester);
      final decision = controller().present(
        CommandApprovalRequest(
          id: 'ap_long',
          subject: CommandApprovalReplaceSource([
            for (var i = 0; i < 24; i++)
              relinkItem('gone-$i', 'org-${i % 6}/skills'),
          ]),
          expiresAt: DateTime.utc(2026, 10, 20, 12, 10),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no overflow');
      final sheet = find.descendant(
        of: find.byKey(const Key('command-line-approval')),
        matching: find.byType(CupertinoPopupSurface),
      );
      expect(tester.getSize(sheet).height, lessThanOrEqualTo(480));
      expect(find.text('gone-23').hitTestable(), findsNothing);
      await tester.scrollUntilVisible(
        find.text('gone-23'),
        200,
        scrollable: find
            .ancestor(
              of: find.byKey(const Key('command-line-approval-targets')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('gone-23').hitTestable(), findsOneWidget);

      await tester.tap(find.byKey(const Key('command-line-approval-confirm')));
      await tester.pumpAndSettle();
      expect(await decision, isA<CommandApprovalApproved>());
    });

    testWidgets('describes a tag deletion', (tester) async {
      await pumpHost(tester);
      controller().present(
        CommandApprovalRequest(
          id: 'ap_tag',
          subject: const CommandApprovalDeleteTag(tagId: 'tag-1'),
          expiresAt: DateTime.utc(2026, 10, 20, 12, 10),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The command line wants to delete the tag “Testing”'),
        findsOneWidget,
      );
      expect(find.textContaining('removed from 1 Skill.'), findsOneWidget);
      controller().deny();
      await tester.pumpAndSettle();
    });
  });
}
