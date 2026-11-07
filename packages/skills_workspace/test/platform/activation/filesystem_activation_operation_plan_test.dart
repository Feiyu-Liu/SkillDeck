import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_mutation_models.dart';
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/activation_mutation_ports.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/infrastructure/activation/workspace_activation_materialization_paths.dart';
import 'package:skills_workspace/src/platform/activation/filesystem_activation_operation_plan.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/operations/filesystem_operation_recovery.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late WorkspaceLayout layout;
  late PlatformDurableWorkspaceFilesystem filesystem;
  late OperationRecoverySpecRegistry registry;
  late _Expectation expectations;
  late FilesystemActivationOperationPlan plans;
  late FilesystemOperationRecovery recovery;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'activation-operation-plan-',
    );
    layout = WorkspaceLayout(path.join(temporary.path, 'workspace'));
    filesystem = PlatformDurableWorkspaceFilesystem();
    registry = OperationRecoverySpecRegistry();
    expectations = _Expectation();
    plans = FilesystemActivationOperationPlan(
      materializationPaths: WorkspaceActivationMaterializationPaths(
        layout: layout,
      ),
      assembler: OperationPlanAssembler(
        subjectIdentities: const _SubjectIds(),
        recoveryPlans: const _UnusedRecoveryPlans(),
      ),
      recoverySpecs: registry,
      targetExpectations: expectations,
    );
    recovery = FilesystemOperationRecovery(
      layout: layout,
      filesystem: filesystem,
      registry: registry,
      backupMaintenance: _BackupMaintenance(),
    );
    await _writeSkill(layout.repositoryCopyPath('example'), 'managed');
  });

  tearDown(() async {
    if (!await temporary.exists()) return;
    await for (final entity in temporary.list(followLinks: false)) {
      await filesystem.removeOwnedPath(
        targetPath: entity.path,
        ownerRoot: temporary.path,
      );
    }
    await temporary.delete();
  });

  test('copy apply and pre-commit rollback restore occupied bytes', () async {
    final target = path.join(temporary.path, 'agent', 'example');
    await _writeSkill(target, 'external');
    final plan = _assemble(
      plans,
      snapshot: _snapshot(),
      pathMutation: _materialize(
        targetPath: target,
        mode: ActivationMode.copy,
        expectation: ActivationTargetExpectation.occupied('reviewed'),
      ),
    );

    await recovery.prepareStep(
      plan.preparationSteps.single,
      CancellationToken.none(),
    );
    await recovery.applyStep(
      plan.applyingSteps.single,
      CancellationToken.none(),
    );
    expect(await _skillBody(target), 'managed');

    await recovery.rollback(
      plan,
      observedPhase: OperationJournalPhase.applying,
    );
    await recovery.rollback(
      plan,
      observedPhase: OperationJournalPhase.applying,
    );
    expect(await _skillBody(target), 'external');
  });

  test(
    'target change after capture is rejected instead of overwritten',
    () async {
      final target = path.join(temporary.path, 'agent', 'example');
      await _writeSkill(target, 'external');
      final plan = _assemble(
        plans,
        snapshot: _snapshot(),
        pathMutation: _materialize(
          targetPath: target,
          mode: ActivationMode.copy,
          expectation: ActivationTargetExpectation.occupied('reviewed'),
        ),
      );
      await recovery.prepareStep(
        plan.preparationSteps.single,
        CancellationToken.none(),
      );
      await File(path.join(target, 'SKILL.md')).writeAsString('changed');

      await expectLater(
        recovery.applyStep(plan.applyingSteps.single, CancellationToken.none()),
        throwsA(
          isA<OperationRecoveryException>().having(
            (error) => error.reason,
            'reason',
            OperationRecoveryFailureReason.entryTypeChanged,
          ),
        ),
      );
      expect(await _skillBody(target), 'changed');
    },
  );

  test(
    'reviewed precondition fails before publishing recovery evidence',
    () async {
      expectations.matchesResult = false;
      final target = path.join(temporary.path, 'agent', 'example');
      await _writeSkill(target, 'external');
      final plan = _assemble(
        plans,
        snapshot: _snapshot(),
        pathMutation: _materialize(
          targetPath: target,
          mode: ActivationMode.copy,
          expectation: ActivationTargetExpectation.occupied('reviewed'),
        ),
      );

      await expectLater(
        recovery.prepareStep(
          plan.preparationSteps.single,
          CancellationToken.none(),
        ),
        throwsA(isA<ExternalOperationPreconditionChanged>()),
      );

      expect(await _skillBody(target), 'external');
      expect(
        await Directory(
          layout.operationRecoveryPath(plan.operationId),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'symbolic-link target is stored directly and rollback removes it',
    () async {
      if (Platform.isWindows) return;
      final target = path.join(temporary.path, 'agent', 'example');
      final plan = _assemble(
        plans,
        snapshot: _snapshot(),
        pathMutation: _materialize(
          targetPath: target,
          mode: ActivationMode.symbolicLink,
          expectation: const ActivationTargetExpectation.vacant(),
        ),
      );

      await recovery.prepareStep(
        plan.preparationSteps.single,
        CancellationToken.none(),
      );
      await recovery.applyStep(
        plan.applyingSteps.single,
        CancellationToken.none(),
      );
      expect(await Link(target).target(), layout.repositoryCopyPath('example'));

      await recovery.rollback(
        plan,
        observedPhase: OperationJournalPhase.applying,
      );
      expect(
        await FileSystemEntity.type(target, followLinks: false),
        FileSystemEntityType.notFound,
      );
    },
  );

  test('Deactivate deletion is recoverable before commit', () async {
    final target = path.join(temporary.path, 'agent', 'example');
    await _writeSkill(target, 'published');
    final plan = _assemble(
      plans,
      snapshot: _snapshot(activations: <SkillActivation>[_activation()]),
      pathMutation: DeleteActivationPath(
        managedSkillId: _skillId,
        slotKey: 'example',
        targetPath: target,
      ),
      delete: true,
    );

    await recovery.prepareStep(
      plan.preparationSteps.single,
      CancellationToken.none(),
    );
    await recovery.applyStep(
      plan.applyingSteps.single,
      CancellationToken.none(),
    );
    expect(await Directory(target).exists(), isFalse);

    await recovery.rollback(
      plan,
      observedPhase: OperationJournalPhase.applying,
    );
    expect(await _skillBody(target), 'published');
  });

  test(
    'fresh recovery adapter rolls committed plan forward from bundle',
    () async {
      final target = path.join(temporary.path, 'agent', 'example');
      final plan = _assemble(
        plans,
        snapshot: _snapshot(),
        pathMutation: _materialize(
          targetPath: target,
          mode: ActivationMode.copy,
          expectation: const ActivationTargetExpectation.vacant(),
        ),
      );
      await recovery.prepareStep(
        plan.preparationSteps.single,
        CancellationToken.none(),
      );

      final restarted = FilesystemOperationRecovery(
        layout: layout,
        filesystem: filesystem,
        registry: OperationRecoverySpecRegistry(),
        backupMaintenance: _BackupMaintenance(),
      );
      await restarted.rollForward(plan);
      await restarted.rollForward(plan);

      expect(await _skillBody(target), 'managed');
    },
  );
}

OperationPlan _assemble(
  FilesystemActivationOperationPlan plans, {
  required RepositorySnapshot snapshot,
  required ActivationPathMutation pathMutation,
  bool delete = false,
}) => plans.assemble(
  operationId: OperationId(_operationId),
  expectedRepositoryRevision: snapshot.revision,
  planningSnapshot: snapshot,
  kind: delete
      ? WorkspaceOperationKind.deactivate
      : WorkspaceOperationKind.activate,
  mutation: ActivationMutationPlan(
    businessChanges: WorkspaceBusinessChangeSet(
      mutations: <WorkspaceBusinessMutation>[
        if (delete)
          DeleteActivation(_activationId)
        else
          PutActivation(
            activationId: _activationId,
            managedSkillId: _skillId,
            canonicalPath: path.dirname(pathMutation.targetPath),
            scope: WorkspaceActivationScope.global,
            mode:
                (pathMutation as MaterializeActivationPath).target.mode ==
                    ActivationMode.copy
                ? WorkspaceActivationMode.copy
                : WorkspaceActivationMode.symbolicLink,
            projectRootId: null,
            projectRootPath: null,
            agentIds: const <String>['agent'],
            createdAtMicros: 1,
          ),
      ],
    ),
    pathMutations: <ActivationPathMutation>[pathMutation],
    affectedSkillIds: <ManagedSkillId>{_skillId},
  ),
  subjects: <OperationSubjectIntent>[
    OperationSubjectIntent(
      managedSkillId: _skillId,
      displayName: 'Example',
      beforeContentHash: 'a' * 64,
      afterContentHash: 'a' * 64,
    ),
  ],
);

MaterializeActivationPath _materialize({
  required String targetPath,
  required ActivationMode mode,
  required ActivationTargetExpectation expectation,
}) => MaterializeActivationPath(
  managedSkillId: _skillId,
  slotKey: 'example',
  targetPath: targetPath,
  target: ResolvedActivationTarget(
    location: path.dirname(targetPath),
    scope: ActivationScope.global,
    mode: mode,
    agentIds: const <String>['agent'],
  ),
  expectation: expectation,
);

Future<void> _writeSkill(String root, String body) async {
  await Directory(root).create(recursive: true);
  await File(path.join(root, 'SKILL.md')).writeAsString(body);
}

Future<String> _skillBody(String root) =>
    File(path.join(root, 'SKILL.md')).readAsString();

final class _Expectation implements ActivationTargetExpectationPort {
  bool matchesResult = true;
  int calls = 0;

  @override
  Future<bool> matches({
    required ManagedSkill skill,
    required ResolvedActivationTarget target,
    required String targetPath,
    required ActivationTargetExpectation expectation,
  }) async {
    calls += 1;
    return matchesResult;
  }
}

final class _SubjectIds implements OperationSubjectIdentityPort {
  const _SubjectIds();

  @override
  String allocateOperationSubjectId() => _subjectId;
}

final class _UnusedRecoveryPlans implements OperationRecoveryPlanFactoryPort {
  const _UnusedRecoveryPlans();

  @override
  List<PreparationOperationStep> createDestructiveEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
  }) => throw UnsupportedError('not used');

  @override
  OperationRecoveryPlanSteps createDestructive({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required DestructiveOperationRecoveryIntent intent,
  }) => throw UnsupportedError('not used');

  @override
  OperationRecoveryPlanSteps createSqliteOnly({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required bool destructive,
  }) => throw UnsupportedError('not used');
}

final class _BackupMaintenance
    implements OperationRecoveryBackupMaintenancePort {
  @override
  Future<void> armDestructiveBarrier(OperationRecoveryContext context) async {}

  @override
  Future<void> completeCommittedDestruction(
    OperationRecoveryContext context,
  ) async {}

  @override
  Future<void> restoreSteadyAfterProvenRollback(
    OperationRecoveryContext context,
  ) async {}

  @override
  Future<void> rotate(OperationRecoveryContext context) async {}
}

SkillActivation _activation() => SkillActivation(
  location: '/unused',
  scope: ActivationScope.global,
  mode: ActivationMode.copy,
  agentIds: const <String>['agent'],
);

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
        publishedAt: DateTime.utc(2026, 8, 17),
      ),
      activations: activations,
    ),
  ],
);

final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174300');
const _operationId = '123e4567-e89b-42d3-b456-426614174301';
const _activationId = '123e4567-e89b-42d3-8456-426614174302';
const _subjectId = '123e4567-e89b-42d3-9456-426614174303';
