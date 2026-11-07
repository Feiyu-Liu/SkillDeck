import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_target_resolver.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog.dart';
import 'package:skills_workspace/src/application/discovery/external_discovery_models.dart';
import 'package:skills_workspace/src/application/discovery/external_skill_scanner.dart';
import 'package:skills_workspace/src/application/install/initial_import_models.dart';
import 'package:skills_workspace/src/application/install/initial_import_planner.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/external_discovery_ports.dart';
import 'package:skills_workspace/src/application/ports/initial_import_ports.dart';
import 'package:skills_workspace/src/application/ports/source_acquisition_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_coordinator.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/composition/initial_import_command_handlers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../support/activation/activation_fakes.dart';
import '../support/install/initial_import_fakes.dart';
import '../support/operations/operation_fakes.dart';

void main() {
  late _Fixture fixture;

  tearDown(() => fixture.close());

  for (final entry in _sourceFailureCodes.entries) {
    test('Install maps source failure ${entry.key.name}', () async {
      fixture = await _Fixture.create();
      fixture.sources.result = SourceAcquisitionFailure<AcquiredSource>(
        code: entry.key,
        context: const <String, Object?>{'bounded': 'context'},
        warnings: <SourceAcquisitionWarning>[
          SourceAcquisitionWarning(
            code: SourceAcquisitionWarningCode.sourceEntrySkipped,
          ),
        ],
      );

      final result = await fixture.install();

      expect(result.failureOrNull?.code, entry.value);
      expect(result.failureOrNull?.context, const {'bounded': 'context'});
      expect(result.warnings.single.code, SkillsWarningCode.sourceEntrySkipped);
      expect(fixture.operations.log.events, isEmpty);
    });
  }

  for (final entry in _externalFailureCodes.entries) {
    test('Adoption maps discovery failure ${entry.key.name}', () async {
      fixture = await _Fixture.create();
      fixture.locations.result =
          ExternalDiscoveryFailure<List<ScannedExternalSkill>>(
            code: entry.key,
            context: const <String, Object?>{'bounded': 'context'},
            warnings: <ExternalDiscoveryWarning>[
              ExternalDiscoveryWarning(
                code: ExternalDiscoveryWarningCode.sourceEntrySkipped,
              ),
            ],
          );

      final result = await fixture.adopt();

      expect(result.failureOrNull?.code, entry.value);
      expect(result.failureOrNull?.context, const {'bounded': 'context'});
      expect(result.warnings.single.code, SkillsWarningCode.sourceEntrySkipped);
      expect(fixture.operations.log.events, isEmpty);
    });
  }

  test('Install commits affected Skills and preserves warnings', () async {
    fixture = await _Fixture.create();
    fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
      value: _acquired(),
      warnings: <SourceAcquisitionWarning>[
        SourceAcquisitionWarning(
          code: SourceAcquisitionWarningCode.sourceEntrySkipped,
          context: const <String, Object?>{'entry': 'ignored'},
        ),
      ],
    );
    fixture.reader.value = RepositorySnapshot(revision: RepositoryRevision(1));

    final result = await fixture.install(
      request: InstallRequest(
        source: _source,
        selectedSkillNames: const <String>{'example'},
        includeInternal: true,
        fullDepth: true,
        activationSelection: const ActivationSelection.none(),
      ),
    );

    expect(result.valueOrNull?.affectedSkillIds, hasLength(1));
    expect(result.valueOrNull?.snapshot.revision, RepositoryRevision(1));
    expect(result.warnings.single.code, SkillsWarningCode.sourceEntrySkipped);
    expect(fixture.sources.selection, const <String>{'example'});
    expect(fixture.sources.includeInternal, isTrue);
    expect(fixture.sources.fullDepth, isTrue);
    expect(fixture.businessCommits, 1);
  });

  test('Install returns a takeover draft and confirms it atomically', () async {
    fixture = await _Fixture.create();
    fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
      value: _acquired(),
    );
    final targetPath = path.join(_platformLocation('/agent/skills'), 'example');
    fixture.occupancy.results[targetPath] = _installOccupancy(
      targetPath,
      fingerprint: 'reviewed',
    );

    final inspected = await fixture.installAttempt(
      request: InstallRequest(
        source: _source,
        activationSelection: ActivationSelection.explicit([
          ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ]),
      ),
    );

    final required = inspected.valueOrNull as InstallTakeoverRequired;
    expect(required.draft.targets.single.targetPath, targetPath);
    expect(
      required.draft.targets.single.kind,
      ActivationTargetOccupancyKind.brokenSymbolicLink,
    );
    expect(fixture.businessCommits, 0);
    expect(fixture.revisions.calls, 0);

    fixture.reader.value = RepositorySnapshot(revision: RepositoryRevision(1));
    final confirmed = await fixture.confirmInstallTakeover(required.draft);

    expect(confirmed.valueOrNull?.affectedSkillIds, hasLength(1));
    expect(fixture.businessCommits, 1);
  });

  test(
    'changed Install takeover target requires a fresh confirmation',
    () async {
      fixture = await _Fixture.create();
      fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
        value: _acquired(),
      );
      final targetPath = path.join(
        _platformLocation('/agent/skills'),
        'example',
      );
      fixture.occupancy.results[targetPath] = _installOccupancy(
        targetPath,
        fingerprint: 'reviewed',
      );
      final inspected = await fixture.installAttempt(
        request: InstallRequest(
          source: _source,
          activationSelection: ActivationSelection.explicit([
            ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
          ]),
        ),
      );
      fixture.occupancy.results[targetPath] = _installOccupancy(
        targetPath,
        fingerprint: 'changed',
      );

      final confirmed = await fixture.confirmInstallTakeover(
        (inspected.valueOrNull as InstallTakeoverRequired).draft,
      );

      expect(
        confirmed.failureOrNull?.code,
        SkillsErrorCode.staleInstallTakeover,
      );
      expect(fixture.businessCommits, 0);
      expect(fixture.revisions.calls, 0);
    },
  );

  test('Install maps planning failure before creating a Journal', () async {
    fixture = await _Fixture.create(
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        managedSkills: <ManagedSkill>[_managedSkill()],
      ),
    );
    fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
      value: _acquired(),
    );

    final result = await fixture.install();

    expect(
      result.failureOrNull?.code,
      SkillsErrorCode.sourceReplacementRequired,
    );
    expect(fixture.operations.log.events, isEmpty);
  });

  test('pre-cancelled Install stops before acquisition and Journal', () async {
    fixture = await _Fixture.create();
    fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
      value: _acquired(),
    );
    final cancellation = CancellationSource();
    await cancellation.cancel();

    final result = await fixture.install(cancellationToken: cancellation.token);

    expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
    expect(fixture.sources.calls, 0);
    expect(fixture.operations.log.events, isEmpty);
  });

  test(
    'Install maps revision preparation rejection after envelope rollback',
    () async {
      fixture = await _Fixture.create();
      fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
        value: _acquired(),
      );
      fixture.revisions.failure =
          InitialRevisionPreparationFailureCode.ioFailure;

      final result = await fixture.install();

      expect(result.failureOrNull?.code, SkillsErrorCode.operationFailed);
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

  for (final detail in RevisionEngineFailureCode.values) {
    test('Install reports ${detail.name} after preparation rollback', () async {
      fixture = await _Fixture.create();
      fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
        value: _acquired(),
      );
      fixture.revisions.failure =
          InitialRevisionPreparationFailureCode.revisionStoreUnavailable;
      fixture.revisions.failureDetail = detail;
      final result = await fixture.install();
      expect(result.failureOrNull?.code, SkillsErrorCode.operationFailed);
      expect(result.failureOrNull?.context, {
        'revisionCode': 'revisionStoreUnavailable',
        'detail': detail.name,
      });
      expect(
        fixture.operations.log.events,
        contains('control.envelope-rollback-complete'),
      );
    });
  }

  test(
    'Install reports stale Repository revision with actual revision',
    () async {
      fixture = await _Fixture.create(
        coordinatorRevision: RepositoryRevision(1),
      );
      fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
        value: _acquired(),
      );

      final result = await fixture.install();

      expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
      expect(result.failureOrNull?.context['actualRepositoryRevision'], 1);
    },
  );

  test('Install maps apply rollback and rollback-pending failures', () async {
    fixture = await _Fixture.create();
    fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
      value: _acquired(),
    );
    fixture.operations.failures.failures
      ..add('recovery.apply:apply')
      ..add('recovery.rollback');

    final result = await fixture.install();

    expect(result.failureOrNull?.code, SkillsErrorCode.recoveryFailed);
    expect(result.failureOrNull?.context['reason'], 'applyFailed');
  });

  test(
    'Install exposes finalization-pending and still reloads Snapshot',
    () async {
      fixture = await _Fixture.create();
      fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
        value: _acquired(),
      );
      fixture.reader.value = RepositorySnapshot(
        revision: RepositoryRevision(1),
      );
      fixture.operations.failures.failures.add('recovery.finalize:finalize');

      final result = await fixture.install();

      expect(result, isA<SkillsCommittedFinalizationPending<MutationReport>>());
      expect(
        result.warnings.map((warning) => warning.code),
        contains(SkillsWarningCode.finalizationDeferred),
      );
      expect(fixture.reader.reads, 1);
    },
  );

  test(
    'Install preserves pending direction when Snapshot reload also fails',
    () async {
      fixture = await _Fixture.create();
      fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
        value: _acquired(),
      );
      fixture.operations.failures.failures.add('recovery.finalize:finalize');
      fixture.reader.error = StateError('unreadable');

      final result = await fixture.install();

      expect(result, isA<SkillsCommittedFinalizationPending<MutationReport>>());
      expect(
        result.warnings.map((warning) => warning.code),
        contains(SkillsWarningCode.finalizationDeferred),
      );
    },
  );

  test('Install converts completed reload failure to pending', () async {
    fixture = await _Fixture.create();
    fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
      value: _acquired(),
    );
    fixture.reader.error = StateError('unreadable');

    final result = await fixture.install();

    expect(result, isA<SkillsCommittedFinalizationPending<MutationReport>>());
    expect(
      result.warnings.map((warning) => warning.code),
      contains(SkillsWarningCode.finalizationDeferred),
    );
  });

  test('Install reports deferred cleanup without losing success', () async {
    fixture = await _Fixture.create();
    fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
      value: _acquired(),
    );
    fixture.reader.value = RepositorySnapshot(revision: RepositoryRevision(1));
    fixture.operations.failures.failures.add('recovery.cleanup');

    final result = await fixture.install();

    expect(result.valueOrNull, isNotNull);
    expect(
      result.warnings.map((warning) => warning.code),
      contains(SkillsWarningCode.recoveryCleanupDeferred),
    );
  });

  test(
    'Adoption maps an occupied destination to activationUnavailable',
    () async {
      fixture = await _Fixture.create();
      final root = _platformLocation('/agent/skills');
      final existingPath = path.join(root, 'LegacyExample');
      final targetPath = path.join(root, 'example');
      final source = LocalSourceDescriptor(
        locator: root,
        skillPath: 'LegacyExample',
      );
      fixture.locations.result =
          ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
            value: [
              ScannedExternalSkill(
                declaredName: 'example',
                description: 'Example Skill',
                slotKey: 'example',
                contentHash: 'a' * 64,
                skillLocation: existingPath,
                source: source,
              ),
            ],
            warnings: [
              ExternalDiscoveryWarning(
                code: ExternalDiscoveryWarningCode.sourceEntrySkipped,
                context: const {'entry': 'discovery-skipped'},
              ),
            ],
          );
      fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
        value: _acquired(source: source),
        warnings: [
          SourceAcquisitionWarning(
            code: SourceAcquisitionWarningCode.sourceEntrySkipped,
            context: const {'entry': 'source-skipped'},
          ),
        ],
      );
      fixture.occupancy.results[targetPath] = _installOccupancy(
        targetPath,
        fingerprint: 'undiscovered',
      );
      fixture.occupancy.results[existingPath] = InspectedActivationOccupancy(
        managedSkillId: _foreignId,
        slotKey: 'example',
        target: activationTarget(location: root),
        targetPath: existingPath,
        kind: InspectedActivationOccupancyKind.skillDirectory,
        contentRelation:
            InspectedActivationContentRelation.matchesCurrentRevision,
        fingerprint: 'reviewed',
        replaceable: true,
        existingContentHash: 'a' * 64,
      );
      final candidate = ExternalSkillCandidate(
        slotKey: 'example',
        declaredName: 'example',
        description: 'Example Skill',
        contentHash: 'a' * 64,
        locations: [existingPath],
        agentIds: const ['agent'],
      );

      final result = await fixture.adopt(
        request: AdoptRequest(
          selection: ExternalAdoptionSelection.fromCandidate(
            candidate,
            existingPath,
          ),
        ),
      );

      expect(result, isA<SkillsFailure<MutationReport>>());
      expect(result.failureOrNull!.code, SkillsErrorCode.activationUnavailable);
      expect(result.failureOrNull!.context, {
        'reason': 'adoptionTargetOccupied',
        'occupant': 'link',
        'occupants': [
          {'targetPath': targetPath, 'occupant': 'link'},
        ],
        'slotKey': 'example',
        'targetPaths': [targetPath],
      });
      expect(result.warnings.map((warning) => warning.code), [
        SkillsWarningCode.sourceEntrySkipped,
        SkillsWarningCode.sourceEntrySkipped,
      ]);
      expect(result.warnings.map((warning) => warning.context['entry']), [
        'discovery-skipped',
        'source-skipped',
      ]);
      expect(fixture.operations.log.events, isEmpty);
      expect(fixture.revisions.calls, 0);
      expect(fixture.businessCommits, 0);
    },
  );

  test(
    'Adoption scans, reacquires and commits the authoritative occurrence',
    () async {
      fixture = await _Fixture.create();
      fixture.locations.result =
          ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
            value: <ScannedExternalSkill>[_scanned()],
            warnings: <ExternalDiscoveryWarning>[
              ExternalDiscoveryWarning(
                code: ExternalDiscoveryWarningCode.sourceEntrySkipped,
              ),
            ],
          );
      fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
        value: _acquired(source: _occurrenceSource),
      );
      final targetPath = path.join(
        _platformLocation('/agent/skills'),
        'example',
      );
      fixture.occupancy.results[targetPath] = InspectedActivationOccupancy(
        managedSkillId: _foreignId,
        slotKey: 'example',
        target: activationTarget(location: _platformLocation('/agent/skills')),
        targetPath: targetPath,
        kind: InspectedActivationOccupancyKind.skillDirectory,
        contentRelation:
            InspectedActivationContentRelation.matchesCurrentRevision,
        fingerprint: 'fingerprint',
        replaceable: true,
        existingContentHash: 'a' * 64,
      );
      fixture.reader.value = RepositorySnapshot(
        revision: RepositoryRevision(1),
      );

      final result = await fixture.adopt();

      expect(result.valueOrNull?.affectedSkillIds, hasLength(1));
      expect(result.warnings.single.code, SkillsWarningCode.sourceEntrySkipped);
      expect(fixture.sources.calls, 1);
      expect(fixture.locations.selectedSlotKeyRequests, <Set<String>?>[
        const <String>{'example'},
      ]);
    },
  );

  test(
    'Adoption maps a changed reviewed occurrence to stale Snapshot',
    () async {
      fixture = await _Fixture.create();
      fixture.locations.result =
          ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
            value: <ScannedExternalSkill>[
              ScannedExternalSkill(
                declaredName: 'example',
                description: 'Example Skill',
                slotKey: 'example',
                contentHash: 'b' * 64,
                skillLocation: path.join(
                  _platformLocation('/agent/skills'),
                  'example',
                ),
                source: _occurrenceSource,
              ),
            ],
          );
      fixture.reader.value = RepositorySnapshot(
        revision: RepositoryRevision(1),
      );

      final result = await fixture.adopt();

      expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
      expect(
        result.failureOrNull?.context['reason'],
        'reviewedLocationsChanged',
      );
      expect(fixture.sources.calls, 0);
    },
  );
}

final class _Fixture {
  _Fixture._({
    required this.reader,
    required this.snapshots,
    required this.sources,
    required this.locations,
    required this.occupancy,
    required this.revisions,
    required this.operations,
    required this.dispatcher,
  });

  static Future<_Fixture> create({
    RepositorySnapshot? snapshot,
    RepositoryRevision? coordinatorRevision,
  }) async {
    final initial = snapshot ?? RepositorySnapshot.empty();
    final reader = _Reader(initial);
    final snapshots = WorkspaceSnapshotPublisher(reader: reader);
    await snapshots.publishInitial(initial);
    final sources = _Sources();
    final locations = _Locations();
    final occupancy = RecordingActivationOccupancyProbe();
    final revisions = RecordingInitialRevisionCandidates();
    final operations = OperationHarness(
      repositoryRevision: coordinatorRevision ?? initial.revision,
    );
    const identity = PosixActivationLocationIdentity();
    final catalog = AgentCatalog.create(
      platform: DesktopPlatform.macos,
      detectionPort: FakeAgentDetectionPort(),
      builtIns: <AgentDefinition>[
        AgentDefinition(
          id: 'agent',
          displayName: 'Agent',
          platforms: <DesktopPlatform, AgentPlatformDefinition>{
            DesktopPlatform.macos: AgentPlatformDefinition(
              globalSkillsPath: '/agent/skills',
            ),
          },
        ),
      ],
    ).valueOrNull!;
    final resolver = ActivationTargetResolver(
      catalog: catalog,
      symbolicLinkCapability: FakeSymbolicLinkCapability(),
      locationIdentity: identity,
    );
    final planner = InitialImportPlanner(
      sourceAcquisition: SourceAcquisitionCoordinator(
        local: sources,
        git: sources,
        wellKnown: sources,
      ),
      activationTargetResolver: resolver,
      occupancyProbe: occupancy,
      locationIdentity: identity,
      identities: SequenceWorkspaceEntityIdentities(),
      sourcePayloads: FakeSourcePayloadEncoding(),
      revisionCandidates: revisions,
      clock: () => _now,
    );
    final scanner = ExternalSkillScanner(
      catalog: catalog,
      activationTargetResolver: resolver,
      locationIdentity: identity,
      locationPort: locations,
    );
    return _Fixture._(
      reader: reader,
      snapshots: snapshots,
      sources: sources,
      locations: locations,
      occupancy: occupancy,
      revisions: revisions,
      operations: operations,
      dispatcher: CompositeSkillsRepositoryCommandDispatcher(
        buildInitialImportCommandHandlers(
          snapshots: snapshots,
          operations: operations.createCoordinator(),
          sources: SourceAcquisitionCoordinator(
            local: sources,
            git: sources,
            wellKnown: sources,
          ),
          externalSkills: () => scanner,
          initialImports: planner,
          plans: const _Plans(),
        ),
      ),
    );
  }

  final _Reader reader;
  final WorkspaceSnapshotPublisher snapshots;
  final _Sources sources;
  final _Locations locations;
  final RecordingActivationOccupancyProbe occupancy;
  final RecordingInitialRevisionCandidates revisions;
  final OperationHarness operations;
  final CompositeSkillsRepositoryCommandDispatcher dispatcher;
  var businessCommits = 0;

  Future<SkillsResult<MutationReport>> install({
    InstallRequest? request,
    CancellationToken? cancellationToken,
  }) async {
    final result = await installAttempt(
      request: request,
      cancellationToken: cancellationToken,
    );
    return result.fold<SkillsResult<MutationReport>>(
      onSuccess: (success) {
        final attempt = success.value;
        if (attempt is! InstallCompleted) {
          return SkillsFailure<MutationReport>(
            code: SkillsErrorCode.externalConflict,
          );
        }
        return SkillsSuccess<MutationReport>(
          value: attempt.report,
          changed: success.changed,
          warnings: success.warnings,
        );
      },
      onFailure: (failure) => SkillsFailure<MutationReport>(
        code: failure.code,
        context: failure.context,
        warnings: failure.warnings,
      ),
      onCommittedFinalizationPending: (pending) =>
          SkillsCommittedFinalizationPending<MutationReport>(
            operationId: pending.operationId,
            committedRepositoryRevision: pending.committedRepositoryRevision,
            warnings: pending.warnings,
          ),
    );
  }

  Future<SkillsResult<InstallAttempt>> installAttempt({
    InstallRequest? request,
    CancellationToken? cancellationToken,
  }) => dispatcher.execute<InstallAttempt>(
    operationId: _operationId,
    kind: WorkspaceOperationKind.install,
    request: request ?? InstallRequest(source: _source),
    cancellationToken: cancellationToken ?? CancellationToken.none(),
    markBusinessCommitted: () => businessCommits += 1,
    reportProgress: (phase, {currentItem, completed = 0, total}) {},
  );

  Future<SkillsResult<MutationReport>> confirmInstallTakeover(
    InstallTakeoverDraft draft,
  ) => _execute(
    WorkspaceOperationKind.confirmInstallTakeover,
    ConfirmInstallTakeoverRequest(draft: draft),
  );

  Future<SkillsResult<MutationReport>> adopt({AdoptRequest? request}) =>
      _execute(
        WorkspaceOperationKind.adopt,
        request ??
            AdoptRequest(
              selection: ExternalAdoptionSelection.fromCandidate(
                _candidate,
                path.join(_platformLocation('/agent/skills'), 'example'),
              ),
            ),
      );

  Future<SkillsResult<MutationReport>> _execute(
    WorkspaceOperationKind kind,
    Object request, {
    CancellationToken? cancellationToken,
  }) => dispatcher.execute<MutationReport>(
    operationId: _operationId,
    kind: kind,
    request: request,
    cancellationToken: cancellationToken ?? CancellationToken.none(),
    markBusinessCommitted: () => businessCommits += 1,
    reportProgress: (phase, {currentItem, completed = 0, total}) {},
  );

  Future<void> close() => snapshots.close();
}

final class _Plans implements InitialImportOperationPlanPort {
  const _Plans();

  @override
  PreparedOperationEnvelope createEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required InitialImportPreflight preflight,
  }) => PreparedOperationEnvelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    committedRepositoryRevision: expectedRepositoryRevision.next(),
    operationGeneration: expectedRepositoryRevision.next().value,
    preparationSteps: <PreparationOperationStep>[
      for (final subject in preflight.subjects) ...<PreparationOperationStep>[
        PreparationOperationStep(
          stepId: 'candidate-${subject.managedSkillId.value}',
          recoveryReference: RecoveryReference(
            'candidate-${subject.managedSkillId.value}',
          ),
          kind: PreparationStepKind.revisionCandidate,
        ),
        PreparationOperationStep(
          stepId: 'bundle-${subject.managedSkillId.value}',
          recoveryReference: RecoveryReference(
            'bundle-${subject.managedSkillId.value}',
          ),
          kind: PreparationStepKind.revisionBundle,
        ),
      ],
    ],
    record: OperationRecordPlan(
      operationId: operationId,
      kind: preflight.kind.name,
      subjects: const <OperationSubjectPlan>[],
      retainWithoutSubjects: true,
    ),
  );

  @override
  OperationPlan sealPlan({
    required PreparedOperationEnvelope envelope,
    required InitialImportPreflight preflight,
    required InitialImportPlan initialImportPlan,
  }) => OperationPlan(
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
    revisionSelectionChanges: initialImportPlan.revisionSelectionChanges,
    businessChanges: initialImportPlan.businessChanges,
    record: envelope.record,
  );
}

final class _Sources
    implements
        LocalSourceAcquisitionPort,
        GitSourceAcquisitionPort,
        WellKnownSourceAcquisitionPort {
  SourceAcquisitionResult<AcquiredSource> result =
      SourceAcquisitionFailure<AcquiredSource>(
        code: SourceAcquisitionFailureCode.sourceUnavailable,
      );
  var calls = 0;
  Set<String>? selection;
  bool? includeInternal;
  bool? fullDepth;

  Future<SourceAcquisitionResult<AcquiredSource>> _read(
    Set<String> selectedSkillNames,
    SourceAcquisitionOptions options,
  ) async {
    calls += 1;
    selection = selectedSkillNames;
    includeInternal = options.includeInternal;
    fullDepth = options.fullDepth;
    return result;
  }

  @override
  Future<SourceAcquisitionResult<AcquiredSource>> acquireLocal(
    LocalSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) => _read(selectedSkillNames, options);

  @override
  Future<SourceAcquisitionResult<AcquiredSource>> acquireGit(
    GitSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) => _read(selectedSkillNames, options);

  @override
  Future<List<SourceAcquisitionResult<AcquiredSource>>> acquireGitBatch(
    List<SourceAcquisitionRequest> requests, {
    required CancellationToken cancellationToken,
    void Function(int index, SourceAcquisitionResult<AcquiredSource> result)?
    onResult,
  }) async {
    final results = <SourceAcquisitionResult<AcquiredSource>>[];
    for (var index = 0; index < requests.length; index += 1) {
      final request = requests[index];
      final result = await _read(request.selectedSkillNames, request.options);
      results.add(result);
      onResult?.call(index, result);
    }
    return results;
  }

  @override
  Future<SourceAcquisitionResult<AcquiredSource>> acquireWellKnown(
    WellKnownSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) => _read(selectedSkillNames, options);
}

final class _Locations implements ExternalSkillLocationPort {
  ExternalDiscoveryResult<List<ScannedExternalSkill>> result =
      ExternalDiscoverySuccess<List<ScannedExternalSkill>>(value: const []);
  final List<Set<String>?> selectedSlotKeyRequests = <Set<String>?>[];

  @override
  Future<ExternalDiscoveryResult<List<ScannedExternalSkill>>> scanLocation({
    required String location,
    Set<String>? selectedSlotKeys,
    required bool includeInternal,
    required CancellationToken cancellationToken,
  }) async {
    selectedSlotKeyRequests.add(
      selectedSlotKeys == null ? null : Set.unmodifiable(selectedSlotKeys),
    );
    return result;
  }
}

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

AcquiredSource _acquired({LocalSourceDescriptor? source}) {
  final resolved = source ?? _source;
  return AcquiredSource(
    canonicalSource: resolved,
    skills: <AcquiredSourceSkill>[_skill(resolved)],
  );
}

AcquiredSourceSkill _skill(SourceDescriptor source) => AcquiredSourceSkill(
  provenance: source,
  declaredName: 'example',
  description: 'Example Skill',
  slotKey: 'example',
  skillPath: 'example',
  frontmatter: const <String, Object?>{
    'name': 'example',
    'description': 'Example Skill',
  },
  tree: NormalizedSkillTree(
    files: <NormalizedSkillFile>[
      NormalizedSkillFile(
        relativePath: 'SKILL.md',
        bytes: const <int>[1],
        isExecutable: false,
      ),
    ],
    contentHash: 'a' * 64,
    byteSize: 1,
  ),
);

ManagedSkill _managedSkill() => ManagedSkill(
  id: _foreignId,
  slotKey: 'example',
  declaredName: 'example',
  displayName: 'Example',
  description: 'Example Skill',
  source: LocalSourceDescriptor(locator: '/different'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: 'b' * 64,
    fileCount: 1,
    byteSize: 1,
    publishedAt: _now,
  ),
);

ScannedExternalSkill _scanned() => ScannedExternalSkill(
  declaredName: 'example',
  description: 'Example Skill',
  slotKey: 'example',
  contentHash: 'a' * 64,
  skillLocation: path.join(_platformLocation('/agent/skills'), 'example'),
  source: _occurrenceSource,
);

InspectedActivationOccupancy _installOccupancy(
  String targetPath, {
  required String fingerprint,
}) => InspectedActivationOccupancy(
  managedSkillId: _foreignId,
  slotKey: 'example',
  target: activationTarget(location: _platformLocation('/agent/skills')),
  targetPath: targetPath,
  kind: InspectedActivationOccupancyKind.brokenSymbolicLink,
  contentRelation: InspectedActivationContentRelation.indeterminate,
  fingerprint: fingerprint,
  replaceable: true,
  linkTarget: '/legacy/repository/example',
);

final _candidate = ExternalSkillCandidate(
  slotKey: 'example',
  declaredName: 'example',
  description: 'Example Skill',
  contentHash: 'a' * 64,
  locations: <String>[path.join(_platformLocation('/agent/skills'), 'example')],
  agentIds: const <String>['agent'],
);

final _source = LocalSourceDescriptor(locator: '/source');
final _occurrenceSource = LocalSourceDescriptor(
  locator: _platformLocation('/agent/skills'),
  skillPath: 'example',
);
final _operationId = OperationId('123e4567-e89b-42d3-8456-426614174001');
final _foreignId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174999');
final _now = DateTime.utc(2026, 8, 17);

const _sourceFailureCodes = <SourceAcquisitionFailureCode, SkillsErrorCode>{
  SourceAcquisitionFailureCode.sourceUnavailable:
      SkillsErrorCode.sourceUnavailable,
  SourceAcquisitionFailureCode.sourceAuthenticationRequired:
      SkillsErrorCode.sourceAuthenticationRequired,
  SourceAcquisitionFailureCode.gitUnavailable: SkillsErrorCode.gitUnavailable,
  SourceAcquisitionFailureCode.gitFailed: SkillsErrorCode.gitFailed,
  SourceAcquisitionFailureCode.developerToolsRequired:
      SkillsErrorCode.developerToolsRequired,
  SourceAcquisitionFailureCode.transportRejected:
      SkillsErrorCode.transportRejected,
  SourceAcquisitionFailureCode.httpFailure: SkillsErrorCode.httpFailure,
  SourceAcquisitionFailureCode.digestMismatch: SkillsErrorCode.digestMismatch,
  SourceAcquisitionFailureCode.archiveInvalid: SkillsErrorCode.archiveInvalid,
  SourceAcquisitionFailureCode.skillNotFound: SkillsErrorCode.skillNotFound,
  SourceAcquisitionFailureCode.invalidSkill: SkillsErrorCode.invalidSkill,
  SourceAcquisitionFailureCode.unsupportedSkillName:
      SkillsErrorCode.unsupportedSkillName,
  SourceAcquisitionFailureCode.skillContentLimitExceeded:
      SkillsErrorCode.skillContentLimitExceeded,
  SourceAcquisitionFailureCode.duplicateSkillSlot:
      SkillsErrorCode.duplicateSkillSlot,
  SourceAcquisitionFailureCode.updateUnsupported:
      SkillsErrorCode.updateUnsupported,
  SourceAcquisitionFailureCode.operationCancelled:
      SkillsErrorCode.operationCancelled,
  SourceAcquisitionFailureCode.ioFailure: SkillsErrorCode.ioFailure,
};

String _platformLocation(String value) => path.normalize(path.absolute(value));

const _externalFailureCodes = <ExternalDiscoveryFailureCode, SkillsErrorCode>{
  ExternalDiscoveryFailureCode.agentNotFound: SkillsErrorCode.agentNotFound,
  ExternalDiscoveryFailureCode.activationUnsupported:
      SkillsErrorCode.activationUnsupported,
  ExternalDiscoveryFailureCode.projectRootNotFound:
      SkillsErrorCode.projectRootNotFound,
  ExternalDiscoveryFailureCode.sourceUnavailable:
      SkillsErrorCode.sourceUnavailable,
  ExternalDiscoveryFailureCode.invalidSkill: SkillsErrorCode.invalidSkill,
  ExternalDiscoveryFailureCode.contentLimitExceeded:
      SkillsErrorCode.skillContentLimitExceeded,
  ExternalDiscoveryFailureCode.operationCancelled:
      SkillsErrorCode.operationCancelled,
  ExternalDiscoveryFailureCode.ioFailure: SkillsErrorCode.ioFailure,
};
