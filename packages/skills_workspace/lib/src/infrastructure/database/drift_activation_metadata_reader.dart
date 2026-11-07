import '../../application/activation/activation_mutation_models.dart';
import '../../application/ports/activation_mutation_ports.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import 'workspace_database.dart';

/// Maps Activation control-plane rows into application-owned immutable data.
final class DriftActivationMetadataReader
    implements ActivationMetadataReaderPort {
  const DriftActivationMetadataReader({required WorkspaceDatabase database})
    : _database = database;

  final WorkspaceDatabase _database;

  @override
  Future<List<PersistedActivation>> readForSkills(
    Set<ManagedSkillId> managedSkillIds,
  ) async {
    if (managedSkillIds.isEmpty) return const <PersistedActivation>[];
    final ids = managedSkillIds.map((id) => id.value).toList(growable: false);
    return _database.transaction(() async {
      final locations = await (_database.select(
        _database.activationLocations,
      )..where((row) => row.managedSkillId.isIn(ids))).get();
      final locationIds = locations
          .map((row) => row.id)
          .toList(growable: false);
      final agents = locationIds.isEmpty
          ? const <ActivationAgent>[]
          : await (_database.select(_database.activationAgents)
                  ..where((row) => row.activationLocationId.isIn(locationIds)))
                .get();
      final agentsByLocation = <String, List<String>>{};
      for (final agent in agents) {
        agentsByLocation
            .putIfAbsent(agent.activationLocationId, () => <String>[])
            .add(agent.agentId);
      }
      final result = <PersistedActivation>[];
      for (final location in locations) {
        final agentIds = agentsByLocation[location.id] ?? <String>[];
        agentIds.sort();
        result.add(
          PersistedActivation(
            activationId: location.id,
            managedSkillId: ManagedSkillId(location.managedSkillId),
            activation: SkillActivation(
              location: location.canonicalPath,
              scope: _scope(location.scope),
              mode: _mode(location.mode),
              agentIds: agentIds,
              projectRootId: location.projectRootId,
              projectRootPath: location.projectRootPath,
            ),
            createdAtMicros: location.createdAtMicros,
          ),
        );
      }
      result.sort((left, right) {
        final skill = left.managedSkillId.value.compareTo(
          right.managedSkillId.value,
        );
        return skill != 0
            ? skill
            : left.activation.location.compareTo(right.activation.location);
      });
      return List<PersistedActivation>.unmodifiable(result);
    });
  }
}

ActivationScope _scope(String value) => switch (value) {
  'global' => ActivationScope.global,
  'project' => ActivationScope.project,
  _ => throw StateError('Unknown Activation scope.'),
};

ActivationMode _mode(String value) => switch (value) {
  'copy' => ActivationMode.copy,
  'symbolicLink' => ActivationMode.symbolicLink,
  _ => throw StateError('Unknown Activation mode.'),
};
