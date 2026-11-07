/// Relational identity recorded in every verified Control Plane backup.
final class ControlPlaneIdentity {
  const ControlPlaneIdentity({
    required this.schemaVersion,
    required this.repositoryRevision,
    required this.destructionEpoch,
  });

  final int schemaVersion;
  final int repositoryRevision;
  final int destructionEpoch;

  @override
  bool operator ==(Object other) =>
      other is ControlPlaneIdentity &&
      other.schemaVersion == schemaVersion &&
      other.repositoryRevision == repositoryRevision &&
      other.destructionEpoch == destructionEpoch;

  @override
  int get hashCode =>
      Object.hash(schemaVersion, repositoryRevision, destructionEpoch);
}

enum ControlPlaneIntegrityLevel { quick, full }

sealed class ControlPlaneProbeResult {
  const ControlPlaneProbeResult();
}

final class ControlPlaneHealthy extends ControlPlaneProbeResult {
  const ControlPlaneHealthy(this.identity);

  final ControlPlaneIdentity identity;
}

final class ControlPlaneUnusable extends ControlPlaneProbeResult {
  const ControlPlaneUnusable(this.reason);

  final ControlPlaneProbeFailureReason reason;
}

enum ControlPlaneProbeFailureReason {
  missing,
  cannotOpen,
  schemaMismatch,
  integrityCheckFailed,
  foreignKeyCheckFailed,
  metadataUnavailable,
}

final class ControlPlaneBackupManifest {
  const ControlPlaneBackupManifest({
    required this.backupId,
    required this.identity,
    required this.createdAtMicros,
    required this.databaseByteSize,
    required this.databaseSha256,
  });

  final String backupId;
  final ControlPlaneIdentity identity;
  final int createdAtMicros;
  final int databaseByteSize;
  final String databaseSha256;
}

final class VerifiedControlPlaneBackup {
  const VerifiedControlPlaneBackup({
    required this.directoryPath,
    required this.databasePath,
    required this.manifest,
  });

  final String directoryPath;
  final String databasePath;
  final ControlPlaneBackupManifest manifest;
}

sealed class BackupEligibility {
  const BackupEligibility();
}

final class SteadyBackupEligibility extends BackupEligibility {
  const SteadyBackupEligibility({
    required this.destructionEpoch,
    required this.establishedAtRepositoryRevision,
  });

  final int destructionEpoch;
  final int establishedAtRepositoryRevision;
}

final class ArmedBackupEligibility extends BackupEligibility {
  const ArmedBackupEligibility({
    required this.operationId,
    required this.previousDestructionEpoch,
    required this.intendedDestructionEpoch,
    required this.previousSteadyRepositoryRevision,
    required this.armedAtRepositoryRevision,
  });

  final String operationId;
  final int previousDestructionEpoch;
  final int intendedDestructionEpoch;
  final int previousSteadyRepositoryRevision;
  final int armedAtRepositoryRevision;
}

enum ControlPlaneBackupFailureCode {
  invalidEligibilityFence,
  eligibilityMismatch,
  destructiveBarrierArmed,
  backupCreationFailed,
  backupVerificationFailed,
  noEligibleBackup,
  primaryRestoreFailed,
}

final class ControlPlaneBackupException implements Exception {
  const ControlPlaneBackupException(this.code);

  final ControlPlaneBackupFailureCode code;

  @override
  String toString() => 'ControlPlaneBackupException(${code.name})';
}

sealed class ControlPlaneStartupResult {
  const ControlPlaneStartupResult();
}

final class ControlPlanePrimaryReady extends ControlPlaneStartupResult {
  const ControlPlanePrimaryReady(this.identity);

  final ControlPlaneIdentity identity;
}

final class ControlPlanePrimaryRestored extends ControlPlaneStartupResult {
  const ControlPlanePrimaryRestored({
    required this.identity,
    required this.backup,
  });

  final ControlPlaneIdentity identity;
  final VerifiedControlPlaneBackup backup;
}

/// The primary is readable, but Journal recovery must prove whether the
/// destructive Business Commit Point occurred before writable open continues.
final class ControlPlaneArmedBarrierNeedsResolution
    extends ControlPlaneStartupResult {
  const ControlPlaneArmedBarrierNeedsResolution({
    required this.identity,
    required this.eligibility,
  });

  final ControlPlaneIdentity identity;
  final ArmedBackupEligibility eligibility;
}

final class ControlPlaneStartupBlocked extends ControlPlaneStartupResult {
  const ControlPlaneStartupBlocked(this.code);

  final ControlPlaneBackupFailureCode code;
}
