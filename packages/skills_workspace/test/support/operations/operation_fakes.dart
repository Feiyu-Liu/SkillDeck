import 'package:skills_workspace/src/api/cancellation.dart';
import 'package:skills_workspace/src/application/operations/operation_coordinator.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/lock_wait_policy.dart';

final class OperationEventLog {
  final List<String> events = <String>[];

  void Function(String event)? afterEvent;

  void add(String event) {
    events.add(event);
    afterEvent?.call(event);
  }

  void clear() => events.clear();
}

final class OperationFailureInjector {
  final Set<String> failures = <String>{};
  final Set<String> externalPreconditionFailures = <String>{};

  void check(String event) {
    if (externalPreconditionFailures.contains(event)) {
      throw const ExternalOperationPreconditionChanged();
    }
    if (failures.contains(event)) {
      throw InjectedOperationFailure(event);
    }
  }
}

final class InjectedOperationFailure implements Exception {
  const InjectedOperationFailure(this.event);

  final String event;

  @override
  String toString() => 'InjectedOperationFailure($event)';
}

final class FakeWorkspaceWriterLock implements WorkspaceWriterLockPort {
  FakeWorkspaceWriterLock({required this.log, required this.failures});

  final OperationEventLog log;
  final OperationFailureInjector failures;
  LockWaitPolicy? observedWaitPolicy;

  @override
  Future<WorkspaceWriterLease> acquire({LockWaitPolicy? waitPolicy}) async {
    observedWaitPolicy = waitPolicy;
    const event = 'lock.acquire';
    log.add(event);
    failures.check(event);
    return _FakeWorkspaceWriterLease(log: log, failures: failures);
  }
}

final class FakeOperationRevisionReferenceMaintenance
    implements OperationRevisionReferenceMaintenancePort {
  FakeOperationRevisionReferenceMaintenance({
    required this.log,
    required this.failures,
  });

  final OperationEventLog log;
  final OperationFailureInjector failures;
  var calls = 0;
  final Set<int> failOnCalls = <int>{};
  final List<List<String>> observedEventPrefixes = <List<String>>[];
  final List<Set<ManagedSkillId>?> observedIsolatedSkillIds = [];
  final List<Set<ManagedSkillId>?> observedSelectedSkillIds = [];

  @override
  Future<void> reconcileRevisionReferences({
    Set<ManagedSkillId>? isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  }) async {
    calls += 1;
    observedEventPrefixes.add(List<String>.unmodifiable(log.events));
    observedIsolatedSkillIds.add(
      isolatedSkillIds == null ? null : Set.unmodifiable(isolatedSkillIds),
    );
    observedSelectedSkillIds.add(
      selectedSkillIds == null ? null : Set.unmodifiable(selectedSkillIds),
    );
    if (failOnCalls.contains(calls)) {
      throw InjectedOperationFailure('refs.reconcile:$calls');
    }
    failures.check('refs.reconcile');
  }
}

final class _FakeWorkspaceWriterLease implements WorkspaceWriterLease {
  _FakeWorkspaceWriterLease({required this.log, required this.failures});

  final OperationEventLog log;
  final OperationFailureInjector failures;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) {
      throw StateError('The fake writer lease was released more than once.');
    }
    _released = true;
    const event = 'lock.release';
    log.add(event);
    failures.check(event);
  }
}

final class FakeOperationControlPlane implements OperationControlPlanePort {
  FakeOperationControlPlane({
    required this.log,
    required this.failures,
    RepositoryRevision? repositoryRevision,
  }) : repositoryRevision = repositoryRevision ?? RepositoryRevision.initial();

  final OperationEventLog log;
  final OperationFailureInjector failures;
  RepositoryRevision repositoryRevision;
  final Map<OperationId, JournaledOperation> _journals =
      <OperationId, JournaledOperation>{};

  List<JournaledOperation> get journals =>
      List<JournaledOperation>.unmodifiable(_journals.values);

  void seed(OperationPlan plan, OperationJournalPhase phase) {
    _journals[plan.operationId] = JournaledOperation(plan: plan, phase: phase);
  }

  void seedPreparedEnvelope(
    PreparedOperationEnvelope envelope,
    OperationJournalPhase phase,
  ) {
    _journals[envelope.operationId] = JournaledOperation.prepared(
      envelope: envelope,
      phase: phase,
    );
  }

  @override
  Future<RepositoryRevision> readRepositoryRevision() async {
    const event = 'control.read';
    log.add(event);
    failures.check(event);
    return repositoryRevision;
  }

  @override
  Future<void> persistPrepared(OperationPlan plan) async {
    const event = 'control.prepared';
    log.add(event);
    failures.check(event);
    _journals[plan.operationId] = JournaledOperation(
      plan: plan,
      phase: OperationJournalPhase.prepared,
    );
  }

  @override
  Future<void> persistPreparedEnvelope(
    PreparedOperationEnvelope envelope,
  ) async {
    const event = 'control.prepared-envelope';
    log.add(event);
    failures.check(event);
    _journals[envelope.operationId] = JournaledOperation.prepared(
      envelope: envelope,
      phase: OperationJournalPhase.prepared,
      stepStatuses: <String, OperationStepStatus>{
        for (final step in envelope.preparationSteps)
          step.stepId: OperationStepStatus.planned,
      },
    );
  }

  @override
  Future<void> sealPreparedPlan(
    PreparedOperationEnvelope envelope,
    OperationPlan plan,
  ) async {
    const event = 'control.seal-plan';
    log.add(event);
    failures.check(event);
    final current = _journals[envelope.operationId];
    if (current == null ||
        current.phase != OperationJournalPhase.prepared ||
        current.definition is! PreparedOperationEnvelope ||
        !envelope.isSealedBy(plan)) {
      throw StateError('The Prepared envelope cannot be sealed.');
    }
    _journals[envelope.operationId] = JournaledOperation(
      plan: plan,
      phase: current.phase,
      stepStatuses: <String, OperationStepStatus>{
        ...current.stepStatuses,
        for (final step in <OperationStep>[
          ...plan.preparationSteps,
          ...plan.applyingSteps,
          ...plan.finalizationSteps,
        ])
          if (!current.stepStatuses.containsKey(step.stepId))
            step.stepId: OperationStepStatus.planned,
      },
    );
  }

  @override
  Future<void> markApplying(OperationId operationId) async {
    const event = 'control.applying';
    log.add(event);
    failures.check(event);
    _replacePhase(operationId, OperationJournalPhase.applying);
  }

  @override
  Future<void> markStepStarted(OperationId operationId, String stepId) async {
    final event = 'control.step-start:$stepId';
    log.add(event);
    failures.check(event);
    _replaceStepStatus(operationId, stepId, OperationStepStatus.started);
  }

  @override
  Future<void> markStepCompleted(OperationId operationId, String stepId) async {
    final event = 'control.step-complete:$stepId';
    log.add(event);
    failures.check(event);
    _replaceStepStatus(operationId, stepId, OperationStepStatus.completed);
  }

  @override
  Future<void> commitBusinessState(OperationPlan plan) async {
    const event = 'control.commit';
    log.add(event);
    failures.check(event);
    repositoryRevision = plan.committedRepositoryRevision;
    _replacePhase(plan.operationId, OperationJournalPhase.committed);
  }

  @override
  Future<void> applyFinalizationEffect(
    OperationId operationId,
    OperationFinalizationEffect effect,
  ) async {
    const event = 'control.finalization-effect';
    log.add(event);
    failures.check(event);
  }

  @override
  Future<void> markFinalizing(OperationId operationId) async {
    const event = 'control.finalizing';
    log.add(event);
    failures.check(event);
    _replacePhase(operationId, OperationJournalPhase.finalizing);
  }

  @override
  Future<void> complete(OperationPlan plan) async {
    const event = 'control.complete';
    log.add(event);
    failures.check(event);
    _replacePhase(plan.operationId, OperationJournalPhase.completed);
  }

  @override
  Future<void> completeRollback(
    OperationPlan plan,
    OperationAbortReason reason,
  ) async {
    const event = 'control.rollback-complete';
    log.add(event);
    failures.check(event);
    _replacePhase(plan.operationId, OperationJournalPhase.completed);
  }

  @override
  Future<void> completePreparedEnvelopeRollback(
    PreparedOperationEnvelope envelope,
    OperationAbortReason reason,
  ) async {
    const event = 'control.envelope-rollback-complete';
    log.add(event);
    failures.check(event);
    _replacePhase(envelope.operationId, OperationJournalPhase.completed);
  }

  @override
  Future<List<JournaledOperation>> loadRecoverableOperations() async {
    const event = 'control.load-recoverable';
    log.add(event);
    failures.check(event);
    return List<JournaledOperation>.unmodifiable(_journals.values);
  }

  @override
  Future<void> deleteCompletedJournal(OperationId operationId) async {
    const event = 'control.delete-journal';
    log.add(event);
    failures.check(event);
    final journal = _journals[operationId];
    if (journal == null || journal.phase != OperationJournalPhase.completed) {
      throw StateError('Only a completed Journal can be deleted.');
    }
    _journals.remove(operationId);
  }

  void _replacePhase(OperationId operationId, OperationJournalPhase phase) {
    final current = _journals[operationId];
    if (current == null) {
      throw StateError('Missing Journal for $operationId.');
    }
    _journals[operationId] = JournaledOperation.fromDefinition(
      definition: current.definition,
      phase: phase,
      stepStatuses: current.stepStatuses,
    );
  }

  void _replaceStepStatus(
    OperationId operationId,
    String stepId,
    OperationStepStatus status,
  ) {
    final current = _journals[operationId];
    if (current == null || !current.stepStatuses.containsKey(stepId)) {
      return;
    }
    final statuses = <String, OperationStepStatus>{
      ...current.stepStatuses,
      stepId: status,
    };
    _journals[operationId] = JournaledOperation.fromDefinition(
      definition: current.definition,
      phase: current.phase,
      stepStatuses: statuses,
    );
  }
}

final class FakeOperationRecovery
    implements OperationRecoveryPort, PreparedOperationRecoveryPort {
  FakeOperationRecovery({required this.log, required this.failures});

  final OperationEventLog log;
  final OperationFailureInjector failures;

  @override
  Future<void> prepareStep(
    PreparationOperationStep step,
    CancellationToken cancellationToken,
  ) async {
    final event = 'recovery.prepare:${step.stepId}';
    log.add(event);
    failures.check(event);
  }

  @override
  Future<void> applyStep(
    ApplyingOperationStep step,
    CancellationToken cancellationToken,
  ) async {
    final event = 'recovery.apply:${step.stepId}';
    log.add(event);
    failures.check(event);
  }

  @override
  Future<OperationFinalizationEffect?> finalizeStep(
    FinalizationOperationStep step,
  ) async {
    final event = 'recovery.finalize:${step.stepId}';
    log.add(event);
    failures.check(event);
    return null;
  }

  @override
  Future<void> rollback(
    OperationPlan plan, {
    required OperationJournalPhase observedPhase,
  }) async {
    const event = 'recovery.rollback';
    log.add(event);
    failures.check(event);
  }

  @override
  Future<List<OperationFinalizationEffect>> rollForward(
    OperationPlan plan,
  ) async {
    const event = 'recovery.roll-forward';
    log.add(event);
    failures.check(event);
    return const <OperationFinalizationEffect>[];
  }

  @override
  Future<void> cleanupCompleted(OperationPlan plan) async {
    const event = 'recovery.cleanup';
    log.add(event);
    failures.check(event);
  }

  @override
  Future<void> rollbackPreparedEnvelope(
    PreparedOperationEnvelope envelope, {
    required OperationJournalPhase observedPhase,
  }) async {
    const event = 'recovery.rollback-envelope';
    log.add(event);
    failures.check(event);
  }

  @override
  Future<void> cleanupCompletedPreparedEnvelope(
    PreparedOperationEnvelope envelope,
  ) async {
    const event = 'recovery.cleanup-envelope';
    log.add(event);
    failures.check(event);
  }
}

final class OperationHarness {
  OperationHarness({RepositoryRevision? repositoryRevision}) {
    writerLock = FakeWorkspaceWriterLock(log: log, failures: failures);
    controlPlane = FakeOperationControlPlane(
      log: log,
      failures: failures,
      repositoryRevision: repositoryRevision,
    );
    recovery = FakeOperationRecovery(log: log, failures: failures);
    referenceMaintenance = FakeOperationRevisionReferenceMaintenance(
      log: log,
      failures: failures,
    );
  }

  final OperationEventLog log = OperationEventLog();
  final OperationFailureInjector failures = OperationFailureInjector();
  late final FakeWorkspaceWriterLock writerLock;
  late final FakeOperationControlPlane controlPlane;
  late final FakeOperationRecovery recovery;
  late final FakeOperationRevisionReferenceMaintenance referenceMaintenance;

  OperationCoordinator createCoordinator({
    OperationAbortClassifier classifyAbort = classifyOperationAbort,
  }) => OperationCoordinator(
    writerLock: writerLock,
    controlPlane: controlPlane,
    recovery: recovery,
    referenceMaintenance: referenceMaintenance,
    classifyAbort: classifyAbort,
  );
}
