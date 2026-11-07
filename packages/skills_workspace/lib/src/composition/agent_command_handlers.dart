import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/activation/activation_result.dart';
import '../application/agents/agent_catalog_controller.dart';
import '../application/agents/agent_root_ownership_auditor.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/public_models.dart';

/// Builds Agent Catalog and target-inspection commands.
///
/// Catalog replacement is intentionally in-memory. The App owns persistence
/// for user-defined Agent settings and supplies them again on the next open.
List<SkillsCommandHandler> buildAgentCommandHandlers({
  required AgentCatalogController catalogs,
  required AgentRootOwnershipAuditor ownershipAuditor,
  required WorkspaceSnapshotPublisher snapshots,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<InspectAgentsRequest, List<AgentInfo>>(
    kind: WorkspaceOperationKind.inspectAgents,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final catalog = catalogs.current;
      final roots = snapshots.current.projectRoots;
      final globallyDetected = await catalog.detect();
      final projectDetections = <String, Set<String>>{};
      for (final root in roots) {
        projectDetections[root.id] = await catalog.detect(projectRoot: root);
      }
      final agents = <AgentInfo>[];
      for (final definition in catalog.definitions) {
        if (definition.id == 'universal') continue;
        final rules = definition.onPlatform(catalog.platform);
        if (rules == null) continue;
        agents.add(
          AgentInfo(
            id: definition.id,
            displayName: definition.displayName,
            isBuiltIn: catalogs.isBuiltIn(definition.id),
            supportedScopes: {
              if (rules.globalSkillsPath != null) ActivationScope.global,
              if (rules.projectSkillsPath != null) ActivationScope.project,
            },
            detectedGlobally: globallyDetected.contains(definition.id),
            detectedProjectRootIds: {
              for (final entry in projectDetections.entries)
                if (entry.value.contains(definition.id)) entry.key,
            },
          ),
        );
      }
      agents.sort((a, b) => a.id.compareTo(b.id));
      return SkillsSuccess(value: List.unmodifiable(agents), changed: false);
    },
  ),
  TypedSkillsCommandHandler<
    InspectActivationTargetsRequest,
    List<ActivationTargetInfo>
  >(
    kind: WorkspaceOperationKind.inspectActivationTargets,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final projectRoot = request.scope == ActivationScope.project
          ? snapshot.findProjectRoot(request.projectRootId!)
          : null;
      if (request.scope == ActivationScope.project && projectRoot == null) {
        return SkillsFailure<List<ActivationTargetInfo>>(
          code: SkillsErrorCode.projectRootNotFound,
          context: <String, Object?>{'projectRootId': request.projectRootId},
        );
      }

      final catalog = catalogs.current;
      final detected = await catalog.detect(projectRoot: projectRoot);
      final definitions = catalog.definitions.toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      final targets = <ActivationTargetInfo>[];
      for (final definition in definitions) {
        final resolved = catalog.resolve(
          agentId: definition.id,
          scope: request.scope,
          projectRoot: projectRoot,
        );
        final target = resolved.valueOrNull;
        if (target == null) continue;
        targets.add(
          ActivationTargetInfo(
            agentId: definition.id,
            displayName: definition.displayName,
            detected: detected.contains(definition.id),
            location: target.location,
            scope: target.scope,
            projectRootId: target.projectRootId,
            projectRootPath: target.projectRootPath,
          ),
        );
      }
      return SkillsSuccess<List<ActivationTargetInfo>>(
        value: targets,
        changed: false,
      );
    },
  ),
  TypedSkillsCommandHandler<
    InspectAgentRootOwnershipRequest,
    AgentRootOwnershipAudit
  >(
    kind: WorkspaceOperationKind.inspectAgentRootOwnership,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      try {
        return SkillsSuccess<AgentRootOwnershipAudit>(
          value: await ownershipAuditor.inspect(),
          changed: false,
        );
      } on Object {
        return SkillsFailure<AgentRootOwnershipAudit>(
          code: SkillsErrorCode.ioFailure,
          context: const <String, Object?>{
            'reason': 'agentRootOwnershipInspectionFailed',
          },
        );
      }
    },
  ),
  TypedSkillsCommandHandler<ReconfigureAgentCatalogRequest, RepositorySnapshot>(
    kind: WorkspaceOperationKind.reconfigureAgentCatalog,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final result = catalogs.reconfigure(request.agents);
      final failure = result.failureOrNull;
      if (failure != null) {
        return SkillsFailure<RepositorySnapshot>(
          code: _activationFailure(failure.code),
          context: failure.context,
        );
      }
      return SkillsSuccess<RepositorySnapshot>(
        value: snapshots.current,
        changed: result.valueOrNull!.changed,
      );
    },
  ),
];

SkillsErrorCode _activationFailure(
  ActivationFailureCode code,
) => switch (code) {
  ActivationFailureCode.duplicateAgentId => SkillsErrorCode.duplicateAgentId,
  ActivationFailureCode.agentNotFound => SkillsErrorCode.agentNotFound,
  ActivationFailureCode.activationUnsupported =>
    SkillsErrorCode.activationUnsupported,
  ActivationFailureCode.projectRootNotFound =>
    SkillsErrorCode.projectRootNotFound,
  ActivationFailureCode.activationUnavailable =>
    SkillsErrorCode.activationUnavailable,
  ActivationFailureCode.externalConflict => SkillsErrorCode.externalConflict,
  ActivationFailureCode.skillNotFound => SkillsErrorCode.skillNotFound,
  ActivationFailureCode.operationCancelled =>
    SkillsErrorCode.operationCancelled,
};
