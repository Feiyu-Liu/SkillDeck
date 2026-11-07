import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/default_skills_repository.dart';
import 'package:skills_workspace/src/api/finalization_recovery_command.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/activation/activation_target_resolver.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog.dart';
import 'package:skills_workspace/src/application/discovery/external_discovery_models.dart';
import 'package:skills_workspace/src/application/discovery/external_skill_scanner.dart';
import 'package:skills_workspace/src/application/ports/agent_activation_ports.dart';
import 'package:skills_workspace/src/application/ports/external_discovery_ports.dart';
import 'package:skills_workspace/src/application/ports/history_ports.dart';
import 'package:skills_workspace/src/application/ports/source_acquisition_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/operations/finalization_recovery_service.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_coordinator.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/composition/read_command_handlers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

void main() {
  late _Fixture fixture;

  tearDown(() => fixture.close());

  test(
    'refresh publishes the authoritative Snapshot and reports progress',
    () async {
      fixture = await _Fixture.create(RepositorySnapshot.empty());
      fixture.reader.value = _snapshot(revision: 1);

      final result = await fixture.execute<RepositorySnapshot>(
        WorkspaceOperationKind.refresh,
        const RefreshWorkspaceCommand(),
      );

      expect(result.valueOrNull?.revision, RepositoryRevision(1));
      expect((result as SkillsSuccess<RepositorySnapshot>).changed, isFalse);
      expect(fixture.progress, <OperationProgressPhase>[
        OperationProgressPhase.inspecting,
      ]);
    },
  );

  test('refresh maps an unreadable Snapshot to stateCorrupt', () async {
    fixture = await _Fixture.create(RepositorySnapshot.empty());
    fixture.reader.error = StateError('unreadable');

    final result = await fixture.execute<RepositorySnapshot>(
      WorkspaceOperationKind.refresh,
      const RefreshWorkspaceCommand(),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.stateCorrupt);
  });

  test('finalization recovery is idempotent when no Journal remains', () async {
    fixture = await _Fixture.create(RepositorySnapshot.empty());

    final result = await fixture.execute<RepositorySnapshot>(
      WorkspaceOperationKind.resumeFinalizationRecovery,
      const ResumeFinalizationRecoveryCommand(),
    );

    expect(result.valueOrNull, same(fixture.snapshots.current));
    expect((result as SkillsSuccess<RepositorySnapshot>).changed, isFalse);
    expect(fixture.finalizationRecovery.calls, 1);
    expect(fixture.progress, <OperationProgressPhase>[
      OperationProgressPhase.finalizing,
    ]);
  });

  test(
    'finalization recovery reloads and publishes the recovered Snapshot',
    () async {
      fixture = await _Fixture.create(RepositorySnapshot.empty());
      fixture.reader.value = _snapshot(revision: 1);
      fixture.finalizationRecovery.report =
          OperationRecoveryReport(<RecoveredOperation>[
            RecoveredOperation(
              operationId: _operationId,
              observedPhase: OperationJournalPhase.committed,
              disposition: RecoveredOperationDisposition.rolledForward,
            ),
          ]);
      final published = <RepositorySnapshot>[];
      final subscription = fixture.snapshots.snapshots.listen(published.add);
      addTearDown(subscription.cancel);

      final result = await fixture.execute<RepositorySnapshot>(
        WorkspaceOperationKind.resumeFinalizationRecovery,
        const ResumeFinalizationRecoveryCommand(),
      );

      expect(result.valueOrNull?.revision, RepositoryRevision(1));
      expect((result as SkillsSuccess<RepositorySnapshot>).changed, isTrue);
      expect(fixture.snapshots.current.revision, RepositoryRevision(1));
      expect(published, <RepositorySnapshot>[_snapshot(revision: 1)]);
    },
  );

  test(
    'finalization recovery maps retry-required Journal work to a typed failure',
    () async {
      fixture = await _Fixture.create(RepositorySnapshot.empty());
      fixture.finalizationRecovery.report =
          OperationRecoveryReport(<RecoveredOperation>[
            RecoveredOperation(
              operationId: _operationId,
              observedPhase: OperationJournalPhase.finalizing,
              disposition: RecoveredOperationDisposition.retryRequired,
            ),
          ]);

      final result = await fixture.execute<RepositorySnapshot>(
        WorkspaceOperationKind.resumeFinalizationRecovery,
        const ResumeFinalizationRecoveryCommand(),
      );

      expect(
        result.failureOrNull?.code,
        SkillsErrorCode.finalizationRecoveryFailed,
      );
    },
  );

  test(
    'finalization recovery maps an execution error to a typed failure',
    () async {
      fixture = await _Fixture.create(RepositorySnapshot.empty());
      fixture.finalizationRecovery.error = StateError('recovery failed');

      final result = await fixture.execute<RepositorySnapshot>(
        WorkspaceOperationKind.resumeFinalizationRecovery,
        const ResumeFinalizationRecoveryCommand(),
      );

      expect(
        result.failureOrNull?.code,
        SkillsErrorCode.finalizationRecoveryFailed,
      );
    },
  );

  test('source inspection forwards options and maps warnings', () async {
    fixture = await _Fixture.create(RepositorySnapshot.empty());
    fixture.sources.result = SourceAcquisitionSuccess<AcquiredSource>(
      value: _acquiredSource(),
      warnings: <SourceAcquisitionWarning>[
        SourceAcquisitionWarning(
          code: SourceAcquisitionWarningCode.sourceEntrySkipped,
          context: const <String, Object?>{'entry': 'nested'},
        ),
      ],
    );

    final result = await fixture.execute<SourceInspection>(
      WorkspaceOperationKind.inspectSource,
      InspectSourceRequest(
        source: _source,
        includeInternal: true,
        fullDepth: true,
      ),
    );

    expect(result.valueOrNull?.candidates.single.slotKey, 'example');
    expect(result.warnings.single.code, SkillsWarningCode.sourceEntrySkipped);
    expect(result.warnings.single.context, const {'entry': 'nested'});
    expect(fixture.sources.includeInternal, isTrue);
    expect(fixture.sources.fullDepth, isTrue);
  });

  for (final entry in _sourceFailureCodes.entries) {
    test('source inspection maps ${entry.key.name}', () async {
      fixture = await _Fixture.create(RepositorySnapshot.empty());
      fixture.sources.result = SourceAcquisitionFailure<AcquiredSource>(
        code: entry.key,
        context: const <String, Object?>{'bounded': 'context'},
        warnings: <SourceAcquisitionWarning>[
          SourceAcquisitionWarning(
            code: SourceAcquisitionWarningCode.sourceEntrySkipped,
          ),
        ],
      );

      final result = await fixture.execute<SourceInspection>(
        WorkspaceOperationKind.inspectSource,
        InspectSourceRequest(source: _source),
      );

      expect(result.failureOrNull?.code, entry.value);
      expect(result.failureOrNull?.context, const {'bounded': 'context'});
      expect(result.warnings.single.code, SkillsWarningCode.sourceEntrySkipped);
    });
  }

  test(
    'selected-location discovery returns candidates and all warnings',
    () async {
      fixture = await _Fixture.create(RepositorySnapshot.empty());
      fixture.locations.result =
          ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
            value: <ScannedExternalSkill>[_scannedSkill()],
            warnings: <ExternalDiscoveryWarning>[
              for (final code in ExternalDiscoveryWarningCode.values)
                ExternalDiscoveryWarning(
                  code: code,
                  context: <String, Object?>{'code': code.name},
                ),
            ],
          );

      final result = await fixture.execute<ExternalSkillsDiscovery>(
        WorkspaceOperationKind.discoverExternalSkills,
        DiscoverExternalSkillsRequest(
          selection: ActivationSelection.explicit(<ActivationTarget>[
            ActivationTarget(agentId: _agentId, scope: ActivationScope.global),
          ]),
          includeInternal: true,
        ),
      );

      expect(result.valueOrNull?.candidates.single.slotKey, 'example');
      expect(
        result.warnings.map((warning) => warning.code),
        <SkillsWarningCode>[
          SkillsWarningCode.noActivationTarget,
          SkillsWarningCode.projectSymbolicLinkPortability,
          SkillsWarningCode.duplicateExposure,
          SkillsWarningCode.activationTargetSkipped,
          SkillsWarningCode.sourceEntrySkipped,
          SkillsWarningCode.sharedActivationLocation,
        ],
      );
      expect(fixture.locations.includeInternal, isTrue);
    },
  );

  test(
    'all-known-location discovery resolves and scans catalog targets',
    () async {
      fixture = await _Fixture.create(RepositorySnapshot.empty());
      fixture.locations.result =
          ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
            value: <ScannedExternalSkill>[_scannedSkill()],
          );

      final result = await fixture.execute<ExternalSkillsDiscovery>(
        WorkspaceOperationKind.discoverExternalSkills,
        const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
      );

      expect(result.valueOrNull?.candidates.single.slotKey, 'example');
      expect(fixture.locations.locations, <String>[
        _platformLocation('/agents/skills'),
      ]);
    },
  );

  for (final entry in _externalFailureCodes.entries) {
    test('external discovery maps ${entry.key.name}', () async {
      fixture = await _Fixture.create(RepositorySnapshot.empty());
      fixture.locations.result =
          ExternalDiscoveryFailure<List<ScannedExternalSkill>>(
            code: entry.key,
            context: const <String, Object?>{'location': '/agents/skills'},
            warnings: <ExternalDiscoveryWarning>[
              ExternalDiscoveryWarning(
                code: ExternalDiscoveryWarningCode.sourceEntrySkipped,
              ),
            ],
          );

      final result = await fixture.execute<ExternalSkillsDiscovery>(
        WorkspaceOperationKind.discoverExternalSkills,
        DiscoverExternalSkillsRequest(
          selection: ActivationSelection.explicit(<ActivationTarget>[
            ActivationTarget(agentId: _agentId, scope: ActivationScope.global),
          ]),
        ),
      );

      expect(result.failureOrNull?.code, entry.value);
      expect(result.failureOrNull?.context, const {
        'location': '/agents/skills',
      });
      expect(result.warnings.single.code, SkillsWarningCode.sourceEntrySkipped);
    });
  }

  test('all-known-location resolution failure stops before scanning', () async {
    fixture = await _Fixture.create(
      RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        projectRoots: <ProjectRoot>[ProjectRoot(id: 'root', path: '/agents')],
      ),
      conflictingCatalogLocations: true,
    );

    final result = await fixture.execute<ExternalSkillsDiscovery>(
      WorkspaceOperationKind.discoverExternalSkills,
      const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.activationUnsupported);
    expect(fixture.locations.locations, isEmpty);
  });

  test('Update Candidate inspection returns current projection', () async {
    final candidate = UpdateCandidateSummary(
      status: UpdateCandidateStatus.validationFailed,
      conflicts: const <UpdateConflict>[],
      validationCode: 'invalid',
      createdAt: _now,
    );
    fixture = await _Fixture.create(_snapshot(candidate: candidate));

    final result = await fixture.execute<UpdateCandidateSummary?>(
      WorkspaceOperationKind.inspectUpdateCandidate,
      InspectUpdateCandidateRequest(managedSkillId: _skillId),
    );

    expect(result.valueOrNull, same(candidate));
  });

  test('missing Update Candidate subject fails', () async {
    fixture = await _Fixture.create(RepositorySnapshot.empty());

    final result = await fixture.execute<UpdateCandidateSummary?>(
      WorkspaceOperationKind.inspectUpdateCandidate,
      InspectUpdateCandidateRequest(managedSkillId: _skillId),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.skillNotFound);
  });

  test('global Operation History forwards cursor and limit', () async {
    fixture = await _Fixture.create(RepositorySnapshot.empty());
    fixture.history.operationPage = OperationHistoryPage(
      entries: const <OperationHistoryEntry>[],
      nextCursor: 'next',
    );

    final result = await fixture.execute<OperationHistoryPage>(
      WorkspaceOperationKind.inspectOperationHistory,
      const OperationHistoryRequest(cursor: 'cursor', limit: 7),
    );

    expect(result.valueOrNull?.nextCursor, 'next');
    expect(fixture.history.operationCursor, 'cursor');
    expect(fixture.history.operationLimit, 7);
  });

  test(
    'Skill Operation History rejects a missing subject before I/O',
    () async {
      fixture = await _Fixture.create(RepositorySnapshot.empty());

      final result = await fixture.execute<OperationHistoryPage>(
        WorkspaceOperationKind.inspectOperationHistory,
        OperationHistoryRequest(managedSkillId: _skillId),
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.skillNotFound);
      expect(fixture.history.operationReads, 0);
    },
  );

  test('invalid Operation History cursor maps to invalidSkill', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.history.operationError = ArgumentError('cursor');

    final result = await fixture.execute<OperationHistoryPage>(
      WorkspaceOperationKind.inspectOperationHistory,
      OperationHistoryRequest(managedSkillId: _skillId, cursor: 'bad'),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.invalidSkill);
    expect(result.failureOrNull?.context, const {'reason': 'invalidCursor'});
  });

  test('Published History forwards subject, cursor and limit', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.history.publishedPage = PublishedHistoryPage(
      revisions: const <PublishedRevisionSummary>[],
      nextCursor: 'next',
    );

    final result = await fixture.execute<PublishedHistoryPage>(
      WorkspaceOperationKind.inspectPublishedHistory,
      PublishedHistoryRequest(
        managedSkillId: _skillId,
        cursor: 'cursor',
        limit: 9,
      ),
    );

    expect(result.valueOrNull?.nextCursor, 'next');
    expect(fixture.history.publishedSkillId, _skillId);
    expect(fixture.history.publishedCursor, 'cursor');
    expect(fixture.history.publishedLimit, 9);
  });

  test('missing Published History subject fails before I/O', () async {
    fixture = await _Fixture.create(RepositorySnapshot.empty());

    final result = await fixture.execute<PublishedHistoryPage>(
      WorkspaceOperationKind.inspectPublishedHistory,
      PublishedHistoryRequest(managedSkillId: _skillId),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.skillNotFound);
    expect(fixture.history.publishedReads, 0);
  });

  test('invalid Published History cursor maps to invalidSkill', () async {
    fixture = await _Fixture.create(_snapshot());
    fixture.history.publishedError = ArgumentError('cursor');

    final result = await fixture.execute<PublishedHistoryPage>(
      WorkspaceOperationKind.inspectPublishedHistory,
      PublishedHistoryRequest(managedSkillId: _skillId, cursor: 'bad'),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.invalidSkill);
    expect(result.failureOrNull?.context, const {'reason': 'invalidCursor'});
  });
}

final class _Fixture {
  _Fixture._({
    required this.reader,
    required this.snapshots,
    required this.finalizationRecovery,
    required this.sources,
    required this.locations,
    required this.history,
    required this.dispatcher,
  });

  static Future<_Fixture> create(
    RepositorySnapshot snapshot, {
    bool conflictingCatalogLocations = false,
  }) async {
    final reader = _SnapshotReader(snapshot);
    final snapshots = WorkspaceSnapshotPublisher(reader: reader);
    await snapshots.publishInitial(snapshot);
    final sources = _Sources();
    final finalizationRecovery = _FinalizationRecovery();
    final locations = _Locations();
    final history = _History();
    const identity = _LocationIdentity(sameObjectPairs: <(String, String)>{});
    final catalog = AgentCatalog.create(
      platform: DesktopPlatform.macos,
      detectionPort: const _Detection(),
      builtIns: <AgentDefinition>[
        AgentDefinition(
          id: _agentId,
          displayName: 'Agent',
          platforms: <DesktopPlatform, AgentPlatformDefinition>{
            DesktopPlatform.macos: AgentPlatformDefinition(
              globalSkillsPath: '/agents/skills',
              projectSkillsPath: conflictingCatalogLocations ? 'skills' : null,
            ),
          },
        ),
      ],
    ).valueOrNull!;
    final scanner = ExternalSkillScanner(
      catalog: catalog,
      activationTargetResolver: ActivationTargetResolver(
        catalog: catalog,
        symbolicLinkCapability: const _Links(),
        locationIdentity: identity,
      ),
      locationIdentity: identity,
      locationPort: locations,
    );
    return _Fixture._(
      reader: reader,
      snapshots: snapshots,
      finalizationRecovery: finalizationRecovery,
      sources: sources,
      locations: locations,
      history: history,
      dispatcher: CompositeSkillsRepositoryCommandDispatcher(
        buildReadCommandHandlers(
          snapshots: snapshots,
          finalizationRecovery: finalizationRecovery,
          sources: SourceAcquisitionCoordinator(
            local: sources,
            git: sources,
            wellKnown: sources,
          ),
          externalSkills: () => scanner,
          history: history,
        ),
      ),
    );
  }

  final _SnapshotReader reader;
  final WorkspaceSnapshotPublisher snapshots;
  final _FinalizationRecovery finalizationRecovery;
  final _Sources sources;
  final _Locations locations;
  final _History history;
  final CompositeSkillsRepositoryCommandDispatcher dispatcher;
  final List<OperationProgressPhase> progress = <OperationProgressPhase>[];

  Future<SkillsResult<T>> execute<T>(
    WorkspaceOperationKind kind,
    Object request,
  ) => dispatcher.execute<T>(
    operationId: _operationId,
    kind: kind,
    request: request,
    cancellationToken: CancellationToken.none(),
    markBusinessCommitted: () {},
    reportProgress: (phase, {currentItem, completed = 0, total}) {
      progress.add(phase);
    },
  );

  Future<void> close() => snapshots.close();
}

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  _SnapshotReader(this.value);

  RepositorySnapshot value;
  Object? error;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async {
    if (error case final failure?) throw failure;
    return value;
  }
}

final class _FinalizationRecovery implements WorkspaceFinalizationRecoveryPort {
  var calls = 0;
  OperationRecoveryReport report = OperationRecoveryReport(
    const <RecoveredOperation>[],
  );
  Object? error;

  @override
  Future<OperationRecoveryReport> resumeFinalizationRecovery() async {
    calls += 1;
    if (error case final failure?) throw failure;
    return report;
  }
}

final class _Sources
    implements
        LocalSourceAcquisitionPort,
        GitSourceAcquisitionPort,
        WellKnownSourceAcquisitionPort {
  SourceAcquisitionResult<AcquiredSource> result =
      SourceAcquisitionSuccess<AcquiredSource>(value: _acquiredSource());
  bool? includeInternal;
  bool? fullDepth;

  Future<SourceAcquisitionResult<AcquiredSource>> _read(
    SourceAcquisitionOptions options,
  ) async {
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
  }) => _read(options);

  @override
  Future<SourceAcquisitionResult<AcquiredSource>> acquireGit(
    GitSourceDescriptor source, {
    required Set<String> selectedSkillNames,
    required SourceAcquisitionOptions options,
    required CancellationToken cancellationToken,
  }) => _read(options);

  @override
  Future<List<SourceAcquisitionResult<AcquiredSource>>> acquireGitBatch(
    List<SourceAcquisitionRequest> requests, {
    required CancellationToken cancellationToken,
    void Function(int index, SourceAcquisitionResult<AcquiredSource> result)?
    onResult,
  }) async {
    final results = <SourceAcquisitionResult<AcquiredSource>>[];
    for (var index = 0; index < requests.length; index += 1) {
      final result = await _read(requests[index].options);
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
  }) => _read(options);
}

final class _Locations implements ExternalSkillLocationPort {
  ExternalDiscoveryResult<List<ScannedExternalSkill>> result =
      ExternalDiscoverySuccess<List<ScannedExternalSkill>>(value: const []);
  final List<String> locations = <String>[];
  bool? includeInternal;

  @override
  Future<ExternalDiscoveryResult<List<ScannedExternalSkill>>> scanLocation({
    required String location,
    Set<String>? selectedSlotKeys,
    required bool includeInternal,
    required CancellationToken cancellationToken,
  }) async {
    locations.add(location);
    this.includeInternal = includeInternal;
    return result;
  }
}

final class _History implements WorkspaceHistoryPort {
  OperationHistoryPage operationPage = OperationHistoryPage(entries: const []);
  PublishedHistoryPage publishedPage = PublishedHistoryPage(
    revisions: const [],
  );
  Object? operationError;
  Object? publishedError;
  var operationReads = 0;
  var publishedReads = 0;
  ManagedSkillId? operationSkillId;
  String? operationCursor;
  int? operationLimit;
  ManagedSkillId? publishedSkillId;
  String? publishedCursor;
  int? publishedLimit;

  @override
  Future<OperationHistoryPage> readOperationHistory({
    ManagedSkillId? managedSkillId,
    String? cursor,
    required int limit,
  }) async {
    operationReads += 1;
    operationSkillId = managedSkillId;
    operationCursor = cursor;
    operationLimit = limit;
    if (operationError case final failure?) throw failure;
    return operationPage;
  }

  @override
  Future<PublishedHistoryPage> readPublishedHistory({
    required ManagedSkillId managedSkillId,
    String? cursor,
    required int limit,
  }) async {
    publishedReads += 1;
    publishedSkillId = managedSkillId;
    publishedCursor = cursor;
    publishedLimit = limit;
    if (publishedError case final failure?) throw failure;
    return publishedPage;
  }
}

final class _Detection implements AgentDetectionPort {
  const _Detection();

  @override
  Future<bool> matches(
    AgentDetectionPath detection, {
    ProjectRoot? projectRoot,
  }) async => false;
}

final class _Links implements SymbolicLinkCapabilityPort {
  const _Links();

  @override
  Future<bool> supportsSymbolicLinks(String targetLocation) async => false;
}

final class _LocationIdentity implements ActivationLocationIdentityPort {
  const _LocationIdentity({this.sameObjectPairs = const <(String, String)>{}});

  final Set<(String, String)> sameObjectPairs;

  @override
  Future<bool> sameExistingObject(String left, String right) async =>
      key(left) == key(right) ||
      sameObjectPairs.contains((left, right)) ||
      sameObjectPairs.contains((right, left));

  @override
  Future<String?> resolveExistingDirectory(String location) async =>
      normalize(location);

  @override
  String normalize(String location) => path.posix.normalize(location);

  @override
  String key(String location) => normalize(location);
}

String _platformLocation(String value) => path.normalize(path.absolute(value));

AcquiredSource _acquiredSource() => AcquiredSource(
  canonicalSource: _source,
  skills: <AcquiredSourceSkill>[
    AcquiredSourceSkill(
      provenance: _source,
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
    ),
  ],
);

ScannedExternalSkill _scannedSkill() => ScannedExternalSkill(
  declaredName: 'example',
  description: 'Example Skill',
  slotKey: 'example',
  contentHash: 'a' * 64,
  skillLocation: '/agents/skills/example',
  source: _source,
);

RepositorySnapshot _snapshot({
  int revision = 0,
  UpdateCandidateSummary? candidate,
}) => RepositorySnapshot(
  revision: RepositoryRevision(revision),
  managedSkills: <ManagedSkill>[
    ManagedSkill(
      id: _skillId,
      slotKey: 'example',
      declaredName: 'example',
      displayName: 'Example',
      description: 'Example Skill',
      source: _source,
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        publishedAt: _now,
      ),
      updateCandidate: candidate,
    ),
  ],
);

const _agentId = 'agent';
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _operationId = OperationId('123e4567-e89b-42d3-b456-426614174001');
final _source = LocalSourceDescriptor(locator: '/tmp/example');
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
