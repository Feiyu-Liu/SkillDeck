import '../../domain/identifiers.dart';
import '../operations/operation_models.dart';
import 'update_models.dart';

/// Binds source-Update and Update Candidate intents to opaque recovery plans.
abstract interface class UpdateOperationPlanPort {
  PreparedOperationEnvelope createUpdateEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required List<UpdatePreparationRequired> preflights,
  });

  OperationPlan sealUpdatePlan({
    required PreparedOperationEnvelope envelope,
    required List<UpdatePreparationRequired> preflights,
    required List<PreparedUpdatePlan> preparedPlans,
  });

  PreparedOperationEnvelope createCandidatePublishEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required UpdateCandidatePublishPreflight preflight,
  });

  OperationPlan sealCandidatePublishPlan({
    required PreparedOperationEnvelope envelope,
    required UpdateCandidatePublishPreflight preflight,
    required PreparedUpdatePlan preparedPlan,
  });

  PreparedOperationEnvelope createCandidateAbandonEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required UpdateCandidateAbandonPlan abandonPlan,
  });

  OperationPlan sealCandidateAbandonPlan({
    required PreparedOperationEnvelope envelope,
    required UpdateCandidateAbandonPlan abandonPlan,
    required PreparedUpdateCandidateAbandon prepared,
  });

  OperationPlan createConflictResolutionPlan({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required ManagedSkillId managedSkillId,
    required UpdateConflictResolutionPlan resolutionPlan,
  });
}
