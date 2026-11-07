import 'package:skills_workspace/src/application/ports/update_ports.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';

final class RecordingUpdateDraftInspector implements UpdateDraftInspectionPort {
  UpdateDraftInspection result = const UpdateDraftInspection.clean();
  Future<UpdateDraftInspectionResult> Function({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  })?
  onInspect;
  var calls = 0;

  @override
  Future<UpdateDraftInspectionResult> inspectForUpdate({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    final callback = onInspect;
    if (callback != null) {
      return callback(skill: skill, cancellationToken: cancellationToken);
    }
    return UpdateDraftInspectionSuccess(result);
  }
}

final class RecordingUpdateRevisionStateReader
    implements UpdateRevisionStatePort {
  RecordingUpdateRevisionStateReader(this.state);

  UpdateRevisionState? state;
  var calls = 0;

  @override
  Future<UpdateRevisionState?> readUpdateState(
    ManagedSkillId managedSkillId,
  ) async {
    calls += 1;
    return state;
  }
}

final class RecordingSlotMigrationInspector
    implements UpdateSlotMigrationInspectionPort {
  UpdateSlotMigrationInspectionResult result =
      const UpdateSlotMigrationInspectionSuccess();
  var calls = 0;
  String? lastOldSlotKey;
  String? lastNewSlotKey;

  @override
  Future<UpdateSlotMigrationInspectionResult> inspect({
    required RepositorySnapshot snapshot,
    required ManagedSkill skill,
    required String newSlotKey,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    lastOldSlotKey = skill.slotKey;
    lastNewSlotKey = newSlotKey;
    return result;
  }
}

final class RecordingUpdateCandidateStateReader
    implements UpdateCandidateStatePort {
  RecordingUpdateCandidateStateReader(this.state);

  UpdateCandidateState? state;
  var calls = 0;

  @override
  Future<UpdateCandidateState?> readCandidateState(
    ManagedSkillId managedSkillId, {
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    return state;
  }
}
