import 'dart:async';

import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/destructive_intent.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/destructive/destructive_operation_models.dart';
import 'package:skills_workspace/src/application/destructive/destructive_operation_planner.dart';
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/destructive_operation_ports.dart';
import 'package:skills_workspace/src/application/ports/initial_import_ports.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/destructive_command_handlers.dart';
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
  late _PlanningState state;
  late _ReplacementPreparation preparation;
  late _RecoveryEntries recoveryEntries;
  late CompositeSkillsRepositoryCommandDispatcher dispatcher;

  setUp(() async {
    operations = OperationHarness();
    reader = _SnapshotReader(_publicSnapshot());
    snapshots = WorkspaceSnapshotPublisher(reader: reader);
    await snapshots.publishInitial(reader.value);
    state = _PlanningState(_planningSnapshot());
    state.log = operations.log;
    preparation = _ReplacementPreparation(operations.log);
    recoveryEntries = _RecoveryEntries();
    final recoveryPlans = _RecoveryPlans();
    final operationPlans = OperationPlanAssembler(
      subjectIdentities: _SubjectIds(),
      recoveryPlans: recoveryPlans,
    );
    final planner = DestructiveOperationPlanner(
      identities: _Identities(),
      replacementPreparation: preparation,
      recoveryEntries: recoveryEntries,
      operationPlans: operationPlans,
      clock: () => 10,
    );
    dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      buildDestructiveCommandHandlers(
        snapshots: snapshots,
        operations: operations.createCoordinator(),
        operationPlans: operationPlans,
        state: state,
        planner: planner,
      ),
    );
  });

  tearDown(() => snapshots.close());

  test('Removal plans from lock-held internal state and reloads', () async {
    reader.value = RepositorySnapshot(revision: RepositoryRevision(1));
    var committed = false;

    final result = await _execute<MutationReport>(
      dispatcher,
      WorkspaceOperationKind.remove,
      RemoveRequest(
        managedSkillIds: {_skillId},
        intent: DestructiveIntent(reviewedRevision: RepositoryRevision(0)),
      ),
      markBusinessCommitted: () => committed = true,
    );

    expect(result, isA<SkillsSuccess<MutationReport>>());
    expect(result.valueOrNull?.affectedSkillIds, {_skillId});
    expect(result.valueOrNull?.snapshot, reader.value);
    expect(state.calls, 1);
    expect(committed, isTrue);
    expect(
      operations.log.events,
      containsAllInOrder(['lock.acquire', 'state.read', 'control.prepared']),
    );
  });

  test(
    'Removal propagates and maps cancellation during recovery preparation',
    () async {
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

      final pending = _execute<MutationReport>(
        dispatcher,
        WorkspaceOperationKind.remove,
        RemoveRequest(
          managedSkillIds: {_skillId},
          intent: DestructiveIntent(reviewedRevision: RepositoryRevision(0)),
        ),
        cancellationToken: cancellation.token,
      );

      expect(identical(await entered.future, cancellation.token), isTrue);
      await cancellation.cancel();
      release.complete();
      final result = await pending;

      expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
      expect(operations.log.events, isNot(contains('control.prepared')));
    },
  );

  test(
    'stale destructive intent rejects before lock or state access',
    () async {
      final result = await _execute<MutationReport>(
        dispatcher,
        WorkspaceOperationKind.remove,
        RemoveRequest(
          managedSkillIds: {_skillId},
          intent: DestructiveIntent(reviewedRevision: RepositoryRevision(9)),
        ),
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
      expect(state.calls, 0);
      expect(operations.log.events, isEmpty);
    },
  );

  test('Draft-inspection cancellation remains operationCancelled', () async {
    state.failure = const DestructivePlanningStateException(
      DestructivePlanningStateFailureCode.operationCancelled,
      reason: 'operationCancelled',
    );

    final result = await _execute<MutationReport>(
      dispatcher,
      WorkspaceOperationKind.remove,
      RemoveRequest(
        managedSkillIds: {_skillId},
        intent: DestructiveIntent(reviewedRevision: RepositoryRevision(0)),
      ),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
    expect(result.failureOrNull?.context, <String, Object?>{
      'reason': 'operationCancelled',
    });
    expect(operations.log.events, isNot(contains('control.prepared')));
  });

  test('Source Replacement journals before candidate preparation', () async {
    reader.value = _publicSnapshot(revision: 1, slotKey: 'replacement-slot');

    final result = await _execute<MutationReport>(
      dispatcher,
      WorkspaceOperationKind.replaceSource,
      ReplaceSourceRequest(
        managedSkillId: _skillId,
        source: LocalSourceDescriptor(locator: '/replacement'),
        intent: DestructiveIntent(reviewedRevision: RepositoryRevision(0)),
      ),
    );

    expect(result, isA<SkillsSuccess<MutationReport>>());
    expect(preparation.calls, 1);
    expect(
      operations.log.events.indexOf('control.prepared'),
      lessThan(operations.log.events.indexOf('replacement.prepare')),
    );
  });
}

Future<SkillsResult<T>> _execute<T>(
  CompositeSkillsRepositoryCommandDispatcher dispatcher,
  WorkspaceOperationKind kind,
  Object request, {
  void Function()? markBusinessCommitted,
  CancellationToken? cancellationToken,
}) => dispatcher.execute<T>(
  operationId: _operationId,
  kind: kind,
  request: request,
  cancellationToken: cancellationToken ?? CancellationToken.none(),
  markBusinessCommitted: markBusinessCommitted ?? () {},
  reportProgress: (phase, {currentItem, completed = 0, total}) {},
);

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  _SnapshotReader(this.value);

  RepositorySnapshot value;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      value;
}

final class _PlanningState implements DestructivePlanningStatePort {
  _PlanningState(this.value);

  final DestructivePlanningSnapshot value;
  var calls = 0;
  OperationEventLog? log;
  DestructivePlanningStateException? failure;

  @override
  Future<DestructivePlanningSnapshot> readPlanningSnapshot({
    required RepositorySnapshot publicSnapshot,
    required DestructivePlanningPurpose purpose,
    required Set<ManagedSkillId> targetManagedSkillIds,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    log?.add('state.read');
    if (failure case final exception?) throw exception;
    return value;
  }
}

final class _ReplacementPreparation
    implements SourceReplacementPreparationPort {
  _ReplacementPreparation(this.log);

  final OperationEventLog log;
  var calls = 0;

  @override
  Future<SourceReplacementPreparationResult> prepareSourceReplacement(
    SourceReplacementPreparationIntent intent, {
    required PreparedOperationEnvelope envelope,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    log.add('replacement.prepare');
    return SourceReplacementPreparationSuccess(
      PreparedSourceReplacement(
        managedSkillId: intent.managedSkillId,
        sourceLineage: intent.intendedSourceLineage,
        objectId: _newObject,
        objectFormat: WorkspaceObjectFormat.sha1,
        persistedSourceKind: WorkspaceSourceKind.local,
        sourcePayloadSchemaVersion: 1,
        sourcePayloadJson: '{"locator":"/replacement"}',
        slotKey: 'replacement-slot',
        declaredName: 'replacement-slot',
        displayName: 'Replacement',
        description: 'Replacement description',
        contentHash: _newHash,
        fileCount: 1,
        byteSize: 1,
      ),
    );
  }
}

final class _RecoveryEntries
    implements DestructiveRecoveryEntryPreparationPort {
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
    await onPrepare?.call(
      operationId: operationId,
      intent: intent,
      cancellationToken: cancellationToken,
    );
  }
}

final class _Identities implements WorkspaceEntityIdentityPort {
  @override
  SourceLineageReference allocateSourceLineage() => _newLineage;

  @override
  String allocateActivationId() => throw UnimplementedError();

  @override
  ManagedSkillId allocateManagedSkillId() => throw UnimplementedError();
}

final class _SubjectIds implements OperationSubjectIdentityPort {
  @override
  String allocateOperationSubjectId() => _subjectId;
}

final class _RecoveryPlans implements OperationRecoveryPlanFactoryPort {
  @override
  List<PreparationOperationStep> createDestructiveEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
  }) => [
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
  }) => OperationRecoveryPlanSteps(
    preparationSteps: createDestructiveEnvelope(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: committedRepositoryRevision,
    ),
    applyingSteps: [
      ApplyingOperationStep(
        stepId: 'apply',
        recoveryReference: RecoveryReference('apply'),
        kind: ApplyingStepKind.destructiveReplacement,
      ),
    ],
    finalizationSteps: const [],
  );

  @override
  OperationRecoveryPlanSteps createSqliteOnly({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required bool destructive,
  }) => throw UnimplementedError();
}

RepositorySnapshot _publicSnapshot({
  int revision = 0,
  String slotKey = 'one',
}) => RepositorySnapshot(
  revision: RepositoryRevision(revision),
  managedSkills: [
    ManagedSkill(
      id: _skillId,
      slotKey: slotKey,
      declaredName: slotKey,
      displayName: 'One',
      description: 'One Skill',
      source: LocalSourceDescriptor(locator: '/source'),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: _oldHash,
        fileCount: 1,
        byteSize: 1,
        publishedAt: DateTime.utc(2026, 8, 17),
      ),
    ),
  ],
);

DestructivePlanningSnapshot _planningSnapshot() => DestructivePlanningSnapshot(
  repositoryRevision: RepositoryRevision(0),
  managedSkills: [_planningSkill()],
);

DestructiveManagedSkillState _planningSkill() => DestructiveManagedSkillState(
  managedSkillId: _skillId,
  slotKey: 'one',
  declaredName: 'one',
  displayName: 'One',
  description: 'One Skill',
  createdAtMicros: 1,
  sourceLineages: [DestructiveSourceLineageState(sourceLineage: _oldLineage)],
  activeSourceLineage: _oldLineage,
  currentUpstream: RevisionAddress(
    sourceLineage: _oldLineage,
    objectId: _oldObject,
  ),
  currentEffective: RevisionAddress(
    sourceLineage: _oldLineage,
    objectId: _oldObject,
  ),
  currentContentHash: _oldHash,
  activationIds: const [],
  draftState: DestructiveDraftState.absent,
  hasUpdateCandidateSession: false,
);

final _operationId = OperationId('123e4567-e89b-42d3-a456-426614174020');
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _oldLineage = SourceLineageReference(
  '123e4567-e89b-42d3-8456-426614174001',
);
final _newLineage = SourceLineageReference(
  '123e4567-e89b-42d3-8456-426614174002',
);
const _subjectId = '123e4567-e89b-42d3-8456-426614174003';
final _oldObject = RevisionObjectId('a' * 40);
final _newObject = RevisionObjectId('b' * 40);
const _oldHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
