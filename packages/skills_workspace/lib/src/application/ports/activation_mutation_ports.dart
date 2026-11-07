import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../activation/activation_models.dart';
import '../activation/activation_mutation_models.dart';
import '../operations/operation_models.dart';
import '../operations/operation_plan_assembler.dart';

/// Reads Activation identity and provenance without exposing Drift rows.
abstract interface class ActivationMetadataReaderPort {
  Future<List<PersistedActivation>> readForSkills(
    Set<ManagedSkillId> managedSkillIds,
  );
}

/// Allocates stable Activation row identities.
abstract interface class ActivationIdentityPort {
  String allocateActivationId();
}

/// Resolves the stable Repository Copy selected by an Activation.
abstract interface class ActivationMaterializationPathPort {
  String repositoryCopyPath(String slotKey);
}

/// Converts one application Activation mutation into opaque recovery steps.
///
/// Filesystem paths, link construction, rollback payloads and recovery bundle
/// internals remain owned by the implementation.
abstract interface class ActivationOperationPlanPort {
  OperationPlan assemble({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositorySnapshot planningSnapshot,
    required WorkspaceOperationKind kind,
    required ActivationMutationPlan mutation,
    required List<OperationSubjectIntent> subjects,
  });
}

/// Re-checks a reviewed unmanaged target immediately before recovery evidence
/// captures its bytes. This closes the inspection-to-apply race without
/// leaking activation fingerprints into the generic Operation Journal.
abstract interface class ActivationTargetExpectationPort {
  Future<bool> matches({
    required ManagedSkill skill,
    required ResolvedActivationTarget target,
    required String targetPath,
    required ActivationTargetExpectation expectation,
  });
}
