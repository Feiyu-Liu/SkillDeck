import 'package:skills_manager/features/settings/data/app_settings_store.dart';
import 'package:skills_manager/features/settings/data/skills_manager_runtime.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

/// Coordinates the durable App-settings authority with the live Agent catalog.
///
/// SharedPreferences is written first so a process exit always restarts from
/// the intended catalog. If the live Workspace rejects the catalog, the prior
/// durable snapshot is restored before the failure escapes to presentation.
final class AppSettingsCoordinator {
  const AppSettingsCoordinator({
    required this.store,
    required this.runtime,
    this.onCommittedPending = _ignoreCommittedPending,
    this.onCatalogReconfigured = _ignoreCatalogReconfigured,
  });

  final AppSettingsStore store;
  final AppSettingsRuntime runtime;
  final void Function(WorkspaceCommittedPending<SkillsWorkspaceSnapshot>)
  onCommittedPending;
  final void Function() onCatalogReconfigured;

  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> save(
    AppSettings next,
  ) async {
    next.validate();
    final previous = await store.captureSnapshot();
    await store.write(next);
    final WorkspaceCompletion<SkillsWorkspaceSnapshot> completion;
    try {
      completion = await runtime.reconfigureAgentCatalog(next);
    } on Object {
      await store.restore(previous);
      rethrow;
    }
    switch (completion) {
      case WorkspaceCompleted():
        onCatalogReconfigured();
        return completion;
      case WorkspaceCommittedPending():
        // The new preferences are durable authority after the business commit
        // point. Keep them even if a later presentation-layer handoff fails.
        onCommittedPending(completion);
        onCatalogReconfigured();
        return completion;
      case WorkspaceFailed():
        await store.restore(previous);
        return completion;
    }
  }
}

void _ignoreCommittedPending(
  WorkspaceCommittedPending<SkillsWorkspaceSnapshot> pending,
) {}

void _ignoreCatalogReconfigured() {}
