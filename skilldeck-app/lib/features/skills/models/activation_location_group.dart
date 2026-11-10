import 'skills_workspace.dart';
import 'installed_skill.dart';

/// The Universal Agent convention names a shared canonical directory rather
/// than one more installed Agent, so it is a pseudo Agent id everywhere.
const universalAgentId = 'universal';

typedef ActivationLocationKey = ({
  WorkspaceScope scope,
  String? projectRootId,
  String location,
});

ActivationLocationKey activationLocationKey(
  WorkspaceScope scope,
  String? projectRootId,
  String location,
) => (scope: scope, projectRootId: projectRootId, location: location);

/// A directory is the activation boundary, not an individual Agent.
final class ActivationLocationGroup {
  ActivationLocationGroup(
    Iterable<WorkspaceActivationTarget> targets, {
    Set<String>? memberIds,
  }) : targets = List.unmodifiable(
         targets.toList()..sort((a, b) => a.agentId.compareTo(b.agentId)),
       ),
       memberIds = memberIds == null ? null : Set.unmodifiable(memberIds);

  final List<WorkspaceActivationTarget> targets;

  /// App roster projection; null is a raw, unprojected catalog group.
  final Set<String>? memberIds;
  ActivationLocationGroup forMembers(Set<String> ids) =>
      ActivationLocationGroup(targets, memberIds: ids);
  bool get canActivate => requestAgentIds.isNotEmpty;
  WorkspaceActivationTarget get first => memberIds == null
      ? targets.first
      : targets.where((t) => memberIds!.contains(t.agentId)).firstOrNull ??
            targets.first;
  String get location => first.location;
  ActivationLocationKey get key =>
      activationLocationKey(first.scope, first.projectRootId, location);
  bool get shared => targets.any((t) => t.agentId == universalAgentId);
  bool get detected => targets.any((t) => t.detected);
  List<WorkspaceActivationTarget> get visibleAgents => targets
      .where(
        (t) =>
            t.agentId != universalAgentId &&
            (memberIds?.contains(t.agentId) ?? t.detected),
      )
      .toList(growable: false);
  String get names => targets
      .where(
        (t) =>
            t.agentId != universalAgentId &&
            (memberIds == null ||
                !canActivate ||
                memberIds!.contains(t.agentId)),
      )
      .map((t) => t.displayName)
      .toSet()
      .join(', ');

  /// Undetected locations are explicit opt-ins; one target resolves the path.
  Set<String> get requestAgentIds => memberIds != null
      ? {
          for (final t in targets)
            if (t.agentId != universalAgentId && memberIds!.contains(t.agentId))
              t.agentId,
        }
      : detected
      ? {
          for (final target in targets)
            if (target.detected) target.agentId,
        }
      : {first.agentId};
}

List<ActivationLocationGroup> groupActivationLocations(
  Iterable<WorkspaceActivationTarget> targets,
) {
  final grouped = <ActivationLocationKey, List<WorkspaceActivationTarget>>{};
  for (final target in targets) {
    if (target.location.isEmpty) continue;
    final key = activationLocationKey(
      target.scope,
      target.projectRootId,
      target.location,
    );
    grouped.putIfAbsent(key, () => []).add(target);
  }
  return grouped.values.map(ActivationLocationGroup.new).toList()..sort((a, b) {
    if (a.shared != b.shared) return a.shared ? -1 : 1;
    final byName = a.names.compareTo(b.names);
    return byName != 0 ? byName : a.location.compareTo(b.location);
  });
}

/// Scope is the reach axis: a Global Activation reaches every Agent, a Project
/// Activation reaches only that Project, and `inactive` is the bucket no Agent
/// can reach. Reach is why `inactive` belongs here and not beside Agents.
enum InstalledScopeFilter { global, project, inactive }

/// Direct Activation state for the selected Global and Project scopes.
/// Global and Project Activations are independent and may coexist.
final class SkillScopeState {
  const SkillScopeState({
    required this.hasGlobalActivation,
    required this.hasProjectActivation,
  });

  final bool hasGlobalActivation;
  final bool hasProjectActivation;

  bool get isInactive => !hasGlobalActivation && !hasProjectActivation;
}

SkillScopeState skillScopeState(InstalledSkill skill, {String? projectRootId}) {
  var hasGlobal = false;
  var hasProject = false;
  for (final activation in skill.activations) {
    if (activation.scope == WorkspaceScope.global) {
      hasGlobal = true;
    } else if (activation.scope == WorkspaceScope.project &&
        (projectRootId == null || activation.projectRootId == projectRootId)) {
      hasProject = true;
    }
  }
  return SkillScopeState(
    hasGlobalActivation: hasGlobal,
    hasProjectActivation: hasProject,
  );
}

/// Whether a Project activation group overlaps an Agent already reached by a
/// Global activation of the same Skill.
bool hasGlobalActivationOverlap({
  required InstalledSkill skill,
  required ActivationLocationGroup projectGroup,
}) {
  final projectAgentIds = projectGroup.targets.map((target) => target.agentId);
  final projectAgents = projectAgentIds.toSet();
  for (final activation in skill.activations) {
    if (activation.scope != WorkspaceScope.global) continue;
    if (activation.agentIds.any(projectAgents.contains)) return true;
    if (projectGroup.shared && activation.agentIds.contains(universalAgentId)) {
      return true;
    }
  }
  return false;
}

enum InstalledLocationFilterKind { all, location }

final class InstalledLocationFilter {
  const InstalledLocationFilter.all()
    : kind = InstalledLocationFilterKind.all,
      key = null;
  const InstalledLocationFilter.location(this.key)
    : kind = InstalledLocationFilterKind.location;

  final InstalledLocationFilterKind kind;
  final ActivationLocationKey? key;
}

Iterable<SkillActivationLocation> installedActivationsInScope(
  InstalledSkill skill, {
  required InstalledScopeFilter scope,
  String? projectRootId,
}) {
  if (scope == InstalledScopeFilter.inactive) {
    return const <SkillActivationLocation>[];
  }
  final workspaceScope = scope == InstalledScopeFilter.global
      ? WorkspaceScope.global
      : WorkspaceScope.project;
  final rootId = scope == InstalledScopeFilter.global ? null : projectRootId;
  return skill.activations.where(
    (a) => a.scope == workspaceScope && a.projectRootId == rootId,
  );
}

/// What a Skill occupies inside one Scope, against what the Scope offers.
///
/// Both sides count Activation Locations, not Agents. A directory is the
/// activation boundary: dozens of built-in conventions share
/// `~/.agents/skills` and `deactivate` takes locations, so a location is also
/// exactly one switch. Counting Agents instead would make the fraction read as
/// if each of them could be turned on separately.
typedef ActivationReach = ({int enabled, int total});

/// The offered groups a Skill occupies inside one Scope, in [groups] order.
List<ActivationLocationGroup> activeGroupsInScope(
  InstalledSkill skill, {
  required Iterable<ActivationLocationGroup> groups,
  required InstalledScopeFilter scope,
  String? projectRootId,
}) {
  final occupied = _occupiedLocations(
    skill,
    scope: scope,
    projectRootId: projectRootId,
  );
  return [
    for (final group in groups)
      if (occupied.contains(group.key)) group,
  ];
}

Set<ActivationLocationKey> _occupiedLocations(
  InstalledSkill skill, {
  required InstalledScopeFilter scope,
  String? projectRootId,
}) => {
  for (final activation in installedActivationsInScope(
    skill,
    scope: scope,
    projectRootId: projectRootId,
  ))
    activationLocationKey(
      activation.scope,
      activation.projectRootId,
      activation.location,
    ),
};

ActivationReach activationReachInScope(
  InstalledSkill skill, {
  required Iterable<ActivationLocationGroup> groups,
  required InstalledScopeFilter scope,
  String? projectRootId,
}) {
  if (scope == InstalledScopeFilter.inactive) {
    return (enabled: 0, total: 0);
  }
  final occupied = _occupiedLocations(
    skill,
    scope: scope,
    projectRootId: projectRootId,
  );
  final offered = <ActivationLocationKey>{
    for (final group in groups) group.key,
  };
  return (
    enabled: occupied.intersection(offered).length,
    total: offered.length,
  );
}

bool matchesInstalledSelection(
  InstalledSkill skill, {
  required InstalledScopeFilter scope,
  String? projectRootId,
  required InstalledLocationFilter filter,
}) {
  if (scope == InstalledScopeFilter.inactive) {
    // Inactive is device-wide: a Project Root selection must not change it.
    return skill.activations.isEmpty;
  }
  final activations = installedActivationsInScope(
    skill,
    scope: scope,
    projectRootId: projectRootId,
  );
  if (filter.kind == InstalledLocationFilterKind.all) {
    return activations.isNotEmpty;
  }

  final selectedKey = filter.key;
  if (selectedKey == null) return false;

  // A Global Agent is a management target: include other Agents' Global
  // Skills and fully inactive Skills. Project-only Skills remain excluded.
  // The row switch, not list membership, reflects this target's activation.
  if (scope == InstalledScopeFilter.global) {
    return activations.isNotEmpty || skill.activations.isEmpty;
  }

  // Project management remains bounded by the selected Scope and location,
  // plus fully inactive Skills that can be enabled there.
  if (activations.isEmpty && skill.activations.isNotEmpty) return false;

  // Activation is location-centric, so the selected target is matched by its
  // location key rather than by an individual Agent id.
  return skill.activations.isEmpty ||
      activations.any(
        (activation) =>
            activationLocationKey(
              activation.scope,
              activation.projectRootId,
              activation.location,
            ) ==
            selectedKey,
      );
}
