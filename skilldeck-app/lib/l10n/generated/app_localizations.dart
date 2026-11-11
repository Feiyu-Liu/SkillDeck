import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck'**
  String get appTitle;

  /// No description provided for @navWorkspace.
  ///
  /// In en, this message translates to:
  /// **'WORKSPACE'**
  String get navWorkspace;

  /// No description provided for @navMaintenance.
  ///
  /// In en, this message translates to:
  /// **'MAINTENANCE'**
  String get navMaintenance;

  /// No description provided for @navInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get navInstalled;

  /// No description provided for @navWrite.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get navWrite;

  /// No description provided for @navTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get navTest;

  /// No description provided for @navUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get navUpdates;

  /// No description provided for @navFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get navFavorites;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @trayShowWindow.
  ///
  /// In en, this message translates to:
  /// **'Show Main Window'**
  String get trayShowWindow;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit SkillDeck'**
  String get trayQuit;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonRefreshAndReview.
  ///
  /// In en, this message translates to:
  /// **'Refresh and review'**
  String get commonRefreshAndReview;

  /// No description provided for @commonGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get commonGlobal;

  /// No description provided for @commonProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get commonProject;

  /// No description provided for @activationUniversalAgents.
  ///
  /// In en, this message translates to:
  /// **'Universal Agents'**
  String get activationUniversalAgents;

  /// No description provided for @activationUnknownAgent.
  ///
  /// In en, this message translates to:
  /// **'Unknown Agent'**
  String get activationUnknownAgent;

  /// No description provided for @activationInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get activationInactive;

  /// No description provided for @agentsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage Agents'**
  String get agentsManage;

  /// No description provided for @agentsBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in Agents'**
  String get agentsBuiltIn;

  /// No description provided for @agentsDetected.
  ///
  /// In en, this message translates to:
  /// **'Detected'**
  String get agentsDetected;

  /// No description provided for @agentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Agents to display.'**
  String get agentsEmpty;

  /// No description provided for @agentsRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Agent from management?'**
  String get agentsRemoveTitle;

  /// No description provided for @agentsRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get agentsRemoveAction;

  /// No description provided for @agentsRemoveDescription.
  ///
  /// In en, this message translates to:
  /// **'This removes the Agent from the app\'s management list. Existing Skill files and activations remain accessible to the Agent.'**
  String get agentsRemoveDescription;

  /// No description provided for @agentsOutsideRoster.
  ///
  /// In en, this message translates to:
  /// **'Outside the management list'**
  String get agentsOutsideRoster;

  /// No description provided for @activationAllAgentsToggle.
  ///
  /// In en, this message translates to:
  /// **'Select all Agents'**
  String get activationAllAgentsToggle;

  /// No description provided for @operationPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get operationPreparing;

  /// No description provided for @operationInspecting.
  ///
  /// In en, this message translates to:
  /// **'Inspecting source…'**
  String get operationInspecting;

  /// No description provided for @operationWaitingForLock.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the repository…'**
  String get operationWaitingForLock;

  /// No description provided for @operationPlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning changes…'**
  String get operationPlanning;

  /// No description provided for @operationApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying changes…'**
  String get operationApplying;

  /// No description provided for @operationRecovering.
  ///
  /// In en, this message translates to:
  /// **'Recovering repository state…'**
  String get operationRecovering;

  /// No description provided for @operationRollingBack.
  ///
  /// In en, this message translates to:
  /// **'Restoring the previous state…'**
  String get operationRollingBack;

  /// No description provided for @operationSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Operation completed.'**
  String get operationSucceeded;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed.'**
  String get operationFailed;

  /// No description provided for @operationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Operation cancelled.'**
  String get operationCancelled;

  /// No description provided for @operationProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total}'**
  String operationProgress(Object completed, Object total);

  /// No description provided for @warningInternalSymlinkSkipped.
  ///
  /// In en, this message translates to:
  /// **'An internal symbolic link was skipped.'**
  String get warningInternalSymlinkSkipped;

  /// No description provided for @warningSourceEntrySkipped.
  ///
  /// In en, this message translates to:
  /// **'An unsupported source entry was skipped.'**
  String get warningSourceEntrySkipped;

  /// No description provided for @warningNoActivationTarget.
  ///
  /// In en, this message translates to:
  /// **'No compatible activation target was found.'**
  String get warningNoActivationTarget;

  /// No description provided for @warningProjectSymlinkPortability.
  ///
  /// In en, this message translates to:
  /// **'This project activation uses a symbolic link that may not be portable.'**
  String get warningProjectSymlinkPortability;

  /// No description provided for @warningDuplicateExposure.
  ///
  /// In en, this message translates to:
  /// **'This skill is already exposed at an equivalent location.'**
  String get warningDuplicateExposure;

  /// No description provided for @warningSharedActivationLocation.
  ///
  /// In en, this message translates to:
  /// **'Several Agent Skills folders are one folder, so this Skill was activated there once for all of them.'**
  String get warningSharedActivationLocation;

  /// No description provided for @warningAgentUndetected.
  ///
  /// In en, this message translates to:
  /// **'A selected agent was not detected on this device.'**
  String get warningAgentUndetected;

  /// No description provided for @warningActivationTargetSkipped.
  ///
  /// In en, this message translates to:
  /// **'An unavailable activation target was skipped.'**
  String get warningActivationTargetSkipped;

  /// No description provided for @warningRecoveryCleanupDeferred.
  ///
  /// In en, this message translates to:
  /// **'Some temporary recovery files could not be cleaned up. Repository data is unchanged.'**
  String get warningRecoveryCleanupDeferred;

  /// No description provided for @commonSectionBreadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get commonSectionBreadcrumb;

  /// No description provided for @browserRepositoryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Repository unavailable'**
  String get browserRepositoryUnavailable;

  /// No description provided for @browserRepositoryUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Repository could not be opened.'**
  String get browserRepositoryUnavailableMessage;

  /// No description provided for @browserDesktopRequired.
  ///
  /// In en, this message translates to:
  /// **'Desktop required'**
  String get browserDesktopRequired;

  /// No description provided for @browserDesktopRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck currently supports desktop platforms.'**
  String get browserDesktopRequiredMessage;

  /// No description provided for @browserRefreshRepository.
  ///
  /// In en, this message translates to:
  /// **'Refresh repository'**
  String get browserRefreshRepository;

  /// No description provided for @browserBreadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Workspace / Installed'**
  String get browserBreadcrumb;

  /// No description provided for @browserInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get browserInstalled;

  /// No description provided for @browserNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No skills match \"{query}\".'**
  String browserNoMatches(Object query);

  /// No description provided for @browserFavoritesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No favorite skills yet.'**
  String get browserFavoritesEmpty;

  /// No description provided for @browserInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get browserInactive;

  /// No description provided for @browserActiveRatio.
  ///
  /// In en, this message translates to:
  /// **'{count}/{total} active'**
  String browserActiveRatio(Object count, Object total);

  /// No description provided for @browserAddSkills.
  ///
  /// In en, this message translates to:
  /// **'Add skills'**
  String get browserAddSkills;

  /// No description provided for @browserAddFromSource.
  ///
  /// In en, this message translates to:
  /// **'Add from source'**
  String get browserAddFromSource;

  /// No description provided for @browserDiscoverExistingSkills.
  ///
  /// In en, this message translates to:
  /// **'Discover existing Skills'**
  String get browserDiscoverExistingSkills;

  /// No description provided for @browserUnmanagedSkillsFound.
  ///
  /// In en, this message translates to:
  /// **'{count} unmanaged Skills found'**
  String browserUnmanagedSkillsFound(Object count);

  /// No description provided for @browserAllAgents.
  ///
  /// In en, this message translates to:
  /// **'All Agents'**
  String get browserAllAgents;

  /// No description provided for @browserAllScopes.
  ///
  /// In en, this message translates to:
  /// **'All scopes'**
  String get browserAllScopes;

  /// No description provided for @browserSearchSkills.
  ///
  /// In en, this message translates to:
  /// **'Search skills'**
  String get browserSearchSkills;

  /// No description provided for @browserNoSkillsYet.
  ///
  /// In en, this message translates to:
  /// **'No skills yet'**
  String get browserNoSkillsYet;

  /// No description provided for @browserEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Install your first skill from a local folder, a Git repo, or a URL.'**
  String get browserEmptyDescription;

  /// No description provided for @browserAgentFilter.
  ///
  /// In en, this message translates to:
  /// **'Agent filter {number}'**
  String browserAgentFilter(Object number);

  /// No description provided for @browserScopeSelector.
  ///
  /// In en, this message translates to:
  /// **'Scope filter'**
  String get browserScopeSelector;

  /// No description provided for @browserSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get browserSort;

  /// No description provided for @browserSortNameAscending.
  ///
  /// In en, this message translates to:
  /// **'Name A-Z'**
  String get browserSortNameAscending;

  /// No description provided for @browserSortNameDescending.
  ///
  /// In en, this message translates to:
  /// **'Name Z-A'**
  String get browserSortNameDescending;

  /// No description provided for @browserSortRecentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get browserSortRecentlyAdded;

  /// No description provided for @browserSortOldestAdded.
  ///
  /// In en, this message translates to:
  /// **'Oldest added'**
  String get browserSortOldestAdded;

  /// No description provided for @workspaceBackToSkills.
  ///
  /// In en, this message translates to:
  /// **'Back to skills'**
  String get workspaceBackToSkills;

  /// No description provided for @workspaceBreadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get workspaceBreadcrumb;

  /// No description provided for @workspaceCheckForUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for update'**
  String get workspaceCheckForUpdate;

  /// No description provided for @workspaceUpdateAvailableAction.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get workspaceUpdateAvailableAction;

  /// No description provided for @workspaceUpdateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get workspaceUpdateNow;

  /// No description provided for @workspaceRemoveSkill.
  ///
  /// In en, this message translates to:
  /// **'Delete skill'**
  String get workspaceRemoveSkill;

  /// No description provided for @workspaceFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get workspaceFavorite;

  /// No description provided for @workspaceUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get workspaceUnfavorite;

  /// No description provided for @workspaceTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get workspaceTranslate;

  /// No description provided for @workspaceTranslationComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Translation arrives in a later version'**
  String get workspaceTranslationComingSoon;

  /// No description provided for @workspaceVersion.
  ///
  /// In en, this message translates to:
  /// **'VERSION'**
  String get workspaceVersion;

  /// No description provided for @workspaceSource.
  ///
  /// In en, this message translates to:
  /// **'SOURCE'**
  String get workspaceSource;

  /// No description provided for @workspaceReplaceSource.
  ///
  /// In en, this message translates to:
  /// **'Replace source'**
  String get workspaceReplaceSource;

  /// No description provided for @workspaceReplaceSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace Skill source'**
  String get workspaceReplaceSourceTitle;

  /// No description provided for @workspaceReplaceSourceDescription.
  ///
  /// In en, this message translates to:
  /// **'The new source must contain the same Skill. Existing activations will be preserved.'**
  String get workspaceReplaceSourceDescription;

  /// No description provided for @workspaceReplaceSourceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replace source'**
  String get workspaceReplaceSourceConfirm;

  /// No description provided for @workspaceReplaceSourceSuccess.
  ///
  /// In en, this message translates to:
  /// **'Skill source replaced.'**
  String get workspaceReplaceSourceSuccess;

  /// No description provided for @workspaceReplaceSourceStepReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get workspaceReplaceSourceStepReplace;

  /// No description provided for @workspaceReplaceSourceMismatch.
  ///
  /// In en, this message translates to:
  /// **'A different Skill'**
  String get workspaceReplaceSourceMismatch;

  /// No description provided for @workspaceReplaceSourceNoMatch.
  ///
  /// In en, this message translates to:
  /// **'This source does not contain {name}.'**
  String workspaceReplaceSourceNoMatch(Object name);

  /// No description provided for @workspaceReplaceSourceCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current source'**
  String get workspaceReplaceSourceCurrent;

  /// No description provided for @workspaceReplaceSourceNew.
  ///
  /// In en, this message translates to:
  /// **'New source'**
  String get workspaceReplaceSourceNew;

  /// No description provided for @workspaceReplacing.
  ///
  /// In en, this message translates to:
  /// **'Replacing source…'**
  String get workspaceReplacing;

  /// No description provided for @sourceKindLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get sourceKindLocal;

  /// No description provided for @sourceKindGit.
  ///
  /// In en, this message translates to:
  /// **'Git'**
  String get sourceKindGit;

  /// No description provided for @sourceKindUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get sourceKindUrl;

  /// No description provided for @workspacePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get workspacePreview;

  /// No description provided for @workspaceSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get workspaceSettings;

  /// No description provided for @workspaceSkillNotFound.
  ///
  /// In en, this message translates to:
  /// **'Skill not found'**
  String get workspaceSkillNotFound;

  /// No description provided for @workspaceDocumentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The selected Markdown file could not be read.'**
  String get workspaceDocumentUnavailable;

  /// No description provided for @workspaceDocumentUnavailableNamed.
  ///
  /// In en, this message translates to:
  /// **'{fileName} could not be read.'**
  String workspaceDocumentUnavailableNamed(String fileName);

  /// No description provided for @workspaceDocumentBrowserTitle.
  ///
  /// In en, this message translates to:
  /// **'Markdown files'**
  String get workspaceDocumentBrowserTitle;

  /// No description provided for @workspaceDocumentListUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The Markdown file list could not be loaded.'**
  String get workspaceDocumentListUnavailable;

  /// No description provided for @workspaceDocumentListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Markdown files found.'**
  String get workspaceDocumentListEmpty;

  /// No description provided for @workspaceDocumentSelectorTooltip.
  ///
  /// In en, this message translates to:
  /// **'Choose a Markdown file. Current file: {fileName}'**
  String workspaceDocumentSelectorTooltip(String fileName);

  /// No description provided for @workspaceActivations.
  ///
  /// In en, this message translates to:
  /// **'ACTIVATIONS'**
  String get workspaceActivations;

  /// No description provided for @workspaceActivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Activate skill'**
  String get workspaceActivateTitle;

  /// No description provided for @workspaceActivateDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the Agents that should use this Skill.'**
  String get workspaceActivateDescription;

  /// No description provided for @workspaceActivateScope.
  ///
  /// In en, this message translates to:
  /// **'ACTIVATION SCOPE'**
  String get workspaceActivateScope;

  /// No description provided for @workspaceActivateTargets.
  ///
  /// In en, this message translates to:
  /// **'AGENTS'**
  String get workspaceActivateTargets;

  /// No description provided for @workspaceActivateNoTargets.
  ///
  /// In en, this message translates to:
  /// **'No Agents are available for this scope.'**
  String get workspaceActivateNoTargets;

  /// No description provided for @workspaceActivateAlreadyActive.
  ///
  /// In en, this message translates to:
  /// **'Already active'**
  String get workspaceActivateAlreadyActive;

  /// No description provided for @workspaceActivateUndetectedWarning.
  ///
  /// In en, this message translates to:
  /// **'Not detected; explicit activation is still available.'**
  String get workspaceActivateUndetectedWarning;

  /// No description provided for @workspaceActivateSelectProject.
  ///
  /// In en, this message translates to:
  /// **'Select a Project Root'**
  String get workspaceActivateSelectProject;

  /// No description provided for @workspaceTakeoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace the existing target?'**
  String get workspaceTakeoverTitle;

  /// No description provided for @workspaceTakeoverDescription.
  ///
  /// In en, this message translates to:
  /// **'{agentName} already has an item at this Skill path. Review it before replacing it with the managed copy.'**
  String workspaceTakeoverDescription(String agentName);

  /// No description provided for @workspaceInstallTakeoverDescription.
  ///
  /// In en, this message translates to:
  /// **'{agentName} already has an item at this Skill path. Review it before installing and replacing the existing item.'**
  String workspaceInstallTakeoverDescription(String agentName);

  /// No description provided for @workspaceTakeoverPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get workspaceTakeoverPath;

  /// No description provided for @workspaceTakeoverType.
  ///
  /// In en, this message translates to:
  /// **'Existing item'**
  String get workspaceTakeoverType;

  /// No description provided for @workspaceTakeoverContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get workspaceTakeoverContent;

  /// No description provided for @workspaceTakeoverSkillDirectory.
  ///
  /// In en, this message translates to:
  /// **'Skill folder'**
  String get workspaceTakeoverSkillDirectory;

  /// No description provided for @workspaceTakeoverSkillSymbolicLink.
  ///
  /// In en, this message translates to:
  /// **'Skill symbolic link'**
  String get workspaceTakeoverSkillSymbolicLink;

  /// No description provided for @workspaceTakeoverFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get workspaceTakeoverFile;

  /// No description provided for @workspaceTakeoverInvalidDirectory.
  ///
  /// In en, this message translates to:
  /// **'Folder without a valid SKILL.md'**
  String get workspaceTakeoverInvalidDirectory;

  /// No description provided for @workspaceTakeoverBrokenSymbolicLink.
  ///
  /// In en, this message translates to:
  /// **'Broken symbolic link'**
  String get workspaceTakeoverBrokenSymbolicLink;

  /// No description provided for @workspaceTakeoverContentDifferent.
  ///
  /// In en, this message translates to:
  /// **'Different from the selected Skill'**
  String get workspaceTakeoverContentDifferent;

  /// No description provided for @workspaceTakeoverContentUnknown.
  ///
  /// In en, this message translates to:
  /// **'Could not be compared with the selected Skill'**
  String get workspaceTakeoverContentUnknown;

  /// No description provided for @workspaceTakeoverOpenLocation.
  ///
  /// In en, this message translates to:
  /// **'Open location'**
  String get workspaceTakeoverOpenLocation;

  /// No description provided for @workspaceTakeoverConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replace and activate'**
  String get workspaceTakeoverConfirm;

  /// No description provided for @workspaceInstallTakeoverConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replace and install'**
  String get workspaceInstallTakeoverConfirm;

  /// No description provided for @workspaceTakeoverWarning.
  ///
  /// In en, this message translates to:
  /// **'The existing item will be replaced. If the operation fails, SkillDeck restores it from recovery data.'**
  String get workspaceTakeoverWarning;

  /// No description provided for @notificationOpenLocationFailed.
  ///
  /// In en, this message translates to:
  /// **'The file location could not be opened.'**
  String get notificationOpenLocationFailed;

  /// No description provided for @workspaceNotes.
  ///
  /// In en, this message translates to:
  /// **'NOTES'**
  String get workspaceNotes;

  /// No description provided for @workspaceAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add a note about this skill…'**
  String get workspaceAddNote;

  /// No description provided for @workspaceNotDetected.
  ///
  /// In en, this message translates to:
  /// **'Not detected on this device'**
  String get workspaceNotDetected;

  /// No description provided for @workspaceGlobalScope.
  ///
  /// In en, this message translates to:
  /// **'Global scope'**
  String get workspaceGlobalScope;

  /// No description provided for @workspaceNoActivations.
  ///
  /// In en, this message translates to:
  /// **'No active Agents.'**
  String get workspaceNoActivations;

  /// No description provided for @workspaceDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get workspaceDeactivate;

  /// No description provided for @workspaceActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get workspaceActivate;

  /// No description provided for @workspaceActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get workspaceActive;

  /// No description provided for @workspaceInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get workspaceInactive;

  /// No description provided for @workspaceDuplicateActivationTitle.
  ///
  /// In en, this message translates to:
  /// **'Possible duplicate activation'**
  String get workspaceDuplicateActivationTitle;

  /// No description provided for @workspaceDuplicateActivationMessage.
  ///
  /// In en, this message translates to:
  /// **'This Skill is already active globally for this Agent. Activating it in this project may create a duplicate Skill.'**
  String get workspaceDuplicateActivationMessage;

  /// No description provided for @workspaceDuplicateActivationContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue activating'**
  String get workspaceDuplicateActivationContinue;

  /// No description provided for @workspaceDuplicateActivationDontAskAgain.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show this again'**
  String get workspaceDuplicateActivationDontAskAgain;

  /// No description provided for @workspaceRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete skill?'**
  String get workspaceRemoveTitle;

  /// No description provided for @workspaceRemoveMessage.
  ///
  /// In en, this message translates to:
  /// **'This deletes the Repository Copy and clears its Agent activations.'**
  String get workspaceRemoveMessage;

  /// No description provided for @workspaceRemoveNamedTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String workspaceRemoveNamedTitle(Object name);

  /// No description provided for @workspaceRemoveDetailedMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the Repository Copy and clears all Agent activations. This can’t be undone.'**
  String get workspaceRemoveDetailedMessage;

  /// No description provided for @workspaceRemoveCleared.
  ///
  /// In en, this message translates to:
  /// **'WILL BE CLEARED'**
  String get workspaceRemoveCleared;

  /// No description provided for @workspaceRemoveSlot.
  ///
  /// In en, this message translates to:
  /// **'Skill Slot — {name}'**
  String workspaceRemoveSlot(Object name);

  /// No description provided for @workspaceRemoveActivationCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Activation(s)'**
  String workspaceRemoveActivationCount(Object count);

  /// No description provided for @workspaceRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Delete skill'**
  String get workspaceRemoveAction;

  /// No description provided for @workspaceRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'The skill could not be deleted.'**
  String get workspaceRemoveFailed;

  /// No description provided for @workspaceRemoving.
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get workspaceRemoving;

  /// No description provided for @workspaceRemoveConfirmAgain.
  ///
  /// In en, this message translates to:
  /// **'Confirm again'**
  String get workspaceRemoveConfirmAgain;

  /// No description provided for @workspaceRemoveRevision.
  ///
  /// In en, this message translates to:
  /// **'Confirmed at revision r{revision}. If the repository changed, you’ll review again.'**
  String workspaceRemoveRevision(Object revision);

  /// No description provided for @workspaceRemoveStale.
  ///
  /// In en, this message translates to:
  /// **'The repository changed. Review the refreshed skill at revision r{revision}, then confirm again.'**
  String workspaceRemoveStale(Object revision);

  /// No description provided for @updatesBreadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get updatesBreadcrumb;

  /// No description provided for @updatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updatesTitle;

  /// No description provided for @updatesCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get updatesCheckAgain;

  /// No description provided for @updatesUpdateAll.
  ///
  /// In en, this message translates to:
  /// **'Update all'**
  String get updatesUpdateAll;

  /// No description provided for @updatesEmpty.
  ///
  /// In en, this message translates to:
  /// **'All skills are up to date.'**
  String get updatesEmpty;

  /// No description provided for @updatesCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get updatesCurrent;

  /// No description provided for @updatesAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updatesAvailable;

  /// No description provided for @updatesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Source unavailable'**
  String get updatesUnavailable;

  /// No description provided for @updatesTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Git update check timed out'**
  String get updatesTimedOut;

  /// No description provided for @updatesUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Updates unsupported for this source'**
  String get updatesUnsupported;

  /// No description provided for @updatesUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updatesUpdate;

  /// No description provided for @updatesResolutionRequired.
  ///
  /// In en, this message translates to:
  /// **'Update requires resolution'**
  String get updatesResolutionRequired;

  /// No description provided for @updatesCandidateResolutionRequired.
  ///
  /// In en, this message translates to:
  /// **'Update candidate needs resolution'**
  String get updatesCandidateResolutionRequired;

  /// No description provided for @updatesAbandonCandidate.
  ///
  /// In en, this message translates to:
  /// **'Abandon candidate'**
  String get updatesAbandonCandidate;

  /// No description provided for @updatesNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked'**
  String get updatesNotChecked;

  /// No description provided for @updatesChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updatesChecking;

  /// No description provided for @updatesCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'The check could not be completed.'**
  String get updatesCheckFailed;

  /// No description provided for @updatesCheckOne.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get updatesCheckOne;

  /// No description provided for @updatesCheckProgress.
  ///
  /// In en, this message translates to:
  /// **'Checked {completed} of {total}'**
  String updatesCheckProgress(Object completed, Object total);

  /// No description provided for @updatesUpdatingSkill.
  ///
  /// In en, this message translates to:
  /// **'Updating {slotKey}'**
  String updatesUpdatingSkill(String slotKey);

  /// No description provided for @updatesUpdatingSkills.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updating 1 Skill} other{Updating {count} Skills}}'**
  String updatesUpdatingSkills(int count);

  /// No description provided for @updatesUpdatingDetail.
  ///
  /// In en, this message translates to:
  /// **'{slotKey} · {phase}'**
  String updatesUpdatingDetail(String slotKey, String phase);

  /// No description provided for @updatesFetchingSource.
  ///
  /// In en, this message translates to:
  /// **'Fetching the new version…'**
  String get updatesFetchingSource;

  /// No description provided for @updatesIntegrityRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery required before this skill can be changed.'**
  String get updatesIntegrityRecovery;

  /// No description provided for @settingsBreadcrumb.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get settingsBreadcrumb;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsValidateWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Skills Validation'**
  String get settingsValidateWorkspace;

  /// No description provided for @settingsValidateWorkspaceRunning.
  ///
  /// In en, this message translates to:
  /// **'Validating Skills…'**
  String get settingsValidateWorkspaceRunning;

  /// No description provided for @settingsValidateWorkspaceDone.
  ///
  /// In en, this message translates to:
  /// **'Workspace validation completed.'**
  String get settingsValidateWorkspaceDone;

  /// No description provided for @settingsValidateWorkspaceDescription.
  ///
  /// In en, this message translates to:
  /// **'Check every managed Skill for missing or changed files.'**
  String get settingsValidateWorkspaceDescription;

  /// No description provided for @settingsAppUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsAppUpdateTitle;

  /// No description provided for @settingsAppUpdateCurrentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current version: {version}'**
  String settingsAppUpdateCurrentVersion(String version);

  /// No description provided for @settingsAppUpdateVersionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get settingsAppUpdateVersionUnknown;

  /// No description provided for @settingsAppUpdateUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'Automatic updates are not configured in this build.'**
  String get settingsAppUpdateUnconfigured;

  /// No description provided for @settingsAppUpdateInvalid.
  ///
  /// In en, this message translates to:
  /// **'This build has an invalid update configuration.'**
  String get settingsAppUpdateInvalid;

  /// No description provided for @settingsAppUpdateReady.
  ///
  /// In en, this message translates to:
  /// **'Automatic update checks are enabled.'**
  String get settingsAppUpdateReady;

  /// No description provided for @settingsAppUpdateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates'**
  String get settingsAppUpdateChecking;

  /// No description provided for @settingsAppUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck {version} is available.'**
  String settingsAppUpdateAvailable(String version);

  /// No description provided for @settingsAppUpdateAvailableGeneric.
  ///
  /// In en, this message translates to:
  /// **'A new SkillDeck version is available.'**
  String get settingsAppUpdateAvailableGeneric;

  /// No description provided for @settingsAppUpdateDownloaded.
  ///
  /// In en, this message translates to:
  /// **'The update has downloaded. Open the updater to view progress and confirm installation.'**
  String get settingsAppUpdateDownloaded;

  /// No description provided for @settingsAppUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'The update operation failed. Try checking again.'**
  String get settingsAppUpdateFailed;

  /// No description provided for @settingsAppUpdateBusy.
  ///
  /// In en, this message translates to:
  /// **'Finish the active SkillDeck operation before restarting.'**
  String get settingsAppUpdateBusy;

  /// No description provided for @settingsAppUpdateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsAppUpdateCheck;

  /// No description provided for @settingsAppUpdateProcessing.
  ///
  /// In en, this message translates to:
  /// **'The updater is busy. Please try again shortly.'**
  String get settingsAppUpdateProcessing;

  /// No description provided for @sidebarAppUpdateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get sidebarAppUpdateChecking;

  /// No description provided for @sidebarAppUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get sidebarAppUpdateAvailable;

  /// No description provided for @sidebarAppUpdateDownloaded.
  ///
  /// In en, this message translates to:
  /// **'View update'**
  String get sidebarAppUpdateDownloaded;

  /// No description provided for @sidebarAppUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry update'**
  String get sidebarAppUpdateFailed;

  /// No description provided for @settingsAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck'**
  String get settingsAboutTitle;

  /// No description provided for @settingsOfficialWebsite.
  ///
  /// In en, this message translates to:
  /// **'Official Website'**
  String get settingsOfficialWebsite;

  /// No description provided for @settingsChangelog.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get settingsChangelog;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsTermsOfService;

  /// No description provided for @settingsOpenSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get settingsOpenSourceLicenses;

  /// No description provided for @openSourceLicensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get openSourceLicensesTitle;

  /// No description provided for @openSourceLicensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck is built with these components. Choose one to read its license.'**
  String get openSourceLicensesSubtitle;

  /// No description provided for @openSourceLicensesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 license} other{{count} licenses}}'**
  String openSourceLicensesCount(int count);

  /// No description provided for @openSourceLicensesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The license texts could not be loaded.'**
  String get openSourceLicensesLoadFailed;

  /// No description provided for @settingsValidateWorkspaceFailed.
  ///
  /// In en, this message translates to:
  /// **'Workspace validation failed.'**
  String get settingsValidateWorkspaceFailed;

  /// No description provided for @settingsValidateWorkspaceSummary.
  ///
  /// In en, this message translates to:
  /// **'Checked {checked} skills, repaired {repaired} artifacts, found {drifted} external changes, and failed {failed} skills.'**
  String settingsValidateWorkspaceSummary(
    Object checked,
    Object drifted,
    Object failed,
    Object repaired,
  );

  /// No description provided for @settingsEnvironmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Environment check'**
  String get settingsEnvironmentTitle;

  /// No description provided for @settingsEnvironmentDescription.
  ///
  /// In en, this message translates to:
  /// **'Check the external tools SkillDeck relies on. Checks run only when you start them.'**
  String get settingsEnvironmentDescription;

  /// No description provided for @settingsEnvironmentRecheck.
  ///
  /// In en, this message translates to:
  /// **'Recheck'**
  String get settingsEnvironmentRecheck;

  /// No description provided for @settingsEnvironmentOpenInstallPrompt.
  ///
  /// In en, this message translates to:
  /// **'Open install prompt'**
  String get settingsEnvironmentOpenInstallPrompt;

  /// No description provided for @settingsEnvironmentCheckGit.
  ///
  /// In en, this message translates to:
  /// **'Git command line'**
  String get settingsEnvironmentCheckGit;

  /// No description provided for @settingsEnvironmentStatusNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet'**
  String get settingsEnvironmentStatusNotChecked;

  /// No description provided for @settingsEnvironmentStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get settingsEnvironmentStatusChecking;

  /// No description provided for @settingsEnvironmentGitAvailable.
  ///
  /// In en, this message translates to:
  /// **'Git is available.'**
  String get settingsEnvironmentGitAvailable;

  /// No description provided for @settingsEnvironmentGitNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Git was not found on this device. Public HTTPS repositories still install; SSH and private repositories need Git.'**
  String get settingsEnvironmentGitNotInstalled;

  /// No description provided for @settingsEnvironmentGitDeveloperToolsRequired.
  ///
  /// In en, this message translates to:
  /// **'The macOS Command Line Developer Tools are required. Choose Install in the system dialog, then recheck.'**
  String get settingsEnvironmentGitDeveloperToolsRequired;

  /// No description provided for @settingsEnvironmentGitDeveloperToolsInstalling.
  ///
  /// In en, this message translates to:
  /// **'The Command Line Developer Tools are installing. Recheck once the install finishes.'**
  String get settingsEnvironmentGitDeveloperToolsInstalling;

  /// No description provided for @settingsEnvironmentGitProbeFailed.
  ///
  /// In en, this message translates to:
  /// **'The Git check did not complete.'**
  String get settingsEnvironmentGitProbeFailed;

  /// No description provided for @settingsInterfaceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Interface language'**
  String get settingsInterfaceLanguage;

  /// No description provided for @settingsFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get settingsFollowSystem;

  /// No description provided for @settingsChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get settingsChinese;

  /// No description provided for @settingsEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsEnglish;

  /// No description provided for @settingsCustomAgents.
  ///
  /// In en, this message translates to:
  /// **'Custom Agents'**
  String get settingsCustomAgents;

  /// No description provided for @settingsCustomAgentsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage additional Agent skill locations on this device.'**
  String get settingsCustomAgentsDescription;

  /// No description provided for @settingsAgentsManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent Management'**
  String get settingsAgentsManagementTitle;

  /// No description provided for @settingsAgentsManagementDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage built-in Agents and configure custom Agents on this device.'**
  String get settingsAgentsManagementDescription;

  /// No description provided for @settingsAddAgent.
  ///
  /// In en, this message translates to:
  /// **'Add Agent'**
  String get settingsAddAgent;

  /// No description provided for @settingsEditAgent.
  ///
  /// In en, this message translates to:
  /// **'Edit Agent'**
  String get settingsEditAgent;

  /// No description provided for @settingsDeleteAgent.
  ///
  /// In en, this message translates to:
  /// **'Remove Agent'**
  String get settingsDeleteAgent;

  /// No description provided for @settingsSaveAgent.
  ///
  /// In en, this message translates to:
  /// **'Save Agent'**
  String get settingsSaveAgent;

  /// No description provided for @settingsAgentName.
  ///
  /// In en, this message translates to:
  /// **'Agent name'**
  String get settingsAgentName;

  /// No description provided for @settingsAgentIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get settingsAgentIcon;

  /// No description provided for @settingsAgentPathGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global Skills directory'**
  String get settingsAgentPathGlobal;

  /// No description provided for @settingsAgentPathProject.
  ///
  /// In en, this message translates to:
  /// **'Project Skills relative directory'**
  String get settingsAgentPathProject;

  /// No description provided for @settingsAgentChooseGlobalDirectory.
  ///
  /// In en, this message translates to:
  /// **'Choose global Skills directory'**
  String get settingsAgentChooseGlobalDirectory;

  /// No description provided for @settingsAgentAdvancedShow.
  ///
  /// In en, this message translates to:
  /// **'Show advanced settings'**
  String get settingsAgentAdvancedShow;

  /// No description provided for @settingsAgentAdvancedHide.
  ///
  /// In en, this message translates to:
  /// **'Hide advanced settings'**
  String get settingsAgentAdvancedHide;

  /// No description provided for @settingsAgentDiscoveryPathsGlobal.
  ///
  /// In en, this message translates to:
  /// **'Additional global discovery directories'**
  String get settingsAgentDiscoveryPathsGlobal;

  /// No description provided for @settingsAgentDiscoveryPathsProject.
  ///
  /// In en, this message translates to:
  /// **'Additional project discovery directories'**
  String get settingsAgentDiscoveryPathsProject;

  /// No description provided for @settingsAgentDiscoveryPathsHint.
  ///
  /// In en, this message translates to:
  /// **'One path per line. These paths are only scanned to discover and migrate existing Skills.'**
  String get settingsAgentDiscoveryPathsHint;

  /// No description provided for @settingsAgentNoCustom.
  ///
  /// In en, this message translates to:
  /// **'No custom Agents yet.'**
  String get settingsAgentNoCustom;

  /// No description provided for @settingsAgentDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this Agent configuration? Existing files and activation links will not be deleted.'**
  String get settingsAgentDeleteConfirm;

  /// No description provided for @settingsAgentInvalidPath.
  ///
  /// In en, this message translates to:
  /// **'Configure this device with an absolute global path or a safe relative project path. Additional discovery paths require a directory for the same scope.'**
  String get settingsAgentInvalidPath;

  /// No description provided for @settingsAgentBusy.
  ///
  /// In en, this message translates to:
  /// **'Agent configuration is busy. Try again when the current operation finishes.'**
  String get settingsAgentBusy;

  /// No description provided for @settingsAgentReloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Agent configuration could not be applied. The previous configuration remains active.'**
  String get settingsAgentReloadFailed;

  /// No description provided for @translationSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translationSettingsTitle;

  /// No description provided for @translationSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure the single active Provider profile. Skill content is sent only after you confirm each translation.'**
  String get translationSettingsDescription;

  /// No description provided for @translationProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get translationProvider;

  /// No description provided for @translationProviderOpenAI.
  ///
  /// In en, this message translates to:
  /// **'OpenAI compatible'**
  String get translationProviderOpenAI;

  /// No description provided for @translationProviderAnthropic.
  ///
  /// In en, this message translates to:
  /// **'Anthropic'**
  String get translationProviderAnthropic;

  /// No description provided for @translationEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get translationEndpoint;

  /// No description provided for @translationModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get translationModel;

  /// No description provided for @translationTargetLanguage.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get translationTargetLanguage;

  /// No description provided for @translationApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get translationApiKey;

  /// No description provided for @translationApiKeyStored.
  ///
  /// In en, this message translates to:
  /// **'Stored securely — enter a value only to replace it'**
  String get translationApiKeyStored;

  /// No description provided for @translationApiKeyOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional for local OpenAI-compatible endpoints'**
  String get translationApiKeyOptional;

  /// No description provided for @translationAdvancedShow.
  ///
  /// In en, this message translates to:
  /// **'Show advanced settings'**
  String get translationAdvancedShow;

  /// No description provided for @translationAdvancedHide.
  ///
  /// In en, this message translates to:
  /// **'Hide advanced settings'**
  String get translationAdvancedHide;

  /// No description provided for @translationProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get translationProtocol;

  /// No description provided for @translationCharacterBudget.
  ///
  /// In en, this message translates to:
  /// **'Character budget'**
  String get translationCharacterBudget;

  /// No description provided for @translationConcurrency.
  ///
  /// In en, this message translates to:
  /// **'Concurrency'**
  String get translationConcurrency;

  /// No description provided for @translationMaxOutputTokens.
  ///
  /// In en, this message translates to:
  /// **'Max output tokens'**
  String get translationMaxOutputTokens;

  /// No description provided for @translationOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get translationOptional;

  /// No description provided for @translationReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get translationReasoning;

  /// No description provided for @translationReasoningDescription.
  ///
  /// In en, this message translates to:
  /// **'Off by default so reasoning cannot consume translation output budget.'**
  String get translationReasoningDescription;

  /// No description provided for @translationSave.
  ///
  /// In en, this message translates to:
  /// **'Save translation settings'**
  String get translationSave;

  /// No description provided for @translationSettingsError.
  ///
  /// In en, this message translates to:
  /// **'Translation settings could not be saved. Check the values and try again.'**
  String get translationSettingsError;

  /// No description provided for @translationAction.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translationAction;

  /// No description provided for @translationCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel translation'**
  String get translationCancel;

  /// No description provided for @translationConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Translate this Skill?'**
  String get translationConfirmTitle;

  /// No description provided for @translationConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Skill text will be sent to this service.'**
  String get translationConfirmMessage;

  /// No description provided for @translationConfirmProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get translationConfirmProvider;

  /// No description provided for @translationConfirmEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint host'**
  String get translationConfirmEndpoint;

  /// No description provided for @translationConfirmTarget.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get translationConfirmTarget;

  /// No description provided for @translationScopeFullDocument.
  ///
  /// In en, this message translates to:
  /// **'Full Skill'**
  String get translationScopeFullDocument;

  /// No description provided for @translationScopeDescription.
  ///
  /// In en, this message translates to:
  /// **'Description only'**
  String get translationScopeDescription;

  /// No description provided for @translationDescriptionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No translatable SKILL.md description is available.'**
  String get translationDescriptionUnavailable;

  /// No description provided for @translationShowCached.
  ///
  /// In en, this message translates to:
  /// **'Show cached'**
  String get translationShowCached;

  /// No description provided for @translationConfigureFirst.
  ///
  /// In en, this message translates to:
  /// **'Configure a Translation Provider in Settings first.'**
  String get translationConfigureFirst;

  /// No description provided for @translationProviderOpenAIShort.
  ///
  /// In en, this message translates to:
  /// **'OpenAI compatible'**
  String get translationProviderOpenAIShort;

  /// No description provided for @translationProviderAnthropicShort.
  ///
  /// In en, this message translates to:
  /// **'Anthropic'**
  String get translationProviderAnthropicShort;

  /// No description provided for @translationShowOriginal.
  ///
  /// In en, this message translates to:
  /// **'Show original'**
  String get translationShowOriginal;

  /// No description provided for @translationDeleteCache.
  ///
  /// In en, this message translates to:
  /// **'Delete cache'**
  String get translationDeleteCache;

  /// No description provided for @projectRootsTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Project Directories'**
  String get projectRootsTitle;

  /// No description provided for @projectRootsDescription.
  ///
  /// In en, this message translates to:
  /// **'Registered roots are available for project-scoped activations.'**
  String get projectRootsDescription;

  /// No description provided for @projectRootsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Project Roots registered.'**
  String get projectRootsEmpty;

  /// No description provided for @projectRootsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Project Root'**
  String get projectRootsAdd;

  /// No description provided for @projectRootsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get projectRootsManage;

  /// No description provided for @projectRootsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove Project Root'**
  String get projectRootsRemove;

  /// No description provided for @projectRootsError.
  ///
  /// In en, this message translates to:
  /// **'The Project Root operation failed.'**
  String get projectRootsError;

  /// No description provided for @externalSkillsTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover existing Skills'**
  String get externalSkillsTitle;

  /// No description provided for @externalSkillsDescription.
  ///
  /// In en, this message translates to:
  /// **'Other tools installed these Skills in Agent folders. Take them over to update and activate them in SkillDeck.'**
  String get externalSkillsDescription;

  /// No description provided for @externalSkillsScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning known Agent locations…'**
  String get externalSkillsScanning;

  /// No description provided for @externalSkillsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No unmanaged Skills found'**
  String get externalSkillsEmpty;

  /// No description provided for @externalSkillsEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'All valid Skills in known Agent locations are already managed.'**
  String get externalSkillsEmptyDescription;

  /// No description provided for @externalSkillsRescan.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get externalSkillsRescan;

  /// No description provided for @externalSkillsAdoptCount.
  ///
  /// In en, this message translates to:
  /// **'Take over {count}'**
  String externalSkillsAdoptCount(Object count);

  /// No description provided for @externalSkillsAdopting.
  ///
  /// In en, this message translates to:
  /// **'Adopting Skills'**
  String get externalSkillsAdopting;

  /// No description provided for @externalSkillsCompletedCount.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} Skills completed.'**
  String externalSkillsCompletedCount(Object completed, Object total);

  /// No description provided for @externalSkillsSuccess.
  ///
  /// In en, this message translates to:
  /// **'Skills adopted'**
  String get externalSkillsSuccess;

  /// No description provided for @externalSkillsCancelled.
  ///
  /// In en, this message translates to:
  /// **'Adoption cancelled'**
  String get externalSkillsCancelled;

  /// No description provided for @externalSkillsPartial.
  ///
  /// In en, this message translates to:
  /// **'Adoption partially completed'**
  String get externalSkillsPartial;

  /// No description provided for @externalSkillsScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed'**
  String get externalSkillsScanFailed;

  /// No description provided for @externalSkillsAdoptionFailed.
  ///
  /// In en, this message translates to:
  /// **'Adoption failed'**
  String get externalSkillsAdoptionFailed;

  /// No description provided for @externalSkillsFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Skill could not be taken over} other{{count} Skills could not be taken over}}'**
  String externalSkillsFailedTitle(int count);

  /// No description provided for @externalSkillsFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Found {count, plural, =1{1 existing Skill} other{{count} existing Skills}}'**
  String externalSkillsFoundTitle(int count);

  /// No description provided for @externalSkillsSummaryTotal.
  ///
  /// In en, this message translates to:
  /// **'Found'**
  String get externalSkillsSummaryTotal;

  /// No description provided for @externalSkillsSummaryReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to take over'**
  String get externalSkillsSummaryReady;

  /// No description provided for @externalSkillsSummaryConflicts.
  ///
  /// In en, this message translates to:
  /// **'Need a version'**
  String get externalSkillsSummaryConflicts;

  /// No description provided for @externalSkillsSummaryCount.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String externalSkillsSummaryCount(int count);

  /// No description provided for @externalSkillsDecideTitle.
  ///
  /// In en, this message translates to:
  /// **'Resolve conflicts'**
  String get externalSkillsDecideTitle;

  /// No description provided for @externalSkillsDecideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A Skill with the same name differs between Agents'**
  String get externalSkillsDecideSubtitle;

  /// No description provided for @externalSkillsChooseVersion.
  ///
  /// In en, this message translates to:
  /// **'Choose version'**
  String get externalSkillsChooseVersion;

  /// No description provided for @externalSkillsVersionMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep the version from'**
  String get externalSkillsVersionMenuTitle;

  /// No description provided for @externalSkillsOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Show in Finder'**
  String get externalSkillsOpenFolder;

  /// No description provided for @externalSkillsRestTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more can be taken over directly} other{{count} more can be taken over directly}}'**
  String externalSkillsRestTitle(int count);

  /// No description provided for @externalSkillsReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 can be taken over directly} other{{count} can be taken over directly}}'**
  String externalSkillsReadyTitle(int count);

  /// No description provided for @externalSkillsNamesMore.
  ///
  /// In en, this message translates to:
  /// **'{names}, and more'**
  String externalSkillsNamesMore(String names);

  /// No description provided for @externalSkillsNameSeparator.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get externalSkillsNameSeparator;

  /// No description provided for @externalSkillsViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get externalSkillsViewAll;

  /// No description provided for @externalSkillsChooseIndividually.
  ///
  /// In en, this message translates to:
  /// **'Choose individually'**
  String get externalSkillsChooseIndividually;

  /// No description provided for @externalSkillsAdoptAll.
  ///
  /// In en, this message translates to:
  /// **'Take over all {count}'**
  String externalSkillsAdoptAll(int count);

  /// No description provided for @externalSkillsSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get externalSkillsSelectAll;

  /// No description provided for @externalSkillsAgentsColumn.
  ///
  /// In en, this message translates to:
  /// **'Found in'**
  String get externalSkillsAgentsColumn;

  /// No description provided for @externalSkillsConflictCopies.
  ///
  /// In en, this message translates to:
  /// **'{count} copies differ'**
  String externalSkillsConflictCopies(int count);

  /// No description provided for @externalSkillsSharedFolder.
  ///
  /// In en, this message translates to:
  /// **'Shared folder'**
  String get externalSkillsSharedFolder;

  /// No description provided for @externalSkillsSharedBy.
  ///
  /// In en, this message translates to:
  /// **'Used by {count} Agents'**
  String externalSkillsSharedBy(int count);

  /// No description provided for @externalSkillsVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking for changes…'**
  String get externalSkillsVerifying;

  /// No description provided for @errorSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The source is unavailable.'**
  String get errorSourceUnavailable;

  /// No description provided for @errorAuthenticationRequired.
  ///
  /// In en, this message translates to:
  /// **'The repository doesn\'t exist or is private. Check the address; a private repository needs Git installed and signed in.'**
  String get errorAuthenticationRequired;

  /// No description provided for @errorGitUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Git is unavailable on this device. Public HTTPS repositories install without Git; SSH and private repositories need it.'**
  String get errorGitUnavailable;

  /// No description provided for @errorGitFailed.
  ///
  /// In en, this message translates to:
  /// **'The Git operation failed. Check the source address and try again.'**
  String get errorGitFailed;

  /// No description provided for @errorGitFileCountExceeded.
  ///
  /// In en, this message translates to:
  /// **'The repository exceeds the scan limit. Specify a repository subpath and try again.'**
  String get errorGitFileCountExceeded;

  /// No description provided for @errorDeveloperToolsRequired.
  ///
  /// In en, this message translates to:
  /// **'Git needs the macOS Command Line Developer Tools. Open Settings › Environment check to finish setup.'**
  String get errorDeveloperToolsRequired;

  /// No description provided for @errorTransportRejected.
  ///
  /// In en, this message translates to:
  /// **'The source address was rejected for safety.'**
  String get errorTransportRejected;

  /// No description provided for @errorArchiveInvalid.
  ///
  /// In en, this message translates to:
  /// **'The downloaded archive is invalid.'**
  String get errorArchiveInvalid;

  /// No description provided for @errorDigestMismatch.
  ///
  /// In en, this message translates to:
  /// **'The source content did not pass integrity verification. Check the source and try again.'**
  String get errorDigestMismatch;

  /// No description provided for @errorSkillNotFound.
  ///
  /// In en, this message translates to:
  /// **'The skill no longer exists.'**
  String get errorSkillNotFound;

  /// No description provided for @errorStaleSnapshot.
  ///
  /// In en, this message translates to:
  /// **'The repository changed. Refresh and review the action again.'**
  String get errorStaleSnapshot;

  /// No description provided for @errorInvalidSkill.
  ///
  /// In en, this message translates to:
  /// **'The source contains an invalid or unsupported skill.'**
  String get errorInvalidSkill;

  /// No description provided for @errorSkillContentLimitExceeded.
  ///
  /// In en, this message translates to:
  /// **'The skill content exceeds the supported file-count or size limit.'**
  String get errorSkillContentLimitExceeded;

  /// No description provided for @errorInvalidSource.
  ///
  /// In en, this message translates to:
  /// **'This source is unsupported.'**
  String get errorInvalidSource;

  /// No description provided for @errorDuplicateSkill.
  ///
  /// In en, this message translates to:
  /// **'The skill conflicts with an installed Skill Slot.'**
  String get errorDuplicateSkill;

  /// No description provided for @errorDuplicateSkillsWithinSource.
  ///
  /// In en, this message translates to:
  /// **'This source contains multiple skills with the same name. Specify a particular subpath.'**
  String get errorDuplicateSkillsWithinSource;

  /// No description provided for @errorSourceReplacementRequired.
  ///
  /// In en, this message translates to:
  /// **'A managed Skill already uses this Skill Slot. Replace its source to continue.'**
  String get errorSourceReplacementRequired;

  /// No description provided for @errorExternalSkillConflict.
  ///
  /// In en, this message translates to:
  /// **'An unmanaged skill already occupies this activation target. Refresh and review it before continuing.'**
  String get errorExternalSkillConflict;

  /// No description provided for @errorActivation.
  ///
  /// In en, this message translates to:
  /// **'The activation target is unavailable or unsupported.'**
  String get errorActivation;

  /// No description provided for @errorAdoptionTargetOccupied.
  ///
  /// In en, this message translates to:
  /// **'Something else is already in this Skill\'s folder. Move it away, then try again.'**
  String get errorAdoptionTargetOccupied;

  /// No description provided for @errorAdoptionTargetOccupiedFile.
  ///
  /// In en, this message translates to:
  /// **'A file is in the way of this Skill\'s folder. Move it elsewhere, then try again: {path}'**
  String errorAdoptionTargetOccupiedFile(Object path);

  /// No description provided for @errorAdoptionTargetOccupiedInvalidSkill.
  ///
  /// In en, this message translates to:
  /// **'This Skill\'s folder holds a SKILL.md that is not a valid Skill. Fix or move that folder, then try again: {path}'**
  String errorAdoptionTargetOccupiedInvalidSkill(Object path);

  /// No description provided for @errorAdoptionTargetOccupiedDirectoryWithContent.
  ///
  /// In en, this message translates to:
  /// **'This Skill\'s folder already holds other files. Move that folder elsewhere, then try again: {path}'**
  String errorAdoptionTargetOccupiedDirectoryWithContent(Object path);

  /// No description provided for @errorAdoptionTargetOccupiedOtherSkill.
  ///
  /// In en, this message translates to:
  /// **'This Skill\'s folder holds a different Skill. Rename or move one of them, then try again: {path}'**
  String errorAdoptionTargetOccupiedOtherSkill(Object path);

  /// No description provided for @errorAdoptionTargetOccupiedSameSlotSkill.
  ///
  /// In en, this message translates to:
  /// **'This Skill\'s folder holds another copy of it that was not part of the review. Move that copy elsewhere, then try again: {path}'**
  String errorAdoptionTargetOccupiedSameSlotSkill(Object path);

  /// No description provided for @errorAdoptionTargetOccupiedLink.
  ///
  /// In en, this message translates to:
  /// **'This Skill\'s folder is a link to something else. Remove the link, then try again: {path}'**
  String errorAdoptionTargetOccupiedLink(Object path);

  /// No description provided for @errorProjectRoot.
  ///
  /// In en, this message translates to:
  /// **'The selected Project Root was removed.'**
  String get errorProjectRoot;

  /// No description provided for @errorInvalidProjectRoot.
  ///
  /// In en, this message translates to:
  /// **'The selected project directory is invalid.'**
  String get errorInvalidProjectRoot;

  /// No description provided for @errorProjectRootConflict.
  ///
  /// In en, this message translates to:
  /// **'The project directory conflicts with an existing registration.'**
  String get errorProjectRootConflict;

  /// No description provided for @errorAgent.
  ///
  /// In en, this message translates to:
  /// **'The selected Agent is unavailable.'**
  String get errorAgent;

  /// No description provided for @errorDuplicateAgentId.
  ///
  /// In en, this message translates to:
  /// **'An Agent with this identifier already exists.'**
  String get errorDuplicateAgentId;

  /// No description provided for @errorPersonalTagNotFound.
  ///
  /// In en, this message translates to:
  /// **'The personal tag no longer exists.'**
  String get errorPersonalTagNotFound;

  /// No description provided for @errorDuplicatePersonalTag.
  ///
  /// In en, this message translates to:
  /// **'A personal tag with this name already exists.'**
  String get errorDuplicatePersonalTag;

  /// No description provided for @errorRepositoryBusy.
  ///
  /// In en, this message translates to:
  /// **'Another operation is using the repository.'**
  String get errorRepositoryBusy;

  /// No description provided for @errorOperationCancelled.
  ///
  /// In en, this message translates to:
  /// **'The operation was cancelled.'**
  String get errorOperationCancelled;

  /// No description provided for @errorRepositoryState.
  ///
  /// In en, this message translates to:
  /// **'The repository state needs recovery or is unsupported.'**
  String get errorRepositoryState;

  /// No description provided for @errorControlPlaneCorrupt.
  ///
  /// In en, this message translates to:
  /// **'The workspace control data is damaged. Changes are blocked to protect your skills.'**
  String get errorControlPlaneCorrupt;

  /// No description provided for @errorUnsupportedWorkspaceVersion.
  ///
  /// In en, this message translates to:
  /// **'This workspace version is not supported by this version of SkillDeck. Update SkillDeck and try again.'**
  String get errorUnsupportedWorkspaceVersion;

  /// No description provided for @errorWorkspaceMaintenanceFailed.
  ///
  /// In en, this message translates to:
  /// **'Workspace maintenance failed. Changes are blocked until recovery completes.'**
  String get errorWorkspaceMaintenanceFailed;

  /// No description provided for @errorMigrationFailed.
  ///
  /// In en, this message translates to:
  /// **'The workspace could not be upgraded safely. No further changes were made.'**
  String get errorMigrationFailed;

  /// No description provided for @errorRevisionStoreCorrupt.
  ///
  /// In en, this message translates to:
  /// **'The skill revision store is damaged. Replace the source or delete the affected skill to recover safely.'**
  String get errorRevisionStoreCorrupt;

  /// No description provided for @errorDirtyDraftResolutionRequired.
  ///
  /// In en, this message translates to:
  /// **'This skill has unpublished changes. Publish or discard them before continuing.'**
  String get errorDirtyDraftResolutionRequired;

  /// No description provided for @errorUpdateCandidateResolutionRequired.
  ///
  /// In en, this message translates to:
  /// **'This skill has an unresolved update candidate. Resolve or abandon it before continuing.'**
  String get errorUpdateCandidateResolutionRequired;

  /// No description provided for @errorNameChangeNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'A managed skill cannot change its declared name. Restore the original name before continuing.'**
  String get errorNameChangeNotAllowed;

  /// No description provided for @errorFinalizationRecoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'The changes were committed, but recovery could not finish. Retry recovery before making more changes.'**
  String get errorFinalizationRecoveryFailed;

  /// No description provided for @workspaceIntegrityRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Skill recovery required'**
  String get workspaceIntegrityRecoveryTitle;

  /// No description provided for @workspaceIntegrityRecoveryMessage.
  ///
  /// In en, this message translates to:
  /// **'This skill\'s revision data could not be verified. Updates, activations, favorites, and notes are disabled. Replace the source or delete the skill to recover safely.'**
  String get workspaceIntegrityRecoveryMessage;

  /// No description provided for @workspaceIntegrityValidating.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get workspaceIntegrityValidating;

  /// No description provided for @workspaceIntegrityDriftPending.
  ///
  /// In en, this message translates to:
  /// **'Changed externally'**
  String get workspaceIntegrityDriftPending;

  /// No description provided for @workspaceIntegrityRepairFailed.
  ///
  /// In en, this message translates to:
  /// **'Repair failed'**
  String get workspaceIntegrityRepairFailed;

  /// No description provided for @workspaceIntegrityStoreCorrupt.
  ///
  /// In en, this message translates to:
  /// **'Recovery required'**
  String get workspaceIntegrityStoreCorrupt;

  /// No description provided for @errorRollback.
  ///
  /// In en, this message translates to:
  /// **'The operation could not be restored safely.'**
  String get errorRollback;

  /// No description provided for @errorIo.
  ///
  /// In en, this message translates to:
  /// **'A local file operation failed.'**
  String get errorIo;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'The operation failed.'**
  String get errorUnknown;

  /// No description provided for @acquisitionTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a skill'**
  String get acquisitionTitle;

  /// No description provided for @acquisitionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Install from a local folder, a Git repo, or a URL.'**
  String get acquisitionSubtitle;

  /// No description provided for @acquisitionSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get acquisitionSource;

  /// No description provided for @acquisitionSkillsFound.
  ///
  /// In en, this message translates to:
  /// **'Skills found'**
  String get acquisitionSkillsFound;

  /// No description provided for @acquisitionSelectAllSkills.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get acquisitionSelectAllSkills;

  /// No description provided for @acquisitionNoValidSkills.
  ///
  /// In en, this message translates to:
  /// **'No valid skills found.'**
  String get acquisitionNoValidSkills;

  /// No description provided for @acquisitionScope.
  ///
  /// In en, this message translates to:
  /// **'SCOPE'**
  String get acquisitionScope;

  /// No description provided for @acquisitionAgents.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get acquisitionAgents;

  /// No description provided for @acquisitionGlobalDescription.
  ///
  /// In en, this message translates to:
  /// **'Activates for all projects on this device.'**
  String get acquisitionGlobalDescription;

  /// No description provided for @acquisitionProjectDescription.
  ///
  /// In en, this message translates to:
  /// **'Activates for a specific registered Project Root.'**
  String get acquisitionProjectDescription;

  /// No description provided for @acquisitionRegisterProjectRoot.
  ///
  /// In en, this message translates to:
  /// **'Register a Project Root before project activation.'**
  String get acquisitionRegisterProjectRoot;

  /// No description provided for @acquisitionManageProjectRoots.
  ///
  /// In en, this message translates to:
  /// **'Manage Project Roots'**
  String get acquisitionManageProjectRoots;

  /// No description provided for @acquisitionStoreOnly.
  ///
  /// In en, this message translates to:
  /// **'Store only'**
  String get acquisitionStoreOnly;

  /// No description provided for @acquisitionDetectedCount.
  ///
  /// In en, this message translates to:
  /// **'/ {count} detected'**
  String acquisitionDetectedCount(Object count);

  /// No description provided for @acquisitionAddAgent.
  ///
  /// In en, this message translates to:
  /// **'Add Agent'**
  String get acquisitionAddAgent;

  /// No description provided for @acquisitionInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing skills…'**
  String get acquisitionInstalling;

  /// No description provided for @acquisitionPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing source…'**
  String get acquisitionPreparing;

  /// No description provided for @acquisitionInspecting.
  ///
  /// In en, this message translates to:
  /// **'Inspecting source…'**
  String get acquisitionInspecting;

  /// No description provided for @acquisitionWaitingForRepository.
  ///
  /// In en, this message translates to:
  /// **'Waiting for repository…'**
  String get acquisitionWaitingForRepository;

  /// No description provided for @acquisitionPlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning changes…'**
  String get acquisitionPlanning;

  /// No description provided for @acquisitionApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying changes…'**
  String get acquisitionApplying;

  /// No description provided for @acquisitionRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring previous state…'**
  String get acquisitionRestoring;

  /// No description provided for @acquisitionFinishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing…'**
  String get acquisitionFinishing;

  /// No description provided for @acquisitionErrorResolve.
  ///
  /// In en, this message translates to:
  /// **'Enter a supported local, Git, or HTTPS source.'**
  String get acquisitionErrorResolve;

  /// No description provided for @acquisitionErrorInspect.
  ///
  /// In en, this message translates to:
  /// **'The source could not be inspected.'**
  String get acquisitionErrorInspect;

  /// No description provided for @acquisitionErrorInstall.
  ///
  /// In en, this message translates to:
  /// **'The skills could not be installed.'**
  String get acquisitionErrorInstall;

  /// No description provided for @acquisitionGoToEnvironmentSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get acquisitionGoToEnvironmentSettings;

  /// No description provided for @acquisitionErrorRefresh.
  ///
  /// In en, this message translates to:
  /// **'The skills were installed, but the repository could not be refreshed.'**
  String get acquisitionErrorRefresh;

  /// No description provided for @acquisitionSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get acquisitionSelect;

  /// No description provided for @acquisitionActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get acquisitionActivate;

  /// No description provided for @acquisitionLocalFolder.
  ///
  /// In en, this message translates to:
  /// **'Local Folder'**
  String get acquisitionLocalFolder;

  /// No description provided for @acquisitionLocalFolderDescription.
  ///
  /// In en, this message translates to:
  /// **'A folder containing one or more skills.'**
  String get acquisitionLocalFolderDescription;

  /// No description provided for @acquisitionGitRepository.
  ///
  /// In en, this message translates to:
  /// **'Git Repository'**
  String get acquisitionGitRepository;

  /// No description provided for @acquisitionGitRepositoryDescription.
  ///
  /// In en, this message translates to:
  /// **'GitHub, GitLab, or any Git remote.'**
  String get acquisitionGitRepositoryDescription;

  /// No description provided for @acquisitionWebSourceUrl.
  ///
  /// In en, this message translates to:
  /// **'Web Source URL'**
  String get acquisitionWebSourceUrl;

  /// No description provided for @acquisitionWebSourceUrlDescription.
  ///
  /// In en, this message translates to:
  /// **'A well-known HTTPS skills endpoint.'**
  String get acquisitionWebSourceUrlDescription;

  /// No description provided for @acquisitionFolderPath.
  ///
  /// In en, this message translates to:
  /// **'FOLDER PATH'**
  String get acquisitionFolderPath;

  /// No description provided for @acquisitionRepositoryUrl.
  ///
  /// In en, this message translates to:
  /// **'REPOSITORY URL'**
  String get acquisitionRepositoryUrl;

  /// No description provided for @acquisitionSourceUrl.
  ///
  /// In en, this message translates to:
  /// **'SOURCE URL'**
  String get acquisitionSourceUrl;

  /// No description provided for @acquisitionFolderPathHint.
  ///
  /// In en, this message translates to:
  /// **'/path/to/skills'**
  String get acquisitionFolderPathHint;

  /// No description provided for @acquisitionRepositoryUrlHint.
  ///
  /// In en, this message translates to:
  /// **'github.com/owner/repo or owner/repo'**
  String get acquisitionRepositoryUrlHint;

  /// No description provided for @acquisitionGitRef.
  ///
  /// In en, this message translates to:
  /// **'GIT REF'**
  String get acquisitionGitRef;

  /// No description provided for @acquisitionGitRefHint.
  ///
  /// In en, this message translates to:
  /// **'main, tag, or commit (optional)'**
  String get acquisitionGitRefHint;

  /// No description provided for @acquisitionGitSubpath.
  ///
  /// In en, this message translates to:
  /// **'REPOSITORY SUBPATH'**
  String get acquisitionGitSubpath;

  /// No description provided for @acquisitionGitSubpathHint.
  ///
  /// In en, this message translates to:
  /// **'path/to/skills (optional)'**
  String get acquisitionGitSubpathHint;

  /// No description provided for @acquisitionSourceUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://skills.example.com'**
  String get acquisitionSourceUrlHint;

  /// No description provided for @acquisitionMultipleSkillsHint.
  ///
  /// In en, this message translates to:
  /// **'You can install multiple skills from one repository at once.'**
  String get acquisitionMultipleSkillsHint;

  /// No description provided for @acquisitionStep.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of 3'**
  String acquisitionStep(Object current);

  /// No description provided for @acquisitionInstall.
  ///
  /// In en, this message translates to:
  /// **'Install {count} skill{plural}'**
  String acquisitionInstall(Object count, Object plural);

  /// No description provided for @notificationInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get notificationInfoTitle;

  /// No description provided for @notificationSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get notificationSuccessTitle;

  /// No description provided for @notificationWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Completed with a warning'**
  String get notificationWarningTitle;

  /// No description provided for @notificationErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get notificationErrorTitle;

  /// No description provided for @notificationRepositoryRefreshed.
  ///
  /// In en, this message translates to:
  /// **'The repository was refreshed.'**
  String get notificationRepositoryRefreshed;

  /// No description provided for @notificationSkillsInstalled.
  ///
  /// In en, this message translates to:
  /// **'The selected skills were installed.'**
  String get notificationSkillsInstalled;

  /// No description provided for @notificationActivationEnabled.
  ///
  /// In en, this message translates to:
  /// **'The skill is now active.'**
  String get notificationActivationEnabled;

  /// No description provided for @notificationActivationDisabled.
  ///
  /// In en, this message translates to:
  /// **'The skill is now inactive.'**
  String get notificationActivationDisabled;

  /// No description provided for @notificationSkillFavorited.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites.'**
  String get notificationSkillFavorited;

  /// No description provided for @notificationSkillUnfavorited.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites.'**
  String get notificationSkillUnfavorited;

  /// No description provided for @notificationSkillUpdated.
  ///
  /// In en, this message translates to:
  /// **'The skill was updated.'**
  String get notificationSkillUpdated;

  /// No description provided for @notificationSkillRemoved.
  ///
  /// In en, this message translates to:
  /// **'The skill was deleted.'**
  String get notificationSkillRemoved;

  /// No description provided for @notificationUpdatesApplied.
  ///
  /// In en, this message translates to:
  /// **'The selected updates were applied.'**
  String get notificationUpdatesApplied;

  /// No description provided for @notificationProjectRootRegistered.
  ///
  /// In en, this message translates to:
  /// **'The Project Root was registered.'**
  String get notificationProjectRootRegistered;

  /// No description provided for @notificationProjectRootUnregistered.
  ///
  /// In en, this message translates to:
  /// **'The Project Root was removed.'**
  String get notificationProjectRootUnregistered;

  /// No description provided for @notificationExternalSkillsAdopted.
  ///
  /// In en, this message translates to:
  /// **'The selected external Skills are now managed.'**
  String get notificationExternalSkillsAdopted;

  /// No description provided for @notificationExternalSkillsPartiallyAdopted.
  ///
  /// In en, this message translates to:
  /// **'Some Skills are now managed. The others could not be taken over.'**
  String get notificationExternalSkillsPartiallyAdopted;

  /// No description provided for @notificationTranslationTitle.
  ///
  /// In en, this message translates to:
  /// **'Translating'**
  String get notificationTranslationTitle;

  /// No description provided for @notificationTranslationStarted.
  ///
  /// In en, this message translates to:
  /// **'Translation started. The document will update block by block.'**
  String get notificationTranslationStarted;

  /// No description provided for @notificationTranslationProgress.
  ///
  /// In en, this message translates to:
  /// **'Translated {completed} of {total} blocks.'**
  String notificationTranslationProgress(Object completed, Object total);

  /// No description provided for @notificationTranslationCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling translation…'**
  String get notificationTranslationCancelling;

  /// No description provided for @notificationTranslationCompleted.
  ///
  /// In en, this message translates to:
  /// **'The document was translated successfully.'**
  String get notificationTranslationCompleted;

  /// No description provided for @notificationTranslationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Translation was cancelled and the previous content was restored.'**
  String get notificationTranslationCancelled;

  /// No description provided for @notificationTranslationFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed. The previous translation or original content has been restored.'**
  String get notificationTranslationFailed;

  /// No description provided for @notificationTranslationCacheDeleted.
  ///
  /// In en, this message translates to:
  /// **'The cached translation was deleted.'**
  String get notificationTranslationCacheDeleted;

  /// No description provided for @notificationTranslationSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Translation settings saved.'**
  String get notificationTranslationSettingsSaved;

  /// No description provided for @notificationFinalizationPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Finishing recovery'**
  String get notificationFinalizationPendingTitle;

  /// No description provided for @notificationFinalizationPending.
  ///
  /// In en, this message translates to:
  /// **'Changes were committed. Finishing recovery…'**
  String get notificationFinalizationPending;

  /// No description provided for @notificationFinalizationRecovered.
  ///
  /// In en, this message translates to:
  /// **'Recovery is complete.'**
  String get notificationFinalizationRecovered;

  /// No description provided for @workspaceFinalizationRetryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recovery needs attention'**
  String get workspaceFinalizationRetryTitle;

  /// No description provided for @workspaceFinalizationRetryMessage.
  ///
  /// In en, this message translates to:
  /// **'Committed changes are safe, but cleanup could not finish. Retry recovery before making more workspace changes.'**
  String get workspaceFinalizationRetryMessage;

  /// No description provided for @workspaceFinalizationRetryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry recovery'**
  String get workspaceFinalizationRetryAction;

  /// No description provided for @notificationUpdateCheckStarted.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get notificationUpdateCheckStarted;

  /// No description provided for @notificationUpdateCheckCurrent.
  ///
  /// In en, this message translates to:
  /// **'This skill is already up to date.'**
  String get notificationUpdateCheckCurrent;

  /// No description provided for @notificationUpdateCheckAvailable.
  ///
  /// In en, this message translates to:
  /// **'An update is available for this skill.'**
  String get notificationUpdateCheckAvailable;

  /// No description provided for @notificationUpdateCheckUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The source could not be reached, so the update status is unknown.'**
  String get notificationUpdateCheckUnavailable;

  /// No description provided for @notificationUpdateCheckUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This source does not support update checks.'**
  String get notificationUpdateCheckUnsupported;

  /// No description provided for @notificationUpdateCheckResolutionRequired.
  ///
  /// In en, this message translates to:
  /// **'This skill needs resolution on the Updates page before it can be updated.'**
  String get notificationUpdateCheckResolutionRequired;

  /// No description provided for @notificationUpdateCandidateAbandoned.
  ///
  /// In en, this message translates to:
  /// **'The update candidate was abandoned.'**
  String get notificationUpdateCandidateAbandoned;

  /// No description provided for @notificationOperationCancelled.
  ///
  /// In en, this message translates to:
  /// **'The operation was cancelled.'**
  String get notificationOperationCancelled;

  /// No description provided for @notificationCompletedWithWarnings.
  ///
  /// In en, this message translates to:
  /// **'The operation completed, but some items need attention.'**
  String get notificationCompletedWithWarnings;

  /// No description provided for @notificationShowDetails.
  ///
  /// In en, this message translates to:
  /// **'Show details'**
  String get notificationShowDetails;

  /// No description provided for @ownershipRepairTitle.
  ///
  /// In en, this message translates to:
  /// **'Repair Agent folder ownership?'**
  String get ownershipRepairTitle;

  /// No description provided for @ownershipRepairMessage.
  ///
  /// In en, this message translates to:
  /// **'Some Agent Skills folders belong to another user. SkillDeck can restore them to your account before continuing.'**
  String get ownershipRepairMessage;

  /// No description provided for @ownershipRepairSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'macOS will ask for an administrator password. SkillDeck only changes the owner of the folders listed below; it does not change their permissions.'**
  String get ownershipRepairSystemPrompt;

  /// No description provided for @ownershipRepairCustomAgent.
  ///
  /// In en, this message translates to:
  /// **'Custom Agent — confirm this path'**
  String get ownershipRepairCustomAgent;

  /// No description provided for @ownershipRepairBuiltInAgent.
  ///
  /// In en, this message translates to:
  /// **'Built-in Agent'**
  String get ownershipRepairBuiltInAgent;

  /// No description provided for @ownershipRepairCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get ownershipRepairCancel;

  /// No description provided for @ownershipRepairContinue.
  ///
  /// In en, this message translates to:
  /// **'Repair and continue'**
  String get ownershipRepairContinue;

  /// No description provided for @errorAgentRootOwnership.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck could not safely repair the Agent Skills folder ownership. Review the folder path and permissions, then try again.'**
  String get errorAgentRootOwnership;

  /// No description provided for @errorAgentRootOwnershipOutsideHome.
  ///
  /// In en, this message translates to:
  /// **'An Agent Skills folder resolves outside your home directory and cannot be repaired automatically: {path}'**
  String errorAgentRootOwnershipOutsideHome(Object path);

  /// No description provided for @errorAgentRootOwnershipNotDirectory.
  ///
  /// In en, this message translates to:
  /// **'The configured Agent Skills path is not a folder: {path}'**
  String errorAgentRootOwnershipNotDirectory(Object path);

  /// No description provided for @errorAgentRootOwnershipInspectionFailed.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck could not inspect this Agent Skills folder. It may be a broken or circular link: {path}'**
  String errorAgentRootOwnershipInspectionFailed(Object path);

  /// No description provided for @errorAgentRootOwnershipAuthorizationRejected.
  ///
  /// In en, this message translates to:
  /// **'macOS did not authorize the Agent Skills ownership repair.'**
  String get errorAgentRootOwnershipAuthorizationRejected;

  /// No description provided for @errorAgentRootOwnershipRepairFailed.
  ///
  /// In en, this message translates to:
  /// **'macOS could not change the owner of the selected Agent Skills folders.'**
  String get errorAgentRootOwnershipRepairFailed;

  /// No description provided for @errorAgentRootOwnershipStillInvalid.
  ///
  /// In en, this message translates to:
  /// **'Some entries are still owned by another user after repair: {path}'**
  String errorAgentRootOwnershipStillInvalid(Object path);

  /// No description provided for @errorAgentRootOwnershipBlockedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Agent Skills folders need fixing before SkillDeck can continue.'**
  String errorAgentRootOwnershipBlockedCount(int count);

  /// No description provided for @errorAgentRootOwnershipStillInvalidCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Agent Skills folders still have problems after the repair.'**
  String errorAgentRootOwnershipStillInvalidCount(int count);

  /// No description provided for @errorAgentRootOwnershipUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Automatic Agent Skills ownership repair is not supported on this device.'**
  String get errorAgentRootOwnershipUnsupported;

  /// No description provided for @stubComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon: {section}'**
  String stubComingSoon(Object section);

  /// No description provided for @skillDriftReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Review outside changes'**
  String get skillDriftReviewAction;

  /// No description provided for @skillDriftReviewTooltip.
  ///
  /// In en, this message translates to:
  /// **'This skill was changed outside SkillDeck. Updates, activation, and editing are paused until you resolve it.'**
  String get skillDriftReviewTooltip;

  /// No description provided for @skillDriftWhatChanged.
  ///
  /// In en, this message translates to:
  /// **'What changed'**
  String get skillDriftWhatChanged;

  /// No description provided for @skillDriftHowToResolve.
  ///
  /// In en, this message translates to:
  /// **'How to resolve'**
  String get skillDriftHowToResolve;

  /// No description provided for @skillDriftLocationAgentFolder.
  ///
  /// In en, this message translates to:
  /// **'Agent folder'**
  String get skillDriftLocationAgentFolder;

  /// No description provided for @skillDriftLinkReplaced.
  ///
  /// In en, this message translates to:
  /// **'The link to SkillDeck was replaced with a regular file or folder'**
  String get skillDriftLinkReplaced;

  /// No description provided for @skillDriftFolderReplaced.
  ///
  /// In en, this message translates to:
  /// **'The folder was replaced with a link or file'**
  String get skillDriftFolderReplaced;

  /// No description provided for @skillDriftKeepOption.
  ///
  /// In en, this message translates to:
  /// **'Keep the changes in {location}'**
  String skillDriftKeepOption(String location);

  /// No description provided for @skillDriftKeepOptionDetail.
  ///
  /// In en, this message translates to:
  /// **'Saved as a new version and synced to every location. You can undo it from History.'**
  String get skillDriftKeepOptionDetail;

  /// No description provided for @skillDriftRestoreOptionDetail.
  ///
  /// In en, this message translates to:
  /// **'Discard the outside changes and return every location to the current version.'**
  String get skillDriftRestoreOptionDetail;

  /// No description provided for @skillDriftChooseOption.
  ///
  /// In en, this message translates to:
  /// **'Choose an option'**
  String get skillDriftChooseOption;

  /// No description provided for @skillDriftDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Review outside changes'**
  String get skillDriftDialogTitle;

  /// No description provided for @skillDriftReviewDescription.
  ///
  /// In en, this message translates to:
  /// **'These locations were changed outside SkillDeck. Choose which content to keep.'**
  String get skillDriftReviewDescription;

  /// No description provided for @skillDriftLocationRepositoryCopy.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck\'s stored copy'**
  String get skillDriftLocationRepositoryCopy;

  /// No description provided for @skillDriftContentChanged.
  ///
  /// In en, this message translates to:
  /// **'Files were edited'**
  String get skillDriftContentChanged;

  /// No description provided for @skillDriftWrongLinkTarget.
  ///
  /// In en, this message translates to:
  /// **'The link now points somewhere else'**
  String get skillDriftWrongLinkTarget;

  /// No description provided for @skillDriftKeepExternal.
  ///
  /// In en, this message translates to:
  /// **'Keep these changes'**
  String get skillDriftKeepExternal;

  /// No description provided for @skillDriftRestoreManaged.
  ///
  /// In en, this message translates to:
  /// **'Restore SkillDeck version'**
  String get skillDriftRestoreManaged;

  /// No description provided for @skillDriftRestoreWarning.
  ///
  /// In en, this message translates to:
  /// **'Outside changes will be overwritten and are not backed up. Export them first if you need them.'**
  String get skillDriftRestoreWarning;

  /// No description provided for @skillDriftExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get skillDriftExportAction;

  /// No description provided for @skillDriftExported.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String skillDriftExported(String path);

  /// No description provided for @skillDriftStale.
  ///
  /// In en, this message translates to:
  /// **'The skill or external files changed since this review. Refresh and review again before choosing an action.'**
  String get skillDriftStale;

  /// No description provided for @skillDriftKeepUnavailable.
  ///
  /// In en, this message translates to:
  /// **'These changes can\'t be saved as a new version, so only the SkillDeck version can be restored.'**
  String get skillDriftKeepUnavailable;

  /// No description provided for @skillDriftNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No external changes remain. Restoring will leave this skill unchanged.'**
  String get skillDriftNoChanges;

  /// No description provided for @removeSkillDriftWarning.
  ///
  /// In en, this message translates to:
  /// **'This skill has external changes. Deleting it will permanently discard changes at its managed locations.'**
  String get removeSkillDriftWarning;

  /// No description provided for @errorDriftResolutionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This action is unavailable for the external change. Review the available actions. If the files cannot be reviewed safely, replace the source or delete the skill.'**
  String get errorDriftResolutionUnavailable;

  /// No description provided for @skillDriftMissingArtifacts.
  ///
  /// In en, this message translates to:
  /// **'Missing locations that will also be restored: {count}.'**
  String skillDriftMissingArtifacts(int count);

  /// No description provided for @skillDriftRefreshReview.
  ///
  /// In en, this message translates to:
  /// **'Refresh and review again'**
  String get skillDriftRefreshReview;

  /// No description provided for @skillDriftRestoreMissing.
  ///
  /// In en, this message translates to:
  /// **'Restore missing locations'**
  String get skillDriftRestoreMissing;

  /// No description provided for @settingsGlobalActivationMethod.
  ///
  /// In en, this message translates to:
  /// **'Global activation method'**
  String get settingsGlobalActivationMethod;

  /// No description provided for @settingsActivationMethodAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get settingsActivationMethodAutomatic;

  /// No description provided for @settingsActivationMethodCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get settingsActivationMethodCopy;

  /// No description provided for @settingsActivationMethodSymbolicLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get settingsActivationMethodSymbolicLink;

  /// No description provided for @settingsActivationMethodAutomaticDescription.
  ///
  /// In en, this message translates to:
  /// **'Links when the folder supports it, otherwise copies.'**
  String get settingsActivationMethodAutomaticDescription;

  /// No description provided for @settingsActivationMethodCopyDescription.
  ///
  /// In en, this message translates to:
  /// **'Places a full copy in each Agent folder. Most compatible; each update rewrites the copy.'**
  String get settingsActivationMethodCopyDescription;

  /// No description provided for @settingsActivationMethodSymbolicLinkDescription.
  ///
  /// In en, this message translates to:
  /// **'Points to SkillDeck\'s stored copy, so updates apply instantly. Activation fails if the folder can\'t hold a link.'**
  String get settingsActivationMethodSymbolicLinkDescription;

  /// No description provided for @settingsActivationMethodScopeNote.
  ///
  /// In en, this message translates to:
  /// **'Applies to new activations only. Project activations always copy.'**
  String get settingsActivationMethodScopeNote;

  /// No description provided for @errorSymbolicLinkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This Agent folder can\'t hold a symbolic link. In Settings › Agents, set the global activation method to Automatic or Copy.'**
  String get errorSymbolicLinkUnavailable;

  /// No description provided for @acquisitionCandidateInstalled.
  ///
  /// In en, this message translates to:
  /// **'Already installed. A Slot holds one Skill, so it can\'t be installed again.'**
  String get acquisitionCandidateInstalled;

  /// No description provided for @acquisitionOpenInstalledSkill.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get acquisitionOpenInstalledSkill;

  /// No description provided for @acquisitionErrorLocalPath.
  ///
  /// In en, this message translates to:
  /// **'Enter the folder\'s full path, or choose it with the button on the right.'**
  String get acquisitionErrorLocalPath;

  /// No description provided for @acquisitionSubtitleV2.
  ///
  /// In en, this message translates to:
  /// **'Install from a link, an install command, a local folder, or a Git repository.'**
  String get acquisitionSubtitleV2;

  /// No description provided for @acquisitionInputModeSmart.
  ///
  /// In en, this message translates to:
  /// **'Detect automatically'**
  String get acquisitionInputModeSmart;

  /// No description provided for @acquisitionInputModeTyped.
  ///
  /// In en, this message translates to:
  /// **'By type'**
  String get acquisitionInputModeTyped;

  /// No description provided for @acquisitionSmartHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a repository, an npx skills add command, a URL, or a folder path'**
  String get acquisitionSmartHint;

  /// No description provided for @acquisitionAgentPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Let an Agent install it for me'**
  String get acquisitionAgentPromptTitle;

  /// No description provided for @acquisitionAgentPromptCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get acquisitionAgentPromptCopied;

  /// No description provided for @acquisitionAgentPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Send this prompt to an Agent. It installs the Skill with the skilldeck Skill.'**
  String get acquisitionAgentPromptHint;

  /// No description provided for @acquisitionAgentPromptCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy prompt'**
  String get acquisitionAgentPromptCopy;

  /// No description provided for @acquisitionAgentPromptOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get acquisitionAgentPromptOpenSettings;

  /// No description provided for @acquisitionAgentSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up the command line first'**
  String get acquisitionAgentSetupTitle;

  /// No description provided for @acquisitionAgentSetupBody.
  ///
  /// In en, this message translates to:
  /// **'Agents install through the skilldeck Skill, which calls the command line. Finish both steps in Settings › Command Line.'**
  String get acquisitionAgentSetupBody;

  /// No description provided for @acquisitionAgentSetupTool.
  ///
  /// In en, this message translates to:
  /// **'Command line tool ready'**
  String get acquisitionAgentSetupTool;

  /// No description provided for @acquisitionAgentSetupSkill.
  ///
  /// In en, this message translates to:
  /// **'skilldeck Skill active for an Agent'**
  String get acquisitionAgentSetupSkill;

  /// No description provided for @acquisitionAgentPrompt.
  ///
  /// In en, this message translates to:
  /// **'Call the \"skilldeck\" Skill and use the skilldeck command to install a Skill for me:\n1. First check which Skills the source contains. If there is only one, install it. If there are several, list their names and descriptions and ask me which to install.\n2. After installing, activate it for the Agent you are running in, so you can use it right away.\n3. When you are done, tell me which Skills were installed and which Agent they are active for. If SkillDeck needs my approval, or a step fails, tell me why and what to do next.\n\nThe Skill I want (a repository, URL, or local folder path): '**
  String get acquisitionAgentPrompt;

  /// No description provided for @acquisitionAdvancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced options'**
  String get acquisitionAdvancedOptions;

  /// No description provided for @acquisitionAdvancedOptionsHint.
  ///
  /// In en, this message translates to:
  /// **'Git ref, repository subpath'**
  String get acquisitionAdvancedOptionsHint;

  /// No description provided for @acquisitionInspect.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get acquisitionInspect;

  /// No description provided for @acquisitionClearInput.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get acquisitionClearInput;

  /// No description provided for @acquisitionDetectedKind.
  ///
  /// In en, this message translates to:
  /// **'{kind} · {count} skill{plural} found'**
  String acquisitionDetectedKind(Object kind, Object count, Object plural);

  /// No description provided for @acquisitionPreselectedSkills.
  ///
  /// In en, this message translates to:
  /// **'Preselected skills'**
  String get acquisitionPreselectedSkills;

  /// No description provided for @acquisitionPreselectedSkillsNote.
  ///
  /// In en, this message translates to:
  /// **'From the command\'s --skill. They will be checked in the next step; you can still change the selection.'**
  String get acquisitionPreselectedSkillsNote;

  /// No description provided for @acquisitionPreselectedScopeGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global scope preselected from the command\'s -g.'**
  String get acquisitionPreselectedScopeGlobal;

  /// No description provided for @acquisitionPreselectedAgents.
  ///
  /// In en, this message translates to:
  /// **'Agents preselected from the command: {agents}.'**
  String acquisitionPreselectedAgents(Object agents);

  /// No description provided for @acquisitionUnmatchedSkills.
  ///
  /// In en, this message translates to:
  /// **'Not found in this source: {names}.'**
  String acquisitionUnmatchedSkills(Object names);

  /// No description provided for @acquisitionIgnoredFlags.
  ///
  /// In en, this message translates to:
  /// **'Ignored: {flags}.'**
  String acquisitionIgnoredFlags(Object flags);

  /// No description provided for @acquisitionErrorWebSourceHasNoSkillsTitle.
  ///
  /// In en, this message translates to:
  /// **'This address has no installable skills'**
  String get acquisitionErrorWebSourceHasNoSkillsTitle;

  /// No description provided for @acquisitionErrorWebSourceHasNoSkillsBody.
  ///
  /// In en, this message translates to:
  /// **'It may be an article or a project home page. Go back to that page, copy its install command or GitHub repository address, and paste it here.'**
  String get acquisitionErrorWebSourceHasNoSkillsBody;

  /// No description provided for @acquisitionMultipleSkillsHintV2.
  ///
  /// In en, this message translates to:
  /// **'You can install multiple skills from one repository at once. An npx skills add command works here too.'**
  String get acquisitionMultipleSkillsHintV2;

  /// No description provided for @errorNoSkillsInSource.
  ///
  /// In en, this message translates to:
  /// **'No skills were found in this source. A skill is a folder that contains a SKILL.md file.'**
  String get errorNoSkillsInSource;

  /// No description provided for @errorLocalFolderNotFound.
  ///
  /// In en, this message translates to:
  /// **'This folder doesn\'t exist. Check the path.'**
  String get errorLocalFolderNotFound;

  /// No description provided for @errorRepositorySubpathNotFound.
  ///
  /// In en, this message translates to:
  /// **'The repository has no such subpath. Check the spelling, or leave it empty to scan the whole repository.'**
  String get errorRepositorySubpathNotFound;

  /// No description provided for @errorGitNetwork.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the repository. Check your network or proxy settings and try again.'**
  String get errorGitNetwork;

  /// No description provided for @errorGitRefNotFound.
  ///
  /// In en, this message translates to:
  /// **'The repository has no such branch or tag.'**
  String get errorGitRefNotFound;

  /// No description provided for @errorSourceLocatorHasQuery.
  ///
  /// In en, this message translates to:
  /// **'The address can\'t include query parameters or account details. Remove them and try again.'**
  String get errorSourceLocatorHasQuery;

  /// No description provided for @errorSkillFileCountExceeded.
  ///
  /// In en, this message translates to:
  /// **'This skill has more than {maximum} files. Choose the skill\'s own folder rather than a whole project.'**
  String errorSkillFileCountExceeded(int maximum);

  /// No description provided for @errorSkillByteSizeExceeded.
  ///
  /// In en, this message translates to:
  /// **'This skill is larger than {maximum} MB. Choose the skill\'s own folder rather than a whole project.'**
  String errorSkillByteSizeExceeded(int maximum);

  /// No description provided for @errorSkillMarkdownInvalid.
  ///
  /// In en, this message translates to:
  /// **'SKILL.md is missing, or its header lacks a valid name and description.'**
  String get errorSkillMarkdownInvalid;

  /// No description provided for @errorSkillMarkdownInvalidAt.
  ///
  /// In en, this message translates to:
  /// **'The header of {path} lacks a valid name and description.'**
  String errorSkillMarkdownInvalidAt(Object path);

  /// No description provided for @errorSkillNameUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Skill names may use only lowercase letters, digits, and hyphens.'**
  String get errorSkillNameUnsupported;

  /// No description provided for @errorSkillNameUnsupportedAt.
  ///
  /// In en, this message translates to:
  /// **'The name in {path} isn\'t supported. Skill names may use only lowercase letters, digits, and hyphens.'**
  String errorSkillNameUnsupportedAt(Object path);

  /// No description provided for @externalSkillsRescanned.
  ///
  /// In en, this message translates to:
  /// **'The Agent folders changed, so they were scanned again. Review the list and confirm to take the skills over.'**
  String get externalSkillsRescanned;

  /// No description provided for @browserEmptyExistingDescription.
  ///
  /// In en, this message translates to:
  /// **'Found {count, plural, =1{1 skill} other{{count} skills}} already in your Agent folders. Take them over without reinstalling.'**
  String browserEmptyExistingDescription(int count);

  /// No description provided for @browserTakeOverExistingSkills.
  ///
  /// In en, this message translates to:
  /// **'Take over existing skills'**
  String get browserTakeOverExistingSkills;

  /// No description provided for @settingsNavGroupApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsNavGroupApp;

  /// No description provided for @settingsNavGroupSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsNavGroupSystem;

  /// No description provided for @settingsGeneralTitle.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneralTitle;

  /// No description provided for @settingsGeneralDescription.
  ///
  /// In en, this message translates to:
  /// **'Interface language, how Skills are activated, and project folders. Changes apply right away.'**
  String get settingsGeneralDescription;

  /// No description provided for @settingsAppearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceTitle;

  /// No description provided for @settingsAppearanceDescription.
  ///
  /// In en, this message translates to:
  /// **'Theme and how Skill lists are displayed. Changes apply right away.'**
  String get settingsAppearanceDescription;

  /// No description provided for @settingsAppearanceMode.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsAppearanceMode;

  /// No description provided for @settingsAppearanceModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Follow System switches with your system\'s light or dark mode.'**
  String get settingsAppearanceModeDescription;

  /// No description provided for @settingsAppearanceModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsAppearanceModeLight;

  /// No description provided for @settingsAppearanceModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsAppearanceModeDark;

  /// No description provided for @settingsSkillListLayout.
  ///
  /// In en, this message translates to:
  /// **'Skill list view'**
  String get settingsSkillListLayout;

  /// No description provided for @settingsSkillListLayoutDescription.
  ///
  /// In en, this message translates to:
  /// **'Applies to both Installed and Favorites.'**
  String get settingsSkillListLayoutDescription;

  /// No description provided for @settingsSkillListLayoutList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get settingsSkillListLayoutList;

  /// No description provided for @settingsSkillListLayoutCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get settingsSkillListLayoutCards;

  /// No description provided for @settingsAgentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get settingsAgentsTitle;

  /// No description provided for @settingsAgentsDescription.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck activates Skills into the folders of these Agents. Agents that are turned off are not offered as activation targets.'**
  String get settingsAgentsDescription;

  /// No description provided for @settingsMaintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get settingsMaintenanceTitle;

  /// No description provided for @settingsMaintenanceDescription.
  ///
  /// In en, this message translates to:
  /// **'For troubleshooting. Each check runs only when you start it.'**
  String get settingsMaintenanceDescription;

  /// No description provided for @settingsAboutSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'About SkillDeck'**
  String get settingsAboutSectionTitle;

  /// No description provided for @settingsLanguageGroup.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageGroup;

  /// No description provided for @settingsActivationGroup.
  ///
  /// In en, this message translates to:
  /// **'Activation'**
  String get settingsActivationGroup;

  /// No description provided for @settingsProjectRootsGroup.
  ///
  /// In en, this message translates to:
  /// **'Project Folders'**
  String get settingsProjectRootsGroup;

  /// No description provided for @settingsLanguageDescription.
  ///
  /// In en, this message translates to:
  /// **'Follow System uses the language of your system.'**
  String get settingsLanguageDescription;

  /// No description provided for @settingsProjectRootsRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered Project Roots'**
  String get settingsProjectRootsRegistered;

  /// No description provided for @agentsShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all {count} Agents'**
  String agentsShowAll(int count);

  /// No description provided for @agentsShowFewer.
  ///
  /// In en, this message translates to:
  /// **'Show fewer'**
  String get agentsShowFewer;

  /// No description provided for @settingsSkillsGroup.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get settingsSkillsGroup;

  /// No description provided for @settingsEnvironmentGroup.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get settingsEnvironmentGroup;

  /// No description provided for @settingsValidateNow.
  ///
  /// In en, this message translates to:
  /// **'Validate Now'**
  String get settingsValidateNow;

  /// No description provided for @settingsValidationLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last validated {time}. {summary}'**
  String settingsValidationLastRun(String time, String summary);

  /// No description provided for @settingsValidationLastFailed.
  ///
  /// In en, this message translates to:
  /// **'Last validated {time}. The validation could not finish.'**
  String settingsValidationLastFailed(String time);

  /// No description provided for @settingsUpdatesGroup.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdatesGroup;

  /// No description provided for @settingsLinksGroup.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get settingsLinksGroup;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsAppVersion(String version);

  /// No description provided for @settingsAutomaticUpdates.
  ///
  /// In en, this message translates to:
  /// **'Automatic Updates'**
  String get settingsAutomaticUpdates;

  /// No description provided for @translationServiceGroup.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get translationServiceGroup;

  /// No description provided for @translationOutputGroup.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get translationOutputGroup;

  /// No description provided for @translationEndpointHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the default endpoint.'**
  String get translationEndpointHint;

  /// No description provided for @translationApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Stored in the system credential store and never logged.'**
  String get translationApiKeyHint;

  /// No description provided for @translationStatusConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured · {provider}'**
  String translationStatusConfigured(String provider);

  /// No description provided for @translationStatusNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'No translation service configured'**
  String get translationStatusNotConfigured;

  /// No description provided for @translationStatusNotConfiguredDetail.
  ///
  /// In en, this message translates to:
  /// **'Fill in the settings below and save them to translate Skills.'**
  String get translationStatusNotConfiguredDetail;

  /// No description provided for @translationTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get translationTestConnection;

  /// No description provided for @translationTestRunning.
  ///
  /// In en, this message translates to:
  /// **'Testing the connection…'**
  String get translationTestRunning;

  /// No description provided for @translationTestSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Connection works'**
  String get translationTestSucceeded;

  /// No description provided for @translationTestSucceededDetail.
  ///
  /// In en, this message translates to:
  /// **'The service returned a translation of a short sample. No Skill content was sent.'**
  String get translationTestSucceededDetail;

  /// No description provided for @translationTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get translationTestFailed;

  /// No description provided for @translationTestFailedAuthentication.
  ///
  /// In en, this message translates to:
  /// **'The API key was rejected or has no access to this model.'**
  String get translationTestFailedAuthentication;

  /// No description provided for @translationTestFailedRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The service is limiting requests. Try again later.'**
  String get translationTestFailedRateLimited;

  /// No description provided for @translationTestFailedNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the endpoint. Check the address and your network.'**
  String get translationTestFailedNetwork;

  /// No description provided for @translationTestFailedRejected.
  ///
  /// In en, this message translates to:
  /// **'The service rejected the request. Check the model name and protocol.'**
  String get translationTestFailedRejected;

  /// No description provided for @translationTestFailedConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Check the endpoint, model, and target language.'**
  String get translationTestFailedConfiguration;

  /// No description provided for @translationTestFailedCredentialRequired.
  ///
  /// In en, this message translates to:
  /// **'Anthropic needs an API key.'**
  String get translationTestFailedCredentialRequired;

  /// No description provided for @translationTestFailedUnknown.
  ///
  /// In en, this message translates to:
  /// **'The connection test did not finish.'**
  String get translationTestFailedUnknown;

  /// No description provided for @translationUnsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get translationUnsavedChanges;

  /// No description provided for @translationRevert.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get translationRevert;

  /// No description provided for @tagsFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsFilterTitle;

  /// No description provided for @tagsCreate.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get tagsCreate;

  /// No description provided for @tagsNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get tagsNamePlaceholder;

  /// No description provided for @tagsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get tagsDelete;

  /// No description provided for @tagsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String tagsDeleteTitle(Object name);

  /// No description provided for @tagsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No Skills use this tag.} =1{1 Skill will lose this tag.} other{{count} Skills will lose this tag.}} The Skills themselves stay unchanged.'**
  String tagsDeleteMessage(int count);

  /// No description provided for @tagsSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search or create a tag'**
  String get tagsSearchPlaceholder;

  /// No description provided for @tagsCreateNamed.
  ///
  /// In en, this message translates to:
  /// **'Create “{name}”'**
  String tagsCreateNamed(Object name);

  /// No description provided for @tagsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get tagsAdd;

  /// No description provided for @tagsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove tag {name}'**
  String tagsRemove(Object name);

  /// No description provided for @tagsFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Skills carry all of the selected tags.'**
  String get tagsFilterEmpty;

  /// No description provided for @tagsClearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear tag filter'**
  String get tagsClearFilter;

  /// No description provided for @tagsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get tagsClear;

  /// No description provided for @tagsManageHint.
  ///
  /// In en, this message translates to:
  /// **'Right-click a tag to rename, recolor, or delete it.'**
  String get tagsManageHint;

  /// No description provided for @tagsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get tagsEdit;

  /// No description provided for @tagsColorSwatch.
  ///
  /// In en, this message translates to:
  /// **'Color {index}'**
  String tagsColorSwatch(int index);

  /// No description provided for @tagsNoneAssigned.
  ///
  /// In en, this message translates to:
  /// **'No tags yet.'**
  String get tagsNoneAssigned;

  /// No description provided for @commandLineVerbActivateProgressive.
  ///
  /// In en, this message translates to:
  /// **'Activating'**
  String get commandLineVerbActivateProgressive;

  /// No description provided for @commandLineVerbActivatePast.
  ///
  /// In en, this message translates to:
  /// **'Activated'**
  String get commandLineVerbActivatePast;

  /// No description provided for @commandLineVerbDeactivateProgressive.
  ///
  /// In en, this message translates to:
  /// **'Deactivating'**
  String get commandLineVerbDeactivateProgressive;

  /// No description provided for @commandLineVerbDeactivatePast.
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get commandLineVerbDeactivatePast;

  /// No description provided for @commandLineVerbFavoriteProgressive.
  ///
  /// In en, this message translates to:
  /// **'Favoriting'**
  String get commandLineVerbFavoriteProgressive;

  /// No description provided for @commandLineVerbFavoritePast.
  ///
  /// In en, this message translates to:
  /// **'Favorited'**
  String get commandLineVerbFavoritePast;

  /// No description provided for @commandLineVerbUnfavoriteProgressive.
  ///
  /// In en, this message translates to:
  /// **'Unfavoriting'**
  String get commandLineVerbUnfavoriteProgressive;

  /// No description provided for @commandLineVerbUnfavoritePast.
  ///
  /// In en, this message translates to:
  /// **'Unfavorited'**
  String get commandLineVerbUnfavoritePast;

  /// No description provided for @commandLineVerbNoteProgressive.
  ///
  /// In en, this message translates to:
  /// **'Annotating'**
  String get commandLineVerbNoteProgressive;

  /// No description provided for @commandLineVerbNotePast.
  ///
  /// In en, this message translates to:
  /// **'Annotated'**
  String get commandLineVerbNotePast;

  /// No description provided for @commandLineVerbTagAddProgressive.
  ///
  /// In en, this message translates to:
  /// **'Tagging'**
  String get commandLineVerbTagAddProgressive;

  /// No description provided for @commandLineVerbTagAddPast.
  ///
  /// In en, this message translates to:
  /// **'Tagged'**
  String get commandLineVerbTagAddPast;

  /// No description provided for @commandLineVerbTagRemoveProgressive.
  ///
  /// In en, this message translates to:
  /// **'Untagging'**
  String get commandLineVerbTagRemoveProgressive;

  /// No description provided for @commandLineVerbTagRemovePast.
  ///
  /// In en, this message translates to:
  /// **'Untagged'**
  String get commandLineVerbTagRemovePast;

  /// No description provided for @commandLineVerbInstallProgressive.
  ///
  /// In en, this message translates to:
  /// **'Installing'**
  String get commandLineVerbInstallProgressive;

  /// No description provided for @commandLineVerbInstallPast.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get commandLineVerbInstallPast;

  /// No description provided for @commandLineVerbUpdateProgressive.
  ///
  /// In en, this message translates to:
  /// **'Updating'**
  String get commandLineVerbUpdateProgressive;

  /// No description provided for @commandLineVerbUpdatePast.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get commandLineVerbUpdatePast;

  /// No description provided for @commandLineVerbRemoveProgressive.
  ///
  /// In en, this message translates to:
  /// **'Deleting'**
  String get commandLineVerbRemoveProgressive;

  /// No description provided for @commandLineVerbRemovePast.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get commandLineVerbRemovePast;

  /// No description provided for @commandLineVerbReplaceSourceProgressive.
  ///
  /// In en, this message translates to:
  /// **'Replacing the source of'**
  String get commandLineVerbReplaceSourceProgressive;

  /// No description provided for @commandLineVerbReplaceSourcePast.
  ///
  /// In en, this message translates to:
  /// **'Replaced the source of'**
  String get commandLineVerbReplaceSourcePast;

  /// No description provided for @commandLineRunning.
  ///
  /// In en, this message translates to:
  /// **'Command line: {verb} {count, plural, =1{1 Skill} other{{count} Skills}}'**
  String commandLineRunning(String verb, int count);

  /// No description provided for @commandLineCancelledSuffix.
  ///
  /// In en, this message translates to:
  /// **', the rest cancelled'**
  String get commandLineCancelledSuffix;

  /// No description provided for @commandLineSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'{verb} {count, plural, =1{1 Skill} other{{count} Skills}}'**
  String commandLineSummaryTitle(String verb, int count);

  /// No description provided for @commandLineSummaryReplaceSource.
  ///
  /// In en, this message translates to:
  /// **'Replaced the source of {count, plural, =1{1 Skill} other{{count} Skills}}'**
  String commandLineSummaryReplaceSource(int count);

  /// No description provided for @commandLineSummaryFailedSuffix.
  ///
  /// In en, this message translates to:
  /// **', {failed} failed'**
  String commandLineSummaryFailedSuffix(int failed);

  /// No description provided for @commandLineSummaryOrigin.
  ///
  /// In en, this message translates to:
  /// **'Command line'**
  String get commandLineSummaryOrigin;

  /// No description provided for @commandLineSummaryAllSucceeded.
  ///
  /// In en, this message translates to:
  /// **'All succeeded'**
  String get commandLineSummaryAllSucceeded;

  /// No description provided for @commandLineSummaryDone.
  ///
  /// In en, this message translates to:
  /// **'{count} completed'**
  String commandLineSummaryDone(int count);

  /// No description provided for @commandLineSummaryMore.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String commandLineSummaryMore(int count);

  /// No description provided for @commandLineAgents.
  ///
  /// In en, this message translates to:
  /// **'For {agents}'**
  String commandLineAgents(String agents);

  /// No description provided for @commandLineProgress.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total}'**
  String commandLineProgress(int done, int total);

  /// No description provided for @commandLineProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing {slotKey}'**
  String commandLineProcessing(String slotKey);

  /// No description provided for @commandLineCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commandLineCancel;

  /// No description provided for @commandLineCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get commandLineCancelling;

  /// No description provided for @commandLineOpenSkill.
  ///
  /// In en, this message translates to:
  /// **'Open {slotKey}'**
  String commandLineOpenSkill(String slotKey);

  /// No description provided for @commandLineDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commandLineDismiss;

  /// No description provided for @commandLineErrorActivationTargetOccupied.
  ///
  /// In en, this message translates to:
  /// **'An unmanaged folder with the same name is in the way; nothing was changed.'**
  String get commandLineErrorActivationTargetOccupied;

  /// No description provided for @commandLineErrorOwnershipRepair.
  ///
  /// In en, this message translates to:
  /// **'Agent folder permissions need repair in SkillDeck.'**
  String get commandLineErrorOwnershipRepair;

  /// No description provided for @commandLineErrorUnknownAgent.
  ///
  /// In en, this message translates to:
  /// **'That Agent is not set up on this device.'**
  String get commandLineErrorUnknownAgent;

  /// No description provided for @commandLineErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'The operation failed.'**
  String get commandLineErrorGeneric;

  /// No description provided for @operationWaitingForCommandLine.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the command line to finish…'**
  String get operationWaitingForCommandLine;

  /// No description provided for @commandLineApprovalRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'The command line wants to delete {count, plural, =1{1 Skill} other{{count} Skills}}'**
  String commandLineApprovalRemoveTitle(int count);

  /// No description provided for @commandLineApprovalDeleteTagTitle.
  ///
  /// In en, this message translates to:
  /// **'The command line wants to delete the tag “{tag}”'**
  String commandLineApprovalDeleteTagTitle(String tag);

  /// No description provided for @commandLineApprovalActivatedIn.
  ///
  /// In en, this message translates to:
  /// **'Removes activations in {agents}'**
  String commandLineApprovalActivatedIn(String agents);

  /// No description provided for @commandLineApprovalNotActivated.
  ///
  /// In en, this message translates to:
  /// **'Not active in any Agent'**
  String get commandLineApprovalNotActivated;

  /// No description provided for @commandLineApprovalUnpublishedDraft.
  ///
  /// In en, this message translates to:
  /// **'has an unpublished Draft'**
  String get commandLineApprovalUnpublishedDraft;

  /// No description provided for @commandLineApprovalSkillGone.
  ///
  /// In en, this message translates to:
  /// **'No longer installed'**
  String get commandLineApprovalSkillGone;

  /// No description provided for @commandLineApprovalRemoveWarning.
  ///
  /// In en, this message translates to:
  /// **'This can’t be undone: files, version history, Drafts, notes, and tag assignments are deleted together.'**
  String get commandLineApprovalRemoveWarning;

  /// No description provided for @commandLineApprovalTagWarning.
  ///
  /// In en, this message translates to:
  /// **'The tag is removed from {count, plural, =1{1 Skill} other{{count} Skills}}. This can’t be undone.'**
  String commandLineApprovalTagWarning(int count);

  /// No description provided for @commandLineApprovalStale.
  ///
  /// In en, this message translates to:
  /// **'This changed after you looked. Review it again.'**
  String get commandLineApprovalStale;

  /// No description provided for @commandLineApprovalDeny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get commandLineApprovalDeny;

  /// No description provided for @commandLineApprovalConfirmRemove.
  ///
  /// In en, this message translates to:
  /// **'Delete {count, plural, =1{1 Skill} other{{count} Skills}}'**
  String commandLineApprovalConfirmRemove(int count);

  /// No description provided for @commandLineApprovalConfirmDeleteTag.
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get commandLineApprovalConfirmDeleteTag;

  /// No description provided for @commandLineApprovalReplaceSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'The command line wants to replace the source of {count, plural, =1{1 Skill} other{{count} Skills}}'**
  String commandLineApprovalReplaceSourceTitle(int count);

  /// No description provided for @commandLineApprovalReplaceSourceWarning.
  ///
  /// In en, this message translates to:
  /// **'The old source’s version history and local changes will be deleted for good.'**
  String get commandLineApprovalReplaceSourceWarning;

  /// No description provided for @commandLineApprovalConfirmReplaceSource.
  ///
  /// In en, this message translates to:
  /// **'Replace sources'**
  String get commandLineApprovalConfirmReplaceSource;

  /// No description provided for @settingsCommandLineTitle.
  ///
  /// In en, this message translates to:
  /// **'Command Line'**
  String get settingsCommandLineTitle;

  /// No description provided for @settingsCommandLineDescription.
  ///
  /// In en, this message translates to:
  /// **'Let Agents manage Skills with the skilldeck command.'**
  String get settingsCommandLineDescription;

  /// No description provided for @commandLineStatusGroup.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get commandLineStatusGroup;

  /// No description provided for @commandLineStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Command-line service status'**
  String get commandLineStatusTitle;

  /// No description provided for @commandLineStatusDetail.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck {version}'**
  String commandLineStatusDetail(String version);

  /// No description provided for @commandLineStatusRunningBadge.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get commandLineStatusRunningBadge;

  /// No description provided for @commandLineStatusStoppedBadge.
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get commandLineStatusStoppedBadge;

  /// No description provided for @commandLineToolGroup.
  ///
  /// In en, this message translates to:
  /// **'Command-line tool'**
  String get commandLineToolGroup;

  /// No description provided for @commandLineToolLocation.
  ///
  /// In en, this message translates to:
  /// **'CLI location'**
  String get commandLineToolLocation;

  /// No description provided for @commandLineToolLocationDetail.
  ///
  /// In en, this message translates to:
  /// **'Agents call the CLI at this path.'**
  String get commandLineToolLocationDetail;

  /// No description provided for @commandLineToolNotBundled.
  ///
  /// In en, this message translates to:
  /// **'This build of SkillDeck doesn’t include the command-line tool.'**
  String get commandLineToolNotBundled;

  /// No description provided for @commandLineToolFailed.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck couldn’t update the command-line tool. Any previous copy is unchanged.'**
  String get commandLineToolFailed;

  /// No description provided for @commandLinePathTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to PATH (optional)'**
  String get commandLinePathTitle;

  /// No description provided for @commandLinePathDetail.
  ///
  /// In en, this message translates to:
  /// **'To type skilldeck directly in a terminal, add this line to ~/.zshrc:'**
  String get commandLinePathDetail;

  /// No description provided for @commandLinePathWindows.
  ///
  /// In en, this message translates to:
  /// **'The SkillDeck installer adds this folder to your PATH.'**
  String get commandLinePathWindows;

  /// No description provided for @commandLinePathLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Install in Terminal'**
  String get commandLinePathLinkTitle;

  /// No description provided for @commandLinePathLinkDetail.
  ///
  /// In en, this message translates to:
  /// **'Adds the skilldeck command to /usr/local/bin so you can run it from any terminal. You may need to enter an administrator password once.'**
  String get commandLinePathLinkDetail;

  /// No description provided for @commandLinePathLinkInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed at {path}.'**
  String commandLinePathLinkInstalled(String path);

  /// No description provided for @commandLinePathLinkConflict.
  ///
  /// In en, this message translates to:
  /// **'/usr/local/bin/skilldeck is already in use. Add this line to ~/.zshrc instead:'**
  String get commandLinePathLinkConflict;

  /// No description provided for @commandLinePathLinkInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get commandLinePathLinkInstall;

  /// No description provided for @commandLinePathLinkRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commandLinePathLinkRemove;

  /// No description provided for @commandLinePathLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck couldn’t change /usr/local/bin/skilldeck.'**
  String get commandLinePathLinkFailed;

  /// No description provided for @commandLineAgentSkillGroup.
  ///
  /// In en, this message translates to:
  /// **'Install the Command-line Skill'**
  String get commandLineAgentSkillGroup;

  /// No description provided for @commandLineAgentSkillTitle.
  ///
  /// In en, this message translates to:
  /// **'Command-line Skill'**
  String get commandLineAgentSkillTitle;

  /// No description provided for @commandLineAgentSkillActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get commandLineAgentSkillActive;

  /// No description provided for @commandLineAgentSkillInactive.
  ///
  /// In en, this message translates to:
  /// **'Installed, but not active for any Agent.'**
  String get commandLineAgentSkillInactive;

  /// No description provided for @commandLineAgentSkillNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Teaches Agents to use skilldeck. Installing activates it for every Agent on this device.'**
  String get commandLineAgentSkillNotInstalled;

  /// No description provided for @commandLineAgentSkillInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get commandLineAgentSkillInstall;

  /// No description provided for @commandLineAgentSkillInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get commandLineAgentSkillInstalling;

  /// No description provided for @commandLineAgentSkillOpen.
  ///
  /// In en, this message translates to:
  /// **'View Skill'**
  String get commandLineAgentSkillOpen;

  /// No description provided for @commandLineAgentSkillInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'The Agent Skill couldn’t be installed.'**
  String get commandLineAgentSkillInstallFailed;

  /// No description provided for @commandLineSafetyGroup.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get commandLineSafetyGroup;

  /// No description provided for @commandLineSafetyTitle.
  ///
  /// In en, this message translates to:
  /// **'Deletions need your confirmation in the App'**
  String get commandLineSafetyTitle;

  /// No description provided for @commandLineSafetyDetail.
  ///
  /// In en, this message translates to:
  /// **'Agents can only request a deletion.'**
  String get commandLineSafetyDetail;

  /// No description provided for @commandLineSafetyAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get commandLineSafetyAlwaysOn;

  /// No description provided for @workspaceTakeoverTargets.
  ///
  /// In en, this message translates to:
  /// **'Existing target'**
  String get workspaceTakeoverTargets;

  /// No description provided for @ownershipRepairFoldersTitle.
  ///
  /// In en, this message translates to:
  /// **'Folders to repair'**
  String get ownershipRepairFoldersTitle;

  /// No description provided for @customAgentInvalidPathTitle.
  ///
  /// In en, this message translates to:
  /// **'Invalid path'**
  String get customAgentInvalidPathTitle;

  /// No description provided for @commandLineApprovalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Requested from the skilldeck command line. Nothing runs until you approve.'**
  String get commandLineApprovalSubtitle;

  /// No description provided for @commandLineApprovalRemoveSection.
  ///
  /// In en, this message translates to:
  /// **'To delete'**
  String get commandLineApprovalRemoveSection;

  /// No description provided for @commandLineApprovalReplaceSection.
  ///
  /// In en, this message translates to:
  /// **'To replace'**
  String get commandLineApprovalReplaceSection;

  /// No description provided for @projectRootsRegisteredTitle.
  ///
  /// In en, this message translates to:
  /// **'Registered'**
  String get projectRootsRegisteredTitle;

  /// No description provided for @projectRootsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 folder} other{{count} folders}} registered'**
  String projectRootsCount(int count);

  /// No description provided for @agentsManageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SkillDeck activates Skills in the Agents on this list.'**
  String get agentsManageSubtitle;

  /// No description provided for @agentsManagedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Agent} other{{count} Agents}}'**
  String agentsManagedCount(int count);

  /// No description provided for @agentsAddBuiltInTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a built-in Agent'**
  String get agentsAddBuiltInTitle;

  /// No description provided for @agentsAddBuiltInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Agents to add to the list.'**
  String get agentsAddBuiltInSubtitle;

  /// No description provided for @agentsManagedListTitle.
  ///
  /// In en, this message translates to:
  /// **'Managed Agents'**
  String get agentsManagedListTitle;

  /// No description provided for @customAgentEditorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set up Skills folders for an Agent without built-in support.'**
  String get customAgentEditorSubtitle;

  /// No description provided for @customAgentBasicTitle.
  ///
  /// In en, this message translates to:
  /// **'Basic information'**
  String get customAgentBasicTitle;

  /// No description provided for @customAgentSkillsFoldersTitle.
  ///
  /// In en, this message translates to:
  /// **'Skills folders'**
  String get customAgentSkillsFoldersTitle;

  /// No description provided for @acquisitionActivationScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Activation scope'**
  String get acquisitionActivationScopeTitle;

  /// No description provided for @workspaceReplaceSourceFound.
  ///
  /// In en, this message translates to:
  /// **'Found {name} in the new source.'**
  String workspaceReplaceSourceFound(String name);

  /// No description provided for @agentsAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get agentsAddAction;

  /// No description provided for @whatsNewVersionBadge.
  ///
  /// In en, this message translates to:
  /// **'New in {version}'**
  String whatsNewVersionBadge(Object version);

  /// No description provided for @whatsNewCommandLineTitle.
  ///
  /// In en, this message translates to:
  /// **'Now with command line control'**
  String get whatsNewCommandLineTitle;

  /// No description provided for @whatsNewCommandLineBody.
  ///
  /// In en, this message translates to:
  /// **'AI Agents can now install, activate, and organize your Skills with the skilldeck command.'**
  String get whatsNewCommandLineBody;

  /// No description provided for @whatsNewOpenCommandLineSettings.
  ///
  /// In en, this message translates to:
  /// **'Command Line Settings'**
  String get whatsNewOpenCommandLineSettings;

  /// No description provided for @whatsNewDarkModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Now in dark mode'**
  String get whatsNewDarkModeTitle;

  /// No description provided for @whatsNewDarkModeBody.
  ///
  /// In en, this message translates to:
  /// **'Choose Light or Dark in Settings › Appearance, or let SkillDeck follow your system.'**
  String get whatsNewDarkModeBody;

  /// No description provided for @whatsNewOpenAppearanceSettings.
  ///
  /// In en, this message translates to:
  /// **'Appearance Settings'**
  String get whatsNewOpenAppearanceSettings;

  /// No description provided for @whatsNewDismiss.
  ///
  /// In en, this message translates to:
  /// **'Got It'**
  String get whatsNewDismiss;

  /// No description provided for @workspaceSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Source address unavailable'**
  String get workspaceSourceUnavailable;

  /// No description provided for @workspaceSourceNotWebLink.
  ///
  /// In en, this message translates to:
  /// **'This source has no supported safe web link.'**
  String get workspaceSourceNotWebLink;

  /// No description provided for @workspaceOpenSourceFailed.
  ///
  /// In en, this message translates to:
  /// **'The source link could not be opened.'**
  String get workspaceOpenSourceFailed;

  /// No description provided for @workspaceOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open source: {address}'**
  String workspaceOpenSource(String address);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
