import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/library/personal_tag_palette.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

/// Personal Tags from the Workspace Snapshot, ordered by name.
final personalTagsProvider = Provider<List<WorkspacePersonalTag>>((ref) {
  final tags = ref.watch(workspaceSnapshotProvider).value?.personalTags;
  if (tags == null) return const [];
  return List.unmodifiable(
    [...tags]..sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    ),
  );
});

/// How many managed Skills carry each Personal Tag.
final personalTagCountsProvider = Provider<Map<String, int>>((ref) {
  final skills = ref.watch(workspaceSnapshotProvider).value?.skills;
  final counts = <String, int>{};
  for (final skill in skills ?? const <WorkspaceSkill>[]) {
    for (final tagId in skill.personalTagIds) {
      counts[tagId] = (counts[tagId] ?? 0) + 1;
    }
  }
  return Map.unmodifiable(counts);
});

/// The tags a Skill must all carry to stay visible on Installed and Favorites.
final personalTagFilterProvider =
    NotifierProvider<PersonalTagFilterController, Set<String>>(
      PersonalTagFilterController.new,
    );

final class PersonalTagFilterController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // Deleting a tag must not leave an invisible filter behind.
    ref.listen(workspaceSnapshotProvider, (_, next) {
      final snapshot = next.value;
      if (snapshot == null || state.isEmpty) return;
      final kept = state.where((id) => snapshot.findPersonalTag(id) != null);
      if (kept.length != state.length) state = Set.unmodifiable(kept);
    });
    return const {};
  }

  void toggle(String tagId) => state = Set.unmodifiable(
    state.contains(tagId)
        ? state.where((id) => id != tagId)
        : {...state, tagId},
  );

  void clear() => state = const {};
}

final personalTagCommandsProvider =
    NotifierProvider<PersonalTagCommands, Set<String>>(PersonalTagCommands.new);

/// Mutates Personal Tags and their Skill assignments.
///
/// Like [SkillLibraryCommands], durable values are read back from the
/// Workspace Snapshot; this controller only tracks in-flight keys so a repeated
/// click cannot submit the same mutation twice. Create and rename return their
/// failure so the editing field can show it inline instead of as a toast.
final class PersonalTagCommands extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  Future<AppFailure?> create(String name, {WorkspaceSkillId? assignTo}) async {
    final repository = ref.read(skillsWorkspaceRepositoryProvider);
    final color = nextPersonalTagColor(ref.read(personalTagsProvider));
    WorkspacePersonalTag? created;
    final failure = await _run(
      'create',
      () => repository.createPersonalTag(name: name.trim(), color: color),
      operation: WorkspaceOperationKind.createPersonalTag,
      notifyFailure: false,
      onCompleted: (tag) => created = tag,
    );
    if (failure == null && created != null && assignTo != null) {
      await assign(skillId: assignTo, tagId: created!.id);
    }
    return failure;
  }

  Future<AppFailure?> rename(WorkspacePersonalTag tag, String name) {
    final trimmed = name.trim();
    if (trimmed == tag.name) return Future.value();
    return _run(
      'tag:${tag.id}',
      () => ref
          .read(skillsWorkspaceRepositoryProvider)
          .updatePersonalTag(tagId: tag.id, name: trimmed, color: tag.color),
      operation: WorkspaceOperationKind.updatePersonalTag,
      notifyFailure: false,
    );
  }

  Future<void> recolor(WorkspacePersonalTag tag, String color) {
    if (color == tag.color) return Future.value();
    return _run(
      'tag:${tag.id}',
      () => ref
          .read(skillsWorkspaceRepositoryProvider)
          .updatePersonalTag(tagId: tag.id, name: tag.name, color: color),
      operation: WorkspaceOperationKind.updatePersonalTag,
    );
  }

  Future<void> delete(String tagId) => _run(
    'tag:$tagId',
    () => ref.read(skillsWorkspaceRepositoryProvider).deletePersonalTag(tagId),
    operation: WorkspaceOperationKind.deletePersonalTag,
  );

  Future<void> assign({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => _run(
    'skill:${skillId.value}:$tagId',
    () => ref
        .read(skillsWorkspaceRepositoryProvider)
        .assignPersonalTag(skillId: skillId, tagId: tagId),
    operation: WorkspaceOperationKind.assignPersonalTag,
  );

  Future<void> unassign({
    required WorkspaceSkillId skillId,
    required String tagId,
  }) => _run(
    'skill:${skillId.value}:$tagId',
    () => ref
        .read(skillsWorkspaceRepositoryProvider)
        .unassignPersonalTag(skillId: skillId, tagId: tagId),
    operation: WorkspaceOperationKind.unassignPersonalTag,
  );

  Future<AppFailure?> _run<T>(
    String key,
    WorkspaceTask<T> Function() start, {
    required WorkspaceOperationKind operation,
    bool notifyFailure = true,
    void Function(T value)? onCompleted,
  }) async {
    if (state.contains(key)) return null;
    state = Set.unmodifiable({...state, key});
    try {
      final completion = await start().completed;
      if (!ref.mounted) return null;
      switch (completion) {
        case WorkspaceCompleted(:final value, :final warnings):
          if (warnings.isNotEmpty) {
            ref
                .read(appNotificationControllerProvider.notifier)
                .warning(AppNotificationMessage.completedWithWarnings);
          }
          onCompleted?.call(value);
          return null;
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
          :final warnings,
        ):
          ref
              .read(workspaceFinalizationCoordinatorProvider.notifier)
              .register(
                WorkspaceCommittedPending<void>(
                  operationId: operationId,
                  committedRevision: committedRevision,
                  warnings: warnings,
                ),
              );
          return null;
        case WorkspaceFailed(:final failure):
          if (notifyFailure) _notifyFailure(failure);
          return failure;
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return null;
      final failure = ref
          .read(appFailureReporterProvider)
          .capture(error, stackTrace, operationKey: operation.name);
      if (notifyFailure) _notifyFailure(failure);
      return failure;
    } finally {
      if (ref.mounted) {
        state = Set.unmodifiable(state.where((id) => id != key));
      }
    }
  }

  void _notifyFailure(AppFailure failure) => ref
      .read(appNotificationControllerProvider.notifier)
      .publish(AppNotification.failure(failure));
}
