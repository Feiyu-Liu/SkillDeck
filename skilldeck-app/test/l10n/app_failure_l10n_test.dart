import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/app_failure_l10n.dart';
import 'package:skills_manager/l10n/generated/app_localizations_en.dart';
import 'package:skills_manager/l10n/generated/app_localizations_zh.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

void main() {
  test(
    'drift stale errors localize with refresh-then-review in both locales',
    () {
      for (final code in [
        WorkspaceErrorCode.staleDriftReview,
        WorkspaceErrorCode.staleSnapshot,
      ]) {
        final failure = WorkspaceFailure(
          code: code,
          operation: WorkspaceOperationKind.resolveSkillDrift,
        );
        expect(failure.recoveryPolicy, AppRecoveryPolicy.refreshThenReview);
        expect(
          localizeAppFailure(AppLocalizationsEn(), failure),
          AppLocalizationsEn().errorStaleSnapshot,
        );
        expect(
          localizeAppFailure(AppLocalizationsZh(), failure),
          AppLocalizationsZh().errorStaleSnapshot,
        );
      }
    },
  );

  test(
    'unavailable drift resolution localizes without claiming Store corruption',
    () {
      final failure = WorkspaceFailure(
        code: WorkspaceErrorCode.driftResolutionUnavailable,
        operation: WorkspaceOperationKind.inspectSkillDrift,
        context: const {'reason': 'unsafeInspection'},
      );
      expect(failure.message, AppFailureMessage.driftResolutionUnavailable);
      expect(
        localizeAppFailure(AppLocalizationsEn(), failure),
        AppLocalizationsEn().errorDriftResolutionUnavailable,
      );
      expect(
        localizeAppFailure(AppLocalizationsZh(), failure),
        AppLocalizationsZh().errorDriftResolutionUnavailable,
      );
    },
  );

  test('an unavailable explicit link points to the activation setting', () {
    final linkUnavailable = WorkspaceFailure(
      code: WorkspaceErrorCode.activationUnsupported,
      operation: WorkspaceOperationKind.activate,
      context: const {'reason': 'symbolicLinkUnavailable'},
    );
    final otherwise = WorkspaceFailure(
      code: WorkspaceErrorCode.activationUnsupported,
      operation: WorkspaceOperationKind.activate,
    );
    for (final l10n in [AppLocalizationsEn(), AppLocalizationsZh()]) {
      expect(
        localizeAppFailure(l10n, linkUnavailable),
        l10n.errorSymbolicLinkUnavailable,
      );
      expect(localizeAppFailure(l10n, otherwise), l10n.errorActivation);
    }
  });

  test('an occupied adoption target asks the user to move it away', () {
    final failure = WorkspaceFailure(
      code: WorkspaceErrorCode.activationUnavailable,
      operation: WorkspaceOperationKind.adopt,
      context: const {'reason': 'adoptionTargetOccupied'},
    );
    for (final l10n in [AppLocalizationsEn(), AppLocalizationsZh()]) {
      expect(
        localizeAppFailure(l10n, failure),
        l10n.errorAdoptionTargetOccupied,
      );
    }
  });

  test('an occupied adoption target names what is in the way and where', () {
    const path = '/home/.agents/skills/alpha';
    WorkspaceFailure occupied(String occupant) => WorkspaceFailure(
      code: WorkspaceErrorCode.activationUnavailable,
      operation: WorkspaceOperationKind.adopt,
      context: {
        'reason': 'adoptionTargetOccupied',
        'occupant': occupant,
        'occupants': [
          {'targetPath': path, 'occupant': occupant},
        ],
      },
    );
    for (final l10n in [AppLocalizationsEn(), AppLocalizationsZh()]) {
      expect(localizeAppFailure(l10n, occupied('file')), contains(path));
      expect({
        for (final occupant in [
          'file',
          'invalidSkill',
          'directoryWithContent',
          'otherSkill',
          'sameSlotSkill',
          'link',
        ])
          localizeAppFailure(l10n, occupied(occupant)),
      }, hasLength(6));
      expect(
        localizeAppFailure(l10n, occupied('file')),
        l10n.errorAdoptionTargetOccupiedFile(path),
      );
      for (final generic in ['unknown', 'emptyDirectory', 'somethingNew']) {
        expect(
          localizeAppFailure(l10n, occupied(generic)),
          l10n.errorAdoptionTargetOccupied,
        );
      }
    }
  });

  test('distinguishes source duplicates from installed slot conflicts', () {
    final sourceDuplicate = WorkspaceFailure(
      code: WorkspaceErrorCode.duplicateSkillSlot,
      operation: WorkspaceOperationKind.inspectSource,
      context: const {'reason': 'duplicateSlotsWithinSource'},
    );
    final occupied = WorkspaceFailure(
      code: WorkspaceErrorCode.duplicateSkillSlot,
      operation: WorkspaceOperationKind.install,
    );
    expect(
      localizeAppFailure(AppLocalizationsZh(), sourceDuplicate),
      '该来源包含多个同名 Skill，请指定具体子路径。',
    );
    expect(
      localizeAppFailure(AppLocalizationsEn(), sourceDuplicate),
      'This source contains multiple skills with the same name. Specify a particular subpath.',
    );
    expect(
      localizeAppFailure(AppLocalizationsZh(), occupied),
      AppLocalizationsZh().errorDuplicateSkill,
    );
    expect(
      localizeAppFailure(AppLocalizationsEn(), occupied),
      AppLocalizationsEn().errorDuplicateSkill,
    );
  });

  test('localizes shared recovery actions in both locales', () {
    expect(
      localizeAppFailureRecoveryAction(
        AppLocalizationsEn(),
        AppRecoveryPolicy.retryExplicitly,
      ),
      'Retry',
    );
    expect(
      localizeAppFailureRecoveryAction(
        AppLocalizationsEn(),
        AppRecoveryPolicy.refresh,
      ),
      'Refresh',
    );
    expect(
      localizeAppFailureRecoveryAction(
        AppLocalizationsZh(),
        AppRecoveryPolicy.refreshThenReview,
      ),
      '刷新并重新检查',
    );
    expect(
      localizeAppFailureRecoveryAction(
        AppLocalizationsZh(),
        AppRecoveryPolicy.none,
      ),
      isNull,
    );
  });

  test('localizes a blocked root outside Home with its path', () {
    final failure = WorkspaceFailure(
      code: WorkspaceErrorCode.agentRootOwnership,
      operation: WorkspaceOperationKind.activate,
      context: const <String, Object?>{
        'reason': 'agentRootOwnershipBlocked',
        'issueReason': 'outsideUserHome',
        'rootPath': '/opt/agent/skills',
        'issueCount': 1,
        'issues': [
          {'issueReason': 'outsideUserHome', 'rootPath': '/opt/agent/skills'},
        ],
      },
    );

    expect(
      localizeAppFailure(AppLocalizationsEn(), failure),
      'An Agent Skills folder resolves outside your home directory and '
      'cannot be repaired automatically: /opt/agent/skills',
    );
  });

  test('lists every blocked folder on its own line', () {
    final failure = WorkspaceFailure(
      code: WorkspaceErrorCode.agentRootOwnership,
      operation: WorkspaceOperationKind.adopt,
      context: const <String, Object?>{
        'reason': 'agentRootOwnershipBlocked',
        'issueReason': 'inspectionFailed',
        'rootPath': '/Users/tester/.legacy/skills',
        'issueCount': 2,
        'issues': [
          {
            'issueReason': 'inspectionFailed',
            'rootPath': '/Users/tester/.legacy/skills',
          },
          {
            'issueReason': 'notDirectory',
            'rootPath': '/Users/tester/.agent/skills',
          },
        ],
      },
    );

    expect(localizeAppFailure(AppLocalizationsZh(), failure).split('\n'), [
      '有 2 个 Agent Skills 文件夹需要先修正，SkillDeck 才能继续。',
      'SkillDeck 无法检查这个 Agent Skills 文件夹，它可能是失效或循环的链接：'
          '/Users/tester/.legacy/skills',
      '配置的 Agent Skills 路径不是文件夹：/Users/tester/.agent/skills',
    ]);
    expect(
      localizeAppFailure(AppLocalizationsEn(), failure),
      isNot(contains('ownership')),
    );
  });

  test('localizes an unsuccessful post-repair inspection', () {
    final failure = WorkspaceFailure(
      code: WorkspaceErrorCode.agentRootOwnership,
      operation: WorkspaceOperationKind.adopt,
      context: const <String, Object?>{
        'reason': 'agentRootOwnershipStillInvalid',
        'issueReason': 'ownerMismatch',
        'rootPath': '/Users/tester/.agent/skills',
        'issueCount': 1,
      },
    );

    final message = localizeAppFailure(AppLocalizationsZh(), failure);

    expect(message, contains('/Users/tester/.agent/skills'));
    expect(message, contains('修复后仍有部分条目属于其他用户'));
  });

  test('distinguishes Git availability and repository size failures', () {
    final tooLarge = WorkspaceFailure(
      code: WorkspaceErrorCode.gitFailed,
      operation: WorkspaceOperationKind.inspectSource,
      context: const <String, Object?>{'reason': 'fileCountExceeded'},
    );
    final treeOutputTooLarge = WorkspaceFailure(
      code: WorkspaceErrorCode.gitFailed,
      operation: WorkspaceOperationKind.inspectSource,
      context: const <String, Object?>{'reason': 'treeOutputExceededLimit'},
    );
    final failed = WorkspaceFailure(
      code: WorkspaceErrorCode.gitFailed,
      operation: WorkspaceOperationKind.inspectSource,
    );
    final unavailable = WorkspaceFailure(
      code: WorkspaceErrorCode.gitUnavailable,
      operation: WorkspaceOperationKind.inspectSource,
    );

    expect(
      localizeAppFailure(AppLocalizationsZh(), tooLarge),
      '仓库内容超出扫描限制，请指定仓库子路径后重试。',
    );
    expect(
      localizeAppFailure(AppLocalizationsZh(), treeOutputTooLarge),
      '仓库内容超出扫描限制，请指定仓库子路径后重试。',
    );
    expect(
      localizeAppFailure(AppLocalizationsEn(), failed),
      'The Git operation failed. Check the source address and try again.',
    );
    expect(
      localizeAppFailure(AppLocalizationsEn(), unavailable),
      'Git is unavailable on this device. Public HTTPS repositories install '
      'without Git; SSH and private repositories need it.',
    );
  });

  test('localizes detailed workspace failure causes', () {
    const expected = <WorkspaceErrorCode, String>{
      WorkspaceErrorCode.digestMismatch: '来源内容未通过完整性校验，请检查来源后重试。',
      WorkspaceErrorCode.skillContentLimitExceeded: 'Skill 内容超出支持的文件数量或大小限制。',
      WorkspaceErrorCode.invalidSource: '该来源不受支持。',
      WorkspaceErrorCode.sourceReplacementRequired:
          '已存在同一 Skill Slot，请通过“更换来源”继续。',
      WorkspaceErrorCode.invalidProjectRoot: '所选项目目录无效。',
      WorkspaceErrorCode.projectRootConflict: '项目目录与现有注册项冲突。',
      WorkspaceErrorCode.duplicateAgentId: 'Agent 标识已存在。',
      WorkspaceErrorCode.personalTagNotFound: '该个人标签已不存在。',
      WorkspaceErrorCode.duplicatePersonalTag: '已存在同名个人标签。',
      WorkspaceErrorCode.unsupportedStateVersion:
          '此工作区版本不受当前应用支持，请更新 SkillDeck 后重试。',
      WorkspaceErrorCode.unsupportedJournalVersion:
          '此工作区版本不受当前应用支持，请更新 SkillDeck 后重试。',
      WorkspaceErrorCode.journalMaintenanceFailed: '工作区维护失败，恢复完成前已阻止修改。',
    };

    for (final entry in expected.entries) {
      final failure = WorkspaceFailure(
        code: entry.key,
        operation: WorkspaceOperationKind.inspectSource,
      );

      expect(
        localizeAppFailure(AppLocalizationsZh(), failure),
        entry.value,
        reason: entry.key.name,
      );
    }
  });

  group('first-run Source failures name what to fix', () {
    String en(AppFailure failure) =>
        localizeAppFailure(AppLocalizationsEn(), failure);
    String zh(AppFailure failure) =>
        localizeAppFailure(AppLocalizationsZh(), failure);
    WorkspaceFailure inspect(
      WorkspaceErrorCode code, [
      Map<String, Object?> context = const {},
    ]) => WorkspaceFailure(
      code: code,
      operation: WorkspaceOperationKind.inspectSource,
      context: context,
    );

    test('a Source with no Skills is not called a missing Skill', () {
      final failure = inspect(WorkspaceErrorCode.skillNotFound, {
        'reason': 'noValidSkills',
      });
      expect(en(failure), AppLocalizationsEn().errorNoSkillsInSource);
      expect(zh(failure), AppLocalizationsZh().errorNoSkillsInSource);
      expect(
        en(inspect(WorkspaceErrorCode.skillNotFound)),
        AppLocalizationsEn().errorSkillNotFound,
      );
    });

    test('an unavailable Source says which part is missing', () {
      expect(
        en(
          inspect(WorkspaceErrorCode.sourceUnavailable, {
            'reason': 'sourceRootNotDirectory',
          }),
        ),
        AppLocalizationsEn().errorLocalFolderNotFound,
      );
      expect(
        zh(
          inspect(WorkspaceErrorCode.sourceUnavailable, {
            'reason': 'searchRootUnavailable',
          }),
        ),
        AppLocalizationsZh().errorRepositorySubpathNotFound,
      );
      expect(
        en(inspect(WorkspaceErrorCode.httpFailure)),
        AppLocalizationsEn().errorSourceUnavailable,
      );
    });

    test('Git failures separate network, missing refs, and the rest', () {
      for (final reason in ['network', 'tls', 'certificate', 'proxy']) {
        expect(
          en(inspect(WorkspaceErrorCode.gitFailed, {'reason': reason})),
          AppLocalizationsEn().errorGitNetwork,
          reason: reason,
        );
      }
      expect(
        en(inspect(WorkspaceErrorCode.gitFailed, {'timedOut': true})),
        AppLocalizationsEn().errorGitNetwork,
      );
      expect(
        zh(inspect(WorkspaceErrorCode.gitFailed, {'reason': 'refNotFound'})),
        AppLocalizationsZh().errorGitRefNotFound,
      );
      expect(
        en(inspect(WorkspaceErrorCode.gitFailed, {'exitCode': 128})),
        AppLocalizationsEn().errorGitFailed,
      );
      expect(
        en(
          inspect(WorkspaceErrorCode.gitFailed, {
            'reason': 'fileCountExceeded',
          }),
        ),
        AppLocalizationsEn().errorGitFileCountExceeded,
      );
    });

    test('content limits report which limit and its value', () {
      expect(
        zh(
          inspect(WorkspaceErrorCode.skillContentLimitExceeded, {
            'limit': 'fileCount',
            'actual': 1001,
            'maximumFileCount': 1000,
            'maximumByteSize': 52428800,
          }),
        ),
        AppLocalizationsZh().errorSkillFileCountExceeded(1000),
      );
      expect(
        en(
          inspect(WorkspaceErrorCode.skillContentLimitExceeded, {
            'limit': 'byteSize',
            'maximumFileCount': 1000,
            'maximumByteSize': 52428800,
          }),
        ),
        AppLocalizationsEn().errorSkillByteSizeExceeded(50),
      );
      expect(
        en(inspect(WorkspaceErrorCode.skillContentLimitExceeded)),
        AppLocalizationsEn().errorSkillContentLimitExceeded,
      );
    });

    test('invalid SKILL.md files name the file when the Workspace does', () {
      expect(
        en(
          inspect(WorkspaceErrorCode.invalidSkill, {
            'reason': 'unsupportedSkillName',
            'path': 'skills/review/SKILL.md',
          }),
        ),
        AppLocalizationsEn().errorSkillNameUnsupportedAt(
          'skills/review/SKILL.md',
        ),
      );
      expect(
        zh(
          inspect(WorkspaceErrorCode.invalidSkill, {
            'reason': 'missingDescription',
            'path': 'SKILL.md',
          }),
        ),
        AppLocalizationsZh().errorSkillMarkdownInvalidAt('SKILL.md'),
      );
      expect(
        en(
          inspect(WorkspaceErrorCode.invalidSkill, {
            'reason': 'invalidSkillFrontmatter',
          }),
        ),
        AppLocalizationsEn().errorSkillMarkdownInvalid,
      );
      expect(
        en(inspect(WorkspaceErrorCode.invalidSkill)),
        AppLocalizationsEn().errorInvalidSkill,
      );
    });

    test('a locator with a query explains what to remove', () {
      expect(
        en(
          inspect(WorkspaceErrorCode.transportRejected, {
            'reason': 'embeddedCredentials',
          }),
        ),
        AppLocalizationsEn().errorSourceLocatorHasQuery,
      );
      expect(
        en(inspect(WorkspaceErrorCode.transportRejected)),
        AppLocalizationsEn().errorTransportRejected,
      );
    });
  });
}
