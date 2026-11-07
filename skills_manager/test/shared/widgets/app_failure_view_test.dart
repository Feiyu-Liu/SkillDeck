import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';

void main() {
  testWidgets('maps recovery policies to one shared action', (tester) async {
    var calls = 0;
    final cases = <WorkspaceErrorCode, String>{
      WorkspaceErrorCode.sourceUnavailable: 'Retry',
      WorkspaceErrorCode.skillNotFound: 'Refresh',
      WorkspaceErrorCode.externalConflict: 'Refresh and review',
      WorkspaceErrorCode.controlPlaneCorrupt: '',
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(
        _testApp(
          AppFailureView(
            failure: _failure(entry.key),
            variant: AppFailureViewVariant.centered,
            actionKey: const Key('failure-action'),
            onAction: () => calls += 1,
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);
      if (entry.value.isEmpty) {
        expect(find.byKey(const Key('failure-action')), findsNothing);
      } else {
        expect(find.text(entry.value), findsOneWidget);
        await tester.tap(find.byKey(const Key('failure-action')));
        expect(calls, greaterThan(0));
      }
    }
  });

  testWidgets('banner supports dismissal and disables actions while busy', (
    tester,
  ) async {
    var actionCalls = 0;
    var dismissCalls = 0;
    await tester.pumpWidget(
      _testApp(
        AppFailureView(
          key: const Key('failure-banner'),
          failure: _failure(WorkspaceErrorCode.sourceUnavailable),
          variant: AppFailureViewVariant.banner,
          actionKey: const Key('failure-action'),
          onAction: () => actionCalls += 1,
          onDismiss: () => dismissCalls += 1,
          busy: true,
        ),
      ),
    );

    expect(find.byKey(const Key('failure-banner')), findsOneWidget);
    expect(find.byKey(const Key('failure-action')), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('failure-action')))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<AppIconButton>(find.byType(AppIconButton)).onPressed,
      isNull,
    );
    expect(actionCalls, 0);
    expect(dismissCalls, 0);
  });

  testWidgets('does not expose diagnostic text', (tester) async {
    await tester.pumpWidget(
      _testApp(
        AppFailureView(
          failure: WorkspaceFailure(
            code: WorkspaceErrorCode.sourceUnavailable,
            operation: WorkspaceOperationKind.install,
            diagnostic: 'private path and secret token',
          ),
          variant: AppFailureViewVariant.centered,
          onAction: () {},
        ),
      ),
    );

    expect(find.textContaining('private path'), findsNothing);
    expect(find.textContaining('secret token'), findsNothing);
  });
}

Widget _testApp(Widget child) => CupertinoApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

WorkspaceFailure _failure(WorkspaceErrorCode code) =>
    WorkspaceFailure(code: code, operation: WorkspaceOperationKind.install);
