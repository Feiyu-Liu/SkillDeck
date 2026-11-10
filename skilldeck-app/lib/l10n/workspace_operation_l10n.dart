import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/generated/app_localizations.dart';

/// [commandLineBusy] names the command line as the lock holder while a
/// Command Host write is running, rather than a generic "repository".
String localizeWorkspacePhase(
  AppLocalizations l10n,
  WorkspaceOperationPhase phase, {
  bool commandLineBusy = false,
}) => switch (phase) {
  WorkspaceOperationPhase.preparing => l10n.operationPreparing,
  WorkspaceOperationPhase.queued => l10n.operationPreparing,
  WorkspaceOperationPhase.inspecting => l10n.operationInspecting,
  WorkspaceOperationPhase.waitingForLock =>
    commandLineBusy
        ? l10n.operationWaitingForCommandLine
        : l10n.operationWaitingForLock,
  WorkspaceOperationPhase.planning => l10n.operationPlanning,
  WorkspaceOperationPhase.applying => l10n.operationApplying,
  WorkspaceOperationPhase.committing => l10n.operationApplying,
  WorkspaceOperationPhase.finalizing => l10n.operationRecovering,
  WorkspaceOperationPhase.recovering => l10n.operationRecovering,
  WorkspaceOperationPhase.rollingBack => l10n.operationRollingBack,
  WorkspaceOperationPhase.succeeded => l10n.operationSucceeded,
  WorkspaceOperationPhase.failed => l10n.operationFailed,
  WorkspaceOperationPhase.cancelled => l10n.operationCancelled,
};

String localizeWorkspaceWarning(
  AppLocalizations l10n,
  WorkspaceWarning warning,
) => switch (warning.code) {
  WorkspaceWarningCode.internalSymlinkSkipped =>
    l10n.warningInternalSymlinkSkipped,
  WorkspaceWarningCode.sourceEntrySkipped => l10n.warningSourceEntrySkipped,
  WorkspaceWarningCode.noActivationTarget => l10n.warningNoActivationTarget,
  WorkspaceWarningCode.projectSymbolicLinkPortability =>
    l10n.warningProjectSymlinkPortability,
  WorkspaceWarningCode.duplicateExposure => l10n.warningDuplicateExposure,
  WorkspaceWarningCode.agentUndetected => l10n.warningAgentUndetected,
  WorkspaceWarningCode.activationTargetSkipped =>
    l10n.warningActivationTargetSkipped,
  WorkspaceWarningCode.recoveryCleanupDeferred =>
    l10n.warningRecoveryCleanupDeferred,
  WorkspaceWarningCode.draftPreservedAfterPublish =>
    l10n.warningRecoveryCleanupDeferred,
  WorkspaceWarningCode.finalizationDeferred =>
    l10n.warningRecoveryCleanupDeferred,
  WorkspaceWarningCode.sharedActivationLocation =>
    l10n.warningSharedActivationLocation,
};
