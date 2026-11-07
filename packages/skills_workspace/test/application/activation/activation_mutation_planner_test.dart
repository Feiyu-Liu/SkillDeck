import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_mutation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_mutation_planner.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/activation_mutation_ports.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  late _ActivationIds identities;
  late ActivationMutationPlanner planner;

  setUp(() {
    identities = _ActivationIds();
    planner = ActivationMutationPlanner(
      locationIdentity: const PosixActivationLocationIdentity(),
      identities: identities,
      clock: () => _now,
    );
  });

  test('plans a vacant copy target and one Activation row', () {
    final result = planner.activate(
      snapshot: _snapshot(),
      managedSkillIds: <ManagedSkillId>{_skillId},
      resolvedTargets: _targets(mode: ActivationMode.copy),
      occupancies: const <InspectedActivationOccupancy>[],
      persistedActivations: const <PersistedActivation>[],
    );

    final plan = result.valueOrNull!;
    expect(plan.changed, isTrue);
    final mutation = plan.businessChanges.mutations.single as PutActivation;
    expect(mutation.activationId, _activationId);
    expect(mutation.canonicalPath, '/agents/skills');
    expect(mutation.createdAtMicros, _now.microsecondsSinceEpoch);
    final materialization =
        plan.pathMutations.single as MaterializeActivationPath;
    expect(materialization.targetPath, path.join('/agents/skills', 'example'));
    expect(
      materialization.expectation.kind,
      ActivationTargetExpectationKind.vacant,
    );
  });

  test('merges shared-location agents without replacing equal bytes', () {
    final existing = SkillActivation(
      location: '/agents/skills',
      scope: ActivationScope.global,
      mode: ActivationMode.copy,
      agentIds: const <String>['alpha'],
    );
    final result = planner.activate(
      snapshot: _snapshot(activations: <SkillActivation>[existing]),
      managedSkillIds: <ManagedSkillId>{_skillId},
      resolvedTargets: _targets(
        mode: ActivationMode.copy,
        agentIds: const <String>['beta'],
      ),
      occupancies: const <InspectedActivationOccupancy>[],
      persistedActivations: <PersistedActivation>[_persisted(existing)],
    );

    final plan = result.valueOrNull!;
    expect(plan.pathMutations, isEmpty);
    final mutation = plan.businessChanges.mutations.single as PutActivation;
    expect(mutation.activationId, _activationId);
    expect(mutation.agentIds, <String>['alpha', 'beta']);
    expect(mutation.createdAtMicros, 10);
    expect(identities.allocations, 0);
  });

  test('mode change replaces the managed target with retained identity', () {
    final existing = SkillActivation(
      location: '/agents/skills',
      scope: ActivationScope.global,
      mode: ActivationMode.copy,
      agentIds: const <String>['alpha'],
    );
    final result = planner.activate(
      snapshot: _snapshot(activations: <SkillActivation>[existing]),
      managedSkillIds: <ManagedSkillId>{_skillId},
      resolvedTargets: _targets(mode: ActivationMode.symbolicLink),
      occupancies: const <InspectedActivationOccupancy>[],
      persistedActivations: <PersistedActivation>[_persisted(existing)],
    );

    final plan = result.valueOrNull!;
    final pathChange = plan.pathMutations.single as MaterializeActivationPath;
    expect(
      pathChange.expectation.kind,
      ActivationTargetExpectationKind.managed,
    );
    expect(
      (plan.businessChanges.mutations.single as PutActivation).activationId,
      _activationId,
    );
  });

  test('occupied unmanaged target freezes its reviewed fingerprint', () {
    final target = _targets(mode: ActivationMode.copy).targets.single;
    final occupancy = InspectedActivationOccupancy(
      managedSkillId: _skillId,
      slotKey: 'example',
      target: target,
      targetPath: path.join('/agents/skills', 'example'),
      kind: InspectedActivationOccupancyKind.skillDirectory,
      contentRelation:
          InspectedActivationContentRelation.differsFromCurrentRevision,
      fingerprint: 'skillDirectory:reviewed',
      replaceable: true,
    );

    final result = planner.activate(
      snapshot: _snapshot(),
      managedSkillIds: <ManagedSkillId>{_skillId},
      resolvedTargets: _targets(mode: ActivationMode.copy),
      occupancies: <InspectedActivationOccupancy>[occupancy],
      persistedActivations: const <PersistedActivation>[],
    );

    final expectation =
        (result.valueOrNull!.pathMutations.single as MaterializeActivationPath)
            .expectation;
    expect(
      expectation.kind,
      ActivationTargetExpectationKind.occupiedFingerprint,
    );
    expect(expectation.fingerprint, 'skillDirectory:reviewed');
  });

  test('existing repository link is adopted without rewriting the link', () {
    final target = _targets(mode: ActivationMode.symbolicLink).targets.single;
    final occupancy = InspectedActivationOccupancy(
      managedSkillId: _skillId,
      slotKey: 'example',
      target: target,
      targetPath: path.join('/agents/skills', 'example'),
      kind: InspectedActivationOccupancyKind.skillSymbolicLink,
      contentRelation:
          InspectedActivationContentRelation.matchesCurrentRevision,
      fingerprint: 'skillSymbolicLink:reviewed',
      replaceable: true,
      pointsToRepositoryCopy: true,
    );

    final result = planner.activate(
      snapshot: _snapshot(),
      managedSkillIds: <ManagedSkillId>{_skillId},
      resolvedTargets: _targets(mode: ActivationMode.symbolicLink),
      occupancies: <InspectedActivationOccupancy>[occupancy],
      persistedActivations: const <PersistedActivation>[],
    );

    expect(result.valueOrNull!.pathMutations, isEmpty);
    expect(
      result.valueOrNull!.businessChanges.mutations.single,
      isA<PutActivation>(),
    );
  });

  test('rejects conflicting provenance at one canonical location', () {
    final existing = SkillActivation(
      location: '/agents/skills',
      scope: ActivationScope.global,
      mode: ActivationMode.copy,
      agentIds: const <String>['alpha'],
    );
    final target = ResolvedActivationTarget(
      location: '/agents/skills',
      scope: ActivationScope.project,
      mode: ActivationMode.copy,
      agentIds: const <String>['alpha'],
      projectRootId: 'project',
      projectRootPath: '/project',
    );

    final result = planner.activate(
      snapshot: _snapshot(activations: <SkillActivation>[existing]),
      managedSkillIds: <ManagedSkillId>{_skillId},
      resolvedTargets: ResolvedActivationTargets(
        targets: <ResolvedActivationTarget>[target],
      ),
      occupancies: const <InspectedActivationOccupancy>[],
      persistedActivations: <PersistedActivation>[_persisted(existing)],
    );

    expect(
      result.failureOrNull?.code,
      ActivationMutationFailureCode.activationUnsupported,
    );
  });

  test('deactivate selects canonical locations and preserves others', () {
    final first = SkillActivation(
      location: '/agents/first',
      scope: ActivationScope.global,
      mode: ActivationMode.copy,
      agentIds: const <String>['first'],
    );
    final second = SkillActivation(
      location: '/agents/second',
      scope: ActivationScope.global,
      mode: ActivationMode.symbolicLink,
      agentIds: const <String>['second'],
    );
    final result = planner.deactivate(
      snapshot: _snapshot(activations: <SkillActivation>[first, second]),
      managedSkillIds: <ManagedSkillId>{_skillId},
      locations: const <String>{'/agents/second'},
      persistedActivations: <PersistedActivation>[
        _persisted(first, id: _firstActivationId),
        _persisted(second, id: _secondActivationId),
      ],
    );

    final plan = result.valueOrNull!;
    expect(
      (plan.businessChanges.mutations.single as DeleteActivation).activationId,
      _secondActivationId,
    );
    expect(
      (plan.pathMutations.single as DeleteActivationPath).targetPath,
      path.join('/agents/second', 'example'),
    );
  });

  test(
    'missing Skill and mismatched SQLite projection fail before planning',
    () {
      final missing = planner.activate(
        snapshot: _snapshot(),
        managedSkillIds: <ManagedSkillId>{_missingId},
        resolvedTargets: _targets(mode: ActivationMode.copy),
        occupancies: const <InspectedActivationOccupancy>[],
        persistedActivations: const <PersistedActivation>[],
      );
      expect(
        missing.failureOrNull?.code,
        ActivationMutationFailureCode.skillNotFound,
      );

      final activation = SkillActivation(
        location: '/agents/skills',
        scope: ActivationScope.global,
        mode: ActivationMode.copy,
        agentIds: const <String>['alpha'],
      );
      final mismatched = planner.deactivate(
        snapshot: _snapshot(activations: <SkillActivation>[activation]),
        managedSkillIds: <ManagedSkillId>{_skillId},
        locations: null,
        persistedActivations: const <PersistedActivation>[],
      );
      expect(
        mismatched.failureOrNull?.code,
        ActivationMutationFailureCode.stateInconsistent,
      );
    },
  );
}

final _now = DateTime.utc(2026, 8, 17, 12);
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174100');
final _missingId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174101');
const _activationId = '123e4567-e89b-42d3-b456-426614174102';
const _firstActivationId = '123e4567-e89b-42d3-8456-426614174103';
const _secondActivationId = '123e4567-e89b-42d3-9456-426614174104';

RepositorySnapshot _snapshot({
  List<SkillActivation> activations = const <SkillActivation>[],
}) => RepositorySnapshot(
  revision: RepositoryRevision.initial(),
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

ResolvedActivationTargets _targets({
  required ActivationMode mode,
  List<String> agentIds = const <String>['alpha'],
}) => ResolvedActivationTargets(
  targets: <ResolvedActivationTarget>[
    ResolvedActivationTarget(
      location: '/agents/skills',
      scope: ActivationScope.global,
      mode: mode,
      agentIds: agentIds,
    ),
  ],
);

PersistedActivation _persisted(
  SkillActivation activation, {
  String id = _activationId,
}) => PersistedActivation(
  activationId: id,
  managedSkillId: _skillId,
  activation: activation,
  createdAtMicros: 10,
);

final class _ActivationIds implements ActivationIdentityPort {
  int allocations = 0;

  @override
  String allocateActivationId() {
    allocations += 1;
    return _activationId;
  }
}
