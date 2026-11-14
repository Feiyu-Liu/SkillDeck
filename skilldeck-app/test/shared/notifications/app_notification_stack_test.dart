import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:skills_manager/shared/notifications/toastification_app_notification_presenter.dart';
import 'package:skills_manager/shared/widgets/app_notification_scope.dart';
import 'package:skills_manager/shared/widgets/app_notification_toast.dart';

void main() {
  late ToastificationAppNotificationPresenter presenter;

  setUp(() => presenter = ToastificationAppNotificationPresenter());
  tearDown(() => presenter.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      const AppNotificationScope(
        child: CupertinoApp(
          home: CupertinoPageScaffold(child: SizedBox.expand()),
        ),
      ),
    );
  }

  void show(
    String message, {
    bool task = false,
    bool expires = false,
    bool details = false,
  }) {
    presenter.present(
      AppNotificationPresentation(
        kind: task
            ? AppNotificationPresentationKind.taskStarted
            : AppNotificationPresentationKind.transient,
        taskId: task ? 1 : null,
        content: AppNotificationContent(
          severity: expires
              ? AppNotificationSeverity.success
              : AppNotificationSeverity.error,
          message: message,
          taskRunning: task,
          detail: details ? 'Not a folder: /a\nBroken link: /b' : null,
          detailLabel: details ? 'Show details' : null,
        ),
      ),
    );
  }

  testWidgets(
    'three mixed notifications preserve the top inset with compact painted gaps',
    (tester) async {
      await pumpApp(tester);
      show('First');
      await _settleStack(tester);
      final firstTop = _surface(tester, 'First').top;
      expect(firstTop, 60);
      show('Task', task: true);
      await _settleStack(tester);
      show('Newest');
      await _settleStack(tester);
      final surfaces = _surfaces(tester);
      expect(surfaces, hasLength(3));
      expect(surfaces.first.top, firstTop);
      expect(_gaps(surfaces), [8, 8]);
      await _clearStack(tester, presenter);
    },
  );

  testWidgets(
    'expanded details and closing the middle notification reflow without overlaps or holes',
    (tester) async {
      await pumpApp(tester);
      show('First');
      await _settleStack(tester);
      show('Details', details: true);
      await _settleStack(tester);
      show('Task', task: true);
      await _settleStack(tester);
      final collapsedHeight = _surface(tester, 'Details').height;
      await tester.tap(find.byKey(const Key('app-notification-show-details')));
      await _settleStack(tester);
      expect(_surface(tester, 'Details').height, greaterThan(collapsedHeight));
      expect(_gaps(_surfaces(tester)), [8, 8]);
      expect(_surfaces(tester).first.top, 60);
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(AppNotificationToast, 'Details'),
          matching: find.byKey(const Key('app-notification-close')),
        ),
      );
      await _settleStack(tester);
      expect(find.text('Details'), findsNothing);
      expect(_surfaces(tester), hasLength(2));
      expect(_surfaces(tester).first.top, 60);
      expect(_gaps(_surfaces(tester)), [8]);
      await _clearStack(tester, presenter);
    },
  );

  testWidgets(
    'automatic removal compacts the stack and the three item limit remains in force',
    (tester) async {
      await pumpApp(tester);
      show('First');
      await _settleStack(tester);
      show('Expires', expires: true);
      await _settleStack(tester);
      show('Task', task: true);
      await _settleStack(tester);
      await tester.pump(const Duration(seconds: 3));
      await _settleStack(tester);
      expect(find.text('Expires'), findsNothing);
      expect(_surfaces(tester), hasLength(2));
      expect(_gaps(_surfaces(tester)), [8]);
      expect(_surfaces(tester).first.top, 60);
      show('Third');
      await _settleStack(tester);
      show('Fourth');
      await _settleStack(tester);
      expect(find.text('First'), findsNothing);
      expect(_surfaces(tester), hasLength(3));
      expect(_gaps(_surfaces(tester)), [8, 8]);
      await _clearStack(tester, presenter);
    },
  );
}

Future<void> _settleStack(WidgetTester tester) async {
  // Direct presenter calls enqueue insertion for the next application frame.
  tester.binding.scheduleFrame();
  // Running task spinners never settle; advance just the existing transitions.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Rect _surface(WidgetTester tester, String message) => tester.getRect(
  find
      .descendant(
        of: find.widgetWithText(AppNotificationToast, message),
        matching: find.byType(ClipRRect),
      )
      .first,
);

List<Rect> _surfaces(WidgetTester tester) {
  final surfaces = find.byType(AppNotificationToast).evaluate().map((element) {
    return tester.getRect(
      find
          .descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
  }).toList()..sort((left, right) => left.top.compareTo(right.top));
  return surfaces;
}

List<double> _gaps(List<Rect> surfaces) => [
  for (var i = 1; i < surfaces.length; i++)
    surfaces[i].top - surfaces[i - 1].bottom,
];

Future<void> _clearStack(
  WidgetTester tester,
  ToastificationAppNotificationPresenter presenter,
) async {
  presenter.dismissAll();
  await _settleStack(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}
