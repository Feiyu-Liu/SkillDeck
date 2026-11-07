import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/skills_workspace.dart';
import 'skills_providers.dart';
import 'workspace_snapshot_providers.dart';

typedef ActivationTargetScope = ({WorkspaceScope scope, String? projectRootId});

final activationCatalogRevisionProvider =
    NotifierProvider<ActivationCatalogRevision, int>(
      ActivationCatalogRevision.new,
    );

class ActivationCatalogRevision extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() {
    // Invalidate before notifying consumers that immediately request a refresh.
    ref.invalidate(activationTargetsProvider);
    state++;
  }
}

/// Shared read-only target inspection. Mutations still use the repository facade.
final activationTargetsProvider =
    FutureProvider.family<
      WorkspaceCompletion<List<WorkspaceActivationTarget>>,
      ActivationTargetScope
    >((ref, selection) async {
      ref.watch(activationCatalogRevisionProvider);
      final repository = ref.watch(skillsWorkspaceRepositoryProvider);
      await ref.watch(
        workspaceSnapshotProvider.selectAsync(
          (s) => s.projectRoots
              .map((r) => '${r.id}\u0000${r.path}')
              .join('\u0001'),
        ),
      );
      return repository
          .inspectActivationTargets(
            scope: selection.scope,
            projectRootId: selection.projectRootId,
          )
          .completed;
    });
