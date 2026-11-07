import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';

/// Every Activation target the selected Scope knows about, detected or not.
/// This is what tells the page which Agents are actually installed here, so it
/// backs both the Agent filter and the per-Skill Agent count.
final installedScopeActivationTargetsProvider =
    Provider<List<WorkspaceActivationTarget>>((ref) {
      final scopeFilter = ref.watch(installedScopeFilterProvider);
      if (scopeFilter == InstalledScopeFilter.inactive) {
        return const <WorkspaceActivationTarget>[];
      }
      final scope = scopeFilter == InstalledScopeFilter.global
          ? WorkspaceScope.global
          : WorkspaceScope.project;
      final projectRootId = scope == WorkspaceScope.global
          ? null
          : ref.watch(installedProjectRootFilterProvider);
      final inspection = ref.watch(
        activationTargetsProvider((scope: scope, projectRootId: projectRootId)),
      );
      return switch (inspection.value) {
        WorkspaceCompleted<List<WorkspaceActivationTarget>>(:final value) =>
          value,
        _ => const <WorkspaceActivationTarget>[],
      };
    });

/// The Agent groups the Installed page can filter by within the selected
/// Scope: only groups with a current roster member, including those with no
/// enabled Skills yet. Historical Activations never extend the roster.
final installedAgentGroupsProvider = Provider<List<ActivationLocationGroup>>((
  ref,
) {
  final scopeFilter = ref.watch(installedScopeFilterProvider);
  if (scopeFilter == InstalledScopeFilter.inactive) {
    return const <ActivationLocationGroup>[];
  }
  final known = ref.watch(installedScopeActivationTargetsProvider);
  final members =
      ref.watch(deviceAgentMembersProvider).value ?? const <String>{};
  return deviceActivationGroups(known, members);
});

/// The group the Agent filter points at, or null while All Agents is selected.
final selectedInstalledAgentGroupProvider = Provider<ActivationLocationGroup?>((
  ref,
) {
  final filter = ref.watch(installedLocationFilterProvider);
  if (filter.kind != InstalledLocationFilterKind.location) return null;
  for (final group in ref.watch(installedAgentGroupsProvider)) {
    if (group.key == filter.key) return group;
  }
  return null;
});
