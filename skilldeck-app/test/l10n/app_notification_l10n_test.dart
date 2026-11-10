import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/app_notification_l10n.dart';
import 'package:skills_manager/l10n/generated/app_localizations_en.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';

void main() {
  test('a failure listing several folders toasts its summary, with the '
      'folders behind Show details', () {
    final notification = AppNotification.failure(
      WorkspaceFailure(
        code: WorkspaceErrorCode.agentRootOwnership,
        operation: WorkspaceOperationKind.activate,
        context: const {
          'reason': 'agentRootOwnershipBlocked',
          'issues': [
            {'issueReason': 'notDirectory', 'rootPath': '/Users/me/.a/skills'},
            {'issueReason': 'outsideUserHome', 'rootPath': '/opt/agent/skills'},
          ],
        },
      ),
    );

    final content = localizeAppNotification(AppLocalizationsEn(), notification);

    expect(
      content.message,
      '2 Agent Skills folders need fixing before SkillDeck can continue.',
    );
    expect(content.detail!.split('\n'), [
      contains('/Users/me/.a/skills'),
      contains('/opt/agent/skills'),
    ]);
    expect(content.detailLabel, 'Show details');
  });

  test('a one-line failure has no details', () {
    final notification = AppNotification.failure(
      WorkspaceFailure(
        code: WorkspaceErrorCode.agentRootOwnership,
        operation: WorkspaceOperationKind.activate,
        context: const {
          'reason': 'agentRootOwnershipBlocked',
          'issueReason': 'notDirectory',
          'rootPath': '/Users/me/.a/skills',
          'issues': [
            {'issueReason': 'notDirectory', 'rootPath': '/Users/me/.a/skills'},
          ],
        },
      ),
    );

    final content = localizeAppNotification(AppLocalizationsEn(), notification);

    expect(content.message, contains('/Users/me/.a/skills'));
    expect(content.detail, isNull);
    expect(content.detailLabel, isNull);
  });
}
