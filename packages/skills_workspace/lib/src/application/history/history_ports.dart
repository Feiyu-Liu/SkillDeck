import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../operations/operation_models.dart';
import 'history_models.dart';

abstract interface class WorkspaceHistoryContentPort {
  Future<HistoricalRevisionSelection?> resolvePublishedRevision({
    required ManagedSkillId managedSkillId,
    required OperationSubjectReference reference,
  });

  Future<HistoryResult<SkillDiff>> compare({
    required ManagedSkillId managedSkillId,
    required HistoricalRevisionSelection? from,
    required HistoricalRevisionSelection to,
    required CancellationToken cancellationToken,
  });

  Future<RestoreRevisionState?> readRestoreState(ManagedSkillId managedSkillId);

  /// Full normalized Draft comparison; watcher flags are not authoritative.
  Future<HistoryResult<bool>> inspectDraftDirty({
    required ManagedSkill skill,
    required RestoreRevisionState state,
    required CancellationToken cancellationToken,
  });
}

abstract interface class RestoreRevisionPreparationPort {
  Future<HistoryResult<PreparedRestorePublish>> prepareRestorePublish({
    required PreparedOperationEnvelope envelope,
    required RestorePublishPreflight preflight,
    required CancellationToken cancellationToken,
  });
}

abstract interface class RestoreOperationPlanPort {
  PreparedOperationEnvelope createRestoreEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RestorePublishPreflight preflight,
  });

  OperationPlan sealRestorePlan({
    required PreparedOperationEnvelope envelope,
    required RestorePublishPreflight preflight,
    required PreparedRestorePublishPlan preparedPlan,
  });
}
