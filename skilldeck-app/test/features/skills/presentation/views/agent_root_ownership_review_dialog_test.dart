import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/views/agent_root_ownership_review_dialog.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('requires explicit confirmation for a custom Agent root', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final presenter = CupertinoAgentRootOwnershipReviewPresenter(
      navigatorKey: navigatorKey,
    );
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox.shrink(),
      ),
    );

    final result = presenter.review(_customAudit());
    await tester.pumpAndSettle();

    expect(find.text('Repair Agent folder ownership?'), findsOneWidget);
    final confirm = tester.widget<AppButton>(
      find.byKey(const Key('ownership-repair-confirm')),
    );
    expect(confirm.onPressed, isNull);

    await tester.ensureVisible(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pump();
    final enabledConfirm = tester.widget<AppButton>(
      find.byKey(const Key('ownership-repair-confirm')),
    );
    expect(enabledConfirm.onPressed, isNotNull);
    enabledConfirm.onPressed!();
    await tester.pumpAndSettle();

    expect(await result, {'/Users/tester/.custom/skills'});
  });
}

WorkspaceAgentRootOwnershipAudit _customAudit() =>
    WorkspaceAgentRootOwnershipAudit(
      supported: true,
      currentUserId: 501,
      examinedRootCount: 1,
      issues: [
        WorkspaceAgentRootOwnershipIssue(
          rootPath: '/Users/tester/.custom/skills',
          agentIds: const {'custom'},
          customAgentIds: const {'custom'},
          roles: const {WorkspaceAgentSkillRootRole.canonicalActivation},
          reason: WorkspaceAgentRootOwnershipIssueReason.ownerMismatch,
          repairable: true,
        ),
      ],
    );
