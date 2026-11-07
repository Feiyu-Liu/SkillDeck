import 'package:skills_workspace/src/application/install/initial_import_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/initial_import_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';

final class SequenceWorkspaceEntityIdentities
    implements WorkspaceEntityIdentityPort {
  var _managedSkill = 1;
  var _lineage = 101;
  var _activation = 201;

  @override
  ManagedSkillId allocateManagedSkillId() =>
      ManagedSkillId(_uuid(_managedSkill++));

  @override
  SourceLineageReference allocateSourceLineage() =>
      SourceLineageReference(_uuid(_lineage++));

  @override
  String allocateActivationId() => _uuid(_activation++);
}

final class FakeSourcePayloadEncoding implements SourcePayloadEncodingPort {
  SourcePayloadEncodingFailureCode? failure;
  final encodedSources = <SourceDescriptor>[];

  @override
  SourcePayloadEncodingResult encode(SourceDescriptor source) {
    encodedSources.add(source);
    final failed = failure;
    if (failed != null) return SourcePayloadEncodingFailure(failed);
    return SourcePayloadEncoded(
      PersistedSourcePayload(
        kind: switch (source.type) {
          SourceType.local => WorkspaceSourceKind.local,
          SourceType.git => WorkspaceSourceKind.git,
          SourceType.wellKnown => WorkspaceSourceKind.wellKnown,
          SourceType.adoptedSnapshot => WorkspaceSourceKind.adoptedSnapshot,
        },
        payloadSchemaVersion: 1,
        payloadJson: '{}',
      ),
    );
  }
}

final class RecordingInitialRevisionCandidates
    implements InitialRevisionCandidatePort {
  InitialRevisionPreparationFailureCode? failure;
  RevisionEngineFailureCode? failureDetail;
  var calls = 0;
  List<InitialRevisionPreparationIntent> lastIntents = const [];
  PreparedOperationEnvelope? lastEnvelope;

  @override
  Future<InitialRevisionPreparationResult> prepareInitialRevisions(
    List<InitialRevisionPreparationIntent> intents, {
    required PreparedOperationEnvelope envelope,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    lastIntents = List.unmodifiable(intents);
    lastEnvelope = envelope;
    final failed = failure;
    if (failed != null) {
      return InitialRevisionPreparationFailure(failed, detail: failureDetail);
    }
    return InitialRevisionPreparationSuccess([
      for (var index = 0; index < intents.length; index += 1)
        PreparedInitialRevision(
          managedSkillId: intents[index].managedSkillId,
          sourceLineage: intents[index].sourceLineage,
          objectId: RevisionObjectId(
            (index + 1).toRadixString(16).padLeft(40, '0'),
          ),
          objectFormat: WorkspaceObjectFormat.sha1,
          candidateRecoveryReference: RecoveryReference(
            'candidate-${intents[index].managedSkillId.value}',
          ),
          bundleRecoveryReference: RecoveryReference(
            'bundle-${intents[index].managedSkillId.value}',
          ),
        ),
    ]);
  }
}

String _uuid(int suffix) =>
    '00000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}';
