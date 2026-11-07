import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../operations/operation_models.dart';
import 'draft_models.dart';

abstract interface class DraftWorkspaceStatePort {
  Future<DraftRevisionState?> readDraftState(ManagedSkillId managedSkillId);

  /// Returns authoritative dirty state from a bounded full normalized scan.
  Future<DraftPlanningResult<DraftSummary?>> inspectDraft({
    required ManagedSkill skill,
    required DraftRevisionState state,
    required CancellationToken cancellationToken,
  });
}

/// Performs only operation-scoped external preparation after the Prepared
/// Journal is durable.
abstract interface class DraftRevisionPreparationPort {
  Future<DraftPlanningResult<PreparedEnsureDraft>> prepareEnsureDraft({
    required PreparedOperationEnvelope envelope,
    required EnsureDraftPreparationRequired preflight,
    required CancellationToken cancellationToken,
  });

  Future<DraftPlanningResult<PreparedDraftPublish>> preparePublishDraft({
    required PreparedOperationEnvelope envelope,
    required PublishDraftPreparationRequired preflight,
    required CancellationToken cancellationToken,
  });
}

/// Binds Draft intents to opaque recovery and materialization steps.
abstract interface class DraftOperationPlanPort {
  PreparedOperationEnvelope createEnsureEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required EnsureDraftPreparationRequired preflight,
  });

  OperationPlan sealEnsurePlan({
    required PreparedOperationEnvelope envelope,
    required EnsureDraftPreparationRequired preflight,
    required PreparedEnsureDraftPlan preparedPlan,
  });

  OperationPlan createDiscardPlan({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required DiscardDraftPlan plan,
  });

  PreparedOperationEnvelope createPublishEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required PublishDraftPreparationRequired preflight,
  });

  OperationPlan sealPublishPlan({
    required PreparedOperationEnvelope envelope,
    required PublishDraftPreparationRequired preflight,
    required PreparedDraftPublishPlan preparedPlan,
  });
}
