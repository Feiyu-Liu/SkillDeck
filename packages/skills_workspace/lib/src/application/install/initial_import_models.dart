import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../../domain/revision_content.dart';
import '../activation/activation_models.dart';
import '../activation/activation_result.dart';
import '../operations/operation_models.dart';
import '../operations/workspace_business_changes.dart';
import '../runtime/revision_engine_port.dart';
import '../source/source_acquisition_models.dart';

enum InitialImportKind { install, adoption }

enum InitialImportFailureCode {
  operationCancelled,
  duplicateSkillSlot,
  sourceReplacementRequired,
  dirtyDraftResolutionRequired,
  sourceReacquisitionFailed,
  staleExternalCandidate,
  staleInstallTakeover,
  externalConflict,
  activationUnavailable,
  activationUnsupported,
  agentNotFound,
  projectRootNotFound,
  sourcePayloadInvalid,
  revisionPreparationFailed,
}

sealed class InitialImportPlanningResult<T> {
  const InitialImportPlanningResult();

  T? get valueOrNull;
  InitialImportPlanningFailure<T>? get failureOrNull;
  InitialImportTakeoverInspection? get takeoverOrNull;
}

final class PersistedSourcePayload {
  const PersistedSourcePayload({
    required this.kind,
    required this.payloadSchemaVersion,
    required this.payloadJson,
  });

  final WorkspaceSourceKind kind;
  final int payloadSchemaVersion;
  final String payloadJson;
}

final class InitialImportPlanningSuccess<T>
    extends InitialImportPlanningResult<T> {
  const InitialImportPlanningSuccess(this.value);

  final T value;

  @override
  T get valueOrNull => value;

  @override
  InitialImportPlanningFailure<T>? get failureOrNull => null;

  @override
  InitialImportTakeoverInspection? get takeoverOrNull => null;
}

final class InitialImportPlanningFailure<T>
    extends InitialImportPlanningResult<T> {
  InitialImportPlanningFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
    List<SourceAcquisitionWarning> sourceWarnings =
        const <SourceAcquisitionWarning>[],
    List<ActivationWarning> activationWarnings = const <ActivationWarning>[],
  }) : context = Map.unmodifiable(context),
       sourceWarnings = List.unmodifiable(sourceWarnings),
       activationWarnings = List.unmodifiable(activationWarnings);

  final InitialImportFailureCode code;
  final Map<String, Object?> context;
  final List<SourceAcquisitionWarning> sourceWarnings;
  final List<ActivationWarning> activationWarnings;

  @override
  T? get valueOrNull => null;

  @override
  InitialImportPlanningFailure<T> get failureOrNull => this;

  @override
  InitialImportTakeoverInspection? get takeoverOrNull => null;
}

final class InitialImportPlanningTakeoverRequired<T>
    extends InitialImportPlanningResult<T> {
  const InitialImportPlanningTakeoverRequired(this.takeover);

  final InitialImportTakeoverInspection takeover;

  @override
  T? get valueOrNull => null;

  @override
  InitialImportPlanningFailure<T>? get failureOrNull => null;

  @override
  InitialImportTakeoverInspection get takeoverOrNull => takeover;
}

final class InitialImportTakeoverInspection {
  InitialImportTakeoverInspection({
    required this.preflight,
    required List<InspectedActivationOccupancy> occupancies,
    required Map<String, String> targetSignatures,
  }) : occupancies = List.unmodifiable(occupancies),
       targetSignatures = Map.unmodifiable(targetSignatures);

  final InitialImportPreflight preflight;
  final List<InspectedActivationOccupancy> occupancies;
  final Map<String, String> targetSignatures;

  Map<String, String> get fingerprintsByTargetPath => Map.unmodifiable({
    for (final occupancy in occupancies)
      occupancy.targetPath: occupancy.fingerprint,
  });
}

/// Candidate request whose implementation is confined to the Revision worker.
final class InitialRevisionPreparationIntent {
  const InitialRevisionPreparationIntent({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.tree,
    required this.resolvedSourceRevision,
  });

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final NormalizedSkillTree tree;
  final String? resolvedSourceRevision;
}

/// Prepared immutable candidate plus the evidence needed for recovery.
final class PreparedInitialRevision {
  const PreparedInitialRevision({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.objectId,
    required this.objectFormat,
    required this.candidateRecoveryReference,
    required this.bundleRecoveryReference,
  });

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId objectId;
  final WorkspaceObjectFormat objectFormat;
  final RecoveryReference candidateRecoveryReference;
  final RecoveryReference bundleRecoveryReference;
}

final class RevisionRecoveryIntent {
  const RevisionRecoveryIntent({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.retainedRoot,
    required this.recoveryReference,
  });

  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId retainedRoot;
  final RecoveryReference recoveryReference;
}

/// One already-inspected target frozen before any candidate Store write.
final class InitialImportTargetPreflight {
  const InitialImportTargetPreflight({
    required this.target,
    required this.targetPath,
    required this.mustExist,
    this.requiresInertOccupant = false,
    this.expectedExistingContentHash,
    this.expectedExistingFingerprint,
  });

  final ResolvedActivationTarget target;
  final String targetPath;
  final bool mustExist;
  final bool requiresInertOccupant;
  final String? expectedExistingContentHash;
  final String? expectedExistingFingerprint;
}

/// One reviewed compatibility occurrence removed after canonical Activation
/// materialization succeeds.
final class InitialImportRetirementPreflight {
  const InitialImportRetirementPreflight({
    required this.target,
    required this.targetPath,
    required this.expectedExistingContentHash,
    required this.expectedExistingFingerprint,
  });

  final ResolvedActivationTarget target;
  final String targetPath;
  final String expectedExistingContentHash;
  final String expectedExistingFingerprint;
}

/// Stable per-Skill facts produced by read-only initial-import preflight.
final class InitialImportSubjectPreflight {
  InitialImportSubjectPreflight({
    required this.skill,
    required this.managedSkillId,
    required this.sourceLineage,
    required this.sourcePayload,
    required List<InitialImportTargetPreflight> targets,
    List<InitialImportRetirementPreflight> retirements =
        const <InitialImportRetirementPreflight>[],
  }) : targets = List.unmodifiable(targets),
       retirements = List.unmodifiable(retirements);

  final AcquiredSourceSkill skill;
  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final PersistedSourcePayload sourcePayload;
  final List<InitialImportTargetPreflight> targets;
  final List<InitialImportRetirementPreflight> retirements;
}

/// Immutable read-only result that is safe to retain before Journaling.
///
/// It contains no Store object ID, candidate path, Bundle path, or recovery
/// reference. Those facts may be created only after its Prepared envelope has
/// become durable.
final class InitialImportPreflight {
  InitialImportPreflight({
    required this.kind,
    required this.snapshotRevision,
    required this.plannedAtMicros,
    required List<InitialImportSubjectPreflight> subjects,
    required List<InitialRevisionPreparationIntent> revisionIntents,
    List<SourceAcquisitionWarning> sourceWarnings =
        const <SourceAcquisitionWarning>[],
    List<ActivationWarning> activationWarnings = const <ActivationWarning>[],
  }) : subjects = List.unmodifiable(subjects),
       revisionIntents = List.unmodifiable(revisionIntents),
       sourceWarnings = List.unmodifiable(sourceWarnings),
       activationWarnings = List.unmodifiable(activationWarnings) {
    if (subjects.isEmpty || subjects.length != revisionIntents.length) {
      throw ArgumentError(
        'Initial import subjects and revision intents must align.',
      );
    }
    final subjectIds = subjects
        .map((subject) => subject.managedSkillId)
        .toSet();
    final intentIds = revisionIntents
        .map((intent) => intent.managedSkillId)
        .toSet();
    if (subjectIds.length != subjects.length ||
        intentIds.length != revisionIntents.length ||
        !subjectIds.containsAll(intentIds)) {
      throw ArgumentError(
        'Initial import subjects and revision intents must be one-to-one.',
      );
    }
  }

  final InitialImportKind kind;
  final RepositoryRevision snapshotRevision;
  final int plannedAtMicros;
  final List<InitialImportSubjectPreflight> subjects;
  final List<InitialRevisionPreparationIntent> revisionIntents;
  final List<SourceAcquisitionWarning> sourceWarnings;
  final List<ActivationWarning> activationWarnings;

  Set<ManagedSkillId> get affectedSkillIds =>
      Set.unmodifiable(subjects.map((subject) => subject.managedSkillId));
}

sealed class InitialImportMaterializationIntent {
  const InitialImportMaterializationIntent({
    required this.managedSkillId,
    required this.slotKey,
    required this.revision,
  });

  final ManagedSkillId managedSkillId;
  final String slotKey;
  final RevisionAddress revision;
}

final class RepositoryCopyMaterializationIntent
    extends InitialImportMaterializationIntent {
  const RepositoryCopyMaterializationIntent({
    required super.managedSkillId,
    required super.slotKey,
    required super.revision,
  });
}

final class ActivationMaterializationIntent
    extends InitialImportMaterializationIntent {
  const ActivationMaterializationIntent({
    required super.managedSkillId,
    required super.slotKey,
    required super.revision,
    required this.target,
    required this.targetPath,
    required this.replaceExisting,
    this.expectedExistingFingerprint,
  });

  final ResolvedActivationTarget target;
  final String targetPath;
  final bool replaceExisting;
  final String? expectedExistingFingerprint;
}

final class ExternalOccurrenceRetirementIntent
    extends InitialImportMaterializationIntent {
  const ExternalOccurrenceRetirementIntent({
    required super.managedSkillId,
    required super.slotKey,
    required super.revision,
    required this.target,
    required this.targetPath,
    required this.expectedExistingFingerprint,
  });

  final ResolvedActivationTarget target;
  final String targetPath;
  final String expectedExistingFingerprint;
}

/// Complete application plan consumed by the future Operation-plan assembler.
final class InitialImportPlan {
  InitialImportPlan({
    required this.kind,
    required this.businessChanges,
    required List<RevisionSelectionChangePlan> revisionSelectionChanges,
    required List<InitialRevisionPreparationIntent> revisionIntents,
    required List<PreparedInitialRevision> preparedRevisions,
    required List<RevisionRecoveryIntent> recoveryIntents,
    required List<InitialImportMaterializationIntent> materializationIntents,
    required Set<ManagedSkillId> affectedSkillIds,
    List<SourceAcquisitionWarning> sourceWarnings =
        const <SourceAcquisitionWarning>[],
    List<ActivationWarning> activationWarnings = const <ActivationWarning>[],
  }) : revisionSelectionChanges = List.unmodifiable(revisionSelectionChanges),
       revisionIntents = List.unmodifiable(revisionIntents),
       preparedRevisions = List.unmodifiable(preparedRevisions),
       recoveryIntents = List.unmodifiable(recoveryIntents),
       materializationIntents = List.unmodifiable(materializationIntents),
       affectedSkillIds = Set.unmodifiable(affectedSkillIds),
       sourceWarnings = List.unmodifiable(sourceWarnings),
       activationWarnings = List.unmodifiable(activationWarnings);

  final InitialImportKind kind;
  final WorkspaceBusinessChangeSet businessChanges;
  final List<RevisionSelectionChangePlan> revisionSelectionChanges;
  final List<InitialRevisionPreparationIntent> revisionIntents;
  final List<PreparedInitialRevision> preparedRevisions;
  final List<RevisionRecoveryIntent> recoveryIntents;
  final List<InitialImportMaterializationIntent> materializationIntents;
  final Set<ManagedSkillId> affectedSkillIds;
  final List<SourceAcquisitionWarning> sourceWarnings;
  final List<ActivationWarning> activationWarnings;
}

bool sourceCandidateMatches(
  ExternalSkillCandidate left,
  ExternalSkillCandidate right,
) =>
    left.slotKey == right.slotKey &&
    left.declaredName == right.declaredName &&
    left.description == right.description &&
    left.contentHash == right.contentHash &&
    _sameSet(left.locations, right.locations) &&
    _sameSet(left.agentIds, right.agentIds);

bool _sameSet(List<String> left, List<String> right) =>
    left.length == right.length && left.toSet().containsAll(right);
