import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/drift/drift_models.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/history/history_ports.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/published_artifact_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';

final driftSkillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final driftLineage = SourceLineageReference(
  '123e4567-e89b-42d3-8456-426614174001',
);
RevisionObjectId driftObject(String character) =>
    RevisionObjectId(character * 40);
final driftTargetPath = path.join(Directory.systemTemp.path, 'reviewed-copy');

ManagedSkill driftSkill({
  DraftSummary? draft,
  UpdateCandidateSummary? updateCandidate,
  List<SkillActivation> activations = const [],
}) => ManagedSkill(
  id: driftSkillId,
  slotKey: 'sample',
  declaredName: 'sample',
  displayName: 'Sample',
  description: 'Current',
  source: LocalSourceDescriptor(locator: Directory.systemTemp.path),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: 'a' * 64,
    fileCount: 1,
    byteSize: 1,
    publishedAt: DateTime.utc(2026, 10, 14),
  ),
  draft: draft,
  updateCandidate: updateCandidate,
  activations: activations,
);

DraftSummary driftDraft() => DraftSummary(
  purpose: DraftPurpose.customization,
  path: path.join(Directory.systemTemp.path, 'draft'),
  isDirty: false,
  updatedAt: DateTime.utc(2026, 10, 14),
);

RestoreRevisionState driftState({RevisionObjectId? effective}) =>
    RestoreRevisionState(
      managedSkillId: driftSkillId,
      sourceLineage: driftLineage,
      currentUpstream: driftObject('1'),
      currentEffective: effective ?? driftObject('2'),
      managedSkillCreatedAtMicros: 1,
      draftCreatedAtMicros: 2,
    );

SkillMaterializationInspection driftInspection({
  RevisionObjectId? effective,
  String? fingerprint,
  String? targetPath,
  SkillDriftLocationKind kind = SkillDriftLocationKind.repositoryCopy,
  PublishedArtifactMismatchKind mismatch =
      PublishedArtifactMismatchKind.contentChanged,
}) => SkillMaterializationInspection(
  effectiveObjectId: effective ?? driftObject('2'),
  effectiveContentHash: 'a' * 64,
  artifacts: [
    SkillMaterializationArtifact(
      locationKind: kind,
      targetPath: targetPath ?? driftTargetPath,
      inspection: PublishedArtifactInspection(
        state: PublishedArtifactState.mismatching,
        observedEntryKind: ObservedEntryKind.directory,
        mismatchKind: mismatch,
        fingerprint: fingerprint ?? 'b' * 64,
        fileCount: 1,
        byteSize: 2,
      ),
    ),
  ],
);

DriftReviewEvidence driftReview({
  bool canKeep = true,
  SkillMaterializationInspection? inspected,
  SkillDriftLocationKind kind = SkillDriftLocationKind.repositoryCopy,
  SkillDriftKind driftKind = SkillDriftKind.contentChanged,
}) =>
    createDriftReview(
          owner: Object(),
          managedSkillId: driftSkillId,
          inspected: inspected ?? driftInspection(kind: kind),
          missingArtifactCount: 0,
          artifacts: [
            SkillDriftArtifact(
              artifactId: 'repositoryCopy',
              locationKind: kind,
              driftKind: driftKind,
              canKeepExternal: canKeep,
              canExport: true,
            ),
          ],
        )
        as DriftReviewEvidence;

DriftResolutionPreflight driftPreflight({
  ManagedSkill? skill,
  RestoreRevisionState? state,
  String? selectedPath,
  String? selectedFingerprint,
  bool hadCleanDraft = false,
}) {
  final inspected = driftInspection(
    effective: state?.currentEffective,
    targetPath: selectedPath,
    fingerprint: selectedFingerprint,
  );
  return DriftResolutionPreflight(
    snapshotRevision: RepositoryRevision(5),
    plannedAtMicros: 10,
    skill: skill ?? driftSkill(),
    state: state ?? driftState(),
    review: driftReview(inspected: inspected),
    current: inspected,
    resolution: const KeepExternalSkillDrift('repositoryCopy'),
    selectedPath: selectedPath ?? driftTargetPath,
    selectedFingerprint: selectedFingerprint ?? 'b' * 64,
    hadCleanDraft: hadCleanDraft,
  );
}

final class FakeDriftHistoryContent implements WorkspaceHistoryContentPort {
  RestoreRevisionState? state = driftState();
  HistoryResult<bool> draftResult = const HistorySuccess(false);
  int draftInspections = 0;

  @override
  Future<RestoreRevisionState?> readRestoreState(
    ManagedSkillId managedSkillId,
  ) async => state;

  @override
  Future<HistoryResult<bool>> inspectDraftDirty({
    required ManagedSkill skill,
    required RestoreRevisionState state,
    required CancellationToken cancellationToken,
  }) async {
    draftInspections += 1;
    return draftResult;
  }

  @override
  Future<HistoricalRevisionSelection?> resolvePublishedRevision({
    required ManagedSkillId managedSkillId,
    required OperationSubjectReference reference,
  }) => throw UnimplementedError();

  @override
  Future<HistoryResult<SkillDiff>> compare({
    required ManagedSkillId managedSkillId,
    required HistoricalRevisionSelection? from,
    required HistoricalRevisionSelection to,
    required CancellationToken cancellationToken,
  }) => throw UnimplementedError();
}
