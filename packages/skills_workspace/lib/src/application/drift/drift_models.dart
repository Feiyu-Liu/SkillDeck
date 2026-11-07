import '../../domain/identifiers.dart';
import '../../domain/cancellation.dart';
import '../../domain/public_models.dart';
import '../history/history_models.dart';
import '../operations/operation_models.dart';
import '../ports/workspace_lifecycle_ports.dart';
import '../ports/published_artifact_ports.dart';
import '../runtime/revision_engine_port.dart';

enum DriftFailureCode {
  operationCancelled,
  skillNotFound,
  revisionStoreCorrupt,
  staleDriftReview,
  driftResolutionUnavailable,
  updateCandidateResolutionRequired,
  dirtyDraftResolutionRequired,
  invalidSkill,
  skillContentLimitExceeded,
  declaredNameChangeNotAllowed,
  historicalNameMismatch,
  ioFailure,
}

sealed class DriftResult<T> {
  const DriftResult();
  T? get valueOrNull;
  DriftFailure<T>? get failureOrNull;
}

final class DriftSuccess<T> extends DriftResult<T> {
  const DriftSuccess({required this.value});
  final T value;
  @override
  T get valueOrNull => value;
  @override
  DriftFailure<T>? get failureOrNull => null;
}

final class DriftFailure<T> extends DriftResult<T> {
  DriftFailure({required this.code, Map<String, Object?> context = const {}})
    : context = Map.unmodifiable(context);
  final DriftFailureCode code;
  final Map<String, Object?> context;
  @override
  T? get valueOrNull => null;
  @override
  DriftFailure<T> get failureOrNull => this;
}

// The private implementation and runtime owner prevent caller-forged reviews.
abstract interface class DriftReviewEvidence implements SkillDriftReview {
  Object get owner;
  SkillMaterializationInspection get inspected;
}

SkillDriftReview createDriftReview({
  required Object owner,
  required ManagedSkillId managedSkillId,
  required SkillMaterializationInspection inspected,
  required List<SkillDriftArtifact> artifacts,
  required int missingArtifactCount,
}) => _SkillDriftReview(
  owner,
  managedSkillId,
  inspected,
  artifacts,
  missingArtifactCount,
);

final class _SkillDriftReview implements DriftReviewEvidence {
  _SkillDriftReview(
    this.owner,
    this.managedSkillId,
    this.inspected,
    List<SkillDriftArtifact> artifacts,
    this.missingArtifactCount,
  ) : artifacts = List.unmodifiable(artifacts);
  @override
  final Object owner;
  @override
  final ManagedSkillId managedSkillId;
  @override
  final SkillMaterializationInspection inspected;
  @override
  String get effectiveContentHash => inspected.effectiveContentHash;
  @override
  final List<SkillDriftArtifact> artifacts;
  @override
  final int missingArtifactCount;
}

final class DriftResolutionPreflight {
  const DriftResolutionPreflight({
    required this.snapshotRevision,
    required this.plannedAtMicros,
    required this.skill,
    required this.state,
    required this.review,
    required this.current,
    required this.resolution,
    required this.selectedPath,
    required this.selectedFingerprint,
    required this.hadCleanDraft,
  });
  final RepositoryRevision snapshotRevision;
  final int plannedAtMicros;
  final ManagedSkill skill;
  final RestoreRevisionState state;
  final DriftReviewEvidence review;
  final SkillMaterializationInspection current;
  final SkillDriftResolution resolution;
  final String? selectedPath;
  final String? selectedFingerprint;
  final bool hadCleanDraft;
  bool get keepsExternal => resolution is KeepExternalSkillDrift;
}

abstract interface class DriftRevisionPreparationPort {
  Future<DriftResult<PreparedRestorePublish>> prepareAcceptExternal({
    required PreparedOperationEnvelope envelope,
    required DriftResolutionPreflight preflight,
    required CancellationToken cancellationToken,
  });
  Future<DriftResult<RevisionObjectId>> prepareRestoreArtifacts({
    required PreparedOperationEnvelope envelope,
    required DriftResolutionPreflight preflight,
    required CancellationToken cancellationToken,
  });
}

abstract interface class DriftOperationPlanPort {
  PreparedOperationEnvelope createDriftEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required DriftResolutionPreflight preflight,
  });
  OperationPlan sealDriftPlan({
    required PreparedOperationEnvelope envelope,
    required DriftResolutionPreflight preflight,
    required PreparedRestorePublishPlan? publishedPlan,
    required CancellationToken cancellationToken,
  });
}

/// Copies a reviewed artifact without acquiring the Workspace Writer Lock.
/// Implementations enforce no-follow capture, bounded content, writable output,
/// forbidden destination roots, and atomic sibling staging publication.
abstract interface class DriftArtifactExporterPort {
  Future<DriftResult<String>> export({
    required String sourcePath,
    required String slotKey,
    required String destinationDirectory,
    required List<String> forbiddenRoots,
    required String expectedFingerprint,
    required PublishedArtifactInspectorPort inspector,
    required CancellationToken cancellationToken,
    required DateTime now,
  });
}
