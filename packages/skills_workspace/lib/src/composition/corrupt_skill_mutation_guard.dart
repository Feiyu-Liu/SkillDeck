import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'skill_integrity_coordinator.dart';

/// Applies the per-Skill corruption isolation policy at command admission.
///
/// Read-only operations and Workspace-wide mutations remain available. A
/// mutation that would change an isolated Skill is rejected before its handler
/// can plan, journal, or write. Explicit Source Replacement and Removal are the
/// two destructive escape hatches defined by ADR-0084.
List<SkillsCommandHandler> guardCorruptSkillMutations({
  required List<SkillsCommandHandler> handlers,
  required WorkspaceSnapshotPublisher snapshots,
  SkillIntegrityCoordinator? integrity,
}) => <SkillsCommandHandler>[
  for (final handler in handlers)
    _CorruptSkillMutationGuard(
      delegate: handler,
      snapshots: snapshots,
      integrity: integrity,
    ),
];

final class _CorruptSkillMutationGuard implements SkillsCommandHandler {
  const _CorruptSkillMutationGuard({
    required SkillsCommandHandler delegate,
    required WorkspaceSnapshotPublisher snapshots,
    SkillIntegrityCoordinator? integrity,
  }) : _delegate = delegate,
       _snapshots = snapshots,
       _integrity = integrity;

  final SkillsCommandHandler _delegate;
  final WorkspaceSnapshotPublisher _snapshots;
  final SkillIntegrityCoordinator? _integrity;

  @override
  WorkspaceOperationKind get kind => _delegate.kind;

  @override
  Future<SkillsResult<Object?>> execute(
    Object request,
    SkillsCommandContext context,
  ) async {
    final snapshot = _snapshots.current;
    final affected = _affectedSkillIds(kind, request, snapshot);
    final knownSkillIds = snapshot.managedSkills
        .map((skill) => skill.id)
        .toSet();
    final existingAffected = affected.where(knownSkillIds.contains).toSet();
    final integrity = _integrity;
    if (existingAffected.isNotEmpty &&
        _requiresIntegrity(kind) &&
        integrity != null) {
      final ids = existingAffected.toList(growable: false)
        ..sort((left, right) => left.value.compareTo(right.value));
      final results = await Future.wait([
        for (final id in ids) integrity.validate(id),
      ]);
      final blocked = results.where(
        (result) => switch (result.status) {
          SkillIntegrityStatus.driftPending ||
          SkillIntegrityStatus.repairFailed ||
          SkillIntegrityStatus.revisionStoreCorrupt => true,
          _ => false,
        },
      );
      if (blocked.isNotEmpty) {
        final drift = blocked.any(
          (result) => result.status == SkillIntegrityStatus.driftPending,
        );
        return SkillsFailure<Object?>(
          code: SkillsErrorCode.revisionStoreCorrupt,
          context: <String, Object?>{
            'reason': drift ? 'driftPending' : 'integrityUnavailable',
          },
        );
      }
    }
    if (existingAffected.isNotEmpty && _requiresIntegrity(kind)) {
      final blocked =
          snapshot.integrity.skills
              .where((state) => state.mutationBlocked)
              .map((state) => state.managedSkillId)
              .where(existingAffected.contains)
              .toList(growable: false)
            ..sort((left, right) => left.value.compareTo(right.value));
      if (blocked.isNotEmpty) {
        return Future<SkillsResult<Object?>>.value(
          SkillsFailure<Object?>(
            code: SkillsErrorCode.revisionStoreCorrupt,
            context: <String, Object?>{
              'managedSkillIds': [for (final id in blocked) id.value],
            },
          ),
        );
      }
    }
    return _delegate.execute(request, context);
  }
}

bool _requiresIntegrity(WorkspaceOperationKind kind) => switch (kind) {
  WorkspaceOperationKind.update ||
  WorkspaceOperationKind.replaceSource ||
  WorkspaceOperationKind.activate ||
  WorkspaceOperationKind.confirmActivationTakeover ||
  WorkspaceOperationKind.deactivate ||
  WorkspaceOperationKind.remove ||
  WorkspaceOperationKind.ensureDraft ||
  WorkspaceOperationKind.discardDraft ||
  WorkspaceOperationKind.publishDraft ||
  WorkspaceOperationKind.resolveUpdateConflict ||
  WorkspaceOperationKind.publishUpdateCandidate ||
  WorkspaceOperationKind.abandonUpdateCandidate ||
  WorkspaceOperationKind.restorePublish => true,
  _ => false,
};

Set<ManagedSkillId> _affectedSkillIds(
  WorkspaceOperationKind kind,
  Object request,
  RepositorySnapshot snapshot,
) => switch (kind) {
  WorkspaceOperationKind.open ||
  WorkspaceOperationKind.refresh ||
  WorkspaceOperationKind.validateWorkspace ||
  WorkspaceOperationKind.resumeFinalizationRecovery ||
  WorkspaceOperationKind.close ||
  WorkspaceOperationKind.inspectSource ||
  WorkspaceOperationKind.listEffectiveFiles ||
  WorkspaceOperationKind.readEffectiveFile ||
  WorkspaceOperationKind.install ||
  WorkspaceOperationKind.confirmInstallTakeover ||
  WorkspaceOperationKind.adopt ||
  WorkspaceOperationKind.checkUpdates ||
  // ADR-0084 explicitly keeps these destructive recovery paths available.
  WorkspaceOperationKind.replaceSource ||
  WorkspaceOperationKind.inspectActivationTargets ||
  WorkspaceOperationKind.inspectAgents ||
  WorkspaceOperationKind.inspectAgentRootOwnership ||
  WorkspaceOperationKind.discoverExternalSkills ||
  WorkspaceOperationKind.registerProjectRoot ||
  WorkspaceOperationKind.remove ||
  WorkspaceOperationKind.reconfigureAgentCatalog ||
  WorkspaceOperationKind.createPersonalTag ||
  WorkspaceOperationKind.updatePersonalTag ||
  WorkspaceOperationKind.inspectDraft ||
  WorkspaceOperationKind.inspectUpdateCandidate ||
  WorkspaceOperationKind.inspectOperationHistory ||
  WorkspaceOperationKind.inspectPublishedHistory ||
  WorkspaceOperationKind.inspectDiff ||
  WorkspaceOperationKind.inspectSkillDrift ||
  WorkspaceOperationKind.exportSkillDriftArtifact ||
  WorkspaceOperationKind.resolveSkillDrift => const <ManagedSkillId>{},

  WorkspaceOperationKind.update => (request as UpdateRequest).managedSkillIds,
  WorkspaceOperationKind.activate =>
    (request as ActivateRequest).managedSkillIds,
  WorkspaceOperationKind.confirmActivationTakeover => <ManagedSkillId>{
    for (final target
        in (request as ConfirmActivationTakeoverRequest).draft.targets)
      target.managedSkillId,
  },
  WorkspaceOperationKind.deactivate =>
    (request as DeactivateRequest).managedSkillIds,
  WorkspaceOperationKind.unregisterProjectRoot => <ManagedSkillId>{
    for (final skill in snapshot.managedSkills)
      if (skill.activations.any(
        (activation) =>
            activation.projectRootId ==
            (request as UnregisterProjectRootRequest).id,
      ))
        skill.id,
  },
  WorkspaceOperationKind.setFavorite => <ManagedSkillId>{
    (request as SetFavoriteRequest).managedSkillId,
  },
  WorkspaceOperationKind.saveNote => <ManagedSkillId>{
    (request as SaveNoteRequest).managedSkillId,
  },
  WorkspaceOperationKind.deleteNote => <ManagedSkillId>{
    (request as DeleteNoteRequest).managedSkillId,
  },
  WorkspaceOperationKind.deletePersonalTag => <ManagedSkillId>{
    for (final skill in snapshot.managedSkills)
      if (skill.personalTagIds.contains(
        (request as DeletePersonalTagRequest).tagId,
      ))
        skill.id,
  },
  WorkspaceOperationKind.assignPersonalTag => <ManagedSkillId>{
    (request as AssignPersonalTagRequest).managedSkillId,
  },
  WorkspaceOperationKind.unassignPersonalTag => <ManagedSkillId>{
    (request as UnassignPersonalTagRequest).managedSkillId,
  },
  WorkspaceOperationKind.ensureDraft => <ManagedSkillId>{
    (request as EnsureDraftRequest).managedSkillId,
  },
  WorkspaceOperationKind.discardDraft => <ManagedSkillId>{
    (request as DiscardDraftRequest).managedSkillId,
  },
  WorkspaceOperationKind.publishDraft => <ManagedSkillId>{
    (request as PublishDraftRequest).managedSkillId,
  },
  WorkspaceOperationKind.resolveUpdateConflict => <ManagedSkillId>{
    (request as ResolveUpdateConflictRequest).managedSkillId,
  },
  WorkspaceOperationKind.publishUpdateCandidate => <ManagedSkillId>{
    (request as PublishUpdateCandidateRequest).managedSkillId,
  },
  WorkspaceOperationKind.abandonUpdateCandidate => <ManagedSkillId>{
    (request as AbandonUpdateCandidateRequest).managedSkillId,
  },
  WorkspaceOperationKind.restorePublish => <ManagedSkillId>{
    (request as RestorePublishRequest).managedSkillId,
  },
};
