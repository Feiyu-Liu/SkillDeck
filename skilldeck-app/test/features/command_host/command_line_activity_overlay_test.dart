import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/command_host/presentation/widgets/command_line_activity_overlay.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/l10n/generated/app_localizations_en.dart';
import 'package:skills_manager/shared/navigation/app_routes.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        commandLineSummaryLifetimeProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pumpOverlay(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Stack(
            children: [Positioned.fill(child: CommandLineActivityOverlay())],
          ),
        ),
        GoRoute(
          path: '/installed/:skillId',
          name: AppRouteNames.skillDetail,
          builder: (context, state) =>
              Text('detail ${state.pathParameters['skillId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const items = [
    CommandLineActivityItem(skillId: 'id-alpha', slotKey: 'alpha'),
    CommandLineActivityItem(skillId: 'id-beta', slotKey: 'beta'),
  ];

  test('every activity kind has both verbs', () {
    final l10n = AppLocalizationsEn();
    for (final kind in CommandLineActivityKind.values) {
      expect(commandLineProgressiveVerb(l10n, kind), isNotEmpty);
      expect(commandLinePastVerb(l10n, kind), isNotEmpty);
    }
    expect(
      commandLineProgressiveVerb(l10n, CommandLineActivityKind.replaceSource),
      'Replacing the source of',
    );
    expect(
      commandLinePastVerb(l10n, CommandLineActivityKind.replaceSource),
      'Replaced the source of',
    );
  });

  testWidgets('shows nothing while the command line is idle', (tester) async {
    await pumpOverlay(tester);

    expect(find.byKey(const Key('command-line-running')), findsNothing);
    expect(find.byKey(const Key('command-line-summary-title')), findsNothing);
  });

  testWidgets('shows a running request with progress and cancels it', (
    tester,
  ) async {
    var cancelled = 0;
    await pumpOverlay(tester);
    final session = container
        .read(commandLineActivityProvider.notifier)
        .begin(
          kind: CommandLineActivityKind.activate,
          agentNames: const ['Codex'],
          items: items,
          onCancel: () => cancelled++,
        );
    session.start('id-alpha');
    session.finish('id-alpha', CommandLineItemStatus.succeeded);
    session.start('id-beta');
    await tester.pumpAndSettle();

    expect(find.text('Command line: Activating 2 Skills'), findsOneWidget);
    expect(find.text('For Codex · 1/2 · Processing beta'), findsOneWidget);

    await tester.tap(find.byKey(const Key('command-line-cancel')));
    // The Neo button spins while cancelling, so the frame never settles.
    await tester.pump(const Duration(milliseconds: 300));

    expect(cancelled, 1);
    expect(find.text('Cancelling…'), findsOneWidget);
  });

  testWidgets('summarises a partial batch and opens the failed Skill', (
    tester,
  ) async {
    await pumpOverlay(tester);
    final session = container
        .read(commandLineActivityProvider.notifier)
        .begin(kind: CommandLineActivityKind.activate, items: items);
    session.finish('id-alpha', CommandLineItemStatus.succeeded);
    session.finish(
      'id-beta',
      CommandLineItemStatus.failed,
      errorCode: 'activationTargetOccupied',
    );
    session.end();
    await tester.pumpAndSettle();

    expect(find.text('Activated 1 Skill, 1 failed'), findsOneWidget);
    expect(find.text('Command line'), findsOneWidget);
    // The failure lists its own name and reason, apart from the successes.
    expect(
      find.descendant(
        of: find.byKey(const Key('command-line-summary-failures')),
        matching: find.text('beta'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('An unmanaged folder with the same name'),
      findsOneWidget,
    );
    expect(find.text('1 completed'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('command-line-summary-chips')),
        matching: find.text('alpha'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('command-line-open-skill')));
    await tester.pumpAndSettle();

    expect(find.text('detail id-beta'), findsOneWidget);
  });

  testWidgets('dismisses a finished summary', (tester) async {
    await pumpOverlay(tester);
    container
        .read(commandLineActivityProvider.notifier)
        .begin(kind: CommandLineActivityKind.favorite, items: items)
        .end();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('command-line-summary-title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('command-line-dismiss')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('command-line-summary-title')), findsNothing);
  });

  testWidgets('an all-success summary shows names as tags in two lines', (
    tester,
  ) async {
    await pumpOverlay(tester);
    final many = [
      for (var i = 0; i < 22; i++)
        CommandLineActivityItem(
          skillId: 'id-$i',
          slotKey: 'skill-number-$i-with-a-long-name',
        ),
    ];
    final session = container
        .read(commandLineActivityProvider.notifier)
        .begin(kind: CommandLineActivityKind.replaceSource, items: many);
    for (final item in many) {
      session.finish(item.skillId, CommandLineItemStatus.succeeded);
    }
    session.end();
    await tester.pumpAndSettle();

    expect(find.text('Replaced the source of 22 Skills'), findsOneWidget);
    expect(find.text('Command line · All succeeded'), findsOneWidget);
    expect(find.textContaining('completed'), findsNothing);

    final chips = find.byKey(const Key('command-line-summary-chips'));
    final more = find.byKey(const Key('command-line-summary-more'));
    expect(more, findsOneWidget);
    final shown = find
        .descendant(of: chips, matching: find.textContaining('skill-number-'))
        .evaluate()
        .length;
    expect(shown, inInclusiveRange(1, 21));
    expect(find.text('+${22 - shown}'), findsOneWidget);
    final tops = {
      for (final element
          in find.descendant(of: chips, matching: find.byType(Text)).evaluate())
        tester.getTopLeft(find.byWidget(element.widget)).dy.round(),
    };
    expect(tops.length, lessThanOrEqualTo(2), reason: 'at most two lines');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('command-line-dismiss')));
    await tester.pumpAndSettle();
  });

  testWidgets('a short all-success summary shows every name and no +N', (
    tester,
  ) async {
    await pumpOverlay(tester);
    final session = container
        .read(commandLineActivityProvider.notifier)
        .begin(kind: CommandLineActivityKind.activate, items: items);
    session.finish('id-alpha', CommandLineItemStatus.succeeded);
    session.finish('id-beta', CommandLineItemStatus.succeeded);
    session.end();
    await tester.pumpAndSettle();

    expect(find.text('Activated 2 Skills'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.byKey(const Key('command-line-summary-more')), findsNothing);
    await tester.tap(find.byKey(const Key('command-line-dismiss')));
    await tester.pumpAndSettle();
  });
}
