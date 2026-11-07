import 'dart:async';

import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/drift/drift_models.dart';
import 'package:skills_workspace/src/application/drift/drift_resolution_planner.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/published_artifact_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/drift_command_handlers.dart';
import 'package:skills_workspace/src/composition/skill_integrity_coordinator.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';

import 'drift_test_support.dart';
import 'operations/operation_fakes.dart';

final class DriftCommandFixture {
  final operations = OperationHarness();
  final materializations = FakeDriftCommandMaterializations();
  final revisions = FakeDriftCommandRevisions();
  final exporter = FakeDriftCommandExporter();
  final content = FakeDriftHistoryContent();
  late final FakeDriftCommandSnapshotReader reader;
  late final WorkspaceSnapshotPublisher snapshots;
  late final SkillIntegrityCoordinator integrity;
  late final CompositeSkillsRepositoryCommandDispatcher dispatcher;
  final progress = <OperationProgressPhase>[];
  final committed = Completer<void>();

  static Future<DriftCommandFixture> create() async {
    final fixture = DriftCommandFixture();
    fixture.reader = FakeDriftCommandSnapshotReader(fixture.operations);
    fixture.snapshots = WorkspaceSnapshotPublisher(reader: fixture.reader);
    await fixture.snapshots.publishInitial(await fixture.reader.read());
    fixture.integrity = SkillIntegrityCoordinator(
      snapshots: fixture.snapshots,
      materializations: fixture.materializations,
      writerLock: fixture.operations.writerLock,
    );
    fixture.dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      buildDriftCommandHandlers(
        snapshots: fixture.snapshots,
        materializations: fixture.materializations,
        inspector: FakeDriftCommandInspector(),
        exporter: fixture.exporter,
        planner: DriftResolutionPlanner(
          content: fixture.content,
          clock: () => DateTime.utc(2026, 10, 14),
        ),
        revisions: fixture.revisions,
        plans: FakeDriftCommandPlans(),
        operations: fixture.operations.createCoordinator(),
        integrity: fixture.integrity,
        forbiddenExportRoots: () => const ['/workspace'],
      ),
    );
    return fixture;
  }

  Future<SkillsResult<T>> execute<T>(
    WorkspaceOperationKind kind,
    Object request,
  ) => dispatcher.execute<T>(
    operationId: OperationId('123e4567-e89b-42d3-a456-426614174005'),
    kind: kind,
    request: request,
    cancellationToken: CancellationToken.none(),
    markBusinessCommitted: () {
      if (!committed.isCompleted) committed.complete();
    },
    reportProgress: (phase, {currentItem, completed = 0, total}) {
      progress.add(phase);
    },
  );

  Future<SkillDriftReview> inspect() async => (await execute<SkillDriftReview>(
    WorkspaceOperationKind.inspectSkillDrift,
    InspectSkillDriftRequest(managedSkillId: driftSkillId),
  )).valueOrNull!;

  Future<SkillsResult<MutationReport>> restore(SkillDriftReview review) =>
      execute<MutationReport>(
        WorkspaceOperationKind.resolveSkillDrift,
        ResolveSkillDriftRequest(
          review: review,
          resolution: const RestoreManagedSkillDrift(),
        ),
      );

  SkillIntegrityStatus get status => snapshots.current.integrity.skills
      .singleWhere((state) => state.managedSkillId == driftSkillId)
      .status;
}

final class FakeDriftCommandSnapshotReader
    implements WorkspaceSnapshotReaderPort {
  FakeDriftCommandSnapshotReader(this.operations);
  final OperationHarness operations;
  bool throwOnRead = false;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async {
    if (throwOnRead) throw StateError('injected reload failure');
    return RepositorySnapshot(
      revision: operations.controlPlane.repositoryRevision,
      managedSkills: [driftSkill()],
      integrity: integrity ?? WorkspaceIntegrity(),
    );
  }
}

final class FakeDriftCommandMaterializations
    implements WorkspaceMaterializationReconciliationPort {
  SkillMaterializationInspection inspection = driftInspection();
  Completer<WorkspaceMaterializationReconciliationReport>? blockedValidation;
  final validationStarted = Completer<void>();
  int validations = 0;

  @override
  Future<SkillMaterializationInspection> inspectSkillMaterializations(
    ManagedSkillId managedSkillId, {
    CancellationToken? cancellationToken,
  }) async => inspection;

  @override
  Future<WorkspaceMaterializationReconciliationReport>
  reconcileMaterializations({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
    bool repairMismatching = true,
    bool repairMissing = true,
  }) async {
    validations++;
    if (!validationStarted.isCompleted) validationStarted.complete();
    if (validations == 1 && blockedValidation != null) {
      return blockedValidation!.future;
    }
    return driftReconciliation();
  }
}

WorkspaceMaterializationReconciliationReport driftReconciliation({
  bool drifted = false,
}) => WorkspaceMaterializationReconciliationReport(
  inspectedArtifactCount: 1,
  inspectedFileCount: 1,
  inspectedByteCount: 1,
  repairedArtifactCount: 0,
  inspectionElapsed: Duration.zero,
  repairElapsed: Duration.zero,
  mismatchingArtifactCount: drifted ? 1 : 0,
  mismatchingSkillIds: drifted ? [driftSkillId] : const [],
);

final class FakeDriftCommandRevisions implements DriftRevisionPreparationPort {
  DriftResult<RevisionObjectId> result = DriftSuccess(value: driftObject('2'));
  int calls = 0;

  @override
  Future<DriftResult<RevisionObjectId>> prepareRestoreArtifacts({
    required PreparedOperationEnvelope envelope,
    required DriftResolutionPreflight preflight,
    required CancellationToken cancellationToken,
  }) async {
    calls++;
    return result;
  }

  @override
  Future<DriftResult<PreparedRestorePublish>> prepareAcceptExternal({
    required PreparedOperationEnvelope envelope,
    required DriftResolutionPreflight preflight,
    required CancellationToken cancellationToken,
  }) => throw UnimplementedError();
}

final class FakeDriftCommandPlans implements DriftOperationPlanPort {
  @override
  PreparedOperationEnvelope createDriftEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required DriftResolutionPreflight preflight,
  }) => PreparedOperationEnvelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    committedRepositoryRevision: expectedRepositoryRevision.next(),
    operationGeneration: expectedRepositoryRevision.next().value,
    preparationSteps: [
      PreparationOperationStep(
        stepId: 'prepare',
        recoveryReference: RecoveryReference('prepare'),
        kind: PreparationStepKind.revisionCandidate,
      ),
    ],
    record: OperationRecordPlan(
      operationId: operationId,
      kind: WorkspaceOperationKind.resolveSkillDrift.name,
      subjects: const [],
      retainWithoutSubjects: true,
    ),
  );

  @override
  OperationPlan sealDriftPlan({
    required PreparedOperationEnvelope envelope,
    required DriftResolutionPreflight preflight,
    required PreparedRestorePublishPlan? publishedPlan,
    required CancellationToken cancellationToken,
  }) => OperationPlan(
    operationId: envelope.operationId,
    expectedRepositoryRevision: envelope.expectedRepositoryRevision,
    committedRepositoryRevision: envelope.committedRepositoryRevision,
    operationGeneration: envelope.operationGeneration,
    preparationSteps: envelope.preparationSteps,
    applyingSteps: [
      ApplyingOperationStep(
        stepId: 'apply',
        recoveryReference: RecoveryReference('apply'),
        kind: ApplyingStepKind.materializationReplacement,
      ),
    ],
    finalizationSteps: [
      FinalizationOperationStep(
        stepId: 'finalize',
        recoveryReference: RecoveryReference('finalize'),
        kind: FinalizationStepKind.materializationVerification,
      ),
    ],
    record: envelope.record,
    revisionSelectionChanges: const [],
  );
}

final class FakeDriftCommandExporter implements DriftArtifactExporterPort {
  DriftResult<String> result = const DriftSuccess(value: '/exports/sample');

  @override
  Future<DriftResult<String>> export({
    required String sourcePath,
    required String slotKey,
    required String destinationDirectory,
    required List<String> forbiddenRoots,
    required String expectedFingerprint,
    required PublishedArtifactInspectorPort inspector,
    required CancellationToken cancellationToken,
    required DateTime now,
  }) async => result;
}

final class FakeDriftCommandInspector
    implements PublishedArtifactInspectorPort {
  @override
  Future<PublishedArtifactInspection> observeMetadata({
    required String path,
    required CancellationToken cancellationToken,
  }) => observe(path: path, cancellationToken: cancellationToken);

  @override
  Future<PublishedArtifactInspection> observe({
    required String path,
    required CancellationToken cancellationToken,
  }) async => driftInspection().artifacts.single.inspection;

  @override
  Future<PublishedArtifactInspection> inspectDirectory({
    required String path,
    required String expectedContentHash,
    required CancellationToken cancellationToken,
  }) => observe(path: path, cancellationToken: cancellationToken);

  @override
  Future<PublishedArtifactInspection> inspectSymbolicLink({
    required String path,
    required String expectedTarget,
    required CancellationToken cancellationToken,
  }) => observe(path: path, cancellationToken: cancellationToken);
}
