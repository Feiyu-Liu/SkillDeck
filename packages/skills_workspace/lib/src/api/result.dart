import '../domain/identifiers.dart';
import '../domain/immutable.dart';

/// Stable, presentation-agnostic error codes returned for expected failures.
enum SkillsErrorCode {
  sourceUnavailable,
  sourceAuthenticationRequired,
  gitUnavailable,
  gitFailed,

  /// The host's developer command line tools are missing or still
  /// installing, so system Git cannot run. Recovery is an operating-system
  /// install performed outside the App, never a retry of the same request.
  /// `context['developerTools']` is `'required'` or `'installing'`.
  developerToolsRequired,
  transportRejected,
  httpFailure,
  digestMismatch,
  archiveInvalid,
  skillNotFound,
  staleSnapshot,
  staleInstallTakeover,
  staleActivationTakeover,
  invalidSkill,
  unsupportedSkillName,
  skillContentLimitExceeded,
  duplicateSkillSlot,
  sourceReplacementRequired,
  updateUnsupported,
  externalConflict,
  activationUnavailable,
  activationUnsupported,
  projectRootNotFound,
  invalidProjectRoot,
  projectRootConflict,
  agentNotFound,
  duplicateAgentId,
  personalTagNotFound,
  duplicatePersonalTag,
  repositoryBusy,
  operationCancelled,
  unsupportedStateVersion,
  unsupportedJournalVersion,
  stateCorrupt,
  journalCorrupt,
  journalMaintenanceFailed,
  rollbackFailed,
  recoveryFailed,
  ioFailure,
  operationFailed,

  // Skill Workspace control-plane and revision-history outcomes.
  migrationFailed,
  controlPlaneCorrupt,
  revisionStoreCorrupt,
  invalidEffectiveFilePath,
  effectiveFileNotFound,
  finalizationRecoveryFailed,

  // Draft, history, and Update Candidate preconditions.
  dirtyDraftResolutionRequired,
  updateCandidateResolutionRequired,
  draftChangedDuringPublish,
  declaredNameChangeNotAllowed,
  historicalNameMismatch,

  /// A drift review no longer authorizes this request. `context['reason']` is
  /// `effectiveRevisionChanged`, `artifactChanged`, `foreignReview`, or
  /// `artifactNotFound`.
  staleDriftReview,

  /// The reviewed artifact cannot support the requested resolution.
  /// `context['reason']` is `unsafeInspection`, `keepNotAllowed`, or
  /// `exportNotAllowed`.
  driftResolutionUnavailable,
}

/// Stable, presentation-agnostic warning codes attached to terminal outcomes.
enum SkillsWarningCode {
  internalSymlinkSkipped,
  sourceEntrySkipped,
  noActivationTarget,
  projectSymbolicLinkPortability,
  duplicateExposure,
  agentUndetected,
  activationTargetSkipped,
  recoveryCleanupDeferred,
  draftPreservedAfterPublish,
  finalizationDeferred,

  /// Several configured Agent roots resolve to one physical directory, so
  /// the Skill was activated there once for all of them.
  sharedActivationLocation,
}

/// Non-fatal structured information attached to a terminal outcome.
final class SkillsWarning {
  /// Creates a warning with immutable structured context.
  SkillsWarning({required this.code, Map<String, Object?> context = const {}})
    : context = Map.unmodifiable(context);

  /// The stable machine-readable warning code.
  final SkillsWarningCode code;

  /// Bounded, credential-free context for presentation and diagnostics.
  final Map<String, Object?> context;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillsWarning &&
          code == other.code &&
          mapsEqual(context, other.context);

  @override
  int get hashCode => Object.hash(code, unorderedMapHash(context));

  @override
  String toString() => 'SkillsWarning(code: $code, context: $context)';
}

/// A terminal outcome from an expected Skill Workspace operation.
sealed class SkillsResult<T> {
  const SkillsResult();

  /// Whether the operation completed all committed and finalization work.
  bool get isSuccess;

  /// Whether the operation failed before its business commit point.
  bool get isFailure;

  /// Whether business state committed but required finalization is outstanding.
  bool get isCommittedFinalizationPending;

  /// The completed value, or `null` for other terminal states.
  T? get valueOrNull;

  /// The failure, or `null` for non-failure terminal states.
  SkillsFailure<T>? get failureOrNull;

  /// The committed-pending outcome, or `null` for other terminal states.
  SkillsCommittedFinalizationPending<T>? get finalizationPendingOrNull;

  /// Typed non-fatal warnings associated with this outcome.
  List<SkillsWarning> get warnings;

  /// Exhaustively maps the three terminal states to one value.
  R fold<R>({
    required R Function(SkillsSuccess<T> success) onSuccess,
    required R Function(SkillsFailure<T> failure) onFailure,
    required R Function(SkillsCommittedFinalizationPending<T> pending)
    onCommittedFinalizationPending,
  });
}

/// A fully completed operation outcome.
final class SkillsSuccess<T> extends SkillsResult<T> {
  /// Creates a successful outcome.
  SkillsSuccess({
    required this.value,
    this.changed = false,
    List<SkillsWarning> warnings = const [],
  }) : warnings = List.unmodifiable(warnings);

  /// The operation result value.
  final T value;

  /// Whether the operation changed business-authoritative state.
  final bool changed;

  @override
  final List<SkillsWarning> warnings;

  @override
  bool get isSuccess => true;

  @override
  bool get isFailure => false;

  @override
  bool get isCommittedFinalizationPending => false;

  @override
  T get valueOrNull => value;

  @override
  SkillsFailure<T>? get failureOrNull => null;

  @override
  SkillsCommittedFinalizationPending<T>? get finalizationPendingOrNull => null;

  @override
  R fold<R>({
    required R Function(SkillsSuccess<T> success) onSuccess,
    required R Function(SkillsFailure<T> failure) onFailure,
    required R Function(SkillsCommittedFinalizationPending<T> pending)
    onCommittedFinalizationPending,
  }) => onSuccess(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillsSuccess<T> &&
          value == other.value &&
          changed == other.changed &&
          listsEqual(warnings, other.warnings);

  @override
  int get hashCode => Object.hash(value, changed, Object.hashAll(warnings));

  @override
  String toString() =>
      'SkillsSuccess(value: $value, changed: $changed, warnings: $warnings)';
}

/// An expected failure before the business commit point.
final class SkillsFailure<T> extends SkillsResult<T> {
  /// Creates a typed failure.
  SkillsFailure({
    required this.code,
    Map<String, Object?> context = const {},
    this.diagnostic,
    List<SkillsWarning> warnings = const [],
  }) : context = Map.unmodifiable(context),
       warnings = List.unmodifiable(warnings);

  /// The stable machine-readable failure code.
  final SkillsErrorCode code;

  /// Bounded, credential-free context for presentation and diagnostics.
  final Map<String, Object?> context;

  /// An optional redacted developer diagnostic.
  final String? diagnostic;

  @override
  final List<SkillsWarning> warnings;

  @override
  bool get isSuccess => false;

  @override
  bool get isFailure => true;

  @override
  bool get isCommittedFinalizationPending => false;

  @override
  T? get valueOrNull => null;

  @override
  SkillsFailure<T> get failureOrNull => this;

  @override
  SkillsCommittedFinalizationPending<T>? get finalizationPendingOrNull => null;

  @override
  R fold<R>({
    required R Function(SkillsSuccess<T> success) onSuccess,
    required R Function(SkillsFailure<T> failure) onFailure,
    required R Function(SkillsCommittedFinalizationPending<T> pending)
    onCommittedFinalizationPending,
  }) => onFailure(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillsFailure<T> &&
          code == other.code &&
          mapsEqual(context, other.context) &&
          diagnostic == other.diagnostic &&
          listsEqual(warnings, other.warnings);

  @override
  int get hashCode => Object.hash(
    code,
    unorderedMapHash(context),
    diagnostic,
    Object.hashAll(warnings),
  );

  @override
  String toString() =>
      'SkillsFailure(code: $code, context: $context, '
      'diagnostic: $diagnostic)';
}

/// Business state committed, but mandatory roll-forward work is still pending.
///
/// This state is neither success nor failure. The Workspace resumes its
/// idempotent finalization automatically, including after a process restart.
final class SkillsCommittedFinalizationPending<T> extends SkillsResult<T> {
  /// Creates a committed-pending outcome without raw native diagnostics.
  SkillsCommittedFinalizationPending({
    required this.operationId,
    required this.committedRepositoryRevision,
    List<SkillsWarning> warnings = const [],
  }) : warnings = List.unmodifiable(warnings);

  /// The stable operation whose finalization will be resumed.
  final OperationId operationId;

  /// The repository revision already committed at the business commit point.
  final RepositoryRevision committedRepositoryRevision;

  @override
  final List<SkillsWarning> warnings;

  @override
  bool get isSuccess => false;

  @override
  bool get isFailure => false;

  @override
  bool get isCommittedFinalizationPending => true;

  @override
  T? get valueOrNull => null;

  @override
  SkillsFailure<T>? get failureOrNull => null;

  @override
  SkillsCommittedFinalizationPending<T> get finalizationPendingOrNull => this;

  @override
  R fold<R>({
    required R Function(SkillsSuccess<T> success) onSuccess,
    required R Function(SkillsFailure<T> failure) onFailure,
    required R Function(SkillsCommittedFinalizationPending<T> pending)
    onCommittedFinalizationPending,
  }) => onCommittedFinalizationPending(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillsCommittedFinalizationPending<T> &&
          operationId == other.operationId &&
          committedRepositoryRevision == other.committedRepositoryRevision &&
          listsEqual(warnings, other.warnings);

  @override
  int get hashCode => Object.hash(
    operationId,
    committedRepositoryRevision,
    Object.hashAll(warnings),
  );

  @override
  String toString() =>
      'SkillsCommittedFinalizationPending(operationId: $operationId, '
      'committedRepositoryRevision: $committedRepositoryRevision, '
      'warnings: $warnings)';
}
