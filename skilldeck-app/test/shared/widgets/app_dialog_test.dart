import 'package:skills_manager/l10n/l10n.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';

void main() {
  testWidgets('stacks header, divided sections and footer', (tester) async {
    await tester.pumpWidget(
      _testApp(
        Builder(
          builder: (context) => AppDialogScaffold(
            width: AppDialogWidths.standard,
            header: AppDialogHeader(
              icon: LucideIcons.folderSearch,
              title: 'Found 2 Skills',
              subtitle: 'Take them over to update them here.',
              actions: [
                appDialogCloseButton(
                  context,
                  key: const Key('close'),
                  onPressed: () {},
                ),
              ],
            ),
            sections: const [
              AppDialogSection(
                key: Key('first'),
                title: 'Conflicts',
                subtitle: 'Pick one copy.',
                trailing: Text('View all'),
                child: Text('brainstorming'),
              ),
              AppDialogSection(key: Key('second'), child: Text('pdf')),
            ],
            footer: AppDialogFooter(
              leading: const Text('Step 1 of 3'),
              actions: [
                AppButton(label: 'Cancel', onPressed: () {}),
                AppButton(
                  label: 'Continue',
                  style: NeoButtonVariant.primary,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // The footer reports its real height a frame later and the inset follows.
    await tester.pump();

    expect(find.byType(AppDialogBadge), findsOneWidget);
    expect(find.text('Found 2 Skills'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
    expect(
      tester.widget<AppIconButton>(find.byKey(const Key('close'))).tooltip,
      'Close',
    );
    final first = tester.getRect(find.byKey(const Key('first')));
    final second = tester.getRect(find.byKey(const Key('second')));
    expect(second.top, closeTo(first.bottom, 0.01));
    expect(first.width, AppDialogWidths.standard);

    final footer = tester.getRect(find.byType(AppDialogFooter));
    final cont = tester.getRect(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byType(AppButton),
      ),
    );
    final leading = tester.getRect(find.text('Step 1 of 3'));
    expect(leading.left, closeTo(footer.left + 20, 0.01));
    expect(cont.right, closeTo(footer.right - 20, 0.01));
    expect(footer.top, greaterThanOrEqualTo(second.bottom - 0.01));
  });

  testWidgets('confirmation actions share the footer width', (tester) async {
    await tester.pumpWidget(
      _testApp(
        AppConfirmDialog(
          icon: LucideIcons.trash2,
          tone: AppDialogTone.danger,
          title: 'Delete code-review?',
          message: 'This cannot be undone.',
          actions: [
            AppButton(
              key: const Key('cancel'),
              label: 'Cancel',
              size: NeoButtonSize.large,
              fullWidth: true,
              onPressed: () {},
            ),
            AppButton(
              key: const Key('confirm'),
              label: 'Delete Skill',
              style: NeoButtonVariant.danger,
              size: NeoButtonSize.large,
              fullWidth: true,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    final cancel = tester.getSize(find.byKey(const Key('cancel')));
    final confirm = tester.getSize(find.byKey(const Key('confirm')));
    expect(cancel.width, closeTo(confirm.width, 0.01));
    expect(cancel.height, confirm.height);
    expect(find.byType(AppIconButton), findsNothing);
    expect(
      tester.getSize(find.byType(AppConfirmDialog)).width,
      greaterThanOrEqualTo(AppDialogWidths.confirm),
    );
  });

  testWidgets('maps each tone to its badge colors', (tester) async {
    const expected = {
      AppDialogTone.danger: (AppColors.dangerSoft, AppColors.danger),
      AppDialogTone.info: (AppColors.infoSoft, AppColors.infoStrong),
      AppDialogTone.warning: (AppColors.warningSoft, AppColors.warningStrong),
      AppDialogTone.success: (AppColors.successSoft, AppColors.success),
    };
    for (final MapEntry(key: tone, value: (soft, strong)) in expected.entries) {
      await tester.pumpWidget(
        _testApp(
          Center(
            child: AppDialogBadge(icon: LucideIcons.info, tone: tone),
          ),
        ),
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(AppDialogBadge),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as ShapeDecoration;
      expect(decoration.color, soft, reason: '$tone');
      expect(tester.widget<Icon>(find.byType(Icon)).color, strong);
      expect(tester.getSize(find.byType(AppDialogBadge)), const Size(44, 44));
    }
  });

  testWidgets('scrolls header and sections as one list above the footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _testApp(
        AppDialogScaffold(
          width: AppDialogWidths.standard,
          header: const AppDialogHeader(title: 'Manage Agents'),
          sections: [
            for (var index = 0; index < 20; index++)
              AppDialogSection(
                child: SizedBox(height: 60, child: Text('Agent $index')),
              ),
          ],
          footer: AppDialogFooter(
            actions: [
              AppButton(key: const Key('add'), label: 'Add', onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.text('Manage Agents').hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('add')).hitTestable(), findsOneWidget);

    // The content runs on beneath the footer, which blurs what passes behind.
    final viewport = tester.getRect(find.byType(Scrollable));
    final footer = tester.getRect(find.byType(AppDialogFooter));
    expect(viewport.bottom, closeTo(footer.bottom, 0.01));
    expect(
      find.descendant(
        of: find.byType(AppDialogFooter),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.text('Agent 19'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Agent 19').hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.text('Agent 19')).bottom,
      lessThanOrEqualTo(footer.top),
    );
    expect(find.text('Manage Agents').hitTestable(), findsNothing);
    expect(find.byKey(const Key('add')).hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('add'))).bottom,
      lessThanOrEqualTo(600),
    );
  });

  testWidgets('Esc runs onEscape only while the dialog route is on top', (
    tester,
  ) async {
    var escapes = 0;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppDialogScaffold(
          width: AppDialogWidths.confirm,
          onEscape: () => escapes += 1,
          header: const AppDialogHeader(title: 'Base'),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(escapes, 1);

    navigatorKey.currentState!.push(
      CupertinoPageRoute<void>(builder: (_) => const Text('Covering page')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(escapes, 1);
  });

  testWidgets('showAppConfirmDialog resolves Esc, cancel and confirm', (
    tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      _testApp(
        Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    Future<bool> open() => showAppConfirmDialog(
      context: hostContext,
      icon: LucideIcons.userMinus,
      title: 'Remove Agent?',
      confirmLabel: 'Remove',
      cancelKey: const Key('confirm-cancel'),
      confirmKey: const Key('confirm-ok'),
    );

    var result = open();
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Remove Agent?'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await result, isFalse);

    result = open();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(await result, isTrue);

    result = showAppConfirmDialog(
      context: hostContext,
      icon: LucideIcons.triangleAlert,
      tone: AppDialogTone.warning,
      title: 'Check the paths',
      confirmLabel: 'Done',
      showCancel: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('notes use the tone color without a fill', (tester) async {
    await tester.pumpWidget(
      _testApp(
        const Center(
          child: SizedBox(
            width: 300,
            child: AppDialogNote(
              tone: AppDialogTone.warning,
              text: 'The old history will be deleted.',
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.triangleAlert)).color,
      AppColors.warningStrong,
    );
    expect(
      find.descendant(
        of: find.byType(AppDialogNote),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
  });
}

Widget _testApp(Widget child) => CupertinoApp(
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);
