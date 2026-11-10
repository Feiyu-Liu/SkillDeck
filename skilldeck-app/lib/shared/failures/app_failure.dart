abstract interface class AppWarning {
  String get codeKey;

  Map<String, Object?> get context;
}

enum AppFailureMessage {
  sourceUnavailable,
  authenticationRequired,
  gitUnavailable,
  developerToolsRequired,
  transportRejected,
  archiveInvalid,
  skillNotFound,
  staleSnapshot,
  invalidSkill,
  duplicateSkill,
  externalSkillConflict,
  updateUnsupported,
  activation,
  projectRoot,
  agent,
  agentRootOwnership,
  repositoryBusy,
  operationCancelled,
  repositoryState,
  controlPlaneCorrupt,
  migrationFailed,
  revisionStoreCorrupt,
  driftResolutionUnavailable,
  dirtyDraftResolutionRequired,
  updateCandidateResolutionRequired,
  nameChangeNotAllowed,
  finalizationRecoveryFailed,
  rollback,
  io,
  repositoryOpen,
  repositoryRefresh,
  documentRead,
  invalidSourceInput,
  inspectSource,
  installSkills,
  refreshAfterInstall,
  unexpected,
}

enum AppRecoveryPolicy { none, retryExplicitly, refresh, refreshThenReview }

abstract interface class AppFailure implements Exception {
  String get codeKey;

  String get operationKey;

  AppFailureMessage get message;

  AppRecoveryPolicy get recoveryPolicy;

  Map<String, Object?> get context;

  String? get diagnostic;

  Iterable<AppWarning> get warnings;
}

final class UnexpectedAppFailure implements AppFailure {
  const UnexpectedAppFailure({
    required this.operationKey,
    this.message = AppFailureMessage.unexpected,
    this.recoveryPolicy = AppRecoveryPolicy.retryExplicitly,
  });

  @override
  final String operationKey;

  @override
  final AppFailureMessage message;

  @override
  final AppRecoveryPolicy recoveryPolicy;

  @override
  String get codeKey => 'unexpected';

  @override
  Map<String, Object?> get context => const {};

  @override
  String? get diagnostic => null;

  @override
  Iterable<AppWarning> get warnings => const [];

  @override
  String toString() => 'UnexpectedAppFailure($operationKey)';
}

AppFailure normalizeAppFailure(
  Object error, {
  required String operationKey,
  AppFailureMessage message = AppFailureMessage.unexpected,
  AppRecoveryPolicy recoveryPolicy = AppRecoveryPolicy.retryExplicitly,
}) {
  if (error case final AppFailure failure) return failure;
  return UnexpectedAppFailure(
    operationKey: operationKey,
    message: message,
    recoveryPolicy: recoveryPolicy,
  );
}
