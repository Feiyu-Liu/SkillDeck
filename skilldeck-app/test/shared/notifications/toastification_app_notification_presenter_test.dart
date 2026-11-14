import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/notifications/app_notification_providers.dart';
import 'package:skills_manager/shared/widgets/app_notification_host.dart';
import 'package:skills_manager/shared/widgets/app_notification_scope.dart';

void main() {
  testWidgets('default presenter shows and closes the shared custom toast', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: AppNotificationScope(
          child: CupertinoApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: AppNotificationHost(
              child: Builder(
                builder: (context) => CupertinoButton(
                  key: const Key('publish-notification'),
                  onPressed: () {
                    container
                        .read(appNotificationControllerProvider.notifier)
                        .success(AppNotificationMessage.repositoryRefreshed);
                  },
                  child: const Text('Publish'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('publish-notification')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.byKey(const Key('app-notification-toast')), findsOneWidget);
    expect(find.text('The repository was refreshed.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-notification-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byKey(const Key('app-notification-toast')), findsNothing);
  });

  testWidgets(
    'task toast stays resident, updates in place, and pauses terminal timeout',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppNotificationScope(
            child: CupertinoApp(
              locale: const Locale('en'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const AppNotificationHost(child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pump();

      final presenter = container.read(appNotificationPresenterProvider);
      presenter.present(
        const AppNotificationPresentation(
          kind: AppNotificationPresentationKind.taskStarted,
          taskId: 1,
          content: AppNotificationContent(
            severity: AppNotificationSeverity.info,
            message: 'Translation started.',
            taskRunning: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.byKey(const Key('app-notification-toast')), findsOneWidget);
      expect(
        find.byKey(const Key('app-notification-task-spinner')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('app-notification-close')), findsNothing);

      await tester.pump(const Duration(seconds: 9));
      expect(find.byKey(const Key('app-notification-toast')), findsOneWidget);

      presenter.present(
        const AppNotificationPresentation(
          kind: AppNotificationPresentationKind.taskUpdated,
          taskId: 1,
          content: AppNotificationContent(
            severity: AppNotificationSeverity.info,
            message: 'Translated 2 of 5 blocks.',
            progress: AppNotificationProgress(completed: 2, total: 5),
            taskRunning: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.byKey(const Key('app-notification-toast')), findsOneWidget);
      expect(find.text('Translated 2 of 5 blocks.'), findsOneWidget);
      expect(
        find.byKey(const Key('app-notification-task-progress')),
        findsOneWidget,
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('app-notification-toast'))),
      );
      await tester.pump();

      presenter.present(
        const AppNotificationPresentation(
          kind: AppNotificationPresentationKind.taskFinished,
          taskId: 1,
          content: AppNotificationContent(
            severity: AppNotificationSeverity.success,
            message: 'The document was translated successfully.',
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
      expect(find.byKey(const Key('app-notification-close')), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const Key('app-notification-toast')), findsOneWidget);

      await mouse.moveTo(const Offset(4, 500));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.byKey(const Key('app-notification-toast')), findsNothing);
    },
  );
}
