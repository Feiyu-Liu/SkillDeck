import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/update_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_coordinator.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/application/update/update_command_ports.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/application/update/update_planner.dart';
import 'package:skills_workspace/src/composition/update_command_handlers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../support/operations/operation_fakes.dart';
import '../support/source/source_acquisition_fakes.dart';
import '../support/update/update_fakes.dart';

void main() {
  late OperationHarness operations;
  late _SnapshotReader reader;
  late WorkspaceSnapshotPublisher snapshots;
  late _RevisionPreparation revisions;
  late RecordingUpdateCandidateStateReader candidateStates;
  late FakeSourceAcquisitionPorts sources;
  late SourceDescriptor acquiredCanonicalSource;
  late SourceDescriptor acquiredSkillProvenance;
  late CompositeSkillsRepositoryCommandDispatcher dispatcher;

  setUp(() async {
    operations = OperationHarness();
    reader = _SnapshotReader(_snapshot());
    snapshots = WorkspaceSnapshotPublisher(reader: reader);
    await snapshots.publishInitial(reader.value);
    reader.value = _snapshot(revision: 1, hash: 'c');
    revisions = _RevisionPreparation(operations.log);
    acquiredCanonicalSource = _localSource();
    acquiredSkillProvenance = _localSource();
    sources = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionSuccess<AcquiredSource>(
            value: AcquiredSource(
              canonicalSource: acquiredCanonicalSource,
              skills: <AcquiredSourceSkill>[_incoming(acquiredSkillProvenance)],
            ),
          ),
    );
    final planner = UpdatePlanner(
      sourceAcquisition: SourceAcquisitionCoordinator(
        local: sources,
        git: sources,
        wellKnown: sources,
      ),
      drafts: RecordingUpdateDraftInspector(),
      states: RecordingUpdateRevisionStateReader(_state()),
      slotMigrations: RecordingSlotMigrationInspector(),
      clock: () => DateTime.utc(2026, 8, 17),
    );
    candidateStates = RecordingUpdateCandidateStateReader(null);
    final candidatePlanner = UpdateCandidatePlanner(
      states: candidateStates,
      slotMigrations: RecordingSlotMigrationInspector(),
      clock: () => DateTime.utc(2026, 8, 17),
    );
    dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      buildUpdateCommandHandlers(
        snapshots: snapshots,
        operations: operations.createCoordinator(),
        updates: planner,
        candidates: candidatePlanner,
        assembler: const UpdatePlanAssembler(),
        revisions: revisions,
        plans: const _UpdatePlans(),
      ),
    );
  });

  tearDown(() => snapshots.close());

  test('Update journals its envelope before revision candidate work', () async {
    final result = await dispatcher.execute<MutationReport>(
      operationId: _operationId,
      kind: WorkspaceOperationKind.update,
      request: UpdateRequest(managedSkillIds: <ManagedSkillId>{_skillId}),
      cancellationToken: CancellationToken.none(),
      markBusinessCommitted: () {},
      reportProgress: (phase, {currentItem, completed = 0, total}) {},
    );

    expect(result, isA<SkillsSuccess<MutationReport>>());
    final journalIndex = operations.log.events.indexOf(
      'control.prepared-envelope',
    );
    final preparationIndex = operations.log.events.indexOf('revision.prepare');
    expect(journalIndex, greaterThanOrEqualTo(0));
    expect(preparationIndex, greaterThan(journalIndex));
    expect(operations.log.events, contains('control.seal-plan'));
    expect(result.valueOrNull?.affectedSkillIds, <ManagedSkillId>{_skillId});
  });

  test(
    'Source continuity failure stops before Journal and mutation work',
    () async {
      acquiredCanonicalSource = LocalSourceDescriptor(
        locator: '/different-source',
        skillPath: 'one',
      );

      final result = await dispatcher.execute<MutationReport>(
        operationId: _operationId,
        kind: WorkspaceOperationKind.update,
        request: UpdateRequest(managedSkillIds: <ManagedSkillId>{_skillId}),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.sourceUnavailable);
      expect(result.failureOrNull?.context, <String, Object?>{
        'reason': 'canonicalSourceIdentityChanged',
      });
      expect(sources.calls, hasLength(1));
      expect(operations.log.events, isEmpty);
      expect(operations.controlPlane.journals, isEmpty);
      expect(operations.controlPlane.repositoryRevision.value, 0);
      expect(snapshots.current.revision.value, 0);
    },
  );

  test(
    'selected-Skill identity failure also stops before Journal and mutation',
    () async {
      acquiredSkillProvenance = LocalSourceDescriptor(
        locator: '/unrelated-source',
        skillPath: 'one',
      );

      final result = await dispatcher.execute<MutationReport>(
        operationId: _operationId,
        kind: WorkspaceOperationKind.update,
        request: UpdateRequest(managedSkillIds: <ManagedSkillId>{_skillId}),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.sourceUnavailable);
      expect(result.failureOrNull?.context, <String, Object?>{
        'reason': 'selectedSkillIdentityChanged',
        'matchingSelectionCount': 0,
      });
      expect(sources.calls, hasLength(1));
      expect(operations.log.events, isEmpty);
      expect(operations.controlPlane.journals, isEmpty);
      expect(operations.controlPlane.repositoryRevision.value, 0);
      expect(snapshots.current.revision.value, 0);
    },
  );

  test(
    'candidate preparation failure rolls back and preserves typed cause',
    () async {
      revisions.failure = UpdateRevisionPreparationFailureCode.invalidSkill;

      final result = await dispatcher.execute<MutationReport>(
        operationId: _operationId,
        kind: WorkspaceOperationKind.update,
        request: UpdateRequest(managedSkillIds: <ManagedSkillId>{_skillId}),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.invalidSkill);
      expect(operations.log.events, contains('recovery.rollback-envelope'));
      expect(operations.log.events, isNot(contains('control.commit')));
    },
  );

  test(
    'pre-cancelled Update stops before Source acquisition or Journal',
    () async {
      final cancellation = CancellationSource();
      await cancellation.cancel();

      final result = await dispatcher.execute<MutationReport>(
        operationId: _operationId,
        kind: WorkspaceOperationKind.update,
        request: UpdateRequest(managedSkillIds: <ManagedSkillId>{_skillId}),
        cancellationToken: cancellation.token,
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
      expect(sources.calls, isEmpty);
      expect(operations.controlPlane.journals, isEmpty);
      expect(operations.log.events, isEmpty);
    },
  );

  test(
    'stale Update fails before its Prepared envelope or candidate',
    () async {
      operations.controlPlane.repositoryRevision = RepositoryRevision(1);

      final result = await dispatcher.execute<MutationReport>(
        operationId: _operationId,
        kind: WorkspaceOperationKind.update,
        request: UpdateRequest(managedSkillIds: <ManagedSkillId>{_skillId}),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
      expect(operations.controlPlane.journals, isEmpty);
      expect(
        operations.log.events,
        isNot(contains('control.prepared-envelope')),
      );
      expect(operations.log.events, isNot(contains('revision.prepare')));
    },
  );

  test(
    'explicit conflict resolution commits and reloads typed state',
    () async {
      candidateStates.state = _candidateState();
      reader.value = _snapshot(candidate: _candidateSummary(resolved: false));
      await snapshots.reload();
      reader.value = _snapshot(
        revision: 1,
        candidate: _candidateSummary(resolved: true),
      );

      final result = await dispatcher.execute<RepositorySnapshot>(
        operationId: _operationId,
        kind: WorkspaceOperationKind.resolveUpdateConflict,
        request: ResolveUpdateConflictRequest(
          managedSkillId: _skillId,
          path: 'SKILL.md',
          resolutionState: UpdateConflictResolutionState.resolved,
        ),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(result, isA<SkillsSuccess<RepositorySnapshot>>());
      expect(
        result.valueOrNull
            ?.findSkill(_skillId)
            ?.updateCandidate
            ?.conflicts
            .single
            .resolutionState,
        UpdateConflictResolutionState.resolved,
      );
      expect(operations.log.events, contains('control.commit'));
    },
  );

  test(
    'Publish Update Candidate journals before preparation and reloads',
    () async {
      candidateStates.state = _candidateState(resolved: true);
      reader.value = _snapshot(candidate: _candidateSummary(resolved: true));
      await snapshots.reload();
      reader.value = _snapshot(revision: 1);

      final result = await dispatcher.execute<MutationReport>(
        operationId: _operationId,
        kind: WorkspaceOperationKind.publishUpdateCandidate,
        request: PublishUpdateCandidateRequest(managedSkillId: _skillId),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(result, isA<SkillsSuccess<MutationReport>>());
      expect(result.valueOrNull?.affectedSkillIds, <ManagedSkillId>{_skillId});
      expect(
        operations.log.events.indexOf('revision.prepare-candidate'),
        greaterThan(operations.log.events.indexOf('control.prepared-envelope')),
      );
      expect(operations.log.events, contains('control.seal-plan'));
    },
  );

  test(
    'Publish Update Candidate preserves a typed preparation failure',
    () async {
      candidateStates.state = _candidateState(resolved: true);
      reader.value = _snapshot(candidate: _candidateSummary(resolved: true));
      await snapshots.reload();
      revisions.candidateFailure =
          UpdateRevisionPreparationFailureCode.draftChangedDuringPublish;

      final result = await dispatcher.execute<MutationReport>(
        operationId: _operationId,
        kind: WorkspaceOperationKind.publishUpdateCandidate,
        request: PublishUpdateCandidateRequest(managedSkillId: _skillId),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(
        result.failureOrNull?.code,
        SkillsErrorCode.draftChangedDuringPublish,
      );
      expect(operations.log.events, contains('recovery.rollback-envelope'));
      expect(operations.log.events, isNot(contains('control.commit')));
    },
  );

  test(
    'pre-cancelled candidate Publish stops before state or Journal',
    () async {
      candidateStates.state = _candidateState(resolved: true);
      reader.value = _snapshot(candidate: _candidateSummary(resolved: true));
      await snapshots.reload();
      final cancellation = CancellationSource();
      await cancellation.cancel();

      final result = await dispatcher.execute<MutationReport>(
        operationId: _operationId,
        kind: WorkspaceOperationKind.publishUpdateCandidate,
        request: PublishUpdateCandidateRequest(managedSkillId: _skillId),
        cancellationToken: cancellation.token,
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
      expect(candidateStates.calls, 0);
      expect(operations.controlPlane.journals, isEmpty);
    },
  );

  test('stale candidate Publish fails before revision preparation', () async {
    candidateStates.state = _candidateState(resolved: true);
    reader.value = _snapshot(candidate: _candidateSummary(resolved: true));
    await snapshots.reload();
    operations.controlPlane.repositoryRevision = RepositoryRevision(1);

    final result = await dispatcher.execute<MutationReport>(
      operationId: _operationId,
      kind: WorkspaceOperationKind.publishUpdateCandidate,
      request: PublishUpdateCandidateRequest(managedSkillId: _skillId),
      cancellationToken: CancellationToken.none(),
      markBusinessCommitted: () {},
      reportProgress: (phase, {currentItem, completed = 0, total}) {},
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
    expect(operations.controlPlane.journals, isEmpty);
    expect(
      operations.log.events,
      isNot(contains('revision.prepare-candidate')),
    );
  });

  test('Abandon Update Candidate commits the Session cleanup plan', () async {
    candidateStates.state = _candidateState();
    reader.value = _snapshot(candidate: _candidateSummary(resolved: false));
    await snapshots.reload();
    reader.value = _snapshot(revision: 1);

    final result = await dispatcher.execute<RepositorySnapshot>(
      operationId: _operationId,
      kind: WorkspaceOperationKind.abandonUpdateCandidate,
      request: AbandonUpdateCandidateRequest(managedSkillId: _skillId),
      cancellationToken: CancellationToken.none(),
      markBusinessCommitted: () {},
      reportProgress: (phase, {currentItem, completed = 0, total}) {},
    );

    expect(result, isA<SkillsSuccess<RepositorySnapshot>>());
    expect(operations.log.events, contains('control.commit'));
    expect(
      operations.log.events.indexOf('revision.prepare-abandon'),
      greaterThan(operations.log.events.indexOf('control.prepared-envelope')),
    );
  });

  test('pre-cancelled candidate Abandon never creates a Journal', () async {
    candidateStates.state = _candidateState();
    reader.value = _snapshot(candidate: _candidateSummary(resolved: false));
    await snapshots.reload();
    final cancellation = CancellationSource();
    await cancellation.cancel();

    final result = await dispatcher.execute<RepositorySnapshot>(
      operationId: _operationId,
      kind: WorkspaceOperationKind.abandonUpdateCandidate,
      request: AbandonUpdateCandidateRequest(managedSkillId: _skillId),
      cancellationToken: cancellation.token,
      markBusinessCommitted: () {},
      reportProgress: (phase, {currentItem, completed = 0, total}) {},
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
    expect(candidateStates.calls, 0);
    expect(operations.controlPlane.journals, isEmpty);
  });
}

final class _RevisionPreparation implements UpdateRevisionPreparationPort {
  _RevisionPreparation(this.log);

  final OperationEventLog log;
  UpdateRevisionPreparationFailureCode? failure;
  UpdateRevisionPreparationFailureCode? candidateFailure;

  @override
  Future<UpdateRevisionPreparationResult> prepareUpdate({
    required OperationId operationId,
    required UpdateRevisionPreparationIntent intent,
    required CancellationToken cancellationToken,
  }) async {
    log.add('revision.prepare');
    if (failure case final code?) {
      return UpdateRevisionPreparationFailure(code);
    }
    return UpdateRevisionPreparationSuccess(
      PreparedUpdateRevision(
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        incomingTreeObjectId: _object('3'),
        incomingUpstreamObjectId: _object('4'),
        incomingRequest: RevisionCommitRequest(
          tree: _object('3'),
          parents: <RevisionObjectId>[_object('1')],
          kind: RevisionCommitKind.upstream,
        ),
        outcome: PreparedUpdateClean(
          effectiveObjectId: _object('6'),
          mergedTreeObjectId: _object('5'),
          effectiveRequest: RevisionCommitRequest(
            tree: _object('5'),
            parents: <RevisionObjectId>[_object('2'), _object('4')],
            kind: RevisionCommitKind.effectiveUpdate,
          ),
          mergedTree: _tree('c'),
          declaredName: 'one',
          description: 'Incoming',
          draftDisposition: UpdateDraftDisposition.noDraft,
          capturedDraftFingerprint: null,
        ),
        candidateRecoveryReference: RecoveryReference('candidate'),
        bundleRecoveryReference: RecoveryReference('bundle'),
        materializationRecoveryReference: RecoveryReference('materialization'),
        draftRecoveryReference: RecoveryReference('draft'),
      ),
    );
  }

  @override
  Future<UpdateCandidatePublishPreparationResult> prepareCandidatePublish({
    required OperationId operationId,
    required UpdateCandidatePublishPreparationIntent intent,
    required CancellationToken cancellationToken,
  }) async {
    log.add('revision.prepare-candidate');
    if (candidateFailure case final code?) {
      return UpdateCandidatePublishPreparationFailure(code);
    }
    return UpdateCandidatePublishPreparationSuccess(
      PreparedUpdateCandidatePublish(
        managedSkillId: intent.managedSkillId,
        sourceLineage: intent.sourceLineage,
        effectiveObjectId: _object('6'),
        publishedTreeObjectId: _object('5'),
        effectiveRequest: RevisionCommitRequest(
          tree: _object('5'),
          parents: <RevisionObjectId>[
            intent.previousEffective,
            intent.incomingUpstream,
          ],
          kind: RevisionCommitKind.effectiveUpdate,
        ),
        publishedTree: _tree('c'),
        declaredName: intent.requiredDeclaredName,
        description: intent.incomingDescription,
        draftDisposition: UpdateDraftDisposition.deleteUnchanged,
        capturedDraftFingerprint: DraftFingerprint(
          const <DraftEntryEvidence>[],
        ),
        candidateRecoveryReference: RecoveryReference('candidate'),
        bundleRecoveryReference: RecoveryReference('bundle'),
        materializationRecoveryReference: RecoveryReference('materialization'),
        draftRecoveryReference: RecoveryReference('draft'),
      ),
    );
  }

  @override
  Future<UpdateCandidateAbandonPreparationResult> prepareCandidateAbandon({
    required OperationId operationId,
    required UpdateCandidateCleanupIntent intent,
    required CancellationToken cancellationToken,
  }) async {
    log.add('revision.prepare-abandon');
    return UpdateCandidateAbandonPreparationSuccess(
      PreparedUpdateCandidateAbandon(
        managedSkillId: intent.managedSkillId,
        sourceLineage: intent.sourceLineage,
        retainedPublishedRoots: intent.retainedPublishedRoots,
        bundleRecoveryReference: RecoveryReference('bundle'),
      ),
    );
  }
}

final class _UpdatePlans implements UpdateOperationPlanPort {
  const _UpdatePlans();

  @override
  PreparedOperationEnvelope createUpdateEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required List<UpdatePreparationRequired> preflights,
  }) => _envelope(operationId, expectedRepositoryRevision, 'update');

  @override
  OperationPlan sealUpdatePlan({
    required PreparedOperationEnvelope envelope,
    required List<UpdatePreparationRequired> preflights,
    required List<PreparedUpdatePlan> preparedPlans,
  }) => _sealed(envelope, 'update');

  @override
  PreparedOperationEnvelope createCandidatePublishEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required UpdateCandidatePublishPreflight preflight,
  }) => _envelope(operationId, expectedRepositoryRevision, 'candidate');

  @override
  OperationPlan sealCandidatePublishPlan({
    required PreparedOperationEnvelope envelope,
    required UpdateCandidatePublishPreflight preflight,
    required PreparedUpdatePlan preparedPlan,
  }) => _sealed(envelope, 'candidate');

  @override
  PreparedOperationEnvelope createCandidateAbandonEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required UpdateCandidateAbandonPlan abandonPlan,
  }) => _envelope(operationId, expectedRepositoryRevision, 'abandon');

  @override
  OperationPlan sealCandidateAbandonPlan({
    required PreparedOperationEnvelope envelope,
    required UpdateCandidateAbandonPlan abandonPlan,
    required PreparedUpdateCandidateAbandon prepared,
  }) => _sealed(envelope, 'abandon');

  @override
  OperationPlan createConflictResolutionPlan({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required ManagedSkillId managedSkillId,
    required UpdateConflictResolutionPlan resolutionPlan,
  }) {
    final envelope = _envelope(
      operationId,
      expectedRepositoryRevision,
      'resolve-conflict',
    );
    return OperationPlan(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      committedRepositoryRevision: envelope.committedRepositoryRevision,
      operationGeneration: envelope.operationGeneration,
      preparationSteps: envelope.preparationSteps,
      applyingSteps: const <ApplyingOperationStep>[],
      finalizationSteps: const <FinalizationOperationStep>[],
      revisionSelectionChanges: const <RevisionSelectionChangePlan>[],
      businessChanges: resolutionPlan.businessChanges,
      record: envelope.record,
    );
  }
}

PreparedOperationEnvelope _envelope(
  OperationId operationId,
  RepositoryRevision revision,
  String kind,
) => PreparedOperationEnvelope(
  operationId: operationId,
  expectedRepositoryRevision: revision,
  committedRepositoryRevision: revision.next(),
  operationGeneration: 1,
  preparationSteps: <PreparationOperationStep>[
    PreparationOperationStep(
      stepId: 'candidate',
      recoveryReference: RecoveryReference('candidate'),
      kind: PreparationStepKind.revisionCandidate,
    ),
  ],
  record: OperationRecordPlan(
    operationId: operationId,
    kind: kind,
    subjects: const <OperationSubjectPlan>[],
    retainWithoutSubjects: true,
  ),
);

OperationPlan _sealed(PreparedOperationEnvelope envelope, String kind) =>
    OperationPlan(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      committedRepositoryRevision: envelope.committedRepositoryRevision,
      operationGeneration: envelope.operationGeneration,
      preparationSteps: envelope.preparationSteps,
      applyingSteps: const <ApplyingOperationStep>[],
      finalizationSteps: const <FinalizationOperationStep>[],
      revisionSelectionChanges: const <RevisionSelectionChangePlan>[],
      businessChanges: WorkspaceBusinessChangeSet.empty,
      record: OperationRecordPlan(
        operationId: envelope.operationId,
        kind: kind,
        subjects: const <OperationSubjectPlan>[],
        retainWithoutSubjects: true,
      ),
    );

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  _SnapshotReader(this.value);

  RepositorySnapshot value;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      value;
}

const _skillValue = '123e4567-e89b-42d3-a456-426614174000';
final _skillId = ManagedSkillId(_skillValue);
final _operationId = OperationId('123e4567-e89b-42d3-8456-426614174001');
final _lineage = SourceLineageReference('lineage-1');

RepositorySnapshot _snapshot({
  int revision = 0,
  String hash = 'a',
  UpdateCandidateSummary? candidate,
}) => RepositorySnapshot(
  revision: RepositoryRevision(revision),
  managedSkills: <ManagedSkill>[
    ManagedSkill(
      id: _skillId,
      slotKey: 'one',
      declaredName: 'one',
      displayName: 'One',
      description: 'Old',
      source: _localSource(),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: hash * 64,
        fileCount: 1,
        byteSize: 1,
        publishedAt: DateTime.utc(2026, 8, 1),
      ),
      draft: candidate == null
          ? null
          : DraftSummary(
              purpose: DraftPurpose.updateCandidateResolution,
              path: '/drafts/$_skillValue',
              isDirty: true,
              updatedAt: DateTime.utc(2026, 8, 17),
            ),
      updateCandidate: candidate,
    ),
  ],
);

UpdateRevisionState _state() => UpdateRevisionState(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  previousUpstream: _object('1'),
  currentEffective: _object('2'),
  previousUpstreamContentHash: 'a' * 64,
  managedSkillCreatedAtMicros: 1,
  draftCreatedAtMicros: null,
);

UpdateCandidateState _candidateState({bool resolved = false}) =>
    UpdateCandidateState(
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      previousUpstream: _object('1'),
      previousEffective: _object('2'),
      incomingUpstream: _object('4'),
      candidateObjectId: _object('5'),
      incomingDeclaredName: 'one',
      incomingSlotKey: 'one',
      incomingDescription: 'Incoming',
      managedSkillCreatedAtMicros: 1,
      draftCreatedAtMicros: 2,
      retainedPublishedRoots: <RevisionObjectId>[_object('1'), _object('2')],
      conflicts: <WorkspaceUpdateCandidateItem>[
        WorkspaceUpdateCandidateItem(
          path: 'SKILL.md',
          kind: WorkspaceUpdateCandidateItemKind.text,
          state: resolved
              ? WorkspaceUpdateCandidateItemState.resolved
              : WorkspaceUpdateCandidateItemState.unresolved,
          baseObjectId: null,
          oursObjectId: null,
          theirsObjectId: null,
        ),
      ],
    );

UpdateCandidateSummary _candidateSummary({required bool resolved}) =>
    UpdateCandidateSummary(
      status: UpdateCandidateStatus.conflicted,
      conflicts: <UpdateConflict>[
        UpdateConflict(
          path: 'SKILL.md',
          kind: ConflictKind.text,
          resolutionState: resolved
              ? UpdateConflictResolutionState.resolved
              : UpdateConflictResolutionState.unresolved,
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 17),
    );

AcquiredSourceSkill _incoming(SourceDescriptor source) => AcquiredSourceSkill(
  provenance: source,
  declaredName: 'one',
  description: 'Incoming',
  slotKey: 'one',
  skillPath: 'one',
  frontmatter: const <String, Object?>{'name': 'one'},
  tree: _tree('b'),
);

NormalizedSkillTree _tree(String character) => NormalizedSkillTree(
  files: <NormalizedSkillFile>[
    NormalizedSkillFile(
      relativePath: 'SKILL.md',
      bytes: const <int>[1],
      isExecutable: false,
    ),
  ],
  contentHash: character * 64,
  byteSize: 1,
);

RevisionObjectId _object(String character) => RevisionObjectId(character * 40);

LocalSourceDescriptor _localSource() =>
    LocalSourceDescriptor(locator: '/source', skillPath: 'one');
