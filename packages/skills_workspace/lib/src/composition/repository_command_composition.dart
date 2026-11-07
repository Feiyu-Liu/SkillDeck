import '../api/composite_command_dispatcher.dart';
import '../application/activation/activation_mutation_planner.dart';
import '../application/activation/activation_occupancy_inspector.dart';
import '../application/agents/agent_catalog_controller.dart';
import '../application/agents/agent_root_ownership_auditor.dart';
import '../application/destructive/destructive_operation_planner.dart';
import '../application/discovery/external_skill_scanner.dart';
import '../application/drafts/draft_plan_assembler.dart';
import '../application/drafts/draft_planner.dart';
import '../application/drafts/draft_ports.dart';
import '../application/drift/drift_models.dart';
import '../application/drift/drift_resolution_planner.dart';
import '../application/history/history_ports.dart';
import '../application/history/history_service.dart';
import '../application/history/restore_plan_assembler.dart';
import '../application/install/initial_import_planner.dart';
import '../application/library/library_mutation_planner.dart';
import '../application/operations/finalization_recovery_service.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_plan_assembler.dart';
import '../application/ports/activation_mutation_ports.dart';
import '../application/ports/destructive_operation_ports.dart';
import '../application/ports/external_discovery_ports.dart';
import '../application/ports/history_ports.dart';
import '../application/ports/initial_import_ports.dart';
import '../application/ports/operation_ports.dart';
import '../application/ports/published_artifact_ports.dart';
import '../application/ports/revision_store_access_ports.dart';
import '../application/ports/update_ports.dart';
import '../application/ports/workspace_lifecycle_ports.dart';
import '../application/project_roots/project_root_planner.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../application/source/source_acquisition_coordinator.dart';
import '../application/update/update_command_ports.dart';
import '../application/update/update_planner.dart';
import '../domain/public_models.dart';
import 'activation_command_handlers.dart';
import 'agent_command_handlers.dart';
import 'corrupt_skill_mutation_guard.dart';
import 'destructive_command_handlers.dart';
import 'draft_command_handlers.dart';
import 'drift_command_handlers.dart';
import 'effective_revision_content_command_handlers.dart';
import 'history_command_handlers.dart';
import 'initial_import_command_handlers.dart';
import 'metadata_command_handlers.dart';
import 'read_command_handlers.dart';
import 'skill_integrity_coordinator.dart';
import 'update_check_command_handler.dart';
import 'update_command_handlers.dart';
import 'validation_command_handlers.dart';

/// Complete application-layer handler wiring for one Workspace runtime.
///
/// This is deliberately separate from the public repository factory. It is a
/// dependency-injection seam: every required adapter is explicit, and a
/// composition root cannot accidentally make an operation appear supported by
/// omitting a handler or supplying a nullable no-op implementation.
final class RepositoryCommandComposition {
  RepositoryCommandComposition({
    required this.snapshots,
    required this.materializations,
    required this.writerLock,
    required this.operations,
    required this.finalizationRecovery,
    required this.sources,
    required this.effectiveContent,
    required this.externalSkills,
    required this.historyPort,
    required this.history,
    required this.catalogs,
    required this.ownershipAuditor,
    required this.occupancyInspector,
    required this.activationMetadata,
    required this.activationMutations,
    required this.activationPlans,
    required this.operationPlans,
    required this.projectRoots,
    required this.library,
    required this.clock,
    required this.initialImports,
    required this.initialImportPlans,
    required this.drafts,
    required this.draftAssembler,
    required this.draftRevisions,
    required this.draftPlans,
    required this.updates,
    required this.candidates,
    required this.updateAssembler,
    required this.updateRevisions,
    required this.updatePlans,
    required this.driftExporter,
    required this.driftPlanner,
    required this.driftRevisions,
    required this.driftPlans,
    required this.artifactInspector,
    required this.forbiddenExportRoots,
    required this.restoreAssembler,
    required this.restoreRevisions,
    required this.restorePlans,
    required this.destructiveState,
    required this.destructivePlanner,
  });

  final WorkspaceSnapshotPublisher snapshots;
  final WorkspaceMaterializationReconciliationPort materializations;
  final WorkspaceWriterLockPort writerLock;
  final OperationCoordinator operations;
  final WorkspaceFinalizationRecoveryPort finalizationRecovery;
  final SourceAcquisitionCoordinator sources;
  final CurrentEffectiveRevisionContentPort effectiveContent;
  final ExternalSkillScannerFactory externalSkills;
  final WorkspaceHistoryPort historyPort;
  final WorkspaceHistoryService history;
  final AgentCatalogController catalogs;
  final AgentRootOwnershipAuditor ownershipAuditor;
  final ActivationOccupancyInspectorFactory occupancyInspector;
  final ActivationMetadataReaderPort activationMetadata;
  final ActivationMutationPlanner activationMutations;
  final ActivationOperationPlanPort activationPlans;
  final OperationPlanAssembler operationPlans;
  final ProjectRootPlanner projectRoots;
  final LibraryMutationPlanner library;
  final WorkspaceClockPort clock;
  final InitialImportPlanner initialImports;
  final InitialImportOperationPlanPort initialImportPlans;
  final DraftPlanner drafts;
  final DraftPlanAssembler draftAssembler;
  final DraftRevisionPreparationPort draftRevisions;
  final DraftOperationPlanPort draftPlans;
  final UpdatePlanner updates;
  final UpdateCandidatePlanner candidates;
  final UpdatePlanAssembler updateAssembler;
  final UpdateRevisionPreparationPort updateRevisions;
  final UpdateOperationPlanPort updatePlans;
  final DriftArtifactExporterPort driftExporter;
  final DriftResolutionPlanner driftPlanner;
  final DriftRevisionPreparationPort driftRevisions;
  final DriftOperationPlanPort driftPlans;
  final PublishedArtifactInspectorPort artifactInspector;
  final List<String> Function() forbiddenExportRoots;
  final RestorePlanAssembler restoreAssembler;
  final RestoreRevisionPreparationPort restoreRevisions;
  final RestoreOperationPlanPort restorePlans;
  final DestructivePlanningStatePort destructiveState;
  final DestructiveOperationPlanner destructivePlanner;

  /// Builds the one dispatcher used by [DefaultSkillsRepository].
  ///
  /// The expected set intentionally excludes only lifecycle operations. The
  /// check catches a newly added public command that was not wired here.
  CompositeSkillsRepositoryCommandDispatcher buildDispatcher() {
    final integrity = SkillIntegrityCoordinator(
      snapshots: snapshots,
      materializations: materializations,
      writerLock: writerLock,
    );
    final handlers = <SkillsCommandHandler>[
      ...buildDriftCommandHandlers(
        snapshots: snapshots,
        materializations: materializations,
        inspector: artifactInspector,
        exporter: driftExporter,
        planner: driftPlanner,
        revisions: driftRevisions,
        plans: driftPlans,
        operations: operations,
        integrity: integrity,
        forbiddenExportRoots: forbiddenExportRoots,
      ),
      ...buildReadCommandHandlers(
        snapshots: snapshots,
        finalizationRecovery: finalizationRecovery,
        sources: sources,
        externalSkills: externalSkills,
        history: historyPort,
      ),
      ...buildValidationCommandHandlers(
        snapshots: snapshots,
        integrity: integrity,
      ),
      ...buildEffectiveRevisionContentCommandHandlers(
        snapshots: snapshots,
        content: effectiveContent,
        integrity: integrity,
      ),
      ...buildInitialImportCommandHandlers(
        snapshots: snapshots,
        operations: operations,
        sources: sources,
        externalSkills: externalSkills,
        initialImports: initialImports,
        plans: initialImportPlans,
      ),
      buildUpdateCheckCommandHandler(snapshots: snapshots, updates: updates),
      ...buildUpdateCommandHandlers(
        snapshots: snapshots,
        operations: operations,
        updates: updates,
        candidates: candidates,
        assembler: updateAssembler,
        revisions: updateRevisions,
        plans: updatePlans,
      ),
      ...buildDestructiveCommandHandlers(
        snapshots: snapshots,
        operations: operations,
        operationPlans: operationPlans,
        state: destructiveState,
        planner: destructivePlanner,
      ),
      ...buildAgentCommandHandlers(
        catalogs: catalogs,
        ownershipAuditor: ownershipAuditor,
        snapshots: snapshots,
      ),
      ...buildActivationCommandHandlers(
        snapshots: snapshots,
        operations: operations,
        occupancyInspector: occupancyInspector,
        activationMetadata: activationMetadata,
        activationMutations: activationMutations,
        plans: activationPlans,
      ),
      ...buildMetadataCommandHandlers(
        snapshots: snapshots,
        operations: operations,
        plans: operationPlans,
        projectRoots: projectRoots,
        library: library,
        clock: clock,
      ),
      ...buildDraftCommandHandlers(
        snapshots: snapshots,
        operations: operations,
        drafts: drafts,
        assembler: draftAssembler,
        revisions: draftRevisions,
        plans: draftPlans,
      ),
      ...buildHistoryCommandHandlers(
        snapshots: snapshots,
        history: history,
        assembler: restoreAssembler,
        operations: operations,
        revisions: restoreRevisions,
        plans: restorePlans,
      ),
    ];
    assertCompleteBusinessHandlers(handlers);
    return CompositeSkillsRepositoryCommandDispatcher(
      guardCorruptSkillMutations(
        handlers: handlers,
        snapshots: snapshots,
        integrity: integrity,
      ),
    );
  }
}

typedef ExternalSkillScannerFactory = ExternalSkillScanner Function();
typedef ActivationOccupancyInspectorFactory =
    ActivationOccupancyInspector Function();

/// Verifies the dispatcher input independently of the concrete object graph.
///
/// Kept public within `lib/src` so composition tests can validate the
/// operation matrix without constructing native, Drift, or filesystem state.
void assertCompleteBusinessHandlers(List<SkillsCommandHandler> handlers) {
  final actual = handlers.map((handler) => handler.kind).toSet();
  final expected = WorkspaceOperationKind.values
      .where(
        (kind) =>
            kind != WorkspaceOperationKind.open &&
            kind != WorkspaceOperationKind.close,
      )
      .toSet();
  if (actual.length != handlers.length || actual.length != expected.length) {
    throw StateError(
      'Workspace command composition contains duplicate or missing handlers.',
    );
  }
  final missing = expected.difference(actual);
  final unexpected = actual.difference(expected);
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    throw StateError(
      'Workspace command composition mismatch: '
      'missing=${missing.map((kind) => kind.name).join(',')}, '
      'unexpected=${unexpected.map((kind) => kind.name).join(',')}',
    );
  }
}
