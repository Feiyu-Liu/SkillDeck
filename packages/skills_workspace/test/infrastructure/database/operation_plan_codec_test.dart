import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/database/operation_plan_codec.dart';
import 'package:test/test.dart';

void main() {
  const codec = OperationPlanCodec();

  test('round-trips the complete recovery-direction plan', () {
    final plan = _plan();
    final payload = codec.encode(plan);
    final decoded = codec.decode(
      schemaVersion: OperationPlanCodec.currentSchemaVersion,
      payload: payload,
    );

    expect(decoded.operationId, plan.operationId);
    expect(decoded.expectedRepositoryRevision, plan.expectedRepositoryRevision);
    expect(
      decoded.committedRepositoryRevision,
      plan.committedRepositoryRevision,
    );
    expect(decoded.operationGeneration, 3);
    expect(
      decoded.preparationSteps.single.kind,
      PreparationStepKind.revisionBundle,
    );
    expect(
      decoded.applyingSteps.single.kind,
      ApplyingStepKind.materializationReplacement,
    );
    expect(
      decoded.finalizationSteps.single.kind,
      FinalizationStepKind.backupRotation,
    );
    expect(
      decoded.revisionSelectionChanges.single.intendedEffective,
      plan.revisionSelectionChanges.single.intendedEffective,
    );
    expect(decoded.record.kind, 'update');
    expect(decoded.record.subjects.single, plan.record.subjects.single);
    expect(decoded.businessChanges.incrementsDestructionEpoch, isTrue);
    expect(decoded.businessChanges.mutations.single, isA<PutSkillUserData>());
  });

  test('round-trips an absent previous selection for Install', () {
    final original = _plan(previousSelection: false);
    final decoded = codec.decode(
      schemaVersion: OperationPlanCodec.currentSchemaVersion,
      payload: codec.encode(original),
    );

    expect(decoded.revisionSelectionChanges.single.previousUpstream, isNull);
    expect(decoded.revisionSelectionChanges.single.previousEffective, isNull);
  });

  test('round-trips a pre-candidate Prepared envelope', () {
    final plan = _plan();
    final envelope = PreparedOperationEnvelope(
      operationId: plan.operationId,
      expectedRepositoryRevision: plan.expectedRepositoryRevision,
      committedRepositoryRevision: plan.committedRepositoryRevision,
      operationGeneration: plan.operationGeneration,
      preparationSteps: <PreparationOperationStep>[
        plan.preparationSteps.single,
      ],
      record: OperationRecordPlan(
        operationId: plan.operationId,
        kind: plan.record.kind,
        retainWithoutSubjects: true,
        subjects: const <OperationSubjectPlan>[],
      ),
    );

    final decoded = codec.decodeDefinition(
      schemaVersion: OperationPlanCodec.currentSchemaVersion,
      payload: codec.encodeDefinition(envelope),
    );

    expect(decoded, isA<PreparedOperationEnvelope>());
    final prepared = decoded as PreparedOperationEnvelope;
    expect(prepared.operationId, envelope.operationId);
    expect(prepared.preparationSteps.single.stepId, 'prepare-bundle');
    expect(prepared.record.kind, 'update');
    expect(
      () => codec.decode(
        schemaVersion: OperationPlanCodec.currentSchemaVersion,
        payload: codec.encodeDefinition(envelope),
      ),
      throwsA(_reason('expectedSealedPlan')),
    );
  });

  test('rejects unknown schemas, malformed JSON, and unknown enums', () {
    expect(
      () => codec.decode(schemaVersion: 1, payload: '{}'),
      throwsA(_reason('unsupportedSchemaVersion')),
    );
    expect(
      () => codec.decode(
        schemaVersion: OperationPlanCodec.currentSchemaVersion,
        payload: 'not-json',
      ),
      throwsA(_reason('invalidJson')),
    );
    final payload = codec
        .encode(_plan())
        .replaceFirst('"revisionBundle"', '"unknownStep"');
    expect(
      () => codec.decode(
        schemaVersion: OperationPlanCodec.currentSchemaVersion,
        payload: payload,
      ),
      throwsA(_reason('unknownEnumValue')),
    );
  });
}

OperationPlan _plan({bool previousSelection = true}) {
  final operationId = OperationId('123e4567-e89b-42d3-a456-426614174010');
  final skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174011');
  final lineage = SourceLineageReference(
    '123e4567-e89b-42d3-a456-426614174012',
  );
  final oldAddress = RevisionAddress(
    sourceLineage: lineage,
    objectId: RevisionObjectId('a' * 40),
  );
  final newAddress = RevisionAddress(
    sourceLineage: lineage,
    objectId: RevisionObjectId('b' * 40),
  );
  return OperationPlan(
    operationId: operationId,
    expectedRepositoryRevision: RepositoryRevision(7),
    committedRepositoryRevision: RepositoryRevision(8),
    operationGeneration: 3,
    preparationSteps: [
      PreparationOperationStep(
        stepId: 'prepare-bundle',
        recoveryReference: RecoveryReference('recovery:bundle'),
        kind: PreparationStepKind.revisionBundle,
      ),
    ],
    applyingSteps: [
      ApplyingOperationStep(
        stepId: 'replace-copy',
        recoveryReference: RecoveryReference('recovery:copy'),
        kind: ApplyingStepKind.materializationReplacement,
      ),
    ],
    finalizationSteps: [
      FinalizationOperationStep(
        stepId: 'rotate-backup',
        recoveryReference: RecoveryReference('recovery:backup'),
        kind: FinalizationStepKind.backupRotation,
      ),
    ],
    revisionSelectionChanges: [
      RevisionSelectionChangePlan(
        managedSkillId: skillId,
        previousUpstream: previousSelection ? oldAddress : null,
        previousEffective: previousSelection ? oldAddress : null,
        intendedUpstream: newAddress,
        intendedEffective: newAddress,
      ),
    ],
    businessChanges: WorkspaceBusinessChangeSet(
      incrementsDestructionEpoch: true,
      mutations: [
        PutSkillUserData(
          managedSkillId: skillId,
          favorite: true,
          favoriteChangedAtMicros: 10,
          note: 'Pinned',
          noteUpdatedAtMicros: 11,
        ),
      ],
    ),
    record: OperationRecordPlan(
      operationId: operationId,
      kind: 'update',
      subjects: [
        OperationSubjectPlan(
          reference: OperationSubjectReference(
            operationId: operationId,
            subjectId: '123e4567-e89b-42d3-a456-426614174013',
          ),
          managedSkillId: skillId,
          displayName: 'Example Skill',
          sourceLineage: lineage,
          beforeObjectId: oldAddress.objectId,
          afterObjectId: newAddress.objectId,
          beforeContentHash: 'c' * 64,
          afterContentHash: 'd' * 64,
        ),
      ],
    ),
  );
}

Matcher _reason(String reason) => isA<OperationPlanCodecException>().having(
  (error) => error.reason,
  'reason',
  reason,
);
