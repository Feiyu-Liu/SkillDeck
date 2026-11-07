import 'dart:async';

import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/features/command_host/data/command_host_dispatcher.dart';
import 'package:skills_manager/features/command_host/data/write_command_handlers.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/agent_root_ownership_coordinator.dart';
import 'package:skills_manager/features/skills/data/repositories/ownership_gated_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/services/agent_root_ownership_repair_service.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import '../../support/fake_skills_workspace_repository.dart';
import '../../support/fake_skill_drift_reviews.dart';

void main() {
  test('Command Host returns ownership actionRequired without presenting or repairing', () async {
    final repository = FakeSkillsWorkspaceRepository(
      snapshot: _driftSnapshot(WorkspaceSkillId('drift-skill'), global: false),
    )..ownershipAudit = _issueAudit();
    addTearDown(repository.dispose);
    final presenter = _ReviewPresenter();
    final repair = _RepairService();
    final coordinator = AgentRootOwnershipCoordinator(
      repository: repository,
      repairService: repair,
      reviewPresenter: presenter,
    );
    final gated = OwnershipGatedSkillsWorkspaceRepository(
      delegate: repository,
      coordinator: coordinator,
    );
    final dispatcher = CommandHostDispatcher(
      writeCommandHandlers(
        snapshot: () => repository.current,
        repository: () => gated,
        updates: () => SkillUpdateStatus(states: {}),
        agents: () async => [
          WorkspaceAgentInfo(
            id: 'agent',
            displayName: 'Agent',
            isBuiltIn: true,
            supportedScopes: {WorkspaceScope.global},
            detectedGlobally: true,
            detectedProjectRootIds: {},
          ),
        ],
        members: () async => {'agent'},
      ),
    );
    final result = await dispatcher.dispatch(
      CommandRequest(
        command: 'activate',
        arguments: {
          'selection': SkillSelection(all: true).toJson(),
          'agents': ['agent'],
        },
      ),
    );
    expect(commandExitCode(result), 5);
    expect(result.error!.code, 'agentRootOwnershipRepairRequired');
    expect(result.error!.details, {'screen': 'settings'});
    expect(presenter.calls, 0);
    expect(repair.calls, 0);
    expect(repository.activations, isEmpty);
    // GUI callers retain their interactive path after the opt-in scope ends.
    await gated.adopt(_adoption).completed;
    expect(presenter.calls, 1);
  });

  test(
    'non-interactive ownership inspection never joins a pending GUI review',
    () async {
      final repository = FakeSkillsWorkspaceRepository()
        ..ownershipAudit = _issueAudit();
      addTearDown(repository.dispose);
      final presenter = _ReviewPresenter()..gate = Completer<Set<String>?>();
      final coordinator = AgentRootOwnershipCoordinator(
        repository: repository,
        repairService: _RepairService(),
        reviewPresenter: presenter,
      );
      final gui = coordinator.ensureReady(WorkspaceOperationKind.activate);
      await presenter.entered.future;
      final failure =
          await AgentRootOwnershipCoordinator.withoutInteractiveRepair(
            () => coordinator.ensureReady(WorkspaceOperationKind.activate),
          );
      expect(failure!.context['reason'], 'agentRootOwnershipRepairRequired');
      expect(presenter.calls, 1);
      presenter.gate!.complete(null);
      await gui;
    },
  );

  test('clean audit is cached across gated mutations', () async {
    final repository = FakeSkillsWorkspaceRepository();
    final coordinator = AgentRootOwnershipCoordinator(
      repository: repository,
      repairService: _RepairService(),
      reviewPresenter: _ReviewPresenter(),
    );
    final gated = OwnershipGatedSkillsWorkspaceRepository(
      delegate: repository,
      coordinator: coordinator,
    );

    await gated.adopt(_adoption).completed;
    await gated.adopt(_adoption).completed;

    expect(repository.ownershipInspections, 1);
    expect(repository.adoptionRequests, hasLength(2));
  });

  test('review cancellation prevents the original mutation', () async {
    final repository = FakeSkillsWorkspaceRepository()
      ..ownershipAudit = _issueAudit();
    final coordinator = AgentRootOwnershipCoordinator(
      repository: repository,
      repairService: _RepairService(),
      reviewPresenter: _ReviewPresenter(result: null),
    );
    final gated = OwnershipGatedSkillsWorkspaceRepository(
      delegate: repository,
      coordinator: coordinator,
    );

    final completion = await gated.adopt(_adoption).completed;

    expect(
      completion,
      isA<WorkspaceFailed<WorkspaceMutationReceipt>>().having(
        (failure) => failure.failure.code,
        'code',
        WorkspaceErrorCode.operationCancelled,
      ),
    );
    expect(repository.adoptionRequests, isEmpty);
  });

  test('repairs once, re-inspects, and continues exactly once', () async {
    final repository = FakeSkillsWorkspaceRepository()
      ..ownershipAudits.addAll(<WorkspaceAgentRootOwnershipAudit>[
        _issueAudit(),
        _cleanAudit(),
      ]);
    final repair = _RepairService();
    final coordinator = AgentRootOwnershipCoordinator(
      repository: repository,
      repairService: repair,
      reviewPresenter: _ReviewPresenter(
        result: const {'/Users/tester/.agent/skills'},
      ),
    );
    final gated = OwnershipGatedSkillsWorkspaceRepository(
      delegate: repository,
      coordinator: coordinator,
    );

    final completion = await gated.adopt(_adoption).completed;

    expect(completion, isA<WorkspaceCompleted<WorkspaceMutationReceipt>>());
    expect(repository.ownershipInspections, 2);
    expect(repair.calls, 1);
    expect(repair.reviewedRootPaths, <String>{'/Users/tester/.agent/skills'});
    expect(repository.adoptionRequests, hasLength(1));
  });

  test(
    'post-repair issues stop the mutation with diagnostic context',
    () async {
      final repository = FakeSkillsWorkspaceRepository()
        ..ownershipAudits.addAll(<WorkspaceAgentRootOwnershipAudit>[
          _issueAudit(),
          _issueAudit(),
        ]);
      final coordinator = AgentRootOwnershipCoordinator(
        repository: repository,
        repairService: _RepairService(),
        reviewPresenter: _ReviewPresenter(
          result: const {'/Users/tester/.agent/skills'},
        ),
      );
      final gated = OwnershipGatedSkillsWorkspaceRepository(
        delegate: repository,
        coordinator: coordinator,
      );

      final completion = await gated.adopt(_adoption).completed;

      final failure =
          (completion as WorkspaceFailed<WorkspaceMutationReceipt>).failure;
      expect(failure.context, <String, Object?>{
        'reason': 'agentRootOwnershipStillInvalid',
        'issueReason': 'ownerMismatch',
        'rootPath': '/Users/tester/.agent/skills',
        'issueCount': 1,
        'issues': [
          {
            'issueReason': 'ownerMismatch',
            'rootPath': '/Users/tester/.agent/skills',
          },
        ],
      });
      expect(repository.adoptionRequests, isEmpty);
    },
  );

  test('Project-only install bypasses the global ownership gate', () async {
    final repository = FakeSkillsWorkspaceRepository()
      ..ownershipAudit = _issueAudit();
    final coordinator = AgentRootOwnershipCoordinator(
      repository: repository,
      repairService: _RepairService(),
      reviewPresenter: _ReviewPresenter(result: null),
    );
    final gated = OwnershipGatedSkillsWorkspaceRepository(
      delegate: repository,
      coordinator: coordinator,
    );

    final completion = await gated
        .install(
          WorkspaceInstallRequest(
            source: const SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: '/source',
            ),
            scope: WorkspaceScope.project,
            projectRootId: 'project',
          ),
        )
        .completed;

    expect(
      completion,
      isA<WorkspaceCompleted<WorkspaceInstallAttempt>>().having(
        (completed) => completed.value,
        'value',
        isA<WorkspaceInstallCompleted>(),
      ),
    );
    expect(repository.ownershipInspections, 0);
    expect(repository.installRequests, hasLength(1));
  });

  test(
    'blocked audit reports every blocked folder but no repairable one',
    () async {
      final repository = FakeSkillsWorkspaceRepository()
        ..ownershipAudit = WorkspaceAgentRootOwnershipAudit(
          supported: true,
          currentUserId: 501,
          examinedRootCount: 3,
          issues: [
            WorkspaceAgentRootOwnershipIssue(
              rootPath: '/Users/tester/.repairable/skills',
              agentIds: const {'repairable'},
              roles: const {WorkspaceAgentSkillRootRole.canonicalActivation},
              reason: WorkspaceAgentRootOwnershipIssueReason.ownerMismatch,
              repairable: true,
            ),
            WorkspaceAgentRootOwnershipIssue(
              rootPath: '/Users/tester/.agent/skills',
              agentIds: const {'agent'},
              roles: const {WorkspaceAgentSkillRootRole.canonicalActivation},
              reason: WorkspaceAgentRootOwnershipIssueReason.notDirectory,
              repairable: false,
            ),
            WorkspaceAgentRootOwnershipIssue(
              rootPath: '/opt/agent/skills',
              agentIds: const {'outside'},
              roles: const {WorkspaceAgentSkillRootRole.compatibilityDiscovery},
              reason: WorkspaceAgentRootOwnershipIssueReason.outsideUserHome,
              repairable: false,
            ),
          ],
        );
      final repairService = _RepairService();
      final reviewPresenter = _ReviewPresenter();
      final coordinator = AgentRootOwnershipCoordinator(
        repository: repository,
        repairService: repairService,
        reviewPresenter: reviewPresenter,
      );
      final gated = OwnershipGatedSkillsWorkspaceRepository(
        delegate: repository,
        coordinator: coordinator,
      );

      final completion = await gated.adopt(_adoption).completed;

      final failure =
          (completion as WorkspaceFailed<WorkspaceMutationReceipt>).failure;
      expect(failure.code, WorkspaceErrorCode.agentRootOwnership);
      expect(failure.context, <String, Object?>{
        'reason': 'agentRootOwnershipBlocked',
        'issueReason': 'notDirectory',
        'rootPath': '/Users/tester/.agent/skills',
        'issueCount': 2,
        'issues': [
          {
            'issueReason': 'notDirectory',
            'rootPath': '/Users/tester/.agent/skills',
          },
          {'issueReason': 'outsideUserHome', 'rootPath': '/opt/agent/skills'},
        ],
      });
      expect(failure.recoveryPolicy, AppRecoveryPolicy.refreshThenReview);
      // A blocked folder stops the operation before any repair is offered.
      expect(reviewPresenter.calls, 0);
      expect(repairService.calls, 0);
      expect(repository.adoptionRequests, isEmpty);
    },
  );
  for (final scenario in [
    (
      label: 'keep repository content with global Activation',
      keep: true,
      driftScope: null,
      missing: 0,
      currentGlobal: true,
      gated: true,
    ),
    (
      label: 'keep project-only content without global Activations',
      keep: true,
      driftScope: WorkspaceScope.project,
      missing: 0,
      currentGlobal: false,
      gated: false,
    ),
    (
      label: 'restore reviewed global Activation',
      keep: false,
      driftScope: WorkspaceScope.global,
      missing: 0,
      currentGlobal: true,
      gated: true,
    ),
    (
      label: 'restore project drift leaving global Activation untouched',
      keep: false,
      driftScope: WorkspaceScope.project,
      missing: 0,
      currentGlobal: true,
      gated: false,
    ),
    (
      label: 'restore Repository Copy only',
      keep: false,
      driftScope: null,
      missing: 0,
      currentGlobal: true,
      gated: false,
    ),
    (
      label: 'restore unknown missing location conservatively gates global',
      keep: false,
      driftScope: WorkspaceScope.project,
      missing: 1,
      currentGlobal: true,
      gated: true,
    ),
    (
      label: 'restore project-only missing location',
      keep: false,
      driftScope: WorkspaceScope.project,
      missing: 1,
      currentGlobal: false,
      gated: false,
    ),
  ]) {
    test('drift ownership: ${scenario.label}', () async {
      final id = WorkspaceSkillId('drift-skill');
      final delegate = FakeSkillsWorkspaceRepository(
        snapshot: _driftSnapshot(id, global: scenario.currentGlobal),
      )..ownershipAudit = _issueAudit();
      addTearDown(delegate.dispose);
      final gated = OwnershipGatedSkillsWorkspaceRepository(
        delegate: delegate,
        coordinator: AgentRootOwnershipCoordinator(
          repository: delegate,
          repairService: _RepairService(),
          reviewPresenter: _ReviewPresenter(result: null),
        ),
      );
      final review = FakeWorkspaceSkillDriftReview(
        skillId: id,
        missingArtifactCount: scenario.missing,
        artifacts: [
          WorkspaceDriftedArtifact(
            artifactId: 'artifact',
            locationKind: scenario.driftScope == null
                ? WorkspaceDriftLocationKind.repositoryCopy
                : WorkspaceDriftLocationKind.copyActivation,
            driftKind: WorkspaceDriftKind.contentChanged,
            scope: scenario.driftScope,
            canKeepExternal: true,
            canExport: true,
          ),
        ],
      );
      final completion = await gated
          .resolveSkillDrift(
            review: review,
            resolution: scenario.keep
                ? const WorkspaceDriftResolution.keepExternal('artifact')
                : const WorkspaceDriftResolution.restoreManaged(),
          )
          .completed;
      expect(delegate.ownershipInspections, scenario.gated ? 1 : 0);
      expect(delegate.resolvedSkillDrifts, hasLength(scenario.gated ? 0 : 1));
      if (scenario.gated) {
        expect(
          (completion as WorkspaceFailed<WorkspaceMutationReceipt>)
              .failure
              .code,
          WorkspaceErrorCode.operationCancelled,
        );
      } else {
        expect(completion, isA<WorkspaceCompleted<WorkspaceMutationReceipt>>());
      }
    });
  }

  test('drift inspection and export always bypass ownership gating', () async {
    final id = WorkspaceSkillId('drift-skill');
    final delegate = FakeSkillsWorkspaceRepository(
      snapshot: _driftSnapshot(id, global: true),
    )..ownershipAudit = _issueAudit();
    addTearDown(delegate.dispose);
    final gated = OwnershipGatedSkillsWorkspaceRepository(
      delegate: delegate,
      coordinator: AgentRootOwnershipCoordinator(
        repository: delegate,
        repairService: _RepairService(),
        reviewPresenter: _ReviewPresenter(result: null),
      ),
    );
    final review =
        (await gated.inspectSkillDrift(id).completed
                as WorkspaceCompleted<WorkspaceSkillDriftReview>)
            .value;
    await gated
        .exportSkillDriftArtifact(
          review: review,
          artifactId: 'artifact',
          destinationDirectory: '/exports',
        )
        .completed;
    expect(delegate.inspectedSkillDrifts, [id]);
    expect(delegate.exportedSkillDriftArtifacts.single.review, same(review));
    expect(delegate.ownershipInspections, 0);
  });
}

final _adoption = ExternalSkillAdoptionRequest(
  slotKey: 'example',
  authoritativeLocation: '/source/example',
  reviewedContentHashByLocation: {'/source/example': 'hash'},
);

WorkspaceAgentRootOwnershipAudit _cleanAudit() =>
    WorkspaceAgentRootOwnershipAudit(
      supported: true,
      currentUserId: 501,
      examinedRootCount: 1,
      issues: const [],
    );

WorkspaceAgentRootOwnershipAudit _issueAudit() =>
    WorkspaceAgentRootOwnershipAudit(
      supported: true,
      currentUserId: 501,
      examinedRootCount: 1,
      issues: [
        WorkspaceAgentRootOwnershipIssue(
          rootPath: '/Users/tester/.agent/skills',
          agentIds: const {'agent'},
          roles: const {WorkspaceAgentSkillRootRole.canonicalActivation},
          reason: WorkspaceAgentRootOwnershipIssueReason.ownerMismatch,
          repairable: true,
        ),
      ],
    );

final class _ReviewPresenter implements AgentRootOwnershipReviewPresenter {
  _ReviewPresenter({this.result = const <String>{}});

  final Set<String>? result;
  int calls = 0;
  final entered = Completer<void>();
  Completer<Set<String>?>? gate;

  @override
  Future<Set<String>?> review(WorkspaceAgentRootOwnershipAudit audit) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    return gate == null ? result : await gate!.future;
  }
}

final class _RepairService implements AgentRootOwnershipRepairService {
  int calls = 0;
  Set<String>? reviewedRootPaths;

  @override
  Future<AgentRootOwnershipRepairOutcome> repair({
    required WorkspaceAgentRootOwnershipAudit audit,
    required Set<String> reviewedRootPaths,
  }) async {
    calls += 1;
    this.reviewedRootPaths = Set.unmodifiable(reviewedRootPaths);
    return AgentRootOwnershipRepairOutcome.succeeded;
  }
}

SkillsWorkspaceSnapshot _driftSnapshot(
  WorkspaceSkillId id, {
  required bool global,
}) => SkillsWorkspaceSnapshot(
  revision: 0,
  projectRoots: const [],
  skills: [
    WorkspaceSkill(
      id: id,
      slotKey: 'drift-skill',
      declaredName: 'drift-skill',
      displayName: 'Drift Skill',
      description: 'Review',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/source',
      ),
      currentRevision: SkillRevision(
        contentHash: 'hash',
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime.utc(2026, 10, 14),
      ),
      activations: [
        SkillActivationLocation(
          location: '/agent/skills',
          scope: global ? WorkspaceScope.global : WorkspaceScope.project,
          mode: WorkspaceActivationMode.copy,
          agentIds: ['agent'],
          projectRootId: global ? null : 'project',
        ),
      ],
    ),
  ],
);
