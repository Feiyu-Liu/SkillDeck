import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/source_descriptor.dart';
import '../install/initial_import_models.dart';
import '../operations/operation_models.dart';
import '../runtime/revision_engine_port.dart';

/// Allocates business entity identities without coupling application logic to
/// a UUID package or to Operation identity allocation.
abstract interface class WorkspaceEntityIdentityPort {
  ManagedSkillId allocateManagedSkillId();

  SourceLineageReference allocateSourceLineage();

  String allocateActivationId();
}

enum SourcePayloadEncodingFailureCode { invalidSource, credentialRejected }

sealed class SourcePayloadEncodingResult {
  const SourcePayloadEncodingResult();
}

final class SourcePayloadEncoded extends SourcePayloadEncodingResult {
  const SourcePayloadEncoded(this.payload);

  final PersistedSourcePayload payload;
}

final class SourcePayloadEncodingFailure extends SourcePayloadEncodingResult {
  const SourcePayloadEncodingFailure(this.code);

  final SourcePayloadEncodingFailureCode code;
}

/// Encodes credential-free provenance using the Control Plane's current
/// versioned payload contract.
abstract interface class SourcePayloadEncodingPort {
  SourcePayloadEncodingResult encode(SourceDescriptor source);
}

enum InitialRevisionPreparationFailureCode {
  operationCancelled,
  revisionStoreUnavailable,
  contentRejected,
  recoveryEvidenceFailed,
  ioFailure,
}

sealed class InitialRevisionPreparationResult {
  const InitialRevisionPreparationResult();
}

final class InitialRevisionPreparationSuccess
    extends InitialRevisionPreparationResult {
  InitialRevisionPreparationSuccess(List<PreparedInitialRevision> revisions)
    : revisions = List.unmodifiable(revisions);

  final List<PreparedInitialRevision> revisions;
}

final class InitialRevisionPreparationFailure
    extends InitialRevisionPreparationResult {
  const InitialRevisionPreparationFailure(this.code, {this.detail});

  final RevisionEngineFailureCode? detail;

  final InitialRevisionPreparationFailureCode code;
}

/// Produces operation-scoped immutable candidate evidence for initial imports.
///
/// A concrete adapter must treat the batch as all-or-cleaned and must not
/// publish a live Store, Bundle, Repository Copy, Activation, or SQLite row.
/// Its opaque recovery references are later owned by Operation recovery.
abstract interface class InitialRevisionCandidatePort {
  Future<InitialRevisionPreparationResult> prepareInitialRevisions(
    List<InitialRevisionPreparationIntent> intents, {
    required PreparedOperationEnvelope envelope,
    required CancellationToken cancellationToken,
  });
}

/// Binds an initial-import preflight to the durable transaction contract.
///
/// Implementations own opaque recovery-reference allocation and private
/// materialization specs. [createEnvelope] must not create Store objects or
/// filesystem candidates. [sealPlan] runs only after revision preparation and
/// must preserve the envelope prefix exactly.
abstract interface class InitialImportOperationPlanPort {
  PreparedOperationEnvelope createEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required InitialImportPreflight preflight,
  });

  OperationPlan sealPlan({
    required PreparedOperationEnvelope envelope,
    required InitialImportPreflight preflight,
    required InitialImportPlan initialImportPlan,
  });
}
