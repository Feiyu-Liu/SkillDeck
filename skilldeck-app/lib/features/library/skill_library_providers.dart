import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

final skillLibraryCommandsProvider =
    NotifierProvider<SkillLibraryCommands, Set<WorkspaceSkillId>>(
      SkillLibraryCommands.new,
    );

/// Mutates Library metadata without owning a second durable state projection.
///
/// Favorite and Note values are rendered from the process-wide Workspace
/// Snapshot. This controller retains only transient per-Skill command state so
/// concurrent UI actions cannot submit duplicate mutations for the same
/// managed identity.
final class SkillLibraryCommands extends Notifier<Set<WorkspaceSkillId>> {
  @override
  Set<WorkspaceSkillId> build() => const {};

  bool isBusy(WorkspaceSkillId skillId) => state.contains(skillId);

  Future<void> toggleFavorite({
    required WorkspaceSkillId skillId,
    required bool isFavorite,
  }) => _run(
    skillId,
    () => ref
        .read(skillsWorkspaceRepositoryProvider)
        .setFavorite(skillId: skillId, isFavorite: !isFavorite),
    operation: WorkspaceOperationKind.setFavorite,
    successMessage: isFavorite
        ? AppNotificationMessage.skillUnfavorited
        : AppNotificationMessage.skillFavorited,
  );

  Future<void> saveNote({
    required WorkspaceSkillId skillId,
    required String note,
  }) {
    final workspace = ref.read(skillsWorkspaceRepositoryProvider);
    final deleting = note.trim().isEmpty;
    return _run(
      skillId,
      () => deleting
          ? workspace.deleteNote(skillId)
          : workspace.saveNote(skillId: skillId, note: note),
      operation: deleting
          ? WorkspaceOperationKind.deleteNote
          : WorkspaceOperationKind.saveNote,
    );
  }

  Future<void> _run(
    WorkspaceSkillId skillId,
    WorkspaceTask<SkillsWorkspaceSnapshot> Function() start, {
    required WorkspaceOperationKind operation,
    AppNotificationMessage? successMessage,
  }) async {
    if (state.contains(skillId)) return;
    state = Set.unmodifiable({...state, skillId});
    try {
      final completion = await start().completed;
      if (!ref.mounted) return;
      switch (completion) {
        case WorkspaceCompleted(:final warnings):
          if (warnings.isNotEmpty) {
            _notifyWarning();
          } else if (successMessage != null) {
            ref
                .read(appNotificationControllerProvider.notifier)
                .success(successMessage);
          }
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
        case WorkspaceFailed(:final failure):
          ref
              .read(appNotificationControllerProvider.notifier)
              .publish(AppNotification.failure(failure));
      }
    } on Object catch (error, stackTrace) {
      if (ref.mounted) {
        final failure = ref
            .read(appFailureReporterProvider)
            .capture(error, stackTrace, operationKey: operation.name);
        ref
            .read(appNotificationControllerProvider.notifier)
            .publish(AppNotification.failure(failure));
      }
    } finally {
      if (ref.mounted) {
        state = Set.unmodifiable(state.where((id) => id != skillId));
      }
    }
  }

  void _notifyWarning() => ref
      .read(appNotificationControllerProvider.notifier)
      .warning(AppNotificationMessage.completedWithWarnings);
}
