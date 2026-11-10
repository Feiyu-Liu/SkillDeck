import 'dart:async';

import 'package:skills_manager/features/skills/agent_root_ownership_coordinator.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

final class OwnershipGatedSkillsWorkspaceRepository
    implements SkillsWorkspaceRepository, SkillsUpdateCheckStore {
  OwnershipGatedSkillsWorkspaceRepository({
    required SkillsWorkspaceRepository delegate,
    required AgentRootOwnershipCoordinator coordinator,
  }) : _delegate = delegate,
       _coordinator = coordinator;

  final SkillsWorkspaceRepository _delegate;
  final AgentRootOwnershipCoordinator _coordinator;
  int _operationSequence = 0;

  @override
  Future<WorkspaceUpdateCacheSnapshot> readUpdateCache() =>
      _delegate is SkillsUpdateCheckStore
      ? (_delegate as SkillsUpdateCheckStore).readUpdateCache()
      : Future.value(WorkspaceUpdateCacheSnapshot(records: []));

  @override
  Future<void> upsertUpdateCache(WorkspaceUpdateCacheRecord record) =>
      _delegate is SkillsUpdateCheckStore
      ? (_delegate as SkillsUpdateCheckStore).upsertUpdateCache(record)
      : Future<void>.value();

  @override
  Future<void> removeUpdateCache(WorkspaceSkillId skillId) =>
      _delegate is SkillsUpdateCheckStore
      ? (_delegate as SkillsUpdateCheckStore).removeUpdateCache(skillId)
      : Future<void>.value();

  @override
  Future<void> writeLastFullUpdateSweepAt(DateTime value) =>
      _delegate is SkillsUpdateCheckStore
      ? (_delegate as SkillsUpdateCheckStore).writeLastFullUpdateSweepAt(value)
      : Future<void>.value();

  @override
  SkillsWorkspaceSnapshot? get current => _delegate.current;

  @override
  WorkspaceTask<WorkspaceSkillDriftReview> inspectSkillDrift(
    WorkspaceSkillId skillId,
  ) => _delegate.inspectSkillDrift(skillId);

  @override
  WorkspaceTask<WorkspaceSkillDriftExport> exportSkillDriftArtifact({
    required WorkspaceSkillDriftReview review,
    required String artifactId,
    required String destinationDirectory,
  }) => _delegate.exportSkillDriftArtifact(
    review: review,
    artifactId: artifactId,
    destinationDirectory: destinationDirectory,
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> resolveSkillDrift({
    required WorkspaceSkillDriftReview review,
    required WorkspaceDriftResolution resolution,
  }) {
    WorkspaceTask<WorkspaceMutationReceipt> start() =>
        _delegate.resolveSkillDrift(review: review, resolution: resolution);
    final touchesGlobal = switch (resolution) {
      WorkspaceKeepExternalSkillDrift() => _touchesGlobalActivations({
        review.skillId,
      }),
      WorkspaceRestoreManagedSkillDrift() =>
        review.artifacts.any(
              (artifact) => artifact.scope == WorkspaceScope.global,
            ) ||
            // The opaque review counts missing artifacts without exposing
            // their locations. Any current global Activation may be repaired.
            (review.missingArtifactCount > 0 &&
                _touchesGlobalActivations({review.skillId})),
    };
    return touchesGlobal
        ? _gated(WorkspaceOperationKind.resolveSkillDrift, start)
        : start();
  }

  @override
  Stream<SkillsWorkspaceSnapshot> get snapshots => _delegate.snapshots;

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> open() =>
      _delegate.open();

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> refresh() =>
      _delegate.refresh();

  @override
  WorkspaceTask<WorkspaceValidationReport> validateWorkspace({
    Set<WorkspaceSkillId>? skillIds,
  }) => _delegate.validateWorkspace(skillIds: skillIds);

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> resumeFinalizationRecovery() =>
      _delegate.resumeFinalizationRecovery();

  @override
  Future<WorkspaceCompletion<List<SkillDocumentEntry>>> listSkillDocuments(
    WorkspaceSkillId skillId,
  ) => _delegate.listSkillDocuments(skillId);

  @override
  Future<WorkspaceCompletion<String>> readSkillDocument(
    WorkspaceSkillId skillId,
    String relativePath, {
    required String expectedContentHash,
  }) => _delegate.readSkillDocument(
    skillId,
    relativePath,
    expectedContentHash: expectedContentHash,
  );

  @override
  WorkspaceTask<WorkspaceSourceInspection> inspectSource(
    SkillSourceInput source,
  ) => _delegate.inspectSource(source);

  @override
  Future<WorkspaceGitEnvironmentStatus> probeGitEnvironment() =>
      _delegate.probeGitEnvironment();

  @override
  WorkspaceTask<List<WorkspaceAgentInfo>> inspectAgents() =>
      _delegate.inspectAgents();

  @override
  WorkspaceTask<List<WorkspaceActivationTarget>> inspectActivationTargets({
    required WorkspaceScope scope,
    String? projectRootId,
  }) => _delegate.inspectActivationTargets(
    scope: scope,
    projectRootId: projectRootId,
  );

  @override
  WorkspaceTask<WorkspaceAgentRootOwnershipAudit> inspectAgentRootOwnership() =>
      _delegate.inspectAgentRootOwnership();

  @override
  WorkspaceTask<ExternalSkillsDiscovery> discoverExternalSkills() =>
      _delegate.discoverExternalSkills();

  @override
  WorkspaceTask<WorkspaceInstallAttempt> install(
    WorkspaceInstallRequest request,
  ) => request.storeOnly || request.scope == WorkspaceScope.project
      ? _delegate.install(request)
      : _gated(
          WorkspaceOperationKind.install,
          () => _delegate.install(request),
        );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> confirmInstallTakeover(
    WorkspaceInstallTakeoverDraft draft,
  ) => _gated(
    WorkspaceOperationKind.confirmInstallTakeover,
    () => _delegate.confirmInstallTakeover(draft),
  );

  @override
  WorkspaceTask<WorkspaceMutationReceipt> adopt(
    ExternalSkillAdoptionRequest request,
  ) => _gated(WorkspaceOperationKind.adopt, () => _delegate.adopt(request));

  @override
  WorkspaceTask<WorkspaceMutationReceipt> replaceSource({
    required WorkspaceSkillId skillId,
    required SkillSourceInput source,
    required int expectedRevision,
  }) {
    WorkspaceTask<WorkspaceMutationReceipt> start() => _delegate.replaceSource(
      skillId: skillId,
      source: source,
      expectedRevision: expectedRevision,
    );
    return _touchesGlobalActivations({skillId})
        ? _gated(WorkspaceOperationKind.replaceSource, start)
        : start();
  }

  @override
  WorkspaceTask<WorkspaceActivationAttempt> activate({
    required Set<WorkspaceSkillId> skillIds,
    required WorkspaceScope scope,
    required Set<String> agentIds,
    String? projectRootId,
    WorkspaceActivationMethod activationMethod =
        WorkspaceActivationMethod.automatic,
  }) {
    WorkspaceTask<WorkspaceActivationAttempt> start() => _delegate.activate(
      skillIds: skillIds,
      scope: scope,
      agentIds: agentIds,
      projectRootId: projectRootId,
      activationMethod: activationMethod,
    );
    final task = scope == WorkspaceScope.project
        ? start()
        : _gated(WorkspaceOperationKind.activate, start);
    return _tagTakeoverDraft(
      task,
      requiresOwnershipGate: scope == WorkspaceScope.global,
    );
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> confirmActivationTakeover(
    WorkspaceActivationTakeoverDraft draft,
  ) {
    final tagged = draft is _OwnershipTakeoverDraft ? draft : null;
    final backendDraft = tagged?.delegate ?? draft;
    WorkspaceTask<WorkspaceMutationReceipt> start() =>
        _delegate.confirmActivationTakeover(backendDraft);
    return tagged?.requiresOwnershipGate == false
        ? start()
        : _gated(WorkspaceOperationKind.confirmActivationTakeover, start);
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> deactivate({
    required Set<WorkspaceSkillId> skillIds,
    Set<String>? locations,
  }) {
    WorkspaceTask<WorkspaceMutationReceipt> start() =>
        _delegate.deactivate(skillIds: skillIds, locations: locations);
    return _touchesGlobalActivations(skillIds, locations: locations)
        ? _gated(WorkspaceOperationKind.deactivate, start)
        : start();
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> remove({
    required Set<WorkspaceSkillId> skillIds,
    required int expectedRevision,
  }) {
    WorkspaceTask<WorkspaceMutationReceipt> start() => _delegate.remove(
      skillIds: skillIds,
      expectedRevision: expectedRevision,
    );
    return _touchesGlobalActivations(skillIds)
        ? _gated(WorkspaceOperationKind.remove, start)
        : start();
  }

  @override
  WorkspaceTask<List<WorkspaceUpdateReport>> checkUpdates({
    Set<WorkspaceSkillId>? skillIds,
  }) => _delegate.checkUpdates(skillIds: skillIds);

  @override
  WorkspaceTask<WorkspaceMutationReceipt> update({
    Set<WorkspaceSkillId>? skillIds,
  }) {
    WorkspaceTask<WorkspaceMutationReceipt> start() =>
        _delegate.update(skillIds: skillIds);
    final selected =
        skillIds ??
        {
          for (final skill
              in _delegate.current?.skills ?? const <WorkspaceSkill>[])
            skill.id,
        };
    return _touchesGlobalActivations(selected)
        ? _gated(WorkspaceOperationKind.update, start)
        : start();
  }

  @override
  WorkspaceTask<WorkspaceMutationReceipt> registerProjectRoot({
    required String path,
    String? id,
  }) => _delegate.registerProjectRoot(path: path, id: id);

  @override
  WorkspaceTask<WorkspaceMutationReceipt> unregisterProjectRoot(String id) =>
      _delegate.unregisterProjectRoot(id);

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> reconfigureAgentCatalog(
    List<WorkspaceAgentDefinition> agents,
  ) {
    _coordinator.invalidate();
    return _delegate.reconfigureAgentCatalog(agents);
  }

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> setFavorite({
    required WorkspaceSkillId skillId,
    required bool isFavorite,
  }) => _delegate.setFavorite(skillId: skillId, isFavorite: isFavorite);

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> saveNote({
    required WorkspaceSkillId skillId,
    required String note,
  }) => _delegate.saveNote(skillId: skillId, note: note);

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deleteNote(WorkspaceSkillId skillId) =>
      _delegate.deleteNote(skillId);

  @override
  WorkspaceTask<WorkspacePersonalTag> createPersonalTag({
    required String name,
    String? color,
  }) => _delegate.createPersonalTag(name: name, color: color);

  @override
  WorkspaceTask<WorkspacePersonalTag> updatePersonalTag({
    required String tagId,
    required String name,
    String? color,
  }) => _delegate.updatePersonalTag(tagId: tagId, name: name, color: color);

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> deletePersonalTag(String tagId) =>
      _delegate.deletePersonalTag(tagId);

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> assignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => _delegate.assignPersonalTag(skillId: skillId, tagId: tagId);

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> unassignPersonalTag({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => _delegate.unassignPersonalTag(skillId: skillId, tagId: tagId);

  @override
  WorkspaceTask<SkillsWorkspaceSnapshot> abandonUpdateCandidate(
    WorkspaceSkillId skillId,
  ) => _delegate.abandonUpdateCandidate(skillId);

  @override
  Future<void> close() => _delegate.close();

  WorkspaceTask<T> _gated<T>(
    WorkspaceOperationKind kind,
    WorkspaceTask<T> Function() start,
  ) {
    final operationId = 'ownership-gate-${++_operationSequence}';
    final states = StreamController<WorkspaceOperationProgress>.broadcast();
    WorkspaceTask<T>? inner;
    StreamSubscription<WorkspaceOperationProgress>? subscription;
    var cancellationRequested = false;

    final completed = Future<WorkspaceCompletion<T>>(() async {
      try {
        final failure = await _coordinator.ensureReady(kind);
        if (failure != null) return WorkspaceFailed<T>(failure: failure);
        if (cancellationRequested) {
          return WorkspaceFailed<T>(
            failure: WorkspaceFailure(
              code: WorkspaceErrorCode.operationCancelled,
              operation: kind,
            ),
          );
        }
        inner = start();
        subscription = inner!.states.listen(states.add);
        final completion = await inner!.completed;
        if (completion case WorkspaceFailed(:final failure)) {
          if (_mayReflectFilesystemDrift(failure)) _coordinator.invalidate();
        }
        return completion;
      } finally {
        await subscription?.cancel();
        await states.close();
      }
    });

    return WorkspaceTask<T>(
      current: WorkspaceOperationProgress(
        operationId: operationId,
        kind: kind,
        phase: WorkspaceOperationPhase.queued,
      ),
      states: states.stream,
      completed: completed,
      cancel: () async {
        cancellationRequested = true;
        await inner?.cancel();
      },
    );
  }

  WorkspaceTask<WorkspaceActivationAttempt> _tagTakeoverDraft(
    WorkspaceTask<WorkspaceActivationAttempt> task, {
    required bool requiresOwnershipGate,
  }) => WorkspaceTask<WorkspaceActivationAttempt>(
    current: task.current,
    states: task.states,
    completed: task.completed.then(
      (completion) => switch (completion) {
        WorkspaceCompleted(:final value, :final warnings) => WorkspaceCompleted(
          value: switch (value) {
            WorkspaceActivationTakeoverRequired(:final draft) =>
              WorkspaceActivationTakeoverRequired(
                _OwnershipTakeoverDraft(
                  delegate: draft,
                  requiresOwnershipGate: requiresOwnershipGate,
                ),
              ),
            WorkspaceActivationCompleted() => value,
          },
          warnings: warnings,
        ),
        WorkspaceFailed() => completion,
        WorkspaceCommittedPending() => completion,
      },
    ),
    cancel: task.cancel,
  );

  bool _touchesGlobalActivations(
    Set<WorkspaceSkillId> skillIds, {
    Set<String>? locations,
  }) {
    final snapshot = _delegate.current;
    if (snapshot == null) return true;
    for (final skillId in skillIds) {
      final skill = snapshot.findSkillById(skillId);
      if (skill == null) return true;
      for (final activation in skill.activations) {
        if (activation.scope == WorkspaceScope.global &&
            (locations == null || locations.contains(activation.location))) {
          return true;
        }
      }
    }
    return false;
  }
}

final class _OwnershipTakeoverDraft
    implements WorkspaceActivationTakeoverDraft {
  const _OwnershipTakeoverDraft({
    required this.delegate,
    required this.requiresOwnershipGate,
  });

  final WorkspaceActivationTakeoverDraft delegate;
  final bool requiresOwnershipGate;

  @override
  int get expectedRevision => delegate.expectedRevision;

  @override
  List<WorkspaceOccupiedActivationTarget> get targets => delegate.targets;
}

bool _mayReflectFilesystemDrift(WorkspaceFailure failure) =>
    failure.code == WorkspaceErrorCode.ioFailure ||
    failure.context['reason'] == 'applyFailed' ||
    failure.context['reason'] == 'filesystemOperationFailed';
