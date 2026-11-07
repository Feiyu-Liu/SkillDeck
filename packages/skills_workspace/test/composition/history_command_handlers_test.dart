import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/history/history_ports.dart';
import 'package:skills_workspace/src/application/history/history_service.dart';
import 'package:skills_workspace/src/application/history/restore_plan_assembler.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/history_command_handlers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../support/operations/operation_fakes.dart';

void main() {
  late OperationHarness operations;
  late _SnapshotReader reader;
  late WorkspaceSnapshotPublisher snapshots;
  late _HistoryContent content;
  late _RestorePreparation revisions;
  late _RestorePlans plans;
  late CompositeSkillsRepositoryCommandDispatcher dispatcher;

  setUp(() async {
    operations = OperationHarness();
    reader = _SnapshotReader(_snapshot());
    snapshots = WorkspaceSnapshotPublisher(reader: reader);
    await snapshots.publishInitial(reader.value);
    content = _HistoryContent();
    revisions = _RestorePreparation();
    plans = _RestorePlans();
    dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      buildHistoryCommandHandlers(
        snapshots: snapshots,
        history: WorkspaceHistoryService(content: content, clock: () => _now),
        assembler: const RestorePlanAssembler(),
        operations: operations.createCoordinator(),
        revisions: revisions,
        plans: plans,
      ),
    );
  });

  tearDown(() => snapshots.close());

  test(
    'Inspect Diff returns the immutable read result without mutation',
    () async {
      final progress = <OperationProgressPhase>[];

      final result = await _execute<SkillDiff>(
        dispatcher,
        WorkspaceOperationKind.inspectDiff,
        InspectDiffRequest(
          managedSkillId: _skillId,
          from: _fromReference,
          to: _selectedReference,
        ),
        reportProgress: progress.add,
      );

      expect(result, isA<SkillsSuccess<SkillDiff>>());
      expect(result.valueOrNull, content.diff);
      expect((result as SkillsSuccess<SkillDiff>).changed, isFalse);
      expect(progress, <OperationProgressPhase>[
        OperationProgressPhase.inspecting,
      ]);
      expect(operations.log.events, isEmpty);
    },
  );

  test('history failures retain stable public error-code mappings', () async {
    const expected = <HistoryFailureCode, SkillsErrorCode>{
      HistoryFailureCode.operationCancelled: SkillsErrorCode.operationCancelled,
      HistoryFailureCode.skillNotFound: SkillsErrorCode.skillNotFound,
      HistoryFailureCode.historicalRevisionNotFound:
          SkillsErrorCode.invalidSkill,
      HistoryFailureCode.historicalRevisionOutsideCurrentLineage:
          SkillsErrorCode.invalidSkill,
      HistoryFailureCode.updateCandidateResolutionRequired:
          SkillsErrorCode.updateCandidateResolutionRequired,
      HistoryFailureCode.dirtyDraftResolutionRequired:
          SkillsErrorCode.dirtyDraftResolutionRequired,
      HistoryFailureCode.draftInspectionFailed: SkillsErrorCode.invalidSkill,
      HistoryFailureCode.historicalNameMismatch:
          SkillsErrorCode.historicalNameMismatch,
      HistoryFailureCode.invalidSkill: SkillsErrorCode.invalidSkill,
      HistoryFailureCode.revisionStateUnavailable: SkillsErrorCode.invalidSkill,
      HistoryFailureCode.revisionStoreUnavailable:
          SkillsErrorCode.revisionStoreCorrupt,
      HistoryFailureCode.recoveryEvidenceFailed: SkillsErrorCode.invalidSkill,
      HistoryFailureCode.ioFailure: SkillsErrorCode.ioFailure,
      HistoryFailureCode.invalidPreparedEvidence: SkillsErrorCode.invalidSkill,
    };

    for (final entry in expected.entries) {
      content.compareResult = HistoryFailure<SkillDiff>(
        code: entry.key,
        context: <String, Object?>{'case': entry.key.name},
      );

      final result = await _execute<SkillDiff>(
        dispatcher,
        WorkspaceOperationKind.inspectDiff,
        InspectDiffRequest(managedSkillId: _skillId, to: _selectedReference),
      );

      expect(result.failureOrNull?.code, entry.value, reason: entry.key.name);
      expect(result.failureOrNull?.context['case'], entry.key.name);
    }
  });

  test('Restore Publish commits, reloads, and reports progress', () async {
    reader.value = _snapshot(revision: 1);
    final progress = <OperationProgressPhase>[];
    var committed = false;

    final result = await _restore(
      dispatcher,
      markBusinessCommitted: () => committed = true,
      reportProgress: progress.add,
    );

    expect(result, isA<SkillsSuccess<MutationReport>>());
    expect(result.valueOrNull?.snapshot, reader.value);
    expect(result.valueOrNull?.affectedSkillIds, <ManagedSkillId>{_skillId});
    expect(committed, isTrue);
    expect(
      progress,
      containsAllInOrder(<OperationProgressPhase>[
        OperationProgressPhase.inspecting,
        OperationProgressPhase.committing,
        OperationProgressPhase.finalizing,
      ]),
    );
  });

  test(
    'cleanup failure keeps success and exposes a recovery warning',
    () async {
      operations.failures.failures.add('recovery.cleanup');
      reader.value = _snapshot(revision: 1);

      final result = await _restore(dispatcher);

      expect(result, isA<SkillsSuccess<MutationReport>>());
      expect(
        result.warnings.single.code,
        SkillsWarningCode.recoveryCleanupDeferred,
      );
    },
  );

  test('reload failure reports the already committed operation', () async {
    reader.throwOnRead = true;

    final result = await _restore(dispatcher);

    expect(result, isA<SkillsCommittedFinalizationPending<MutationReport>>());
    expect(result.isCommittedFinalizationPending, isTrue);
    final pending =
        result as SkillsCommittedFinalizationPending<MutationReport>;
    expect(pending.operationId, _operationId);
    expect(pending.committedRepositoryRevision, RepositoryRevision(1));
    expect(result.warnings.single.code, SkillsWarningCode.finalizationDeferred);
  });

  test('post-BCP finalization failure reports committed pending', () async {
    operations.failures.failures.add('recovery.finalize:finalize');

    final result = await _restore(dispatcher);

    expect(result.isCommittedFinalizationPending, isTrue);
    expect(result.warnings.single.code, SkillsWarningCode.finalizationDeferred);
  });

  test(
    'revision preparation failure rolls back and preserves its code',
    () async {
      revisions.result = HistoryFailure<PreparedRestorePublish>(
        code: HistoryFailureCode.revisionStoreUnavailable,
        context: const <String, Object?>{'stage': 'prepare'},
      );

      final result = await _restore(dispatcher);

      expect(result.failureOrNull?.code, SkillsErrorCode.revisionStoreCorrupt);
      expect(result.failureOrNull?.context['stage'], 'prepare');
      expect(operations.log.events, contains('recovery.rollback-envelope'));
    },
  );

  test('invalid prepared evidence is rejected before applying', () async {
    revisions.result = HistorySuccess<PreparedRestorePublish>(
      _preparedRestore(contentHash: _otherHash),
    );

    final result = await _restore(dispatcher);

    expect(result.failureOrNull?.code, SkillsErrorCode.invalidSkill);
    expect(operations.log.events, isNot(contains('control.applying')));
  });

  test('operation abort reasons map to stable public failures', () async {
    Future<void> verify(
      SkillsErrorCode expected, {
      String? failureEvent,
      void Function()? configure,
      CancellationToken? token,
    }) async {
      configure?.call();
      if (failureEvent != null) operations.failures.failures.add(failureEvent);
      final result = await _restore(
        dispatcher,
        cancellationToken: token ?? CancellationToken.none(),
      );
      expect(result.failureOrNull?.code, expected, reason: failureEvent);
    }

    await verify(SkillsErrorCode.repositoryBusy, failureEvent: 'lock.acquire');

    operations = OperationHarness();
    _rebuildDispatcher(
      operations: operations,
      snapshots: snapshots,
      content: content,
      revisions: revisions,
      plans: plans,
      setDispatcher: (value) => dispatcher = value,
    );
    operations.controlPlane.repositoryRevision = RepositoryRevision(9);
    await verify(SkillsErrorCode.staleSnapshot);

    operations = OperationHarness();
    _rebuildDispatcher(
      operations: operations,
      snapshots: snapshots,
      content: content,
      revisions: revisions,
      plans: plans,
      setDispatcher: (value) => dispatcher = value,
    );
    await verify(SkillsErrorCode.stateCorrupt, failureEvent: 'control.read');

    operations = OperationHarness();
    _rebuildDispatcher(
      operations: operations,
      snapshots: snapshots,
      content: content,
      revisions: revisions,
      plans: plans,
      setDispatcher: (value) => dispatcher = value,
    );
    await verify(
      SkillsErrorCode.journalCorrupt,
      failureEvent: 'control.prepared-envelope',
    );

    operations = OperationHarness();
    _rebuildDispatcher(
      operations: operations,
      snapshots: snapshots,
      content: content,
      revisions: revisions,
      plans: plans,
      setDispatcher: (value) => dispatcher = value,
    );
    plans.throwOnSeal = true;
    await verify(SkillsErrorCode.operationFailed);
    plans.throwOnSeal = false;

    operations = OperationHarness();
    _rebuildDispatcher(
      operations: operations,
      snapshots: snapshots,
      content: content,
      revisions: revisions,
      plans: plans,
      setDispatcher: (value) => dispatcher = value,
    );
    await verify(
      SkillsErrorCode.operationFailed,
      failureEvent: 'recovery.apply:apply',
    );

    operations = OperationHarness();
    _rebuildDispatcher(
      operations: operations,
      snapshots: snapshots,
      content: content,
      revisions: revisions,
      plans: plans,
      setDispatcher: (value) => dispatcher = value,
    );
    await verify(
      SkillsErrorCode.operationFailed,
      failureEvent: 'control.commit',
    );

    operations = OperationHarness();
    _rebuildDispatcher(
      operations: operations,
      snapshots: snapshots,
      content: content,
      revisions: revisions,
      plans: plans,
      setDispatcher: (value) => dispatcher = value,
    );
    final source = CancellationSource();
    content.onResolve = () => source.cancel();
    await verify(SkillsErrorCode.operationCancelled, token: source.token);
  });

  test('failed rollback reports recovery failure', () async {
    operations.failures.failures.addAll(<String>{
      'recovery.apply:apply',
      'recovery.rollback',
    });

    final result = await _restore(dispatcher);

    expect(result.failureOrNull?.code, SkillsErrorCode.recoveryFailed);
    expect(result.failureOrNull?.context['reason'], 'applyFailed');
  });
}

void _rebuildDispatcher({
  required OperationHarness operations,
  required WorkspaceSnapshotPublisher snapshots,
  required _HistoryContent content,
  required _RestorePreparation revisions,
  required _RestorePlans plans,
  required void Function(CompositeSkillsRepositoryCommandDispatcher value)
  setDispatcher,
}) {
  setDispatcher(
    CompositeSkillsRepositoryCommandDispatcher(
      buildHistoryCommandHandlers(
        snapshots: snapshots,
        history: WorkspaceHistoryService(content: content, clock: () => _now),
        assembler: const RestorePlanAssembler(),
        operations: operations.createCoordinator(),
        revisions: revisions,
        plans: plans,
      ),
    ),
  );
}

Future<SkillsResult<MutationReport>> _restore(
  CompositeSkillsRepositoryCommandDispatcher dispatcher, {
  CancellationToken? cancellationToken,
  void Function()? markBusinessCommitted,
  void Function(OperationProgressPhase phase)? reportProgress,
}) => _execute<MutationReport>(
  dispatcher,
  WorkspaceOperationKind.restorePublish,
  RestorePublishRequest(
    managedSkillId: _skillId,
    selectedRevision: _selectedReference,
  ),
  cancellationToken: cancellationToken,
  markBusinessCommitted: markBusinessCommitted,
  reportProgress: reportProgress,
);

Future<SkillsResult<T>> _execute<T>(
  CompositeSkillsRepositoryCommandDispatcher dispatcher,
  WorkspaceOperationKind kind,
  Object request, {
  CancellationToken? cancellationToken,
  void Function()? markBusinessCommitted,
  void Function(OperationProgressPhase phase)? reportProgress,
}) => dispatcher.execute<T>(
  operationId: _operationId,
  kind: kind,
  request: request,
  cancellationToken: cancellationToken ?? CancellationToken.none(),
  markBusinessCommitted: markBusinessCommitted ?? () {},
  reportProgress: (phase, {currentItem, completed = 0, total}) {
    reportProgress?.call(phase);
  },
);

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  _SnapshotReader(this.value);

  RepositorySnapshot value;
  bool throwOnRead = false;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async {
    if (throwOnRead) throw StateError('injected reload failure');
    return value;
  }
}

final class _HistoryContent implements WorkspaceHistoryContentPort {
  _HistoryContent()
    : compareResult = HistorySuccess<SkillDiff>(
        SkillDiff(
          managedSkillId: _skillId,
          from: _fromReference,
          to: _selectedReference,
          files: const <SkillFileDiff>[],
        ),
      );

  late HistoryResult<SkillDiff> compareResult;
  HistoryResult<bool> dirtyResult = const HistorySuccess<bool>(false);
  void Function()? onResolve;

  SkillDiff get diff => compareResult.valueOrNull!;

  @override
  Future<HistoryResult<SkillDiff>> compare({
    required ManagedSkillId managedSkillId,
    required HistoricalRevisionSelection? from,
    required HistoricalRevisionSelection to,
    required CancellationToken cancellationToken,
  }) async => compareResult;

  @override
  Future<HistoryResult<bool>> inspectDraftDirty({
    required ManagedSkill skill,
    required RestoreRevisionState state,
    required CancellationToken cancellationToken,
  }) async => dirtyResult;

  @override
  Future<RestoreRevisionState?> readRestoreState(
    ManagedSkillId managedSkillId,
  ) async => _restoreState;

  @override
  Future<HistoricalRevisionSelection?> resolvePublishedRevision({
    required ManagedSkillId managedSkillId,
    required OperationSubjectReference reference,
  }) async {
    onResolve?.call();
    return HistoricalRevisionSelection(
      reference: reference,
      managedSkillId: managedSkillId,
      sourceLineage: _lineage,
      objectId: reference == _selectedReference ? _selectedObject : _baseObject,
      contentHash: reference == _selectedReference ? _selectedHash : _baseHash,
      declaredName: 'sample',
    );
  }
}

final class _RestorePreparation implements RestoreRevisionPreparationPort {
  HistoryResult<PreparedRestorePublish> result = HistorySuccess(
    _preparedRestore(),
  );

  @override
  Future<HistoryResult<PreparedRestorePublish>> prepareRestorePublish({
    required PreparedOperationEnvelope envelope,
    required RestorePublishPreflight preflight,
    required CancellationToken cancellationToken,
  }) async => result;
}

final class _RestorePlans implements RestoreOperationPlanPort {
  bool throwOnSeal = false;

  @override
  PreparedOperationEnvelope createRestoreEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RestorePublishPreflight preflight,
  }) {
    return PreparedOperationEnvelope(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: expectedRepositoryRevision.next(),
      operationGeneration: expectedRepositoryRevision.next().value,
      preparationSteps: <PreparationOperationStep>[
        PreparationOperationStep(
          stepId: 'prepare',
          recoveryReference: RecoveryReference('prepare'),
          kind: PreparationStepKind.revisionCandidate,
        ),
      ],
      record: OperationRecordPlan(
        operationId: operationId,
        kind: WorkspaceOperationKind.restorePublish.name,
        subjects: const <OperationSubjectPlan>[],
        retainWithoutSubjects: true,
      ),
    );
  }

  @override
  OperationPlan sealRestorePlan({
    required PreparedOperationEnvelope envelope,
    required RestorePublishPreflight preflight,
    required PreparedRestorePublishPlan preparedPlan,
  }) {
    if (throwOnSeal) throw StateError('injected plan-sealing failure');
    return OperationPlan(
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
      revisionSelectionChanges: preparedPlan.revisionSelectionChanges,
      businessChanges: preparedPlan.businessChanges,
      record: envelope.record,
    );
  }
}

PreparedRestorePublish _preparedRestore({String contentHash = _selectedHash}) {
  final tree = RevisionObjectId('4' * 40);
  return PreparedRestorePublish(
    managedSkillId: _skillId,
    sourceLineage: _lineage,
    selectedObjectId: _selectedObject,
    treeObjectId: tree,
    effectiveObjectId: _restoredObject,
    effectiveRequest: RevisionCommitRequest(
      tree: tree,
      parents: <RevisionObjectId>[_currentEffective],
      kind: RevisionCommitKind.restorePublish,
    ),
    contentHash: contentHash,
    fileCount: 1,
    byteSize: 10,
    declaredName: 'sample',
    description: 'Restored sample',
    draftAction: RestoreDraftAction.noDraft,
    capturedDraftFingerprint: null,
    candidateRecoveryReference: RecoveryReference('candidate'),
    bundleRecoveryReference: RecoveryReference('bundle'),
    materializationRecoveryReference: RecoveryReference('materialization'),
    draftRecoveryReference: RecoveryReference('draft'),
  );
}

RepositorySnapshot _snapshot({int revision = 0}) => RepositorySnapshot(
  revision: RepositoryRevision(revision),
  managedSkills: <ManagedSkill>[
    ManagedSkill(
      id: _skillId,
      slotKey: 'sample',
      declaredName: 'sample',
      displayName: 'Sample',
      description: 'Sample Skill',
      source: LocalSourceDescriptor(locator: '/source/sample'),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: _baseHash,
        fileCount: 1,
        byteSize: 10,
        publishedAt: _now,
      ),
    ),
  ],
);

final _restoreState = RestoreRevisionState(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  currentUpstream: _baseObject,
  currentEffective: _currentEffective,
  managedSkillCreatedAtMicros: 1,
  draftCreatedAtMicros: null,
);

final _now = DateTime.utc(2026, 8, 20, 12);
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _operationId = OperationId('123e4567-e89b-42d3-a456-426614174001');
final _fromReference = OperationSubjectReference(
  operationId: OperationId('123e4567-e89b-42d3-a456-426614174002'),
  subjectId: '123e4567-e89b-42d3-a456-426614174003',
);
final _selectedReference = OperationSubjectReference(
  operationId: OperationId('123e4567-e89b-42d3-a456-426614174004'),
  subjectId: '123e4567-e89b-42d3-a456-426614174005',
);
final _lineage = SourceLineageReference('123e4567-e89b-42d3-a456-426614174006');
final _baseObject = RevisionObjectId('1' * 40);
final _currentEffective = RevisionObjectId('2' * 40);
final _selectedObject = RevisionObjectId('3' * 40);
final _restoredObject = RevisionObjectId('5' * 40);
const _baseHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _selectedHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _otherHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
