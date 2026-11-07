import 'package:path/path.dart' as path;

import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../operations/workspace_business_changes.dart';
import '../ports/activation_mutation_ports.dart';
import '../ports/agent_activation_ports.dart';
import 'activation_models.dart';
import 'activation_mutation_models.dart';

/// Plans Activation metadata and materialization changes from one Snapshot.
///
/// The planner performs no filesystem or SQLite I/O. Occupancy inspection and
/// persisted Activation reads are frozen inputs, which keeps all-or-nothing
/// validation ahead of Operation Journal creation.
final class ActivationMutationPlanner {
  const ActivationMutationPlanner({
    required ActivationLocationIdentityPort locationIdentity,
    required ActivationIdentityPort identities,
    required DateTime Function() clock,
  }) : _locationIdentity = locationIdentity,
       _identities = identities,
       _clock = clock;

  final ActivationLocationIdentityPort _locationIdentity;
  final ActivationIdentityPort _identities;
  final DateTime Function() _clock;

  ActivationMutationPlanningResult activate({
    required RepositorySnapshot snapshot,
    required Set<ManagedSkillId> managedSkillIds,
    required ResolvedActivationTargets resolvedTargets,
    required List<InspectedActivationOccupancy> occupancies,
    required List<PersistedActivation> persistedActivations,
  }) {
    final skillsResult = _resolveSkills(snapshot, managedSkillIds);
    final skills = skillsResult.valueOrNull;
    if (skills == null) return skillsResult.failureOrNull!;

    final indexedResult = _indexPersisted(
      skills: skills,
      persistedActivations: persistedActivations,
    );
    final persistedBySkill = indexedResult.valueOrNull;
    if (persistedBySkill == null) return indexedResult.failureOrNull!;

    final occupancyResult = _indexOccupancies(
      skills: skills,
      resolvedTargets: resolvedTargets,
      occupancies: occupancies,
    );
    final occupancyByTarget = occupancyResult.valueOrNull;
    if (occupancyByTarget == null) return occupancyResult.failureOrNull!;

    final mutations = <WorkspaceBusinessMutation>[];
    final pathMutations = <ActivationPathMutation>[];
    final nowMicros = _clock().toUtc().microsecondsSinceEpoch;
    for (final skill in skills) {
      final byLocation = persistedBySkill[skill.id]!;
      for (final target in resolvedTargets.targets) {
        final locationKey = _locationIdentity.key(target.location);
        final existing = byLocation[locationKey];
        if (existing != null && !_sameProvenance(existing.activation, target)) {
          return ActivationMutationPlanningFailure(
            code: ActivationMutationFailureCode.activationUnsupported,
            context: <String, Object?>{
              'managedSkillId': skill.id.value,
              'location': target.location,
              'reason': 'conflictingLocationProvenance',
            },
            warnings: resolvedTargets.warnings,
          );
        }

        final mergedAgentIds = <String>{
          ...?existing?.activation.agentIds,
          ...target.agentIds,
        }.toList()..sort();
        final intended = SkillActivation(
          location: target.location,
          scope: target.scope,
          mode: target.mode,
          agentIds: mergedAgentIds,
          projectRootId: target.projectRootId,
          projectRootPath: target.projectRootPath,
        );
        if (existing != null && sameActivation(existing.activation, intended)) {
          continue;
        }

        final targetPath = path.join(target.location, skill.slotKey);
        final occupancy = occupancyByTarget[(skill.id, targetPath)];
        final preserveManagedLink =
            existing == null &&
            occupancy?.kind ==
                InspectedActivationOccupancyKind.skillSymbolicLink &&
            occupancy!.pointsToRepositoryCopy &&
            target.mode == ActivationMode.symbolicLink;
        final requiresMaterialization =
            existing == null || existing.activation.mode != target.mode;
        if (requiresMaterialization && !preserveManagedLink) {
          final expectation = existing != null
              ? const ActivationTargetExpectation.managed()
              : occupancy == null
              ? const ActivationTargetExpectation.vacant()
              : ActivationTargetExpectation.occupied(occupancy.fingerprint);
          pathMutations.add(
            MaterializeActivationPath(
              managedSkillId: skill.id,
              slotKey: skill.slotKey,
              targetPath: targetPath,
              target: target,
              expectation: expectation,
            ),
          );
        }
        mutations.add(
          PutActivation(
            activationId:
                existing?.activationId ?? _identities.allocateActivationId(),
            managedSkillId: skill.id,
            canonicalPath: target.location,
            scope: _workspaceScope(target.scope),
            mode: _workspaceMode(target.mode),
            projectRootId: target.projectRootId,
            projectRootPath: target.projectRootPath,
            agentIds: mergedAgentIds,
            createdAtMicros: existing?.createdAtMicros ?? nowMicros,
          ),
        );
      }
    }

    return ActivationMutationPlanningSuccess(
      ActivationMutationPlan(
        businessChanges: WorkspaceBusinessChangeSet(mutations: mutations),
        pathMutations: pathMutations,
        affectedSkillIds: managedSkillIds,
        warnings: resolvedTargets.warnings,
      ),
    );
  }

  ActivationMutationPlanningResult deactivate({
    required RepositorySnapshot snapshot,
    required Set<ManagedSkillId> managedSkillIds,
    required Set<String>? locations,
    required List<PersistedActivation> persistedActivations,
  }) {
    final skillsResult = _resolveSkills(snapshot, managedSkillIds);
    final skills = skillsResult.valueOrNull;
    if (skills == null) return skillsResult.failureOrNull!;
    final indexedResult = _indexPersisted(
      skills: skills,
      persistedActivations: persistedActivations,
    );
    final persistedBySkill = indexedResult.valueOrNull;
    if (persistedBySkill == null) return indexedResult.failureOrNull!;

    final selectedLocations = locations?.map(_locationIdentity.key).toSet();
    final mutations = <WorkspaceBusinessMutation>[];
    final pathMutations = <ActivationPathMutation>[];
    for (final skill in skills) {
      final persisted = persistedBySkill[skill.id]!.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      for (final entry in persisted) {
        if (selectedLocations != null &&
            !selectedLocations.contains(entry.key)) {
          continue;
        }
        mutations.add(DeleteActivation(entry.value.activationId));
        pathMutations.add(
          DeleteActivationPath(
            managedSkillId: skill.id,
            slotKey: skill.slotKey,
            targetPath: path.join(
              entry.value.activation.location,
              skill.slotKey,
            ),
          ),
        );
      }
    }

    return ActivationMutationPlanningSuccess(
      ActivationMutationPlan(
        businessChanges: WorkspaceBusinessChangeSet(mutations: mutations),
        pathMutations: pathMutations,
        affectedSkillIds: managedSkillIds,
      ),
    );
  }

  _PlanningValue<List<ManagedSkill>> _resolveSkills(
    RepositorySnapshot snapshot,
    Set<ManagedSkillId> managedSkillIds,
  ) {
    final sortedIds = managedSkillIds.toList()
      ..sort((left, right) => left.value.compareTo(right.value));
    final skills = <ManagedSkill>[];
    for (final id in sortedIds) {
      final skill = snapshot.findSkill(id);
      if (skill == null) {
        return _PlanningValue.failure(
          ActivationMutationPlanningFailure(
            code: ActivationMutationFailureCode.skillNotFound,
            context: <String, Object?>{'managedSkillId': id.value},
          ),
        );
      }
      skills.add(skill);
    }
    return _PlanningValue.success(skills);
  }

  _PlanningValue<Map<ManagedSkillId, Map<String, PersistedActivation>>>
  _indexPersisted({
    required List<ManagedSkill> skills,
    required List<PersistedActivation> persistedActivations,
  }) {
    final requestedIds = skills.map((skill) => skill.id).toSet();
    final indexed = <ManagedSkillId, Map<String, PersistedActivation>>{
      for (final skill in skills) skill.id: <String, PersistedActivation>{},
    };
    for (final persisted in persistedActivations) {
      if (!requestedIds.contains(persisted.managedSkillId)) {
        return _PlanningValue.failure(
          ActivationMutationPlanningFailure(
            code: ActivationMutationFailureCode.stateInconsistent,
            context: const <String, Object?>{
              'reason': 'unexpectedPersistedActivation',
            },
          ),
        );
      }
      final key = _locationIdentity.key(persisted.activation.location);
      if (indexed[persisted.managedSkillId]!.containsKey(key)) {
        return _PlanningValue.failure(
          ActivationMutationPlanningFailure(
            code: ActivationMutationFailureCode.stateInconsistent,
            context: <String, Object?>{
              'managedSkillId': persisted.managedSkillId.value,
              'reason': 'duplicateActivationLocation',
            },
          ),
        );
      }
      indexed[persisted.managedSkillId]![key] = persisted;
    }
    for (final skill in skills) {
      final rows = indexed[skill.id]!;
      if (rows.length != skill.activations.length) {
        return _PlanningValue.failure(
          ActivationMutationPlanningFailure(
            code: ActivationMutationFailureCode.stateInconsistent,
            context: <String, Object?>{
              'managedSkillId': skill.id.value,
              'reason': 'activationProjectionMismatch',
            },
          ),
        );
      }
      for (final activation in skill.activations) {
        final persisted = rows[_locationIdentity.key(activation.location)];
        if (persisted == null ||
            !sameActivation(persisted.activation, activation)) {
          return _PlanningValue.failure(
            ActivationMutationPlanningFailure(
              code: ActivationMutationFailureCode.stateInconsistent,
              context: <String, Object?>{
                'managedSkillId': skill.id.value,
                'location': activation.location,
                'reason': 'activationProjectionMismatch',
              },
            ),
          );
        }
      }
    }
    return _PlanningValue.success(indexed);
  }

  _PlanningValue<Map<(ManagedSkillId, String), InspectedActivationOccupancy>>
  _indexOccupancies({
    required List<ManagedSkill> skills,
    required ResolvedActivationTargets resolvedTargets,
    required List<InspectedActivationOccupancy> occupancies,
  }) {
    final skillIds = skills.map((skill) => skill.id).toSet();
    final expectedPaths = <(ManagedSkillId, String)>{
      for (final skill in skills)
        for (final target in resolvedTargets.targets)
          (skill.id, path.join(target.location, skill.slotKey)),
    };
    final indexed = <(ManagedSkillId, String), InspectedActivationOccupancy>{};
    for (final occupancy in occupancies) {
      final key = (occupancy.managedSkillId, occupancy.targetPath);
      if (!skillIds.contains(occupancy.managedSkillId) ||
          !expectedPaths.contains(key) ||
          indexed.containsKey(key)) {
        return _PlanningValue.failure(
          ActivationMutationPlanningFailure(
            code: ActivationMutationFailureCode.stateInconsistent,
            context: const <String, Object?>{
              'reason': 'unexpectedActivationOccupancy',
            },
            warnings: resolvedTargets.warnings,
          ),
        );
      }
      if (!occupancy.replaceable) {
        return _PlanningValue.failure(
          ActivationMutationPlanningFailure(
            code: ActivationMutationFailureCode.activationUnavailable,
            context: <String, Object?>{
              'managedSkillId': occupancy.managedSkillId.value,
              'location': occupancy.target.location,
              'targetPath': occupancy.targetPath,
              'reason': 'targetNotSafelyReplaceable',
            },
            warnings: resolvedTargets.warnings,
          ),
        );
      }
      indexed[key] = occupancy;
    }
    return _PlanningValue.success(indexed);
  }
}

final class _PlanningValue<T> {
  const _PlanningValue.success(this.value) : failure = null;
  const _PlanningValue.failure(this.failure) : value = null;

  final T? value;
  final ActivationMutationPlanningFailure? failure;
  T? get valueOrNull => value;
  ActivationMutationPlanningFailure? get failureOrNull => failure;
}

bool _sameProvenance(
  SkillActivation existing,
  ResolvedActivationTarget requested,
) =>
    existing.scope == requested.scope &&
    existing.projectRootId == requested.projectRootId &&
    existing.projectRootPath == requested.projectRootPath;

WorkspaceActivationScope _workspaceScope(ActivationScope value) =>
    switch (value) {
      ActivationScope.global => WorkspaceActivationScope.global,
      ActivationScope.project => WorkspaceActivationScope.project,
    };

WorkspaceActivationMode _workspaceMode(ActivationMode value) => switch (value) {
  ActivationMode.copy => WorkspaceActivationMode.copy,
  ActivationMode.symbolicLink => WorkspaceActivationMode.symbolicLink,
};
