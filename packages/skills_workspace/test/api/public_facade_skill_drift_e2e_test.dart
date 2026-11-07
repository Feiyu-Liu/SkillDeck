import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';
import '../support/fake_skill_drift_review.dart';

void main() {
  for (final location in [
    SkillDriftLocationKind.repositoryCopy,
    SkillDriftLocationKind.copyActivation,
  ]) {
    for (final keep in [true, false]) {
      test(
        '${location.name}: ${keep ? 'keep' : 'restore'} through facade',
        () async {
          final fixture = await DriftFacadeFixture.create();
          final repository = fixture.repository;
          final baseline = await fixture.history();
          final effectiveBefore = repository.snapshot
              .findSkill(fixture.managedSkillId)!
              .currentRevision;
          final target = location == SkillDriftLocationKind.repositoryCopy
              ? fixture.repositoryCopyPath
              : fixture.activationPath();
          await fixture.changeNotes(target, _externalNotes);

          final review = await fixture.inspect();
          final artifact = review.artifacts.single;
          expect(artifact.locationKind, location);
          expect(artifact.driftKind, SkillDriftKind.contentChanged);
          expect(artifact.canKeepExternal, isTrue);
          expect(artifact.canExport, isTrue);
          expect(artifact.fileCount, 2);
          expect(artifact.byteSize, greaterThan(0));
          if (location == SkillDriftLocationKind.repositoryCopy) {
            expect(artifact.artifactId, 'repositoryCopy');
            expect(artifact.targetPath, isNull);
            expect(artifact.activationLocation, isNull);
          } else {
            expect(artifact.artifactId, matches(r'^activation:[0-9a-f]{16}$'));
            expect(artifact.targetPath, target);
            expect(artifact.activationLocation, fixture.activationRoot());
            expect(artifact.scope, ActivationScope.global);
            expect(artifact.agentIds, [DriftFacadeFixture.firstAgentId]);
          }
          expect(review.missingArtifactCount, 0);

          final result = await fixture.resolve(
            review,
            keep
                ? KeepExternalSkillDrift(artifact.artifactId)
                : const RestoreManagedSkillDrift(),
          );
          expect(result.affectedSkillIds, {fixture.managedSkillId});
          final expectedNotes = keep
              ? _externalNotes
              : DriftFacadeFixture.baseNotes;
          await fixture.expectMaterializedNotes(expectedNotes);
          await fixture.expectEffectiveNotes(expectedNotes);
          expect(
            repository.snapshot.integrity.skills
                .singleWhere(
                  (state) => state.managedSkillId == fixture.managedSkillId,
                )
                .status,
            SkillIntegrityStatus.healthy,
          );
          final history = await fixture.history();
          if (keep) {
            expect(history.revisions, hasLength(baseline.revisions.length + 1));
            expect(
              history.revisions.first.kind,
              WorkspaceOperationKind.resolveSkillDrift,
            );
            expect(
              history.revisions.first.contentHash,
              isNot(effectiveBefore.contentHash),
            );
            expect(
              history.revisions.skip(1).map((entry) => entry.reference),
              baseline.revisions.map((entry) => entry.reference),
            );
          } else {
            expect(
              history.revisions.map((entry) => entry.reference),
              baseline.revisions.map((entry) => entry.reference),
            );
            expect(
              repository.snapshot
                  .findSkill(fixture.managedSkillId)!
                  .currentRevision,
              effectiveBefore,
            );
          }
          expect((await fixture.inspect()).artifacts, isEmpty);
        },
      );
    }
  }

  test('multiple drifted locations keep only the selected authority', () async {
    final fixture = await DriftFacadeFixture.create(twoActivations: true);
    await fixture.changeNotes(
      fixture.repositoryCopyPath,
      'repository external\n',
    );
    await fixture.changeNotes(fixture.activationPath(), _externalNotes);
    await fixture.changeNotes(
      fixture.activationPath(DriftFacadeFixture.secondAgentId),
      'other activation external\n',
    );

    final review = await fixture.inspect();
    expect(review.artifacts, hasLength(3));
    final selected = review.artifacts.singleWhere(
      (artifact) => artifact.targetPath == fixture.activationPath(),
    );
    await fixture.resolve(review, KeepExternalSkillDrift(selected.artifactId));

    await fixture.expectMaterializedNotes(
      _externalNotes,
      secondActivation: true,
    );
    await fixture.expectEffectiveNotes(_externalNotes);
    expect((await fixture.inspect()).artifacts, isEmpty);
  });

  test(
    'wrong link target is restore-only and preserves the external target',
    () async {
      final fixture = await DriftFacadeFixture.create(
        mode: RequestedActivationMode.symbolicLink,
      );
      final externalDirectory = path.join(
        fixture.temporaryRoot.path,
        'external-link-target',
      );
      await Directory(externalDirectory).create();
      await fixture.writeSkillMarkdown(externalDirectory);
      await File(
        path.join(externalDirectory, 'notes.md'),
      ).writeAsString(_externalNotes);
      await Link(fixture.activationPath()).delete();
      await Link(fixture.activationPath()).create(externalDirectory);

      final review = await fixture.inspect();
      final artifact = review.artifacts.single;
      expect(
        artifact.locationKind,
        SkillDriftLocationKind.symbolicLinkActivation,
      );
      expect(artifact.driftKind, SkillDriftKind.wrongLinkTarget);
      expect(artifact.canKeepExternal, isFalse);
      expect(artifact.canExport, isFalse);
      await driftFailure(
        fixture.repository.resolveSkillDrift(
          ResolveSkillDriftRequest(
            review: review,
            resolution: KeepExternalSkillDrift(artifact.artifactId),
          ),
        ),
        SkillsErrorCode.driftResolutionUnavailable,
        reason: 'keepNotAllowed',
      );
      await driftFailure(
        fixture.repository.exportSkillDriftArtifact(
          ExportSkillDriftArtifactRequest(
            review: review,
            artifactId: artifact.artifactId,
            destinationDirectory: fixture.exportDirectory,
          ),
        ),
        SkillsErrorCode.driftResolutionUnavailable,
        reason: 'exportNotAllowed',
      );
      await fixture.resolve(review, const RestoreManagedSkillDrift());

      expect(
        path.normalize(await Link(fixture.activationPath()).target()),
        path.normalize(fixture.repositoryCopyPath),
      );
      expect(
        await File(path.join(externalDirectory, 'notes.md')).readAsString(),
        _externalNotes,
      );
      await fixture.expectMaterializedNotes(DriftFacadeFixture.baseNotes);
    },
    skip: _symbolicLinkSkip,
  );

  for (final repositoryCopy in [true, false]) {
    test(
      '${repositoryCopy ? 'repository' : 'copy activation'} wrong entry type exports file and restores directory',
      () async {
        final fixture = await DriftFacadeFixture.create();
        final target = repositoryCopy
            ? fixture.repositoryCopyPath
            : fixture.activationPath();
        await fixture.deleteArtifact(target);
        await File(target).writeAsString(_externalNotes, flush: true);

        final review = await fixture.inspect();
        final artifact = review.artifacts.single;
        expect(artifact.driftKind, SkillDriftKind.wrongEntryType);
        expect(artifact.canKeepExternal, isFalse);
        expect(artifact.canExport, isTrue);
        await driftFailure(
          fixture.repository.resolveSkillDrift(
            ResolveSkillDriftRequest(
              review: review,
              resolution: KeepExternalSkillDrift(artifact.artifactId),
            ),
          ),
          SkillsErrorCode.driftResolutionUnavailable,
          reason: 'keepNotAllowed',
        );
        final exported = await driftSuccess(
          fixture.repository.exportSkillDriftArtifact(
            ExportSkillDriftArtifactRequest(
              review: review,
              artifactId: artifact.artifactId,
              destinationDirectory: fixture.exportDirectory,
            ),
          ),
        );
        expect(
          await File(exported.exportedPath).readAsString(),
          _externalNotes,
        );
        await File(
          exported.exportedPath,
        ).writeAsString('export stays writable\n');
        await fixture.resolve(review, const RestoreManagedSkillDrift());
        expect(
          await FileSystemEntity.type(target, followLinks: false),
          FileSystemEntityType.directory,
        );
        await fixture.expectMaterializedNotes(DriftFacadeFixture.baseNotes);
      },
    );
  }

  test(
    'a directory replacing a symbolic-link Activation is restored as a link',
    () async {
      final fixture = await DriftFacadeFixture.create(
        mode: RequestedActivationMode.symbolicLink,
      );
      await Link(fixture.activationPath()).delete();
      await Directory(fixture.activationPath()).create();
      await fixture.writeSkillMarkdown(fixture.activationPath());
      await File(
        path.join(fixture.activationPath(), 'notes.md'),
      ).writeAsString(_externalNotes);

      final review = await fixture.inspect();
      final artifact = review.artifacts.single;
      expect(artifact.driftKind, SkillDriftKind.wrongEntryType);
      expect(artifact.canKeepExternal, isFalse);
      expect(artifact.canExport, isTrue);
      await fixture.resolve(review, const RestoreManagedSkillDrift());
      expect(
        await FileSystemEntity.type(
          fixture.activationPath(),
          followLinks: false,
        ),
        FileSystemEntityType.link,
      );
      await fixture.expectMaterializedNotes(DriftFacadeFixture.baseNotes);
    },
    skip: _symbolicLinkSkip,
  );

  test(
    'missing published paths still auto-repair without a drift review',
    () async {
      final fixture = await DriftFacadeFixture.create();
      await fixture.deleteArtifact(fixture.repositoryCopyPath);
      await fixture.deleteArtifact(fixture.activationPath());

      final validation = await driftSuccess(
        fixture.repository.validateWorkspace(
          ValidateWorkspaceRequest(managedSkillIds: {fixture.managedSkillId}),
        ),
      );
      expect(validation.repairedArtifactCount, 2);
      expect(validation.driftedSkillIds, isEmpty);
      await fixture.expectMaterializedNotes(DriftFacadeFixture.baseNotes);
      expect((await fixture.inspect()).artifacts, isEmpty);
    },
  );

  test('restore repairs reviewed drift plus a missing projection', () async {
    final fixture = await DriftFacadeFixture.create();
    await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);
    await fixture.deleteArtifact(fixture.activationPath());
    final review = await fixture.inspect();
    expect(review.artifacts, hasLength(1));
    expect(review.missingArtifactCount, 1);
    await fixture.resolve(review, const RestoreManagedSkillDrift());
    await fixture.expectMaterializedNotes(DriftFacadeFixture.baseNotes);
  });

  test('unsafe inspection refuses resolution and preserves bytes', () async {
    final fixture = await DriftFacadeFixture.create();
    await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);
    await Directory(path.join(fixture.repositoryCopyPath, '.git')).create();

    await driftFailure(
      fixture.repository.inspectSkillDrift(
        InspectSkillDriftRequest(managedSkillId: fixture.managedSkillId),
      ),
      SkillsErrorCode.driftResolutionUnavailable,
      reason: 'unsafeInspection',
    );
    expect(
      await File(
        path.join(fixture.repositoryCopyPath, 'notes.md'),
      ).readAsString(),
      _externalNotes,
    );
    await fixture.expectEffectiveNotes(DriftFacadeFixture.baseNotes);
  });

  test('changed reviewed bytes stale both export and resolution', () async {
    final fixture = await DriftFacadeFixture.create();
    await fixture.changeNotes(fixture.activationPath(), _externalNotes);
    final review = await fixture.inspect();
    final artifactId = review.artifacts.single.artifactId;
    await fixture.changeNotes(
      fixture.activationPath(),
      'changed after review\n',
    );

    await driftFailure(
      fixture.repository.exportSkillDriftArtifact(
        ExportSkillDriftArtifactRequest(
          review: review,
          artifactId: artifactId,
          destinationDirectory: fixture.exportDirectory,
        ),
      ),
      SkillsErrorCode.staleDriftReview,
      reason: 'artifactChanged',
    );
    for (final resolution in <SkillDriftResolution>[
      KeepExternalSkillDrift(artifactId),
      const RestoreManagedSkillDrift(),
    ]) {
      await driftFailure(
        fixture.repository.resolveSkillDrift(
          ResolveSkillDriftRequest(review: review, resolution: resolution),
        ),
        SkillsErrorCode.staleDriftReview,
        reason: 'artifactChanged',
      );
    }
    expect(await Directory(fixture.exportDirectory).list().length, 0);
    expect(
      await File(
        path.join(fixture.activationPath(), 'notes.md'),
      ).readAsString(),
      'changed after review\n',
    );
  });

  test('changed Effective Revision invalidates an earlier review', () async {
    final fixture = await DriftFacadeFixture.create();
    await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);
    final review = await fixture.inspect();
    await fixture.resolve(
      review,
      KeepExternalSkillDrift(review.artifacts.single.artifactId),
    );

    await driftFailure(
      fixture.repository.resolveSkillDrift(
        ResolveSkillDriftRequest(
          review: review,
          resolution: const RestoreManagedSkillDrift(),
        ),
      ),
      SkillsErrorCode.staleDriftReview,
      reason: 'effectiveRevisionChanged',
    );
    await fixture.expectEffectiveNotes(_externalNotes);
  });

  test('foreign review and unknown artifact cannot authorize writes', () async {
    final fixture = await DriftFacadeFixture.create();
    await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);
    final review = await fixture.inspect();
    final foreign = FakeSkillDriftReview(
      managedSkillId: review.managedSkillId,
      effectiveContentHash: review.effectiveContentHash,
      artifacts: review.artifacts,
    );
    await driftFailure(
      fixture.repository.resolveSkillDrift(
        ResolveSkillDriftRequest(
          review: foreign,
          resolution: const RestoreManagedSkillDrift(),
        ),
      ),
      SkillsErrorCode.staleDriftReview,
      reason: 'foreignReview',
    );
    await driftFailure(
      fixture.repository.exportSkillDriftArtifact(
        ExportSkillDriftArtifactRequest(
          review: foreign,
          artifactId: 'repositoryCopy',
          destinationDirectory: fixture.exportDirectory,
        ),
      ),
      SkillsErrorCode.staleDriftReview,
      reason: 'foreignReview',
    );
    await driftFailure(
      fixture.repository.resolveSkillDrift(
        ResolveSkillDriftRequest(
          review: review,
          resolution: const KeepExternalSkillDrift('unknown'),
        ),
      ),
      SkillsErrorCode.staleDriftReview,
      reason: 'artifactNotFound',
    );
    await driftFailure(
      fixture.repository.exportSkillDriftArtifact(
        ExportSkillDriftArtifactRequest(
          review: review,
          artifactId: 'unknown',
          destinationDirectory: fixture.exportDirectory,
        ),
      ),
      SkillsErrorCode.staleDriftReview,
      reason: 'artifactNotFound',
    );
    await fixture.expectEffectiveNotes(DriftFacadeFixture.baseNotes);
  });

  for (final keep in [true, false]) {
    test(
      'a new drift at an unreviewed location prevents ${keep ? 'keep' : 'restore'} from overwriting it',
      () async {
        final fixture = await DriftFacadeFixture.create();
        await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);
        final review = await fixture.inspect();
        await fixture.changeNotes(
          fixture.activationPath(),
          'unreviewed external bytes\n',
        );

        await driftFailure(
          fixture.repository.resolveSkillDrift(
            ResolveSkillDriftRequest(
              review: review,
              resolution: keep
                  ? const KeepExternalSkillDrift('repositoryCopy')
                  : const RestoreManagedSkillDrift(),
            ),
          ),
          SkillsErrorCode.staleDriftReview,
          reason: 'artifactChanged',
        );
        expect(
          await File(
            path.join(fixture.repositoryCopyPath, 'notes.md'),
          ).readAsString(),
          _externalNotes,
        );
        expect(
          await File(
            path.join(fixture.activationPath(), 'notes.md'),
          ).readAsString(),
          'unreviewed external bytes\n',
        );
        await fixture.expectEffectiveNotes(DriftFacadeFixture.baseNotes);
        expect((await fixture.history()).revisions, hasLength(1));
      },
    );
  }

  test(
    'unchanged restore does not journal or advance the Repository Revision',
    () async {
      final fixture = await DriftFacadeFixture.create();
      final review = await fixture.inspect();
      final revision = fixture.repository.snapshot.revision;
      final history = (await fixture.history()).revisions.length;
      final result = await fixture.resolve(
        review,
        const RestoreManagedSkillDrift(),
      );
      expect(result.snapshot.revision, revision);
      expect((await fixture.history()).revisions.length, history);
      final outcome = await fixture.repository
          .resolveSkillDrift(
            ResolveSkillDriftRequest(
              review: review,
              resolution: const RestoreManagedSkillDrift(),
            ),
          )
          .completed;
      expect((outcome as SkillsSuccess<MutationReport>).changed, isFalse);
    },
  );

  test(
    'oversized wrong-type file stays driftPending and can be restored only',
    () async {
      final fixture = await DriftFacadeFixture.create();
      await fixture.deleteArtifact(fixture.repositoryCopyPath);
      final file = await File(
        fixture.repositoryCopyPath,
      ).open(mode: FileMode.write);
      await file.truncate(50 * 1024 * 1024 + 1);
      await file.close();
      await driftSuccess(
        fixture.repository.validateWorkspace(const ValidateWorkspaceRequest()),
      );
      expect(
        fixture.repository.snapshot.integrity.skills
            .singleWhere((s) => s.managedSkillId == fixture.managedSkillId)
            .status,
        SkillIntegrityStatus.driftPending,
      );
      final review = await fixture.inspect();
      final artifact = review.artifacts.single;
      expect(artifact.driftKind, SkillDriftKind.wrongEntryType);
      expect(artifact.canKeepExternal, isFalse);
      expect(artifact.canExport, isFalse);
      await driftFailure(
        fixture.repository.exportSkillDriftArtifact(
          ExportSkillDriftArtifactRequest(
            review: review,
            artifactId: artifact.artifactId,
            destinationDirectory: fixture.exportDirectory,
          ),
        ),
        SkillsErrorCode.driftResolutionUnavailable,
        reason: 'exportNotAllowed',
      );
      await fixture.resolve(review, const RestoreManagedSkillDrift());
      expect(
        await FileSystemEntity.type(
          fixture.repositoryCopyPath,
          followLinks: false,
        ),
        FileSystemEntityType.directory,
      );
      expect(
        fixture.repository.snapshot.integrity.skills
            .singleWhere((s) => s.managedSkillId == fixture.managedSkillId)
            .status,
        SkillIntegrityStatus.healthy,
      );
      await fixture.expectMaterializedNotes(DriftFacadeFixture.baseNotes);
      expect((await fixture.history()).revisions, hasLength(1));
    },
  );

  test('wrong-type Git directory replacing a link is restore-only', () async {
    final fixture = await DriftFacadeFixture.create(
      mode: RequestedActivationMode.symbolicLink,
    );
    final target = fixture.activationPath();
    await fixture.deleteArtifact(target);
    await Directory(path.join(target, '.git')).create(recursive: true);
    await File(path.join(target, '.git', 'config')).writeAsString('fixture');
    await driftSuccess(
      fixture.repository.validateWorkspace(const ValidateWorkspaceRequest()),
    );
    expect(
      fixture.repository.snapshot.integrity.skills
          .singleWhere((s) => s.managedSkillId == fixture.managedSkillId)
          .status,
      SkillIntegrityStatus.driftPending,
    );
    final review = await fixture.inspect();
    expect(review.artifacts.single.canKeepExternal, isFalse);
    expect(review.artifacts.single.canExport, isFalse);
    await fixture.resolve(review, const RestoreManagedSkillDrift());
    expect(
      await FileSystemEntity.type(target, followLinks: false),
      FileSystemEntityType.link,
    );
    expect((await fixture.history()).revisions, hasLength(1));
  });

  test('directory containing internal links reports canExport false', () async {
    final fixture = await DriftFacadeFixture.create();
    await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);
    await Link(
      path.join(fixture.repositoryCopyPath, 'notes-link.md'),
    ).create('notes.md');
    final review = await fixture.inspect();
    expect(review.artifacts.single.canExport, isFalse);
    await driftFailure(
      fixture.repository.exportSkillDriftArtifact(
        ExportSkillDriftArtifactRequest(
          review: review,
          artifactId: 'repositoryCopy',
          destinationDirectory: fixture.exportDirectory,
        ),
      ),
      SkillsErrorCode.driftResolutionUnavailable,
      reason: 'exportNotAllowed',
    );
  });

  test(
    'same-content Effective Revision replacement also stales export',
    () async {
      final fixture = await DriftFacadeFixture.create();
      final installedRevision =
          (await fixture.history()).revisions.single.reference;
      await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);
      final review = await fixture.inspect();
      await fixture.resolve(
        review,
        const KeepExternalSkillDrift('repositoryCopy'),
      );
      await driftSuccess(
        fixture.repository.restorePublish(
          RestorePublishRequest(
            managedSkillId: fixture.managedSkillId,
            selectedRevision: installedRevision,
          ),
        ),
      );
      expect(
        fixture.repository.snapshot
            .findSkill(fixture.managedSkillId)!
            .currentRevision
            .contentHash,
        review.effectiveContentHash,
      );
      await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);

      await driftFailure(
        fixture.repository.exportSkillDriftArtifact(
          ExportSkillDriftArtifactRequest(
            review: review,
            artifactId: 'repositoryCopy',
            destinationDirectory: fixture.exportDirectory,
          ),
        ),
        SkillsErrorCode.staleDriftReview,
        reason: 'effectiveRevisionChanged',
      );
      expect(await Directory(fixture.exportDirectory).list().length, 0);
    },
  );

  test('keeping an external declared-name change is rejected', () async {
    final fixture = await DriftFacadeFixture.create();
    await fixture.makeWritable(fixture.repositoryCopyPath);
    await fixture.writeSkillMarkdown(
      fixture.repositoryCopyPath,
      name: 'renamed-skill',
    );
    final review = await fixture.inspect();

    await driftFailure(
      fixture.repository.resolveSkillDrift(
        ResolveSkillDriftRequest(
          review: review,
          resolution: const KeepExternalSkillDrift('repositoryCopy'),
        ),
      ),
      SkillsErrorCode.declaredNameChangeNotAllowed,
    );
    expect(
      fixture.repository.snapshot
          .findSkill(fixture.managedSkillId)!
          .declaredName,
      DriftFacadeFixture.skillName,
    );
    expect((await fixture.history()).revisions, hasLength(1));
  });

  for (final fileLimit in [true, false]) {
    test(
      '${fileLimit ? 'file-count' : 'byte-size'} limit crossed after review fails closed',
      () async {
        final fixture = await DriftFacadeFixture.create();
        await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);
        final review = await fixture.inspect();
        if (fileLimit) {
          for (var index = 0; index < 1000; index++) {
            await File(
              path.join(fixture.repositoryCopyPath, 'extra-$index'),
            ).writeAsString('x');
          }
        } else {
          final file = await File(
            path.join(fixture.repositoryCopyPath, 'large.bin'),
          ).open(mode: FileMode.write);
          await file.truncate(50 * 1024 * 1024 + 1);
          await file.close();
        }
        final result = await fixture.repository
            .resolveSkillDrift(
              ResolveSkillDriftRequest(
                review: review,
                resolution: const KeepExternalSkillDrift('repositoryCopy'),
              ),
            )
            .completed;
        expect(result, isA<SkillsFailure<MutationReport>>());
        expect(
          result.failureOrNull!.code,
          SkillsErrorCode.driftResolutionUnavailable,
        );
        expect(result.failureOrNull!.context['reason'], 'unsafeInspection');
        await fixture.expectEffectiveNotes(DriftFacadeFixture.baseNotes);
        expect((await fixture.history()).revisions, hasLength(1));
        expect(
          await File(
            path.join(fixture.repositoryCopyPath, 'notes.md'),
          ).readAsString(),
          _externalNotes,
        );
      },
    );
  }

  test(
    'dirty Draft blocks keep while restore leaves the Draft untouched',
    () async {
      final fixture = await DriftFacadeFixture.create();
      final draft = await driftSuccess(
        fixture.repository.ensureDraft(
          EnsureDraftRequest(managedSkillId: fixture.managedSkillId),
        ),
      );
      await fixture.changeNotes(draft.path, 'unpublished Draft\n');
      await fixture.changeNotes(fixture.repositoryCopyPath, _externalNotes);
      final review = await fixture.inspect();

      await driftFailure(
        fixture.repository.resolveSkillDrift(
          ResolveSkillDriftRequest(
            review: review,
            resolution: const KeepExternalSkillDrift('repositoryCopy'),
          ),
        ),
        SkillsErrorCode.dirtyDraftResolutionRequired,
      );
      await fixture.resolve(review, const RestoreManagedSkillDrift());
      expect(
        await File(path.join(draft.path, 'notes.md')).readAsString(),
        'unpublished Draft\n',
      );
      expect(
        fixture.repository.snapshot.findSkill(fixture.managedSkillId)!.draft,
        isNotNull,
      );
      await fixture.expectEffectiveNotes(DriftFacadeFixture.baseNotes);
    },
  );

  test(
    'clean Draft follows the existing Publish cleanup path when keeping',
    () async {
      final fixture = await DriftFacadeFixture.create();
      final draft = await driftSuccess(
        fixture.repository.ensureDraft(
          EnsureDraftRequest(managedSkillId: fixture.managedSkillId),
        ),
      );
      await fixture.changeNotes(fixture.activationPath(), _externalNotes);
      final review = await fixture.inspect();
      await fixture.resolve(
        review,
        KeepExternalSkillDrift(review.artifacts.single.artifactId),
      );

      expect(
        fixture.repository.snapshot.findSkill(fixture.managedSkillId)!.draft,
        isNull,
      );
      expect(await Directory(draft.path).exists(), isFalse);
      await fixture.expectEffectiveNotes(_externalNotes);
    },
  );

  test(
    'pending Update Candidate blocks keep while restore preserves candidate',
    () async {
      final fixture = await DriftFacadeFixture.create();
      final repository = fixture.repository;
      final draft = await driftSuccess(
        repository.ensureDraft(
          EnsureDraftRequest(managedSkillId: fixture.managedSkillId),
        ),
      );
      await fixture.changeNotes(draft.path, 'local customization\n');
      await driftSuccess(
        repository.publishDraft(
          PublishDraftRequest(managedSkillId: fixture.managedSkillId),
        ),
      );
      await fixture.changeNotes(fixture.sourcePath, 'incoming upstream\n');
      await driftSuccess(
        repository.update(
          UpdateRequest(managedSkillIds: {fixture.managedSkillId}),
        ),
      );
      final candidate = repository.snapshot
          .findSkill(fixture.managedSkillId)!
          .updateCandidate;
      expect(candidate, isNotNull);
      await fixture.changeNotes(fixture.activationPath(), _externalNotes);
      final review = await fixture.inspect();

      await driftFailure(
        repository.resolveSkillDrift(
          ResolveSkillDriftRequest(
            review: review,
            resolution: KeepExternalSkillDrift(
              review.artifacts.single.artifactId,
            ),
          ),
        ),
        SkillsErrorCode.updateCandidateResolutionRequired,
      );
      await fixture.resolve(review, const RestoreManagedSkillDrift());
      expect(
        repository.snapshot.findSkill(fixture.managedSkillId)!.updateCandidate,
        candidate,
      );
      await fixture.expectEffectiveNotes('local customization\n');
    },
  );

  test(
    'drift commands bypass integrity gating and export writable copies',
    () async {
      final fixture = await DriftFacadeFixture.create();
      final repository = fixture.repository;
      await fixture.changeNotes(fixture.activationPath(), _externalNotes);
      await driftSuccess(
        repository.validateWorkspace(
          ValidateWorkspaceRequest(managedSkillIds: {fixture.managedSkillId}),
        ),
      );
      expect(
        repository.snapshot.integrity.skills
            .singleWhere(
              (state) => state.managedSkillId == fixture.managedSkillId,
            )
            .status,
        SkillIntegrityStatus.driftPending,
      );
      await driftFailure(
        repository.ensureDraft(
          EnsureDraftRequest(managedSkillId: fixture.managedSkillId),
        ),
        SkillsErrorCode.revisionStoreCorrupt,
      );
      final review = await fixture.inspect();
      final artifact = review.artifacts.single;
      for (final destination in [
        fixture.workspacePath,
        fixture.repositoryCopyPath,
        fixture.activationRoot(),
        fixture.activationPath(),
      ]) {
        await driftFailure(
          repository.exportSkillDriftArtifact(
            ExportSkillDriftArtifactRequest(
              review: review,
              artifactId: artifact.artifactId,
              destinationDirectory: destination,
            ),
          ),
          SkillsErrorCode.driftResolutionUnavailable,
          reason: 'exportNotAllowed',
        );
      }
      final first = await driftSuccess(
        repository.exportSkillDriftArtifact(
          ExportSkillDriftArtifactRequest(
            review: review,
            artifactId: artifact.artifactId,
            destinationDirectory: fixture.exportDirectory,
          ),
        ),
      );
      final second = await driftSuccess(
        repository.exportSkillDriftArtifact(
          ExportSkillDriftArtifactRequest(
            review: review,
            artifactId: artifact.artifactId,
            destinationDirectory: fixture.exportDirectory,
          ),
        ),
      );
      expect(
        path.basename(first.exportedPath),
        matches(r'^drift-skill-external-\d{14}$'),
      );
      expect(second.exportedPath, isNot(first.exportedPath));
      expect(
        await File(path.join(first.exportedPath, 'notes.md')).readAsString(),
        _externalNotes,
      );
      await File(
        path.join(first.exportedPath, 'notes.md'),
      ).writeAsString('editable export\n');
      expect(
        await File(
          path.join(fixture.activationPath(), 'notes.md'),
        ).readAsString(),
        _externalNotes,
      );
      expect(await Directory(fixture.exportDirectory).list().length, 2);
      await fixture.resolve(review, const RestoreManagedSkillDrift());
      expect(
        repository.snapshot.integrity.skills
            .singleWhere(
              (state) => state.managedSkillId == fixture.managedSkillId,
            )
            .status,
        SkillIntegrityStatus.healthy,
      );
      expect(
        await File(path.join(first.exportedPath, 'notes.md')).readAsString(),
        'editable export\n',
      );
    },
  );
}

const _externalNotes = 'reviewed external notes\n';
final _symbolicLinkSkip = Platform.isWindows
    ? 'Creating symbolic links is not guaranteed on Windows CI.'
    : false;
