// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'SkillDeck';

  @override
  String get navWorkspace => 'Skills';

  @override
  String get navMaintenance => '维护';

  @override
  String get navInstalled => '已安装';

  @override
  String get navWrite => '编写';

  @override
  String get navTest => '测试';

  @override
  String get navUpdates => '更新';

  @override
  String get navFavorites => '收藏';

  @override
  String get navSettings => '设置';

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '关闭';

  @override
  String get trayShowWindow => '显示主窗口';

  @override
  String get trayQuit => '退出 SkillDeck';

  @override
  String get commonDone => '完成';

  @override
  String get commonBack => '返回';

  @override
  String get commonContinue => '继续';

  @override
  String get commonRetry => '重试';

  @override
  String get commonRefresh => '刷新';

  @override
  String get commonRefreshAndReview => '刷新并重新检查';

  @override
  String get commonGlobal => '全局';

  @override
  String get commonProject => '项目';

  @override
  String get activationUniversalAgents => '通用 Agents';

  @override
  String get activationUnknownAgent => '未知 Agent';

  @override
  String get activationInactive => '未激活';

  @override
  String get agentsManage => '管理 Agents';

  @override
  String get agentsBuiltIn => '内置 Agents';

  @override
  String get agentsDetected => '已检测到';

  @override
  String get agentsEmpty => '暂无可显示的 Agents。';

  @override
  String get agentsRemoveTitle => '将 Agent 移出管理名单？';

  @override
  String get agentsRemoveAction => '移除';

  @override
  String get agentsRemoveDescription =>
      '这只会将 Agent 从 App 管理名单移除。已有 Skill 文件和激活状态保持不变，Agent 仍可访问它们。';

  @override
  String get agentsOutsideRoster => '已移出管理名单';

  @override
  String get activationAllAgentsToggle => '选择全部 Agents';

  @override
  String get operationPreparing => '正在准备…';

  @override
  String get operationInspecting => '正在检查来源…';

  @override
  String get operationWaitingForLock => '正在等待仓库…';

  @override
  String get operationPlanning => '正在规划更改…';

  @override
  String get operationApplying => '正在应用更改…';

  @override
  String get operationRecovering => '正在恢复仓库状态…';

  @override
  String get operationRollingBack => '正在还原之前的状态…';

  @override
  String get operationSucceeded => '操作已完成。';

  @override
  String get operationFailed => '操作失败。';

  @override
  String get operationCancelled => '操作已取消。';

  @override
  String operationProgress(Object completed, Object total) {
    return '$completed / $total';
  }

  @override
  String get warningInternalSymlinkSkipped => '已跳过一个内部符号链接。';

  @override
  String get warningSourceEntrySkipped => '已跳过一个不支持的来源条目。';

  @override
  String get warningNoActivationTarget => '未找到兼容的激活目标。';

  @override
  String get warningProjectSymlinkPortability => '此项目的激活使用符号链接，可能无法在其他设备上使用。';

  @override
  String get warningDuplicateExposure => '此 Skill 已在等效位置激活。';

  @override
  String get warningSharedActivationLocation =>
      '多个 Agent 的 Skills 文件夹实际是同一个文件夹，已为它们一并激活。';

  @override
  String get warningAgentUndetected => '此设备未检测到所选 Agent。';

  @override
  String get warningActivationTargetSkipped => '已跳过一个不可用的激活目标。';

  @override
  String get warningRecoveryCleanupDeferred => '部分临时恢复文件未能清理，仓库数据未受影响。';

  @override
  String get commonSectionBreadcrumb => '工作区';

  @override
  String get browserRepositoryUnavailable => '仓库不可用';

  @override
  String get browserRepositoryUnavailableMessage => '无法打开 Skills 仓库。';

  @override
  String get browserDesktopRequired => '需要桌面端';

  @override
  String get browserDesktopRequiredMessage => 'Skills 管理目前仅支持桌面平台。';

  @override
  String get browserRefreshRepository => '刷新仓库';

  @override
  String get browserBreadcrumb => '工作区 / 已安装';

  @override
  String get browserInstalled => '已安装';

  @override
  String browserNoMatches(Object query) {
    return '没有匹配 \"$query\" 的 Skills。';
  }

  @override
  String get browserFavoritesEmpty => '还没有收藏的 Skills。';

  @override
  String get browserInactive => '未激活';

  @override
  String browserActiveRatio(Object count, Object total) {
    return '已激活 $count/$total';
  }

  @override
  String get browserAddSkills => '添加 Skill';

  @override
  String get browserAddFromSource => '从来源添加';

  @override
  String get browserDiscoverExistingSkills => '发现已有 Skills';

  @override
  String browserUnmanagedSkillsFound(Object count) {
    return '发现 $count 个未管理 Skills';
  }

  @override
  String get browserAllAgents => '全部 Agents';

  @override
  String get browserAllScopes => '全部范围';

  @override
  String get browserSearchSkills => '搜索 Skills';

  @override
  String get browserNoSkillsYet => '暂无 Skills';

  @override
  String get browserEmptyDescription => '从本地文件夹、Git 仓库或 URL 安装第一个 Skill。';

  @override
  String browserAgentFilter(Object number) {
    return 'Agents 筛选 $number';
  }

  @override
  String get browserScopeSelector => '范围筛选';

  @override
  String get browserSort => '排序';

  @override
  String get browserSortNameAscending => '名称 A-Z';

  @override
  String get browserSortNameDescending => '名称 Z-A';

  @override
  String get browserSortRecentlyAdded => '最近添加';

  @override
  String get browserSortOldestAdded => '最早添加';

  @override
  String get workspaceBackToSkills => '返回 Skills 列表';

  @override
  String get workspaceBreadcrumb => '已安装';

  @override
  String get workspaceCheckForUpdate => '检查更新';

  @override
  String get workspaceUpdateAvailableAction => '可升级';

  @override
  String get workspaceUpdateNow => '立即更新';

  @override
  String get workspaceRemoveSkill => '删除 Skill';

  @override
  String get workspaceFavorite => '收藏';

  @override
  String get workspaceUnfavorite => '取消收藏';

  @override
  String get workspaceTranslate => '翻译';

  @override
  String get workspaceTranslationComingSoon => '翻译功能将在后续版本提供';

  @override
  String get workspaceVersion => '版本';

  @override
  String get workspaceSource => '来源';

  @override
  String get workspaceReplaceSource => '更换来源';

  @override
  String get workspaceReplaceSourceTitle => '更换 Skill 来源';

  @override
  String get workspaceReplaceSourceDescription =>
      '新来源必须包含相同的 Skill，现有激活状态会被保留。';

  @override
  String get workspaceReplaceSourceConfirm => '更换来源';

  @override
  String get workspaceReplaceSourceSuccess => 'Skill 来源已更换。';

  @override
  String get workspaceReplaceSourceStepReplace => '替换';

  @override
  String get workspaceReplaceSourceMismatch => '不是当前 Skill';

  @override
  String workspaceReplaceSourceNoMatch(Object name) {
    return '此来源中没有 $name。';
  }

  @override
  String get workspaceReplaceSourceCurrent => '当前来源';

  @override
  String get workspaceReplaceSourceNew => '新来源';

  @override
  String get workspaceReplacing => '正在更换来源…';

  @override
  String get sourceKindLocal => '本地';

  @override
  String get sourceKindGit => 'Git';

  @override
  String get sourceKindUrl => 'URL';

  @override
  String get workspacePreview => '预览';

  @override
  String get workspaceSettings => '设置';

  @override
  String get workspaceSkillNotFound => '未找到 Skill';

  @override
  String get workspaceDocumentUnavailable => '无法读取所选 Markdown 文件。';

  @override
  String workspaceDocumentUnavailableNamed(String fileName) {
    return '无法读取 $fileName。';
  }

  @override
  String get workspaceDocumentBrowserTitle => 'Markdown 文件';

  @override
  String get workspaceDocumentListUnavailable => '无法加载 Markdown 文件列表。';

  @override
  String get workspaceDocumentListEmpty => '未找到 Markdown 文件。';

  @override
  String workspaceDocumentSelectorTooltip(String fileName) {
    return '选择 Markdown 文件，当前文件：$fileName';
  }

  @override
  String get workspaceActivations => '激活状态';

  @override
  String get workspaceActivateTitle => '激活 Skill';

  @override
  String get workspaceActivateDescription => '选择要使用此 Skill 的 Agents。';

  @override
  String get workspaceActivateScope => '激活范围';

  @override
  String get workspaceActivateTargets => 'Agents';

  @override
  String get workspaceActivateNoTargets => '此范围内没有可用的 Agents。';

  @override
  String get workspaceActivateAlreadyActive => '已激活';

  @override
  String get workspaceActivateUndetectedWarning => '尚未检测到，但仍可显式激活。';

  @override
  String get workspaceActivateSelectProject => '选择项目根目录';

  @override
  String get workspaceTakeoverTitle => '替换现有目标？';

  @override
  String workspaceTakeoverDescription(String agentName) {
    return '$agentName 的 Skill 路径中已存在同名内容。请确认后再用受管副本替换。';
  }

  @override
  String workspaceInstallTakeoverDescription(String agentName) {
    return '$agentName 的 Skill 路径已被占用。请检查后再替换现有项目并安装。';
  }

  @override
  String get workspaceTakeoverPath => '路径';

  @override
  String get workspaceTakeoverType => '现有项目';

  @override
  String get workspaceTakeoverContent => '内容';

  @override
  String get workspaceTakeoverSkillDirectory => 'Skill 文件夹';

  @override
  String get workspaceTakeoverSkillSymbolicLink => 'Skill 符号链接';

  @override
  String get workspaceTakeoverFile => '文件';

  @override
  String get workspaceTakeoverInvalidDirectory => '不含有效 SKILL.md 的文件夹';

  @override
  String get workspaceTakeoverBrokenSymbolicLink => '已断开的符号链接';

  @override
  String get workspaceTakeoverContentDifferent => '与所选 Skill 内容不同';

  @override
  String get workspaceTakeoverContentUnknown => '无法与所选 Skill 比较';

  @override
  String get workspaceTakeoverOpenLocation => '打开所在位置';

  @override
  String get workspaceTakeoverConfirm => '替换并激活';

  @override
  String get workspaceInstallTakeoverConfirm => '替换并安装';

  @override
  String get workspaceTakeoverWarning =>
      '现有项目将被替换；如果操作失败，SkillDeck 会使用恢复数据将其还原。';

  @override
  String get notificationOpenLocationFailed => '无法打开文件所在位置。';

  @override
  String get workspaceNotes => '备注';

  @override
  String get workspaceAddNote => '为此 Skill 添加备注…';

  @override
  String get workspaceNotDetected => '此设备未检测到';

  @override
  String get workspaceGlobalScope => '全局范围';

  @override
  String get workspaceNoActivations => '尚未在任何 Agent 中激活。';

  @override
  String get workspaceDeactivate => '停用';

  @override
  String get workspaceActivate => '激活';

  @override
  String get workspaceActive => '已激活';

  @override
  String get workspaceInactive => '未激活';

  @override
  String get workspaceDuplicateActivationTitle => '可能重复激活';

  @override
  String get workspaceDuplicateActivationMessage =>
      '该 Skill 已在此 Agent 的全局范围激活，继续在项目中激活可能产生重复的 Skill。';

  @override
  String get workspaceDuplicateActivationContinue => '继续激活';

  @override
  String get workspaceDuplicateActivationDontAskAgain => '不再提示';

  @override
  String get workspaceRemoveTitle => '删除 Skill？';

  @override
  String get workspaceRemoveMessage => '这会删除仓库副本并清除其 Agent 激活状态。';

  @override
  String workspaceRemoveNamedTitle(Object name) {
    return '删除 $name？';
  }

  @override
  String get workspaceRemoveDetailedMessage =>
      '这会永久删除仓库副本并清除所有 Agent 激活状态，且无法撤销。';

  @override
  String get workspaceRemoveCleared => '将被清除';

  @override
  String workspaceRemoveSlot(Object name) {
    return 'Skill 槽位 — $name';
  }

  @override
  String workspaceRemoveActivationCount(Object count) {
    return '$count 个 Agent 组';
  }

  @override
  String get workspaceRemoveAction => '删除 Skill';

  @override
  String get workspaceRemoveFailed => '无法删除该 Skill。';

  @override
  String get workspaceRemoving => '正在删除…';

  @override
  String get workspaceRemoveConfirmAgain => '再次确认';

  @override
  String workspaceRemoveRevision(Object revision) {
    return '已基于版本 r$revision 确认。如果仓库发生变化，需要重新检查。';
  }

  @override
  String workspaceRemoveStale(Object revision) {
    return '仓库已发生变化。请检查版本 r$revision 中刷新后的 Skill，然后再次确认。';
  }

  @override
  String get updatesBreadcrumb => '工作区';

  @override
  String get updatesTitle => '更新';

  @override
  String get updatesCheckAgain => '重新检查';

  @override
  String get updatesUpdateAll => '全部更新';

  @override
  String get updatesEmpty => '所有 Skills 均为最新版本。';

  @override
  String get updatesCurrent => '已是最新';

  @override
  String get updatesAvailable => '有可用更新';

  @override
  String get updatesUnavailable => '来源不可用';

  @override
  String get updatesTimedOut => 'Git 更新检查超时';

  @override
  String get updatesUnsupported => '此来源不支持更新';

  @override
  String get updatesUpdate => '更新';

  @override
  String get updatesResolutionRequired => '更新需要处理';

  @override
  String get updatesCandidateResolutionRequired => '更新候选需要处理';

  @override
  String get updatesAbandonCandidate => '放弃候选';

  @override
  String get updatesNotChecked => '尚未检查';

  @override
  String get updatesChecking => '正在检查…';

  @override
  String get updatesCheckFailed => '本次检查未能完成。';

  @override
  String get updatesCheckOne => '检查';

  @override
  String updatesCheckProgress(Object completed, Object total) {
    return '已检查 $completed/$total';
  }

  @override
  String updatesUpdatingSkill(String slotKey) {
    return '正在更新 $slotKey';
  }

  @override
  String updatesUpdatingSkills(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '正在更新 $count 个 Skill',
    );
    return '$_temp0';
  }

  @override
  String updatesUpdatingDetail(String slotKey, String phase) {
    return '$slotKey · $phase';
  }

  @override
  String get updatesFetchingSource => '正在获取新版本…';

  @override
  String get updatesIntegrityRecovery => '此 Skill 必须先恢复，才能更改。';

  @override
  String get settingsBreadcrumb => '工作区';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsValidateWorkspace => 'Skills 校验';

  @override
  String get settingsValidateWorkspaceRunning => '正在校验 Skills…';

  @override
  String get settingsValidateWorkspaceDone => '工作区校验完成。';

  @override
  String get settingsValidateWorkspaceDescription =>
      '检查所有已管理 Skills 是否存在缺失或变更文件。';

  @override
  String get settingsAppUpdateTitle => '检查更新';

  @override
  String settingsAppUpdateCurrentVersion(String version) {
    return '当前版本：$version';
  }

  @override
  String get settingsAppUpdateVersionUnknown => '无法获取';

  @override
  String get settingsAppUpdateUnconfigured => '此构建尚未配置自动更新。';

  @override
  String get settingsAppUpdateInvalid => '此构建的更新配置无效。';

  @override
  String get settingsAppUpdateReady => '已启用自动更新检查。';

  @override
  String get settingsAppUpdateChecking => '正在检查更新';

  @override
  String settingsAppUpdateAvailable(String version) {
    return 'SkillDeck $version 可用。';
  }

  @override
  String get settingsAppUpdateAvailableGeneric => '有新的 SkillDeck 版本可用。';

  @override
  String get settingsAppUpdateDownloaded => '签名更新已在更新器中准备就绪。';

  @override
  String get settingsAppUpdateFailed => '更新操作失败，请重新检查。';

  @override
  String get settingsAppUpdateBusy => '请先完成正在进行的 SkillDeck 操作，再重启更新。';

  @override
  String get settingsAppUpdateCheck => '检查更新';

  @override
  String get sidebarAppUpdateChecking => '正在检查…';

  @override
  String get sidebarAppUpdateAvailable => '有可用更新';

  @override
  String get sidebarAppUpdateDownloaded => '安装更新';

  @override
  String get sidebarAppUpdateFailed => '重试更新';

  @override
  String get settingsAboutTitle => 'SkillDeck';

  @override
  String get settingsOfficialWebsite => '官网入口';

  @override
  String get settingsChangelog => '更新日志';

  @override
  String get settingsPrivacyPolicy => '隐私政策';

  @override
  String get settingsTermsOfService => '用户协议';

  @override
  String get settingsOpenSourceLicenses => '开源许可证';

  @override
  String get openSourceLicensesTitle => '开源许可证';

  @override
  String get openSourceLicensesSubtitle => 'SkillDeck 由这些组件构建。选择一项查看它的许可证。';

  @override
  String openSourceLicensesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 份许可证',
    );
    return '$_temp0';
  }

  @override
  String get openSourceLicensesLoadFailed => '许可证文本加载失败。';

  @override
  String get settingsValidateWorkspaceFailed => '工作区校验失败。';

  @override
  String settingsValidateWorkspaceSummary(
    Object checked,
    Object drifted,
    Object failed,
    Object repaired,
  ) {
    return '已校验 $checked 个 Skills，修复 $repaired 个文件，发现 $drifted 个外部变更，$failed 个 Skills 失败。';
  }

  @override
  String get settingsEnvironmentTitle => '环境检查';

  @override
  String get settingsEnvironmentDescription =>
      '检查 SkillDeck 依赖的外部工具。仅在你手动发起时执行检查。';

  @override
  String get settingsEnvironmentRecheck => '重新检查';

  @override
  String get settingsEnvironmentOpenInstallPrompt => '打开安装提示';

  @override
  String get settingsEnvironmentCheckGit => 'Git 命令行';

  @override
  String get settingsEnvironmentStatusNotChecked => '尚未检查';

  @override
  String get settingsEnvironmentStatusChecking => '正在检查…';

  @override
  String get settingsEnvironmentGitAvailable => 'Git 可用。';

  @override
  String get settingsEnvironmentGitNotInstalled =>
      '此设备上未找到 Git。公开的 HTTPS 仓库仍可安装；SSH 地址和私有仓库需要 Git。';

  @override
  String get settingsEnvironmentGitDeveloperToolsRequired =>
      '需要安装 macOS 命令行开发者工具。请在系统弹窗中选择「安装」，完成后重新检查。';

  @override
  String get settingsEnvironmentGitDeveloperToolsInstalling =>
      '命令行开发者工具正在安装，请在安装完成后重新检查。';

  @override
  String get settingsEnvironmentGitProbeFailed => 'Git 检查未能完成。';

  @override
  String get settingsInterfaceLanguage => '界面语言';

  @override
  String get settingsFollowSystem => '跟随系统';

  @override
  String get settingsChinese => '中文';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsCustomAgents => '自定义 Agents';

  @override
  String get settingsCustomAgentsDescription => '管理此设备上其他 Agent 的 Skills 目录。';

  @override
  String get settingsAgentsManagementTitle => 'Agents管理';

  @override
  String get settingsAgentsManagementDescription =>
      '管理内置 Agents，并配置此设备上的自定义 Agents。';

  @override
  String get settingsAddAgent => '添加 Agent';

  @override
  String get settingsEditAgent => '编辑 Agent';

  @override
  String get settingsDeleteAgent => '移除 Agent';

  @override
  String get settingsSaveAgent => '保存 Agent';

  @override
  String get settingsAgentName => 'Agent 名称';

  @override
  String get settingsAgentIcon => '图标';

  @override
  String get settingsAgentPathGlobal => '全局 Skills 目录';

  @override
  String get settingsAgentPathProject => '项目 Skills 相对目录';

  @override
  String get settingsAgentChooseGlobalDirectory => '选择全局 Skills 目录';

  @override
  String get settingsAgentAdvancedShow => '显示高级设置';

  @override
  String get settingsAgentAdvancedHide => '收起高级设置';

  @override
  String get settingsAgentDiscoveryPathsGlobal => '其他全局发现目录';

  @override
  String get settingsAgentDiscoveryPathsProject => '其他项目发现目录';

  @override
  String get settingsAgentDiscoveryPathsHint =>
      '每行一个路径。这些路径只用于发现并迁移已有 Skills，不会作为新的写入目标。';

  @override
  String get settingsAgentNoCustom => '还没有自定义 Agent。';

  @override
  String get settingsAgentDeleteConfirm => '移除这个 Agent 配置？已有文件和激活链接不会被删除。';

  @override
  String get settingsAgentInvalidPath =>
      '请为当前设备配置绝对的全局路径或安全的项目相对路径；其他发现目录需要先配置相同范围的 Skills 目录。';

  @override
  String get settingsAgentBusy => 'Agent 配置正在处理中，请等待当前操作完成。';

  @override
  String get settingsAgentReloadFailed => 'Agent 配置未能应用，之前的配置仍在生效。';

  @override
  String get translationSettingsTitle => '翻译';

  @override
  String get translationSettingsDescription =>
      '配置唯一启用的 Provider 配置。每次翻译都只会在你明确确认后上传 Skill 内容。';

  @override
  String get translationProvider => 'Provider';

  @override
  String get translationProviderOpenAI => 'OpenAI 兼容';

  @override
  String get translationProviderAnthropic => 'Anthropic';

  @override
  String get translationEndpoint => 'Endpoint';

  @override
  String get translationModel => '模型';

  @override
  String get translationTargetLanguage => '目标语言';

  @override
  String get translationApiKey => 'API Key';

  @override
  String get translationApiKeyStored => '已安全存储；仅在需要替换时输入新值';

  @override
  String get translationApiKeyOptional => '本地 OpenAI 兼容 Endpoint 可不填';

  @override
  String get translationAdvancedShow => '显示高级设置';

  @override
  String get translationAdvancedHide => '收起高级设置';

  @override
  String get translationProtocol => '协议';

  @override
  String get translationCharacterBudget => '字符预算';

  @override
  String get translationConcurrency => '并发数';

  @override
  String get translationMaxOutputTokens => '最大输出 Token';

  @override
  String get translationOptional => '可选';

  @override
  String get translationReasoning => '推理';

  @override
  String get translationReasoningDescription => '默认关闭，避免推理占用翻译输出预算。';

  @override
  String get translationSave => '保存翻译设置';

  @override
  String get translationSettingsError => '无法保存翻译设置。请检查输入后重试。';

  @override
  String get translationAction => '翻译';

  @override
  String get translationCancel => '取消翻译';

  @override
  String get translationConfirmTitle => '翻译这个 Skill？';

  @override
  String get translationConfirmMessage => 'Skill 文本将发送到以下服务。';

  @override
  String get translationConfirmProvider => 'Provider';

  @override
  String get translationConfirmEndpoint => 'Endpoint 主机';

  @override
  String get translationConfirmTarget => '目标语言';

  @override
  String get translationScopeFullDocument => '翻译全文';

  @override
  String get translationScopeDescription => '仅翻译描述';

  @override
  String get translationDescriptionUnavailable =>
      '当前 SKILL.md 没有可翻译的 description。';

  @override
  String get translationShowCached => '显示缓存';

  @override
  String get translationConfigureFirst => '请先在设置中配置翻译 Provider。';

  @override
  String get translationProviderOpenAIShort => 'OpenAI 兼容';

  @override
  String get translationProviderAnthropicShort => 'Anthropic';

  @override
  String get translationShowOriginal => '显示原文';

  @override
  String get translationDeleteCache => '删除译文缓存';

  @override
  String get projectRootsTitle => '管理项目目录';

  @override
  String get projectRootsDescription => '注册后的根目录可用于项目范围的激活。';

  @override
  String get projectRootsEmpty => '尚未注册项目根目录。';

  @override
  String get projectRootsAdd => '添加项目根目录';

  @override
  String get projectRootsManage => '管理';

  @override
  String get projectRootsRemove => '移除项目根目录';

  @override
  String get projectRootsError => '项目根目录操作失败。';

  @override
  String get externalSkillsTitle => '发现已有 Skills';

  @override
  String get externalSkillsDescription =>
      '它们由其他工具装在 Agent 文件夹里。接管后，可以在 SkillDeck 里统一更新和激活。';

  @override
  String get externalSkillsScanning => '正在扫描已知 Agents 位置…';

  @override
  String get externalSkillsEmpty => '未发现未管理 Skills';

  @override
  String get externalSkillsEmptyDescription =>
      '已知 Agents 位置中的有效 Skills 均已纳入管理。';

  @override
  String get externalSkillsRescan => '重新扫描';

  @override
  String externalSkillsAdoptCount(Object count) {
    return '接管 $count 个';
  }

  @override
  String get externalSkillsAdopting => '正在接管 Skills';

  @override
  String externalSkillsCompletedCount(Object completed, Object total) {
    return '已完成 $completed/$total 个 Skills。';
  }

  @override
  String get externalSkillsSuccess => 'Skills 接管完成';

  @override
  String get externalSkillsCancelled => '接管已取消';

  @override
  String get externalSkillsPartial => '部分 Skills 已完成接管';

  @override
  String get externalSkillsScanFailed => '扫描失败';

  @override
  String get externalSkillsAdoptionFailed => '接管失败';

  @override
  String externalSkillsFailedTitle(int count) {
    return '$count 个 Skill 未能接管';
  }

  @override
  String externalSkillsFoundTitle(int count) {
    return '发现 $count 个已有 Skill';
  }

  @override
  String get externalSkillsSummaryTotal => '共发现';

  @override
  String get externalSkillsSummaryReady => '可以直接接管';

  @override
  String get externalSkillsSummaryConflicts => '需要选择版本';

  @override
  String externalSkillsSummaryCount(int count) {
    return '$count 个';
  }

  @override
  String get externalSkillsDecideTitle => '解决冲突';

  @override
  String get externalSkillsDecideSubtitle => '同名 Skill 在不同 Agent 里内容不同';

  @override
  String get externalSkillsChooseVersion => '选择版本';

  @override
  String get externalSkillsVersionMenuTitle => '以哪个版本为准';

  @override
  String get externalSkillsOpenFolder => '在访达中显示';

  @override
  String externalSkillsRestTitle(int count) {
    return '另外 $count 个可以直接接管';
  }

  @override
  String externalSkillsReadyTitle(int count) {
    return '$count 个可以直接接管';
  }

  @override
  String externalSkillsNamesMore(String names) {
    return '$names 等';
  }

  @override
  String get externalSkillsNameSeparator => '、';

  @override
  String get externalSkillsViewAll => '查看全部';

  @override
  String get externalSkillsChooseIndividually => '逐个选择';

  @override
  String externalSkillsAdoptAll(int count) {
    return '全部接管 $count 个';
  }

  @override
  String get externalSkillsSelectAll => '全选';

  @override
  String get externalSkillsAgentsColumn => '所在 Agent';

  @override
  String externalSkillsConflictCopies(int count) {
    return '$count 份副本内容不同';
  }

  @override
  String get externalSkillsSharedFolder => '通用文件夹';

  @override
  String externalSkillsSharedBy(int count) {
    return '$count 个 Agent 共用';
  }

  @override
  String get externalSkillsVerifying => '正在核对最新状态…';

  @override
  String get errorSourceUnavailable => '来源不可用。';

  @override
  String get errorAuthenticationRequired =>
      '仓库不存在，或者是私有仓库。请检查地址；私有仓库需要安装 Git 并完成登录。';

  @override
  String get errorGitUnavailable =>
      '此设备上无法使用 Git。公开的 HTTPS 仓库无需 Git；SSH 地址和私有仓库需要安装 Git。';

  @override
  String get errorGitFailed => 'Git 操作失败，请检查来源地址后重试。';

  @override
  String get errorGitFileCountExceeded => '仓库内容超出扫描限制，请指定仓库子路径后重试。';

  @override
  String get errorDeveloperToolsRequired =>
      'Git 需要 macOS 命令行开发者工具。请前往「设置 › 环境检查」完成配置。';

  @override
  String get errorTransportRejected => '出于安全原因，来源地址已被拒绝。';

  @override
  String get errorArchiveInvalid => '下载的归档文件无效。';

  @override
  String get errorDigestMismatch => '来源内容未通过完整性校验，请检查来源后重试。';

  @override
  String get errorSkillNotFound => '该 Skill 已不存在。';

  @override
  String get errorStaleSnapshot => '仓库已发生变化，请刷新并重新检查此操作。';

  @override
  String get errorInvalidSkill => '来源包含无效或不支持的 Skill。';

  @override
  String get errorSkillContentLimitExceeded => 'Skill 内容超出支持的文件数量或大小限制。';

  @override
  String get errorInvalidSource => '该来源不受支持。';

  @override
  String get errorDuplicateSkill => '该 Skill 与已安装的 Skill Slot 冲突。';

  @override
  String get errorDuplicateSkillsWithinSource => '该来源包含多个同名 Skill，请指定具体子路径。';

  @override
  String get errorSourceReplacementRequired => '已存在同一 Skill Slot，请通过“更换来源”继续。';

  @override
  String get errorExternalSkillConflict => '此激活目标已存在未管理的 Skill，请刷新并检查后再继续。';

  @override
  String get errorActivation => '激活目标不可用或不受支持。';

  @override
  String get errorAdoptionTargetOccupied => '此 Skill 的目标文件夹已被其他内容占用，请移走后重试。';

  @override
  String errorAdoptionTargetOccupiedFile(Object path) {
    return '此 Skill 的文件夹位置被一个文件占用，请移走后重试：$path';
  }

  @override
  String errorAdoptionTargetOccupiedInvalidSkill(Object path) {
    return '此 Skill 的文件夹里有一个无效的 SKILL.md，请修复或移走该文件夹后重试：$path';
  }

  @override
  String errorAdoptionTargetOccupiedDirectoryWithContent(Object path) {
    return '此 Skill 的文件夹里已有其他文件，请把该文件夹移走后重试：$path';
  }

  @override
  String errorAdoptionTargetOccupiedOtherSkill(Object path) {
    return '此 Skill 的文件夹里是另一个 Skill，请重命名或移走其中一个后重试：$path';
  }

  @override
  String errorAdoptionTargetOccupiedSameSlotSkill(Object path) {
    return '此 Skill 的文件夹里有它的另一份副本，但不在本次审查中，请移走该副本后重试：$path';
  }

  @override
  String errorAdoptionTargetOccupiedLink(Object path) {
    return '此 Skill 的文件夹是一个指向其他内容的链接，请删除该链接后重试：$path';
  }

  @override
  String get errorProjectRoot => '所选项目根目录已移除。';

  @override
  String get errorInvalidProjectRoot => '所选项目目录无效。';

  @override
  String get errorProjectRootConflict => '项目目录与现有注册项冲突。';

  @override
  String get errorAgent => '所选 Agent 不可用。';

  @override
  String get errorDuplicateAgentId => 'Agent 标识已存在。';

  @override
  String get errorPersonalTagNotFound => '该个人标签已不存在。';

  @override
  String get errorDuplicatePersonalTag => '已存在同名个人标签。';

  @override
  String get errorRepositoryBusy => '另一个操作正在使用仓库。';

  @override
  String get errorOperationCancelled => '操作已取消。';

  @override
  String get errorRepositoryState => '仓库状态需要恢复或不受支持。';

  @override
  String get errorControlPlaneCorrupt => '工作区控制数据已损坏。为保护 Skills，当前已阻止继续修改。';

  @override
  String get errorUnsupportedWorkspaceVersion =>
      '此工作区版本不受当前应用支持，请更新 SkillDeck 后重试。';

  @override
  String get errorWorkspaceMaintenanceFailed => '工作区维护失败，恢复完成前已阻止修改。';

  @override
  String get errorMigrationFailed => '工作区未能安全升级，系统没有继续执行后续修改。';

  @override
  String get errorRevisionStoreCorrupt =>
      'Skill 版本存储已损坏。请替换来源或删除受影响的 Skill 以安全恢复。';

  @override
  String get errorDirtyDraftResolutionRequired =>
      '该 Skill 存在未发布的修改，请先发布或丢弃修改后再继续。';

  @override
  String get errorUpdateCandidateResolutionRequired =>
      '该 Skill 存在尚未解决的更新候选，请先解决或放弃候选后再继续。';

  @override
  String get errorNameChangeNotAllowed => '已管理 Skill 不能更改声明名称，请恢复原名称后再继续。';

  @override
  String get errorFinalizationRecoveryFailed =>
      '修改已提交，但恢复流程未能完成。请先重试恢复，再执行其他修改。';

  @override
  String get workspaceIntegrityRecoveryTitle => 'Skill 需要恢复';

  @override
  String get workspaceIntegrityRecoveryMessage =>
      '无法验证此 Skill 的版本数据。更新、激活、收藏和备注已禁用。请替换来源或删除该 Skill 以安全恢复。';

  @override
  String get workspaceIntegrityValidating => '校验中';

  @override
  String get workspaceIntegrityDriftPending => '检测到外部变更';

  @override
  String get workspaceIntegrityRepairFailed => '修复失败';

  @override
  String get workspaceIntegrityStoreCorrupt => '需要恢复';

  @override
  String get errorRollback => '无法安全恢复此操作。';

  @override
  String get errorIo => '本地文件操作失败。';

  @override
  String get errorUnknown => '操作失败。';

  @override
  String get acquisitionTitle => '添加 Skill';

  @override
  String get acquisitionSubtitle => '从本地文件夹、Git 仓库或 URL 安装。';

  @override
  String get acquisitionSource => '来源';

  @override
  String get acquisitionSkillsFound => '找到的 Skills';

  @override
  String get acquisitionSelectAllSkills => '全部选择';

  @override
  String get acquisitionNoValidSkills => '未找到有效 Skills。';

  @override
  String get acquisitionScope => '范围';

  @override
  String get acquisitionAgents => 'Agents';

  @override
  String get acquisitionGlobalDescription => '在此设备的所有项目中激活。';

  @override
  String get acquisitionProjectDescription => '仅在指定的已注册项目根目录中激活。';

  @override
  String get acquisitionRegisterProjectRoot => '请先注册项目根目录，再在项目范围内激活。';

  @override
  String get acquisitionManageProjectRoots => '管理项目目录';

  @override
  String get acquisitionStoreOnly => '仅存储';

  @override
  String acquisitionDetectedCount(Object count) {
    return '/ 检测到 $count 个';
  }

  @override
  String get acquisitionAddAgent => '添加 Agent';

  @override
  String get acquisitionInstalling => '正在安装 Skills…';

  @override
  String get acquisitionPreparing => '正在准备来源…';

  @override
  String get acquisitionInspecting => '正在检查来源…';

  @override
  String get acquisitionWaitingForRepository => '正在等待仓库…';

  @override
  String get acquisitionPlanning => '正在规划更改…';

  @override
  String get acquisitionApplying => '正在应用更改…';

  @override
  String get acquisitionRestoring => '正在还原之前的状态…';

  @override
  String get acquisitionFinishing => '正在完成…';

  @override
  String get acquisitionErrorResolve => '请输入支持的本地、Git 或 HTTPS 来源。';

  @override
  String get acquisitionErrorInspect => '无法检查该来源。';

  @override
  String get acquisitionErrorInstall => '无法安装 Skills。';

  @override
  String get acquisitionGoToEnvironmentSettings => '前往设置';

  @override
  String get acquisitionErrorRefresh => 'Skills 已安装，但无法刷新仓库。';

  @override
  String get acquisitionSelect => '选择';

  @override
  String get acquisitionActivate => '激活';

  @override
  String get acquisitionLocalFolder => '本地文件夹';

  @override
  String get acquisitionLocalFolderDescription => '包含一个或多个 Skills 的文件夹。';

  @override
  String get acquisitionGitRepository => 'Git 仓库';

  @override
  String get acquisitionGitRepositoryDescription =>
      'GitHub、GitLab 或任意 Git 远程仓库。';

  @override
  String get acquisitionWebSourceUrl => '网页来源 URL';

  @override
  String get acquisitionWebSourceUrlDescription => '符合约定的 HTTPS Skills 端点。';

  @override
  String get acquisitionFolderPath => '文件夹路径';

  @override
  String get acquisitionRepositoryUrl => '仓库 URL';

  @override
  String get acquisitionSourceUrl => '来源 URL';

  @override
  String get acquisitionFolderPathHint => '/路径/到/Skills';

  @override
  String get acquisitionRepositoryUrlHint => 'github.com/所有者/仓库 或 所有者/仓库';

  @override
  String get acquisitionGitRef => 'GIT 引用';

  @override
  String get acquisitionGitRefHint => '分支、标签或提交（可选）';

  @override
  String get acquisitionGitSubpath => '仓库子路径';

  @override
  String get acquisitionGitSubpathHint => 'path/to/skills（可选）';

  @override
  String get acquisitionSourceUrlHint => 'https://skills.example.com';

  @override
  String get acquisitionMultipleSkillsHint => '一个仓库可一次安装多个 Skills。';

  @override
  String acquisitionStep(Object current) {
    return '第 $current 步，共 3 步';
  }

  @override
  String acquisitionInstall(Object count, Object plural) {
    return '安装 $count 个 Skill$plural';
  }

  @override
  String get notificationInfoTitle => '通知';

  @override
  String get notificationSuccessTitle => '操作完成';

  @override
  String get notificationWarningTitle => '操作完成，但有警告';

  @override
  String get notificationErrorTitle => '操作失败';

  @override
  String get notificationRepositoryRefreshed => '仓库已刷新。';

  @override
  String get notificationSkillsInstalled => '所选 Skills 已安装。';

  @override
  String get notificationActivationEnabled => '已激活。';

  @override
  String get notificationActivationDisabled => '已停用。';

  @override
  String get notificationSkillFavorited => '已收藏。';

  @override
  String get notificationSkillUnfavorited => '已取消收藏。';

  @override
  String get notificationSkillUpdated => 'Skill 已更新。';

  @override
  String get notificationSkillRemoved => 'Skill 已删除。';

  @override
  String get notificationUpdatesApplied => '所选更新已应用。';

  @override
  String get notificationProjectRootRegistered => '项目根目录已注册。';

  @override
  String get notificationProjectRootUnregistered => '项目根目录已移除。';

  @override
  String get notificationExternalSkillsAdopted => '所选外部 Skills 已纳入管理。';

  @override
  String get notificationExternalSkillsPartiallyAdopted =>
      '部分 Skills 已纳入管理，其余未能接管。';

  @override
  String get notificationTranslationTitle => '正在翻译';

  @override
  String get notificationTranslationStarted => '翻译已开始，正文将按内容块逐步更新。';

  @override
  String notificationTranslationProgress(Object completed, Object total) {
    return '已翻译 $completed/$total 个内容块。';
  }

  @override
  String get notificationTranslationCancelling => '正在取消翻译…';

  @override
  String get notificationTranslationCompleted => '文档翻译完成。';

  @override
  String get notificationTranslationCancelled => '翻译已取消，并恢复之前的内容。';

  @override
  String get notificationTranslationFailed => '翻译失败，已恢复上次缓存或原文。';

  @override
  String get notificationTranslationCacheDeleted => '译文缓存已删除。';

  @override
  String get notificationTranslationSettingsSaved => '翻译设置已保存。';

  @override
  String get notificationFinalizationPendingTitle => '正在完成恢复';

  @override
  String get notificationFinalizationPending => '更改已提交，正在完成恢复…';

  @override
  String get notificationFinalizationRecovered => '恢复已完成。';

  @override
  String get workspaceFinalizationRetryTitle => '恢复需要处理';

  @override
  String get workspaceFinalizationRetryMessage =>
      '已提交的更改是安全的，但清理尚未完成。请先重试恢复，再继续修改工作区。';

  @override
  String get workspaceFinalizationRetryAction => '重试恢复';

  @override
  String get notificationUpdateCheckStarted => '正在检查更新…';

  @override
  String get notificationUpdateCheckCurrent => '该 Skill 已是最新版本。';

  @override
  String get notificationUpdateCheckAvailable => '该 Skill 有可用更新。';

  @override
  String get notificationUpdateCheckUnavailable => '无法访问来源，更新状态未知。';

  @override
  String get notificationUpdateCheckUnsupported => '此来源不支持检查更新。';

  @override
  String get notificationUpdateCheckResolutionRequired =>
      '该 Skill 需要先在更新页处理，才能更新。';

  @override
  String get notificationUpdateCandidateAbandoned => '已放弃更新候选。';

  @override
  String get notificationOperationCancelled => '操作已取消。';

  @override
  String get notificationCompletedWithWarnings => '操作已完成，但部分项目需要注意。';

  @override
  String get notificationShowDetails => '查看详情';

  @override
  String get ownershipRepairTitle => '修复 Agent 文件夹所有权？';

  @override
  String get ownershipRepairMessage =>
      '部分 Agent Skills 文件夹属于其他用户。SkillDeck 可以先将其所有权恢复为当前账户，再继续操作。';

  @override
  String get ownershipRepairSystemPrompt =>
      'macOS 将弹出管理员密码窗口。SkillDeck 只会更改以下文件夹的所有者，不会修改权限。';

  @override
  String get ownershipRepairCustomAgent => '自定义 Agent — 请确认此路径';

  @override
  String get ownershipRepairBuiltInAgent => '内置 Agent';

  @override
  String get ownershipRepairCancel => '取消';

  @override
  String get ownershipRepairContinue => '修复并继续';

  @override
  String get errorAgentRootOwnership =>
      'SkillDeck 无法安全修复 Agent Skills 文件夹的所有权。请检查文件夹路径和权限后重试。';

  @override
  String errorAgentRootOwnershipOutsideHome(Object path) {
    return 'Agent Skills 文件夹解析到了用户主目录之外，无法自动修复：$path';
  }

  @override
  String errorAgentRootOwnershipNotDirectory(Object path) {
    return '配置的 Agent Skills 路径不是文件夹：$path';
  }

  @override
  String errorAgentRootOwnershipInspectionFailed(Object path) {
    return 'SkillDeck 无法检查这个 Agent Skills 文件夹，它可能是失效或循环的链接：$path';
  }

  @override
  String get errorAgentRootOwnershipAuthorizationRejected =>
      'macOS 未授权修复 Agent Skills 文件夹所有权。';

  @override
  String get errorAgentRootOwnershipRepairFailed =>
      'macOS 无法更改所选 Agent Skills 文件夹的所有者。';

  @override
  String errorAgentRootOwnershipStillInvalid(Object path) {
    return '修复后仍有部分条目属于其他用户：$path';
  }

  @override
  String errorAgentRootOwnershipBlockedCount(int count) {
    return '有 $count 个 Agent Skills 文件夹需要先修正，SkillDeck 才能继续。';
  }

  @override
  String errorAgentRootOwnershipStillInvalidCount(int count) {
    return '修复后仍有 $count 个 Agent Skills 文件夹存在问题。';
  }

  @override
  String get errorAgentRootOwnershipUnsupported =>
      '此设备暂不支持自动修复 Agent Skills 文件夹所有权。';

  @override
  String stubComingSoon(Object section) {
    return '即将推出：$section';
  }

  @override
  String get skillDriftReviewAction => '处理外部变更';

  @override
  String get skillDriftReviewTooltip =>
      '此 Skill 在 SkillDeck 之外被修改。处理之前，更新、激活和编辑暂不可用。';

  @override
  String get skillDriftWhatChanged => '发生了什么';

  @override
  String get skillDriftHowToResolve => '如何处理';

  @override
  String get skillDriftLocationAgentFolder => 'Agent 目录';

  @override
  String get skillDriftLinkReplaced => '原本指向 SkillDeck 的链接被替换成了普通文件或文件夹';

  @override
  String get skillDriftFolderReplaced => '原本的文件夹被替换成了链接或文件';

  @override
  String skillDriftKeepOption(String location) {
    return '保留「$location」中的修改';
  }

  @override
  String get skillDriftKeepOptionDetail => '保存为新版本，并同步到所有位置。之后可以在历史中撤回。';

  @override
  String get skillDriftRestoreOptionDetail => '丢弃外部修改，把所有位置还原为当前版本。';

  @override
  String get skillDriftChooseOption => '请选择处理方式';

  @override
  String get skillDriftDialogTitle => '处理外部变更';

  @override
  String get skillDriftReviewDescription =>
      '以下位置的内容在 SkillDeck 之外被改动过，请决定以哪份为准。';

  @override
  String get skillDriftLocationRepositoryCopy => 'SkillDeck 保存的副本';

  @override
  String get skillDriftContentChanged => '文件内容被修改了';

  @override
  String get skillDriftWrongLinkTarget => '链接被改为指向其他位置';

  @override
  String get skillDriftKeepExternal => '保留这份修改';

  @override
  String get skillDriftRestoreManaged => '恢复 SkillDeck 版本';

  @override
  String get skillDriftRestoreWarning => '外部修改会被覆盖，SkillDeck 不会自动备份。如需保留，请先导出。';

  @override
  String get skillDriftExportAction => '导出…';

  @override
  String skillDriftExported(String path) {
    return '已导出到 $path';
  }

  @override
  String get skillDriftStale => 'Skill 或外部文件在审查后发生了变化，请刷新并重新审查，再选择处理方式。';

  @override
  String get skillDriftKeepUnavailable => '这类修改无法保存为新版本，只能恢复 SkillDeck 版本。';

  @override
  String get skillDriftNoChanges => '当前没有外部变更，恢复操作会保持此 Skill 不变。';

  @override
  String get removeSkillDriftWarning => '此 Skill 存在外部修改。删除后，受管位置的外部修改也将永久丢失。';

  @override
  String get errorDriftResolutionUnavailable =>
      '此操作不适用于当前外部变更，请选择可用的处理方式。如果无法安全审查这些文件，请替换来源或删除 Skill。';

  @override
  String skillDriftMissingArtifacts(int count) {
    return '另有 $count 个缺失位置将被恢复。';
  }

  @override
  String get skillDriftRefreshReview => '刷新并重新审查';

  @override
  String get skillDriftRestoreMissing => '恢复缺失位置';

  @override
  String get settingsGlobalActivationMethod => '全局激活方式';

  @override
  String get settingsActivationMethodAutomatic => '自动';

  @override
  String get settingsActivationMethodCopy => '复制';

  @override
  String get settingsActivationMethodSymbolicLink => '链接';

  @override
  String get settingsActivationMethodAutomaticDescription => '能建链接时用链接，否则复制。';

  @override
  String get settingsActivationMethodCopyDescription =>
      '在 Agent 文件夹里放一份完整副本，兼容性最好；每次更新会重写副本。';

  @override
  String get settingsActivationMethodSymbolicLinkDescription =>
      '指向 SkillDeck 保存的副本，更新立即生效；文件夹不支持链接时激活会失败。';

  @override
  String get settingsActivationMethodScopeNote => '只影响之后新建的激活；项目内的激活始终使用复制。';

  @override
  String get errorSymbolicLinkUnavailable =>
      '这个 Agent 文件夹不支持符号链接。请在 设置 › Agents管理 里把全局激活方式改为“自动”或“复制”。';

  @override
  String get acquisitionCandidateInstalled => '已安装。同一个位置只能放一个 Skill，所以不能重复安装。';

  @override
  String get acquisitionOpenInstalledSkill => '查看';

  @override
  String get acquisitionErrorLocalPath => '请输入文件夹的完整路径，或点击右侧按钮选择文件夹。';

  @override
  String get acquisitionSubtitleV2 => '从链接、安装命令、本地文件夹或 Git 仓库安装。';

  @override
  String get acquisitionInputModeSmart => '智能识别';

  @override
  String get acquisitionInputModeTyped => '按类型';

  @override
  String get acquisitionSmartHint => '粘贴仓库地址、npx skills add 命令、网址或文件夹路径';

  @override
  String get acquisitionAgentPromptTitle => '让 Agent 帮我安装';

  @override
  String get acquisitionAgentPromptCopied => '已复制';

  @override
  String get acquisitionAgentPromptHint =>
      '把提示词发给 Agent，它会使用 skilldeck Skill 安装。';

  @override
  String get acquisitionAgentPromptCopy => '复制提示词';

  @override
  String get acquisitionAgentPromptOpenSettings => '去设置';

  @override
  String get acquisitionAgentSetupTitle => '先开启命令行和 skilldeck Skill';

  @override
  String get acquisitionAgentSetupBody =>
      'Agent 会通过 skilldeck Skill 调用命令行来安装。请在 设置 › 命令行 中完成以下两项。';

  @override
  String get acquisitionAgentSetupTool => '命令行工具已就绪';

  @override
  String get acquisitionAgentSetupSkill => 'skilldeck Skill 已激活到 Agent';

  @override
  String get acquisitionAgentPrompt =>
      '请调用 “skilldeck” Skill，通过 skilldeck 命令帮我安装一个 Skill：\n1. 先查看来源里有哪些 Skill。只有一个时直接安装；有多个时，列出它们的名称和简介，问我要装哪些。\n2. 安装后，在你当前运行的这个 Agent 里激活它，这样你之后就能直接使用。\n3. 完成后告诉我装了哪些 Skill、激活在哪个 Agent。如果需要我在 SkillDeck 里确认，或者某一步失败了，告诉我原因和下一步该怎么做。\n\n我想安装的是（仓库地址、网址或本地文件夹路径）：';

  @override
  String get acquisitionAdvancedOptions => '高级选项';

  @override
  String get acquisitionAdvancedOptionsHint => 'Git 引用、仓库子路径';

  @override
  String get acquisitionInspect => '检查';

  @override
  String get acquisitionClearInput => '清空';

  @override
  String acquisitionDetectedKind(Object kind, Object count, Object plural) {
    return '$kind · 找到 $count 个 Skill$plural';
  }

  @override
  String get acquisitionPreselectedSkills => '预选 Skill';

  @override
  String get acquisitionPreselectedSkillsNote =>
      '来自命令里的 --skill。下一步会预先勾选它们，你仍可以修改选择。';

  @override
  String get acquisitionPreselectedScopeGlobal => '根据命令里的 -g 预选了全局范围。';

  @override
  String acquisitionPreselectedAgents(Object agents) {
    return '根据命令预选的 Agent：$agents。';
  }

  @override
  String acquisitionUnmatchedSkills(Object names) {
    return '这个来源里没有找到：$names。';
  }

  @override
  String acquisitionIgnoredFlags(Object flags) {
    return '已忽略：$flags。';
  }

  @override
  String get acquisitionErrorWebSourceHasNoSkillsTitle => '这个网址里没有可以安装的 Skills';

  @override
  String get acquisitionErrorWebSourceHasNoSkillsBody =>
      '它可能是一篇介绍文章或项目主页。请回到那个页面，复制上面的安装命令或 GitHub 仓库地址，再粘贴到这里。';

  @override
  String get acquisitionMultipleSkillsHintV2 =>
      '一个仓库可一次安装多个 Skills。这里同样接受粘贴 npx skills add 命令。';

  @override
  String get errorNoSkillsInSource =>
      '这个来源里没有找到 Skill。Skill 是一个包含 SKILL.md 文件的文件夹。';

  @override
  String get errorLocalFolderNotFound => '找不到这个文件夹，请检查路径。';

  @override
  String get errorRepositorySubpathNotFound => '仓库里没有这个子路径。请检查拼写，或者留空以扫描整个仓库。';

  @override
  String get errorGitNetwork => '连不上这个仓库。请检查网络或代理设置后重试。';

  @override
  String get errorGitRefNotFound => '仓库里没有这个分支或标签。';

  @override
  String get errorSourceLocatorHasQuery => '地址里不能带 ? 后面的参数或账号信息，请去掉后重试。';

  @override
  String errorSkillFileCountExceeded(int maximum) {
    return '这个 Skill 的文件超过 $maximum 个。请选择 Skill 自己所在的文件夹，而不是整个项目。';
  }

  @override
  String errorSkillByteSizeExceeded(int maximum) {
    return '这个 Skill 超过 $maximum MB。请选择 Skill 自己所在的文件夹，而不是整个项目。';
  }

  @override
  String get errorSkillMarkdownInvalid =>
      'SKILL.md 缺失，或者开头缺少有效的 name 和 description。';

  @override
  String errorSkillMarkdownInvalidAt(Object path) {
    return '$path 的开头缺少有效的 name 和 description。';
  }

  @override
  String get errorSkillNameUnsupported => 'Skill 名称只能使用小写英文字母、数字和连字符。';

  @override
  String errorSkillNameUnsupportedAt(Object path) {
    return '$path 里的名称不受支持。Skill 名称只能使用小写英文字母、数字和连字符。';
  }

  @override
  String get externalSkillsRescanned => 'Agent 文件夹里的内容有变化，已重新扫描。请检查列表，确认后再接管。';

  @override
  String browserEmptyExistingDescription(int count) {
    return '在 Agent 文件夹里检测到 $count 个已有 Skill，可以直接接管，不用重新安装。';
  }

  @override
  String get browserTakeOverExistingSkills => '接管已有 Skills';

  @override
  String get settingsNavGroupApp => '应用';

  @override
  String get settingsNavGroupSystem => '系统';

  @override
  String get settingsGeneralTitle => '通用';

  @override
  String get settingsGeneralDescription => '界面语言、激活方式和项目目录。改动会立即生效。';

  @override
  String get settingsAppearanceTitle => '外观';

  @override
  String get settingsAppearanceDescription => '主题和 Skill 列表的显示方式。改动会立即生效。';

  @override
  String get settingsAppearanceMode => '主题';

  @override
  String get settingsAppearanceModeDescription => '选择“跟随系统”时，随系统的浅色或深色模式切换。';

  @override
  String get settingsAppearanceModeLight => '浅色';

  @override
  String get settingsAppearanceModeDark => '深色';

  @override
  String get settingsSkillListLayout => 'Skill 列表视图';

  @override
  String get settingsSkillListLayoutDescription => '同时用于“已安装”和“收藏”页面。';

  @override
  String get settingsSkillListLayoutList => '列表';

  @override
  String get settingsSkillListLayoutCards => '卡片';

  @override
  String get settingsAgentsTitle => 'Agents';

  @override
  String get settingsAgentsDescription =>
      'SkillDeck 会把 Skill 激活到这些 Agent 的目录。关闭的 Agent 不会出现在激活目标里。';

  @override
  String get settingsMaintenanceTitle => '维护';

  @override
  String get settingsMaintenanceDescription => '排查问题时使用。每项检查都只在你点击时运行。';

  @override
  String get settingsAboutSectionTitle => '关于 SkillDeck';

  @override
  String get settingsLanguageGroup => '语言';

  @override
  String get settingsActivationGroup => '激活';

  @override
  String get settingsProjectRootsGroup => '项目目录';

  @override
  String get settingsLanguageDescription => '选择“跟随系统”时，使用系统语言。';

  @override
  String get settingsProjectRootsRegistered => '已注册的项目根目录';

  @override
  String agentsShowAll(int count) {
    return '显示全部 $count 个 Agent';
  }

  @override
  String get agentsShowFewer => '收起';

  @override
  String get settingsSkillsGroup => 'Skills';

  @override
  String get settingsEnvironmentGroup => '运行环境';

  @override
  String get settingsValidateNow => '立即校验';

  @override
  String settingsValidationLastRun(String time, String summary) {
    return '上次校验：$time。$summary';
  }

  @override
  String settingsValidationLastFailed(String time) {
    return '上次校验：$time。校验未能完成。';
  }

  @override
  String get settingsUpdatesGroup => '更新';

  @override
  String get settingsLinksGroup => '链接';

  @override
  String settingsAppVersion(String version) {
    return '版本 $version';
  }

  @override
  String get settingsAutomaticUpdates => '自动更新';

  @override
  String get translationServiceGroup => '服务';

  @override
  String get translationOutputGroup => '输出';

  @override
  String get translationEndpointHint => '留空使用默认地址。';

  @override
  String get translationApiKeyHint => '保存在系统凭据存储中，不会写入日志。';

  @override
  String translationStatusConfigured(String provider) {
    return '已配置 · $provider';
  }

  @override
  String get translationStatusNotConfigured => '尚未配置翻译服务';

  @override
  String get translationStatusNotConfiguredDetail => '填写下面的设置并保存后，就可以翻译 Skill。';

  @override
  String get translationTestConnection => '测试连接';

  @override
  String get translationTestRunning => '正在测试连接…';

  @override
  String get translationTestSucceeded => '连接成功';

  @override
  String get translationTestSucceededDetail =>
      '服务已返回一句示例文本的译文，没有发送任何 Skill 内容。';

  @override
  String get translationTestFailed => '连接失败';

  @override
  String get translationTestFailedAuthentication => 'API Key 无效，或没有这个模型的访问权限。';

  @override
  String get translationTestFailedRateLimited => '服务限制了请求频率，请稍后再试。';

  @override
  String get translationTestFailedNetwork => '连不上服务地址，请检查地址和网络。';

  @override
  String get translationTestFailedRejected => '服务拒绝了请求，请检查模型名称和协议。';

  @override
  String get translationTestFailedConfiguration => '请检查服务地址、模型和目标语言。';

  @override
  String get translationTestFailedCredentialRequired =>
      'Anthropic 需要填写 API Key。';

  @override
  String get translationTestFailedUnknown => '连接测试未能完成。';

  @override
  String get translationUnsavedChanges => '有未保存的修改';

  @override
  String get translationRevert => '还原';

  @override
  String get tagsFilterTitle => '标签';

  @override
  String get tagsCreate => '新建标签';

  @override
  String get tagsNamePlaceholder => '标签名称';

  @override
  String get tagsDelete => '删除';

  @override
  String tagsDeleteTitle(Object name) {
    return '删除“$name”？';
  }

  @override
  String tagsDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个 Skill 会失去这个标签。',
    );
    return '${_temp0}Skill 本身不受影响。';
  }

  @override
  String get tagsSearchPlaceholder => '搜索或新建标签';

  @override
  String tagsCreateNamed(Object name) {
    return '新建“$name”';
  }

  @override
  String get tagsAdd => '添加标签';

  @override
  String tagsRemove(Object name) {
    return '移除标签 $name';
  }

  @override
  String get tagsFilterEmpty => '没有同时带有所选标签的 Skill。';

  @override
  String get tagsClearFilter => '清除标签筛选';

  @override
  String get tagsClear => '清除';

  @override
  String get tagsManageHint => '右键标签可改名、改色或删除';

  @override
  String get tagsEdit => '编辑标签';

  @override
  String tagsColorSwatch(int index) {
    return '颜色 $index';
  }

  @override
  String get tagsNoneAssigned => '还没有标签。';

  @override
  String get commandLineVerbActivateProgressive => '激活';

  @override
  String get commandLineVerbActivatePast => '激活';

  @override
  String get commandLineVerbDeactivateProgressive => '停用';

  @override
  String get commandLineVerbDeactivatePast => '停用';

  @override
  String get commandLineVerbFavoriteProgressive => '收藏';

  @override
  String get commandLineVerbFavoritePast => '收藏';

  @override
  String get commandLineVerbUnfavoriteProgressive => '取消收藏';

  @override
  String get commandLineVerbUnfavoritePast => '取消收藏';

  @override
  String get commandLineVerbNoteProgressive => '更新备注';

  @override
  String get commandLineVerbNotePast => '更新备注';

  @override
  String get commandLineVerbTagAddProgressive => '添加标签';

  @override
  String get commandLineVerbTagAddPast => '添加标签';

  @override
  String get commandLineVerbTagRemoveProgressive => '移除标签';

  @override
  String get commandLineVerbTagRemovePast => '移除标签';

  @override
  String get commandLineVerbInstallProgressive => '安装';

  @override
  String get commandLineVerbInstallPast => '安装';

  @override
  String get commandLineVerbUpdateProgressive => '更新';

  @override
  String get commandLineVerbUpdatePast => '更新';

  @override
  String get commandLineVerbRemoveProgressive => '删除';

  @override
  String get commandLineVerbRemovePast => '删除';

  @override
  String get commandLineVerbReplaceSourceProgressive => '更换来源';

  @override
  String get commandLineVerbReplaceSourcePast => '更换来源';

  @override
  String commandLineRunning(String verb, int count) {
    return '命令行正在$verb $count 个 Skill';
  }

  @override
  String get commandLineCancelledSuffix => '，其余已取消';

  @override
  String commandLineSummaryTitle(String verb, int count) {
    return '已$verb $count 个 Skill';
  }

  @override
  String commandLineSummaryReplaceSource(int count) {
    return '已更换 $count 个 Skill 的来源';
  }

  @override
  String commandLineSummaryFailedSuffix(int failed) {
    return '，$failed 个失败';
  }

  @override
  String get commandLineSummaryOrigin => '命令行';

  @override
  String get commandLineSummaryAllSucceeded => '全部成功';

  @override
  String commandLineSummaryDone(int count) {
    return '$count 个已完成';
  }

  @override
  String commandLineSummaryMore(int count) {
    return '+$count';
  }

  @override
  String commandLineAgents(String agents) {
    return '对象：$agents';
  }

  @override
  String commandLineProgress(int done, int total) {
    return '$done/$total';
  }

  @override
  String commandLineProcessing(String slotKey) {
    return '正在处理 $slotKey';
  }

  @override
  String get commandLineCancel => '取消';

  @override
  String get commandLineCancelling => '正在取消…';

  @override
  String commandLineOpenSkill(String slotKey) {
    return '查看 $slotKey';
  }

  @override
  String get commandLineDismiss => '关闭';

  @override
  String get commandLineErrorActivationTargetOccupied =>
      '目标目录里已有同名的非托管文件夹，未做任何改动';

  @override
  String get commandLineErrorOwnershipRepair => '需要在 SkillDeck 里修复 Agent 目录权限';

  @override
  String get commandLineErrorUnknownAgent => '这台设备上没有这个 Agent';

  @override
  String get commandLineErrorGeneric => '操作失败';

  @override
  String get operationWaitingForCommandLine => '等待命令行完成…';

  @override
  String commandLineApprovalRemoveTitle(int count) {
    return '命令行请求删除 $count 个 Skill';
  }

  @override
  String commandLineApprovalDeleteTagTitle(String tag) {
    return '命令行请求删除标签「$tag」';
  }

  @override
  String commandLineApprovalActivatedIn(String agents) {
    return '移除 $agents 中的激活';
  }

  @override
  String get commandLineApprovalNotActivated => '未在任何 Agent 中激活';

  @override
  String get commandLineApprovalUnpublishedDraft => '有未发布的草稿';

  @override
  String get commandLineApprovalSkillGone => '已不在库中';

  @override
  String get commandLineApprovalRemoveWarning =>
      '删除后无法撤销：文件、版本历史、草稿、备注和标签会一起删除。';

  @override
  String commandLineApprovalTagWarning(int count) {
    return '标签会从 $count 个 Skill 上移除，无法撤销。';
  }

  @override
  String get commandLineApprovalStale => '内容已更新，请重新确认。';

  @override
  String get commandLineApprovalDeny => '拒绝';

  @override
  String commandLineApprovalConfirmRemove(int count) {
    return '删除 $count 个 Skill';
  }

  @override
  String get commandLineApprovalConfirmDeleteTag => '删除标签';

  @override
  String commandLineApprovalReplaceSourceTitle(int count) {
    return '命令行请求更换 $count 个 Skill 的来源';
  }

  @override
  String get commandLineApprovalReplaceSourceWarning => '旧来源的版本历史和本地修改将被永久删除。';

  @override
  String get commandLineApprovalConfirmReplaceSource => '更换来源';

  @override
  String get settingsCommandLineTitle => '命令行';

  @override
  String get settingsCommandLineDescription =>
      '让 Agent 通过 skilldeck 命令管理 Skill。';

  @override
  String get commandLineStatusGroup => '状态';

  @override
  String get commandLineStatusTitle => '命令行服务状态';

  @override
  String commandLineStatusDetail(String version) {
    return 'SkillDeck $version';
  }

  @override
  String get commandLineStatusRunningBadge => '运行中';

  @override
  String get commandLineStatusStoppedBadge => '未运行';

  @override
  String get commandLineToolGroup => '命令行工具';

  @override
  String get commandLineToolLocation => 'CLI 位置';

  @override
  String get commandLineToolLocationDetail => 'Agent 通过此路径调用 CLI。';

  @override
  String get commandLineToolNotBundled => '这个版本的 SkillDeck 没有包含命令行工具。';

  @override
  String get commandLineToolFailed => 'SkillDeck 未能更新命令行工具，之前的副本保持不变。';

  @override
  String get commandLinePathTitle => '加入 PATH（可选）';

  @override
  String get commandLinePathDetail => '想在终端里直接输入 skilldeck，把下面这行加到 ~/.zshrc：';

  @override
  String get commandLinePathWindows => 'SkillDeck 安装程序会把这个文件夹加入 PATH。';

  @override
  String get commandLinePathLinkTitle => '在终端中安装';

  @override
  String get commandLinePathLinkDetail =>
      '把 skilldeck 命令添加到 /usr/local/bin，之后在任意终端都能直接使用。可能需要输入一次管理员密码。';

  @override
  String commandLinePathLinkInstalled(String path) {
    return '已安装到 $path。';
  }

  @override
  String get commandLinePathLinkConflict =>
      '/usr/local/bin/skilldeck 已被占用。可手动加入 ~/.zshrc：';

  @override
  String get commandLinePathLinkInstall => '安装';

  @override
  String get commandLinePathLinkRemove => '移除';

  @override
  String get commandLinePathLinkFailed =>
      'SkillDeck 无法修改 /usr/local/bin/skilldeck。';

  @override
  String get commandLineAgentSkillGroup => '安装命令行 Skill';

  @override
  String get commandLineAgentSkillTitle => '命令行 Skill';

  @override
  String get commandLineAgentSkillActive => '已激活';

  @override
  String get commandLineAgentSkillInactive => '已安装，但未激活到任何 Agent。';

  @override
  String get commandLineAgentSkillNotInstalled =>
      '教 Agent 使用 skilldeck。安装后将其激活到本机所有 Agent。';

  @override
  String get commandLineAgentSkillInstall => '安装';

  @override
  String get commandLineAgentSkillInstalling => '正在安装…';

  @override
  String get commandLineAgentSkillOpen => '查看 Skill';

  @override
  String get commandLineAgentSkillInstallFailed => '未能安装 Agent Skill。';

  @override
  String get commandLineSafetyGroup => '安全';

  @override
  String get commandLineSafetyTitle => '删除需要在 App 中确认';

  @override
  String get commandLineSafetyDetail => 'Agent 只能发起删除请求。';

  @override
  String get commandLineSafetyAlwaysOn => '始终开启';

  @override
  String get workspaceTakeoverTargets => '现有目标';

  @override
  String get ownershipRepairFoldersTitle => '需要修复的文件夹';

  @override
  String get customAgentInvalidPathTitle => '路径无效';

  @override
  String get commandLineApprovalSubtitle => '来自 skilldeck 命令行，批准后才会执行。';

  @override
  String get commandLineApprovalRemoveSection => '将删除';

  @override
  String get commandLineApprovalReplaceSection => '将更换';

  @override
  String get projectRootsRegisteredTitle => '已注册';

  @override
  String projectRootsCount(int count) {
    return '已注册 $count 个';
  }

  @override
  String get agentsManageSubtitle => 'SkillDeck 会把 Skill 激活到名单里的 Agent。';

  @override
  String agentsManagedCount(int count) {
    return '共 $count 个 Agent';
  }

  @override
  String get agentsAddBuiltInTitle => '添加内置 Agent';

  @override
  String get agentsAddBuiltInSubtitle => '选择要加入管理名单的 Agent。';

  @override
  String get agentsManagedListTitle => '管理名单';

  @override
  String get customAgentEditorSubtitle => '为没有内置支持的 Agent 配置 Skills 目录。';

  @override
  String get customAgentBasicTitle => '基本信息';

  @override
  String get customAgentSkillsFoldersTitle => 'Skills 目录';

  @override
  String get acquisitionActivationScopeTitle => '激活范围';

  @override
  String workspaceReplaceSourceFound(String name) {
    return '已在新来源中找到 $name。';
  }

  @override
  String get agentsAddAction => '添加';

  @override
  String whatsNewVersionBadge(Object version) {
    return '$version 新功能';
  }

  @override
  String get whatsNewCommandLineTitle => '现已支持命令行操作';

  @override
  String get whatsNewCommandLineBody =>
      '可以让 AI Agents 通过 skilldeck 命令帮你安装、启用和整理 Skills';

  @override
  String get whatsNewOpenCommandLineSettings => '进入命令行设置';

  @override
  String get whatsNewDarkModeTitle => '现已支持深色模式';

  @override
  String get whatsNewDarkModeBody =>
      '可以在设置 › 外观中选择浅色或深色，也可以让 SkillDeck 跟随系统自动切换';

  @override
  String get whatsNewOpenAppearanceSettings => '进入外观设置';

  @override
  String get whatsNewDismiss => '知道了';
}
