import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;

import '../application/operations/operation_models.dart';
import '../application/ports/workspace_lifecycle_ports.dart';
import '../application/runtime/revision_engine_port.dart';
import '../domain/identifiers.dart';
import '../infrastructure/database/workspace_database.dart';
import '../infrastructure/workspace_layout.dart';
import '../native/revision_engine/revision_recovery_bundle.dart';
import '../platform/filesystem/durable_workspace_filesystem.dart';

/// Complete private selection required to validate one active Revision Store.
///
/// The public startup coordinator observes only [managedSkillId]. Store paths,
/// lineage identity and object IDs remain infrastructure details.
final class DriftWorkspaceSelectedRevision
    implements WorkspaceSelectedRevision {
  const DriftWorkspaceSelectedRevision({
    required this.managedSkillId,
    required this.sourceLineage,
    required this.currentUpstream,
    required this.currentEffective,
  });

  @override
  final ManagedSkillId managedSkillId;
  final SourceLineageReference sourceLineage;
  final RevisionObjectId currentUpstream;
  final RevisionObjectId currentEffective;
}

/// Validates canonical Stores and restores corruption only from the
/// matching, verified Revision Recovery Bundle.
///
/// A Store plus Bundle failure is isolated to the affected Skill. The adapter
/// never elects Repository Copy or Activation bytes as revision authority.
final class DriftWorkspaceRevisionMaintenance
    implements WorkspaceRevisionMaintenancePort {
  const DriftWorkspaceRevisionMaintenance({
    required WorkspaceDatabase database,
    required WorkspaceLayout layout,
    required RevisionEnginePort revisionEngine,
    required DurableWorkspaceFilesystem filesystem,
    RevisionRecoveryBundleCodec bundleCodec =
        const RevisionRecoveryBundleCodec(),
  }) : _database = database,
       _layout = layout,
       _revisionEngine = revisionEngine,
       _filesystem = filesystem,
       _bundleCodec = bundleCodec;

  final WorkspaceDatabase _database;
  final WorkspaceLayout _layout;
  final RevisionEnginePort _revisionEngine;
  final DurableWorkspaceFilesystem _filesystem;
  final RevisionRecoveryBundleCodec _bundleCodec;

  @override
  Future<List<WorkspaceSelectedRevision>> selectedRevisions() async {
    final selections = _database.currentRevisionSelection;
    final lineages = _database.sourceLineages;
    final query = _database
        .select(selections)
        .join(<Join<HasResultSet, dynamic>>[
          innerJoin(
            lineages,
            lineages.id.equalsExp(selections.sourceLineageId) &
                lineages.managedSkillId.equalsExp(selections.managedSkillId),
          ),
        ]);
    final rows = await query.get();
    final values =
        <DriftWorkspaceSelectedRevision>[
          for (final row in rows)
            DriftWorkspaceSelectedRevision(
              managedSkillId: ManagedSkillId(
                row.readTable(selections).managedSkillId,
              ),
              sourceLineage: SourceLineageReference(
                row.readTable(selections).sourceLineageId,
              ),
              currentUpstream: RevisionObjectId(
                row.readTable(selections).upstreamObjectId,
              ),
              currentEffective: RevisionObjectId(
                row.readTable(selections).effectiveObjectId,
              ),
            ),
        ]..sort(
          (left, right) =>
              left.managedSkillId.value.compareTo(right.managedSkillId.value),
        );
    return List<WorkspaceSelectedRevision>.unmodifiable(values);
  }

  @override
  Future<WorkspaceRevisionMaintenanceResult> validateOrRecover(
    WorkspaceSelectedRevision selectedRevision,
  ) async {
    if (selectedRevision is! DriftWorkspaceSelectedRevision) {
      throw ArgumentError.value(
        selectedRevision,
        'selectedRevision',
        'must originate from this maintenance adapter',
      );
    }
    final selection = selectedRevision;
    final storePath = _layout.revisionStorePath(selection.managedSkillId);
    if (await _storeIsHealthy(storePath, selection)) {
      return WorkspaceRevisionMaintenanceResult(
        managedSkillId: selection.managedSkillId,
        disposition: WorkspaceRevisionMaintenanceDisposition.healthy,
      );
    }

    final recovered = await _restoreFromBundle(storePath, selection);
    return WorkspaceRevisionMaintenanceResult(
      managedSkillId: selection.managedSkillId,
      disposition: recovered
          ? WorkspaceRevisionMaintenanceDisposition.recoveredFromBundle
          : WorkspaceRevisionMaintenanceDisposition.isolatedCorrupt,
    );
  }

  Future<bool> _storeIsHealthy(
    String storePath,
    DriftWorkspaceSelectedRevision selection,
  ) async {
    try {
      await _revisionEngine.verifyStore(storePath);
      await _revisionEngine.readTree(storePath, selection.currentUpstream);
      if (selection.currentEffective != selection.currentUpstream) {
        await _revisionEngine.readTree(storePath, selection.currentEffective);
      }
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> _restoreFromBundle(
    String storePath,
    DriftWorkspaceSelectedRevision selection,
  ) async {
    final bundlePath = _layout.revisionBundlePath(selection.managedSkillId);
    TargetVolumeStagingPath? staging;
    String? displacedPath;
    try {
      final manifestBytes = await File(
        path.join(bundlePath, 'manifest.json'),
      ).readAsBytes();
      final completionBytes = await File(
        path.join(bundlePath, 'COMPLETE'),
      ).readAsBytes();
      final packPath = path.join(bundlePath, 'objects.pack');
      final indexPath = path.join(bundlePath, 'objects.idx');
      final packBytes = await File(packPath).readAsBytes();
      final indexBytes = await File(indexPath).readAsBytes();
      final manifest = _bundleCodec.verify(
        manifestBytes: manifestBytes,
        completionFenceBytes: completionBytes,
        packBytes: packBytes,
        indexBytes: indexBytes,
      );
      if (manifest.sourceLineageId != selection.sourceLineage.encoded ||
          manifest.currentUpstream != selection.currentUpstream ||
          manifest.currentEffective != selection.currentEffective ||
          !manifest.retainedPublishedRoots.contains(
            selection.currentUpstream,
          ) ||
          !manifest.retainedPublishedRoots.contains(
            selection.currentEffective,
          )) {
        return false;
      }

      staging = await _filesystem.createSiblingStagingPath(
        storePath,
        kind: DurableEntryKind.directory,
        purpose: 'bundle-restore',
      );
      await _revisionEngine.restoreRecoveryPack(
        stagedRepositoryPath: staging.path,
        packPath: packPath,
        indexPath: indexPath,
        retainedRoots: manifest.retainedPublishedRoots,
      );
      await _revisionEngine.verifyStore(staging.path);
      await _revisionEngine.readTree(staging.path, selection.currentUpstream);
      if (selection.currentEffective != selection.currentUpstream) {
        await _revisionEngine.readTree(
          staging.path,
          selection.currentEffective,
        );
      }
      final publication = await _filesystem.publish(
        candidatePath: staging.path,
        destinationPath: storePath,
        kind: DurableEntryKind.directory,
        makeReadOnly: false,
        requirePlainDirectory: true,
        verify: (publishedPath) async {
          if (!await _storeIsHealthy(publishedPath, selection)) {
            throw StateError('The restored Revision Store is not readable.');
          }
        },
      );
      displacedPath = publication.displacedPath;
      staging = null;
      if (displacedPath != null) {
        try {
          await _filesystem.removeOwnedPath(
            targetPath: displacedPath,
            ownerRoot: _layout.revisionStoresRoot,
          );
        } on Object {
          // The authoritative Store already recovered. Residue cleanup is
          // derived maintenance and must not downgrade that fact.
        }
      }
      return true;
    } on Object {
      return false;
    } finally {
      final pendingStaging = staging;
      if (pendingStaging != null) {
        try {
          await _filesystem.removeOwnedPath(
            targetPath: pendingStaging.path,
            ownerRoot: _layout.revisionStoresRoot,
          );
        } on Object {
          // Startup still isolates this Skill; cleanup can be retried later.
        }
      }
    }
  }
}
