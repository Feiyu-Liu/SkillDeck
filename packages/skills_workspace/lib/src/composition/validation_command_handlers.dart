import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'skill_integrity_coordinator.dart';

List<SkillsCommandHandler> buildValidationCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required SkillIntegrityCoordinator integrity,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<
    ValidateWorkspaceRequest,
    WorkspaceValidationReport
  >(
    kind: WorkspaceOperationKind.validateWorkspace,
    handle: (request, context) async {
      final available = snapshots.current.managedSkills
          .map((skill) => skill.id)
          .toSet();
      final selected = request.managedSkillIds ?? available;
      if (!available.containsAll(selected)) {
        return SkillsFailure<WorkspaceValidationReport>(
          code: SkillsErrorCode.skillNotFound,
        );
      }
      final ids = selected.toList(growable: false)
        ..sort((left, right) => left.value.compareTo(right.value));
      var cursor = 0;
      var completed = 0;
      final results = <ManagedSkillId, SkillIntegrityValidationResult>{};
      context.reportProgress(
        OperationProgressPhase.inspecting,
        completed: 0,
        total: ids.length,
      );

      Future<void> worker() async {
        while (!context.cancellationToken.isCancelled) {
          final index = cursor;
          if (index >= ids.length) return;
          cursor += 1;
          final id = ids[index];
          results[id] = await integrity.validate(id);
          completed += 1;
          context.reportProgress(
            OperationProgressPhase.inspecting,
            completed: completed,
            total: ids.length,
          );
        }
      }

      await Future.wait([
        for (var index = 0; index < ids.length.clamp(0, 4); index += 1)
          worker(),
      ]);
      if (context.cancellationToken.isCancelled) {
        return SkillsFailure<WorkspaceValidationReport>(
          code: SkillsErrorCode.operationCancelled,
        );
      }
      final repairedSkillIds = <ManagedSkillId>[];
      final driftedSkillIds = <ManagedSkillId>[];
      final failedSkillIds = <ManagedSkillId>[];
      var repairedArtifactCount = 0;
      var healthySkillCount = 0;
      for (final entry in results.entries) {
        repairedArtifactCount += entry.value.repairedArtifactCount;
        if (entry.value.repairedArtifactCount > 0) {
          repairedSkillIds.add(entry.key);
        }
        switch (entry.value.status) {
          case SkillIntegrityStatus.healthy || SkillIntegrityStatus.recovered:
            healthySkillCount += 1;
          case SkillIntegrityStatus.driftPending:
            driftedSkillIds.add(entry.key);
          case SkillIntegrityStatus.repairFailed ||
              SkillIntegrityStatus.revisionStoreCorrupt:
            failedSkillIds.add(entry.key);
          case SkillIntegrityStatus.unverified ||
              SkillIntegrityStatus.validating:
            failedSkillIds.add(entry.key);
        }
      }
      return SkillsSuccess<WorkspaceValidationReport>(
        value: WorkspaceValidationReport(
          checkedSkillCount: results.length,
          repairedArtifactCount: repairedArtifactCount,
          healthySkillCount: healthySkillCount,
          repairedSkillIds: repairedSkillIds,
          driftedSkillIds: driftedSkillIds,
          failedSkillIds: failedSkillIds,
        ),
      );
    },
  ),
];
