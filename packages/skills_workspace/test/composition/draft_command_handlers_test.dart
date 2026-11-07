import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/drafts/draft_models.dart';
import 'package:skills_workspace/src/application/drafts/draft_plan_assembler.dart';
import 'package:skills_workspace/src/application/drafts/draft_planner.dart';
import 'package:skills_workspace/src/application/drafts/draft_ports.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/draft_command_handlers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../support/operations/operation_fakes.dart';

void main() {
  late _Fixture fixture;

  tearDown(() => fixture.close());

  test('Inspect Draft returns authoritative normalized dirty state', () async {
    fixture = await _Fixture.create(_snapshot(draft: _draft(false)));
    fixture.states.inspectResult = DraftPlanningSuccess<DraftSummary?>(
      _draft(true),
    );

    final result = await fixture.execute<DraftSummary?>(
      WorkspaceOperationKind.inspectDraft,
      InspectDraftRequest(managedSkillId: _skillId),
    );

    expect(result.valueOrNull?.isDirty, isTrue);
    expect(fixture.states.inspectCalls, 1);
  });

  test('Inspect Draft returns null without reading revision state', () async {
    fixture = await _Fixture.create(_snapshot());

    final result = await fixture.execute<DraftSummary?>(
      WorkspaceOperationKind.inspectDraft,
      InspectDraftRequest(managedSkillId: _skillId),
    );

    expect(result, isA<SkillsSuccess<DraftSummary?>>());
    expect(result.valueOrNull, isNull);
    expect(fixture.states.stateReads, 0);
  });

  test('Inspect Draft rejects a missing Skill', () async {
    fixture = await _Fixture.create(RepositorySnapshot.empty());

    final result = await fixture.execute<DraftSummary?>(
      WorkspaceOperationKind.inspectDraft,
      InspectDraftRequest(managedSkillId: _skillId),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.skillNotFound);
  });

  for (final entry in _draftFailureCodes.entries) {
    test('Inspect Draft maps ${entry.key.name}', () async {
      fixture = await _Fixture.create(_snapshot(draft: _draft(true)));
      fixture.states.inspectResult = DraftPlanningFailure<DraftSummary?>(
        code: entry.key,
        context: const <String, Object?>{'bounded': 'context'},
      );

      final result = await fixture.execute<DraftSummary?>(
        WorkspaceOperationKind.inspectDraft,
        InspectDraftRequest(managedSkillId: _skillId),
      );

      expect(result.failureOrNull?.code, entry.value);
      expect(result.failureOrNull?.context['bounded'], 'context');
      if (entry.key == DraftPlanningFailureCode.draftNotFound) {
        expect(result.failureOrNull?.context['reason'], 'draftNotFound');
      }
    });
  }

  test(
    'Ensure Draft returns an existing Draft as an unchanged no-op',
    () async {
      fixture = await _Fixture.create(_snapshot(draft: _draft(false)));
      fixture.states.inspectResult = DraftPlanningSuccess<DraftSummary?>(
        _draft(true),
      );

      final result = await fixture.execute<DraftSummary>(
        WorkspaceOperationKind.ensureDraft,
        EnsureDraftRequest(managedSkillId: _skillId),
      );

      expect(result.valueOrNull?.isDirty, isTrue);
      expect((result as SkillsSuccess<DraftSummary>).changed, isFalse);
      expect(fixture.operations.log.events, isEmpty);
    },
  );

  test('Ensure Draft commits and reloads the created Draft', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.reader.value = _snapshot(revision: 1, draft: _draft(false));

    final result = await fixture.execute<DraftSummary>(
      WorkspaceOperationKind.ensureDraft,
      EnsureDraftRequest(managedSkillId: _skillId),
    );

    expect(result.valueOrNull?.path, _draft(false).path);
    expect((result as SkillsSuccess<DraftSummary>).changed, isTrue);
    expect(fixture.businessCommits, 1);
    expect(fixture.progress, <OperationProgressPhase>[
      OperationProgressPhase.inspecting,
      OperationProgressPhase.committing,
      OperationProgressPhase.finalizing,
    ]);
  });

  test(
    'Ensure Draft maps candidate preparation rejection after rollback',
    () async {
      fixture = await _Fixture.create(_snapshot());
      fixture.revisions.ensureFailure = DraftPlanningFailureCode.ioFailure;

      final result = await fixture.execute<DraftSummary>(
        WorkspaceOperationKind.ensureDraft,
        EnsureDraftRequest(managedSkillId: _skillId),
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.ioFailure);
      expect(
        fixture.operations.log.events,
        containsAllInOrder(<String>[
          'control.prepared-envelope',
          'recovery.rollback-envelope',
          'control.envelope-rollback-complete',
        ]),
      );
    },
  );

  test('Ensure Draft maps invalid prepared evidence after rollback', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.revisions.invalidEnsureEvidence = true;

    final result = await fixture.execute<DraftSummary>(
      WorkspaceOperationKind.ensureDraft,
      EnsureDraftRequest(managedSkillId: _skillId),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.invalidSkill);
    expect(
      fixture.operations.log.events,
      contains('recovery.rollback-envelope'),
    );
  });

  test('Ensure Draft reports a stale Repository Revision', () async {
    fixture = await _Fixture.create(
      _snapshot(),
      coordinatorRevision: RepositoryRevision(1),
    );

    final result = await fixture.execute<DraftSummary>(
      WorkspaceOperationKind.ensureDraft,
      EnsureDraftRequest(managedSkillId: _skillId),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
    expect(result.failureOrNull?.context['actualRepositoryRevision'], 1);
  });

  test('Ensure Draft maps a pre-commit apply failure after rollback', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.operations.failures.failures.add('recovery.apply:apply');

    final result = await fixture.execute<DraftSummary>(
      WorkspaceOperationKind.ensureDraft,
      EnsureDraftRequest(managedSkillId: _skillId),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.operationFailed);
    expect(result.failureOrNull?.context['reason'], 'applyFailed');
  });

  test('Ensure Draft exposes rollback recovery failure', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.operations.failures.failures
      ..add('recovery.apply:apply')
      ..add('recovery.rollback');

    final result = await fixture.execute<DraftSummary>(
      WorkspaceOperationKind.ensureDraft,
      EnsureDraftRequest(managedSkillId: _skillId),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.recoveryFailed);
    expect(result.failureOrNull?.context['reason'], 'applyFailed');
  });

  test(
    'Ensure Draft preserves committed-pending finalization direction',
    () async {
      fixture = await _Fixture.create(_snapshot());
      fixture.reader.value = _snapshot(revision: 1, draft: _draft(false));
      fixture.operations.failures.failures.add('recovery.finalize:finalize');

      final result = await fixture.execute<DraftSummary>(
        WorkspaceOperationKind.ensureDraft,
        EnsureDraftRequest(managedSkillId: _skillId),
      );

      expect(result, isA<SkillsCommittedFinalizationPending<DraftSummary>>());
      expect(
        result.warnings.single.code,
        SkillsWarningCode.finalizationDeferred,
      );
      expect(fixture.reader.reads, 0);
    },
  );

  test(
    'Ensure Draft turns reload failure after completion into pending',
    () async {
      fixture = await _Fixture.create(_snapshot());
      fixture.reader.error = StateError('unreadable');

      final result = await fixture.execute<DraftSummary>(
        WorkspaceOperationKind.ensureDraft,
        EnsureDraftRequest(managedSkillId: _skillId),
      );

      expect(result, isA<SkillsCommittedFinalizationPending<DraftSummary>>());
      expect(
        result.warnings.single.code,
        SkillsWarningCode.finalizationDeferred,
      );
    },
  );

  test(
    'Ensure Draft reports deferred non-destructive cleanup as a warning',
    () async {
      fixture = await _Fixture.create(_snapshot());
      fixture.reader.value = _snapshot(revision: 1, draft: _draft(false));
      fixture.operations.failures.failures.add('recovery.cleanup');

      final result = await fixture.execute<DraftSummary>(
        WorkspaceOperationKind.ensureDraft,
        EnsureDraftRequest(managedSkillId: _skillId),
      );

      expect(result.valueOrNull, isNotNull);
      expect(
        result.warnings.single.code,
        SkillsWarningCode.recoveryCleanupDeferred,
      );
    },
  );

  test('Discard Draft commits the already-planned deletion', () async {
    fixture = await _Fixture.create(_snapshot(draft: _draft(true)));
    fixture.reader.value = _snapshot(revision: 1);

    final result = await fixture.execute<RepositorySnapshot>(
      WorkspaceOperationKind.discardDraft,
      DiscardDraftRequest(managedSkillId: _skillId),
    );

    expect(result.valueOrNull?.revision, RepositoryRevision(1));
    expect(fixture.plans.discardPlans, 1);
  });

  test('Discard Draft fails before Journal when no Draft exists', () async {
    fixture = await _Fixture.create(_snapshot());

    final result = await fixture.execute<RepositorySnapshot>(
      WorkspaceOperationKind.discardDraft,
      DiscardDraftRequest(managedSkillId: _skillId),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.invalidSkill);
    expect(result.failureOrNull?.context['reason'], 'draftNotFound');
    expect(fixture.operations.log.events, isEmpty);
  });

  test(
    'Publish Draft commits the prepared revision and affected Skill',
    () async {
      fixture = await _Fixture.create(_snapshot(draft: _draft(true)));
      fixture.reader.value = _snapshot(revision: 1);

      final result = await fixture.execute<MutationReport>(
        WorkspaceOperationKind.publishDraft,
        PublishDraftRequest(managedSkillId: _skillId),
      );

      expect(result.valueOrNull?.affectedSkillIds, <ManagedSkillId>{_skillId});
      expect(result.valueOrNull?.snapshot.revision, RepositoryRevision(1));
      expect(fixture.plans.publishPlans, 1);
    },
  );

  test('Publish Draft maps candidate preparation rejection', () async {
    fixture = await _Fixture.create(_snapshot(draft: _draft(true)));
    fixture.revisions.publishFailure =
        DraftPlanningFailureCode.draftChangedDuringPublish;

    final result = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.publishDraft,
      PublishDraftRequest(managedSkillId: _skillId),
    );

    expect(
      result.failureOrNull?.code,
      SkillsErrorCode.draftChangedDuringPublish,
    );
    expect(fixture.plans.publishPlans, 0);
  });

  test('Publish Draft maps invalid assembled evidence', () async {
    fixture = await _Fixture.create(_snapshot(draft: _draft(true)));
    fixture.revisions.invalidPublishEvidence = true;

    final result = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.publishDraft,
      PublishDraftRequest(managedSkillId: _skillId),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.invalidSkill);
    expect(
      fixture.operations.log.events,
      contains('recovery.rollback-envelope'),
    );
  });

  test('Publish Draft is blocked by an unresolved Update Candidate', () async {
    fixture = await _Fixture.create(
      _snapshot(draft: _draft(true), candidate: _candidate),
    );

    final result = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.publishDraft,
      PublishDraftRequest(managedSkillId: _skillId),
    );

    expect(
      result.failureOrNull?.code,
      SkillsErrorCode.updateCandidateResolutionRequired,
    );
    expect(fixture.operations.log.events, isEmpty);
  });
}

final class _Fixture {
  _Fixture._({
    required this.reader,
    required this.snapshots,
    required this.states,
    required this.revisions,
    required this.plans,
    required this.operations,
    required this.dispatcher,
  });

  static Future<_Fixture> create(
    RepositorySnapshot snapshot, {
    RepositoryRevision? coordinatorRevision,
  }) async {
    final reader = _Reader(snapshot);
    final snapshots = WorkspaceSnapshotPublisher(reader: reader);
    await snapshots.publishInitial(snapshot);
    final states = _States();
    final revisions = _Revisions();
    final plans = _Plans();
    final operations = OperationHarness(
      repositoryRevision: coordinatorRevision ?? snapshot.revision,
    );
    return _Fixture._(
      reader: reader,
      snapshots: snapshots,
      states: states,
      revisions: revisions,
      plans: plans,
      operations: operations,
      dispatcher: CompositeSkillsRepositoryCommandDispatcher(
        buildDraftCommandHandlers(
          snapshots: snapshots,
          operations: operations.createCoordinator(),
          drafts: DraftPlanner(states: states, clock: () => _now),
          assembler: const DraftPlanAssembler(),
          revisions: revisions,
          plans: plans,
        ),
      ),
    );
  }

  final _Reader reader;
  final WorkspaceSnapshotPublisher snapshots;
  final _States states;
  final _Revisions revisions;
  final _Plans plans;
  final OperationHarness operations;
  final CompositeSkillsRepositoryCommandDispatcher dispatcher;
  final List<OperationProgressPhase> progress = <OperationProgressPhase>[];
  var businessCommits = 0;

  Future<SkillsResult<T>> execute<T>(
    WorkspaceOperationKind kind,
    Object request,
  ) => dispatcher.execute<T>(
    operationId: _operationId,
    kind: kind,
    request: request,
    cancellationToken: CancellationToken.none(),
    markBusinessCommitted: () => businessCommits += 1,
    reportProgress: (phase, {currentItem, completed = 0, total}) {
      progress.add(phase);
    },
  );

  Future<void> close() => snapshots.close();
}

final class _States implements DraftWorkspaceStatePort {
  DraftRevisionState? state = _state;
  DraftPlanningResult<DraftSummary?> inspectResult =
      DraftPlanningSuccess<DraftSummary?>(_draft(true));
  var stateReads = 0;
  var inspectCalls = 0;

  @override
  Future<DraftRevisionState?> readDraftState(
    ManagedSkillId managedSkillId,
  ) async {
    stateReads += 1;
    return state;
  }

  @override
  Future<DraftPlanningResult<DraftSummary?>> inspectDraft({
    required ManagedSkill skill,
    required DraftRevisionState state,
    required CancellationToken cancellationToken,
  }) async {
    inspectCalls += 1;
    return inspectResult;
  }
}

final class _Revisions implements DraftRevisionPreparationPort {
  DraftPlanningFailureCode? ensureFailure;
  DraftPlanningFailureCode? publishFailure;
  bool invalidEnsureEvidence = false;
  bool invalidPublishEvidence = false;

  @override
  Future<DraftPlanningResult<PreparedEnsureDraft>> prepareEnsureDraft({
    required PreparedOperationEnvelope envelope,
    required EnsureDraftPreparationRequired preflight,
    required CancellationToken cancellationToken,
  }) async {
    if (ensureFailure case final code?) {
      return DraftPlanningFailure<PreparedEnsureDraft>(code: code);
    }
    return DraftPlanningSuccess<PreparedEnsureDraft>(
      PreparedEnsureDraft(
        managedSkillId: preflight.skill.id,
        sourceLineage: preflight.state.sourceLineage,
        baseObjectId: invalidEnsureEvidence
            ? RevisionObjectId('9' * 40)
            : preflight.state.currentEffective,
        draftRecoveryReference: RecoveryReference('draft'),
      ),
    );
  }

  @override
  Future<DraftPlanningResult<PreparedDraftPublish>> preparePublishDraft({
    required PreparedOperationEnvelope envelope,
    required PublishDraftPreparationRequired preflight,
    required CancellationToken cancellationToken,
  }) async {
    if (publishFailure case final code?) {
      return DraftPlanningFailure<PreparedDraftPublish>(code: code);
    }
    final tree = RevisionObjectId('3' * 40);
    return DraftPlanningSuccess<PreparedDraftPublish>(
      PreparedDraftPublish(
        managedSkillId: preflight.skill.id,
        sourceLineage: preflight.state.sourceLineage,
        treeObjectId: tree,
        effectiveObjectId: RevisionObjectId('4' * 40),
        effectiveRequest: RevisionCommitRequest(
          tree: tree,
          parents: <RevisionObjectId>[preflight.state.currentEffective],
          kind: RevisionCommitKind.localPublish,
        ),
        contentHash: 'b' * 64,
        fileCount: 1,
        byteSize: 2,
        declaredName: invalidPublishEvidence
            ? 'changed-name'
            : preflight.skill.declaredName,
        description: 'Published',
        draftAction: PublishedDraftAction.deleteUnchanged,
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
}

final class _Plans implements DraftOperationPlanPort {
  var discardPlans = 0;
  var publishPlans = 0;

  @override
  PreparedOperationEnvelope createEnsureEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required EnsureDraftPreparationRequired preflight,
  }) => _envelope(operationId, expectedRepositoryRevision, 'ensureDraft');

  @override
  OperationPlan sealEnsurePlan({
    required PreparedOperationEnvelope envelope,
    required EnsureDraftPreparationRequired preflight,
    required PreparedEnsureDraftPlan preparedPlan,
  }) => _sealed(envelope, preparedPlan.businessChanges);

  @override
  OperationPlan createDiscardPlan({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required DiscardDraftPlan plan,
  }) {
    discardPlans += 1;
    return _sealed(
      _envelope(operationId, expectedRepositoryRevision, 'discardDraft'),
      plan.businessChanges,
    );
  }

  @override
  PreparedOperationEnvelope createPublishEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required PublishDraftPreparationRequired preflight,
  }) => _envelope(operationId, expectedRepositoryRevision, 'publishDraft');

  @override
  OperationPlan sealPublishPlan({
    required PreparedOperationEnvelope envelope,
    required PublishDraftPreparationRequired preflight,
    required PreparedDraftPublishPlan preparedPlan,
  }) {
    publishPlans += 1;
    return _sealed(envelope, preparedPlan.businessChanges);
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
  operationGeneration: revision.next().value,
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

OperationPlan _sealed(
  PreparedOperationEnvelope envelope,
  WorkspaceBusinessChangeSet businessChanges,
) => OperationPlan(
  operationId: envelope.operationId,
  expectedRepositoryRevision: envelope.expectedRepositoryRevision,
  committedRepositoryRevision: envelope.committedRepositoryRevision,
  operationGeneration: envelope.operationGeneration,
  preparationSteps: envelope.preparationSteps,
  applyingSteps: <ApplyingOperationStep>[
    ApplyingOperationStep(
      stepId: 'apply',
      recoveryReference: RecoveryReference('apply'),
      kind: ApplyingStepKind.materializationReplacement,
    ),
  ],
  finalizationSteps: <FinalizationOperationStep>[
    FinalizationOperationStep(
      stepId: 'finalize',
      recoveryReference: RecoveryReference('finalize'),
      kind: FinalizationStepKind.materializationVerification,
    ),
  ],
  revisionSelectionChanges: const <RevisionSelectionChangePlan>[],
  businessChanges: businessChanges,
  record: envelope.record,
);

final class _Reader implements WorkspaceSnapshotReaderPort {
  _Reader(this.value);

  RepositorySnapshot value;
  Object? error;
  var reads = 0;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async {
    reads += 1;
    if (error case final failure?) throw failure;
    return value;
  }
}

final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _operationId = OperationId('123e4567-e89b-42d3-8456-426614174001');
final _lineage = SourceLineageReference('lineage-1');
final _now = DateTime.utc(2026, 8, 17);
final _candidate = UpdateCandidateSummary(
  status: UpdateCandidateStatus.validationFailed,
  conflicts: const <UpdateConflict>[],
  validationCode: 'invalid',
  createdAt: _now,
);
final _state = DraftRevisionState(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  currentUpstream: RevisionObjectId('1' * 40),
  currentEffective: RevisionObjectId('2' * 40),
  managedSkillCreatedAtMicros: 1,
  draftCreatedAtMicros: 2,
);

RepositorySnapshot _snapshot({
  int revision = 0,
  DraftSummary? draft,
  UpdateCandidateSummary? candidate,
}) => RepositorySnapshot(
  revision: RepositoryRevision(revision),
  managedSkills: <ManagedSkill>[
    ManagedSkill(
      id: _skillId,
      slotKey: 'one',
      declaredName: 'one',
      displayName: 'One',
      description: 'One',
      source: LocalSourceDescriptor(locator: '/source/one'),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        publishedAt: DateTime.utc(2026, 8, 1),
      ),
      draft: draft,
      updateCandidate: candidate,
    ),
  ],
);

DraftSummary _draft(bool dirty) => DraftSummary(
  purpose: DraftPurpose.customization,
  path: '/drafts/${_skillId.value}',
  isDirty: dirty,
  updatedAt: _now,
);

const _draftFailureCodes = <DraftPlanningFailureCode, SkillsErrorCode>{
  DraftPlanningFailureCode.operationCancelled:
      SkillsErrorCode.operationCancelled,
  DraftPlanningFailureCode.skillNotFound: SkillsErrorCode.skillNotFound,
  DraftPlanningFailureCode.draftNotFound: SkillsErrorCode.invalidSkill,
  DraftPlanningFailureCode.updateCandidateResolutionRequired:
      SkillsErrorCode.updateCandidateResolutionRequired,
  DraftPlanningFailureCode.draftChangedDuringPublish:
      SkillsErrorCode.draftChangedDuringPublish,
  DraftPlanningFailureCode.declaredNameChangeNotAllowed:
      SkillsErrorCode.declaredNameChangeNotAllowed,
  DraftPlanningFailureCode.invalidSkill: SkillsErrorCode.invalidSkill,
  DraftPlanningFailureCode.revisionStateUnavailable:
      SkillsErrorCode.invalidSkill,
  DraftPlanningFailureCode.revisionStoreUnavailable:
      SkillsErrorCode.revisionStoreCorrupt,
  DraftPlanningFailureCode.recoveryEvidenceFailed: SkillsErrorCode.invalidSkill,
  DraftPlanningFailureCode.ioFailure: SkillsErrorCode.ioFailure,
  DraftPlanningFailureCode.invalidPreparedEvidence:
      SkillsErrorCode.invalidSkill,
};
