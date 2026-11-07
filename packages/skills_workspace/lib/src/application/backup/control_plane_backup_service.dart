import 'package:path/path.dart' as path;

import '../ports/control_plane_backup_ports.dart';
import '../ports/workspace_lifecycle_ports.dart';
import 'control_plane_backup_codec.dart';
import 'control_plane_backup_models.dart';

const int retainedControlPlaneBackupCount = 3;

final class ControlPlaneBackupPaths {
  const ControlPlaneBackupPaths({
    required this.workspaceRoot,
    required this.primaryDatabasePath,
    required this.backupRoot,
    required this.eligibilityPath,
  });

  final String workspaceRoot;
  final String primaryDatabasePath;
  final String backupRoot;
  final String eligibilityPath;
}

typedef ControlPlaneClock = int Function();

/// Coordinates verified same-device SQLite backups without owning SQLite or
/// platform filesystem primitives.
///
/// Callers hold the Workspace Writer Lock for every method. The database port
/// keeps `VACUUM INTO` and probes on Drift-owned executors, while the durability
/// port owns flush, same-parent publication, reopen verification and cleanup.
final class ControlPlaneBackupService implements WorkspaceStartupRecoveryPort {
  ControlPlaneBackupService({
    required ControlPlaneBackupDatabasePort database,
    required ControlPlaneBackupDurabilityPort durability,
    required ControlPlaneBackupPaths paths,
    ControlPlaneBackupCodec codec = const ControlPlaneBackupCodec(),
    ControlPlaneClock? clock,
  }) : _database = database,
       _durability = durability,
       _paths = paths,
       _codec = codec,
       _clock = clock ?? _utcMicros;

  final ControlPlaneBackupDatabasePort _database;
  final ControlPlaneBackupDurabilityPort _durability;
  final ControlPlaneBackupPaths _paths;
  final ControlPlaneBackupCodec _codec;
  final ControlPlaneClock _clock;

  Future<SteadyBackupEligibility> initializeSteadyEligibility({
    ControlPlaneIdentity? initializedIdentity,
  }) async {
    if (await _durability.exists(_paths.eligibilityPath)) {
      final existing = await _readEligibility();
      if (existing case final SteadyBackupEligibility steady) return steady;
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.destructiveBarrierArmed,
      );
    }
    final identity = initializedIdentity ?? await _database.liveIdentity();
    final steady = SteadyBackupEligibility(
      destructionEpoch: identity.destructionEpoch,
      establishedAtRepositoryRevision: 0,
    );
    await _replaceEligibility(steady);
    return steady;
  }

  Future<VerifiedControlPlaneBackup> createBackup() async {
    final identity = await _database.liveIdentity();
    final eligibility = await _readEligibility();
    if (eligibility is! SteadyBackupEligibility ||
        eligibility.destructionEpoch != identity.destructionEpoch ||
        identity.repositoryRevision <
            eligibility.establishedAtRepositoryRevision) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.eligibilityMismatch,
      );
    }
    return _createBackup(identity);
  }

  Future<ArmedBackupEligibility> armDestructiveBarrier({
    required String operationId,
    required ControlPlaneIdentity expectedIdentity,
  }) async {
    final live = await _database.liveIdentity();
    if (live != expectedIdentity) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.eligibilityMismatch,
      );
    }
    final eligibility = await _readEligibility();
    if (eligibility is! SteadyBackupEligibility ||
        eligibility.destructionEpoch != live.destructionEpoch ||
        live.repositoryRevision < eligibility.establishedAtRepositoryRevision) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.eligibilityMismatch,
      );
    }
    final armed = ArmedBackupEligibility(
      operationId: operationId,
      previousDestructionEpoch: live.destructionEpoch,
      intendedDestructionEpoch: live.destructionEpoch + 1,
      previousSteadyRepositoryRevision:
          eligibility.establishedAtRepositoryRevision,
      armedAtRepositoryRevision: live.repositoryRevision,
    );
    await _replaceEligibility(armed);
    return armed;
  }

  /// Restores the previous steady fence only after Journal recovery proves the
  /// destructive operation stayed before its Business Commit Point.
  Future<SteadyBackupEligibility> restoreSteadyAfterProvenRollback({
    required String operationId,
  }) async {
    final eligibility = await _readEligibility();
    final live = await _database.liveIdentity();
    if (eligibility case final SteadyBackupEligibility steady) {
      // A crash can stop publication before the armed candidate replaces the
      // previous steady fence. The Journal has already proved this operation
      // remained pre-BCP, so retaining that matching steady state is the
      // idempotent rollback result. This also covers re-entry after rollback
      // published steady but stopped before Journal completion.
      if (live.destructionEpoch != steady.destructionEpoch ||
          live.repositoryRevision < steady.establishedAtRepositoryRevision) {
        throw const ControlPlaneBackupException(
          ControlPlaneBackupFailureCode.eligibilityMismatch,
        );
      }
      return steady;
    }
    final armed = eligibility as ArmedBackupEligibility;
    if (armed.operationId != operationId ||
        live.destructionEpoch != armed.previousDestructionEpoch ||
        live.repositoryRevision != armed.armedAtRepositoryRevision) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.eligibilityMismatch,
      );
    }
    final steady = SteadyBackupEligibility(
      destructionEpoch: armed.previousDestructionEpoch,
      establishedAtRepositoryRevision: armed.previousSteadyRepositoryRevision,
    );
    await _replaceEligibility(steady);
    return steady;
  }

  /// Publishes the first backup without retired data, advances the fence, then
  /// removes all old-epoch backups. It is idempotent when finalization resumes.
  Future<VerifiedControlPlaneBackup> completeCommittedDestruction({
    required String operationId,
  }) async {
    final live = await _database.liveIdentity();
    final eligibility = await _readEligibility();
    if (eligibility case final ArmedBackupEligibility armed) {
      if (armed.operationId != operationId ||
          live.destructionEpoch != armed.intendedDestructionEpoch ||
          live.repositoryRevision <= armed.armedAtRepositoryRevision) {
        throw const ControlPlaneBackupException(
          ControlPlaneBackupFailureCode.eligibilityMismatch,
        );
      }
      final backup = await _createBackup(live);
      final steady = SteadyBackupEligibility(
        destructionEpoch: live.destructionEpoch,
        establishedAtRepositoryRevision:
            backup.manifest.identity.repositoryRevision,
      );
      await _replaceEligibility(steady);
      await _deleteOtherEpochs(live.destructionEpoch);
      return backup;
    }

    // The steady fence is published before old-epoch cleanup. Journal recovery
    // can therefore re-enter finalization after that publication boundary. The
    // caller has already proved the named operation committed; this branch only
    // resumes cleanup from the durable steady state.
    final steady = eligibility as SteadyBackupEligibility;
    if (steady.destructionEpoch != live.destructionEpoch ||
        live.repositoryRevision < steady.establishedAtRepositoryRevision) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.eligibilityMismatch,
      );
    }
    final backups = await verifiedBackupsForEpoch(live.destructionEpoch);
    final eligible = backups
        .where(
          (backup) =>
              backup.manifest.identity.repositoryRevision >=
              steady.establishedAtRepositoryRevision,
        )
        .toList(growable: false);
    if (eligible.isEmpty) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.noEligibleBackup,
      );
    }
    await _deleteOtherEpochs(live.destructionEpoch);
    return eligible.first;
  }

  @override
  Future<ControlPlaneStartupResult> recoverPrimaryForStartup() async {
    final BackupEligibility eligibility;
    try {
      eligibility = await _readEligibility();
    } on Object {
      return const ControlPlaneStartupBlocked(
        ControlPlaneBackupFailureCode.invalidEligibilityFence,
      );
    }

    final primary = await _database.probeDatabase(
      _paths.primaryDatabasePath,
      integrityLevel: ControlPlaneIntegrityLevel.quick,
    );
    if (eligibility case final ArmedBackupEligibility armed) {
      return switch (primary) {
        ControlPlaneHealthy(:final identity) =>
          ControlPlaneArmedBarrierNeedsResolution(
            identity: identity,
            eligibility: armed,
          ),
        ControlPlaneUnusable() => const ControlPlaneStartupBlocked(
          ControlPlaneBackupFailureCode.destructiveBarrierArmed,
        ),
      };
    }

    final steady = eligibility as SteadyBackupEligibility;
    if (primary case ControlPlaneHealthy(:final identity)) {
      if (identity.destructionEpoch != steady.destructionEpoch ||
          identity.repositoryRevision <
              steady.establishedAtRepositoryRevision) {
        return const ControlPlaneStartupBlocked(
          ControlPlaneBackupFailureCode.eligibilityMismatch,
        );
      }
      return ControlPlanePrimaryReady(identity);
    }

    final backups = await verifiedBackupsForEpoch(steady.destructionEpoch);
    final eligible = backups
        .where(
          (backup) =>
              backup.manifest.identity.repositoryRevision >=
              steady.establishedAtRepositoryRevision,
        )
        .toList(growable: false);
    if (eligible.isEmpty) {
      return const ControlPlaneStartupBlocked(
        ControlPlaneBackupFailureCode.noEligibleBackup,
      );
    }
    eligible.sort(_newestBackupFirst);
    final selected = eligible.first;
    try {
      await _restorePrimary(selected);
    } on Object {
      return const ControlPlaneStartupBlocked(
        ControlPlaneBackupFailureCode.primaryRestoreFailed,
      );
    }
    return ControlPlanePrimaryRestored(
      identity: selected.manifest.identity,
      backup: selected,
    );
  }

  Future<List<VerifiedControlPlaneBackup>> verifiedBackupsForEpoch(
    int destructionEpoch,
  ) async {
    final epochDirectory = _epochDirectory(destructionEpoch);
    final directories = await _durability.listChildDirectories(epochDirectory);
    final verified = <VerifiedControlPlaneBackup>[];
    for (final directory in directories) {
      try {
        verified.add(await _verifyBackup(directory));
      } on Object {
        // Corrupt or incomplete candidates are never eligible. Cleanup is
        // performed only by a successful backup finalization under the lock.
      }
    }
    verified.sort(_newestBackupFirst);
    return List<VerifiedControlPlaneBackup>.unmodifiable(verified);
  }

  Future<VerifiedControlPlaneBackup> _createBackup(
    ControlPlaneIdentity identity,
  ) async {
    final backupId = '${identity.repositoryRevision}';
    final destination = path.join(
      _epochDirectory(identity.destructionEpoch),
      backupId,
    );
    final staging = await _durability.createSiblingStagingPath(
      destination,
      kind: ControlPlaneStagingKind.directory,
    );
    try {
      final databasePath = path.join(staging, 'workspace.sqlite');
      if (await _durability.exists(databasePath)) {
        throw const ControlPlaneBackupException(
          ControlPlaneBackupFailureCode.backupCreationFailed,
        );
      }
      await _database.vacuumInto(databasePath);
      final probe = await _database.probeDatabase(
        databasePath,
        integrityLevel: ControlPlaneIntegrityLevel.full,
      );
      if (probe is! ControlPlaneHealthy || probe.identity != identity) {
        throw const ControlPlaneBackupException(
          ControlPlaneBackupFailureCode.backupVerificationFailed,
        );
      }
      final manifest = ControlPlaneBackupManifest(
        backupId: backupId,
        identity: identity,
        createdAtMicros: _clock(),
        databaseByteSize: await _durability.fileSize(databasePath),
        databaseSha256: await _durability.sha256File(databasePath),
      );
      final manifestBytes = _codec.encodeManifest(manifest);
      await _durability.writeDurableFile(
        path.join(staging, 'manifest.json'),
        manifestBytes,
      );
      await _durability.writeDurableFile(
        path.join(staging, 'COMPLETE'),
        _codec.createCompletionFence(manifestBytes),
      );
      await _verifyBackup(
        staging,
        expectedIdentity: identity,
        verifyDirectoryName: false,
      );
      await _durability.publish(
        candidatePath: staging,
        destinationPath: destination,
        kind: ControlPlaneStagingKind.directory,
        verify: (publishedPath) => _verifyBackup(
          publishedPath,
          expectedIdentity: identity,
          verifyDirectoryName: path.equals(publishedPath, destination),
        ),
      );
      final published = await _verifyBackup(
        destination,
        expectedIdentity: identity,
      );
      await _pruneEpoch(identity.destructionEpoch);
      return published;
    } on Object {
      await _removeIfOwned(staging);
      rethrow;
    }
  }

  Future<VerifiedControlPlaneBackup> _verifyBackup(
    String directoryPath, {
    ControlPlaneIdentity? expectedIdentity,
    bool verifyDirectoryName = true,
  }) async {
    final databasePath = path.join(directoryPath, 'workspace.sqlite');
    final manifestPath = path.join(directoryPath, 'manifest.json');
    final completePath = path.join(directoryPath, 'COMPLETE');
    if (!await _durability.exists(databasePath) ||
        !await _durability.exists(manifestPath) ||
        !await _durability.exists(completePath)) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.backupVerificationFailed,
      );
    }
    final manifestBytes = await _durability.readFile(manifestPath);
    final manifest = _codec.decodeManifest(manifestBytes);
    _codec.verifyCompletionFence(
      manifestBytes: manifestBytes,
      completionFenceBytes: await _durability.readFile(completePath),
    );
    if ((verifyDirectoryName &&
            path.basename(directoryPath) != manifest.backupId) ||
        (expectedIdentity != null && manifest.identity != expectedIdentity) ||
        await _durability.fileSize(databasePath) != manifest.databaseByteSize ||
        await _durability.sha256File(databasePath) != manifest.databaseSha256) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.backupVerificationFailed,
      );
    }
    final probe = await _database.probeDatabase(
      databasePath,
      integrityLevel: ControlPlaneIntegrityLevel.full,
    );
    if (probe is! ControlPlaneHealthy || probe.identity != manifest.identity) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.backupVerificationFailed,
      );
    }
    return VerifiedControlPlaneBackup(
      directoryPath: directoryPath,
      databasePath: databasePath,
      manifest: manifest,
    );
  }

  Future<void> _restorePrimary(VerifiedControlPlaneBackup backup) async {
    final staging = await _durability.createSiblingStagingPath(
      _paths.primaryDatabasePath,
      kind: ControlPlaneStagingKind.file,
    );
    try {
      await _durability.copyDurableFile(
        sourcePath: backup.databasePath,
        destinationPath: staging,
      );
      final stagedProbe = await _database.probeDatabase(
        staging,
        integrityLevel: ControlPlaneIntegrityLevel.full,
      );
      if (stagedProbe is! ControlPlaneHealthy ||
          stagedProbe.identity != backup.manifest.identity ||
          await _durability.sha256File(staging) !=
              backup.manifest.databaseSha256) {
        throw const ControlPlaneBackupException(
          ControlPlaneBackupFailureCode.primaryRestoreFailed,
        );
      }
      await _removeIfOwned('${_paths.primaryDatabasePath}-wal');
      await _removeIfOwned('${_paths.primaryDatabasePath}-shm');
      await _durability.publish(
        candidatePath: staging,
        destinationPath: _paths.primaryDatabasePath,
        kind: ControlPlaneStagingKind.file,
        verify: (publishedPath) async {
          if (await _durability.sha256File(publishedPath) !=
              backup.manifest.databaseSha256) {
            throw const ControlPlaneBackupException(
              ControlPlaneBackupFailureCode.primaryRestoreFailed,
            );
          }
          final probe = await _database.probeDatabase(
            publishedPath,
            integrityLevel: ControlPlaneIntegrityLevel.full,
          );
          if (probe is! ControlPlaneHealthy ||
              probe.identity != backup.manifest.identity) {
            throw const ControlPlaneBackupException(
              ControlPlaneBackupFailureCode.primaryRestoreFailed,
            );
          }
        },
      );
    } on Object {
      await _removeIfOwned(staging);
      rethrow;
    }
  }

  Future<BackupEligibility> _readEligibility() async {
    if (!await _durability.exists(_paths.eligibilityPath)) {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.invalidEligibilityFence,
      );
    }
    try {
      return _codec.decodeEligibility(
        await _durability.readFile(_paths.eligibilityPath),
      );
    } on Object {
      throw const ControlPlaneBackupException(
        ControlPlaneBackupFailureCode.invalidEligibilityFence,
      );
    }
  }

  Future<void> _replaceEligibility(BackupEligibility eligibility) async {
    final bytes = _codec.encodeEligibility(eligibility);
    final staging = await _durability.createSiblingStagingPath(
      _paths.eligibilityPath,
      kind: ControlPlaneStagingKind.file,
    );
    try {
      await _durability.writeDurableFile(staging, bytes);
      await _durability.publish(
        candidatePath: staging,
        destinationPath: _paths.eligibilityPath,
        kind: ControlPlaneStagingKind.file,
        verify: (publishedPath) async {
          final decoded = _codec.decodeEligibility(
            await _durability.readFile(publishedPath),
          );
          if (!_sameEligibility(decoded, eligibility)) {
            throw const ControlPlaneBackupException(
              ControlPlaneBackupFailureCode.invalidEligibilityFence,
            );
          }
        },
      );
    } on Object {
      await _removeIfOwned(staging);
      rethrow;
    }
  }

  Future<void> _pruneEpoch(int destructionEpoch) async {
    final epochDirectory = _epochDirectory(destructionEpoch);
    final allDirectories = await _durability.listChildDirectories(
      epochDirectory,
    );
    final verified = await verifiedBackupsForEpoch(destructionEpoch);
    final keep = verified
        .take(retainedControlPlaneBackupCount)
        .map((backup) => path.normalize(backup.directoryPath))
        .toSet();
    for (final directory in allDirectories) {
      if (!keep.contains(path.normalize(directory))) {
        await _durability.removeOwnedPath(
          targetPath: directory,
          ownerRoot: _paths.backupRoot,
        );
      }
    }
  }

  Future<void> _deleteOtherEpochs(int activeEpoch) async {
    final active = path.normalize(_epochDirectory(activeEpoch));
    for (final directory in await _durability.listChildDirectories(
      _paths.backupRoot,
    )) {
      if (path.normalize(directory) != active) {
        await _durability.removeOwnedPath(
          targetPath: directory,
          ownerRoot: _paths.backupRoot,
        );
      }
    }
  }

  Future<void> _removeIfOwned(String targetPath) async {
    try {
      await _durability.removeOwnedPath(
        targetPath: targetPath,
        ownerRoot: _paths.workspaceRoot,
      );
    } on Object {
      // Cleanup is repeatable and callers preserve the primary failure.
    }
  }

  String _epochDirectory(int destructionEpoch) =>
      path.join(_paths.backupRoot, '$destructionEpoch');
}

int _newestBackupFirst(
  VerifiedControlPlaneBackup left,
  VerifiedControlPlaneBackup right,
) {
  final revision = right.manifest.identity.repositoryRevision.compareTo(
    left.manifest.identity.repositoryRevision,
  );
  if (revision != 0) return revision;
  final created = right.manifest.createdAtMicros.compareTo(
    left.manifest.createdAtMicros,
  );
  if (created != 0) return created;
  return right.manifest.backupId.compareTo(left.manifest.backupId);
}

bool _sameEligibility(BackupEligibility left, BackupEligibility right) {
  if (left is SteadyBackupEligibility && right is SteadyBackupEligibility) {
    return left.destructionEpoch == right.destructionEpoch &&
        left.establishedAtRepositoryRevision ==
            right.establishedAtRepositoryRevision;
  }
  if (left is ArmedBackupEligibility && right is ArmedBackupEligibility) {
    return left.operationId == right.operationId &&
        left.previousDestructionEpoch == right.previousDestructionEpoch &&
        left.intendedDestructionEpoch == right.intendedDestructionEpoch &&
        left.previousSteadyRepositoryRevision ==
            right.previousSteadyRepositoryRevision &&
        left.armedAtRepositoryRevision == right.armedAtRepositoryRevision;
  }
  return false;
}

int _utcMicros() => DateTime.now().toUtc().microsecondsSinceEpoch;
