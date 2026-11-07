import 'dart:async';

import '../backup/control_plane_backup_models.dart';

typedef ControlPlanePathVerifier = FutureOr<void> Function(String path);

enum ControlPlaneStagingKind { file, directory }

/// Drift-owned database work required by backup and startup recovery.
abstract interface class ControlPlaneBackupDatabasePort {
  Future<ControlPlaneIdentity> liveIdentity();

  /// Executes `VACUUM INTO` on the one Drift-owned writer executor.
  Future<void> vacuumInto(String destinationPath);

  /// Opens and closes an independent Drift-owned probe executor.
  Future<ControlPlaneProbeResult> probeDatabase(
    String databasePath, {
    required ControlPlaneIntegrityLevel integrityLevel,
  });
}

/// Application-owned durability seam for Control Plane artifacts.
///
/// Platform implementations provide same-parent staging, recursive flush,
/// reopen verification, atomic publication and contained cleanup. The
/// application layer never imports the platform filesystem implementation.
abstract interface class ControlPlaneBackupDurabilityPort {
  Future<bool> exists(String targetPath);

  Future<int> fileSize(String filePath);

  Future<List<int>> readFile(String filePath);

  Future<String> sha256File(String filePath);

  Future<List<String>> listChildDirectories(String parentPath);

  Future<String> createSiblingStagingPath(
    String destinationPath, {
    required ControlPlaneStagingKind kind,
  });

  Future<void> writeDurableFile(String filePath, List<int> bytes);

  Future<void> copyDurableFile({
    required String sourcePath,
    required String destinationPath,
  });

  Future<void> publish({
    required String candidatePath,
    required String destinationPath,
    required ControlPlaneStagingKind kind,
    required ControlPlanePathVerifier verify,
  });

  Future<void> removeOwnedPath({
    required String targetPath,
    required String ownerRoot,
  });
}
