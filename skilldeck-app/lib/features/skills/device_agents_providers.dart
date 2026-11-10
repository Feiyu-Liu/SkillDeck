import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/presentation/view_models/app_settings_view_model.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';

import 'activation_location_providers.dart';
import 'models/activation_location_group.dart';
import 'models/skills_workspace.dart';
import 'skills_providers.dart';
import 'workspace_snapshot_providers.dart';

final deviceAgentCatalogProvider = FutureProvider<List<WorkspaceAgentInfo>>((
  ref,
) async {
  ref.watch(activationCatalogRevisionProvider);
  await ref.watch(
    workspaceSnapshotProvider.selectAsync(
      (s) => s.projectRoots.map((r) => '${r.id}\u0000${r.path}').join('\u0001'),
    ),
  );
  final result = await ref
      .watch(skillsWorkspaceRepositoryProvider)
      .inspectAgents()
      .completed;
  return switch (result) {
    WorkspaceCompleted(:final value) => value,
    WorkspaceFailed(:final failure) => throw failure,
    _ => throw StateError('Agent inspection did not complete.'),
  };
});

/// One device-wide preference projection; detection remains factual metadata.
Set<String> deviceAgentMemberIds(
  List<WorkspaceAgentInfo> agents,
  AppSettings settings,
) => {
  for (final agent in agents)
    if (!agent.isBuiltIn ||
        (settings.builtInAgentVisibilityOverrides[agent.id] ?? agent.detected))
      agent.id,
};

final deviceAgentMembersProvider = Provider<AsyncValue<Set<String>>>((ref) {
  final settings = ref.watch(appSettingsViewModelProvider);
  if (settings.status == AppSettingsStatus.loading) return const AsyncLoading();
  if (settings.errorCode == 'settings_load_failed') {
    return AsyncError(
      StateError('Agent settings could not be read.'),
      StackTrace.current,
    );
  }
  return ref
      .watch(deviceAgentCatalogProvider)
      .whenData((agents) => deviceAgentMemberIds(agents, settings.settings));
});

/// Preserve original groups (including Universal identity), then project membership.
List<ActivationLocationGroup> projectDeviceAgentGroups(
  Iterable<WorkspaceActivationTarget> targets,
  Set<String> memberIds,
) => [
  for (final group in groupActivationLocations(targets))
    group.forMembers(memberIds),
];

/// Only roster members are manageable; persisted Activations do not add members.
List<ActivationLocationGroup> deviceActivationGroups(
  Iterable<WorkspaceActivationTarget> targets,
  Set<String> memberIds,
) {
  return projectDeviceAgentGroups(
    targets,
    memberIds,
  ).where((g) => g.canActivate).toList()..sort((a, b) {
    if (a.shared != b.shared) return a.shared ? -1 : 1;
    return a.location.compareTo(b.location);
  });
}
