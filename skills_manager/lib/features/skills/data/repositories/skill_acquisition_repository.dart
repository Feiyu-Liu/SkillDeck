import 'package:skills_manager/features/skills/data/mappers/installed_skill_catalog_mapper.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_locator_resolver.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

String _defaultAgentIcon(String _) => 'bot';

final class AcquisitionTask<T> {
  const AcquisitionTask({
    required this.current,
    required this.states,
    required this.completed,
    required this.cancel,
  });

  final AcquisitionProgress current;
  final Stream<AcquisitionProgress> states;
  final Future<WorkspaceCompletion<T>> completed;
  final Future<void> Function() cancel;
}

final class InstallReceipt {
  InstallReceipt({required this.catalog, required Set<String> affectedSlotKeys})
    : affectedSlotKeys = Set.unmodifiable(affectedSlotKeys);

  final InstalledSkillCatalog catalog;
  final Set<String> affectedSlotKeys;
}

sealed class AcquisitionInstallAttempt {
  const AcquisitionInstallAttempt();
}

final class AcquisitionInstallCompleted extends AcquisitionInstallAttempt {
  const AcquisitionInstallCompleted(this.receipt);
  final InstallReceipt receipt;
}

final class AcquisitionInstallTakeoverRequired
    extends AcquisitionInstallAttempt {
  const AcquisitionInstallTakeoverRequired(this.draft);
  final WorkspaceInstallTakeoverDraft draft;
}

abstract interface class SkillAcquisitionRepository {
  List<AgentOption> get agents;

  Future<WorkspaceCompletion<List<AgentOption>>> inspectTargets({
    required SkillActivationScope scope,
    String? projectRootId,
  });

  AcquisitionTask<SkillSourceInspection> inspect(SkillSourceDraft draft);

  AcquisitionTask<AcquisitionInstallAttempt> install(
    InstallSelection selection,
  );

  AcquisitionTask<InstallReceipt> confirmInstallTakeover(
    WorkspaceInstallTakeoverDraft draft,
  );
}

final class WorkspaceSkillAcquisitionRepository
    implements SkillAcquisitionRepository {
  WorkspaceSkillAcquisitionRepository({
    required SkillsWorkspaceRepository workspace,
    required SkillSourceLocatorResolver resolver,
    this.agentIconName = _defaultAgentIcon,
    this.targetInspection,
  }) : _workspace = workspace,
       _resolver = resolver;

  final SkillsWorkspaceRepository _workspace;
  final SkillSourceLocatorResolver _resolver;
  final String Function(String agentId) agentIconName;
  final Future<WorkspaceCompletion<List<WorkspaceActivationTarget>>> Function(
    WorkspaceScope scope,
    String? projectRootId,
  )?
  targetInspection;
  List<AgentOption> _agents = const [];

  void replaceAgents(Iterable<AgentOption> agents) {
    _agents = List.unmodifiable(agents);
  }

  @override
  List<AgentOption> get agents => _agents;

  @override
  Future<WorkspaceCompletion<List<AgentOption>>> inspectTargets({
    required SkillActivationScope scope,
    String? projectRootId,
  }) async {
    final completion = await (targetInspection != null
        ? targetInspection!(
            scope == SkillActivationScope.global
                ? WorkspaceScope.global
                : WorkspaceScope.project,
            projectRootId,
          )
        : _workspace
              .inspectActivationTargets(
                scope: scope == SkillActivationScope.global
                    ? WorkspaceScope.global
                    : WorkspaceScope.project,
                projectRootId: projectRootId,
              )
              .completed);
    return switch (completion) {
      WorkspaceCompleted(:final value, :final warnings) => WorkspaceCompleted(
        value: _agents = List.unmodifiable([
          for (final target in value)
            AgentOption(
              id: target.agentId,
              displayName: target.displayName,
              detected: target.detected,
              location: target.location,
              iconName: agentIconName(target.agentId),
            ),
        ]),
        warnings: warnings,
      ),
      WorkspaceFailed(:final failure, :final warnings) => WorkspaceFailed(
        failure: failure,
        warnings: warnings,
      ),
      WorkspaceCommittedPending(
        :final operationId,
        :final committedRevision,
        :final warnings,
      ) =>
        WorkspaceCommittedPending(
          operationId: operationId,
          committedRevision: committedRevision,
          warnings: warnings,
        ),
    };
  }

  @override
  AcquisitionTask<SkillSourceInspection> inspect(SkillSourceDraft draft) {
    final resolved = _resolver.resolve(draft);
    final source = _workspaceSource(resolved);
    final task = _workspace.inspectSource(source);
    return AcquisitionTask(
      current: _workspaceProgress(task.current),
      states: task.states.map(_workspaceProgress),
      completed: task.completed.then(
        (completion) => switch (completion) {
          WorkspaceCompleted(:final value, :final warnings) =>
            WorkspaceCompleted(
              value: SkillSourceInspection(
                source: resolved,
                candidates: [
                  for (final candidate in value.candidates)
                    SkillCandidate(
                      slotKey: candidate.slotKey,
                      declaredName: candidate.declaredName,
                      description: candidate.description,
                      skillPath: candidate.skillPath,
                      contentHash: candidate.contentHash,
                      fileCount: candidate.fileCount,
                      byteSize: candidate.byteSize,
                    ),
                ],
              ),
              warnings: warnings,
            ),
          WorkspaceFailed(:final failure, :final warnings) => WorkspaceFailed(
            failure: failure,
            warnings: warnings,
          ),
          WorkspaceCommittedPending(
            :final operationId,
            :final committedRevision,
            :final warnings,
          ) =>
            WorkspaceCommittedPending(
              operationId: operationId,
              committedRevision: committedRevision,
              warnings: warnings,
            ),
        },
      ),
      cancel: task.cancel,
    );
  }

  @override
  AcquisitionTask<AcquisitionInstallAttempt> install(
    InstallSelection selection,
  ) {
    final task = _workspace.install(
      WorkspaceInstallRequest(
        source: _workspaceSource(selection.source),
        skillNames: selection.installAllSkills
            ? null
            : selection.selectedSkillNames,
        scope: selection.scope == SkillActivationScope.global
            ? WorkspaceScope.global
            : WorkspaceScope.project,
        projectRootId: selection.projectRootId,
        agentIds: selection.selectedAgentIds,
        storeOnly: selection.storeOnly,
        activationMethod: selection.activationMethod,
      ),
    );
    return AcquisitionTask(
      current: _workspaceProgress(task.current),
      states: task.states.map(_workspaceProgress),
      completed: task.completed.then(
        (completion) => switch (completion) {
          WorkspaceCompleted(:final value, :final warnings) =>
            WorkspaceCompleted(
              value: switch (value) {
                WorkspaceInstallCompleted(:final receipt) =>
                  AcquisitionInstallCompleted(_installReceipt(receipt)),
                WorkspaceInstallTakeoverRequired(:final draft) =>
                  AcquisitionInstallTakeoverRequired(draft),
              },
              warnings: warnings,
            ),
          WorkspaceFailed(:final failure, :final warnings) => WorkspaceFailed(
            failure: failure,
            warnings: warnings,
          ),
          WorkspaceCommittedPending(
            :final operationId,
            :final committedRevision,
            :final warnings,
          ) =>
            WorkspaceCommittedPending(
              operationId: operationId,
              committedRevision: committedRevision,
              warnings: warnings,
            ),
        },
      ),
      cancel: task.cancel,
    );
  }

  @override
  AcquisitionTask<InstallReceipt> confirmInstallTakeover(
    WorkspaceInstallTakeoverDraft draft,
  ) {
    final task = _workspace.confirmInstallTakeover(draft);
    return AcquisitionTask(
      current: _workspaceProgress(task.current),
      states: task.states.map(_workspaceProgress),
      completed: task.completed.then(
        (completion) => switch (completion) {
          WorkspaceCompleted(:final value, :final warnings) =>
            WorkspaceCompleted(
              value: _installReceipt(value),
              warnings: warnings,
            ),
          WorkspaceFailed(:final failure, :final warnings) => WorkspaceFailed(
            failure: failure,
            warnings: warnings,
          ),
          WorkspaceCommittedPending(
            :final operationId,
            :final committedRevision,
            :final warnings,
          ) =>
            WorkspaceCommittedPending(
              operationId: operationId,
              committedRevision: committedRevision,
              warnings: warnings,
            ),
        },
      ),
      cancel: task.cancel,
    );
  }

  InstallReceipt _installReceipt(WorkspaceMutationReceipt receipt) =>
      InstallReceipt(
        catalog: installedSkillCatalogFromWorkspace(receipt.snapshot),
        affectedSlotKeys: {
          for (final skillId in receipt.affectedSkillIds)
            if (receipt.snapshot.findSkillById(skillId) case final skill?)
              skill.slotKey,
        },
      );

  SkillSourceInput _workspaceSource(ResolvedSkillSource source) =>
      SkillSourceInput(
        kind: switch (source.kind) {
          SkillSourceKind.local => WorkspaceSourceKind.local,
          SkillSourceKind.git => WorkspaceSourceKind.git,
          SkillSourceKind.wellKnown => WorkspaceSourceKind.wellKnown,
        },
        locator: source.value,
        ref: source.ref,
        repositorySubpath: source.repositorySubpath,
      );

  AcquisitionProgress _workspaceProgress(WorkspaceOperationProgress state) =>
      AcquisitionProgress(
        phase: switch (state.phase) {
          WorkspaceOperationPhase.queued ||
          WorkspaceOperationPhase.preparing ||
          WorkspaceOperationPhase.recovering => AcquisitionPhase.preparing,
          WorkspaceOperationPhase.inspecting => AcquisitionPhase.inspecting,
          WorkspaceOperationPhase.waitingForLock =>
            AcquisitionPhase.waitingForLock,
          WorkspaceOperationPhase.planning => AcquisitionPhase.planning,
          WorkspaceOperationPhase.applying ||
          WorkspaceOperationPhase.committing ||
          WorkspaceOperationPhase.finalizing => AcquisitionPhase.applying,
          WorkspaceOperationPhase.rollingBack => AcquisitionPhase.rollingBack,
          WorkspaceOperationPhase.succeeded ||
          WorkspaceOperationPhase.failed ||
          WorkspaceOperationPhase.cancelled => AcquisitionPhase.completed,
        },
        currentItem: state.currentItem,
        completed: state.completed,
        total: state.total,
        warnings: state.warnings,
      );
}
