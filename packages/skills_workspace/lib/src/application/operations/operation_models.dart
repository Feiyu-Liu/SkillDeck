import '../../domain/identifiers.dart';
import '../runtime/revision_engine_port.dart';
import 'workspace_business_changes.dart';

enum OperationJournalPhase {
  prepared,
  applying,
  committed,
  finalizing,
  completed,
}

enum OperationStepStatus { planned, started, completed }

enum PreparationStepKind {
  revisionCandidate,
  recoveryEvidence,
  revisionBundle,
  materialization,
  durabilityVerification,
  destructiveBarrier,
  destructiveResources,
}

enum ApplyingStepKind { materializationReplacement, destructiveReplacement }

enum FinalizationStepKind {
  materializationVerification,
  retentionReconciliation,
  draftLifecycle,
  backupRotation,
  stagingCleanup,
  recoveryEvidenceCleanup,
}

enum OperationAbortReason {
  cancelled,
  staleRepositoryRevision,
  externalPreconditionChanged,
  lockUnavailable,
  snapshotReadFailed,
  journalWriteFailed,
  preparationFailed,
  applyFailed,
  businessCommitFailed,
}

/// A bounded, credential-free classification of the exception behind a
/// `preparationFailed`, `applyFailed` or `businessCommitFailed` abort.
///
/// It exists for diagnostics and analytics only: it never carries messages,
/// paths or raw errors, and callers must not branch recovery on it.
enum OperationAbortDetail {
  /// Two recovery entries resolved to one physical mutation target.
  recoveryConflict,

  /// Recovery evidence could not be captured, verified or restored.
  recoveryEvidence,

  /// A planning or plan-building invariant threw (`Error` subclasses).
  planInvariant,

  /// The filesystem refused an operation.
  filesystem,

  /// Anything else.
  unknown,
}

/// An exception that knows which [OperationAbortDetail] it stands for, so the
/// coordinator never has to inspect infrastructure types.
abstract interface class OperationAbortDetailSource {
  OperationAbortDetail get abortDetail;
}

/// Classifies the exception behind an abort.
typedef OperationAbortClassifier = OperationAbortDetail Function(Object error);

/// The infrastructure-free default: self-describing exceptions, then `Error`
/// subclasses, then unknown. The platform layer wraps it to recognize I/O.
OperationAbortDetail classifyOperationAbort(Object error) => switch (error) {
  OperationAbortDetailSource(:final abortDetail) => abortDetail,
  Error() => OperationAbortDetail.planInvariant,
  _ => OperationAbortDetail.unknown,
};

/// A reviewed filesystem precondition changed before the business commit.
///
/// Recovery adapters throw this only for a caller-supplied pre-capture guard.
/// It is deliberately distinct from generic recovery corruption or I/O errors
/// so command handlers can return a retryable stale-state result.
final class ExternalOperationPreconditionChanged implements Exception {
  const ExternalOperationPreconditionChanged();
}

enum OperationPendingReason { rollbackFailed, finalizationFailed }

/// A filesystem recovery decision that must be reflected idempotently in the
/// SQLite control plane before its finalization step can be completed.
sealed class OperationFinalizationEffect {
  const OperationFinalizationEffect();
}

final class DeleteReanchoredDraftEffect extends OperationFinalizationEffect {
  const DeleteReanchoredDraftEffect({
    required this.managedSkillId,
    required this.expectedBaseObjectId,
  });

  final ManagedSkillId managedSkillId;
  final RevisionObjectId expectedBaseObjectId;
}

/// An opaque reference interpreted only by the Operation Recovery adapter.
final class RecoveryReference {
  RecoveryReference(String encoded) : encoded = _requireOpaque(encoded);

  final String encoded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecoveryReference && encoded == other.encoded;

  @override
  int get hashCode => encoded.hashCode;

  @override
  String toString() => 'RecoveryReference(<opaque>)';
}

sealed class OperationStep {
  OperationStep({required this.stepId, required this.recoveryReference}) {
    if (stepId.trim().isEmpty) {
      throw ArgumentError.value(stepId, 'stepId', 'must not be empty');
    }
  }

  final String stepId;
  final RecoveryReference recoveryReference;
}

final class PreparationOperationStep extends OperationStep {
  PreparationOperationStep({
    required super.stepId,
    required super.recoveryReference,
    required this.kind,
  });

  final PreparationStepKind kind;
}

final class ApplyingOperationStep extends OperationStep {
  ApplyingOperationStep({
    required super.stepId,
    required super.recoveryReference,
    required this.kind,
  });

  final ApplyingStepKind kind;
}

final class FinalizationOperationStep extends OperationStep {
  FinalizationOperationStep({
    required super.stepId,
    required super.recoveryReference,
    required this.kind,
  });

  final FinalizationStepKind kind;
}

/// Internal opaque identity for one source lineage.
final class SourceLineageReference {
  SourceLineageReference(String encoded) : encoded = _requireOpaque(encoded);

  final String encoded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceLineageReference && encoded == other.encoded;

  @override
  int get hashCode => encoded.hashCode;
}

/// An internal immutable revision address selected by SQLite.
///
/// The object ID is meaningful only inside its Source Lineage. Store paths,
/// generations, and Git refs remain adapter-owned details.
final class RevisionAddress {
  const RevisionAddress({required this.sourceLineage, required this.objectId});

  final SourceLineageReference sourceLineage;
  final RevisionObjectId objectId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RevisionAddress &&
          sourceLineage == other.sourceLineage &&
          objectId == other.objectId;

  @override
  int get hashCode => Object.hash(sourceLineage, objectId);
}

/// Old and intended Upstream/Effective selections for one managed Skill.
///
/// A null pair represents absence, as used by initial Install and Removal.
/// Source Replacement may move the old and intended pairs across lineages.
final class RevisionSelectionChangePlan {
  RevisionSelectionChangePlan({
    required this.managedSkillId,
    required this.previousUpstream,
    required this.previousEffective,
    required this.intendedUpstream,
    required this.intendedEffective,
  }) {
    _requireAddressPair(
      upstream: previousUpstream,
      effective: previousEffective,
      name: 'previous',
    );
    _requireAddressPair(
      upstream: intendedUpstream,
      effective: intendedEffective,
      name: 'intended',
    );
  }

  final ManagedSkillId managedSkillId;
  final RevisionAddress? previousUpstream;
  final RevisionAddress? previousEffective;
  final RevisionAddress? intendedUpstream;
  final RevisionAddress? intendedEffective;

  static void _requireAddressPair({
    required RevisionAddress? upstream,
    required RevisionAddress? effective,
    required String name,
  }) {
    if ((upstream == null) != (effective == null)) {
      throw ArgumentError('$name Upstream and Effective must coexist.');
    }
    if (upstream != null &&
        upstream.sourceLineage != effective!.sourceLineage) {
      throw ArgumentError('$name revisions must share one Source Lineage.');
    }
  }
}

final class OperationSubjectPlan {
  OperationSubjectPlan({
    required this.reference,
    required this.managedSkillId,
    required this.displayName,
    this.sourceLineage,
    this.beforeObjectId,
    this.afterObjectId,
    this.beforeContentHash,
    this.afterContentHash,
  }) {
    if (displayName.trim().isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'must not be empty',
      );
    }
    if (sourceLineage == null &&
        (beforeObjectId != null || afterObjectId != null)) {
      throw ArgumentError('Revision object IDs require a Source Lineage.');
    }
    _requireOptionalContentHash(beforeContentHash, 'beforeContentHash');
    _requireOptionalContentHash(afterContentHash, 'afterContentHash');
  }

  final OperationSubjectReference reference;
  final ManagedSkillId managedSkillId;
  final String displayName;
  final SourceLineageReference? sourceLineage;
  final RevisionObjectId? beforeObjectId;
  final RevisionObjectId? afterObjectId;
  final String? beforeContentHash;
  final String? afterContentHash;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OperationSubjectPlan &&
          reference == other.reference &&
          managedSkillId == other.managedSkillId &&
          displayName == other.displayName &&
          sourceLineage == other.sourceLineage &&
          beforeObjectId == other.beforeObjectId &&
          afterObjectId == other.afterObjectId &&
          beforeContentHash == other.beforeContentHash &&
          afterContentHash == other.afterContentHash;

  @override
  int get hashCode => Object.hash(
    reference,
    managedSkillId,
    displayName,
    sourceLineage,
    beforeObjectId,
    afterObjectId,
    beforeContentHash,
    afterContentHash,
  );
}

/// The compact history projection committed when finalization succeeds.
final class OperationRecordPlan {
  OperationRecordPlan({
    required this.operationId,
    required this.kind,
    required List<OperationSubjectPlan> subjects,
    this.retainWithoutSubjects = false,
  }) : subjects = List.unmodifiable(subjects) {
    if (kind.trim().isEmpty) {
      throw ArgumentError.value(kind, 'kind', 'must not be empty');
    }
    final references = subjects.map((subject) => subject.reference).toSet();
    if (references.length != subjects.length) {
      throw ArgumentError.value(subjects, 'subjects', 'contains duplicates');
    }
    if (subjects.any(
      (subject) => subject.reference.operationId != operationId,
    )) {
      throw ArgumentError.value(
        subjects,
        'subjects',
        'must belong to the record Operation ID',
      );
    }
    final managedSkillIds = subjects
        .map((subject) => subject.managedSkillId)
        .toSet();
    if (managedSkillIds.length != subjects.length) {
      throw ArgumentError.value(
        subjects,
        'subjects',
        'contains duplicate managed Skills',
      );
    }
    if (subjects.isEmpty && !retainWithoutSubjects) {
      throw ArgumentError(
        'A record without subjects must retain an independent meaning.',
      );
    }
  }

  final OperationId operationId;
  final String kind;
  final List<OperationSubjectPlan> subjects;
  final bool retainWithoutSubjects;

  /// Removes only matching per-Skill or per-lineage subjects.
  ///
  /// Returns `null` when no subject and no independent record meaning remains.
  OperationRecordPlan? withoutSubjects({
    ManagedSkillId? managedSkillId,
    SourceLineageReference? sourceLineage,
  }) {
    if (managedSkillId == null && sourceLineage == null) {
      throw ArgumentError('At least one subject selector is required.');
    }
    final retained = subjects
        .where((subject) {
          final matchesManagedSkill =
              managedSkillId == null ||
              subject.managedSkillId == managedSkillId;
          final matchesSourceLineage =
              sourceLineage == null || subject.sourceLineage == sourceLineage;
          return !(matchesManagedSkill && matchesSourceLineage);
        })
        .toList(growable: false);
    if (retained.isEmpty && !retainWithoutSubjects) {
      return null;
    }
    return OperationRecordPlan(
      operationId: operationId,
      kind: kind,
      subjects: retained,
      retainWithoutSubjects: retainWithoutSubjects,
    );
  }
}

/// The durable operation definition stored in one Journal row.
///
/// A Journal starts with a [PreparedOperationEnvelope] when candidate
/// construction determines facts that cannot be known before the first
/// operation-scoped filesystem write. It is later sealed to an immutable
/// [OperationPlan] while the Journal is still Prepared.
sealed class OperationJournalDefinition {
  const OperationJournalDefinition();

  OperationId get operationId;
  RepositoryRevision get expectedRepositoryRevision;
  RepositoryRevision get committedRepositoryRevision;
  int get operationGeneration;
  List<PreparationOperationStep> get preparationSteps;
  OperationRecordPlan get record;
}

/// The minimal recoverable contract persisted before candidate construction.
///
/// Preparation steps contain only opaque Recovery References. Object IDs,
/// revision selections, and branch-specific business mutations belong to the
/// later sealed [OperationPlan].
final class PreparedOperationEnvelope extends OperationJournalDefinition {
  PreparedOperationEnvelope({
    required this.operationId,
    required this.expectedRepositoryRevision,
    required this.committedRepositoryRevision,
    required this.operationGeneration,
    required List<PreparationOperationStep> preparationSteps,
    required this.record,
  }) : preparationSteps = List.unmodifiable(preparationSteps) {
    _requireOperationDefinition(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: committedRepositoryRevision,
      operationGeneration: operationGeneration,
      preparationSteps: preparationSteps,
      record: record,
    );
  }

  @override
  final OperationId operationId;
  @override
  final RepositoryRevision expectedRepositoryRevision;
  @override
  final RepositoryRevision committedRepositoryRevision;
  @override
  final int operationGeneration;
  @override
  final List<PreparationOperationStep> preparationSteps;
  @override
  final OperationRecordPlan record;

  /// Requires a sealed plan to retain every already-journaled fact exactly.
  bool isSealedBy(OperationPlan plan) {
    if (plan.operationId != operationId ||
        plan.expectedRepositoryRevision != expectedRepositoryRevision ||
        plan.committedRepositoryRevision != committedRepositoryRevision ||
        plan.operationGeneration != operationGeneration ||
        plan.record.operationId != record.operationId ||
        plan.record.kind != record.kind ||
        !_recordIsProjectionOf(record, plan.record) ||
        plan.preparationSteps.length < preparationSteps.length) {
      return false;
    }
    for (var index = 0; index < preparationSteps.length; index += 1) {
      if (!_samePreparationStep(
        preparationSteps[index],
        plan.preparationSteps[index],
      )) {
        return false;
      }
    }
    return true;
  }
}

final class OperationPlan extends OperationJournalDefinition {
  OperationPlan({
    required this.operationId,
    required this.expectedRepositoryRevision,
    required this.committedRepositoryRevision,
    required this.operationGeneration,
    required List<PreparationOperationStep> preparationSteps,
    required List<ApplyingOperationStep> applyingSteps,
    required List<FinalizationOperationStep> finalizationSteps,
    required List<RevisionSelectionChangePlan> revisionSelectionChanges,
    WorkspaceBusinessChangeSet? businessChanges,
    required this.record,
  }) : preparationSteps = List.unmodifiable(preparationSteps),
       applyingSteps = List.unmodifiable(applyingSteps),
       finalizationSteps = List.unmodifiable(finalizationSteps),
       revisionSelectionChanges = List.unmodifiable(revisionSelectionChanges),
       businessChanges = businessChanges ?? WorkspaceBusinessChangeSet.empty {
    if (committedRepositoryRevision != expectedRepositoryRevision.next()) {
      throw ArgumentError(
        'The committed Repository Revision must immediately follow expected.',
      );
    }
    if (operationGeneration < 1) {
      throw ArgumentError.value(
        operationGeneration,
        'operationGeneration',
        'must be positive',
      );
    }
    if (record.operationId != operationId) {
      throw ArgumentError('Operation Record must share the plan Operation ID.');
    }
    final allStepIds = <String>{};
    for (final step in <OperationStep>[
      ...preparationSteps,
      ...applyingSteps,
      ...finalizationSteps,
    ]) {
      if (!allStepIds.add(step.stepId)) {
        throw ArgumentError.value(step.stepId, 'steps', 'contains duplicates');
      }
    }
    final revisionSkillIds = revisionSelectionChanges
        .map((change) => change.managedSkillId)
        .toSet();
    if (revisionSkillIds.length != revisionSelectionChanges.length) {
      throw ArgumentError.value(
        revisionSelectionChanges,
        'revisionSelectionChanges',
        'contains duplicate managed Skills',
      );
    }
  }

  @override
  final OperationId operationId;
  @override
  final RepositoryRevision expectedRepositoryRevision;
  @override
  final RepositoryRevision committedRepositoryRevision;
  @override
  final int operationGeneration;
  @override
  final List<PreparationOperationStep> preparationSteps;
  final List<ApplyingOperationStep> applyingSteps;
  final List<FinalizationOperationStep> finalizationSteps;
  final List<RevisionSelectionChangePlan> revisionSelectionChanges;
  final WorkspaceBusinessChangeSet businessChanges;
  @override
  final OperationRecordPlan record;
}

final class JournaledOperation {
  JournaledOperation({
    required OperationPlan plan,
    required this.phase,
    Map<String, OperationStepStatus> stepStatuses = const {},
  }) : definition = plan,
       stepStatuses = Map<String, OperationStepStatus>.unmodifiable(
         stepStatuses,
       );

  JournaledOperation.prepared({
    required PreparedOperationEnvelope envelope,
    required this.phase,
    Map<String, OperationStepStatus> stepStatuses = const {},
  }) : definition = envelope,
       stepStatuses = Map<String, OperationStepStatus>.unmodifiable(
         stepStatuses,
       );

  JournaledOperation.fromDefinition({
    required this.definition,
    required this.phase,
    Map<String, OperationStepStatus> stepStatuses = const {},
  }) : stepStatuses = Map<String, OperationStepStatus>.unmodifiable(
         stepStatuses,
       );

  final OperationJournalDefinition definition;
  final OperationJournalPhase phase;
  final Map<String, OperationStepStatus> stepStatuses;

  /// Compatibility accessor for callers that only accept sealed Journals.
  OperationPlan get plan {
    final value = definition;
    if (value is OperationPlan) return value;
    throw StateError('The Prepared Journal has not been sealed.');
  }

  PreparedOperationEnvelope? get preparedEnvelope =>
      definition is PreparedOperationEnvelope
      ? definition as PreparedOperationEnvelope
      : null;

  bool get isSealed => definition is OperationPlan;
}

sealed class OperationExecutionOutcome {
  const OperationExecutionOutcome();
}

final class OperationCompleted extends OperationExecutionOutcome {
  const OperationCompleted({
    required this.operationId,
    required this.committedRepositoryRevision,
    this.cleanupPending = false,
  });

  final OperationId operationId;
  final RepositoryRevision committedRepositoryRevision;
  final bool cleanupPending;
}

final class OperationRejected extends OperationExecutionOutcome {
  const OperationRejected({
    required this.reason,
    this.actualRepositoryRevision,
    this.detail,
  });

  final OperationAbortReason reason;
  final RepositoryRevision? actualRepositoryRevision;

  /// Present only when [reason] came from a caught exception.
  final OperationAbortDetail? detail;
}

final class OperationRolledBack extends OperationExecutionOutcome {
  const OperationRolledBack({
    required this.operationId,
    required this.reason,
    this.detail,
  });

  final OperationId operationId;
  final OperationAbortReason reason;

  /// Present only when [reason] came from a caught exception.
  final OperationAbortDetail? detail;
}

final class OperationRollbackPending extends OperationExecutionOutcome {
  const OperationRollbackPending({
    required this.operationId,
    required this.originalReason,
  });

  final OperationId operationId;
  final OperationAbortReason originalReason;
  OperationPendingReason get reason => OperationPendingReason.rollbackFailed;
}

final class OperationCommittedFinalizationPending
    extends OperationExecutionOutcome {
  const OperationCommittedFinalizationPending({
    required this.operationId,
    required this.committedRepositoryRevision,
  });

  final OperationId operationId;
  final RepositoryRevision committedRepositoryRevision;
  OperationPendingReason get reason =>
      OperationPendingReason.finalizationFailed;
}

enum RecoveredOperationDisposition {
  rolledBack,
  rolledForward,
  cleanedCompleted,
  retryRequired,
}

final class RecoveredOperation {
  const RecoveredOperation({
    required this.operationId,
    required this.observedPhase,
    required this.disposition,
  });

  final OperationId operationId;
  final OperationJournalPhase observedPhase;
  final RecoveredOperationDisposition disposition;
}

final class OperationRecoveryReport {
  OperationRecoveryReport(List<RecoveredOperation> operations)
    : operations = List.unmodifiable(operations);

  final List<RecoveredOperation> operations;
}

String _requireOpaque(String value) {
  if (value.trim().isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(
      value,
      'value',
      'must be a non-empty opaque token',
    );
  }
  return value;
}

void _requireOptionalContentHash(String? value, String name) {
  if (value != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a lowercase SHA-256 digest',
    );
  }
}

void _requireOperationDefinition({
  required OperationId operationId,
  required RepositoryRevision expectedRepositoryRevision,
  required RepositoryRevision committedRepositoryRevision,
  required int operationGeneration,
  required List<PreparationOperationStep> preparationSteps,
  required OperationRecordPlan record,
}) {
  if (committedRepositoryRevision != expectedRepositoryRevision.next()) {
    throw ArgumentError(
      'The committed Repository Revision must immediately follow expected.',
    );
  }
  if (operationGeneration < 1) {
    throw ArgumentError.value(
      operationGeneration,
      'operationGeneration',
      'must be positive',
    );
  }
  if (record.operationId != operationId) {
    throw ArgumentError('Operation Record must share the Operation ID.');
  }
  if (preparationSteps.isEmpty) {
    throw ArgumentError.value(
      preparationSteps,
      'preparationSteps',
      'must contain recovery-safe candidate preparation evidence',
    );
  }
  final stepIds = preparationSteps.map((step) => step.stepId).toSet();
  if (stepIds.length != preparationSteps.length) {
    throw ArgumentError.value(
      preparationSteps,
      'preparationSteps',
      'contains duplicates',
    );
  }
}

bool _samePreparationStep(
  PreparationOperationStep left,
  PreparationOperationStep right,
) =>
    left.stepId == right.stepId &&
    left.kind == right.kind &&
    left.recoveryReference == right.recoveryReference;

bool _recordIsProjectionOf(
  OperationRecordPlan projection,
  OperationRecordPlan complete,
) {
  for (final projected in projection.subjects) {
    final matches = complete.subjects.where(
      (candidate) => candidate.reference == projected.reference,
    );
    if (matches.length != 1) return false;
    final candidate = matches.single;
    if (candidate.managedSkillId != projected.managedSkillId ||
        candidate.displayName != projected.displayName ||
        !_matchesKnown(projected.sourceLineage, candidate.sourceLineage) ||
        !_matchesKnown(projected.beforeObjectId, candidate.beforeObjectId) ||
        !_matchesKnown(projected.afterObjectId, candidate.afterObjectId) ||
        !_matchesKnown(
          projected.beforeContentHash,
          candidate.beforeContentHash,
        ) ||
        !_matchesKnown(
          projected.afterContentHash,
          candidate.afterContentHash,
        )) {
      return false;
    }
  }
  return true;
}

bool _matchesKnown<T>(T? projected, T? complete) =>
    projected == null || projected == complete;
