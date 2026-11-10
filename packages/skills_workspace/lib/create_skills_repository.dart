import 'dart:io';

import 'package:path/path.dart' as path;

import 'src/api/configuration.dart';
import 'src/api/default_skills_repository.dart';
import 'src/api/skills_repository.dart';
import 'src/application/activation/activation_mutation_planner.dart';
import 'src/application/activation/activation_occupancy_inspector.dart';
import 'src/application/activation/activation_target_resolver.dart';
import 'src/application/agents/agent_catalog_controller.dart';
import 'src/application/agents/agent_root_ownership_auditor.dart';
import 'src/application/agents/built_in_agent_definitions.dart';
import 'src/application/backup/control_plane_backup_service.dart';
import 'src/application/destructive/destructive_operation_planner.dart';
import 'src/application/discovery/external_skill_scanner.dart';
import 'src/application/drafts/draft_plan_assembler.dart';
import 'src/application/drafts/draft_planner.dart';
import 'src/application/drafts/draft_snapshot_coordinator.dart';
import 'src/application/drift/drift_resolution_planner.dart';
import 'src/application/history/history_service.dart';
import 'src/application/history/restore_plan_assembler.dart';
import 'src/application/install/initial_import_planner.dart';
import 'src/application/library/library_mutation_planner.dart';
import 'src/application/operations/finalization_recovery_service.dart';
import 'src/application/operations/operation_coordinator.dart';
import 'src/application/operations/operation_plan_assembler.dart';
import 'src/application/project_roots/project_root_planner.dart';
import 'src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'src/application/revision_store/revision_store_access_service.dart';
import 'src/application/runtime/draft_aware_workspace_snapshot_reader.dart';
import 'src/application/runtime/workspace_derived_state_reconciler.dart';
import 'src/application/runtime/workspace_journal_recovery_adapter.dart';
import 'src/application/runtime/workspace_open_coordinator.dart';
import 'src/application/runtime/workspace_request_gate.dart';
import 'src/application/runtime/workspace_snapshot_publisher.dart';
import 'src/application/source/source_acquisition_coordinator.dart';
import 'src/application/update/update_planner.dart';
import 'src/composition/destructive_recovery_entries.dart';
import 'src/composition/destructive_recovery_maintenance.dart';
import 'src/composition/materialization_inspection_worker_pool.dart';
import 'src/composition/operation_recovery_backup_maintenance.dart';
import 'src/composition/operation_revision_reference_maintenance.dart';
import 'src/composition/repository_command_composition.dart';
import 'src/composition/revision_operation_plans.dart';
import 'src/composition/revision_preparation_service.dart';
import 'src/composition/revision_worker_task_executor.dart';
import 'src/composition/skills_repository_runtime_adapter.dart';
import 'src/composition/source_replacement_preparation.dart';
import 'src/composition/workspace_materialization_reconciler.dart';
import 'src/composition/workspace_revision_maintenance.dart';
import 'src/domain/lock_wait_policy.dart';
import 'src/domain/public_models.dart';
import 'src/infrastructure/activation/activation_target_expectation.dart';
import 'src/infrastructure/activation/file_system_activation_occupancy_probe.dart';
import 'src/infrastructure/activation/file_system_update_slot_migration_inspector.dart';
import 'src/infrastructure/activation/workspace_activation_materialization_paths.dart';
import 'src/infrastructure/agents/file_system_agent_detection.dart';
import 'src/infrastructure/agents/platform_agent_root_ownership_inspection.dart';
import 'src/infrastructure/content/file_system_published_artifact_inspector.dart';
import 'src/infrastructure/database/drift_activation_metadata_reader.dart';
import 'src/infrastructure/database/drift_destructive_planning_state.dart';
import 'src/infrastructure/database/drift_draft_update_state.dart';
import 'src/infrastructure/database/drift_operation_control_plane.dart';
import 'src/infrastructure/database/drift_revision_pointer_reader.dart';
import 'src/infrastructure/database/drift_revision_reference_reconciliation.dart';
import 'src/infrastructure/database/drift_update_check_store.dart';
import 'src/infrastructure/database/drift_update_draft_inspection.dart';
import 'src/infrastructure/database/drift_workspace_history_content.dart';
import 'src/infrastructure/database/workspace_database.dart';
import 'src/infrastructure/database/workspace_history_reader.dart';
import 'src/infrastructure/database/workspace_snapshot_reader.dart';
import 'src/infrastructure/discovery/file_system_external_skill_location.dart';
import 'src/infrastructure/git_transport/https_proxy_resolver.dart';
import 'src/infrastructure/git_transport/libgit2_source_transport.dart';
import 'src/infrastructure/git_transport/routing_git_source_transport.dart';
import 'src/infrastructure/git_transport/system_git_availability.dart';
import 'src/infrastructure/git_transport/system_git_environment_probe.dart';
import 'src/infrastructure/git_transport/system_git_source_transport.dart';
import 'src/infrastructure/identity/uuid_workspace_identities.dart';
import 'src/infrastructure/project_roots/file_system_project_root_path.dart';
import 'src/infrastructure/project_roots/system_project_root_services.dart';
import 'src/infrastructure/revision_store_update_candidate_content.dart';
import 'src/infrastructure/runtime/drift_control_plane_lifecycle.dart';
import 'src/infrastructure/runtime/fresh_workspace_startup_recovery.dart';
import 'src/infrastructure/source/application_source_adapters.dart';
import 'src/infrastructure/source/application_source_payload_adapter.dart';
import 'src/infrastructure/source/git_application_source_adapter.dart';
import 'src/infrastructure/source/local_source.dart';
import 'src/infrastructure/source/well_known_source.dart';
import 'src/infrastructure/workspace_layout.dart';
import 'src/native/revision_worker/revision_worker_runtime.dart';
import 'src/native/source_transport/source_transport_native.dart';
import 'src/platform/activation/file_system_symbolic_link_capability.dart';
import 'src/platform/activation/filesystem_activation_operation_plan.dart';
import 'src/platform/activation/workspace_activation_location_identity.dart';
import 'src/platform/filesystem/control_plane_backup_durability.dart';
import 'src/platform/filesystem/directory_draft_change_hint.dart';
import 'src/platform/filesystem/durable_workspace_filesystem.dart';
import 'src/platform/filesystem/file_system_published_artifact_metadata_observer.dart';
import 'src/platform/filesystem/file_system_skill_drift_exporter.dart';
import 'src/platform/filesystem/posix_filesystem_primitives.dart';
import 'src/platform/filesystem/windows_filesystem_primitives.dart';
import 'src/platform/filesystem/workspace_file_lock.dart';
import 'src/platform/filesystem/workspace_path_identity.dart';
import 'src/platform/operations/filesystem_operation_recovery.dart';
import 'src/platform/operations/operation_abort_classifier.dart';
import 'src/platform/operations/operation_recovery_bundle.dart';

/// Creates one fully wired local Skill Workspace backend.
///
/// Construction is synchronous and does not open SQLite, start the Revision
/// worker, execute system Git, or mutate the filesystem. Call [SkillsRepository.open]
/// to acquire runtime resources and publish the first Snapshot.
SkillsRepository createSkillsRepository(
  SkillsRepositoryConfiguration configuration,
) {
  final layout = WorkspaceLayout(configuration.rootPath);
  final primitives = Platform.isWindows
      ? const WindowsFilesystemPrimitives()
      : const PosixFilesystemPrimitives();
  final pathIdentity = WorkspacePathIdentityResolver(primitives: primitives);
  final filesystem = PlatformDurableWorkspaceFilesystem.withPrimitives(
    primitives: primitives,
  );
  final lockPolicy = _filesystemLockPolicy(configuration.defaultLockWaitPolicy);
  final runtimeLock = WorkspaceFileLock(
    lockPath: layout.runtimeOwnershipLockPath,
    waitPolicy: lockPolicy,
    filesystem: filesystem,
  );
  final operationWriterLock = WorkspaceFileLock(
    lockPath: layout.operationWriterLockPath,
    waitPolicy: lockPolicy,
    filesystem: filesystem,
  );
  final database = WorkspaceDatabase.forFile(
    File(layout.databasePath),
    busyTimeout: _databaseBusyTimeout(configuration.defaultLockWaitPolicy),
  );
  final controlPlaneLifecycle = DriftControlPlaneLifecycle(database);
  final revisionRuntime = RevisionWorkerRuntime(
    taskExecutor: executeComposedRevisionWorkerTask,
  );
  final materializationInspectionWorkers =
      MaterializationInspectionWorkerPool();
  final requestGate = WorkspaceRequestGate();

  final backupDurability = PlatformControlPlaneBackupDurability(filesystem);
  final backups = ControlPlaneBackupService(
    database: database,
    durability: backupDurability,
    paths: ControlPlaneBackupPaths(
      workspaceRoot: layout.rootPath,
      primaryDatabasePath: layout.databasePath,
      backupRoot: layout.controlPlaneBackupsRoot,
      eligibilityPath: layout.backupEligibilityPath,
    ),
  );
  final startupRecovery = FreshWorkspaceStartupRecovery(
    layout: layout,
    establishedRecovery: backups,
    initializeEmptyControlPlane: () async {
      await controlPlaneLifecycle.open();
      return database.liveIdentity();
    },
    abandonInitializedControlPlane: controlPlaneLifecycle.close,
  );

  final revisionAccessGate = ManagedSkillRevisionAccessGate();
  final pointers = DriftRevisionPointerReader(database);
  final effectiveContent = RevisionStoreAccessService(
    pointers: pointers,
    accessGate: revisionAccessGate,
    storePath: layout.revisionStorePath,
    revisionEngine: revisionRuntime,
  );
  final draftSnapshots = DraftSnapshotCoordinator(
    filesystem: revisionRuntime,
    content: revisionRuntime,
  );
  final draftInspection = DriftUpdateDraftInspection(
    database: database,
    layout: layout,
    accessGate: revisionAccessGate,
    storePath: layout.revisionStorePath,
    revisions: revisionRuntime,
    snapshots: draftSnapshots,
  );
  final snapshotProjection = WorkspaceSnapshotReader(
    database: database,
    layout: layout,
  );
  final snapshots = WorkspaceSnapshotPublisher(
    reader: DraftAwareWorkspaceSnapshotReader(
      projection: snapshotProjection,
      draftInspection: draftInspection,
    ),
    draftChangeHints: DirectoryDraftChangeHintPort(),
  );
  final revisionReferences = DriftWorkspaceRevisionReferenceReconciliation(
    database: database,
    layout: layout,
    revisionEngine: revisionRuntime,
  );
  final artifactInspector = FileSystemPublishedArtifactInspector(
    contentWorker: materializationInspectionWorkers,
    metadataObserver: const FileSystemPublishedArtifactMetadataObserver(),
  );
  final materializations = DriftWorkspaceMaterializationReconciler(
    database: database,
    layout: layout,
    revisionEngine: revisionRuntime,
    filesystem: filesystem,
    artifactInspector: artifactInspector,
    accessGate: revisionAccessGate,
  );
  final derivedState = WorkspaceDerivedStateReconciler(
    revisionReferences: revisionReferences,
    materializations: materializations,
  );

  final recoverySpecs = OperationRecoverySpecRegistry();
  final recoveryPlanFactory = OperationRecoveryPlanFactory(
    registry: recoverySpecs,
  );
  final identities = UuidWorkspaceIdentities();
  final operationPlans = OperationPlanAssembler(
    subjectIdentities: identities,
    recoveryPlans: recoveryPlanFactory,
  );
  final backupMaintenance = WorkspaceOperationRecoveryBackupMaintenance(
    backups: backups,
    database: database,
  );
  final destructiveMaintenance = WorkspaceDestructiveRecoveryMaintenance(
    accessGate: revisionAccessGate,
  );
  final recovery = FilesystemOperationRecovery(
    layout: layout,
    filesystem: filesystem,
    registry: recoverySpecs,
    backupMaintenance: backupMaintenance,
    destructiveMaintenance: destructiveMaintenance,
    draftSnapshots: revisionRuntime,
    manifestWorker: revisionRuntime,
  );
  final controlPlane = DriftOperationControlPlane(database: database);
  final referenceMaintenance = WorkspaceOperationRevisionReferenceMaintenance(
    reconciliation: revisionReferences,
    snapshots: snapshots,
  );
  final operations = OperationCoordinator(
    writerLock: operationWriterLock,
    controlPlane: controlPlane,
    recovery: recovery,
    referenceMaintenance: referenceMaintenance,
    classifyAbort: classifyPlatformOperationAbort,
  );
  final finalizationRecovery = OperationCoordinatorFinalizationRecovery(
    operations: operations,
  );
  final journalRecovery = WorkspaceJournalRecoveryAdapter(
    controlPlane: controlPlane,
    operations: operations,
  );

  const sourceTransportNative = SourceTransportNative();
  final localSource = LocalSourceAdapter(
    contentWorker: revisionRuntime,
    followDirectoryLinks: true,
  );
  final activationLocationSource = LocalSourceAdapter(
    contentWorker: revisionRuntime,
  );
  final sources = SourceAcquisitionCoordinator(
    local: LocalApplicationSourceAdapter(adapter: localSource),
    git: GitApplicationSourceAdapter(
      // Public HTTPS Sources use the embedded libgit2; system Git serves SSH
      // and local locators and is the fallback (ADR-0106).
      transport: RoutingGitSourceTransport(
        libgit2: Libgit2SourceTransport(
          native: sourceTransportNative,
          proxySelector: HttpsProxyResolver(
            readWindowsSettings: windowsProxySettingsFrom(
              sourceTransportNative,
            ),
          ).select,
        ),
        systemGit: SystemGitSourceTransport(),
        systemGitAvailability: PathSystemGitAvailability(),
      ),
      contentWorker: revisionRuntime,
    ),
    wellKnown: WellKnownApplicationSourceAdapter(
      adapter: WellKnownSourceAdapter(contentWorker: revisionRuntime),
    ),
  );

  final platform = _desktopPlatform();
  final agentDetection = FileSystemAgentDetection();
  final builtIns = buildBuiltInAgentDefinitions(
    platform: platform,
    environment: _agentEnvironment(configuration.agentHomePath),
  );
  final catalogsResult = AgentCatalogController.create(
    platform: platform,
    detectionPort: agentDetection,
    builtIns: builtIns,
    additional: configuration.additionalAgents,
  );
  final catalogs = catalogsResult.valueOrNull;
  if (catalogs == null) {
    throw ArgumentError.value(
      configuration.additionalAgents,
      'configuration.additionalAgents',
      'conflicts with the built-in Agent Catalog',
    );
  }
  final ownershipAuditor = AgentRootOwnershipAuditor(
    catalogs: catalogs,
    inspection: const PlatformAgentRootOwnershipInspection(),
    userHomePath: _agentHomePath(configuration.agentHomePath),
  );
  final locationIdentity = WorkspaceActivationLocationIdentity(pathIdentity);
  final symbolicLinks = FileSystemSymbolicLinkCapability();
  ActivationTargetResolver targetResolver() => ActivationTargetResolver(
    catalog: catalogs.current,
    symbolicLinkCapability: symbolicLinks,
    locationIdentity: locationIdentity,
  );
  final occupancyProbe = FileSystemActivationOccupancyProbe(
    repositoryCopyPathForSkill: (skill) =>
        layout.repositoryCopyPath(skill.slotKey),
    locationIdentity: locationIdentity,
    localSource: activationLocationSource,
  );
  final targetExpectations = ActivationTargetExpectationProbe(
    occupancyProbe: occupancyProbe,
  );
  ActivationOccupancyInspector occupancyInspector() =>
      ActivationOccupancyInspector(
        targetResolver: targetResolver(),
        locationIdentity: locationIdentity,
        occupancyProbe: occupancyProbe,
      );
  ExternalSkillScanner externalSkills() => ExternalSkillScanner(
    catalog: catalogs.current,
    activationTargetResolver: targetResolver(),
    locationIdentity: locationIdentity,
    locationPort: FileSystemExternalSkillLocation(
      localSource: activationLocationSource,
    ),
  );

  final candidateContent = RevisionStoreUpdateCandidateContent(
    accessGate: revisionAccessGate,
    storePath: layout.revisionStorePath,
    pointers: pointers,
    revisionEngine: revisionRuntime,
  );
  final draftUpdateState = DriftDraftUpdateState(
    database: database,
    draftInspection: draftInspection,
    candidateContent: candidateContent,
  );
  final slotMigrations = FileSystemUpdateSlotMigrationInspector(
    repositoryCopyPathForSlot: layout.repositoryCopyPath,
  );
  final revisionPreparation = WorkspaceRevisionPreparationService(
    revisions: revisionRuntime,
    layout: layout,
    filesystem: filesystem,
    drafts: draftSnapshots,
  );
  final revisionOperationPlans = WorkspaceRevisionOperationPlans(
    assembler: operationPlans,
    recoverySpecs: recoverySpecs,
    layout: layout,
    targetExpectations: targetExpectations,
    artifactInspector: artifactInspector,
  );

  final sourcePayloads = ApplicationSourcePayloadAdapter();
  final initialImports = InitialImportPlanner(
    activationTargetResolverFactory: targetResolver,
    sourceAcquisition: sources,
    activationTargetResolver: targetResolver(),
    occupancyProbe: occupancyProbe,
    locationIdentity: locationIdentity,
    identities: identities,
    sourcePayloads: sourcePayloads,
    revisionCandidates: revisionPreparation,
    clock: () => DateTime.now().toUtc(),
  );
  final updates = UpdatePlanner(
    sourceAcquisition: sources,
    drafts: draftInspection,
    states: draftUpdateState,
    slotMigrations: slotMigrations,
    clock: () => DateTime.now().toUtc(),
  );
  final candidates = UpdateCandidatePlanner(
    states: draftUpdateState,
    slotMigrations: slotMigrations,
    clock: () => DateTime.now().toUtc(),
  );
  final historyContent = DriftWorkspaceHistoryContent(
    database: database,
    accessGate: revisionAccessGate,
    storePath: layout.revisionStorePath,
    revisionEngine: revisionRuntime,
    draftInspection: draftInspection,
  );
  final history = WorkspaceHistoryService(
    content: historyContent,
    clock: () => DateTime.now().toUtc(),
  );
  final destructiveEntries = WorkspaceDestructiveRecoveryEntries(
    database: database,
    layout: layout,
    revisions: revisionRuntime,
    filesystem: filesystem,
    recoverySpecs: recoverySpecs,
  );
  final destructivePlanner = DestructiveOperationPlanner(
    identities: identities,
    replacementPreparation: WorkspaceSourceReplacementPreparation(
      sources: sources,
      sourcePayloads: sourcePayloads,
      revisions: revisionRuntime,
      layout: layout,
      filesystem: filesystem,
    ),
    recoveryEntries: destructiveEntries,
    operationPlans: operationPlans,
    clock: () => DateTime.now().toUtc().microsecondsSinceEpoch,
  );

  final dispatcher = RepositoryCommandComposition(
    snapshots: snapshots,
    materializations: materializations,
    writerLock: operationWriterLock,
    operations: operations,
    finalizationRecovery: finalizationRecovery,
    sources: sources,
    effectiveContent: effectiveContent,
    externalSkills: externalSkills,
    historyPort: WorkspaceHistoryReader(database),
    history: history,
    catalogs: catalogs,
    ownershipAuditor: ownershipAuditor,
    occupancyInspector: occupancyInspector,
    activationMetadata: DriftActivationMetadataReader(database: database),
    activationMutations: ActivationMutationPlanner(
      locationIdentity: locationIdentity,
      identities: identities,
      clock: () => DateTime.now().toUtc(),
    ),
    activationPlans: FilesystemActivationOperationPlan(
      materializationPaths: WorkspaceActivationMaterializationPaths(
        layout: layout,
      ),
      assembler: operationPlans,
      recoverySpecs: recoverySpecs,
      targetExpectations: targetExpectations,
    ),
    operationPlans: operationPlans,
    projectRoots: ProjectRootPlanner(
      pathPort: const FileSystemProjectRootPath(),
      locationIdentity: locationIdentity,
      idPort: const UuidProjectRootId(),
      clock: const SystemWorkspaceClock(),
    ),
    library: LibraryMutationPlanner(tagIds: identities.allocateActivationId),
    clock: const SystemWorkspaceClock(),
    initialImports: initialImports,
    initialImportPlans: revisionOperationPlans,
    drafts: DraftPlanner(
      states: draftUpdateState,
      clock: () => DateTime.now().toUtc(),
    ),
    draftAssembler: const DraftPlanAssembler(),
    draftRevisions: revisionPreparation,
    draftPlans: revisionOperationPlans,
    updates: updates,
    candidates: candidates,
    updateAssembler: const UpdatePlanAssembler(),
    updateRevisions: revisionPreparation,
    updatePlans: revisionOperationPlans,
    driftPlanner: DriftResolutionPlanner(
      content: historyContent,
      clock: () => DateTime.now().toUtc(),
    ),
    driftExporter: FileSystemSkillDriftExporter(filesystem: filesystem),
    driftRevisions: revisionPreparation,
    driftPlans: revisionOperationPlans,
    artifactInspector: artifactInspector,
    forbiddenExportRoots: () => [
      layout.rootPath,
      for (final skill in snapshots.current.managedSkills)
        for (final activation in skill.activations) activation.location,
      for (final definition in catalogs.current.definitions)
        if (definition.onPlatform(catalogs.current.platform)
            case final rules?) ...[
          ?rules.globalSkillsPath,
          for (final root in snapshots.current.projectRoots)
            if (rules.projectSkillsPath case final relative?)
              path.join(root.path, relative),
        ],
    ],
    restoreAssembler: const RestorePlanAssembler(),
    restoreRevisions: revisionPreparation,
    restorePlans: revisionOperationPlans,
    destructiveState: DriftDestructivePlanningState(
      database: database,
      draftInspection: draftInspection,
    ),
    destructivePlanner: destructivePlanner,
  ).buildDispatcher();

  final lifecycle = WorkspaceOpenCoordinator(
    writerLock: runtimeLock,
    startupRecovery: startupRecovery,
    controlPlane: controlPlaneLifecycle,
    revisionWorker: WorkspaceRevisionWorkerLifecycleGroup([
      revisionRuntime,
      materializationInspectionWorkers,
    ]),
    revisionMaintenance: DriftWorkspaceRevisionMaintenance(
      database: database,
      layout: layout,
      revisionEngine: revisionRuntime,
      filesystem: filesystem,
    ),
    journalRecovery: journalRecovery,
    reconciler: derivedState,
    snapshots: snapshots,
    requestGate: requestGate,
  );
  return DefaultSkillsRepository(
    runtime: SkillsRepositoryRuntimeAdapter(
      lifecycle: lifecycle,
      snapshots: snapshots,
      requestGate: requestGate,
      updateCheckStore: DriftUpdateCheckStore(database),
    ),
    dispatcher: dispatcher,
    operationIds: identities.allocateOperationId,
    // Constructed, never run here: probing during wiring would spawn a child
    // process and, on an affected macOS host, raise the operating system's
    // install dialog without the user having asked for anything.
    gitEnvironment: const SystemGitEnvironmentProbe(),
  );
}

DesktopPlatform _desktopPlatform() {
  if (Platform.isMacOS) return DesktopPlatform.macos;
  if (Platform.isWindows) return DesktopPlatform.windows;
  if (Platform.isLinux) return DesktopPlatform.linux;
  throw UnsupportedError('skills_workspace supports desktop platforms only.');
}

Map<String, String> _agentEnvironment(String? agentHomePath) {
  final environment = Map<String, String>.of(Platform.environment);
  if (agentHomePath == null) return environment;
  environment['HOME'] = agentHomePath;
  environment['USERPROFILE'] = agentHomePath;
  for (final key in const <String>[
    'XDG_CONFIG_HOME',
    'CODEX_HOME',
    'CLAUDE_CONFIG_DIR',
    'VIBE_HOME',
    'HERMES_HOME',
    'AUTOHAND_HOME',
    'GROK_HOME',
    'SARVAM_HOME',
    'REASONIX_HOME',
    'DSH_HOME',
    'DSH_AGENTS_HOME',
    'APPDATA',
  ]) {
    environment.remove(key);
  }
  return environment;
}

String _agentHomePath(String? configured) {
  if (configured != null) return configured;
  final environment = Platform.environment;
  final value = Platform.isWindows
      ? environment['USERPROFILE']
      : environment['HOME'];
  if (value == null || value.trim().isEmpty) {
    throw StateError('The current user Home directory is unavailable.');
  }
  return path.normalize(path.absolute(value));
}

FilesystemLockWaitPolicy _filesystemLockPolicy(LockWaitPolicy policy) =>
    policy.waits
    ? FilesystemLockWaitPolicy.wait(
        timeout: policy.timeout,
        pollInterval: policy.pollInterval,
      )
    : const FilesystemLockWaitPolicy.failFast();

Duration _databaseBusyTimeout(LockWaitPolicy policy) {
  if (!policy.waits) return Duration.zero;
  return policy.timeout ?? const Duration(minutes: 2);
}
