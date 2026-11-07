import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/generated/app_localizations_en.dart';
import 'package:skills_manager/l10n/generated/app_localizations_zh.dart';
import 'package:skills_manager/l10n/workspace_operation_l10n.dart';

void main() {
  test('localizes deferred cleanup without implying operation failure', () {
    final warning = WorkspaceWarning(
      code: WorkspaceWarningCode.recoveryCleanupDeferred,
      context: const {
        'operationId': 'operation-1',
        'reason': 'stagingCleanupFailed',
      },
    );

    expect(
      localizeWorkspaceWarning(AppLocalizationsEn(), warning),
      'Some temporary recovery files could not be cleaned up. '
      'Repository data is unchanged.',
    );
    expect(
      localizeWorkspaceWarning(AppLocalizationsZh(), warning),
      '部分临时恢复文件未能清理，仓库数据未受影响。',
    );
    expect(warning.context['operationId'], 'operation-1');
    expect(warning.context['reason'], 'stagingCleanupFailed');
  });

  test('explains that shared Agent folders were activated once', () {
    final warning = WorkspaceWarning(
      code: WorkspaceWarningCode.sharedActivationLocation,
      context: const {
        'location': '/home/.claude/skills',
        'locations': ['/home/.agents/skills', '/home/.claude/skills'],
        'agentIds': ['claude-code', 'cursor'],
      },
    );

    expect(
      localizeWorkspaceWarning(AppLocalizationsEn(), warning),
      'Several Agent Skills folders are one folder, so this Skill was '
      'activated there once for all of them.',
    );
    expect(
      localizeWorkspaceWarning(AppLocalizationsZh(), warning),
      '多个 Agent 的 Skills 文件夹实际是同一个文件夹，已为它们一并激活。',
    );
  });

  test('names the command line as the lock holder while it runs', () {
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();

    expect(
      localizeWorkspacePhase(en, WorkspaceOperationPhase.waitingForLock),
      'Waiting for the repository…',
    );
    expect(
      localizeWorkspacePhase(
        zh,
        WorkspaceOperationPhase.waitingForLock,
        commandLineBusy: true,
      ),
      '等待命令行完成…',
    );
    expect(
      localizeWorkspacePhase(
        en,
        WorkspaceOperationPhase.applying,
        commandLineBusy: true,
      ),
      en.operationApplying,
    );
  });
}
