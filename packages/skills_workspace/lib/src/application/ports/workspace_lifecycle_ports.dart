import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../backup/control_plane_backup_models.dart';
import '../runtime/revision_engine_port.dart';
import 'published_artifact_ports.dart';

/// Owns the durable primary/backup decision before the Control Plane opens.
///
/// Callers already hold the Workspace Writer Lock. Implementations must not
/// acquire it again.
abstract interface class WorkspaceStartupRecoveryPort {
  Future<ControlPlaneStartupResult> recoverPrimaryForStartup();
}

/// Owns the Drift Control Plane executor lifecycle without exposing Drift.
abstract interface class WorkspaceControlPlaneLifecyclePort {
  Future<void> open();

  Future<void> close();
}

/// Owns the long-lived Revision worker and its explicit shutdown handshake.
abstract interface class WorkspaceRevisionWorkerLifecyclePort {
  Future<void> start();

  Future<void> close();
}

/// An opaque selected Revision Address returned by the Control Plane adapter.
///
/// Infrastructure implementations may attach private Store and
/// object-address data. The application coordinator only observes identity.
abstract interface class WorkspaceSelectedRevision {
  ManagedSkillId get managedSkillId;
}

enum WorkspaceRevisionMaintenanceDisposition {
  healthy,
  recoveredFromBundle,
  isolatedCorrupt,
}

final class WorkspaceRevisionMaintenanceResult {
  const WorkspaceRevisionMaintenanceResult({
    required this.managedSkillId,
    required this.disposition,
  });

  final ManagedSkillId managedSkillId;
  final WorkspaceRevisionMaintenanceDisposition disposition;
}

/// Validates selected Stores and restores only from matching
/// verified recovery Bundles.
abstract interface class WorkspaceRevisionMaintenancePort {
  Future<List<WorkspaceSelectedRevision>> selectedRevisions();

  Future<WorkspaceRevisionMaintenanceResult> validateOrRecover(
    WorkspaceSelectedRevision selectedRevision,
  );
}

/// Recovers the durable Journal while the caller owns the Writer Lock.
///
/// This deliberately differs from a normal operation entry point: startup
/// must never call an adapter that attempts to acquire the same lock again.
abstract interface class WorkspaceJournalRecoveryPort {
  Future<void> recoverUnderWriterLock({
    ArmedBackupEligibility? armedBarrier,
    required Set<ManagedSkillId> isolatedSkillIds,
  });
}

/// Rebuilds derived Git retention references from SQLite-selected roots.
abstract interface class WorkspaceRevisionReferenceReconciliationPort {
  /// [isolatedSkillIds] have neither a trustworthy Store nor Bundle and must
  /// remain untouched so one corrupt Skill does not block Workspace open.
  Future<void> reconcileRevisionReferences({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  });
}

/// Rebuilds Repository Copies and Activations from selected Effective trees.
abstract interface class WorkspaceMaterializationReconciliationPort {
  Future<SkillMaterializationInspection> inspectSkillMaterializations(
    ManagedSkillId managedSkillId, {
    CancellationToken? cancellationToken,
  });

  Future<WorkspaceMaterializationReconciliationReport>
  reconcileMaterializations({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
    bool repairMismatching = true,
    bool repairMissing = true,
  });
}

final class SkillMaterializationArtifact {
  const SkillMaterializationArtifact({
    required this.locationKind,
    required this.targetPath,
    required this.inspection,
    this.activation,
  });

  final SkillDriftLocationKind locationKind;
  final String targetPath;
  final SkillActivation? activation;
  final PublishedArtifactInspection inspection;
}

final class SkillMaterializationInspection {
  SkillMaterializationInspection({
    required this.effectiveObjectId,
    required this.effectiveContentHash,
    required List<SkillMaterializationArtifact> artifacts,
  }) : artifacts = List.unmodifiable(artifacts);

  final RevisionObjectId effectiveObjectId;
  final String effectiveContentHash;
  final List<SkillMaterializationArtifact> artifacts;
}

final class SkillDriftUnsafe implements Exception {
  const SkillDriftUnsafe();
}

final class WorkspaceMaterializationReconciliationReport {
  const WorkspaceMaterializationReconciliationReport({
    required this.inspectedArtifactCount,
    required this.inspectedFileCount,
    required this.inspectedByteCount,
    required this.repairedArtifactCount,
    required this.inspectionElapsed,
    required this.repairElapsed,
    this.mismatchingArtifactCount = 0,
    this.mismatchingSkillIds = const [],
    this.missingArtifactCount = 0,
    this.missingSkillIds = const [],
  });

  final int inspectedArtifactCount;
  final int inspectedFileCount;
  final int inspectedByteCount;
  final int repairedArtifactCount;
  final Duration inspectionElapsed;
  final Duration repairElapsed;
  final int mismatchingArtifactCount;
  final List<ManagedSkillId> mismatchingSkillIds;
  final int missingArtifactCount;
  final List<ManagedSkillId> missingSkillIds;
}

/// Repairs rebuildable state after authoritative Pointer and Journal recovery.
abstract interface class WorkspaceDerivedStateReconcilerPort {
  Future<void> reconcileRevisionReferences({
    required Set<ManagedSkillId> isolatedSkillIds,
  });

  /// Existing Agent materializations for [isolatedSkillIds] must be left
  /// untouched because neither their Store nor Bundle is authoritative.
  Future<WorkspaceMaterializationReconciliationReport>
  reconcileMaterializations({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
    bool repairMismatching = true,
    bool repairMissing = true,
  });
}

/// Reads one transactionally consistent immutable public Snapshot.
abstract interface class WorkspaceSnapshotReaderPort {
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity});
}

/// Projects one immutable Snapshot with caller-supplied filesystem facts.
///
/// The supplied Draft dirty states must come from authoritative full
/// normalized comparisons. Implementations must not persist them or infer a
/// missing entry as dirty. This private seam lets the application runtime keep
/// filesystem inspection outside the Drift adapter while still projecting all
/// public state from one SQLite transaction.
abstract interface class WorkspaceSnapshotProjectionReaderPort
    implements WorkspaceSnapshotReaderPort {
  Future<RepositorySnapshot> readWithDraftDirtyStates({
    required Map<ManagedSkillId, bool> draftDirtyStates,
    WorkspaceIntegrity? integrity,
  });
}

/// Owns the first immutable Snapshot and the application-facing stream.
abstract interface class WorkspaceSnapshotLifecyclePort {
  Future<RepositorySnapshot> readInitial({
    required WorkspaceIntegrity integrity,
  });

  Future<void> publishInitial(RepositorySnapshot snapshot);

  Future<void> close();
}

/// Serializes admission and commit-aware draining of application requests.
abstract interface class WorkspaceRequestGatePort {
  Future<void> openForRequests();

  Future<void> stopAccepting();

  /// Pre-BCP requests cancel or roll back; post-BCP requests finish
  /// finalization or roll forward before this Future completes.
  Future<void> settleInFlightByCommitState();

  Future<void> close();
}
