import 'package:skills_workspace/src/application/drift/drift_models.dart';
import 'package:skills_workspace/src/application/drift/drift_artifacts.dart';
import 'package:skills_workspace/src/application/ports/published_artifact_ports.dart';
import 'package:skills_workspace/src/application/drift/drift_resolution_planner.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

import '../../support/drift_test_support.dart';

void main() {
  late FakeDriftHistoryContent content;
  late DriftResolutionPlanner planner;
  setUp(() {
    content = FakeDriftHistoryContent();
    planner = DriftResolutionPlanner(
      content: content,
      clock: () => DateTime.utc(2026, 10, 14),
    );
  });

  Future<DriftResult<DriftResolutionPreflight>> plan({
    ManagedSkill? skill,
    DriftReviewEvidence? review,
    SkillMaterializationInspection? current,
    SkillDriftResolution resolution = const KeepExternalSkillDrift(
      'repositoryCopy',
    ),
  }) => planner.plan(
    snapshot: RepositorySnapshot(
      revision: RepositoryRevision(5),
      managedSkills: [skill ?? driftSkill()],
    ),
    review: review ?? driftReview(),
    current: current ?? driftInspection(),
    resolution: resolution,
    cancellationToken: CancellationToken.none(),
  );

  test(
    'keep selects by artifact ID with public artifacts in a different order',
    () async {
      final original = driftInspection();
      final activationPath = '$driftTargetPath-activation';
      final activation = SkillMaterializationArtifact(
        locationKind: SkillDriftLocationKind.copyActivation,
        targetPath: activationPath,
        inspection: const PublishedArtifactInspection(
          state: PublishedArtifactState.mismatching,
          mismatchKind: PublishedArtifactMismatchKind.contentChanged,
          observedEntryKind: ObservedEntryKind.directory,
          fingerprint: 'selected',
        ),
      );
      final inspected = SkillMaterializationInspection(
        effectiveObjectId: original.effectiveObjectId,
        effectiveContentHash: original.effectiveContentHash,
        artifacts: [...original.artifacts, activation],
      );
      final review =
          createDriftReview(
                owner: Object(),
                managedSkillId: driftSkillId,
                inspected: inspected,
                artifacts: driftArtifactsFor(inspected).reversed.toList(),
                missingArtifactCount: 0,
              )
              as DriftReviewEvidence;
      final result = await plan(
        review: review,
        current: inspected,
        resolution: KeepExternalSkillDrift(driftArtifactId(activation)),
      );
      expect(result.valueOrNull!.selectedPath, activationPath);
      expect(result.valueOrNull!.selectedFingerprint, 'selected');
    },
  );

  test('keep captures the selected path and reviewed fingerprint', () async {
    final result = await plan();
    expect(result.valueOrNull!.selectedPath, driftTargetPath);
    expect(result.valueOrNull!.selectedFingerprint, 'b' * 64);
    expect(result.valueOrNull!.state.currentEffective, driftObject('2'));
    expect(result.valueOrNull!.hadCleanDraft, isFalse);
    expect(content.draftInspections, 0);
  });

  test(
    'keep fully inspects an existing Draft and retains clean Draft evidence',
    () async {
      final result = await plan(skill: driftSkill(draft: driftDraft()));
      expect(result.valueOrNull!.hadCleanDraft, isTrue);
      expect(content.draftInspections, 1);
    },
  );

  test(
    'cancelled Draft inspection preserves the cancellation outcome',
    () async {
      content.draftResult = HistoryFailure(
        code: HistoryFailureCode.operationCancelled,
      );
      final result = await plan(skill: driftSkill(draft: driftDraft()));
      expect(result.failureOrNull!.code, DriftFailureCode.operationCancelled);
      expect(content.draftInspections, 1);
    },
  );

  test('keep rejects a dirty Draft before preparation', () async {
    content.draftResult = const HistorySuccess(true);
    final result = await plan(skill: driftSkill(draft: driftDraft()));
    expect(
      result.failureOrNull!.code,
      DriftFailureCode.dirtyDraftResolutionRequired,
    );
    expect(content.draftInspections, 1);
  });

  test(
    'keep rejects pending update candidates without inspecting the Draft',
    () async {
      final result = await plan(
        skill: driftSkill(
          draft: driftDraft(),
          updateCandidate: UpdateCandidateSummary(
            status: UpdateCandidateStatus.validationFailed,
            conflicts: const [],
            validationCode: 'invalidSkill',
            createdAt: DateTime.utc(2026, 10, 14),
          ),
        ),
      );
      expect(
        result.failureOrNull!.code,
        DriftFailureCode.updateCandidateResolutionRequired,
      );
      expect(content.draftInspections, 0);
    },
  );

  for (final kind in [
    SkillDriftLocationKind.symbolicLinkActivation,
    SkillDriftLocationKind.repositoryCopy,
  ]) {
    test('keep rejects restore-only $kind', () async {
      final result = await plan(
        current: driftInspection(kind: kind),
        review: driftReview(
          canKeep: false,
          kind: kind,
          driftKind: kind == SkillDriftLocationKind.repositoryCopy
              ? SkillDriftKind.wrongEntryType
              : SkillDriftKind.wrongLinkTarget,
        ),
      );
      expect(
        result.failureOrNull!.code,
        DriftFailureCode.driftResolutionUnavailable,
      );
      expect(result.failureOrNull!.context['reason'], 'keepNotAllowed');
    });
  }

  for (final resolution in [
    const KeepExternalSkillDrift('repositoryCopy'),
    const RestoreManagedSkillDrift(),
  ]) {
    test(
      '$resolution rejects a changed authoritative Effective revision',
      () async {
        content.state = driftState(effective: driftObject('3'));
        final result = await plan(resolution: resolution);
        expect(result.failureOrNull!.code, DriftFailureCode.staleDriftReview);
        expect(
          result.failureOrNull!.context['reason'],
          'effectiveRevisionChanged',
        );
      },
    );
    test(
      '$resolution rejects changed materialization selection evidence',
      () async {
        final result = await plan(
          resolution: resolution,
          current: driftInspection(effective: driftObject('3')),
        );
        expect(result.failureOrNull!.code, DriftFailureCode.staleDriftReview);
        expect(
          result.failureOrNull!.context['reason'],
          'effectiveRevisionChanged',
        );
      },
    );
  }

  test('restore leaves dirty Draft and update candidate untouched', () async {
    content.draftResult = const HistorySuccess(true);
    final result = await plan(
      resolution: const RestoreManagedSkillDrift(),
      skill: driftSkill(
        draft: driftDraft(),
        updateCandidate: UpdateCandidateSummary(
          status: UpdateCandidateStatus.validationFailed,
          conflicts: const [],
          validationCode: 'invalidSkill',
          createdAt: DateTime.utc(2026, 10, 14),
        ),
      ),
    );
    expect(result.valueOrNull!.keepsExternal, isFalse);
    expect(result.valueOrNull!.selectedPath, isNull);
    expect(content.draftInspections, 0);
  });

  test(
    'unknown artifact is stale rather than selecting another artifact',
    () async {
      final result = await plan(
        resolution: const KeepExternalSkillDrift('absent'),
      );
      expect(result.failureOrNull!.code, DriftFailureCode.staleDriftReview);
      expect(result.failureOrNull!.context['reason'], 'artifactNotFound');
    },
  );

  test('unreadable selected revision fails closed', () async {
    content.state = null;
    final result = await plan();
    expect(result.failureOrNull!.code, DriftFailureCode.revisionStoreCorrupt);
  });

  test(
    'a removed managed identity cannot resolve its previous review',
    () async {
      final result = await planner.plan(
        snapshot: RepositorySnapshot.empty(),
        review: driftReview(),
        current: driftInspection(),
        resolution: const RestoreManagedSkillDrift(),
        cancellationToken: CancellationToken.none(),
      );
      expect(result.failureOrNull!.code, DriftFailureCode.skillNotFound);
    },
  );

  test(
    'Draft inspection failure is typed and preserves safe context',
    () async {
      content.draftResult = HistoryFailure(
        code: HistoryFailureCode.invalidSkill,
        context: {'reason': 'invalidDraft'},
      );
      final result = await plan(skill: driftSkill(draft: driftDraft()));
      expect(result.failureOrNull!.code, DriftFailureCode.invalidSkill);
      expect(result.failureOrNull!.context['reason'], 'invalidDraft');
    },
  );

  test('removed activation evidence is stale before resolving drift', () async {
    final result = await plan(
      current: driftInspection(targetPath: '$driftTargetPath-moved'),
    );
    expect(result.failureOrNull!.code, DriftFailureCode.staleDriftReview);
    expect(result.failureOrNull!.context['reason'], 'artifactChanged');
  });

  test('cancelled drift planning is a typed non-mutation', () async {
    final cancellation = CancellationSource();
    await cancellation.cancel();
    final result = await planner.plan(
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision(5),
        managedSkills: [driftSkill()],
      ),
      review: driftReview(),
      current: driftInspection(),
      resolution: const RestoreManagedSkillDrift(),
      cancellationToken: cancellation.token,
    );
    expect(result.failureOrNull!.code, DriftFailureCode.operationCancelled);
  });

  test('export preflight validates the current Effective revision', () async {
    final review = driftReview();
    expect(
      (await planner.validateEffectiveRevision(review)).failureOrNull,
      isNull,
    );
    content.state = driftState(effective: driftObject('3'));
    final stale = await planner.validateEffectiveRevision(review);
    expect(stale.failureOrNull!.code, DriftFailureCode.staleDriftReview);
    expect(stale.failureOrNull!.context['reason'], 'effectiveRevisionChanged');
    content.state = null;
    expect(
      (await planner.validateEffectiveRevision(review)).failureOrNull!.code,
      DriftFailureCode.revisionStoreCorrupt,
    );
  });
}
