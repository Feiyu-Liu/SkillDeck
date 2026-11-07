import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/data/mappers/installed_skill_catalog_mapper.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';

/// The process-wide reactive authority for managed Workspace state.
///
/// The Runtime owns the repository and its final [SkillsWorkspaceRepository.close]
/// call. This provider owns only its subscription, so disposing a feature that
/// watches the Snapshot can never tear down SQLite, the revision worker, or
/// another feature's Workspace operations.
final workspaceSnapshotProvider =
    AsyncNotifierProvider<WorkspaceSnapshotController, SkillsWorkspaceSnapshot>(
      WorkspaceSnapshotController.new,
    );

/// A projection for consumers that still render the existing Installed-Skills
/// domain model during the incremental cutover.
final workspaceInstalledSkillCatalogProvider =
    Provider<AsyncValue<InstalledSkillCatalog>>((ref) {
      return ref
          .watch(workspaceSnapshotProvider)
          .whenData(installedSkillCatalogFromWorkspace);
    });

/// The immutable project-root projection derived from the sole Workspace
/// Snapshot authority.
final workspaceProjectRootsProvider =
    Provider<AsyncValue<List<SkillProjectRoot>>>((ref) {
      return ref
          .watch(workspaceSnapshotProvider)
          .whenData((snapshot) => snapshot.projectRoots);
    });

/// The immutable managed-Skill projection derived from the sole Workspace
/// Snapshot authority.
final workspaceSkillsProvider = Provider<AsyncValue<List<WorkspaceSkill>>>((
  ref,
) {
  return ref
      .watch(workspaceSnapshotProvider)
      .whenData((snapshot) => snapshot.skills);
});

/// One managed Skill selected by stable Workspace identity.
final workspaceSkillByIdProvider =
    Provider.family<AsyncValue<WorkspaceSkill?>, WorkspaceSkillId>((
      ref,
      skillId,
    ) {
      return ref
          .watch(workspaceSnapshotProvider)
          .whenData((snapshot) => snapshot.findSkillById(skillId));
    });

/// The immutable Library projection. Favorite, Note, and Tag consumers must
/// derive their data from this provider instead of maintaining a second cache.
final workspaceFavoriteSkillsProvider =
    Provider<AsyncValue<List<WorkspaceSkill>>>((ref) {
      return ref
          .watch(workspaceSkillsProvider)
          .whenData(
            (skills) =>
                List.unmodifiable(skills.where((skill) => skill.isFavorite)),
          );
    });

/// Opens the shared repository once, then forwards committed Snapshots.
///
/// Subscription starts before [SkillsWorkspaceRepository.open] so an initial
/// publication cannot race past the provider. Business revisions never regress;
/// integrity updates may share the current revision because they are advisory.
final class WorkspaceSnapshotController
    extends AsyncNotifier<SkillsWorkspaceSnapshot> {
  StreamSubscription<SkillsWorkspaceSnapshot>? _subscription;
  SkillsWorkspaceSnapshot? _latest;
  bool _ready = false;

  @override
  Future<SkillsWorkspaceSnapshot> build() async {
    final repository = ref.watch(skillsWorkspaceRepositoryProvider);
    final analytics = ref.watch(appAnalyticsProvider);
    _subscription?.cancel();
    _subscription = repository.snapshots.listen(
      _acceptSnapshot,
      onError: _acceptError,
    );
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      _subscription = null;
      _ready = false;
    });

    // Do not rely on `current`: production facades expose it only after a
    // successful open. Listening first preserves a Snapshot published while
    // open is awaiting I/O or recovery.
    final stopwatch = Stopwatch()..start();
    final WorkspaceCompletion<SkillsWorkspaceSnapshot> completion;
    try {
      completion = await repository.open();
    } on Object {
      stopwatch.stop();
      analytics.track(
        AppAnalyticsEvent.workspaceBootstrap(
          outcome: WorkspaceBootstrapAnalyticsOutcome.failed,
          duration: stopwatch.elapsed,
          errorCode: 'unexpected',
        ),
      );
      rethrow;
    }
    stopwatch.stop();
    analytics.track(
      AppAnalyticsEvent.workspaceBootstrap(
        outcome: switch (completion) {
          WorkspaceCompleted(:final value) => switch (value.integrity) {
            WorkspaceIntegrityStatus.healthy =>
              WorkspaceBootstrapAnalyticsOutcome.success,
            WorkspaceIntegrityStatus.recovered =>
              WorkspaceBootstrapAnalyticsOutcome.recovered,
            WorkspaceIntegrityStatus.corrupt =>
              WorkspaceBootstrapAnalyticsOutcome.failed,
          },
          WorkspaceFailed() => WorkspaceBootstrapAnalyticsOutcome.failed,
          WorkspaceCommittedPending() =>
            WorkspaceBootstrapAnalyticsOutcome.failed,
        },
        duration: stopwatch.elapsed,
        errorCode: switch (completion) {
          WorkspaceFailed(:final failure) => failure.code.name,
          WorkspaceCompleted(:final value)
              when value.integrity == WorkspaceIntegrityStatus.corrupt =>
            'integrity_corrupt',
          WorkspaceCommittedPending() => 'unexpected',
          _ => null,
        },
      ),
    );
    final opened = switch (completion) {
      WorkspaceCompleted(:final value) => value,
      WorkspaceFailed(:final failure) => throw failure,
      WorkspaceCommittedPending(:final operationId) => throw StateError(
        'Workspace open $operationId unexpectedly requires finalization.',
      ),
    };
    // A stream event received during open is newer than its captured result.
    // At equal business revisions, preserve that event's integrity evidence.
    if (_latest == null || opened.revision > _latest!.revision) {
      _acceptSnapshot(opened);
    }
    _ready = true;
    return _latest ?? opened;
  }

  void _acceptSnapshot(SkillsWorkspaceSnapshot next) {
    final previous = _latest;
    if (previous != null) {
      if (previous.revision > next.revision) return;
      if (previous.revision == next.revision &&
          _sameIntegrity(previous, next)) {
        return;
      }
    }
    _latest = next;
    if (_ready && ref.mounted) state = AsyncData(next);
  }

  void _acceptError(Object error, StackTrace stackTrace) {
    if (!_ready || !ref.mounted) return;
    state = AsyncError(error, stackTrace);
  }
}

bool _sameIntegrity(
  SkillsWorkspaceSnapshot previous,
  SkillsWorkspaceSnapshot next,
) {
  if (previous.integrity != next.integrity ||
      previous.skills.length != next.skills.length) {
    return false;
  }
  final statuses = {
    for (final skill in previous.skills) skill.id: skill.integrity,
  };
  return next.skills.every((skill) => statuses[skill.id] == skill.integrity);
}
