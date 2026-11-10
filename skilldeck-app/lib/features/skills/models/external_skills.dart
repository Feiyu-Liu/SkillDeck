import 'package:skills_manager/features/skills/models/skills_workspace.dart';

final class ExternalSkillCandidate {
  ExternalSkillCandidate({
    required this.slotKey,
    required this.declaredName,
    required this.description,
    required this.contentHash,
    required List<String> locations,
    required List<String> agentIds,
    List<String> destinationLocations = const <String>[],
  }) : locations = List.unmodifiable(locations),
       agentIds = List.unmodifiable(agentIds),
       destinationLocations = List.unmodifiable(destinationLocations);

  final String slotKey;
  final String declaredName;
  final String description;
  final String contentHash;
  final List<String> locations;
  final List<String> agentIds;
  final List<String> destinationLocations;
}

final class ExternalSkillConflict {
  ExternalSkillConflict({
    required this.slotKey,
    required Map<String, String> contentHashByLocation,
    List<String> destinationLocations = const <String>[],
    Map<String, List<String>> agentIdsByLocation =
        const <String, List<String>>{},
  }) : contentHashByLocation = Map.unmodifiable(contentHashByLocation),
       destinationLocations = List.unmodifiable(destinationLocations),
       agentIdsByLocation = Map.unmodifiable({
         for (final entry in agentIdsByLocation.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       });

  final String slotKey;
  final Map<String, String> contentHashByLocation;
  final List<String> destinationLocations;

  /// The Agents whose folder holds each copy; empty when unknown.
  final Map<String, List<String>> agentIdsByLocation;

  List<String> get locations => List.unmodifiable(contentHashByLocation.keys);
}

final class ExternalSkillsDiscovery {
  ExternalSkillsDiscovery({
    required List<ExternalSkillCandidate> candidates,
    required List<ExternalSkillConflict> conflicts,
  }) : candidates = List.unmodifiable(candidates),
       conflicts = List.unmodifiable(conflicts);

  factory ExternalSkillsDiscovery.empty() =>
      ExternalSkillsDiscovery(candidates: const [], conflicts: const []);

  final List<ExternalSkillCandidate> candidates;
  final List<ExternalSkillConflict> conflicts;

  bool get isEmpty => candidates.isEmpty && conflicts.isEmpty;

  int get uniqueSlotCount => {
    for (final candidate in candidates) candidate.slotKey,
    for (final conflict in conflicts) conflict.slotKey,
  }.length;
}

final class ExternalSkillAdoptionRequest {
  ExternalSkillAdoptionRequest({
    required this.slotKey,
    required this.authoritativeLocation,
    required Map<String, String> reviewedContentHashByLocation,
    this.activationMethod = WorkspaceActivationMethod.automatic,
  }) : reviewedContentHashByLocation = Map.unmodifiable(
         Map<String, String>.from(reviewedContentHashByLocation),
       );

  final String slotKey;
  final String authoritativeLocation;
  final Map<String, String> reviewedContentHashByLocation;
  final WorkspaceActivationMethod activationMethod;
}
