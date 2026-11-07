import 'dart:io';

import 'package:path/path.dart' as path;

import '../../application/backup/control_plane_backup_models.dart';
import '../../application/backup/control_plane_backup_service.dart';
import '../../application/ports/workspace_lifecycle_ports.dart';
import '../database/workspace_database.dart';
import '../workspace_layout.dart';

typedef EmptyControlPlaneInitializer = Future<ControlPlaneIdentity> Function();

/// Distinguishes a genuinely new Workspace from missing recovery authority.
///
/// A missing database or eligibility fence in a previously used root remains
/// corruption. Schema v1 is created only when the root contains nothing except
/// the runtime-ownership and operation-writer lock files used by the facade.
final class FreshWorkspaceStartupRecovery
    implements WorkspaceStartupRecoveryPort {
  const FreshWorkspaceStartupRecovery({
    required WorkspaceLayout layout,
    required ControlPlaneBackupService establishedRecovery,
    required EmptyControlPlaneInitializer initializeEmptyControlPlane,
    required Future<void> Function() abandonInitializedControlPlane,
  }) : _layout = layout,
       _establishedRecovery = establishedRecovery,
       _initializeEmptyControlPlane = initializeEmptyControlPlane,
       _abandonInitializedControlPlane = abandonInitializedControlPlane;

  final WorkspaceLayout _layout;
  final ControlPlaneBackupService _establishedRecovery;
  final EmptyControlPlaneInitializer _initializeEmptyControlPlane;
  final Future<void> Function() _abandonInitializedControlPlane;

  @override
  Future<ControlPlaneStartupResult> recoverPrimaryForStartup() async {
    if (!await _isFreshWorkspace()) {
      return _establishedRecovery.recoverPrimaryForStartup();
    }
    try {
      final identity = await _initializeEmptyControlPlane();
      if (identity.schemaVersion != workspaceDatabaseSchemaVersion ||
          identity.repositoryRevision != 0 ||
          identity.destructionEpoch != 0) {
        await _abandonInitializedControlPlane();
        return const ControlPlaneStartupBlocked(
          ControlPlaneBackupFailureCode.eligibilityMismatch,
        );
      }
      await _establishedRecovery.initializeSteadyEligibility(
        initializedIdentity: identity,
      );
      return ControlPlanePrimaryReady(identity);
    } on Object {
      try {
        await _abandonInitializedControlPlane();
      } on Object {
        // Startup still fails closed with no writable facade exposed.
      }
      return const ControlPlaneStartupBlocked(
        ControlPlaneBackupFailureCode.primaryRestoreFailed,
      );
    }
  }

  Future<bool> _isFreshWorkspace() async {
    final primaryType = await FileSystemEntity.type(
      _layout.databasePath,
      followLinks: false,
    );
    final eligibilityType = await FileSystemEntity.type(
      _layout.backupEligibilityPath,
      followLinks: false,
    );
    if (primaryType != FileSystemEntityType.notFound ||
        eligibilityType != FileSystemEntityType.notFound) {
      return false;
    }
    final rootType = await FileSystemEntity.type(
      _layout.rootPath,
      followLinks: false,
    );
    if (rootType == FileSystemEntityType.notFound) return true;
    if (rootType != FileSystemEntityType.directory) return false;
    final allowedLockPaths = <String>{
      path.normalize(path.absolute(_layout.runtimeOwnershipLockPath)),
      path.normalize(path.absolute(_layout.operationWriterLockPath)),
    };
    await for (final entity in Directory(
      _layout.rootPath,
    ).list(followLinks: false)) {
      final entityPath = path.normalize(path.absolute(entity.path));
      if (!allowedLockPaths.any(
        (allowed) => path.equals(entityPath, allowed),
      )) {
        return false;
      }
    }
    return true;
  }
}
