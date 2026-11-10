import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/widgets/app_notification_toast.dart';

void main() {
  testWidgets('renders every severity with stable semantics and close action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final expectedIcons = {
      AppNotificationSeverity.info: LucideIcons.info,
      AppNotificationSeverity.success: LucideIcons.circleCheck,
      AppNotificationSeverity.warning: LucideIcons.triangleAlert,
      AppNotificationSeverity.error: LucideIcons.circleAlert,
    };
    var closeCalls = 0;

    for (final entry in expectedIcons.entries) {
      await tester.pumpWidget(
        CupertinoApp(
          home: Center(
            child: AppNotificationToast(
              content: AppNotificationContent(
                severity: entry.key,
                message: 'A concise and safe message.',
              ),
              onClose: () => closeCalls += 1,
            ),
          ),
        ),
      );

      expect(find.byIcon(entry.value), findsOneWidget);
      final liveRegion = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      );
      expect(liveRegion.properties.label, 'A concise and safe message.');
      await tester.tap(find.byKey(const Key('app-notification-close')));
      expect(closeCalls, greaterThan(0));
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('constrains long localized text without layout overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      CupertinoApp(
        home: Align(
          alignment: Alignment.topRight,
          child: AppNotificationToast(
            content: AppNotificationContent(
              severity: AppNotificationSeverity.error,
              message: List.filled(
                30,
                'A safely localized explanation',
              ).join(' '),
            ),
            onClose: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('app-notification-toast')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders running task progress without a close action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(
          child: AppNotificationToast(
            content: AppNotificationContent(
              severity: AppNotificationSeverity.info,
              message: 'Translated 2 of 5 blocks.',
              progress: AppNotificationProgress(completed: 2, total: 5),
              taskRunning: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 220));

    expect(
      find.byKey(const Key('app-notification-task-spinner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('app-notification-task-progress')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('app-notification-close')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('truncates long Provider errors but copies the full text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fullText = 'provider_error: ${'original detail ' * 40}';
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: AppNotificationToast(
            content: AppNotificationContent(
              severity: AppNotificationSeverity.error,
              message: fullText,
              copyText: fullText,
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(fullText));
    expect(text.maxLines, 4);
    expect(text.overflow, TextOverflow.ellipsis);
    await tester.tap(find.byKey(const Key('app-notification-copy')));
    expect(copied, fullText);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the summary and expands to the details on request', (
    tester,
  ) async {
    var pauses = 0;
    var resumes = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: AppNotificationToast(
            content: const AppNotificationContent(
              severity: AppNotificationSeverity.error,
              message: '2 Agent Skills folders need fixing.',
              detail: 'Not a folder: /a\nBroken link: /b',
              detailLabel: 'Show details',
            ),
            onPause: () => pauses += 1,
            onResume: () => resumes += 1,
          ),
        ),
      ),
    );

    expect(find.text('2 Agent Skills folders need fixing.'), findsOneWidget);
    expect(find.byKey(const Key('app-notification-detail')), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('app-notification-show-details'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('app-notification-show-details')));
    await tester.pump();

    expect(find.text('Not a folder: /a'), findsOneWidget);
    expect(find.text('Broken link: /b'), findsOneWidget);
    expect(
      find.byKey(const Key('app-notification-show-details')),
      findsNothing,
    );
    // Expanded, it stays open after the pointer leaves.
    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(pauses, greaterThan(0));
    expect(resumes, 0);
  });
}
