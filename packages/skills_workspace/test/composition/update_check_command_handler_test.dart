import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_coordinator.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/application/update/update_planner.dart';
import 'package:skills_workspace/src/composition/update_check_command_handler.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../support/source/source_acquisition_fakes.dart';
import '../support/update/update_fakes.dart';

void main() {
  late FakeSourceAcquisitionPorts sources;
  late WorkspaceSnapshotPublisher snapshots;
  late CompositeSkillsRepositoryCommandDispatcher dispatcher;

  setUp(() async {
    sources = FakeSourceAcquisitionPorts((source, _, _, _) async {
      return SourceAcquisitionSuccess<AcquiredSource>(
        value: AcquiredSource(
          canonicalSource: source,
          resolvedSourceRevision: 'upstream-2',
          skills: <AcquiredSourceSkill>[
            AcquiredSourceSkill(
              provenance: source,
              declaredName: 'example',
              description: 'Updated',
              slotKey: 'example',
              skillPath: '',
              frontmatter: const <String, Object?>{},
              tree: _tree('b'),
            ),
          ],
        ),
      );
    });
    final snapshot = _snapshot();
    snapshots = WorkspaceSnapshotPublisher(reader: _SnapshotReader(snapshot));
    await snapshots.publishInitial(snapshot);
    final state = UpdateRevisionState(
      managedSkillId: _skillId,
      sourceLineage: SourceLineageReference(
        '123e4567-e89b-42d3-a456-426614174001',
      ),
      previousUpstream: RevisionObjectId('a' * 40),
      currentEffective: RevisionObjectId('a' * 40),
      previousUpstreamContentHash: 'a' * 64,
      managedSkillCreatedAtMicros: 1,
      draftCreatedAtMicros: null,
    );
    final coordinator = SourceAcquisitionCoordinator(
      local: sources,
      git: sources,
      wellKnown: sources,
    );
    final planner = UpdatePlanner(
      sourceAcquisition: coordinator,
      drafts: RecordingUpdateDraftInspector(),
      states: RecordingUpdateRevisionStateReader(state),
      slotMigrations: RecordingSlotMigrationInspector(),
      clock: () => DateTime.utc(2026, 8, 17),
    );
    dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      <SkillsCommandHandler>[
        buildUpdateCheckCommandHandler(snapshots: snapshots, updates: planner),
      ],
    );
  });

  tearDown(() => snapshots.close());

  test('reports an available update with resolved source revision', () async {
    final result = await _execute(
      dispatcher,
      CheckUpdatesRequest(managedSkillIds: <ManagedSkillId>{_skillId}),
    );

    expect(result.valueOrNull?.single.status, UpdateStatus.updateAvailable);
    expect(result.valueOrNull?.single.currentContentHash, 'a' * 64);
    expect(result.valueOrNull?.single.availableContentHash, 'b' * 64);
    expect(result.valueOrNull?.single.resolvedSourceRevision, 'upstream-2');
  });

  test('a removed Skill gets no report without failing the others', () async {
    final missing = ManagedSkillId('123e4567-e89b-42d3-b456-426614174002');

    final result = await _execute(
      dispatcher,
      CheckUpdatesRequest(managedSkillIds: <ManagedSkillId>{_skillId, missing}),
    );

    expect(result.valueOrNull?.single.managedSkillId, _skillId);
    expect(result.valueOrNull?.single.status, UpdateStatus.updateAvailable);
  });

  test(
    'fails before source acquisition when no requested Skill exists',
    () async {
      final missing = ManagedSkillId('123e4567-e89b-42d3-b456-426614174002');

      final result = await _execute(
        dispatcher,
        CheckUpdatesRequest(managedSkillIds: <ManagedSkillId>{missing}),
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.skillNotFound);
      expect(sources.calls, isEmpty);
    },
  );

  test(
    'checks every Skill, reports current, and preserves source warnings',
    () async {
      final harness = await _buildHarness(
        sourceResult: _sourceSuccess(
          treeHash: 'a',
          warnings: <SourceAcquisitionWarning>[
            SourceAcquisitionWarning(
              code: SourceAcquisitionWarningCode.sourceEntrySkipped,
              context: const <String, Object?>{'entry': 'ignored'},
            ),
          ],
        ),
      );
      addTearDown(harness.snapshots.close);

      final result = await _execute(harness.dispatcher, CheckUpdatesRequest());

      expect(result.valueOrNull?.single.status, UpdateStatus.current);
      expect(result.warnings.single.code, SkillsWarningCode.sourceEntrySkipped);
      expect(result.warnings.single.context['entry'], 'ignored');
    },
  );

  test('dirty Draft and persisted Session require resolution', () async {
    for (final snapshot in <RepositorySnapshot>[
      _snapshot(draftDirty: true),
      _snapshot(withUpdateCandidate: true),
    ]) {
      final harness = await _buildHarness(snapshot: snapshot);
      addTearDown(harness.snapshots.close);

      final result = await _execute(
        harness.dispatcher,
        CheckUpdatesRequest(managedSkillIds: <ManagedSkillId>{_skillId}),
      );

      expect(
        result.valueOrNull?.single.status,
        UpdateStatus.resolutionRequired,
      );
    }
  });

  test('an adopted snapshot reports updates unsupported', () async {
    final harness = await _buildHarness(
      snapshot: _snapshot(
        source: AdoptedSnapshotSourceDescriptor(
          authoritativeLocation: '/adopted/example',
          contentHash: 'a' * 64,
        ),
      ),
    );
    addTearDown(harness.snapshots.close);

    final result = await _execute(harness.dispatcher, CheckUpdatesRequest());

    expect(result.valueOrNull?.single.status, UpdateStatus.updateUnsupported);
    expect(harness.sources.calls, isEmpty);
  });

  test('unavailable revision state becomes source unavailable', () async {
    final harness = await _buildHarness(hasState: false);
    addTearDown(harness.snapshots.close);

    final result = await _execute(harness.dispatcher, CheckUpdatesRequest());

    expect(result.valueOrNull?.single.status, UpdateStatus.sourceUnavailable);
  });

  test('source failure becomes unavailable and keeps warnings', () async {
    final harness = await _buildHarness(
      sourceResult: SourceAcquisitionFailure<AcquiredSource>(
        code: SourceAcquisitionFailureCode.sourceUnavailable,
        warnings: <SourceAcquisitionWarning>[
          SourceAcquisitionWarning(
            code: SourceAcquisitionWarningCode.sourceEntrySkipped,
            context: const <String, Object?>{'entry': 'bad'},
          ),
        ],
      ),
    );
    addTearDown(harness.snapshots.close);

    final result = await _execute(harness.dispatcher, CheckUpdatesRequest());

    expect(result.valueOrNull?.single.status, UpdateStatus.sourceUnavailable);
    expect(result.warnings.single.context['entry'], 'bad');
  });

  test('Git timeout remains visible on the unavailable report', () async {
    final harness = await _buildHarness(
      sourceResult: SourceAcquisitionFailure<AcquiredSource>(
        code: SourceAcquisitionFailureCode.gitTimedOut,
      ),
    );
    addTearDown(harness.snapshots.close);

    final result = await _execute(harness.dispatcher, CheckUpdatesRequest());

    final report = result.valueOrNull!.single;
    expect(report.status, UpdateStatus.sourceUnavailable);
    expect(report.failureReason, UpdateCheckFailureReason.timedOut);
  });

  test('source cancellation is a terminal cancellation failure', () async {
    final harness = await _buildHarness(
      sourceResult: SourceAcquisitionFailure<AcquiredSource>(
        code: SourceAcquisitionFailureCode.operationCancelled,
        warnings: <SourceAcquisitionWarning>[
          SourceAcquisitionWarning(
            code: SourceAcquisitionWarningCode.sourceEntrySkipped,
          ),
        ],
      ),
    );
    addTearDown(harness.snapshots.close);

    final result = await _execute(harness.dispatcher, CheckUpdatesRequest());

    expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
    expect(result.warnings, hasLength(1));
  });

  test('pre-cancelled checks stop before source acquisition', () async {
    final harness = await _buildHarness();
    addTearDown(harness.snapshots.close);
    final cancellation = CancellationSource();
    await cancellation.cancel();

    final result = await _execute(
      harness.dispatcher,
      CheckUpdatesRequest(),
      cancellationToken: cancellation.token,
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
    expect(harness.sources.calls, isEmpty);
  });

  test('changed source identity cannot establish update continuity', () async {
    final harness = await _buildHarness(
      sourceResult: _sourceSuccess(
        canonicalSource: LocalSourceDescriptor(locator: '/other/example'),
      ),
    );
    addTearDown(harness.snapshots.close);

    final result = await _execute(harness.dispatcher, CheckUpdatesRequest());

    expect(result.valueOrNull?.single.status, UpdateStatus.sourceUnavailable);
  });

  test('unsupported incoming name requires user resolution', () async {
    final harness = await _buildHarness(
      sourceResult: _sourceSuccess(
        declaredName: 'Example',
        slotKey: 'not-example',
      ),
    );
    addTearDown(harness.snapshots.close);

    final result = await _execute(harness.dispatcher, CheckUpdatesRequest());

    expect(result.valueOrNull?.single.status, UpdateStatus.resolutionRequired);
  });
}

final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');

RepositorySnapshot _snapshot({
  SourceDescriptor? source,
  bool draftDirty = false,
  bool withUpdateCandidate = false,
}) => RepositorySnapshot(
  revision: RepositoryRevision.initial(),
  managedSkills: <ManagedSkill>[
    ManagedSkill(
      id: _skillId,
      slotKey: 'example',
      declaredName: 'example',
      displayName: 'Example',
      description: 'Example',
      source: source ?? LocalSourceDescriptor(locator: '/source/example'),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        publishedAt: DateTime.utc(2026),
      ),
      draft: draftDirty
          ? DraftSummary(
              purpose: DraftPurpose.customization,
              path: '/draft/example',
              isDirty: true,
              updatedAt: DateTime.utc(2026),
            )
          : null,
      updateCandidate: withUpdateCandidate
          ? UpdateCandidateSummary(
              status: UpdateCandidateStatus.validationFailed,
              conflicts: const <UpdateConflict>[],
              createdAt: DateTime.utc(2026),
              validationCode: 'invalidSkill',
            )
          : null,
    ),
  ],
);

Future<_UpdateCheckHarness> _buildHarness({
  RepositorySnapshot? snapshot,
  bool hasState = true,
  SourceAcquisitionResult<AcquiredSource>? sourceResult,
}) async {
  final currentSnapshot = snapshot ?? _snapshot();
  final source = currentSnapshot.managedSkills.single.source;
  final sources = FakeSourceAcquisitionPorts((_, _, _, _) async {
    return sourceResult ?? _sourceSuccess(canonicalSource: source);
  });
  final snapshots = WorkspaceSnapshotPublisher(
    reader: _SnapshotReader(currentSnapshot),
  );
  await snapshots.publishInitial(currentSnapshot);
  final planner = UpdatePlanner(
    sourceAcquisition: SourceAcquisitionCoordinator(
      local: sources,
      git: sources,
      wellKnown: sources,
    ),
    drafts: RecordingUpdateDraftInspector(),
    states: RecordingUpdateRevisionStateReader(hasState ? _defaultState : null),
    slotMigrations: RecordingSlotMigrationInspector(),
    clock: () => DateTime.utc(2026, 8, 17),
  );
  return _UpdateCheckHarness(
    dispatcher: CompositeSkillsRepositoryCommandDispatcher(
      <SkillsCommandHandler>[
        buildUpdateCheckCommandHandler(snapshots: snapshots, updates: planner),
      ],
    ),
    snapshots: snapshots,
    sources: sources,
  );
}

SourceAcquisitionSuccess<AcquiredSource> _sourceSuccess({
  SourceDescriptor? canonicalSource,
  String declaredName = 'example',
  String slotKey = 'example',
  String treeHash = 'b',
  List<SourceAcquisitionWarning> warnings = const <SourceAcquisitionWarning>[],
}) {
  final source =
      canonicalSource ?? LocalSourceDescriptor(locator: '/source/example');
  return SourceAcquisitionSuccess<AcquiredSource>(
    value: AcquiredSource(
      canonicalSource: source,
      resolvedSourceRevision: 'upstream-2',
      skills: <AcquiredSourceSkill>[
        AcquiredSourceSkill(
          provenance: source,
          declaredName: declaredName,
          description: 'Updated',
          slotKey: slotKey,
          skillPath: '',
          frontmatter: const <String, Object?>{},
          tree: _tree(treeHash),
        ),
      ],
    ),
    warnings: warnings,
  );
}

final _defaultState = UpdateRevisionState(
  managedSkillId: _skillId,
  sourceLineage: SourceLineageReference('123e4567-e89b-42d3-a456-426614174001'),
  previousUpstream: RevisionObjectId('a' * 40),
  currentEffective: RevisionObjectId('a' * 40),
  previousUpstreamContentHash: 'a' * 64,
  managedSkillCreatedAtMicros: 1,
  draftCreatedAtMicros: null,
);

final class _UpdateCheckHarness {
  const _UpdateCheckHarness({
    required this.dispatcher,
    required this.snapshots,
    required this.sources,
  });

  final CompositeSkillsRepositoryCommandDispatcher dispatcher;
  final WorkspaceSnapshotPublisher snapshots;
  final FakeSourceAcquisitionPorts sources;
}

NormalizedSkillTree _tree(String hex) => NormalizedSkillTree(
  files: <NormalizedSkillFile>[
    NormalizedSkillFile(
      relativePath: 'SKILL.md',
      bytes: <int>[hex.codeUnitAt(0)],
      isExecutable: false,
    ),
  ],
  contentHash: hex * 64,
  byteSize: 1,
);

Future<SkillsResult<List<UpdateReport>>> _execute(
  CompositeSkillsRepositoryCommandDispatcher dispatcher,
  CheckUpdatesRequest request, {
  CancellationToken? cancellationToken,
}) => dispatcher.execute<List<UpdateReport>>(
  operationId: OperationId('123e4567-e89b-42d3-8456-426614174003'),
  kind: WorkspaceOperationKind.checkUpdates,
  request: request,
  cancellationToken: cancellationToken ?? CancellationToken.none(),
  markBusinessCommitted: () {},
  reportProgress: (phase, {currentItem, completed = 0, total}) {},
);

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  const _SnapshotReader(this.snapshot);

  final RepositorySnapshot snapshot;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      snapshot;
}
