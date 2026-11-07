import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

import '../support/fake_skill_drift_review.dart';

void main() {
  final firstId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
  final secondId = ManagedSkillId('123e4567-e89b-42d3-b456-426614174001');

  test('managed operations accept ManagedSkillId instead of Slot Keys', () {
    final ids = <ManagedSkillId>{firstId, secondId};
    final update = UpdateRequest(managedSkillIds: ids);
    final activate = ActivateRequest(
      managedSkillIds: ids,
      selection: ActivationSelection.explicit([
        ActivationTarget(agentId: 'claude', scope: ActivationScope.global),
      ]),
    );
    final remove = RemoveRequest(
      managedSkillIds: ids,
      intent: DestructiveIntent(reviewedRevision: RepositoryRevision(4)),
    );
    ids.clear();

    expect(update.managedSkillIds, {firstId, secondId});
    expect(activate.managedSkillIds, {firstId, secondId});
    expect(remove.managedSkillIds, {firstId, secondId});
    expect(() => update.managedSkillIds.clear(), throwsUnsupportedError);
  });

  test('source operations stay source-agnostic', () {
    final sources = <SourceDescriptor>[
      LocalSourceDescriptor(locator: '/tmp/skills'),
      GitSourceDescriptor(locator: 'https://example.com/repo.git'),
      WellKnownSourceDescriptor(locator: 'https://example.com/skills.json'),
    ];

    for (final source in sources) {
      expect(InspectSourceRequest(source: source).source, same(source));
      expect(InstallRequest(source: source).source, same(source));
    }
    expect(
      ReplaceSourceRequest(
        managedSkillId: firstId,
        source: sources.last,
        intent: DestructiveIntent(reviewedRevision: RepositoryRevision(8)),
      ).managedSkillId,
      firstId,
    );
  });

  test('draft, library, and history requests retain explicit typed fields', () {
    final operationId = OperationId('123e4567-e89b-42d3-8456-426614174002');
    final reference = OperationSubjectReference(
      operationId: operationId,
      subjectId: '123e4567-e89b-42d3-9456-426614174003',
    );

    expect(EnsureDraftRequest(managedSkillId: firstId).managedSkillId, firstId);
    expect(
      SetFavoriteRequest(managedSkillId: firstId, isFavorite: true).isFavorite,
      isTrue,
    );
    expect(SaveNoteRequest(managedSkillId: firstId, text: 'note').text, 'note');
    expect(
      AssignPersonalTagRequest(managedSkillId: firstId, tagId: 'work').tagId,
      'work',
    );
    expect(
      InspectDiffRequest(managedSkillId: firstId, to: reference).to,
      reference,
    );
    expect(
      RestorePublishRequest(
        managedSkillId: firstId,
        selectedRevision: reference,
      ).selectedRevision,
      reference,
    );
  });

  test(
    'effective revision content queries expose only manifest metadata and bytes',
    () {
      final list = ListEffectiveFilesRequest(managedSkillId: firstId);
      final read = ReadEffectiveFileRequest(
        managedSkillId: firstId,
        expectedContentHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        relativePath: 'docs/guide.md',
      );
      final manifest = EffectiveSkillFileManifest(
        managedSkillId: firstId,
        contentHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        files: <EffectiveSkillFileEntry>[
          const EffectiveSkillFileEntry(
            relativePath: 'docs/guide.md',
            byteSize: 12,
            isExecutable: false,
          ),
        ],
      );

      expect(list.managedSkillId, firstId);
      expect(read.relativePath, 'docs/guide.md');
      expect(manifest.files.single.byteSize, 12);
      expect(manifest.files.single.isExecutable, isFalse);
    },
  );

  test('external adoption selection freezes every reviewed location hash', () {
    const firstLocation = '/agents/a/skills/review';
    const secondLocation = '/agents/b/skills/review';
    final candidate = ExternalSkillCandidate(
      slotKey: 'review',
      declaredName: 'review',
      description: 'Review Skill',
      contentHash: 'a' * 64,
      locations: const <String>[firstLocation, secondLocation],
      agentIds: const <String>['a', 'b'],
    );
    final conflict = ExternalSkillConflict(
      slotKey: 'review',
      contentHashByLocation: <String, String>{
        firstLocation: 'a' * 64,
        secondLocation: 'b' * 64,
      },
    );

    final fromCandidate = ExternalAdoptionSelection.fromCandidate(
      candidate,
      firstLocation,
    );
    final fromConflict = ExternalAdoptionSelection.fromConflict(
      conflict,
      secondLocation,
    );

    expect(fromCandidate.slotKey, 'review');
    expect(fromCandidate.authoritativeLocation, firstLocation);
    expect(fromCandidate.reviewedContentHashByLocation, <String, String>{
      firstLocation: 'a' * 64,
      secondLocation: 'a' * 64,
    });
    expect(fromConflict.authoritativeLocation, secondLocation);
    expect(
      fromConflict.reviewedContentHashByLocation,
      conflict.contentHashByLocation,
    );
    expect(
      () => fromConflict.reviewedContentHashByLocation.clear(),
      throwsUnsupportedError,
    );
  });

  test('external adoption selection rejects an unreviewed authority', () {
    final conflict = ExternalSkillConflict(
      slotKey: 'review',
      contentHashByLocation: <String, String>{
        '/agents/a/skills/review': 'a' * 64,
      },
    );

    expect(
      () => ExternalAdoptionSelection.fromConflict(
        conflict,
        '/agents/b/skills/review',
      ),
      throwsArgumentError,
    );
  });

  test('Update conflicts expose typed resolution state', () {
    final conflict = UpdateConflict(
      path: 'SKILL.md',
      kind: ConflictKind.text,
      resolutionState: UpdateConflictResolutionState.resolved,
    );

    expect(conflict.resolutionState, UpdateConflictResolutionState.resolved);

    final request = ResolveUpdateConflictRequest(
      managedSkillId: firstId,
      path: 'SKILL.md',
      resolutionState: UpdateConflictResolutionState.resolved,
    );
    expect(request.managedSkillId, firstId);
    expect(request.path, 'SKILL.md');
    expect(
      () => ResolveUpdateConflictRequest(
        managedSkillId: firstId,
        path: '../SKILL.md',
        resolutionState: UpdateConflictResolutionState.resolved,
      ),
      throwsArgumentError,
    );
  });

  test('takeover confirmation accepts only an opaque draft handle', () {
    final draft = _PublicDraft(
      reviewedRevision: RepositoryRevision(3),
      targets: <OccupiedActivationTarget>[
        OccupiedActivationTarget(
          managedSkillId: firstId,
          location: '/agents/skills',
          targetPath: '/agents/skills/example',
          agentIds: const <String>['agent'],
          kind: ActivationTargetOccupancyKind.skillDirectory,
          contentRelation: ActivationContentRelation.differsFromCurrentRevision,
        ),
      ],
    );

    final request = ConfirmActivationTakeoverRequest(draft: draft);

    expect(request.draft, same(draft));
    expect(request.draft.reviewedRevision, RepositoryRevision(3));
    expect(request.draft.targets.single.managedSkillId, firstId);
  });

  test('public facade is an implementation-free abstract contract', () {
    expect(SkillsRepository, isA<Type>());
    expect(SkillsOperation<RepositorySnapshot>, isA<Type>());
  });

  test('drift review requests retain an opaque public handle', () {
    final review = FakeSkillDriftReview(
      managedSkillId: firstId,
      effectiveContentHash: 'a' * 64,
      artifacts: [
        SkillDriftArtifact(
          artifactId: 'repositoryCopy',
          locationKind: SkillDriftLocationKind.repositoryCopy,
          driftKind: SkillDriftKind.contentChanged,
          fileCount: 2,
          byteSize: 40,
          canKeepExternal: true,
          canExport: true,
        ),
      ],
      missingArtifactCount: 1,
    );
    final inspect = InspectSkillDriftRequest(managedSkillId: firstId);
    final export = ExportSkillDriftArtifactRequest(
      review: review,
      artifactId: 'repositoryCopy',
      destinationDirectory: '/exports',
    );
    final keep = ResolveSkillDriftRequest(
      review: review,
      resolution: const KeepExternalSkillDrift('repositoryCopy'),
    );
    final restore = ResolveSkillDriftRequest(
      review: review,
      resolution: const RestoreManagedSkillDrift(),
    );

    expect(inspect.managedSkillId, firstId);
    expect(export.review, same(review));
    expect(export.artifactId, 'repositoryCopy');
    expect(export.destinationDirectory, '/exports');
    expect(keep.review, same(review));
    expect(
      (keep.resolution as KeepExternalSkillDrift).artifactId,
      'repositoryCopy',
    );
    expect(restore.review, same(review));
    expect(restore.resolution, isA<RestoreManagedSkillDrift>());
    expect(review.managedSkillId, firstId);
    expect(review.effectiveContentHash, 'a' * 64);
    expect(review.missingArtifactCount, 1);
    expect(review.artifacts.single.targetPath, isNull);
    expect(review.artifacts.single.activationLocation, isNull);
    expect(review.artifacts.single.scope, isNull);
    expect(review.artifacts.single.fileCount, 2);
    expect(review.artifacts.single.byteSize, 40);
    expect(() => review.artifacts.clear(), throwsUnsupportedError);
    expect(
      const SkillDriftExport(exportedPath: '/exports/review').exportedPath,
      '/exports/review',
    );
  });

  test('drift artifacts freeze Agent IDs and expose activation context', () {
    final agentIds = ['claude', 'codex'];
    final artifact = SkillDriftArtifact(
      artifactId: 'activation:0123456789abcdef',
      locationKind: SkillDriftLocationKind.copyActivation,
      driftKind: SkillDriftKind.wrongEntryType,
      targetPath: '/project/skills/review',
      activationLocation: '/project/skills',
      scope: ActivationScope.project,
      projectRootId: 'project',
      agentIds: agentIds,
      canKeepExternal: false,
      canExport: true,
    );
    agentIds.clear();

    expect(artifact.agentIds, ['claude', 'codex']);
    expect(() => artifact.agentIds.clear(), throwsUnsupportedError);
    expect(artifact.targetPath, '/project/skills/review');
    expect(artifact.activationLocation, '/project/skills');
    expect(artifact.scope, ActivationScope.project);
    expect(artifact.projectRootId, 'project');
    expect(artifact.canKeepExternal, isFalse);
    expect(artifact.canExport, isTrue);
    expect(artifact.fileCount, isNull);
    expect(artifact.byteSize, isNull);
  });

  test('drift operation and error names form stable public contracts', () {
    expect(WorkspaceOperationKind.inspectSkillDrift.name, 'inspectSkillDrift');
    expect(
      WorkspaceOperationKind.exportSkillDriftArtifact.name,
      'exportSkillDriftArtifact',
    );
    expect(WorkspaceOperationKind.resolveSkillDrift.name, 'resolveSkillDrift');
    expect(SkillsErrorCode.staleDriftReview.name, 'staleDriftReview');
    expect(
      SkillsErrorCode.driftResolutionUnavailable.name,
      'driftResolutionUnavailable',
    );
    expect(SkillDriftLocationKind.values, hasLength(3));
    expect(SkillDriftKind.values, hasLength(3));
  });
}

final class _PublicDraft implements ActivationTakeoverDraft {
  _PublicDraft({
    required this.reviewedRevision,
    required List<OccupiedActivationTarget> targets,
  }) : targets = List.unmodifiable(targets);

  @override
  final RepositoryRevision reviewedRevision;

  @override
  final List<OccupiedActivationTarget> targets;
}
