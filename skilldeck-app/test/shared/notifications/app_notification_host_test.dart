import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/notifications/app_notification_providers.dart';
import 'package:skills_manager/shared/widgets/app_notification_host.dart';

void main() {
  testWidgets(
    'presents each event exactly once through an injected presenter',
    (tester) async {
      final presenter = _RecordingPresenter();
      final container = ProviderContainer(
        overrides: [
          appNotificationPresenterProvider.overrideWithValue(presenter),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_testApp(container));

      container
          .read(appNotificationControllerProvider.notifier)
          .success(AppNotificationMessage.repositoryRefreshed);
      await tester.pump();

      expect(presenter.presentations, hasLength(1));
      expect(
        presenter.presentations.single.content.severity,
        AppNotificationSeverity.success,
      );
      expect(
        presenter.presentations.single.content.message,
        'The repository was refreshed.',
      );
      expect(
        presenter.presentations.single.kind,
        AppNotificationPresentationKind.transient,
      );

      await tester.pump();
      expect(presenter.presentations, hasLength(1));
    },
  );

  testWidgets(
    'isolates presenter failures from the widget and error pipeline',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          appNotificationPresenterProvider.overrideWithValue(
            _ThrowingPresenter(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_testApp(container));

      container
          .read(appNotificationControllerProvider.notifier)
          .success(AppNotificationMessage.repositoryRefreshed);
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('localizes task progress and preserves one task identity', (
    tester,
  ) async {
    final presenter = _RecordingPresenter();
    final container = ProviderContainer(
      overrides: [
        appNotificationPresenterProvider.overrideWithValue(presenter),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_testApp(container));

    final task = container
        .read(appNotificationControllerProvider.notifier)
        .startTask(
          const AppNotification.message(
            severity: AppNotificationSeverity.info,
            message: AppNotificationMessage.translationStarted,
          ),
        );
    await tester.pump();
    task.update(
      const AppNotification.message(
        severity: AppNotificationSeverity.info,
        message: AppNotificationMessage.translationProgress,
        progress: AppNotificationProgress(completed: 2, total: 4),
      ),
    );
    await tester.pump();
    task.finish(
      const AppNotification.message(
        severity: AppNotificationSeverity.success,
        message: AppNotificationMessage.translationCompleted,
      ),
    );
    await tester.pump();

    expect(presenter.presentations.map((presentation) => presentation.kind), [
      AppNotificationPresentationKind.taskStarted,
      AppNotificationPresentationKind.taskUpdated,
      AppNotificationPresentationKind.taskFinished,
    ]);
    expect(
      presenter.presentations
          .map((presentation) => presentation.taskId)
          .toSet(),
      hasLength(1),
    );
    expect(presenter.presentations.first.taskId, isNotNull);
    expect(
      presenter.presentations[1].content.message,
      'Translated 2 of 4 blocks.',
    );
    expect(presenter.presentations[1].content.progress?.fraction, 0.5);
    expect(presenter.presentations[2].content.taskRunning, isFalse);
  });
}

Widget _testApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const CupertinoApp(
      locale: Locale('en'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppNotificationHost(child: SizedBox.expand()),
    ),
  );
}

final class _RecordingPresenter implements AppNotificationPresenter {
  final presentations = <AppNotificationPresentation>[];

  @override
  void present(AppNotificationPresentation presentation) {
    presentations.add(presentation);
  }

  @override
  void dismissAll() {}

  @override
  void dispose() {}
}

final class _ThrowingPresenter implements AppNotificationPresenter {
  @override
  void present(AppNotificationPresentation presentation) {
    throw StateError('presenter failed');
  }

  @override
  void dismissAll() {}

  @override
  void dispose() {}
}
