import 'package:skills_manager/l10n/generated/app_localizations.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

String localizeAppFailure(
  AppLocalizations l10n,
  AppFailure failure,
) => switch (failure.message) {
  AppFailureMessage.sourceUnavailable => _localizeSourceUnavailable(
    l10n,
    failure,
  ),
  AppFailureMessage.authenticationRequired => l10n.errorAuthenticationRequired,
  AppFailureMessage.gitUnavailable => _localizeGitFailure(l10n, failure),
  AppFailureMessage.developerToolsRequired => l10n.errorDeveloperToolsRequired,
  AppFailureMessage.transportRejected =>
    failure.context['reason'] == 'embeddedCredentials'
        ? l10n.errorSourceLocatorHasQuery
        : l10n.errorTransportRejected,
  AppFailureMessage.archiveInvalid => _localizeArchiveFailure(l10n, failure),
  AppFailureMessage.skillNotFound =>
    failure.context['reason'] == 'noValidSkills'
        ? l10n.errorNoSkillsInSource
        : l10n.errorSkillNotFound,
  AppFailureMessage.staleSnapshot => l10n.errorStaleSnapshot,
  AppFailureMessage.invalidSkill => _localizeInvalidSkillFailure(l10n, failure),
  AppFailureMessage.duplicateSkill => _localizeDuplicateSkillFailure(
    l10n,
    failure,
  ),
  AppFailureMessage.externalSkillConflict => l10n.errorExternalSkillConflict,
  AppFailureMessage.updateUnsupported => l10n.updatesUnsupported,
  AppFailureMessage.activation => switch (failure.context['reason']) {
    'symbolicLinkUnavailable' => l10n.errorSymbolicLinkUnavailable,
    'adoptionTargetOccupied' => _localizeAdoptionTargetOccupied(l10n, failure),
    _ => l10n.errorActivation,
  },
  AppFailureMessage.projectRoot => _localizeProjectRootFailure(l10n, failure),
  AppFailureMessage.agent => _localizeAgentFailure(l10n, failure),
  AppFailureMessage.agentRootOwnership => _localizeAgentRootOwnership(
    l10n,
    failure,
  ),
  AppFailureMessage.repositoryBusy => l10n.errorRepositoryBusy,
  AppFailureMessage.operationCancelled => l10n.errorOperationCancelled,
  AppFailureMessage.repositoryState => l10n.errorRepositoryState,
  AppFailureMessage.controlPlaneCorrupt => _localizeControlPlaneFailure(
    l10n,
    failure,
  ),
  AppFailureMessage.migrationFailed => l10n.errorMigrationFailed,
  AppFailureMessage.revisionStoreCorrupt => l10n.errorRevisionStoreCorrupt,
  AppFailureMessage.driftResolutionUnavailable =>
    l10n.errorDriftResolutionUnavailable,
  AppFailureMessage.dirtyDraftResolutionRequired =>
    l10n.errorDirtyDraftResolutionRequired,
  AppFailureMessage.updateCandidateResolutionRequired =>
    l10n.errorUpdateCandidateResolutionRequired,
  AppFailureMessage.nameChangeNotAllowed => l10n.errorNameChangeNotAllowed,
  AppFailureMessage.finalizationRecoveryFailed =>
    l10n.errorFinalizationRecoveryFailed,
  AppFailureMessage.rollback => l10n.errorRollback,
  AppFailureMessage.io => l10n.errorIo,
  AppFailureMessage.repositoryOpen => l10n.browserRepositoryUnavailableMessage,
  AppFailureMessage.repositoryRefresh =>
    l10n.browserRepositoryUnavailableMessage,
  AppFailureMessage.documentRead => l10n.workspaceDocumentUnavailable,
  AppFailureMessage.invalidSourceInput => switch (failure.codeKey) {
    'invalidLocalLocator' ||
    'invalidFileLocator' => l10n.acquisitionErrorLocalPath,
    _ => l10n.acquisitionErrorResolve,
  },
  AppFailureMessage.inspectSource =>
    failure.codeKey == 'webSourceHasNoSkills'
        ? l10n.acquisitionErrorWebSourceHasNoSkillsBody
        : l10n.acquisitionErrorInspect,
  AppFailureMessage.installSkills => l10n.acquisitionErrorInstall,
  AppFailureMessage.refreshAfterInstall => l10n.acquisitionErrorRefresh,
  AppFailureMessage.unexpected => l10n.errorUnknown,
};

/// Says what holds an adoption target, and where, when the Workspace reports
/// it. The path is the Agent folder the user has to clean up.
String _localizeAdoptionTargetOccupied(
  AppLocalizations l10n,
  AppFailure failure,
) {
  final occupants = failure.context['occupants'];
  final first = occupants is List && occupants.isNotEmpty
      ? occupants.first
      : null;
  final path = first is Map ? first['targetPath'] : null;
  if (path is! String || path.isEmpty) return l10n.errorAdoptionTargetOccupied;
  return switch (failure.context['occupant']) {
    'file' => l10n.errorAdoptionTargetOccupiedFile(path),
    'invalidSkill' => l10n.errorAdoptionTargetOccupiedInvalidSkill(path),
    'directoryWithContent' =>
      l10n.errorAdoptionTargetOccupiedDirectoryWithContent(path),
    'otherSkill' => l10n.errorAdoptionTargetOccupiedOtherSkill(path),
    'sameSlotSkill' => l10n.errorAdoptionTargetOccupiedSameSlotSkill(path),
    'link' => l10n.errorAdoptionTargetOccupiedLink(path),
    _ => l10n.errorAdoptionTargetOccupied,
  };
}

String _localizeGitFailure(AppLocalizations l10n, AppFailure failure) {
  if (failure.codeKey == 'gitUnavailable') return l10n.errorGitUnavailable;
  if (failure.context['timedOut'] == true) return l10n.errorGitNetwork;
  return switch (failure.context['reason']) {
    'fileCountExceeded' ||
    'treeOutputExceededLimit' => l10n.errorGitFileCountExceeded,
    'network' ||
    'tls' ||
    'certificate' ||
    'proxy' ||
    'timedOut' => l10n.errorGitNetwork,
    'refNotFound' => l10n.errorGitRefNotFound,
    _ => l10n.errorGitFailed,
  };
}

String _localizeSourceUnavailable(AppLocalizations l10n, AppFailure failure) =>
    switch (failure.context['reason']) {
      'sourceRootNotDirectory' => l10n.errorLocalFolderNotFound,
      'searchRootUnavailable' => l10n.errorRepositorySubpathNotFound,
      _ => l10n.errorSourceUnavailable,
    };

String _localizeContentLimit(AppLocalizations l10n, AppFailure failure) {
  final context = failure.context;
  return switch ((
    context['limit'],
    context['maximumFileCount'],
    context['maximumByteSize'],
  )) {
    ('fileCount', final int maximum, _) => l10n.errorSkillFileCountExceeded(
      maximum,
    ),
    ('byteSize', _, final int maximum) => l10n.errorSkillByteSizeExceeded(
      maximum ~/ (1024 * 1024),
    ),
    _ => l10n.errorSkillContentLimitExceeded,
  };
}

/// Names the `SKILL.md` that discovery could not use, when the Workspace
/// reports which one. The path is relative to the Source, never a private
/// Workspace path.
String _localizeSkillMarkdownFailure(
  AppLocalizations l10n,
  AppFailure failure,
) {
  final path = failure.context['path'];
  final at = path is String && path.isNotEmpty ? path : null;
  return switch (failure.context['reason']) {
    'unsupportedSkillName' || 'windowsReservedDeviceName' =>
      at == null
          ? l10n.errorSkillNameUnsupported
          : l10n.errorSkillNameUnsupportedAt(at),
    'invalidFrontmatter' ||
    'invalidSkillFrontmatter' ||
    'missingName' ||
    'missingDescription' =>
      at == null
          ? l10n.errorSkillMarkdownInvalid
          : l10n.errorSkillMarkdownInvalidAt(at),
    'missingSkillMarkdown' => l10n.errorSkillMarkdownInvalid,
    _ => l10n.errorInvalidSkill,
  };
}

String _localizeArchiveFailure(AppLocalizations l10n, AppFailure failure) =>
    failure.codeKey == 'digestMismatch'
    ? l10n.errorDigestMismatch
    : l10n.errorArchiveInvalid;

String _localizeInvalidSkillFailure(
  AppLocalizations l10n,
  AppFailure failure,
) => switch (failure.codeKey) {
  'skillContentLimitExceeded' => _localizeContentLimit(l10n, failure),
  'invalidSource' => l10n.errorInvalidSource,
  'personalTagNotFound' => l10n.errorPersonalTagNotFound,
  'duplicatePersonalTag' => l10n.errorDuplicatePersonalTag,
  'unsupportedSkillName' => l10n.errorSkillNameUnsupported,
  _ => _localizeSkillMarkdownFailure(l10n, failure),
};

String _localizeDuplicateSkillFailure(
  AppLocalizations l10n,
  AppFailure failure,
) => failure.codeKey == 'sourceReplacementRequired'
    ? l10n.errorSourceReplacementRequired
    : failure.context['reason'] == 'duplicateSlotsWithinSource'
    ? l10n.errorDuplicateSkillsWithinSource
    : l10n.errorDuplicateSkill;

String _localizeProjectRootFailure(AppLocalizations l10n, AppFailure failure) =>
    switch (failure.codeKey) {
      'invalidProjectRoot' => l10n.errorInvalidProjectRoot,
      'projectRootConflict' => l10n.errorProjectRootConflict,
      _ => l10n.errorProjectRoot,
    };

String _localizeAgentFailure(AppLocalizations l10n, AppFailure failure) =>
    failure.codeKey == 'duplicateAgentId'
    ? l10n.errorDuplicateAgentId
    : l10n.errorAgent;

String _localizeControlPlaneFailure(
  AppLocalizations l10n,
  AppFailure failure,
) => switch (failure.codeKey) {
  'unsupportedStateVersion' ||
  'unsupportedJournalVersion' => l10n.errorUnsupportedWorkspaceVersion,
  'journalMaintenanceFailed' => l10n.errorWorkspaceMaintenanceFailed,
  _ => l10n.errorControlPlaneCorrupt,
};

String? localizeAppFailureRecoveryAction(
  AppLocalizations l10n,
  AppRecoveryPolicy policy,
) => switch (policy) {
  AppRecoveryPolicy.none => null,
  AppRecoveryPolicy.retryExplicitly => l10n.commonRetry,
  AppRecoveryPolicy.refresh => l10n.commonRefresh,
  AppRecoveryPolicy.refreshThenReview => l10n.commonRefreshAndReview,
};

String _localizeAgentRootOwnership(AppLocalizations l10n, AppFailure failure) {
  final context = failure.context;
  final reason = context['reason'];
  final issueReason = context['issueReason'];
  final rootPath = context['rootPath'];
  final path = rootPath is String && rootPath.isNotEmpty ? rootPath : null;

  final issues = <({Object? reason, String path})>[
    if (context['issues'] case final List<Object?> listed)
      for (final issue in listed)
        if (issue
            case {
              'issueReason': final Object? reason,
              'rootPath': final String path,
            }
            when path.isNotEmpty)
          (reason: reason, path: path),
  ];
  // Each folder on its own line, so none is hidden behind a count.
  if (issues.length > 1 &&
      (reason == 'agentRootOwnershipBlocked' ||
          reason == 'agentRootOwnershipStillInvalid')) {
    return [
      reason == 'agentRootOwnershipBlocked'
          ? l10n.errorAgentRootOwnershipBlockedCount(issues.length)
          : l10n.errorAgentRootOwnershipStillInvalidCount(issues.length),
      for (final issue in issues)
        _agentRootIssue(l10n, issue.reason, issue.path) ??
            l10n.errorAgentRootOwnershipStillInvalid(issue.path),
    ].join('\n');
  }

  return switch (reason) {
    'agentRootOwnershipBlocked' when path != null =>
      _agentRootIssue(l10n, issueReason, path) ?? l10n.errorAgentRootOwnership,
    'agentRootOwnershipAuthorizationRejected' =>
      l10n.errorAgentRootOwnershipAuthorizationRejected,
    'agentRootOwnershipRepairFailed' =>
      l10n.errorAgentRootOwnershipRepairFailed,
    'agentRootOwnershipStillInvalid' when path != null =>
      l10n.errorAgentRootOwnershipStillInvalid(path),
    'agentRootOwnershipUnsupported' => l10n.errorAgentRootOwnershipUnsupported,
    _ => l10n.errorAgentRootOwnership,
  };
}

/// The folder's own problem, or null for an ownership mismatch, which repair
/// handles rather than the user.
String? _agentRootIssue(AppLocalizations l10n, Object? reason, String path) =>
    switch (reason) {
      'outsideUserHome' => l10n.errorAgentRootOwnershipOutsideHome(path),
      'notDirectory' => l10n.errorAgentRootOwnershipNotDirectory(path),
      'inspectionFailed' => l10n.errorAgentRootOwnershipInspectionFailed(path),
      _ => null,
    };
