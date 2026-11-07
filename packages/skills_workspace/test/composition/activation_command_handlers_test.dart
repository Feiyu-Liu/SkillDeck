import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_mutation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_mutation_planner.dart';
import 'package:skills_workspace/src/application/activation/activation_occupancy_inspector.dart';
import 'package:skills_workspace/src/application/activation/activation_target_resolver.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog_controller.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/ports/activation_mutation_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/activation_command_handlers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../support/activation/activation_fakes.dart';
import '../support/operations/operation_fakes.dart';

void main() {
  late _Fixture fixture;

  tearDown(() async {
    await fixture.close();
  });

  test(
    'vacant Activate commits metadata and returns ActivationCompleted',
    () async {
      fixture = await _Fixture.create(_snapshot());
      fixture.reader.value = _snapshot(
        revision: 1,
        activations: <SkillActivation>[_activation()],
      );

      final result = await fixture.execute<ActivationAttempt>(
        WorkspaceOperationKind.activate,
        _activateRequest(),
      );

      expect(result.valueOrNull, isA<ActivationCompleted>());
      final completed = result.valueOrNull! as ActivationCompleted;
      expect(completed.report.snapshot.revision, RepositoryRevision(1));
      expect(completed.report.affectedSkillIds, <ManagedSkillId>{_skillId});
      expect(fixture.plans.lastMutation?.pathMutations, hasLength(1));
      expect(
        fixture.operations.log.events,
        containsAllInOrder(<String>[
          'control.prepared',
          'recovery.apply:apply-1',
          'control.commit',
        ]),
      );
    },
  );

  test(
    'divergent target returns an opaque takeover draft without Journal',
    () async {
      fixture = await _Fixture.create(_snapshot());
      fixture.setOccupancy(fingerprint: 'directory:reviewed');

      final result = await fixture.execute<ActivationAttempt>(
        WorkspaceOperationKind.activate,
        _activateRequest(),
      );

      final required = result.valueOrNull as ActivationTakeoverRequired;
      expect(required.draft.reviewedRevision, RepositoryRevision.initial());
      expect(required.draft.targets, hasLength(1));
      expect(
        required.draft.targets.single.contentRelation,
        ActivationContentRelation.differsFromCurrentRevision,
      );
      expect(
        () => required.draft.targets.add(required.draft.targets.single),
        throwsUnsupportedError,
      );
      expect(fixture.operations.log.events, isEmpty);
    },
  );

  test('confirmed takeover re-inspects the fingerprint and commits', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.setOccupancy(fingerprint: 'directory:reviewed');
    final attempt = await fixture.execute<ActivationAttempt>(
      WorkspaceOperationKind.activate,
      _activateRequest(),
    );
    final draft = (attempt.valueOrNull as ActivationTakeoverRequired).draft;
    fixture.reader.value = _snapshot(
      revision: 1,
      activations: <SkillActivation>[_activation()],
    );

    final confirmed = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.confirmActivationTakeover,
      ConfirmActivationTakeoverRequest(draft: draft),
    );

    expect(confirmed.valueOrNull?.snapshot.revision, RepositoryRevision(1));
    expect(
      fixture.plans.lastKind,
      WorkspaceOperationKind.confirmActivationTakeover,
    );
  });

  test(
    'changed takeover target is stale and never creates a Journal',
    () async {
      fixture = await _Fixture.create(_snapshot());
      fixture.setOccupancy(fingerprint: 'directory:reviewed');
      final attempt = await fixture.execute<ActivationAttempt>(
        WorkspaceOperationKind.activate,
        _activateRequest(),
      );
      final draft = (attempt.valueOrNull as ActivationTakeoverRequired).draft;
      fixture.setOccupancy(fingerprint: 'directory:changed');

      final confirmed = await fixture.execute<MutationReport>(
        WorkspaceOperationKind.confirmActivationTakeover,
        ConfirmActivationTakeoverRequest(draft: draft),
      );

      expect(
        confirmed.failureOrNull?.code,
        SkillsErrorCode.staleActivationTakeover,
      );
      expect(
        confirmed.failureOrNull?.context['reason'],
        'activationTargetChanged',
      );
      expect(fixture.operations.log.events, isEmpty);
    },
  );

  test('Repository Revision change makes a takeover stale', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.setOccupancy(fingerprint: 'directory:reviewed');
    final attempt = await fixture.execute<ActivationAttempt>(
      WorkspaceOperationKind.activate,
      _activateRequest(),
    );
    final draft = (attempt.valueOrNull as ActivationTakeoverRequired).draft;
    fixture.reader.value = _snapshot(revision: 1);
    await fixture.snapshots.reload();

    final confirmed = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.confirmActivationTakeover,
      ConfirmActivationTakeoverRequest(draft: draft),
    );

    expect(
      confirmed.failureOrNull?.code,
      SkillsErrorCode.staleActivationTakeover,
    );
    expect(
      confirmed.failureOrNull?.context['reason'],
      'repositoryRevisionChanged',
    );
  });

  test('repeated confirmation is rejected after the first commit', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.setOccupancy(fingerprint: 'directory:reviewed');
    final attempt = await fixture.execute<ActivationAttempt>(
      WorkspaceOperationKind.activate,
      _activateRequest(),
    );
    final draft = (attempt.valueOrNull as ActivationTakeoverRequired).draft;
    fixture.reader.value = _snapshot(
      revision: 1,
      activations: <SkillActivation>[_activation()],
    );
    final first = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.confirmActivationTakeover,
      ConfirmActivationTakeoverRequest(draft: draft),
    );
    expect(first.isSuccess, isTrue);

    final second = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.confirmActivationTakeover,
      ConfirmActivationTakeoverRequest(draft: draft),
    );

    expect(second.failureOrNull?.code, SkillsErrorCode.staleActivationTakeover);
    expect(fixture.plans.assemblies, 1);
  });

  test(
    'Agent Catalog path reconfiguration invalidates a takeover draft',
    () async {
      fixture = await _Fixture.create(_snapshot());
      fixture.setOccupancy(fingerprint: 'directory:reviewed');
      final attempt = await fixture.execute<ActivationAttempt>(
        WorkspaceOperationKind.activate,
        _activateRequest(),
      );
      final draft = (attempt.valueOrNull as ActivationTakeoverRequired).draft;
      expect(
        fixture.catalogs.reconfigure(<AgentDefinition>[
          _agent('/agents/reconfigured'),
        ]).isSuccess,
        isTrue,
      );

      final confirmed = await fixture.execute<MutationReport>(
        WorkspaceOperationKind.confirmActivationTakeover,
        ConfirmActivationTakeoverRequest(draft: draft),
      );

      expect(
        confirmed.failureOrNull?.code,
        SkillsErrorCode.staleActivationTakeover,
      );
      expect(
        confirmed.failureOrNull?.context['reason'],
        'activationTargetChanged',
      );
    },
  );

  test('foreign draft implementation is rejected before inspection', () async {
    fixture = await _Fixture.create(_snapshot());

    final result = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.confirmActivationTakeover,
      ConfirmActivationTakeoverRequest(draft: const _ForeignDraft()),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.operationFailed);
    expect(
      result.failureOrNull?.context['reason'],
      'invalidActivationTakeoverDraft',
    );
    expect(fixture.occupancy.inspectedPaths, isEmpty);
  });

  test('Deactivate removes only selected persisted locations', () async {
    final first = _activation(location: '/agents/first');
    final second = _activation(location: '/agents/second');
    fixture = await _Fixture.create(
      _snapshot(activations: <SkillActivation>[first, second]),
      persistedActivations: <PersistedActivation>[
        _persisted(first, _activationId),
        _persisted(second, _secondActivationId),
      ],
    );
    fixture.reader.value = _snapshot(
      revision: 1,
      activations: <SkillActivation>[first],
    );

    final result = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.deactivate,
      DeactivateRequest(
        managedSkillIds: <ManagedSkillId>{_skillId},
        locations: const <String>{'/agents/second'},
      ),
    );

    expect(
      result.valueOrNull?.snapshot.managedSkills.single.activations,
      <SkillActivation>[first],
    );
    final pathMutation = fixture.plans.lastMutation!.pathMutations.single;
    expect(pathMutation.targetPath, path.join('/agents/second', 'example'));
  });

  test('Deactivate with no matching location is a no-op', () async {
    final activation = _activation();
    fixture = await _Fixture.create(
      _snapshot(activations: <SkillActivation>[activation]),
      persistedActivations: <PersistedActivation>[
        _persisted(activation, _activationId),
      ],
    );

    final result = await fixture.execute<MutationReport>(
      WorkspaceOperationKind.deactivate,
      DeactivateRequest(
        managedSkillIds: <ManagedSkillId>{_skillId},
        locations: const <String>{'/other'},
      ),
    );

    expect((result as SkillsSuccess<MutationReport>).changed, isFalse);
    expect(fixture.operations.log.events, isEmpty);
  });

  test('pre-commit apply failure rolls back and stays a failure', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.reader.value = _snapshot(
      revision: 1,
      activations: <SkillActivation>[_activation()],
    );
    fixture.operations.failures.failures.add('recovery.apply:apply-1');

    final result = await fixture.execute<ActivationAttempt>(
      WorkspaceOperationKind.activate,
      _activateRequest(),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.operationFailed);
    expect(
      fixture.operations.log.events,
      containsAllInOrder(<String>[
        'recovery.apply:apply-1',
        'recovery.rollback',
        'control.rollback-complete',
      ]),
    );
  });

  test('cancelled Activate never journals or mutates', () async {
    fixture = await _Fixture.create(_snapshot());
    final cancellation = CancellationSource();
    await cancellation.cancel();

    final result = await fixture.execute<ActivationAttempt>(
      WorkspaceOperationKind.activate,
      _activateRequest(),
      cancellationToken: cancellation.token,
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
    expect(fixture.operations.log.events, isEmpty);
  });
}

final class _Fixture {
  _Fixture._({
    required this.reader,
    required this.snapshots,
    required this.catalogs,
    required this.occupancy,
    required this.metadata,
    required this.operations,
    required this.plans,
    required this.dispatcher,
  });

  static Future<_Fixture> create(
    RepositorySnapshot snapshot, {
    List<PersistedActivation> persistedActivations =
        const <PersistedActivation>[],
  }) async {
    final reader = _SnapshotReader(snapshot);
    final snapshots = WorkspaceSnapshotPublisher(reader: reader);
    await snapshots.publishInitial(snapshot);
    final catalogs = AgentCatalogController.create(
      platform: DesktopPlatform.macos,
      detectionPort: FakeAgentDetectionPort(matches: (_, _) => true),
      builtIns: const <AgentDefinition>[],
      additional: <AgentDefinition>[_agent('/agents/skills')],
    ).valueOrNull!;
    final occupancy = RecordingActivationOccupancyProbe();
    final metadata = _ActivationMetadata(persistedActivations);
    final operations = OperationHarness(repositoryRevision: snapshot.revision);
    final plans = _ActivationPlans();
    final planner = ActivationMutationPlanner(
      locationIdentity: const PosixActivationLocationIdentity(),
      identities: const _ActivationIds(),
      clock: () => _now,
    );
    ActivationOccupancyInspector inspector() => ActivationOccupancyInspector(
      targetResolver: ActivationTargetResolver(
        catalog: catalogs.current,
        symbolicLinkCapability: FakeSymbolicLinkCapability(defaultResult: true),
        locationIdentity: const PosixActivationLocationIdentity(),
      ),
      locationIdentity: const PosixActivationLocationIdentity(),
      occupancyProbe: occupancy,
    );
    final dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      buildActivationCommandHandlers(
        snapshots: snapshots,
        operations: operations.createCoordinator(),
        occupancyInspector: inspector,
        activationMetadata: metadata,
        activationMutations: planner,
        plans: plans,
      ),
    );
    return _Fixture._(
      reader: reader,
      snapshots: snapshots,
      catalogs: catalogs,
      occupancy: occupancy,
      metadata: metadata,
      operations: operations,
      plans: plans,
      dispatcher: dispatcher,
    );
  }

  final _SnapshotReader reader;
  final WorkspaceSnapshotPublisher snapshots;
  final AgentCatalogController catalogs;
  final RecordingActivationOccupancyProbe occupancy;
  final _ActivationMetadata metadata;
  final OperationHarness operations;
  final _ActivationPlans plans;
  final CompositeSkillsRepositoryCommandDispatcher dispatcher;

  void setOccupancy({required String fingerprint}) {
    final activationLocation = _platformLocation('/agents/skills');
    final target = ResolvedActivationTarget(
      location: activationLocation,
      scope: ActivationScope.global,
      mode: ActivationMode.copy,
      agentIds: const <String>[_agentId],
    );
    final targetPath = path.join(activationLocation, 'example');
    occupancy.results[targetPath] = InspectedActivationOccupancy(
      managedSkillId: _skillId,
      slotKey: 'example',
      target: target,
      targetPath: targetPath,
      kind: InspectedActivationOccupancyKind.skillDirectory,
      contentRelation:
          InspectedActivationContentRelation.differsFromCurrentRevision,
      fingerprint: fingerprint,
      replaceable: true,
      existingDeclaredName: 'example',
      existingContentHash: 'b' * 64,
    );
  }

  Future<SkillsResult<T>> execute<T>(
    WorkspaceOperationKind kind,
    Object request, {
    CancellationToken? cancellationToken,
  }) => dispatcher.execute<T>(
    operationId: OperationId(_operationId),
    kind: kind,
    request: request,
    cancellationToken: cancellationToken ?? CancellationToken.none(),
    markBusinessCommitted: () {},
    reportProgress: (phase, {currentItem, completed = 0, total}) {},
  );

  Future<void> close() => snapshots.close();
}

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  _SnapshotReader(this.value);

  RepositorySnapshot value;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      value;
}

final class _ActivationMetadata implements ActivationMetadataReaderPort {
  _ActivationMetadata(this.values);

  List<PersistedActivation> values;

  @override
  Future<List<PersistedActivation>> readForSkills(
    Set<ManagedSkillId> managedSkillIds,
  ) async => values
      .where((value) => managedSkillIds.contains(value.managedSkillId))
      .toList(growable: false);
}

final class _ActivationPlans implements ActivationOperationPlanPort {
  int assemblies = 0;
  WorkspaceOperationKind? lastKind;
  ActivationMutationPlan? lastMutation;

  @override
  OperationPlan assemble({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositorySnapshot planningSnapshot,
    required WorkspaceOperationKind kind,
    required ActivationMutationPlan mutation,
    required List<OperationSubjectIntent> subjects,
  }) {
    assemblies += 1;
    lastKind = kind;
    lastMutation = mutation;
    final applying = <ApplyingOperationStep>[
      for (var index = 0; index < mutation.pathMutations.length; index += 1)
        ApplyingOperationStep(
          stepId: 'apply-${index + 1}',
          recoveryReference: RecoveryReference('apply-${index + 1}'),
          kind: ApplyingStepKind.materializationReplacement,
        ),
    ];
    return OperationPlan(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: expectedRepositoryRevision.next(),
      operationGeneration: expectedRepositoryRevision.next().value,
      preparationSteps: <PreparationOperationStep>[
        PreparationOperationStep(
          stepId: 'prepare',
          recoveryReference: RecoveryReference('prepare'),
          kind: PreparationStepKind.recoveryEvidence,
        ),
      ],
      applyingSteps: applying,
      finalizationSteps: <FinalizationOperationStep>[
        FinalizationOperationStep(
          stepId: 'finalize',
          recoveryReference: RecoveryReference('finalize'),
          kind: FinalizationStepKind.materializationVerification,
        ),
      ],
      revisionSelectionChanges: const <RevisionSelectionChangePlan>[],
      businessChanges: mutation.businessChanges,
      record: OperationRecordPlan(
        operationId: operationId,
        kind: kind.name,
        subjects: <OperationSubjectPlan>[
          for (var index = 0; index < subjects.length; index += 1)
            OperationSubjectPlan(
              reference: OperationSubjectReference(
                operationId: operationId,
                subjectId: '123e4567-e89b-42d3-8456-42661417420$index',
              ),
              managedSkillId: subjects[index].managedSkillId,
              displayName: subjects[index].displayName,
              beforeContentHash: subjects[index].beforeContentHash,
              afterContentHash: subjects[index].afterContentHash,
            ),
        ],
      ),
    );
  }
}

final class _ActivationIds implements ActivationIdentityPort {
  const _ActivationIds();

  @override
  String allocateActivationId() => _activationId;
}

final class _ForeignDraft implements ActivationTakeoverDraft {
  const _ForeignDraft();

  @override
  RepositoryRevision get reviewedRevision => RepositoryRevision.initial();

  @override
  List<OccupiedActivationTarget> get targets =>
      const <OccupiedActivationTarget>[];
}

final _now = DateTime.utc(2026, 8, 17, 12);
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174200');
const _agentId = 'custom';
const _operationId = '123e4567-e89b-42d3-b456-426614174201';
const _activationId = '123e4567-e89b-42d3-8456-426614174202';
const _secondActivationId = '123e4567-e89b-42d3-9456-426614174203';

AgentDefinition _agent(String globalSkillsPath) => AgentDefinition(
  id: _agentId,
  displayName: 'Custom',
  platforms: <DesktopPlatform, AgentPlatformDefinition>{
    DesktopPlatform.macos: AgentPlatformDefinition(
      globalSkillsPath: globalSkillsPath,
      detectionPaths: <AgentDetectionPath>[
        AgentDetectionPath.absolute('/agents'),
      ],
    ),
  },
);

ActivateRequest _activateRequest() => ActivateRequest(
  managedSkillIds: <ManagedSkillId>{_skillId},
  selection: ActivationSelection.explicit(<ActivationTarget>[
    ActivationTarget(agentId: _agentId, scope: ActivationScope.global),
  ]),
  mode: RequestedActivationMode.copy,
);

SkillActivation _activation({String location = '/agents/skills'}) =>
    SkillActivation(
      location: location,
      scope: ActivationScope.global,
      mode: ActivationMode.copy,
      agentIds: const <String>[_agentId],
    );

String _platformLocation(String value) => path.normalize(path.absolute(value));

PersistedActivation _persisted(SkillActivation activation, String id) =>
    PersistedActivation(
      activationId: id,
      managedSkillId: _skillId,
      activation: activation,
      createdAtMicros: 1,
    );

RepositorySnapshot _snapshot({
  int revision = 0,
  List<SkillActivation> activations = const <SkillActivation>[],
}) => RepositorySnapshot(
  revision: RepositoryRevision(revision),
  managedSkills: <ManagedSkill>[
    ManagedSkill(
      id: _skillId,
      slotKey: 'example',
      declaredName: 'example',
      displayName: 'Example',
      description: 'Example Skill',
      source: LocalSourceDescriptor(locator: '/source/example'),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        publishedAt: _now,
      ),
      activations: activations,
    ),
  ],
);
