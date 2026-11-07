import 'dart:async';

import 'package:skills_workspace/src/application/destructive/destructive_operation_models.dart';
import 'package:skills_workspace/src/application/destructive/destructive_operation_planner.dart';
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/destructive_operation_ports.dart';
import 'package:skills_workspace/src/application/ports/initial_import_ports.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

const _operationValue = '00000000-0000-4000-8000-000000000001';
const _skillValue = '00000000-0000-4000-8000-000000000002';
const _otherSkillValue = '00000000-0000-4000-8000-000000000003';
const _subjectValue = '00000000-0000-4000-8000-000000000004';
const _oldLineageOne = 'old-lineage-one';
const _oldLineageTwo = 'old-lineage-two';
const _newLineage = 'new-lineage';
const _oldUpstreamObject = '1111111111111111111111111111111111111111';
const _oldEffectiveObject = '2222222222222222222222222222222222222222';
const _newObject = '3333333333333333333333333333333333333333';
const _oldHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late _RecordingIdentities identities;
  late _RecordingReplacementPreparation preparation;
  late _RecordingRecoveryPlans recoveryPlans;
  late _RecoveryEntries recoveryEntries;
  late _RecordingSubjectIdentities subjectIdentities;
  late DestructiveOperationPlanner planner;

  setUp(() {
    identities = _RecordingIdentities();
    preparation = _RecordingReplacementPreparation();
    recoveryPlans = _RecordingRecoveryPlans();
    recoveryEntries = _RecoveryEntries();
    subjectIdentities = _RecordingSubjectIdentities();
    planner = _planner(
      identities: identities,
      preparation: preparation,
      recoveryPlans: recoveryPlans,
      recoveryEntries: recoveryEntries,
      subjectIdentities: subjectIdentities,
    );
  });

  test(
    'stale Source Replacement rejects before IDs, acquisition, or recovery',
    () async {
      final result = await planner.planSourceReplacement(
        operationId: OperationId(_operationValue),
        envelope: _replacementEnvelope(recoveryPlans),
        snapshot: _snapshot(),
        destructiveIntent: DestructiveOperationIntent(
          reviewedRevision: RepositoryRevision(6),
        ),
        managedSkillId: ManagedSkillId(_skillValue),
        source: LocalSourceDescriptor(locator: '/replacement'),
        includeInternal: false,
        fullDepth: false,
      );

      expect(
        result.failureOrNull?.code,
        DestructivePlanningFailureCode.staleIntent,
      );
      expect(identities.lineageAllocations, 0);
      expect(preparation.calls, 0);
      expect(recoveryPlans.destructiveCalls, 0);
      expect(subjectIdentities.calls, 0);
    },
  );

  for (final blocked
      in <
        (String, DestructiveManagedSkillState, DestructivePlanningFailureCode)
      >[
        (
          'dirty Draft',
          _skill(draftState: DestructiveDraftState.dirty),
          DestructivePlanningFailureCode.dirtyDraftResolutionRequired,
        ),
        (
          'Update Candidate Session',
          _skill(hasUpdateCandidateSession: true),
          DestructivePlanningFailureCode.updateCandidateResolutionRequired,
        ),
      ]) {
    test(
      '${blocked.$1} blocks Source Replacement before preparation',
      () async {
        final result = await planner.planSourceReplacement(
          operationId: OperationId(_operationValue),
          envelope: _replacementEnvelope(recoveryPlans),
          snapshot: _snapshot(skills: [blocked.$2]),
          destructiveIntent: DestructiveOperationIntent(
            reviewedRevision: RepositoryRevision(7),
          ),
          managedSkillId: ManagedSkillId(_skillValue),
          source: LocalSourceDescriptor(locator: '/replacement'),
          includeInternal: false,
          fullDepth: false,
        );

        expect(result.failureOrNull?.code, blocked.$3);
        expect(identities.lineageAllocations, 0);
        expect(preparation.calls, 0);
        expect(recoveryPlans.destructiveCalls, 0);
      },
    );
  }

  test(
    'Source Replacement preserves identity and user configuration while replacing lineage',
    () async {
      final envelope = _replacementEnvelope(recoveryPlans);
      final result = await planner.planSourceReplacement(
        operationId: OperationId(_operationValue),
        envelope: envelope,
        snapshot: _snapshot(
          skills: [_skill(draftState: DestructiveDraftState.clean)],
        ),
        destructiveIntent: DestructiveOperationIntent(
          reviewedRevision: RepositoryRevision(7),
        ),
        managedSkillId: ManagedSkillId(_skillValue),
        source: LocalSourceDescriptor(locator: '/replacement'),
        includeInternal: true,
        fullDepth: true,
      );

      final plan = result.valueOrNull!;
      expect(envelope.isSealedBy(plan), isTrue);
      expect(preparation.calls, 1);
      expect(
        preparation.lastIntent?.intendedSourceLineage.encoded,
        _newLineage,
      );
      expect(preparation.lastIntent?.includeInternal, isTrue);
      expect(preparation.lastIntent?.fullDepth, isTrue);
      expect(plan.expectedRepositoryRevision, RepositoryRevision(7));
      expect(plan.committedRepositoryRevision, RepositoryRevision(8));
      expect(plan.businessChanges.incrementsDestructionEpoch, isTrue);

      final mutations = plan.businessChanges.mutations;
      final managedSkill = mutations.whereType<PutManagedSkill>().single;
      expect(managedSkill.managedSkillId, ManagedSkillId(_skillValue));
      expect(managedSkill.createdAtMicros, 10);
      expect(managedSkill.activeSourceLineageId, _newLineage);
      expect(managedSkill.slotKey, 'replacement-slot');
      final lineage = mutations.whereType<PutSourceLineage>().single;
      expect(lineage.sourceLineageId, _newLineage);
      expect(mutations.whereType<PutSkillSource>(), hasLength(1));
      expect(mutations.whereType<PutRevisionMetadata>(), hasLength(1));
      expect(mutations.whereType<DeleteDraftWorkspace>(), hasLength(1));
      expect(
        mutations.whereType<DeleteSourceLineage>().map(
          (value) => value.sourceLineageId,
        ),
        [_oldLineageOne, _oldLineageTwo],
      );
      expect(mutations.whereType<PutSkillUserData>(), isEmpty);
      expect(mutations.whereType<PutSkillTagAssignment>(), isEmpty);
      expect(mutations.whereType<PutActivation>(), isEmpty);
      expect(mutations.whereType<DeleteActivation>(), isEmpty);

      final selection = plan.revisionSelectionChanges.single;
      expect(selection.managedSkillId, ManagedSkillId(_skillValue));
      expect(selection.previousUpstream?.objectId.value, _oldUpstreamObject);
      expect(selection.previousEffective?.objectId.value, _oldEffectiveObject);
      expect(selection.intendedUpstream?.sourceLineage.encoded, _newLineage);
      expect(selection.intendedUpstream?.objectId.value, _newObject);
      expect(selection.intendedEffective, selection.intendedUpstream);

      final subject = plan.record.subjects.single;
      expect(subject.managedSkillId, ManagedSkillId(_skillValue));
      expect(subject.sourceLineage?.encoded, _newLineage);
      expect(subject.beforeObjectId, isNull);
      expect(subject.beforeContentHash, isNull);
      expect(subject.afterObjectId?.value, _newObject);
      expect(subject.afterContentHash, _newHash);

      final recovery = recoveryPlans.intent as SourceReplacementRecoveryIntent;
      expect(recovery.skill.managedSkillId, ManagedSkillId(_skillValue));
      expect(recovery.skill.activationIds, [
        'activation-one',
        'activation-two',
      ]);
      expect(recovery.skill.hasDraft, isTrue);
      expect(recovery.skill.hasUpdateCandidateSession, isFalse);
      expect(
        recovery.skill.sourceLineages.map(
          (value) => value.sourceLineage.encoded,
        ),
        [_oldLineageOne, _oldLineageTwo],
      );
      expect(recovery.intendedSourceLineage.encoded, _newLineage);
      expect(recovery.intendedObjectId.value, _newObject);
      expect(recovery.intendedContentHash, _newHash);
      expect(recovery.intendedObjectFormat, WorkspaceObjectFormat.sha1);
    },
  );

  test('Source Replacement rejects a changed occupied Slot Key', () async {
    final result = await planner.planSourceReplacement(
      operationId: OperationId(_operationValue),
      envelope: _replacementEnvelope(recoveryPlans),
      snapshot: _snapshot(
        skills: [
          _skill(),
          _skill(
            managedSkillId: ManagedSkillId(_otherSkillValue),
            slotKey: 'replacement-slot',
            displayName: 'Other',
          ),
        ],
      ),
      destructiveIntent: DestructiveOperationIntent(
        reviewedRevision: RepositoryRevision(7),
      ),
      managedSkillId: ManagedSkillId(_skillValue),
      source: LocalSourceDescriptor(locator: '/replacement'),
      includeInternal: false,
      fullDepth: false,
    );

    expect(
      result.failureOrNull?.code,
      DestructivePlanningFailureCode.replacementSlotOccupied,
    );
    expect(preparation.calls, 1);
    expect(recoveryPlans.destructiveCalls, 0);
    expect(subjectIdentities.calls, 0);
  });

  test('stale Removal rejects before recovery registration', () async {
    final result = await planner.planRemoval(
      operationId: OperationId(_operationValue),
      snapshot: _snapshot(),
      destructiveIntent: DestructiveOperationIntent(
        reviewedRevision: RepositoryRevision(8),
      ),
      managedSkillIds: {ManagedSkillId(_skillValue)},
      cancellationToken: CancellationToken.none(),
    );

    expect(
      result.failureOrNull?.code,
      DestructivePlanningFailureCode.staleIntent,
    );
    expect(recoveryPlans.destructiveCalls, 0);
    expect(subjectIdentities.calls, 0);
  });

  test(
    'Removal deletes complete Skill aggregates but preserves Personal Tag entities',
    () async {
      final second = _skill(
        managedSkillId: ManagedSkillId(_otherSkillValue),
        slotKey: 'second',
        displayName: 'Second',
        draftState: DestructiveDraftState.clean,
        hasUpdateCandidateSession: true,
      );
      final result = await planner.planRemoval(
        operationId: OperationId(_operationValue),
        snapshot: _snapshot(skills: [_skill(), second]),
        destructiveIntent: DestructiveOperationIntent(
          reviewedRevision: RepositoryRevision(7),
        ),
        managedSkillIds: {
          ManagedSkillId(_otherSkillValue),
          ManagedSkillId(_skillValue),
        },
        cancellationToken: CancellationToken.none(),
      );

      final plan = result.valueOrNull!;
      expect(plan.businessChanges.incrementsDestructionEpoch, isTrue);
      expect(
        plan.businessChanges.mutations.whereType<DeleteManagedSkill>().map(
          (mutation) => mutation.managedSkillId.value,
        ),
        [_skillValue, _otherSkillValue],
      );
      expect(
        plan.businessChanges.mutations.whereType<DeletePersonalTag>(),
        isEmpty,
      );
      expect(plan.revisionSelectionChanges, hasLength(2));
      expect(
        plan.revisionSelectionChanges,
        everyElement(
          predicate<RevisionSelectionChangePlan>(
            (change) =>
                change.intendedUpstream == null &&
                change.intendedEffective == null,
          ),
        ),
      );

      final recovery = recoveryPlans.intent as RemovalRecoveryIntent;
      expect(recovery.skills, hasLength(2));
      final recoveredSecond = recovery.skills.singleWhere(
        (skill) => skill.managedSkillId == ManagedSkillId(_otherSkillValue),
      );
      expect(recoveredSecond.sourceLineages, hasLength(2));
      expect(recoveredSecond.activationIds, [
        'activation-one',
        'activation-two',
      ]);
      expect(recoveredSecond.hasDraft, isTrue);
      expect(recoveredSecond.hasUpdateCandidateSession, isTrue);
      expect(plan.record.subjects, hasLength(2));
      expect(
        plan.record.subjects.map((subject) => subject.beforeContentHash),
        everyElement(_oldHash),
      );
    },
  );

  test('Removal maps cancellation during recovery entry preparation', () async {
    final cancellation = CancellationSource();
    final entered = Completer<CancellationToken>();
    final release = Completer<void>();
    recoveryEntries.onPrepare =
        ({
          required operationId,
          required intent,
          required cancellationToken,
        }) async {
          entered.complete(cancellationToken);
          await release.future;
          if (cancellationToken.isCancelled) {
            throw StateError('cancelled during recovery entry preparation');
          }
        };

    final pending = planner.planRemoval(
      operationId: OperationId(_operationValue),
      snapshot: _snapshot(),
      destructiveIntent: DestructiveOperationIntent(
        reviewedRevision: RepositoryRevision(7),
      ),
      managedSkillIds: {ManagedSkillId(_skillValue)},
      cancellationToken: cancellation.token,
    );

    expect(identical(await entered.future, cancellation.token), isTrue);
    await cancellation.cancel();
    release.complete();
    final result = await pending;

    expect(
      result.failureOrNull?.code,
      DestructivePlanningFailureCode.operationCancelled,
    );
    expect(recoveryPlans.destructiveCalls, 0);
    expect(subjectIdentities.calls, 0);
  });
}

DestructiveOperationPlanner _planner({
  required _RecordingIdentities identities,
  required _RecordingReplacementPreparation preparation,
  required _RecordingRecoveryPlans recoveryPlans,
  required _RecoveryEntries recoveryEntries,
  required _RecordingSubjectIdentities subjectIdentities,
}) => DestructiveOperationPlanner(
  identities: identities,
  replacementPreparation: preparation,
  recoveryEntries: recoveryEntries,
  operationPlans: OperationPlanAssembler(
    subjectIdentities: subjectIdentities,
    recoveryPlans: recoveryPlans,
  ),
  clock: () => 100,
);

final class _RecoveryEntries
    implements DestructiveRecoveryEntryPreparationPort {
  var calls = 0;
  Future<void> Function({
    required OperationId operationId,
    required DestructiveOperationRecoveryIntent intent,
    required CancellationToken cancellationToken,
  })?
  onPrepare;

  @override
  Future<void> prepareRecoveryEntries({
    required OperationId operationId,
    required DestructiveOperationRecoveryIntent intent,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    await onPrepare?.call(
      operationId: operationId,
      intent: intent,
      cancellationToken: cancellationToken,
    );
  }
}

DestructivePlanningSnapshot _snapshot({
  List<DestructiveManagedSkillState>? skills,
}) => DestructivePlanningSnapshot(
  repositoryRevision: RepositoryRevision(7),
  managedSkills: skills ?? [_skill()],
);

DestructiveManagedSkillState _skill({
  ManagedSkillId? managedSkillId,
  String slotKey = 'current-slot',
  String displayName = 'Current',
  DestructiveDraftState draftState = DestructiveDraftState.absent,
  bool hasUpdateCandidateSession = false,
}) {
  final activeLineage = SourceLineageReference(_oldLineageTwo);
  return DestructiveManagedSkillState(
    managedSkillId: managedSkillId ?? ManagedSkillId(_skillValue),
    slotKey: slotKey,
    declaredName: slotKey,
    displayName: displayName,
    description: '$displayName description',
    createdAtMicros: 10,
    sourceLineages: [
      DestructiveSourceLineageState(
        sourceLineage: SourceLineageReference(_oldLineageOne),
      ),
      DestructiveSourceLineageState(sourceLineage: activeLineage),
    ],
    activeSourceLineage: activeLineage,
    currentUpstream: RevisionAddress(
      sourceLineage: activeLineage,
      objectId: RevisionObjectId(_oldUpstreamObject),
    ),
    currentEffective: RevisionAddress(
      sourceLineage: activeLineage,
      objectId: RevisionObjectId(_oldEffectiveObject),
    ),
    currentContentHash: _oldHash,
    activationIds: const ['activation-one', 'activation-two'],
    draftState: draftState,
    hasUpdateCandidateSession: hasUpdateCandidateSession,
  );
}

final class _RecordingIdentities implements WorkspaceEntityIdentityPort {
  var lineageAllocations = 0;

  @override
  SourceLineageReference allocateSourceLineage() {
    lineageAllocations += 1;
    return SourceLineageReference(_newLineage);
  }

  @override
  String allocateActivationId() => throw UnimplementedError();

  @override
  ManagedSkillId allocateManagedSkillId() => throw UnimplementedError();
}

final class _RecordingReplacementPreparation
    implements SourceReplacementPreparationPort {
  var calls = 0;
  SourceReplacementPreparationIntent? lastIntent;

  @override
  Future<SourceReplacementPreparationResult> prepareSourceReplacement(
    SourceReplacementPreparationIntent intent, {
    required PreparedOperationEnvelope envelope,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    lastIntent = intent;
    return SourceReplacementPreparationSuccess(
      PreparedSourceReplacement(
        managedSkillId: intent.managedSkillId,
        sourceLineage: intent.intendedSourceLineage,
        objectId: RevisionObjectId(_newObject),
        objectFormat: WorkspaceObjectFormat.sha1,
        persistedSourceKind: WorkspaceSourceKind.local,
        sourcePayloadSchemaVersion: 1,
        sourcePayloadJson: '{"locator":"/replacement"}',
        slotKey: 'replacement-slot',
        declaredName: 'replacement-slot',
        displayName: 'Replacement',
        description: 'Replacement description',
        contentHash: _newHash,
        fileCount: 2,
        byteSize: 128,
      ),
    );
  }
}

final class _RecordingRecoveryPlans
    implements OperationRecoveryPlanFactoryPort {
  var destructiveCalls = 0;
  DestructiveOperationRecoveryIntent? intent;

  @override
  List<PreparationOperationStep> createDestructiveEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
  }) => <PreparationOperationStep>[
    PreparationOperationStep(
      stepId: 'prepare',
      recoveryReference: RecoveryReference('prepare'),
      kind: PreparationStepKind.recoveryEvidence,
    ),
  ];

  @override
  OperationRecoveryPlanSteps createDestructive({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required DestructiveOperationRecoveryIntent intent,
  }) {
    destructiveCalls += 1;
    this.intent = intent;
    return OperationRecoveryPlanSteps(
      preparationSteps: [
        PreparationOperationStep(
          stepId: 'prepare',
          recoveryReference: RecoveryReference('prepare'),
          kind: PreparationStepKind.recoveryEvidence,
        ),
      ],
      applyingSteps: [
        ApplyingOperationStep(
          stepId: 'apply',
          recoveryReference: RecoveryReference('apply'),
          kind: ApplyingStepKind.destructiveReplacement,
        ),
      ],
      finalizationSteps: const [],
    );
  }

  @override
  OperationRecoveryPlanSteps createSqliteOnly({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required bool destructive,
  }) => throw UnimplementedError();
}

PreparedOperationEnvelope _replacementEnvelope(
  _RecordingRecoveryPlans recoveryPlans,
) {
  final operationId = OperationId(_operationValue);
  final expected = RepositoryRevision(7);
  final committed = expected.next();
  return PreparedOperationEnvelope(
    operationId: operationId,
    expectedRepositoryRevision: expected,
    committedRepositoryRevision: committed,
    operationGeneration: committed.value,
    preparationSteps: recoveryPlans.createDestructiveEnvelope(
      operationId: operationId,
      expectedRepositoryRevision: expected,
      committedRepositoryRevision: committed,
    ),
    record: OperationRecordPlan(
      operationId: operationId,
      kind: WorkspaceOperationKind.replaceSource.name,
      subjects: const [],
      retainWithoutSubjects: true,
    ),
  );
}

final class _RecordingSubjectIdentities
    implements OperationSubjectIdentityPort {
  var calls = 0;

  @override
  String allocateOperationSubjectId() {
    calls += 1;
    return _subjectValue.replaceFirst(
      '000004',
      calls.toString().padLeft(6, '0'),
    );
  }
}
