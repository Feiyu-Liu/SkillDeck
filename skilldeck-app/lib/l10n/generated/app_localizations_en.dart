// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SkillDeck';

  @override
  String get navWorkspace => 'WORKSPACE';

  @override
  String get navMaintenance => 'MAINTENANCE';

  @override
  String get navInstalled => 'Installed';

  @override
  String get navWrite => 'Write';

  @override
  String get navTest => 'Test';

  @override
  String get navUpdates => 'Updates';

  @override
  String get navFavorites => 'Favorites';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get trayShowWindow => 'Show Main Window';

  @override
  String get trayQuit => 'Quit SkillDeck';

  @override
  String get commonDone => 'Done';

  @override
  String get commonBack => 'Back';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonRefreshAndReview => 'Refresh and review';

  @override
  String get commonGlobal => 'Global';

  @override
  String get commonProject => 'Project';

  @override
  String get activationUniversalAgents => 'Universal Agents';

  @override
  String get activationUnknownAgent => 'Unknown Agent';

  @override
  String get activationInactive => 'Inactive';

  @override
  String get agentsManage => 'Manage Agents';

  @override
  String get agentsBuiltIn => 'Built-in Agents';

  @override
  String get agentsDetected => 'Detected';

  @override
  String get agentsEmpty => 'No Agents to display.';

  @override
  String get agentsRemoveTitle => 'Remove Agent from management?';

  @override
  String get agentsRemoveAction => 'Remove';

  @override
  String get agentsRemoveDescription =>
      'This removes the Agent from the app\'s management list. Existing Skill files and activations remain accessible to the Agent.';

  @override
  String get agentsOutsideRoster => 'Outside the management list';

  @override
  String get activationAllAgentsToggle => 'Select all Agents';

  @override
  String get operationPreparing => 'Preparing…';

  @override
  String get operationInspecting => 'Inspecting source…';

  @override
  String get operationWaitingForLock => 'Waiting for the repository…';

  @override
  String get operationPlanning => 'Planning changes…';

  @override
  String get operationApplying => 'Applying changes…';

  @override
  String get operationRecovering => 'Recovering repository state…';

  @override
  String get operationRollingBack => 'Restoring the previous state…';

  @override
  String get operationSucceeded => 'Operation completed.';

  @override
  String get operationFailed => 'Operation failed.';

  @override
  String get operationCancelled => 'Operation cancelled.';

  @override
  String operationProgress(Object completed, Object total) {
    return '$completed of $total';
  }

  @override
  String get warningInternalSymlinkSkipped =>
      'An internal symbolic link was skipped.';

  @override
  String get warningSourceEntrySkipped =>
      'An unsupported source entry was skipped.';

  @override
  String get warningNoActivationTarget =>
      'No compatible activation target was found.';

  @override
  String get warningProjectSymlinkPortability =>
      'This project activation uses a symbolic link that may not be portable.';

  @override
  String get warningDuplicateExposure =>
      'This skill is already exposed at an equivalent location.';

  @override
  String get warningSharedActivationLocation =>
      'Several Agent Skills folders are one folder, so this Skill was activated there once for all of them.';

  @override
  String get warningAgentUndetected =>
      'A selected agent was not detected on this device.';

  @override
  String get warningActivationTargetSkipped =>
      'An unavailable activation target was skipped.';

  @override
  String get warningRecoveryCleanupDeferred =>
      'Some temporary recovery files could not be cleaned up. Repository data is unchanged.';

  @override
  String get commonSectionBreadcrumb => 'Workspace';

  @override
  String get browserRepositoryUnavailable => 'Repository unavailable';

  @override
  String get browserRepositoryUnavailableMessage =>
      'Repository could not be opened.';

  @override
  String get browserDesktopRequired => 'Desktop required';

  @override
  String get browserDesktopRequiredMessage =>
      'SkillDeck currently supports desktop platforms.';

  @override
  String get browserRefreshRepository => 'Refresh repository';

  @override
  String get browserBreadcrumb => 'Workspace / Installed';

  @override
  String get browserInstalled => 'Installed';

  @override
  String browserNoMatches(Object query) {
    return 'No skills match \"$query\".';
  }

  @override
  String get browserFavoritesEmpty => 'No favorite skills yet.';

  @override
  String get browserInactive => 'Inactive';

  @override
  String browserActiveRatio(Object count, Object total) {
    return '$count/$total active';
  }

  @override
  String get browserAddSkills => 'Add skills';

  @override
  String get browserAddFromSource => 'Add from source';

  @override
  String get browserDiscoverExistingSkills => 'Discover existing Skills';

  @override
  String browserUnmanagedSkillsFound(Object count) {
    return '$count unmanaged Skills found';
  }

  @override
  String get browserAllAgents => 'All Agents';

  @override
  String get browserAllScopes => 'All scopes';

  @override
  String get browserSearchSkills => 'Search skills';

  @override
  String get browserNoSkillsYet => 'No skills yet';

  @override
  String get browserEmptyDescription =>
      'Install your first skill from a local folder, a Git repo, or a URL.';

  @override
  String browserAgentFilter(Object number) {
    return 'Agent filter $number';
  }

  @override
  String get browserScopeSelector => 'Scope filter';

  @override
  String get browserSort => 'Sort';

  @override
  String get browserSortNameAscending => 'Name A-Z';

  @override
  String get browserSortNameDescending => 'Name Z-A';

  @override
  String get browserSortRecentlyAdded => 'Recently added';

  @override
  String get browserSortOldestAdded => 'Oldest added';

  @override
  String get workspaceBackToSkills => 'Back to skills';

  @override
  String get workspaceBreadcrumb => 'Installed';

  @override
  String get workspaceCheckForUpdate => 'Check for update';

  @override
  String get workspaceUpdateAvailableAction => 'Update available';

  @override
  String get workspaceUpdateNow => 'Update now';

  @override
  String get workspaceRemoveSkill => 'Delete skill';

  @override
  String get workspaceFavorite => 'Favorite';

  @override
  String get workspaceUnfavorite => 'Remove from favorites';

  @override
  String get workspaceTranslate => 'Translate';

  @override
  String get workspaceTranslationComingSoon =>
      'Translation arrives in a later version';

  @override
  String get workspaceVersion => 'VERSION';

  @override
  String get workspaceSource => 'SOURCE';

  @override
  String get workspaceReplaceSource => 'Replace source';

  @override
  String get workspaceReplaceSourceTitle => 'Replace Skill source';

  @override
  String get workspaceReplaceSourceDescription =>
      'The new source must contain the same Skill. Existing activations will be preserved.';

  @override
  String get workspaceReplaceSourceConfirm => 'Replace source';

  @override
  String get workspaceReplaceSourceSuccess => 'Skill source replaced.';

  @override
  String get workspaceReplaceSourceStepReplace => 'Replace';

  @override
  String get workspaceReplaceSourceMismatch => 'A different Skill';

  @override
  String workspaceReplaceSourceNoMatch(Object name) {
    return 'This source does not contain $name.';
  }

  @override
  String get workspaceReplaceSourceCurrent => 'Current source';

  @override
  String get workspaceReplaceSourceNew => 'New source';

  @override
  String get workspaceReplacing => 'Replacing source…';

  @override
  String get sourceKindLocal => 'Local';

  @override
  String get sourceKindGit => 'Git';

  @override
  String get sourceKindUrl => 'URL';

  @override
  String get workspacePreview => 'Preview';

  @override
  String get workspaceSettings => 'Settings';

  @override
  String get workspaceSkillNotFound => 'Skill not found';

  @override
  String get workspaceDocumentUnavailable =>
      'The selected Markdown file could not be read.';

  @override
  String workspaceDocumentUnavailableNamed(String fileName) {
    return '$fileName could not be read.';
  }

  @override
  String get workspaceDocumentBrowserTitle => 'Markdown files';

  @override
  String get workspaceDocumentListUnavailable =>
      'The Markdown file list could not be loaded.';

  @override
  String get workspaceDocumentListEmpty => 'No Markdown files found.';

  @override
  String workspaceDocumentSelectorTooltip(String fileName) {
    return 'Choose a Markdown file. Current file: $fileName';
  }

  @override
  String get workspaceActivations => 'ACTIVATIONS';

  @override
  String get workspaceActivateTitle => 'Activate skill';

  @override
  String get workspaceActivateDescription =>
      'Choose the Agents that should use this Skill.';

  @override
  String get workspaceActivateScope => 'ACTIVATION SCOPE';

  @override
  String get workspaceActivateTargets => 'AGENTS';

  @override
  String get workspaceActivateNoTargets =>
      'No Agents are available for this scope.';

  @override
  String get workspaceActivateAlreadyActive => 'Already active';

  @override
  String get workspaceActivateUndetectedWarning =>
      'Not detected; explicit activation is still available.';

  @override
  String get workspaceActivateSelectProject => 'Select a Project Root';

  @override
  String get workspaceTakeoverTitle => 'Replace the existing target?';

  @override
  String workspaceTakeoverDescription(String agentName) {
    return '$agentName already has an item at this Skill path. Review it before replacing it with the managed copy.';
  }

  @override
  String workspaceInstallTakeoverDescription(String agentName) {
    return '$agentName already has an item at this Skill path. Review it before installing and replacing the existing item.';
  }

  @override
  String get workspaceTakeoverPath => 'Path';

  @override
  String get workspaceTakeoverType => 'Existing item';

  @override
  String get workspaceTakeoverContent => 'Content';

  @override
  String get workspaceTakeoverSkillDirectory => 'Skill folder';

  @override
  String get workspaceTakeoverSkillSymbolicLink => 'Skill symbolic link';

  @override
  String get workspaceTakeoverFile => 'File';

  @override
  String get workspaceTakeoverInvalidDirectory =>
      'Folder without a valid SKILL.md';

  @override
  String get workspaceTakeoverBrokenSymbolicLink => 'Broken symbolic link';

  @override
  String get workspaceTakeoverContentDifferent =>
      'Different from the selected Skill';

  @override
  String get workspaceTakeoverContentUnknown =>
      'Could not be compared with the selected Skill';

  @override
  String get workspaceTakeoverOpenLocation => 'Open location';

  @override
  String get workspaceTakeoverConfirm => 'Replace and activate';

  @override
  String get workspaceInstallTakeoverConfirm => 'Replace and install';

  @override
  String get workspaceTakeoverWarning =>
      'The existing item will be replaced. If the operation fails, SkillDeck restores it from recovery data.';

  @override
  String get notificationOpenLocationFailed =>
      'The file location could not be opened.';

  @override
  String get workspaceNotes => 'NOTES';

  @override
  String get workspaceAddNote => 'Add a note about this skill…';

  @override
  String get workspaceNotDetected => 'Not detected on this device';

  @override
  String get workspaceGlobalScope => 'Global scope';

  @override
  String get workspaceNoActivations => 'No active Agents.';

  @override
  String get workspaceDeactivate => 'Deactivate';

  @override
  String get workspaceActivate => 'Activate';

  @override
  String get workspaceActive => 'Active';

  @override
  String get workspaceInactive => 'Inactive';

  @override
  String get workspaceDuplicateActivationTitle =>
      'Possible duplicate activation';

  @override
  String get workspaceDuplicateActivationMessage =>
      'This Skill is already active globally for this Agent. Activating it in this project may create a duplicate Skill.';

  @override
  String get workspaceDuplicateActivationContinue => 'Continue activating';

  @override
  String get workspaceDuplicateActivationDontAskAgain =>
      'Don\'t show this again';

  @override
  String get workspaceRemoveTitle => 'Delete skill?';

  @override
  String get workspaceRemoveMessage =>
      'This deletes the Repository Copy and clears its Agent activations.';

  @override
  String workspaceRemoveNamedTitle(Object name) {
    return 'Delete $name?';
  }

  @override
  String get workspaceRemoveDetailedMessage =>
      'This permanently deletes the Repository Copy and clears all Agent activations. This can’t be undone.';

  @override
  String get workspaceRemoveCleared => 'WILL BE CLEARED';

  @override
  String workspaceRemoveSlot(Object name) {
    return 'Skill Slot — $name';
  }

  @override
  String workspaceRemoveActivationCount(Object count) {
    return '$count Activation(s)';
  }

  @override
  String get workspaceRemoveAction => 'Delete skill';

  @override
  String get workspaceRemoveFailed => 'The skill could not be deleted.';

  @override
  String get workspaceRemoving => 'Deleting…';

  @override
  String get workspaceRemoveConfirmAgain => 'Confirm again';

  @override
  String workspaceRemoveRevision(Object revision) {
    return 'Confirmed at revision r$revision. If the repository changed, you’ll review again.';
  }

  @override
  String workspaceRemoveStale(Object revision) {
    return 'The repository changed. Review the refreshed skill at revision r$revision, then confirm again.';
  }

  @override
  String get updatesBreadcrumb => 'Workspace';

  @override
  String get updatesTitle => 'Updates';

  @override
  String get updatesCheckAgain => 'Check again';

  @override
  String get updatesUpdateAll => 'Update all';

  @override
  String get updatesEmpty => 'All skills are up to date.';

  @override
  String get updatesCurrent => 'Current';

  @override
  String get updatesAvailable => 'Update available';

  @override
  String get updatesUnavailable => 'Source unavailable';

  @override
  String get updatesTimedOut => 'Git update check timed out';

  @override
  String get updatesUnsupported => 'Updates unsupported for this source';

  @override
  String get updatesUpdate => 'Update';

  @override
  String get updatesResolutionRequired => 'Update requires resolution';

  @override
  String get updatesCandidateResolutionRequired =>
      'Update candidate needs resolution';

  @override
  String get updatesAbandonCandidate => 'Abandon candidate';

  @override
  String get updatesNotChecked => 'Not checked';

  @override
  String get updatesChecking => 'Checking…';

  @override
  String get updatesCheckFailed => 'The check could not be completed.';

  @override
  String get updatesCheckOne => 'Check';

  @override
  String updatesCheckProgress(Object completed, Object total) {
    return 'Checked $completed of $total';
  }

  @override
  String updatesUpdatingSkill(String slotKey) {
    return 'Updating $slotKey';
  }

  @override
  String updatesUpdatingSkills(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Updating $count Skills',
      one: 'Updating 1 Skill',
    );
    return '$_temp0';
  }

  @override
  String updatesUpdatingDetail(String slotKey, String phase) {
    return '$slotKey · $phase';
  }

  @override
  String get updatesFetchingSource => 'Fetching the new version…';

  @override
  String get updatesIntegrityRecovery =>
      'Recovery required before this skill can be changed.';

  @override
  String get settingsBreadcrumb => 'Workspace';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsValidateWorkspace => 'Skills Validation';

  @override
  String get settingsValidateWorkspaceRunning => 'Validating Skills…';

  @override
  String get settingsValidateWorkspaceDone => 'Workspace validation completed.';

  @override
  String get settingsValidateWorkspaceDescription =>
      'Check every managed Skill for missing or changed files.';

  @override
  String get settingsAppUpdateTitle => 'Check for updates';

  @override
  String settingsAppUpdateCurrentVersion(String version) {
    return 'Current version: $version';
  }

  @override
  String get settingsAppUpdateVersionUnknown => 'Unavailable';

  @override
  String get settingsAppUpdateUnconfigured =>
      'Automatic updates are not configured in this build.';

  @override
  String get settingsAppUpdateInvalid =>
      'This build has an invalid update configuration.';

  @override
  String get settingsAppUpdateReady => 'Automatic update checks are enabled.';

  @override
  String get settingsAppUpdateChecking => 'Checking for updates';

  @override
  String settingsAppUpdateAvailable(String version) {
    return 'SkillDeck $version is available.';
  }

  @override
  String get settingsAppUpdateAvailableGeneric =>
      'A new SkillDeck version is available.';

  @override
  String get settingsAppUpdateDownloaded =>
      'The update has downloaded. Open the updater to view progress and confirm installation.';

  @override
  String get settingsAppUpdateFailed =>
      'The update operation failed. Try checking again.';

  @override
  String get settingsAppUpdateBusy =>
      'Finish the active SkillDeck operation before restarting.';

  @override
  String get settingsAppUpdateCheck => 'Check for updates';

  @override
  String get settingsAppUpdateProcessing =>
      'The updater is busy. Please try again shortly.';

  @override
  String get sidebarAppUpdateChecking => 'Checking…';

  @override
  String get sidebarAppUpdateAvailable => 'Update available';

  @override
  String get sidebarAppUpdateDownloaded => 'View update';

  @override
  String get sidebarAppUpdateFailed => 'Retry update';

  @override
  String get settingsAboutTitle => 'SkillDeck';

  @override
  String get settingsOfficialWebsite => 'Official Website';

  @override
  String get settingsChangelog => 'Changelog';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsTermsOfService => 'Terms of Service';

  @override
  String get settingsOpenSourceLicenses => 'Open Source Licenses';

  @override
  String get openSourceLicensesTitle => 'Open source licenses';

  @override
  String get openSourceLicensesSubtitle =>
      'SkillDeck is built with these components. Choose one to read its license.';

  @override
  String openSourceLicensesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count licenses',
      one: '1 license',
    );
    return '$_temp0';
  }

  @override
  String get openSourceLicensesLoadFailed =>
      'The license texts could not be loaded.';

  @override
  String get settingsValidateWorkspaceFailed => 'Workspace validation failed.';

  @override
  String settingsValidateWorkspaceSummary(
    Object checked,
    Object drifted,
    Object failed,
    Object repaired,
  ) {
    return 'Checked $checked skills, repaired $repaired artifacts, found $drifted external changes, and failed $failed skills.';
  }

  @override
  String get settingsEnvironmentTitle => 'Environment check';

  @override
  String get settingsEnvironmentDescription =>
      'Check the external tools SkillDeck relies on. Checks run only when you start them.';

  @override
  String get settingsEnvironmentRecheck => 'Recheck';

  @override
  String get settingsEnvironmentOpenInstallPrompt => 'Open install prompt';

  @override
  String get settingsEnvironmentCheckGit => 'Git command line';

  @override
  String get settingsEnvironmentStatusNotChecked => 'Not checked yet';

  @override
  String get settingsEnvironmentStatusChecking => 'Checking…';

  @override
  String get settingsEnvironmentGitAvailable => 'Git is available.';

  @override
  String get settingsEnvironmentGitNotInstalled =>
      'Git was not found on this device. Public HTTPS repositories still install; SSH and private repositories need Git.';

  @override
  String get settingsEnvironmentGitDeveloperToolsRequired =>
      'The macOS Command Line Developer Tools are required. Choose Install in the system dialog, then recheck.';

  @override
  String get settingsEnvironmentGitDeveloperToolsInstalling =>
      'The Command Line Developer Tools are installing. Recheck once the install finishes.';

  @override
  String get settingsEnvironmentGitProbeFailed =>
      'The Git check did not complete.';

  @override
  String get settingsInterfaceLanguage => 'Interface language';

  @override
  String get settingsFollowSystem => 'Follow System';

  @override
  String get settingsChinese => '中文';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsCustomAgents => 'Custom Agents';

  @override
  String get settingsCustomAgentsDescription =>
      'Manage additional Agent skill locations on this device.';

  @override
  String get settingsAgentsManagementTitle => 'Agent Management';

  @override
  String get settingsAgentsManagementDescription =>
      'Manage built-in Agents and configure custom Agents on this device.';

  @override
  String get settingsAddAgent => 'Add Agent';

  @override
  String get settingsEditAgent => 'Edit Agent';

  @override
  String get settingsDeleteAgent => 'Remove Agent';

  @override
  String get settingsSaveAgent => 'Save Agent';

  @override
  String get settingsAgentName => 'Agent name';

  @override
  String get settingsAgentIcon => 'Icon';

  @override
  String get settingsAgentPathGlobal => 'Global Skills directory';

  @override
  String get settingsAgentPathProject => 'Project Skills relative directory';

  @override
  String get settingsAgentChooseGlobalDirectory =>
      'Choose global Skills directory';

  @override
  String get settingsAgentAdvancedShow => 'Show advanced settings';

  @override
  String get settingsAgentAdvancedHide => 'Hide advanced settings';

  @override
  String get settingsAgentDiscoveryPathsGlobal =>
      'Additional global discovery directories';

  @override
  String get settingsAgentDiscoveryPathsProject =>
      'Additional project discovery directories';

  @override
  String get settingsAgentDiscoveryPathsHint =>
      'One path per line. These paths are only scanned to discover and migrate existing Skills.';

  @override
  String get settingsAgentNoCustom => 'No custom Agents yet.';

  @override
  String get settingsAgentDeleteConfirm =>
      'Remove this Agent configuration? Existing files and activation links will not be deleted.';

  @override
  String get settingsAgentInvalidPath =>
      'Configure this device with an absolute global path or a safe relative project path. Additional discovery paths require a directory for the same scope.';

  @override
  String get settingsAgentBusy =>
      'Agent configuration is busy. Try again when the current operation finishes.';

  @override
  String get settingsAgentReloadFailed =>
      'Agent configuration could not be applied. The previous configuration remains active.';

  @override
  String get translationSettingsTitle => 'Translation';

  @override
  String get translationSettingsDescription =>
      'Configure the single active Provider profile. Skill content is sent only after you confirm each translation.';

  @override
  String get translationProvider => 'Provider';

  @override
  String get translationProviderOpenAI => 'OpenAI compatible';

  @override
  String get translationProviderAnthropic => 'Anthropic';

  @override
  String get translationEndpoint => 'Endpoint';

  @override
  String get translationModel => 'Model';

  @override
  String get translationTargetLanguage => 'Target language';

  @override
  String get translationApiKey => 'API key';

  @override
  String get translationApiKeyStored =>
      'Stored securely — enter a value only to replace it';

  @override
  String get translationApiKeyOptional =>
      'Optional for local OpenAI-compatible endpoints';

  @override
  String get translationAdvancedShow => 'Show advanced settings';

  @override
  String get translationAdvancedHide => 'Hide advanced settings';

  @override
  String get translationProtocol => 'Protocol';

  @override
  String get translationCharacterBudget => 'Character budget';

  @override
  String get translationConcurrency => 'Concurrency';

  @override
  String get translationMaxOutputTokens => 'Max output tokens';

  @override
  String get translationOptional => 'Optional';

  @override
  String get translationReasoning => 'Reasoning';

  @override
  String get translationReasoningDescription =>
      'Off by default so reasoning cannot consume translation output budget.';

  @override
  String get translationSave => 'Save translation settings';

  @override
  String get translationSettingsError =>
      'Translation settings could not be saved. Check the values and try again.';

  @override
  String get translationAction => 'Translate';

  @override
  String get translationCancel => 'Cancel translation';

  @override
  String get translationConfirmTitle => 'Translate this Skill?';

  @override
  String get translationConfirmMessage =>
      'Skill text will be sent to this service.';

  @override
  String get translationConfirmProvider => 'Provider';

  @override
  String get translationConfirmEndpoint => 'Endpoint host';

  @override
  String get translationConfirmTarget => 'Target language';

  @override
  String get translationScopeFullDocument => 'Full Skill';

  @override
  String get translationScopeDescription => 'Description only';

  @override
  String get translationDescriptionUnavailable =>
      'No translatable SKILL.md description is available.';

  @override
  String get translationShowCached => 'Show cached';

  @override
  String get translationConfigureFirst =>
      'Configure a Translation Provider in Settings first.';

  @override
  String get translationProviderOpenAIShort => 'OpenAI compatible';

  @override
  String get translationProviderAnthropicShort => 'Anthropic';

  @override
  String get translationShowOriginal => 'Show original';

  @override
  String get translationDeleteCache => 'Delete cache';

  @override
  String get projectRootsTitle => 'Manage Project Directories';

  @override
  String get projectRootsDescription =>
      'Registered roots are available for project-scoped activations.';

  @override
  String get projectRootsEmpty => 'No Project Roots registered.';

  @override
  String get projectRootsAdd => 'Add Project Root';

  @override
  String get projectRootsManage => 'Manage';

  @override
  String get projectRootsRemove => 'Remove Project Root';

  @override
  String get projectRootsError => 'The Project Root operation failed.';

  @override
  String get externalSkillsTitle => 'Discover existing Skills';

  @override
  String get externalSkillsDescription =>
      'Other tools installed these Skills in Agent folders. Take them over to update and activate them in SkillDeck.';

  @override
  String get externalSkillsScanning => 'Scanning known Agent locations…';

  @override
  String get externalSkillsEmpty => 'No unmanaged Skills found';

  @override
  String get externalSkillsEmptyDescription =>
      'All valid Skills in known Agent locations are already managed.';

  @override
  String get externalSkillsRescan => 'Scan again';

  @override
  String externalSkillsAdoptCount(Object count) {
    return 'Take over $count';
  }

  @override
  String get externalSkillsAdopting => 'Adopting Skills';

  @override
  String externalSkillsCompletedCount(Object completed, Object total) {
    return '$completed of $total Skills completed.';
  }

  @override
  String get externalSkillsSuccess => 'Skills adopted';

  @override
  String get externalSkillsCancelled => 'Adoption cancelled';

  @override
  String get externalSkillsPartial => 'Adoption partially completed';

  @override
  String get externalSkillsScanFailed => 'Scan failed';

  @override
  String get externalSkillsAdoptionFailed => 'Adoption failed';

  @override
  String externalSkillsFailedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Skills could not be taken over',
      one: '1 Skill could not be taken over',
    );
    return '$_temp0';
  }

  @override
  String externalSkillsFoundTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count existing Skills',
      one: '1 existing Skill',
    );
    return 'Found $_temp0';
  }

  @override
  String get externalSkillsSummaryTotal => 'Found';

  @override
  String get externalSkillsSummaryReady => 'Ready to take over';

  @override
  String get externalSkillsSummaryConflicts => 'Need a version';

  @override
  String externalSkillsSummaryCount(int count) {
    return '$count';
  }

  @override
  String get externalSkillsDecideTitle => 'Resolve conflicts';

  @override
  String get externalSkillsDecideSubtitle =>
      'A Skill with the same name differs between Agents';

  @override
  String get externalSkillsChooseVersion => 'Choose version';

  @override
  String get externalSkillsVersionMenuTitle => 'Keep the version from';

  @override
  String get externalSkillsOpenFolder => 'Show in Finder';

  @override
  String externalSkillsRestTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more can be taken over directly',
      one: '1 more can be taken over directly',
    );
    return '$_temp0';
  }

  @override
  String externalSkillsReadyTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count can be taken over directly',
      one: '1 can be taken over directly',
    );
    return '$_temp0';
  }

  @override
  String externalSkillsNamesMore(String names) {
    return '$names, and more';
  }

  @override
  String get externalSkillsNameSeparator => ', ';

  @override
  String get externalSkillsViewAll => 'View all';

  @override
  String get externalSkillsChooseIndividually => 'Choose individually';

  @override
  String externalSkillsAdoptAll(int count) {
    return 'Take over all $count';
  }

  @override
  String get externalSkillsSelectAll => 'Select all';

  @override
  String get externalSkillsAgentsColumn => 'Found in';

  @override
  String externalSkillsConflictCopies(int count) {
    return '$count copies differ';
  }

  @override
  String get externalSkillsSharedFolder => 'Shared folder';

  @override
  String externalSkillsSharedBy(int count) {
    return 'Used by $count Agents';
  }

  @override
  String get externalSkillsVerifying => 'Checking for changes…';

  @override
  String get errorSourceUnavailable => 'The source is unavailable.';

  @override
  String get errorAuthenticationRequired =>
      'The repository doesn\'t exist or is private. Check the address; a private repository needs Git installed and signed in.';

  @override
  String get errorGitUnavailable =>
      'Git is unavailable on this device. Public HTTPS repositories install without Git; SSH and private repositories need it.';

  @override
  String get errorGitFailed =>
      'The Git operation failed. Check the source address and try again.';

  @override
  String get errorGitFileCountExceeded =>
      'The repository exceeds the scan limit. Specify a repository subpath and try again.';

  @override
  String get errorDeveloperToolsRequired =>
      'Git needs the macOS Command Line Developer Tools. Open Settings › Environment check to finish setup.';

  @override
  String get errorTransportRejected =>
      'The source address was rejected for safety.';

  @override
  String get errorArchiveInvalid => 'The downloaded archive is invalid.';

  @override
  String get errorDigestMismatch =>
      'The source content did not pass integrity verification. Check the source and try again.';

  @override
  String get errorSkillNotFound => 'The skill no longer exists.';

  @override
  String get errorStaleSnapshot =>
      'The repository changed. Refresh and review the action again.';

  @override
  String get errorInvalidSkill =>
      'The source contains an invalid or unsupported skill.';

  @override
  String get errorSkillContentLimitExceeded =>
      'The skill content exceeds the supported file-count or size limit.';

  @override
  String get errorInvalidSource => 'This source is unsupported.';

  @override
  String get errorDuplicateSkill =>
      'The skill conflicts with an installed Skill Slot.';

  @override
  String get errorDuplicateSkillsWithinSource =>
      'This source contains multiple skills with the same name. Specify a particular subpath.';

  @override
  String get errorSourceReplacementRequired =>
      'A managed Skill already uses this Skill Slot. Replace its source to continue.';

  @override
  String get errorExternalSkillConflict =>
      'An unmanaged skill already occupies this activation target. Refresh and review it before continuing.';

  @override
  String get errorActivation =>
      'The activation target is unavailable or unsupported.';

  @override
  String get errorAdoptionTargetOccupied =>
      'Something else is already in this Skill\'s folder. Move it away, then try again.';

  @override
  String errorAdoptionTargetOccupiedFile(Object path) {
    return 'A file is in the way of this Skill\'s folder. Move it elsewhere, then try again: $path';
  }

  @override
  String errorAdoptionTargetOccupiedInvalidSkill(Object path) {
    return 'This Skill\'s folder holds a SKILL.md that is not a valid Skill. Fix or move that folder, then try again: $path';
  }

  @override
  String errorAdoptionTargetOccupiedDirectoryWithContent(Object path) {
    return 'This Skill\'s folder already holds other files. Move that folder elsewhere, then try again: $path';
  }

  @override
  String errorAdoptionTargetOccupiedOtherSkill(Object path) {
    return 'This Skill\'s folder holds a different Skill. Rename or move one of them, then try again: $path';
  }

  @override
  String errorAdoptionTargetOccupiedSameSlotSkill(Object path) {
    return 'This Skill\'s folder holds another copy of it that was not part of the review. Move that copy elsewhere, then try again: $path';
  }

  @override
  String errorAdoptionTargetOccupiedLink(Object path) {
    return 'This Skill\'s folder is a link to something else. Remove the link, then try again: $path';
  }

  @override
  String get errorProjectRoot => 'The selected Project Root was removed.';

  @override
  String get errorInvalidProjectRoot =>
      'The selected project directory is invalid.';

  @override
  String get errorProjectRootConflict =>
      'The project directory conflicts with an existing registration.';

  @override
  String get errorAgent => 'The selected Agent is unavailable.';

  @override
  String get errorDuplicateAgentId =>
      'An Agent with this identifier already exists.';

  @override
  String get errorPersonalTagNotFound => 'The personal tag no longer exists.';

  @override
  String get errorDuplicatePersonalTag =>
      'A personal tag with this name already exists.';

  @override
  String get errorRepositoryBusy =>
      'Another operation is using the repository.';

  @override
  String get errorOperationCancelled => 'The operation was cancelled.';

  @override
  String get errorRepositoryState =>
      'The repository state needs recovery or is unsupported.';

  @override
  String get errorControlPlaneCorrupt =>
      'The workspace control data is damaged. Changes are blocked to protect your skills.';

  @override
  String get errorUnsupportedWorkspaceVersion =>
      'This workspace version is not supported by this version of SkillDeck. Update SkillDeck and try again.';

  @override
  String get errorWorkspaceMaintenanceFailed =>
      'Workspace maintenance failed. Changes are blocked until recovery completes.';

  @override
  String get errorMigrationFailed =>
      'The workspace could not be upgraded safely. No further changes were made.';

  @override
  String get errorRevisionStoreCorrupt =>
      'The skill revision store is damaged. Replace the source or delete the affected skill to recover safely.';

  @override
  String get errorDirtyDraftResolutionRequired =>
      'This skill has unpublished changes. Publish or discard them before continuing.';

  @override
  String get errorUpdateCandidateResolutionRequired =>
      'This skill has an unresolved update candidate. Resolve or abandon it before continuing.';

  @override
  String get errorNameChangeNotAllowed =>
      'A managed skill cannot change its declared name. Restore the original name before continuing.';

  @override
  String get errorFinalizationRecoveryFailed =>
      'The changes were committed, but recovery could not finish. Retry recovery before making more changes.';

  @override
  String get workspaceIntegrityRecoveryTitle => 'Skill recovery required';

  @override
  String get workspaceIntegrityRecoveryMessage =>
      'This skill\'s revision data could not be verified. Updates, activations, favorites, and notes are disabled. Replace the source or delete the skill to recover safely.';

  @override
  String get workspaceIntegrityValidating => 'Checking';

  @override
  String get workspaceIntegrityDriftPending => 'Changed externally';

  @override
  String get workspaceIntegrityRepairFailed => 'Repair failed';

  @override
  String get workspaceIntegrityStoreCorrupt => 'Recovery required';

  @override
  String get errorRollback => 'The operation could not be restored safely.';

  @override
  String get errorIo => 'A local file operation failed.';

  @override
  String get errorUnknown => 'The operation failed.';

  @override
  String get acquisitionTitle => 'Add a skill';

  @override
  String get acquisitionSubtitle =>
      'Install from a local folder, a Git repo, or a URL.';

  @override
  String get acquisitionSource => 'Source';

  @override
  String get acquisitionSkillsFound => 'Skills found';

  @override
  String get acquisitionSelectAllSkills => 'Select all';

  @override
  String get acquisitionNoValidSkills => 'No valid skills found.';

  @override
  String get acquisitionScope => 'SCOPE';

  @override
  String get acquisitionAgents => 'Agents';

  @override
  String get acquisitionGlobalDescription =>
      'Activates for all projects on this device.';

  @override
  String get acquisitionProjectDescription =>
      'Activates for a specific registered Project Root.';

  @override
  String get acquisitionRegisterProjectRoot =>
      'Register a Project Root before project activation.';

  @override
  String get acquisitionManageProjectRoots => 'Manage Project Roots';

  @override
  String get acquisitionStoreOnly => 'Store only';

  @override
  String acquisitionDetectedCount(Object count) {
    return '/ $count detected';
  }

  @override
  String get acquisitionAddAgent => 'Add Agent';

  @override
  String get acquisitionInstalling => 'Installing skills…';

  @override
  String get acquisitionPreparing => 'Preparing source…';

  @override
  String get acquisitionInspecting => 'Inspecting source…';

  @override
  String get acquisitionWaitingForRepository => 'Waiting for repository…';

  @override
  String get acquisitionPlanning => 'Planning changes…';

  @override
  String get acquisitionApplying => 'Applying changes…';

  @override
  String get acquisitionRestoring => 'Restoring previous state…';

  @override
  String get acquisitionFinishing => 'Finishing…';

  @override
  String get acquisitionErrorResolve =>
      'Enter a supported local, Git, or HTTPS source.';

  @override
  String get acquisitionErrorInspect => 'The source could not be inspected.';

  @override
  String get acquisitionErrorInstall => 'The skills could not be installed.';

  @override
  String get acquisitionGoToEnvironmentSettings => 'Go to Settings';

  @override
  String get acquisitionErrorRefresh =>
      'The skills were installed, but the repository could not be refreshed.';

  @override
  String get acquisitionSelect => 'Select';

  @override
  String get acquisitionActivate => 'Activate';

  @override
  String get acquisitionLocalFolder => 'Local Folder';

  @override
  String get acquisitionLocalFolderDescription =>
      'A folder containing one or more skills.';

  @override
  String get acquisitionGitRepository => 'Git Repository';

  @override
  String get acquisitionGitRepositoryDescription =>
      'GitHub, GitLab, or any Git remote.';

  @override
  String get acquisitionWebSourceUrl => 'Web Source URL';

  @override
  String get acquisitionWebSourceUrlDescription =>
      'A well-known HTTPS skills endpoint.';

  @override
  String get acquisitionFolderPath => 'FOLDER PATH';

  @override
  String get acquisitionRepositoryUrl => 'REPOSITORY URL';

  @override
  String get acquisitionSourceUrl => 'SOURCE URL';

  @override
  String get acquisitionFolderPathHint => '/path/to/skills';

  @override
  String get acquisitionRepositoryUrlHint =>
      'github.com/owner/repo or owner/repo';

  @override
  String get acquisitionGitRef => 'GIT REF';

  @override
  String get acquisitionGitRefHint => 'main, tag, or commit (optional)';

  @override
  String get acquisitionGitSubpath => 'REPOSITORY SUBPATH';

  @override
  String get acquisitionGitSubpathHint => 'path/to/skills (optional)';

  @override
  String get acquisitionSourceUrlHint => 'https://skills.example.com';

  @override
  String get acquisitionMultipleSkillsHint =>
      'You can install multiple skills from one repository at once.';

  @override
  String acquisitionStep(Object current) {
    return 'Step $current of 3';
  }

  @override
  String acquisitionInstall(Object count, Object plural) {
    return 'Install $count skill$plural';
  }

  @override
  String get notificationInfoTitle => 'Notice';

  @override
  String get notificationSuccessTitle => 'Completed';

  @override
  String get notificationWarningTitle => 'Completed with a warning';

  @override
  String get notificationErrorTitle => 'Operation failed';

  @override
  String get notificationRepositoryRefreshed => 'The repository was refreshed.';

  @override
  String get notificationSkillsInstalled =>
      'The selected skills were installed.';

  @override
  String get notificationActivationEnabled => 'The skill is now active.';

  @override
  String get notificationActivationDisabled => 'The skill is now inactive.';

  @override
  String get notificationSkillFavorited => 'Added to favorites.';

  @override
  String get notificationSkillUnfavorited => 'Removed from favorites.';

  @override
  String get notificationSkillUpdated => 'The skill was updated.';

  @override
  String get notificationSkillRemoved => 'The skill was deleted.';

  @override
  String get notificationUpdatesApplied => 'The selected updates were applied.';

  @override
  String get notificationProjectRootRegistered =>
      'The Project Root was registered.';

  @override
  String get notificationProjectRootUnregistered =>
      'The Project Root was removed.';

  @override
  String get notificationExternalSkillsAdopted =>
      'The selected external Skills are now managed.';

  @override
  String get notificationExternalSkillsPartiallyAdopted =>
      'Some Skills are now managed. The others could not be taken over.';

  @override
  String get notificationTranslationTitle => 'Translating';

  @override
  String get notificationTranslationStarted =>
      'Translation started. The document will update block by block.';

  @override
  String notificationTranslationProgress(Object completed, Object total) {
    return 'Translated $completed of $total blocks.';
  }

  @override
  String get notificationTranslationCancelling => 'Cancelling translation…';

  @override
  String get notificationTranslationCompleted =>
      'The document was translated successfully.';

  @override
  String get notificationTranslationCancelled =>
      'Translation was cancelled and the previous content was restored.';

  @override
  String get notificationTranslationFailed =>
      'Translation failed. The previous translation or original content has been restored.';

  @override
  String get notificationTranslationCacheDeleted =>
      'The cached translation was deleted.';

  @override
  String get notificationTranslationSettingsSaved =>
      'Translation settings saved.';

  @override
  String get notificationFinalizationPendingTitle => 'Finishing recovery';

  @override
  String get notificationFinalizationPending =>
      'Changes were committed. Finishing recovery…';

  @override
  String get notificationFinalizationRecovered => 'Recovery is complete.';

  @override
  String get workspaceFinalizationRetryTitle => 'Recovery needs attention';

  @override
  String get workspaceFinalizationRetryMessage =>
      'Committed changes are safe, but cleanup could not finish. Retry recovery before making more workspace changes.';

  @override
  String get workspaceFinalizationRetryAction => 'Retry recovery';

  @override
  String get notificationUpdateCheckStarted => 'Checking for updates…';

  @override
  String get notificationUpdateCheckCurrent =>
      'This skill is already up to date.';

  @override
  String get notificationUpdateCheckAvailable =>
      'An update is available for this skill.';

  @override
  String get notificationUpdateCheckUnavailable =>
      'The source could not be reached, so the update status is unknown.';

  @override
  String get notificationUpdateCheckUnsupported =>
      'This source does not support update checks.';

  @override
  String get notificationUpdateCheckResolutionRequired =>
      'This skill needs resolution on the Updates page before it can be updated.';

  @override
  String get notificationUpdateCandidateAbandoned =>
      'The update candidate was abandoned.';

  @override
  String get notificationOperationCancelled => 'The operation was cancelled.';

  @override
  String get notificationCompletedWithWarnings =>
      'The operation completed, but some items need attention.';

  @override
  String get notificationShowDetails => 'Show details';

  @override
  String get ownershipRepairTitle => 'Repair Agent folder ownership?';

  @override
  String get ownershipRepairMessage =>
      'Some Agent Skills folders belong to another user. SkillDeck can restore them to your account before continuing.';

  @override
  String get ownershipRepairSystemPrompt =>
      'macOS will ask for an administrator password. SkillDeck only changes the owner of the folders listed below; it does not change their permissions.';

  @override
  String get ownershipRepairCustomAgent => 'Custom Agent — confirm this path';

  @override
  String get ownershipRepairBuiltInAgent => 'Built-in Agent';

  @override
  String get ownershipRepairCancel => 'Cancel';

  @override
  String get ownershipRepairContinue => 'Repair and continue';

  @override
  String get errorAgentRootOwnership =>
      'SkillDeck could not safely repair the Agent Skills folder ownership. Review the folder path and permissions, then try again.';

  @override
  String errorAgentRootOwnershipOutsideHome(Object path) {
    return 'An Agent Skills folder resolves outside your home directory and cannot be repaired automatically: $path';
  }

  @override
  String errorAgentRootOwnershipNotDirectory(Object path) {
    return 'The configured Agent Skills path is not a folder: $path';
  }

  @override
  String errorAgentRootOwnershipInspectionFailed(Object path) {
    return 'SkillDeck could not inspect this Agent Skills folder. It may be a broken or circular link: $path';
  }

  @override
  String get errorAgentRootOwnershipAuthorizationRejected =>
      'macOS did not authorize the Agent Skills ownership repair.';

  @override
  String get errorAgentRootOwnershipRepairFailed =>
      'macOS could not change the owner of the selected Agent Skills folders.';

  @override
  String errorAgentRootOwnershipStillInvalid(Object path) {
    return 'Some entries are still owned by another user after repair: $path';
  }

  @override
  String errorAgentRootOwnershipBlockedCount(int count) {
    return '$count Agent Skills folders need fixing before SkillDeck can continue.';
  }

  @override
  String errorAgentRootOwnershipStillInvalidCount(int count) {
    return '$count Agent Skills folders still have problems after the repair.';
  }

  @override
  String get errorAgentRootOwnershipUnsupported =>
      'Automatic Agent Skills ownership repair is not supported on this device.';

  @override
  String stubComingSoon(Object section) {
    return 'Coming soon: $section';
  }

  @override
  String get skillDriftReviewAction => 'Review outside changes';

  @override
  String get skillDriftReviewTooltip =>
      'This skill was changed outside SkillDeck. Updates, activation, and editing are paused until you resolve it.';

  @override
  String get skillDriftWhatChanged => 'What changed';

  @override
  String get skillDriftHowToResolve => 'How to resolve';

  @override
  String get skillDriftLocationAgentFolder => 'Agent folder';

  @override
  String get skillDriftLinkReplaced =>
      'The link to SkillDeck was replaced with a regular file or folder';

  @override
  String get skillDriftFolderReplaced =>
      'The folder was replaced with a link or file';

  @override
  String skillDriftKeepOption(String location) {
    return 'Keep the changes in $location';
  }

  @override
  String get skillDriftKeepOptionDetail =>
      'Saved as a new version and synced to every location. You can undo it from History.';

  @override
  String get skillDriftRestoreOptionDetail =>
      'Discard the outside changes and return every location to the current version.';

  @override
  String get skillDriftChooseOption => 'Choose an option';

  @override
  String get skillDriftDialogTitle => 'Review outside changes';

  @override
  String get skillDriftReviewDescription =>
      'These locations were changed outside SkillDeck. Choose which content to keep.';

  @override
  String get skillDriftLocationRepositoryCopy => 'SkillDeck\'s stored copy';

  @override
  String get skillDriftContentChanged => 'Files were edited';

  @override
  String get skillDriftWrongLinkTarget => 'The link now points somewhere else';

  @override
  String get skillDriftKeepExternal => 'Keep these changes';

  @override
  String get skillDriftRestoreManaged => 'Restore SkillDeck version';

  @override
  String get skillDriftRestoreWarning =>
      'Outside changes will be overwritten and are not backed up. Export them first if you need them.';

  @override
  String get skillDriftExportAction => 'Export…';

  @override
  String skillDriftExported(String path) {
    return 'Exported to $path';
  }

  @override
  String get skillDriftStale =>
      'The skill or external files changed since this review. Refresh and review again before choosing an action.';

  @override
  String get skillDriftKeepUnavailable =>
      'These changes can\'t be saved as a new version, so only the SkillDeck version can be restored.';

  @override
  String get skillDriftNoChanges =>
      'No external changes remain. Restoring will leave this skill unchanged.';

  @override
  String get removeSkillDriftWarning =>
      'This skill has external changes. Deleting it will permanently discard changes at its managed locations.';

  @override
  String get errorDriftResolutionUnavailable =>
      'This action is unavailable for the external change. Review the available actions. If the files cannot be reviewed safely, replace the source or delete the skill.';

  @override
  String skillDriftMissingArtifacts(int count) {
    return 'Missing locations that will also be restored: $count.';
  }

  @override
  String get skillDriftRefreshReview => 'Refresh and review again';

  @override
  String get skillDriftRestoreMissing => 'Restore missing locations';

  @override
  String get settingsGlobalActivationMethod => 'Global activation method';

  @override
  String get settingsActivationMethodAutomatic => 'Automatic';

  @override
  String get settingsActivationMethodCopy => 'Copy';

  @override
  String get settingsActivationMethodSymbolicLink => 'Link';

  @override
  String get settingsActivationMethodAutomaticDescription =>
      'Links when the folder supports it, otherwise copies.';

  @override
  String get settingsActivationMethodCopyDescription =>
      'Places a full copy in each Agent folder. Most compatible; each update rewrites the copy.';

  @override
  String get settingsActivationMethodSymbolicLinkDescription =>
      'Points to SkillDeck\'s stored copy, so updates apply instantly. Activation fails if the folder can\'t hold a link.';

  @override
  String get settingsActivationMethodScopeNote =>
      'Applies to new activations only. Project activations always copy.';

  @override
  String get errorSymbolicLinkUnavailable =>
      'This Agent folder can\'t hold a symbolic link. In Settings › Agents, set the global activation method to Automatic or Copy.';

  @override
  String get acquisitionCandidateInstalled =>
      'Already installed. A Slot holds one Skill, so it can\'t be installed again.';

  @override
  String get acquisitionOpenInstalledSkill => 'Open';

  @override
  String get acquisitionErrorLocalPath =>
      'Enter the folder\'s full path, or choose it with the button on the right.';

  @override
  String get acquisitionSubtitleV2 =>
      'Install from a link, an install command, a local folder, or a Git repository.';

  @override
  String get acquisitionInputModeSmart => 'Detect automatically';

  @override
  String get acquisitionInputModeTyped => 'By type';

  @override
  String get acquisitionSmartHint =>
      'Paste a repository, an npx skills add command, a URL, or a folder path';

  @override
  String get acquisitionAgentPromptTitle => 'Let an Agent install it for me';

  @override
  String get acquisitionAgentPromptCopied => 'Copied';

  @override
  String get acquisitionAgentPromptHint =>
      'Send this prompt to an Agent. It installs the Skill with the skilldeck Skill.';

  @override
  String get acquisitionAgentPromptCopy => 'Copy prompt';

  @override
  String get acquisitionAgentPromptOpenSettings => 'Go to Settings';

  @override
  String get acquisitionAgentSetupTitle => 'Set up the command line first';

  @override
  String get acquisitionAgentSetupBody =>
      'Agents install through the skilldeck Skill, which calls the command line. Finish both steps in Settings › Command Line.';

  @override
  String get acquisitionAgentSetupTool => 'Command line tool ready';

  @override
  String get acquisitionAgentSetupSkill =>
      'skilldeck Skill active for an Agent';

  @override
  String get acquisitionAgentPrompt =>
      'Call the \"skilldeck\" Skill and use the skilldeck command to install a Skill for me:\n1. First check which Skills the source contains. If there is only one, install it. If there are several, list their names and descriptions and ask me which to install.\n2. After installing, activate it for the Agent you are running in, so you can use it right away.\n3. When you are done, tell me which Skills were installed and which Agent they are active for. If SkillDeck needs my approval, or a step fails, tell me why and what to do next.\n\nThe Skill I want (a repository, URL, or local folder path): ';

  @override
  String get acquisitionAdvancedOptions => 'Advanced options';

  @override
  String get acquisitionAdvancedOptionsHint => 'Git ref, repository subpath';

  @override
  String get acquisitionInspect => 'Check';

  @override
  String get acquisitionClearInput => 'Clear';

  @override
  String acquisitionDetectedKind(Object kind, Object count, Object plural) {
    return '$kind · $count skill$plural found';
  }

  @override
  String get acquisitionPreselectedSkills => 'Preselected skills';

  @override
  String get acquisitionPreselectedSkillsNote =>
      'From the command\'s --skill. They will be checked in the next step; you can still change the selection.';

  @override
  String get acquisitionPreselectedScopeGlobal =>
      'Global scope preselected from the command\'s -g.';

  @override
  String acquisitionPreselectedAgents(Object agents) {
    return 'Agents preselected from the command: $agents.';
  }

  @override
  String acquisitionUnmatchedSkills(Object names) {
    return 'Not found in this source: $names.';
  }

  @override
  String acquisitionIgnoredFlags(Object flags) {
    return 'Ignored: $flags.';
  }

  @override
  String get acquisitionErrorWebSourceHasNoSkillsTitle =>
      'This address has no installable skills';

  @override
  String get acquisitionErrorWebSourceHasNoSkillsBody =>
      'It may be an article or a project home page. Go back to that page, copy its install command or GitHub repository address, and paste it here.';

  @override
  String get acquisitionMultipleSkillsHintV2 =>
      'You can install multiple skills from one repository at once. An npx skills add command works here too.';

  @override
  String get errorNoSkillsInSource =>
      'No skills were found in this source. A skill is a folder that contains a SKILL.md file.';

  @override
  String get errorLocalFolderNotFound =>
      'This folder doesn\'t exist. Check the path.';

  @override
  String get errorRepositorySubpathNotFound =>
      'The repository has no such subpath. Check the spelling, or leave it empty to scan the whole repository.';

  @override
  String get errorGitNetwork =>
      'Couldn\'t reach the repository. Check your network or proxy settings and try again.';

  @override
  String get errorGitRefNotFound => 'The repository has no such branch or tag.';

  @override
  String get errorSourceLocatorHasQuery =>
      'The address can\'t include query parameters or account details. Remove them and try again.';

  @override
  String errorSkillFileCountExceeded(int maximum) {
    return 'This skill has more than $maximum files. Choose the skill\'s own folder rather than a whole project.';
  }

  @override
  String errorSkillByteSizeExceeded(int maximum) {
    return 'This skill is larger than $maximum MB. Choose the skill\'s own folder rather than a whole project.';
  }

  @override
  String get errorSkillMarkdownInvalid =>
      'SKILL.md is missing, or its header lacks a valid name and description.';

  @override
  String errorSkillMarkdownInvalidAt(Object path) {
    return 'The header of $path lacks a valid name and description.';
  }

  @override
  String get errorSkillNameUnsupported =>
      'Skill names may use only lowercase letters, digits, and hyphens.';

  @override
  String errorSkillNameUnsupportedAt(Object path) {
    return 'The name in $path isn\'t supported. Skill names may use only lowercase letters, digits, and hyphens.';
  }

  @override
  String get externalSkillsRescanned =>
      'The Agent folders changed, so they were scanned again. Review the list and confirm to take the skills over.';

  @override
  String browserEmptyExistingDescription(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count skills',
      one: '1 skill',
    );
    return 'Found $_temp0 already in your Agent folders. Take them over without reinstalling.';
  }

  @override
  String get browserTakeOverExistingSkills => 'Take over existing skills';

  @override
  String get settingsNavGroupApp => 'App';

  @override
  String get settingsNavGroupSystem => 'System';

  @override
  String get settingsGeneralTitle => 'General';

  @override
  String get settingsGeneralDescription =>
      'Interface language, how Skills are activated, and project folders. Changes apply right away.';

  @override
  String get settingsAppearanceTitle => 'Appearance';

  @override
  String get settingsAppearanceDescription =>
      'Theme and how Skill lists are displayed. Changes apply right away.';

  @override
  String get settingsAppearanceMode => 'Theme';

  @override
  String get settingsAppearanceModeDescription =>
      'Follow System switches with your system\'s light or dark mode.';

  @override
  String get settingsAppearanceModeLight => 'Light';

  @override
  String get settingsAppearanceModeDark => 'Dark';

  @override
  String get settingsSkillListLayout => 'Skill list view';

  @override
  String get settingsSkillListLayoutDescription =>
      'Applies to both Installed and Favorites.';

  @override
  String get settingsSkillListLayoutList => 'List';

  @override
  String get settingsSkillListLayoutCards => 'Cards';

  @override
  String get settingsAgentsTitle => 'Agents';

  @override
  String get settingsAgentsDescription =>
      'SkillDeck activates Skills into the folders of these Agents. Agents that are turned off are not offered as activation targets.';

  @override
  String get settingsMaintenanceTitle => 'Maintenance';

  @override
  String get settingsMaintenanceDescription =>
      'For troubleshooting. Each check runs only when you start it.';

  @override
  String get settingsAboutSectionTitle => 'About SkillDeck';

  @override
  String get settingsLanguageGroup => 'Language';

  @override
  String get settingsActivationGroup => 'Activation';

  @override
  String get settingsProjectRootsGroup => 'Project Folders';

  @override
  String get settingsLanguageDescription =>
      'Follow System uses the language of your system.';

  @override
  String get settingsProjectRootsRegistered => 'Registered Project Roots';

  @override
  String agentsShowAll(int count) {
    return 'Show all $count Agents';
  }

  @override
  String get agentsShowFewer => 'Show fewer';

  @override
  String get settingsSkillsGroup => 'Skills';

  @override
  String get settingsEnvironmentGroup => 'Environment';

  @override
  String get settingsValidateNow => 'Validate Now';

  @override
  String settingsValidationLastRun(String time, String summary) {
    return 'Last validated $time. $summary';
  }

  @override
  String settingsValidationLastFailed(String time) {
    return 'Last validated $time. The validation could not finish.';
  }

  @override
  String get settingsUpdatesGroup => 'Updates';

  @override
  String get settingsLinksGroup => 'Links';

  @override
  String settingsAppVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsAutomaticUpdates => 'Automatic Updates';

  @override
  String get translationServiceGroup => 'Service';

  @override
  String get translationOutputGroup => 'Output';

  @override
  String get translationEndpointHint =>
      'Leave empty to use the default endpoint.';

  @override
  String get translationApiKeyHint =>
      'Stored in the system credential store and never logged.';

  @override
  String translationStatusConfigured(String provider) {
    return 'Configured · $provider';
  }

  @override
  String get translationStatusNotConfigured =>
      'No translation service configured';

  @override
  String get translationStatusNotConfiguredDetail =>
      'Fill in the settings below and save them to translate Skills.';

  @override
  String get translationTestConnection => 'Test Connection';

  @override
  String get translationTestRunning => 'Testing the connection…';

  @override
  String get translationTestSucceeded => 'Connection works';

  @override
  String get translationTestSucceededDetail =>
      'The service returned a translation of a short sample. No Skill content was sent.';

  @override
  String get translationTestFailed => 'Connection failed';

  @override
  String get translationTestFailedAuthentication =>
      'The API key was rejected or has no access to this model.';

  @override
  String get translationTestFailedRateLimited =>
      'The service is limiting requests. Try again later.';

  @override
  String get translationTestFailedNetwork =>
      'Could not reach the endpoint. Check the address and your network.';

  @override
  String get translationTestFailedRejected =>
      'The service rejected the request. Check the model name and protocol.';

  @override
  String get translationTestFailedConfiguration =>
      'Check the endpoint, model, and target language.';

  @override
  String get translationTestFailedCredentialRequired =>
      'Anthropic needs an API key.';

  @override
  String get translationTestFailedUnknown =>
      'The connection test did not finish.';

  @override
  String get translationUnsavedChanges => 'Unsaved changes';

  @override
  String get translationRevert => 'Revert';

  @override
  String get tagsFilterTitle => 'Tags';

  @override
  String get tagsCreate => 'New tag';

  @override
  String get tagsNamePlaceholder => 'Tag name';

  @override
  String get tagsDelete => 'Delete';

  @override
  String tagsDeleteTitle(Object name) {
    return 'Delete “$name”?';
  }

  @override
  String tagsDeleteMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Skills will lose this tag.',
      one: '1 Skill will lose this tag.',
      zero: 'No Skills use this tag.',
    );
    return '$_temp0 The Skills themselves stay unchanged.';
  }

  @override
  String get tagsSearchPlaceholder => 'Search or create a tag';

  @override
  String tagsCreateNamed(Object name) {
    return 'Create “$name”';
  }

  @override
  String get tagsAdd => 'Add tag';

  @override
  String tagsRemove(Object name) {
    return 'Remove tag $name';
  }

  @override
  String get tagsFilterEmpty => 'No Skills carry all of the selected tags.';

  @override
  String get tagsClearFilter => 'Clear tag filter';

  @override
  String get tagsClear => 'Clear';

  @override
  String get tagsManageHint =>
      'Right-click a tag to rename, recolor, or delete it.';

  @override
  String get tagsEdit => 'Edit tag';

  @override
  String tagsColorSwatch(int index) {
    return 'Color $index';
  }

  @override
  String get tagsNoneAssigned => 'No tags yet.';

  @override
  String get commandLineVerbActivateProgressive => 'Activating';

  @override
  String get commandLineVerbActivatePast => 'Activated';

  @override
  String get commandLineVerbDeactivateProgressive => 'Deactivating';

  @override
  String get commandLineVerbDeactivatePast => 'Deactivated';

  @override
  String get commandLineVerbFavoriteProgressive => 'Favoriting';

  @override
  String get commandLineVerbFavoritePast => 'Favorited';

  @override
  String get commandLineVerbUnfavoriteProgressive => 'Unfavoriting';

  @override
  String get commandLineVerbUnfavoritePast => 'Unfavorited';

  @override
  String get commandLineVerbNoteProgressive => 'Annotating';

  @override
  String get commandLineVerbNotePast => 'Annotated';

  @override
  String get commandLineVerbTagAddProgressive => 'Tagging';

  @override
  String get commandLineVerbTagAddPast => 'Tagged';

  @override
  String get commandLineVerbTagRemoveProgressive => 'Untagging';

  @override
  String get commandLineVerbTagRemovePast => 'Untagged';

  @override
  String get commandLineVerbInstallProgressive => 'Installing';

  @override
  String get commandLineVerbInstallPast => 'Installed';

  @override
  String get commandLineVerbUpdateProgressive => 'Updating';

  @override
  String get commandLineVerbUpdatePast => 'Updated';

  @override
  String get commandLineVerbRemoveProgressive => 'Deleting';

  @override
  String get commandLineVerbRemovePast => 'Deleted';

  @override
  String get commandLineVerbReplaceSourceProgressive =>
      'Replacing the source of';

  @override
  String get commandLineVerbReplaceSourcePast => 'Replaced the source of';

  @override
  String commandLineRunning(String verb, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Skills',
      one: '1 Skill',
    );
    return 'Command line: $verb $_temp0';
  }

  @override
  String get commandLineCancelledSuffix => ', the rest cancelled';

  @override
  String commandLineSummaryTitle(String verb, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Skills',
      one: '1 Skill',
    );
    return '$verb $_temp0';
  }

  @override
  String commandLineSummaryReplaceSource(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Skills',
      one: '1 Skill',
    );
    return 'Replaced the source of $_temp0';
  }

  @override
  String commandLineSummaryFailedSuffix(int failed) {
    return ', $failed failed';
  }

  @override
  String get commandLineSummaryOrigin => 'Command line';

  @override
  String get commandLineSummaryAllSucceeded => 'All succeeded';

  @override
  String commandLineSummaryDone(int count) {
    return '$count completed';
  }

  @override
  String commandLineSummaryMore(int count) {
    return '+$count';
  }

  @override
  String commandLineAgents(String agents) {
    return 'For $agents';
  }

  @override
  String commandLineProgress(int done, int total) {
    return '$done/$total';
  }

  @override
  String commandLineProcessing(String slotKey) {
    return 'Processing $slotKey';
  }

  @override
  String get commandLineCancel => 'Cancel';

  @override
  String get commandLineCancelling => 'Cancelling…';

  @override
  String commandLineOpenSkill(String slotKey) {
    return 'Open $slotKey';
  }

  @override
  String get commandLineDismiss => 'Dismiss';

  @override
  String get commandLineErrorActivationTargetOccupied =>
      'An unmanaged folder with the same name is in the way; nothing was changed.';

  @override
  String get commandLineErrorOwnershipRepair =>
      'Agent folder permissions need repair in SkillDeck.';

  @override
  String get commandLineErrorUnknownAgent =>
      'That Agent is not set up on this device.';

  @override
  String get commandLineErrorGeneric => 'The operation failed.';

  @override
  String get operationWaitingForCommandLine =>
      'Waiting for the command line to finish…';

  @override
  String commandLineApprovalRemoveTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Skills',
      one: '1 Skill',
    );
    return 'The command line wants to delete $_temp0';
  }

  @override
  String commandLineApprovalDeleteTagTitle(String tag) {
    return 'The command line wants to delete the tag “$tag”';
  }

  @override
  String commandLineApprovalActivatedIn(String agents) {
    return 'Removes activations in $agents';
  }

  @override
  String get commandLineApprovalNotActivated => 'Not active in any Agent';

  @override
  String get commandLineApprovalUnpublishedDraft => 'has an unpublished Draft';

  @override
  String get commandLineApprovalSkillGone => 'No longer installed';

  @override
  String get commandLineApprovalRemoveWarning =>
      'This can’t be undone: files, version history, Drafts, notes, and tag assignments are deleted together.';

  @override
  String commandLineApprovalTagWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Skills',
      one: '1 Skill',
    );
    return 'The tag is removed from $_temp0. This can’t be undone.';
  }

  @override
  String get commandLineApprovalStale =>
      'This changed after you looked. Review it again.';

  @override
  String get commandLineApprovalDeny => 'Deny';

  @override
  String commandLineApprovalConfirmRemove(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Skills',
      one: '1 Skill',
    );
    return 'Delete $_temp0';
  }

  @override
  String get commandLineApprovalConfirmDeleteTag => 'Delete tag';

  @override
  String commandLineApprovalReplaceSourceTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Skills',
      one: '1 Skill',
    );
    return 'The command line wants to replace the source of $_temp0';
  }

  @override
  String get commandLineApprovalReplaceSourceWarning =>
      'The old source’s version history and local changes will be deleted for good.';

  @override
  String get commandLineApprovalConfirmReplaceSource => 'Replace sources';

  @override
  String get settingsCommandLineTitle => 'Command Line';

  @override
  String get settingsCommandLineDescription =>
      'Let Agents manage Skills with the skilldeck command.';

  @override
  String get commandLineStatusGroup => 'Status';

  @override
  String get commandLineStatusTitle => 'Command-line service status';

  @override
  String commandLineStatusDetail(String version) {
    return 'SkillDeck $version';
  }

  @override
  String get commandLineStatusRunningBadge => 'Running';

  @override
  String get commandLineStatusStoppedBadge => 'Not running';

  @override
  String get commandLineToolGroup => 'Command-line tool';

  @override
  String get commandLineToolLocation => 'CLI location';

  @override
  String get commandLineToolLocationDetail =>
      'Agents call the CLI at this path.';

  @override
  String get commandLineToolNotBundled =>
      'This build of SkillDeck doesn’t include the command-line tool.';

  @override
  String get commandLineToolFailed =>
      'SkillDeck couldn’t update the command-line tool. Any previous copy is unchanged.';

  @override
  String get commandLinePathTitle => 'Add to PATH (optional)';

  @override
  String get commandLinePathDetail =>
      'To type skilldeck directly in a terminal, add this line to ~/.zshrc:';

  @override
  String get commandLinePathWindows =>
      'The SkillDeck installer adds this folder to your PATH.';

  @override
  String get commandLinePathLinkTitle => 'Install in Terminal';

  @override
  String get commandLinePathLinkDetail =>
      'Adds the skilldeck command to /usr/local/bin so you can run it from any terminal. You may need to enter an administrator password once.';

  @override
  String commandLinePathLinkInstalled(String path) {
    return 'Installed at $path.';
  }

  @override
  String get commandLinePathLinkConflict =>
      '/usr/local/bin/skilldeck is already in use. Add this line to ~/.zshrc instead:';

  @override
  String get commandLinePathLinkInstall => 'Install';

  @override
  String get commandLinePathLinkRemove => 'Remove';

  @override
  String get commandLinePathLinkFailed =>
      'SkillDeck couldn’t change /usr/local/bin/skilldeck.';

  @override
  String get commandLineAgentSkillGroup => 'Install the Command-line Skill';

  @override
  String get commandLineAgentSkillTitle => 'Command-line Skill';

  @override
  String get commandLineAgentSkillActive => 'Active';

  @override
  String get commandLineAgentSkillInactive =>
      'Installed, but not active for any Agent.';

  @override
  String get commandLineAgentSkillNotInstalled =>
      'Teaches Agents to use skilldeck. Installing activates it for every Agent on this device.';

  @override
  String get commandLineAgentSkillInstall => 'Install';

  @override
  String get commandLineAgentSkillInstalling => 'Installing…';

  @override
  String get commandLineAgentSkillOpen => 'View Skill';

  @override
  String get commandLineAgentSkillInstallFailed =>
      'The Agent Skill couldn’t be installed.';

  @override
  String get commandLineSafetyGroup => 'Safety';

  @override
  String get commandLineSafetyTitle =>
      'Deletions need your confirmation in the App';

  @override
  String get commandLineSafetyDetail => 'Agents can only request a deletion.';

  @override
  String get commandLineSafetyAlwaysOn => 'Always on';

  @override
  String get workspaceTakeoverTargets => 'Existing target';

  @override
  String get ownershipRepairFoldersTitle => 'Folders to repair';

  @override
  String get customAgentInvalidPathTitle => 'Invalid path';

  @override
  String get commandLineApprovalSubtitle =>
      'Requested from the skilldeck command line. Nothing runs until you approve.';

  @override
  String get commandLineApprovalRemoveSection => 'To delete';

  @override
  String get commandLineApprovalReplaceSection => 'To replace';

  @override
  String get projectRootsRegisteredTitle => 'Registered';

  @override
  String projectRootsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '1 folder',
    );
    return '$_temp0 registered';
  }

  @override
  String get agentsManageSubtitle =>
      'SkillDeck activates Skills in the Agents on this list.';

  @override
  String agentsManagedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Agents',
      one: '1 Agent',
    );
    return '$_temp0';
  }

  @override
  String get agentsAddBuiltInTitle => 'Add a built-in Agent';

  @override
  String get agentsAddBuiltInSubtitle => 'Choose Agents to add to the list.';

  @override
  String get agentsManagedListTitle => 'Managed Agents';

  @override
  String get customAgentEditorSubtitle =>
      'Set up Skills folders for an Agent without built-in support.';

  @override
  String get customAgentBasicTitle => 'Basic information';

  @override
  String get customAgentSkillsFoldersTitle => 'Skills folders';

  @override
  String get acquisitionActivationScopeTitle => 'Activation scope';

  @override
  String workspaceReplaceSourceFound(String name) {
    return 'Found $name in the new source.';
  }

  @override
  String get agentsAddAction => 'Add';

  @override
  String whatsNewVersionBadge(Object version) {
    return 'New in $version';
  }

  @override
  String get whatsNewCommandLineTitle => 'Now with command line control';

  @override
  String get whatsNewCommandLineBody =>
      'AI Agents can now install, activate, and organize your Skills with the skilldeck command.';

  @override
  String get whatsNewOpenCommandLineSettings => 'Command Line Settings';

  @override
  String get whatsNewDarkModeTitle => 'Now in dark mode';

  @override
  String get whatsNewDarkModeBody =>
      'Choose Light or Dark in Settings › Appearance, or let SkillDeck follow your system.';

  @override
  String get whatsNewOpenAppearanceSettings => 'Appearance Settings';

  @override
  String get whatsNewDismiss => 'Got It';

  @override
  String get workspaceSourceUnavailable => 'Source address unavailable';

  @override
  String get workspaceSourceNotWebLink =>
      'This source has no supported safe web link.';

  @override
  String get workspaceOpenSourceFailed =>
      'The source link could not be opened.';

  @override
  String workspaceOpenSource(String address) {
    return 'Open source: $address';
  }
}
