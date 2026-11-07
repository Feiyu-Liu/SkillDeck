import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_mutation_models.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_service.dart';
import 'package:skills_workspace/src/application/drift/drift_models.dart';
import 'package:skills_workspace/src/application/drift/drift_plan_assembler.dart';
import 'package:skills_workspace/src/application/drafts/draft_snapshot_coordinator.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/operations/operation_coordinator.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/ports/activation_mutation_ports.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/composition/operation_recovery_backup_maintenance.dart';
import 'package:skills_workspace/src/composition/revision_operation_plans.dart';
import 'package:skills_workspace/src/composition/revision_preparation_service.dart';
import 'package:skills_workspace/src/composition/revision_worker_task_executor.dart';
import 'package:skills_workspace/src/infrastructure/content/direct_revision_content_worker.dart';
import 'package:skills_workspace/src/infrastructure/content/file_system_published_artifact_inspector.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_operation_control_plane.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart'
    hide ManagedSkill;
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker_runtime.dart';
import 'package:skills_workspace/src/platform/filesystem/control_plane_backup_durability.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/filesystem/file_system_published_artifact_metadata_observer.dart';
import 'package:skills_workspace/src/platform/filesystem/workspace_file_lock.dart';
import 'package:skills_workspace/src/platform/operations/filesystem_operation_recovery.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';

const skillDriftOriginalBytes =
    '---\nname: recovery-sample\ndescription: Recovery test.\n---\nOriginal\n';
const skillDriftExternalBytes =
    '---\nname: recovery-sample\ndescription: Recovery test.\n---\nExternal bytes\n';
final skillDriftRecoveryOperationId = OperationId(
  'f7777777-7777-4777-8777-777777777777',
);

SkillsRepository createSkillDriftRecoveryRepository(String root) =>
    createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: path.join(root, 'workspace'),
        agentHomePath: path.join(root, 'agent-home'),
      ),
    );

Future<ManagedSkillId> initializeSkillDriftRecovery(String root) async {
  final source = await Directory(
    path.join(root, 'source'),
  ).create(recursive: true);
  await Directory(path.join(root, 'agent-home')).create(recursive: true);
  await File(
    path.join(source.path, 'SKILL.md'),
  ).writeAsString(skillDriftOriginalBytes);
  final repository = createSkillDriftRecoveryRepository(root);
  try {
    _requireSuccess(await repository.open().completed);
    final installed =
        _requireSuccess(
              await repository
                  .install(
                    InstallRequest(
                      source: LocalSourceDescriptor(locator: source.path),
                      activationSelection: const ActivationSelection.none(),
                    ),
                  )
                  .completed,
            )
            as InstallCompleted;
    return installed.report.affectedSkillIds.single;
  } finally {
    await repository.close().completed;
  }
}

Future<void> ensureSkillDriftRecoveryCleanDraft(
  String root,
  ManagedSkillId id,
) async {
  final repository = createSkillDriftRecoveryRepository(root);
  try {
    _requireSuccess(await repository.open().completed);
    _requireSuccess(
      await repository
          .ensureDraft(EnsureDraftRequest(managedSkillId: id))
          .completed,
    );
  } finally {
    await repository.close().completed;
  }
}

/// Exercises real revision preparation, sealed drift plans, and durable
/// transaction adapters, including cleanup of a clean Draft after publication.
Future<OperationExecutionOutcome> runSkillDriftRestoreRecovery({
  required String root,
  bool failBeforeCommit = false,
  bool crashAfterCommit = false,
}) => _runSkillDriftRecovery(
  root: root,
  failBeforeCommit: failBeforeCommit,
  crashAfterCommit: crashAfterCommit,
  keepExternal: false,
);

Future<OperationExecutionOutcome> runSkillDriftKeepRecovery({
  required String root,
  bool failBeforeCommit = false,
  bool crashAfterCommit = false,
}) => _runSkillDriftRecovery(
  root: root,
  failBeforeCommit: failBeforeCommit,
  crashAfterCommit: crashAfterCommit,
  keepExternal: true,
);

Future<OperationExecutionOutcome> _runSkillDriftRecovery({
  required String root,
  required bool keepExternal,
  required bool failBeforeCommit,
  required bool crashAfterCommit,
}) async {
  final repository = createSkillDriftRecoveryRepository(root);
  late ManagedSkill skill;
  late RepositoryRevision revision;
  try {
    final snapshot = _requireSuccess(await repository.open().completed);
    skill = snapshot.managedSkills.single;
    revision = snapshot.revision;
  } finally {
    await repository.close().completed;
  }
  final layout = WorkspaceLayout(path.join(root, 'workspace'));
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  final filesystem = PlatformDurableWorkspaceFilesystem();
  final revisions = RevisionWorkerRuntime(
    taskExecutor: executeComposedRevisionWorkerTask,
  );
  await revisions.start();
  final preparation = WorkspaceRevisionPreparationService(
    revisions: revisions,
    layout: layout,
    filesystem: filesystem,
    drafts: DraftSnapshotCoordinator(filesystem: revisions, content: revisions),
  );
  const inspector = FileSystemPublishedArtifactInspector(
    contentWorker: DirectRevisionContentWorker(),
    metadataObserver: FileSystemPublishedArtifactMetadataObserver(),
  );
  try {
    final selection = await database.currentRevisionSelection
        .select()
        .getSingle();
    final managedRow = await database.managedSkills.select().getSingle();
    final draftRows = await database.draftWorkspaces.select().get();
    final target = layout.repositoryCopyPath(skill.slotKey);
    final externalFile = File(path.join(target, 'SKILL.md'));
    if (!Platform.isWindows) {
      // Only the test owner bypasses published permissions.
      final permissions = await Process.run('chmod', [
        'u+w',
        externalFile.path,
      ]);
      if (permissions.exitCode != 0) {
        throw StateError('Test permission setup failed.');
      }
    } else {
      final permissions = await Process.run('attrib', [
        '-R',
        externalFile.path,
      ]);
      if (permissions.exitCode != 0) {
        throw StateError('Test permission setup failed.');
      }
    }
    await externalFile.writeAsString(skillDriftExternalBytes, flush: true);
    final artifact = SkillMaterializationArtifact(
      locationKind: SkillDriftLocationKind.repositoryCopy,
      targetPath: target,
      inspection: await inspector.inspectDirectory(
        path: target,
        expectedContentHash: skill.currentRevision.contentHash,
        cancellationToken: CancellationToken.none(),
      ),
    );
    final inspected = SkillMaterializationInspection(
      effectiveObjectId: RevisionObjectId(selection.effectiveObjectId),
      effectiveContentHash: skill.currentRevision.contentHash,
      artifacts: [artifact],
    );
    final review =
        createDriftReview(
              owner: Object(),
              managedSkillId: skill.id,
              inspected: inspected,
              artifacts: const [],
              missingArtifactCount: 0,
            )
            as DriftReviewEvidence;
    final preflight = DriftResolutionPreflight(
      snapshotRevision: revision,
      plannedAtMicros: DateTime.now().microsecondsSinceEpoch,
      skill: skill,
      state: RestoreRevisionState(
        managedSkillId: skill.id,
        sourceLineage: SourceLineageReference(selection.sourceLineageId),
        currentUpstream: RevisionObjectId(selection.upstreamObjectId),
        currentEffective: RevisionObjectId(selection.effectiveObjectId),
        managedSkillCreatedAtMicros: managedRow.createdAtMicros,
        draftCreatedAtMicros: draftRows.isEmpty
            ? null
            : draftRows.single.createdAtMicros,
      ),
      review: review,
      current: inspected,
      resolution: keepExternal
          ? const KeepExternalSkillDrift('repositoryCopy')
          : const RestoreManagedSkillDrift(),
      selectedPath: keepExternal ? target : null,
      selectedFingerprint: keepExternal
          ? artifact.inspection.fingerprint
          : null,
      hadCleanDraft: draftRows.isNotEmpty,
    );
    final registry = OperationRecoverySpecRegistry();
    final plans = WorkspaceRevisionOperationPlans(
      assembler: OperationPlanAssembler(
        subjectIdentities: const _DriftRecoverySubjectIdentity(),
        recoveryPlans: OperationRecoveryPlanFactory(registry: registry),
      ),
      recoverySpecs: registry,
      layout: layout,
      targetExpectations: const _DriftRecoveryTargetExpectations(),
      artifactInspector: inspector,
    );
    final backups = ControlPlaneBackupService(
      database: database,
      durability: PlatformControlPlaneBackupDurability(filesystem),
      paths: ControlPlaneBackupPaths(
        workspaceRoot: layout.rootPath,
        primaryDatabasePath: layout.databasePath,
        backupRoot: layout.controlPlaneBackupsRoot,
        eligibilityPath: layout.backupEligibilityPath,
      ),
    );
    var injected = false;
    // The selected external directory already matches Keep's accepted tree,
    // so recovery may correctly skip replacing it. The Recovery Bundle always
    // changes for that new publication and exercises a real rollback boundary.
    final mutationTarget = await filesystem.resolveMutationPath(
      keepExternal ? layout.revisionBundlePath(skill.id) : target,
    );
    final recovery = FilesystemOperationRecovery(
      layout: layout,
      filesystem: filesystem,
      registry: registry,
      backupMaintenance: WorkspaceOperationRecoveryBackupMaintenance(
        backups: backups,
        database: database,
      ),
      onMutationBarrier: (barrier, destinationPath) {
        if (failBeforeCommit &&
            !injected &&
            barrier == DurablePathMutationBarrier.afterCandidatePublished &&
            path.equals(destinationPath, mutationTarget)) {
          injected = true;
          File(
            path.join(root, 'drift-before-commit-fault.marker'),
          ).writeAsStringSync('reached', flush: true);
          throw const FileSystemException('Injected drift transaction fault.');
        }
      },
    );
    final coordinator = OperationCoordinator(
      writerLock: WorkspaceFileLock(
        lockPath: layout.operationWriterLockPath,
        filesystem: filesystem,
      ),
      controlPlane: DriftOperationControlPlane(database: database),
      recovery: recovery,
      referenceMaintenance: const _DriftRecoveryReferences(),
    );
    final cancellationToken = CancellationToken.none();
    return await coordinator.executeDeferred<PreparedRestorePublishPlan?>(
      operationId: skillDriftRecoveryOperationId,
      expectedRepositoryRevision: revision,
      cancellationToken: cancellationToken,
      buildEnvelope: (id, current) => plans.createDriftEnvelope(
        operationId: id,
        expectedRepositoryRevision: current,
        preflight: preflight,
      ),
      prepareCandidate: (envelope, cancellation) async {
        if (keepExternal) {
          final captured = await preparation.prepareAcceptExternal(
            envelope: envelope,
            preflight: preflight,
            cancellationToken: cancellation,
          );
          if (captured.failureOrNull case final failure?) {
            throw StateError(
              'Fixture publication preparation failed: ${failure.code}',
            );
          }
          final assembled = const DriftPlanAssembler().assemble(
            preflight: preflight,
            prepared: captured.valueOrNull!,
          );
          if (assembled.failureOrNull case final failure?) {
            throw StateError(
              'Fixture publication assembly failed: ${failure.code}',
            );
          }
          return assembled.valueOrNull!;
        }
        final prepared = await preparation.prepareRestoreArtifacts(
          envelope: envelope,
          preflight: preflight,
          cancellationToken: cancellation,
        );
        if (prepared.failureOrNull case final failure?) {
          throw StateError(
            'Fixture restore preparation failed: ${failure.code}',
          );
        }
        return null;
      },
      buildPlan: (envelope, candidate) => plans.sealDriftPlan(
        envelope: envelope,
        preflight: preflight,
        publishedPlan: candidate,
        cancellationToken: cancellationToken,
      ),
      onBusinessCommitted: () {
        if (crashAfterCommit) exit(71);
      },
    );
  } finally {
    try {
      await revisions.close();
    } finally {
      await database.close();
    }
  }
}

T _requireSuccess<T>(SkillsResult<T> result) {
  final value = result.valueOrNull;
  if (value == null) {
    throw StateError('Fixture operation failed: ${result.failureOrNull?.code}');
  }
  return value;
}

final class _DriftRecoverySubjectIdentity
    implements OperationSubjectIdentityPort {
  const _DriftRecoverySubjectIdentity();
  @override
  String allocateOperationSubjectId() => 'f7777777-7777-4777-8777-777777777778';
}

final class _DriftRecoveryTargetExpectations
    implements ActivationTargetExpectationPort {
  const _DriftRecoveryTargetExpectations();
  @override
  Future<bool> matches({
    required ManagedSkill skill,
    required ResolvedActivationTarget target,
    required String targetPath,
    required ActivationTargetExpectation expectation,
  }) async => true;
}

final class _DriftRecoveryReferences
    implements OperationRevisionReferenceMaintenancePort {
  const _DriftRecoveryReferences();
  @override
  Future<void> reconcileRevisionReferences({
    Set<ManagedSkillId>? isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  }) async {}
}
