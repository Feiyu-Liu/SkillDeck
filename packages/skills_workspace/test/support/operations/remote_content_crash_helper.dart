import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/application/drafts/draft_snapshot_coordinator.dart';
import 'package:skills_workspace/src/application/operations/operation_coordinator.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/operation_revision_reference_maintenance.dart';
import 'package:skills_workspace/src/composition/remote_content_command.dart';
import 'package:skills_workspace/src/composition/revision_operation_plans.dart';
import 'package:skills_workspace/src/composition/revision_preparation_service.dart';
import 'package:skills_workspace/src/composition/revision_worker_task_executor.dart';
import 'package:skills_workspace/src/infrastructure/activation/activation_target_expectation.dart';
import 'package:skills_workspace/src/infrastructure/activation/file_system_activation_occupancy_probe.dart';
import 'package:skills_workspace/src/infrastructure/activation/file_system_update_slot_migration_inspector.dart';
import 'package:skills_workspace/src/infrastructure/content/direct_revision_content_worker.dart';
import 'package:skills_workspace/src/infrastructure/content/file_system_published_artifact_inspector.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_committed_revision_roots.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_draft_update_state.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_operation_control_plane.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_revision_pointer_reader.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_revision_reference_reconciliation.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_update_draft_inspection.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_snapshot_reader.dart';
import 'package:skills_workspace/src/infrastructure/identity/uuid_workspace_identities.dart';
import 'package:skills_workspace/src/infrastructure/revision_store_update_candidate_content.dart';
import 'package:skills_workspace/src/infrastructure/source/application_source_payload_adapter.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker_runtime.dart';
import 'package:skills_workspace/src/platform/activation/workspace_activation_location_identity.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/filesystem/file_system_published_artifact_metadata_observer.dart';
import 'package:skills_workspace/src/platform/filesystem/posix_filesystem_primitives.dart';
import 'package:skills_workspace/src/platform/filesystem/windows_filesystem_primitives.dart';
import 'package:skills_workspace/src/platform/filesystem/workspace_file_lock.dart';
import 'package:skills_workspace/src/platform/filesystem/workspace_path_identity.dart';
import 'package:skills_workspace/src/platform/operations/filesystem_operation_recovery.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';

Future<void> main(List<String> arguments) async {
  final (workspace, operation, crashPoint, request) = switch (arguments) {
    [
      final workspace,
      'install',
      final pack,
      final effective,
      final upstream,
      final operation,
      final crashPoint,
    ] =>
      (
        workspace,
        operation,
        crashPoint,
        RemoteSkillInstall(
          packPath: pack,
          effective: RevisionId(effective),
          upstream: RevisionId(upstream),
          source: SyncedOriginSourceDescriptor(
            originSourceType: SyncedOriginSourceType.local,
            originDeviceLabel: 'Donor Device',
            displayLabel: 'Donor folder',
          ),
        ),
      ),
    [
      final workspace,
      final skill,
      final expected,
      final target,
      final operation,
      final crashPoint,
    ] =>
      (
        workspace,
        operation,
        crashPoint,
        RemoteSkillContent(
          managedSkillId: ManagedSkillId(skill),
          expectedEffective: RevisionId(expected),
          effective: RevisionId(target),
          upstream: RevisionId(target),
        ),
      ),
    _ => throw ArgumentError('Unexpected remote apply crash helper arguments.'),
  };
  final layout = WorkspaceLayout(workspace);
  final operationId = OperationId(operation);
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  final primitives = Platform.isWindows
      ? const WindowsFilesystemPrimitives()
      : const PosixFilesystemPrimitives();
  final filesystem = PlatformDurableWorkspaceFilesystem.withPrimitives(
    primitives: primitives,
  );
  final runtime = RevisionWorkerRuntime(
    taskExecutor: executeComposedRevisionWorkerTask,
  );
  final snapshots = WorkspaceSnapshotPublisher(
    reader: WorkspaceSnapshotReader(database: database, layout: layout),
  );
  final owner = await WorkspaceFileLock(
    lockPath: layout.runtimeOwnershipLockPath,
    filesystem: filesystem,
  ).acquire();
  await runtime.start();
  try {
    await snapshots.publishInitial(
      await snapshots.readInitial(integrity: WorkspaceIntegrity()),
    );
    final access = ManagedSkillRevisionAccessGate();
    final drafts = DraftSnapshotCoordinator(
      filesystem: runtime,
      content: runtime,
    );
    final pointers = DriftRevisionPointerReader(database);
    final states = DriftDraftUpdateState(
      database: database,
      draftInspection: DriftUpdateDraftInspection(
        database: database,
        layout: layout,
        accessGate: access,
        storePath: layout.revisionStorePath,
        revisions: runtime,
        snapshots: drafts,
      ),
      candidateContent: RevisionStoreUpdateCandidateContent(
        accessGate: access,
        storePath: layout.revisionStorePath,
        pointers: pointers,
        revisionEngine: runtime,
      ),
    );
    final registry = OperationRecoverySpecRegistry();
    final publishedParent = await filesystem.resolveMutationPath(
      switch (request) {
        RemoteSkillContent(:final managedSkillId) => path.join(
          layout.revisionStorePath(managedSkillId),
          'objects',
        ),
        RemoteSkillInstall() => layout.revisionStoresRoot,
        _ => throw UnsupportedError('Expected a revision pack request'),
      },
    );
    final recovery = FilesystemOperationRecovery(
      layout: layout,
      filesystem: filesystem,
      registry: registry,
      draftSnapshots: runtime,
      manifestWorker: runtime,
      onMutationBarrier: (barrier, targetPath) {
        if (crashPoint == 'beforeCommit' &&
            barrier == DurablePathMutationBarrier.afterCandidatePublished &&
            path.isWithin(publishedParent, targetPath)) {
          exit(71);
        }
      },
    );
    final operations = OperationCoordinator(
      writerLock: WorkspaceFileLock(
        lockPath: layout.operationWriterLockPath,
        filesystem: filesystem,
      ),
      controlPlane: DriftOperationControlPlane(database: database),
      recovery: recovery,
      referenceMaintenance: WorkspaceOperationRevisionReferenceMaintenance(
        reconciliation: DriftWorkspaceRevisionReferenceReconciliation(
          database: database,
          layout: layout,
          revisionEngine: runtime,
        ),
        snapshots: snapshots,
      ),
    );
    final plans = WorkspaceRevisionOperationPlans(
      assembler: OperationPlanAssembler(
        subjectIdentities: const UuidWorkspaceIdentities(),
        recoveryPlans: OperationRecoveryPlanFactory(registry: registry),
      ),
      recoverySpecs: registry,
      layout: layout,
      targetExpectations: ActivationTargetExpectationProbe(
        occupancyProbe: FileSystemActivationOccupancyProbe(
          repositoryCopyPathForSkill: (skill) =>
              layout.repositoryCopyPath(skill.slotKey),
          locationIdentity: WorkspaceActivationLocationIdentity(
            WorkspacePathIdentityResolver(primitives: primitives),
          ),
        ),
      ),
      artifactInspector: const FileSystemPublishedArtifactInspector(
        contentWorker: DirectRevisionContentWorker(),
        metadataObserver: FileSystemPublishedArtifactMetadataObserver(),
      ),
    );
    final command = buildRemoteContentCommand(
      handleLibrary: (_, _) => throw UnsupportedError('Content crash fixture'),
      handleRemoval: (_, _) => throw UnsupportedError('Content crash fixture'),
      snapshots: snapshots,
      operations: operations,
      states: states,
      slotMigrations: FileSystemUpdateSlotMigrationInspector(
        repositoryCopyPathForSlot: layout.repositoryCopyPath,
      ),
      preparation: WorkspaceRevisionPreparationService(
        readCommittedRoots: DriftCommittedRevisionRoots(database).readForBundle,
        revisions: runtime,
        layout: layout,
        filesystem: filesystem,
        drafts: drafts,
      ),
      plans: plans,
      runtime: runtime,
      access: access,
      identities: const UuidWorkspaceIdentities(),
      sourcePayloads: const ApplicationSourcePayloadAdapter(),
      readPackHeads: pointers.readCurrentPackHeads,
    );
    final result = await command.execute(
      request,
      SkillsCommandContext(
        operationId: operationId,
        cancellationToken: CancellationToken.none(),
        lockWaitPolicy: null,
        markBusinessCommitted: () {
          if (crashPoint == 'afterCommit') exit(72);
        },
        reportProgress: (_, {currentItem, completed = 0, total}) {},
      ),
    );
    throw StateError('Remote apply did not reach the crash point: $result');
  } finally {
    await snapshots.close();
    await runtime.close();
    await database.close();
    await owner.release();
  }
}
