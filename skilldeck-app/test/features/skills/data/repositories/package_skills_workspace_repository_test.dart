// Opening a real Workspace (native libgit2 and SQLite) on a cold self-hosted
// Windows runner can exceed the default 30 seconds (#52).
@OnPlatform({'windows': Timeout(Duration(minutes: 2))})
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/data/repositories/package_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_workspace/skills_workspace.dart' as workspace;
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fake_skill_drift_reviews.dart';

void main() {
  test(
    'maps stable managed identity and reads Effective Markdown without paths',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'skills-manager-package-adapter-',
      );
      addTearDown(() async {
        if (await temporary.exists()) {
          await _makeWritable(temporary.path);
          await temporary.delete(recursive: true);
        }
      });
      final sourceRoot = Directory(p.join(temporary.path, 'source'));
      final skillRoot = Directory(p.join(sourceRoot.path, 'adapter-skill'));
      await skillRoot.create(recursive: true);
      await File(p.join(skillRoot.path, 'SKILL.md')).writeAsString('''
---
name: adapter-skill
description: Package adapter fixture
---
# Adapter Skill
''');
      await File(p.join(skillRoot.path, 'guide.md')).writeAsString('# Guide\n');
      await File(p.join(skillRoot.path, 'ignored.txt')).writeAsString('ignore');

      final repository = PackageSkillsWorkspaceRepository.create(
        configuration: workspace.SkillsRepositoryConfiguration(
          rootPath: p.join(temporary.path, 'workspace'),
        ),
      );
      addTearDown(repository.close);

      final opened = await _expectCompletion(repository.open());
      expect(opened.skills, isEmpty);

      final install = repository.install(
        WorkspaceInstallRequest(
          source: SkillSourceInput(
            kind: WorkspaceSourceKind.local,
            locator: sourceRoot.path,
          ),
          scope: WorkspaceScope.global,
          storeOnly: true,
        ),
      );
      final installed = (await _expectCompleted(
        install,
      ) as WorkspaceInstallCompleted).receipt;

      expect(installed.affectedSkillIds, hasLength(1));
      final skill = installed.snapshot.skills.single;
      expect(skill.id.value, isNot(startsWith('legacy:')));
      expect(skill.slotKey, 'adapter-skill');
      expect(skill.isFavorite, isFalse);
      expect(skill.personalTagIds, isEmpty);

      final documents = await _expectCompletion(
        repository.listSkillDocuments(skill.id),
      );
      expect(documents.map((document) => document.relativePath), [
        'SKILL.md',
        'guide.md',
      ]);
      expect(
        documents.map((document) => document.contentHash),
        everyElement(skill.currentRevision.contentHash),
      );
      expect(
        await _expectCompletion(
          repository.readSkillDocument(
            skill.id,
            'guide.md',
            expectedContentHash: documents.last.contentHash,
          ),
        ),
        '# Guide\n',
      );

      final refreshed = await _expectCompletion(repository.refresh());
      expect(refreshed.findSkillById(skill.id)?.slotKey, 'adapter-skill');
      expect(await _expectCompletion(repository.open()), same(refreshed));
    },
  );

  test('binds a document read to the hash from its listed manifest', () async {
    const manifestHash =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final managedSkillId = workspace.ManagedSkillId(_managedSkillId);
    final backend =
        _ControlledSkillsRepository(
            _repositorySnapshot(
              revision: 1,
              managedSkillId: managedSkillId,
              slotKey: 'reviewer',
            ),
          )
          ..listEffectiveFilesOperation = _operation(
            workspace.SkillsSuccess(
              value: workspace.EffectiveSkillFileManifest(
                managedSkillId: managedSkillId,
                contentHash: manifestHash,
                files: const [
                  workspace.EffectiveSkillFileEntry(
                    relativePath: 'SKILL.md',
                    byteSize: 1,
                    isExecutable: false,
                  ),
                ],
              ),
            ),
          )
          ..readEffectiveFileOperation = _operation(
            workspace.SkillsFailure<workspace.EffectiveSkillFileContent>(
              code: workspace.SkillsErrorCode.effectiveFileNotFound,
            ),
          );
    final repository = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(() async {
      await repository.close();
      await backend.dispose();
    });
    await _expectCompletion(repository.open());

    final document = (await _expectCompletion(
      repository.listSkillDocuments(WorkspaceSkillId(_managedSkillId)),
    )).single;
    expect(document.contentHash, manifestHash);

    await repository.readSkillDocument(
      WorkspaceSkillId(_managedSkillId),
      document.relativePath,
      expectedContentHash: document.contentHash,
    );

    expect(
      backend.readEffectiveFileRequests.single.expectedContentHash,
      manifestHash,
    );
  });

  test('projects Workspace Library, integrity, Draft, Update Candidate, and activation metadata', () async {
    final managedSkillId = workspace.ManagedSkillId(_managedSkillId);
    final backend = _ControlledSkillsRepository(
      _repositorySnapshot(
        revision: 4,
        managedSkillId: managedSkillId,
        slotKey: 'reviewer',
        source: workspace.GitSourceDescriptor(
          locator: 'https://github.com/example/reviewer.git',
          ref: 'main',
          repositorySubpath: 'skills',
          skillPath: 'reviewer',
        ),
        activations: [
          workspace.SkillActivation(
            location: '/agents/claude/skills',
            scope: workspace.ActivationScope.global,
            mode: workspace.ActivationMode.symbolicLink,
            agentIds: const ['claude-code'],
          ),
        ],
        favorite: const workspace.SkillFavorite(isFavorite: true),
        note: workspace.SkillNote(
          text: 'Keep this for release reviews.',
          updatedAt: _timestamp,
        ),
        personalTagIds: const ['quality'],
        draft: workspace.DraftSummary(
          purpose: workspace.DraftPurpose.customization,
          path: '/workspace/drafts/reviewer',
          isDirty: true,
          updatedAt: _timestamp,
        ),
        updateCandidate: workspace.UpdateCandidateSummary(
          status: workspace.UpdateCandidateStatus.conflicted,
          conflicts: [
            workspace.UpdateConflict(
              path: 'SKILL.md',
              kind: workspace.ConflictKind.text,
              resolutionState:
                  workspace.UpdateConflictResolutionState.unresolved,
            ),
          ],
          createdAt: _timestamp,
        ),
        integrity: workspace.WorkspaceIntegrity(
          status: workspace.WorkspaceIntegrityStatus.recovered,
          skills: [
            workspace.ManagedSkillIntegrity(
              managedSkillId: managedSkillId,
              status: workspace.SkillIntegrityStatus.revisionStoreCorrupt,
            ),
          ],
        ),
        personalTags: [
          workspace.PersonalTag(
            id: 'quality',
            name: 'Quality',
            color: '#3366CC',
            createdAt: _timestamp,
            updatedAt: _timestamp,
          ),
        ],
      ),
    );
    final repository = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(() async {
      await repository.close();
      await backend.dispose();
    });

    final snapshot = await _expectCompletion(repository.open());
    final skill = snapshot.skills.single;

    expect(snapshot.integrity, WorkspaceIntegrityStatus.recovered);
    expect(snapshot.personalTags.single.name, 'Quality');
    expect(snapshot.personalTags.single.color, '#3366CC');
    expect(skill.id.value, _managedSkillId);
    expect(skill.source.kind, WorkspaceSourceKind.git);
    expect(skill.source.locator, 'https://github.com/example/reviewer.git');
    expect(skill.source.ref, 'main');
    expect(skill.source.repositorySubpath, 'skills');
    expect(skill.source.skillPath, 'reviewer');
    expect(skill.isFavorite, isTrue);
    expect(skill.note, 'Keep this for release reviews.');
    expect(skill.personalTagIds, const ['quality']);
    expect(skill.integrity, WorkspaceSkillIntegrityStatus.revisionStoreCorrupt);
    expect(skill.draft?.purpose, WorkspaceDraftPurpose.customization);
    expect(skill.draft?.isDirty, isTrue);
    expect(
      skill.updateCandidate?.status,
      WorkspaceUpdateCandidateStatus.conflicted,
    );
    expect(skill.updateCandidate?.conflictPaths, const ['SKILL.md']);
    expect(skill.activationCount, 1);
    expect(skill.activations.single.location, '/agents/claude/skills');
    expect(skill.activations.single.mode, WorkspaceActivationMode.symbolicLink);
    expect(skill.activations.single.agentIds, const ['claude-code']);
  });

  test(
    'maps an activation takeover using the current Slot Key projection',
    () async {
      final managedSkillId = workspace.ManagedSkillId(_managedSkillId);
      final backend =
          _ControlledSkillsRepository(
              _repositorySnapshot(
                revision: 4,
                managedSkillId: managedSkillId,
                slotKey: 'reviewer',
              ),
            )
            ..activateOperation = _operation(
              workspace.SkillsSuccess<workspace.ActivationAttempt>(
                value: workspace.ActivationTakeoverRequired(
                  _TakeoverDraft(
                    reviewedRevision: workspace.RepositoryRevision(4),
                    targets: [
                      workspace.OccupiedActivationTarget(
                        managedSkillId: managedSkillId,
                        location: '/agents/claude/skills',
                        targetPath: '/agents/claude/skills/reviewer',
                        agentIds: const ['claude-code'],
                        kind: workspace
                            .ActivationTargetOccupancyKind
                            .skillDirectory,
                        contentRelation: workspace
                            .ActivationContentRelation
                            .differsFromCurrentRevision,
                        existingDeclaredName: 'Reviewer',
                      ),
                    ],
                  ),
                ),
              ),
            );
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(() async {
        await repository.close();
        await backend.dispose();
      });
      await _expectCompletion(repository.open());

      final result = await _expectCompleted(
        repository.activate(
          skillIds: {WorkspaceSkillId(_managedSkillId)},
          scope: WorkspaceScope.global,
          agentIds: const {'claude-code'},
        ),
      );

      expect(result, isA<WorkspaceActivationTakeoverRequired>());
      final draft = (result as WorkspaceActivationTakeoverRequired).draft;
      expect(draft.expectedRevision, 4);
      expect(draft.targets.single.slotKey, 'reviewer');
      expect(
        draft.targets.single.contentRelation,
        WorkspaceActivationContentRelation.differsFromCurrentRevision,
      );
    },
  );

  test('forwards the global activation method only where it applies', () async {
    final backend = _ControlledSkillsRepository(
      _repositorySnapshot(
        revision: 4,
        managedSkillId: workspace.ManagedSkillId(_managedSkillId),
        slotKey: 'reviewer',
      ),
    );
    final repository = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(() async {
      await repository.close();
      await backend.dispose();
    });
    await _expectCompletion(repository.open());
    final skillIds = {WorkspaceSkillId(_managedSkillId)};
    const local = SkillSourceInput(
      kind: WorkspaceSourceKind.local,
      locator: '/sources/reviewer',
    );

    for (final (method, scope, expected) in [
      (
        WorkspaceActivationMethod.copy,
        WorkspaceScope.global,
        workspace.RequestedActivationMode.copy,
      ),
      (
        WorkspaceActivationMethod.symbolicLink,
        WorkspaceScope.global,
        workspace.RequestedActivationMode.symbolicLink,
      ),
      (
        WorkspaceActivationMethod.automatic,
        WorkspaceScope.global,
        workspace.RequestedActivationMode.automatic,
      ),
      // A project link would tie checked-in content to this device.
      (
        WorkspaceActivationMethod.symbolicLink,
        WorkspaceScope.project,
        workspace.RequestedActivationMode.automatic,
      ),
    ]) {
      final projectRootId = scope == WorkspaceScope.project ? 'root' : null;
      await _expectCompleted(
        repository.activate(
          skillIds: skillIds,
          scope: scope,
          agentIds: const {'claude-code'},
          projectRootId: projectRootId,
          activationMethod: method,
        ),
      );
      await _expectCompleted(
        repository.install(
          WorkspaceInstallRequest(
            source: local,
            scope: scope,
            projectRootId: projectRootId,
            agentIds: const {'claude-code'},
            activationMethod: method,
          ),
        ),
      );
      expect(
        backend.activateRequests.last.mode,
        expected,
        reason: 'activate $method in ${scope.name}',
      );
      expect(
        backend.installRequests.last.activationMode,
        expected,
        reason: 'install $method in ${scope.name}',
      );
    }

    // Adoption may land in both scopes, so only a copy is forwarded.
    for (final (method, expected) in [
      (WorkspaceActivationMethod.copy, workspace.RequestedActivationMode.copy),
      (
        WorkspaceActivationMethod.symbolicLink,
        workspace.RequestedActivationMode.automatic,
      ),
    ]) {
      await _expectCompleted(
        repository.adopt(
          ExternalSkillAdoptionRequest(
            slotKey: 'reviewer',
            authoritativeLocation: '/agents/claude/skills/reviewer',
            reviewedContentHashByLocation: {
              '/agents/claude/skills/reviewer': 'a' * 64,
            },
            activationMethod: method,
          ),
        ),
      );
      expect(backend.adoptRequests.last.activationMode, expected);
    }
  });

  test(
    'inspection preserves Workspace canonical Source for replacement identity',
    () async {
      final backend =
          _ControlledSkillsRepository(workspace.RepositorySnapshot.empty())
            ..inspectSourceOperation = _operation(
              workspace.SkillsSuccess(
                value: workspace.SourceInspection(
                  source: workspace.GitSourceDescriptor(
                    locator: 'https://github.com/owner/repo.git',
                    ref: 'main',
                    repositorySubpath: 'skills',
                  ),
                  candidates: const [],
                ),
              ),
            );
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(() async {
        await repository.close();
        await backend.dispose();
      });
      await _expectCompletion(repository.open());
      final result = await _expectCompleted(
        repository.inspectSource(
          const SkillSourceInput(
            kind: WorkspaceSourceKind.git,
            locator: 'owner/repo',
            ref: 'main',
            repositorySubpath: 'skills',
          ),
        ),
      );
      expect(result.source.locator, 'https://github.com/owner/repo.git');
      expect(result.source.ref, 'main');
      expect(result.source.repositorySubpath, 'skills');
    },
  );

  test('returns expected backend failure as a typed completion', () async {
    final backend =
        _ControlledSkillsRepository(workspace.RepositorySnapshot.empty())
          ..inspectSourceOperation = _operation(
            workspace.SkillsFailure<workspace.SourceInspection>(
              code: workspace.SkillsErrorCode.sourceUnavailable,
              context: const {'sourceCode': 'notFound'},
            ),
          );
    final repository = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(() async {
      await repository.close();
      await backend.dispose();
    });
    await _expectCompletion(repository.open());

    final completion = await repository
        .inspectSource(
          const SkillSourceInput(
            kind: WorkspaceSourceKind.local,
            locator: '/missing/source',
          ),
        )
        .completed;

    expect(completion, isA<WorkspaceFailed<WorkspaceSourceInspection>>());
    final failure =
        (completion as WorkspaceFailed<WorkspaceSourceInspection>).failure;
    expect(failure.code, WorkspaceErrorCode.sourceUnavailable);
    expect(failure.operation, WorkspaceOperationKind.inspectSource);
    expect(failure.context, const {'sourceCode': 'notFound'});
  });

  group('personal tags', () {
    final managedSkillId = workspace.ManagedSkillId(_managedSkillId);
    final tag = workspace.PersonalTag(
      id: 'tag-1',
      name: 'Writing',
      color: '#3E63DD',
      createdAt: _timestamp,
      updatedAt: _timestamp,
    );

    Future<
      ({
        PackageSkillsWorkspaceRepository repository,
        _ControlledSkillsRepository backend,
      })
    >
    openRepository() async {
      final backend = _ControlledSkillsRepository(
        _repositorySnapshot(
          revision: 1,
          managedSkillId: managedSkillId,
          slotKey: 'reviewer',
        ),
      );
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(() async {
        await repository.close();
        await backend.dispose();
      });
      await _expectCompletion(repository.open());
      return (repository: repository, backend: backend);
    }

    test(
      'create publishes the backend snapshot before returning the tag',
      () async {
        final (:repository, :backend) = await openRepository();
        final tagged = _repositorySnapshot(
          revision: 2,
          managedSkillId: managedSkillId,
          slotKey: 'reviewer',
          personalTags: [tag],
        );
        backend.personalTagOperation = _operation(
          workspace.SkillsSuccess(value: tag),
        );
        backend.emit(tagged);
        final published = expectLater(
          repository.snapshots,
          emitsThrough(
            predicate<SkillsWorkspaceSnapshot>(
              (snapshot) => snapshot.findPersonalTag('tag-1') != null,
            ),
          ),
        );

        final created = await _expectCompletion(
          repository
              .createPersonalTag(name: 'Writing', color: '#3E63DD')
              .completed,
        );

        expect(created.id, 'tag-1');
        expect(created.color, '#3E63DD');
        expect(repository.current?.findPersonalTag('tag-1')?.name, 'Writing');
        await published;
        final request =
            backend.personalTagRequests.single
                as workspace.CreatePersonalTagRequest;
        expect(request.name, 'Writing');
        expect(request.color, '#3E63DD');
      },
    );

    test('update forwards the full name and color replacement', () async {
      final (:repository, :backend) = await openRepository();
      backend.personalTagOperation = _operation(
        workspace.SkillsSuccess(value: tag),
      );

      await _expectCompletion(
        repository
            .updatePersonalTag(tagId: 'tag-1', name: 'Writing', color: null)
            .completed,
      );

      final request =
          backend.personalTagRequests.single
              as workspace.UpdatePersonalTagRequest;
      expect(request.tagId, 'tag-1');
      expect(request.name, 'Writing');
      expect(request.color, isNull);
    });

    test('assign, unassign, and delete map Skill and tag identities', () async {
      final (:repository, :backend) = await openRepository();
      backend.personalTagSnapshotOperation = _operation(
        workspace.SkillsSuccess(value: backend.snapshot),
      );
      final skillId = WorkspaceSkillId(_managedSkillId);

      await _expectCompletion(
        repository
            .assignPersonalTag(skillId: skillId, tagId: 'tag-1')
            .completed,
      );
      await _expectCompletion(
        repository
            .unassignPersonalTag(skillId: skillId, tagId: 'tag-1')
            .completed,
      );
      await _expectCompletion(repository.deletePersonalTag('tag-1').completed);

      final [
        assign as workspace.AssignPersonalTagRequest,
        unassign as workspace.UnassignPersonalTagRequest,
        delete as workspace.DeletePersonalTagRequest,
      ] = backend.personalTagRequests;
      expect(assign.managedSkillId, managedSkillId);
      expect(assign.tagId, 'tag-1');
      expect(unassign.managedSkillId, managedSkillId);
      expect(unassign.tagId, 'tag-1');
      expect(delete.tagId, 'tag-1');
    });

    test('maps duplicate and missing tag failures to typed codes', () async {
      final (:repository, :backend) = await openRepository();
      backend.personalTagOperation = _operation(
        workspace.SkillsFailure<workspace.PersonalTag>(
          code: workspace.SkillsErrorCode.duplicatePersonalTag,
        ),
      );
      backend.personalTagSnapshotOperation = _operation(
        workspace.SkillsFailure<workspace.RepositorySnapshot>(
          code: workspace.SkillsErrorCode.personalTagNotFound,
        ),
      );

      final duplicate = await repository
          .createPersonalTag(name: 'writing')
          .completed;
      final missing = await repository
          .assignPersonalTag(
            skillId: WorkspaceSkillId(_managedSkillId),
            tagId: 'gone',
          )
          .completed;

      expect(
        (duplicate as WorkspaceFailed<WorkspacePersonalTag>).failure.code,
        WorkspaceErrorCode.duplicatePersonalTag,
      );
      expect(
        duplicate.failure.operation,
        WorkspaceOperationKind.createPersonalTag,
      );
      expect(
        (missing as WorkspaceFailed<SkillsWorkspaceSnapshot>).failure.code,
        WorkspaceErrorCode.personalTagNotFound,
      );
    });

    test(
      'rejects blank names and malformed colors before the backend',
      () async {
        final (:repository, :backend) = await openRepository();

        final blank = await repository.createPersonalTag(name: '  ').completed;
        final badColor = await repository
            .updatePersonalTag(tagId: 'tag-1', name: 'Writing', color: 'blue')
            .completed;

        expect(
          (blank as WorkspaceFailed).failure.context['reason'],
          'invalidPersonalTagName',
        );
        expect(
          (badColor as WorkspaceFailed).failure.context['reason'],
          'invalidPersonalTagColor',
        );
        expect(backend.personalTagRequests, isEmpty);
      },
    );
  });

  test('preserves canonical adoption destinations from the package', () async {
    final backend =
        _ControlledSkillsRepository(workspace.RepositorySnapshot.empty())
          ..discoverExternalSkillsOperation = _operation(
            workspace.SkillsSuccess(
              value: workspace.ExternalSkillsDiscovery(
                candidates: <workspace.ExternalSkillCandidate>[
                  workspace.ExternalSkillCandidate(
                    slotKey: 'reviewer',
                    declaredName: 'reviewer',
                    description: 'Reviewer',
                    contentHash: _contentHash,
                    locations: const <String>['/legacy/reviewer'],
                    agentIds: const <String>['custom-reviewer'],
                    destinationLocations: const <String>['/canonical/reviewer'],
                  ),
                ],
                conflicts: <workspace.ExternalSkillConflict>[
                  workspace.ExternalSkillConflict(
                    slotKey: 'conflict',
                    contentHashByLocation: const <String, String>{
                      '/legacy/conflict': _contentHash,
                    },
                    destinationLocations: const <String>['/canonical/conflict'],
                  ),
                ],
              ),
            ),
          );
    final repository = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(() async {
      await repository.close();
      await backend.dispose();
    });

    final discovery = await _expectCompleted(
      repository.discoverExternalSkills(),
    );

    expect(discovery.candidates.single.destinationLocations, const <String>[
      '/canonical/reviewer',
    ]);
    expect(discovery.conflicts.single.destinationLocations, const <String>[
      '/canonical/conflict',
    ]);
  });

  test('returns App source precondition failures as operation-specific typed completions', () async {
    final backend = _ControlledSkillsRepository(
      workspace.RepositorySnapshot.empty(),
    );
    final repository = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(() async {
      await repository.close();
      await backend.dispose();
    });
    const unsupportedSource = SkillSourceInput(
      kind: WorkspaceSourceKind.adoptedSnapshot,
      locator: '/external/snapshot',
    );

    final inspect = await repository.inspectSource(unsupportedSource).completed;
    final install = await repository
        .install(
          WorkspaceInstallRequest(
            source: unsupportedSource,
            scope: WorkspaceScope.global,
            storeOnly: true,
          ),
        )
        .completed;
    final replacement = await repository
        .replaceSource(
          skillId: WorkspaceSkillId(_managedSkillId),
          source: unsupportedSource,
          expectedRevision: 1,
        )
        .completed;

    expect(
      (inspect as WorkspaceFailed<WorkspaceSourceInspection>).failure,
      isA<WorkspaceFailure>()
          .having(
            (failure) => failure.code,
            'code',
            WorkspaceErrorCode.invalidSource,
          )
          .having(
            (failure) => failure.operation,
            'operation',
            WorkspaceOperationKind.inspectSource,
          ),
    );
    expect(
      (install as WorkspaceFailed<WorkspaceInstallAttempt>).failure,
      isA<WorkspaceFailure>()
          .having(
            (failure) => failure.code,
            'code',
            WorkspaceErrorCode.invalidSource,
          )
          .having(
            (failure) => failure.operation,
            'operation',
            WorkspaceOperationKind.install,
          ),
    );
    expect(
      (replacement as WorkspaceFailed<WorkspaceMutationReceipt>).failure,
      isA<WorkspaceFailure>()
          .having(
            (failure) => failure.code,
            'code',
            WorkspaceErrorCode.invalidSource,
          )
          .having(
            (failure) => failure.operation,
            'operation',
            WorkspaceOperationKind.replaceSource,
          ),
    );
  });

  test('returns update-all-before-open as a typed update failure', () async {
    final backend = _ControlledSkillsRepository(
      workspace.RepositorySnapshot.empty(),
    );
    final repository = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(() async {
      await repository.close();
      await backend.dispose();
    });

    final completion = await repository.update().completed;

    expect(completion, isA<WorkspaceFailed<WorkspaceMutationReceipt>>());
    final failure =
        (completion as WorkspaceFailed<WorkspaceMutationReceipt>).failure;
    expect(failure.code, WorkspaceErrorCode.repositoryNotOpen);
    expect(failure.operation, WorkspaceOperationKind.update);
  });

  test(
    'open, refresh, and Effective-document failures stay in typed completions',
    () async {
      final managedSkillId = workspace.ManagedSkillId(_managedSkillId);
      final backend = _ControlledSkillsRepository(
        _repositorySnapshot(
          revision: 1,
          managedSkillId: managedSkillId,
          slotKey: 'reviewer',
        ),
      );
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(() async {
        await repository.close();
        await backend.dispose();
      });

      backend.openOperation = _operation(
        workspace.SkillsFailure<workspace.RepositorySnapshot>(
          code: workspace.SkillsErrorCode.controlPlaneCorrupt,
        ),
      );
      final open = await repository.open();
      expect(open, isA<WorkspaceFailed<SkillsWorkspaceSnapshot>>());
      expect(
        (open as WorkspaceFailed<SkillsWorkspaceSnapshot>).failure.code,
        WorkspaceErrorCode.controlPlaneCorrupt,
      );

      backend.openOperation = _operation(
        workspace.SkillsSuccess(value: backend.snapshot),
      );
      await _expectCompletion(repository.open());

      backend.refreshOperation = _operation(
        workspace.SkillsFailure<workspace.RepositorySnapshot>(
          code: workspace.SkillsErrorCode.repositoryBusy,
        ),
      );
      final refresh = await repository.refresh();
      expect(refresh, isA<WorkspaceFailed<SkillsWorkspaceSnapshot>>());
      expect(
        (refresh as WorkspaceFailed<SkillsWorkspaceSnapshot>).failure.code,
        WorkspaceErrorCode.repositoryBusy,
      );

      backend.listEffectiveFilesOperation = _operation(
        workspace.SkillsFailure<workspace.EffectiveSkillFileManifest>(
          code: workspace.SkillsErrorCode.revisionStoreCorrupt,
        ),
      );
      final listed = await repository.listSkillDocuments(
        WorkspaceSkillId(_managedSkillId),
      );
      expect(listed, isA<WorkspaceFailed<List<SkillDocumentEntry>>>());
      expect(
        (listed as WorkspaceFailed<List<SkillDocumentEntry>>).failure.code,
        WorkspaceErrorCode.revisionStoreCorrupt,
      );

      backend.readEffectiveFileOperation = _operation(
        workspace.SkillsFailure<workspace.EffectiveSkillFileContent>(
          code: workspace.SkillsErrorCode.effectiveFileNotFound,
        ),
      );
      final read = await repository.readSkillDocument(
        WorkspaceSkillId(_managedSkillId),
        'SKILL.md',
        expectedContentHash: _contentHash,
      );
      expect(read, isA<WorkspaceFailed<String>>());
      expect(
        (read as WorkspaceFailed<String>).failure.code,
        WorkspaceErrorCode.effectiveFileNotFound,
      );
    },
  );

  test('maps every public backend error code to a typed App failure', () async {
    const expectedNames = <workspace.SkillsErrorCode, String>{
      workspace.SkillsErrorCode.sourceUnavailable: 'sourceUnavailable',
      workspace.SkillsErrorCode.sourceAuthenticationRequired:
          'sourceAuthenticationRequired',
      workspace.SkillsErrorCode.gitUnavailable: 'gitUnavailable',
      workspace.SkillsErrorCode.gitFailed: 'gitFailed',
      workspace.SkillsErrorCode.developerToolsRequired:
          'developerToolsRequired',
      workspace.SkillsErrorCode.transportRejected: 'transportRejected',
      workspace.SkillsErrorCode.httpFailure: 'httpFailure',
      workspace.SkillsErrorCode.digestMismatch: 'digestMismatch',
      workspace.SkillsErrorCode.archiveInvalid: 'archiveInvalid',
      workspace.SkillsErrorCode.skillNotFound: 'skillNotFound',
      workspace.SkillsErrorCode.staleSnapshot: 'staleSnapshot',
      workspace.SkillsErrorCode.staleDriftReview: 'staleDriftReview',
      workspace.SkillsErrorCode.driftResolutionUnavailable:
          'driftResolutionUnavailable',
      workspace.SkillsErrorCode.staleInstallTakeover: 'staleInstallTakeover',
      workspace.SkillsErrorCode.staleActivationTakeover:
          'staleActivationTakeover',
      workspace.SkillsErrorCode.invalidSkill: 'invalidSkill',
      workspace.SkillsErrorCode.unsupportedSkillName: 'unsupportedSkillName',
      workspace.SkillsErrorCode.skillContentLimitExceeded:
          'skillContentLimitExceeded',
      workspace.SkillsErrorCode.duplicateSkillSlot: 'duplicateSkillSlot',
      workspace.SkillsErrorCode.sourceReplacementRequired:
          'sourceReplacementRequired',
      workspace.SkillsErrorCode.updateUnsupported: 'updateUnsupported',
      workspace.SkillsErrorCode.externalConflict: 'externalConflict',
      workspace.SkillsErrorCode.activationUnavailable: 'activationUnavailable',
      workspace.SkillsErrorCode.activationUnsupported: 'activationUnsupported',
      workspace.SkillsErrorCode.projectRootNotFound: 'projectRootNotFound',
      workspace.SkillsErrorCode.invalidProjectRoot: 'invalidProjectRoot',
      workspace.SkillsErrorCode.projectRootConflict: 'projectRootConflict',
      workspace.SkillsErrorCode.agentNotFound: 'agentNotFound',
      workspace.SkillsErrorCode.duplicateAgentId: 'duplicateAgentId',
      workspace.SkillsErrorCode.personalTagNotFound: 'personalTagNotFound',
      workspace.SkillsErrorCode.duplicatePersonalTag: 'duplicatePersonalTag',
      workspace.SkillsErrorCode.repositoryBusy: 'repositoryBusy',
      workspace.SkillsErrorCode.operationCancelled: 'operationCancelled',
      workspace.SkillsErrorCode.unsupportedStateVersion:
          'unsupportedStateVersion',
      workspace.SkillsErrorCode.unsupportedJournalVersion:
          'unsupportedJournalVersion',
      workspace.SkillsErrorCode.stateCorrupt: 'stateCorrupt',
      workspace.SkillsErrorCode.journalCorrupt: 'journalCorrupt',
      workspace.SkillsErrorCode.journalMaintenanceFailed:
          'journalMaintenanceFailed',
      workspace.SkillsErrorCode.rollbackFailed: 'rollbackFailed',
      workspace.SkillsErrorCode.recoveryFailed: 'recoveryFailed',
      workspace.SkillsErrorCode.ioFailure: 'ioFailure',
      workspace.SkillsErrorCode.operationFailed: 'operationFailed',
      workspace.SkillsErrorCode.migrationFailed: 'migrationFailed',
      workspace.SkillsErrorCode.controlPlaneCorrupt: 'controlPlaneCorrupt',
      workspace.SkillsErrorCode.revisionStoreCorrupt: 'revisionStoreCorrupt',
      workspace.SkillsErrorCode.invalidEffectiveFilePath:
          'invalidEffectiveFilePath',
      workspace.SkillsErrorCode.effectiveFileNotFound: 'effectiveFileNotFound',
      workspace.SkillsErrorCode.finalizationRecoveryFailed:
          'finalizationRecoveryFailed',
      workspace.SkillsErrorCode.dirtyDraftResolutionRequired:
          'dirtyDraftResolutionRequired',
      workspace.SkillsErrorCode.updateCandidateResolutionRequired:
          'updateCandidateResolutionRequired',
      workspace.SkillsErrorCode.draftChangedDuringPublish:
          'draftChangedDuringPublish',
      workspace.SkillsErrorCode.declaredNameChangeNotAllowed:
          'declaredNameChangeNotAllowed',
      workspace.SkillsErrorCode.historicalNameMismatch:
          'historicalNameMismatch',
    };
    expect(
      expectedNames.keys,
      unorderedEquals(workspace.SkillsErrorCode.values),
    );

    final backend = _ControlledSkillsRepository(
      workspace.RepositorySnapshot.empty(),
    );
    final repository = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(() async {
      await repository.close();
      await backend.dispose();
    });
    await _expectCompletion(repository.open());

    for (final MapEntry(key: backendCode, value: expectedName)
        in expectedNames.entries) {
      backend.inspectSourceOperation = _operation(
        workspace.SkillsFailure<workspace.SourceInspection>(code: backendCode),
      );

      final completion = await repository
          .inspectSource(
            const SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: '/source',
            ),
          )
          .completed;

      expect(completion, isA<WorkspaceFailed<WorkspaceSourceInspection>>());
      final failure =
          (completion as WorkspaceFailed<WorkspaceSourceInspection>).failure;
      expect(failure.code.name, expectedName, reason: backendCode.name);
    }
  });

  test(
    'keeps committed-finalization-pending distinct from success and failure',
    () async {
      final backend =
          _ControlledSkillsRepository(workspace.RepositorySnapshot.empty())
            ..installOperation = _operation(
              workspace.SkillsCommittedFinalizationPending<
                workspace.InstallAttempt
              >(
                operationId: workspace.OperationId(_pendingOperationId),
                committedRepositoryRevision: workspace.RepositoryRevision(7),
                warnings: [
                  workspace.SkillsWarning(
                    code: workspace.SkillsWarningCode.finalizationDeferred,
                  ),
                ],
              ),
            );
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(() async {
        await repository.close();
        await backend.dispose();
      });
      await _expectCompletion(repository.open());

      final completion = await repository
          .install(
            WorkspaceInstallRequest(
              source: const SkillSourceInput(
                kind: WorkspaceSourceKind.local,
                locator: '/source',
              ),
              scope: WorkspaceScope.global,
              storeOnly: true,
            ),
          )
          .completed;

      expect(
        completion,
        isA<WorkspaceCommittedPending<WorkspaceInstallAttempt>>(),
      );
      final pending =
          completion as WorkspaceCommittedPending<WorkspaceInstallAttempt>;
      expect(pending.operationId, _pendingOperationId);
      expect(pending.committedRevision, 7);
      expect(
        pending.warnings.single.code,
        WorkspaceWarningCode.finalizationDeferred,
      );
    },
  );

  test('maps and confirms an Install takeover draft', () async {
    final backendDraft = _BackendInstallTakeoverDraft();
    final backend =
        _ControlledSkillsRepository(workspace.RepositorySnapshot.empty())
          ..installOperation = _operation(
            workspace.SkillsSuccess<workspace.InstallAttempt>(
              value: workspace.InstallTakeoverRequired(backendDraft),
            ),
          );
    final repository = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(() async {
      await repository.close();
      await backend.dispose();
    });
    await _expectCompletion(repository.open());

    final attempt = await _expectCompleted(
      repository.install(
        WorkspaceInstallRequest(
          source: const SkillSourceInput(
            kind: WorkspaceSourceKind.local,
            locator: '/source',
          ),
          scope: WorkspaceScope.global,
          agentIds: const {'codex'},
        ),
      ),
    );
    final required = attempt as WorkspaceInstallTakeoverRequired;
    expect(required.draft.targets.single.slotKey, 'debug-log-writer');
    expect(
      required.draft.targets.single.kind,
      WorkspaceActivationTargetOccupancyKind.brokenSymbolicLink,
    );

    await _expectCompleted(repository.confirmInstallTakeover(required.draft));
    expect(backend.confirmedInstallTakeovers, [same(backendDraft)]);
  });

  test(
    'maps Agent root ownership audit without exposing package models',
    () async {
      final backend =
          _ControlledSkillsRepository(workspace.RepositorySnapshot.empty())
            ..ownershipOperation = _operation(
              workspace.SkillsSuccess(
                value: workspace.AgentRootOwnershipAudit(
                  supported: true,
                  currentUserId: 501,
                  examinedRootCount: 1,
                  issues: [
                    workspace.AgentRootOwnershipIssue(
                      rootPath: '/Users/tester/.agent/skills',
                      agentIds: const {'built-in', 'custom'},
                      customAgentIds: const {'custom'},
                      roles: const {
                        workspace.AgentSkillRootRole.canonicalActivation,
                        workspace.AgentSkillRootRole.compatibilityDiscovery,
                      },
                      reason:
                          workspace.AgentRootOwnershipIssueReason.ownerMismatch,
                      repairable: true,
                    ),
                  ],
                ),
              ),
            );
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(() async {
        await repository.close();
        await backend.dispose();
      });

      final audit = await _expectCompleted(
        repository.inspectAgentRootOwnership(),
      );

      expect(audit.currentUserId, 501);
      expect(audit.examinedRootCount, 1);
      expect(audit.issues.single.customAgentIds, {'custom'});
      expect(audit.issues.single.roles, {
        WorkspaceAgentSkillRootRole.canonicalActivation,
        WorkspaceAgentSkillRootRole.compatibilityDiscovery,
      });
      expect(
        audit.issues.single.reason,
        WorkspaceAgentRootOwnershipIssueReason.ownerMismatch,
      );
    },
  );

  test(
    'keeps the App managed identity stable when a Slot Key migrates',
    () async {
      final managedSkillId = workspace.ManagedSkillId(_managedSkillId);
      final backend = _ControlledSkillsRepository(
        _repositorySnapshot(
          revision: 1,
          managedSkillId: managedSkillId,
          slotKey: 'before-migration',
        ),
      );
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(() async {
        await repository.close();
        await backend.dispose();
      });
      final opened = await _expectCompletion(repository.open());
      final originalId = opened.skills.single.id;
      final emitted = repository.snapshots.take(1).toList();

      backend.emit(
        _repositorySnapshot(
          revision: 2,
          managedSkillId: managedSkillId,
          slotKey: 'after-migration',
        ),
      );

      final snapshots = await emitted;
      final migrated = snapshots.single.skills.single;
      expect(migrated.slotKey, 'after-migration');
      expect(migrated.id, originalId);
      expect(
        repository.current?.findSkillById(originalId)?.slotKey,
        'after-migration',
      );
    },
  );
  test(
    'maps opaque drift review metadata and round-trips export and resolutions',
    () async {
      final id = workspace.ManagedSkillId(_managedSkillId);
      final backend = _ControlledSkillsRepository(
        _repositorySnapshot(
          revision: 1,
          managedSkillId: id,
          slotKey: 'reviewer',
        ),
      );
      addTearDown(backend.dispose);
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(repository.close);
      final backendReview = FakePackageSkillDriftReview(
        managedSkillId: id,
        effectiveContentHash: _contentHash,
        missingArtifactCount: 2,
        artifacts: [
          for (
            var index = 0;
            index < workspace.SkillDriftLocationKind.values.length;
            index++
          )
            workspace.SkillDriftArtifact(
              artifactId: 'artifact-$index',
              locationKind: workspace.SkillDriftLocationKind.values[index],
              driftKind: workspace.SkillDriftKind.values[index],
              targetPath: index == 0 ? null : '/agent/skills/reviewer',
              activationLocation: index == 0 ? null : '/agent/skills',
              scope: index == 0 ? null : workspace.ActivationScope.project,
              projectRootId: index == 0 ? null : 'project',
              agentIds: ['agent'],
              fileCount: 3,
              byteSize: 125,
              canKeepExternal: index == 0,
              canExport: index != 2,
            ),
        ],
      );
      backend.driftInspectionOperation = _operation(
        workspace.SkillsSuccess(value: backendReview),
      );
      final review = await _expectCompleted(
        repository.inspectSkillDrift(WorkspaceSkillId(_managedSkillId)),
      );
      expect(review.skillId, WorkspaceSkillId(_managedSkillId));
      expect(review.missingArtifactCount, 2);
      expect(
        review.artifacts.map((artifact) => artifact.locationKind),
        WorkspaceDriftLocationKind.values,
      );
      expect(
        review.artifacts.map((artifact) => artifact.driftKind),
        WorkspaceDriftKind.values,
      );
      expect(review.artifacts.first.targetPath, isNull);
      expect(review.artifacts[1].targetPath, '/agent/skills/reviewer');
      expect(review.artifacts[1].scope, WorkspaceScope.project);
      expect(review.artifacts[1].agentIds, ['agent']);
      expect(review.artifacts.first.canKeepExternal, isTrue);
      expect(review.artifacts.last.canExport, isFalse);
      expect(() => review.artifacts.clear(), throwsUnsupportedError);
      expect(
        () => review.artifacts.first.agentIds.clear(),
        throwsUnsupportedError,
      );
      final exported = await _expectCompleted(
        repository.exportSkillDriftArtifact(
          review: review,
          artifactId: 'artifact-0',
          destinationDirectory: '/exports',
        ),
      );
      expect(exported.exportedPath, '/exports/skill');
      expect(backend.driftExportRequests.single.review, same(backendReview));
      expect(backend.driftExportRequests.single.artifactId, 'artifact-0');
      expect(
        backend.driftExportRequests.single.destinationDirectory,
        '/exports',
      );
      for (final resolution in [
        const WorkspaceDriftResolution.keepExternal('artifact-0'),
        const WorkspaceDriftResolution.restoreManaged(),
      ]) {
        final receipt = await _expectCompleted(
          repository.resolveSkillDrift(review: review, resolution: resolution),
        );
        expect(receipt.affectedSkillIds, {review.skillId});
      }
      expect(backend.driftResolveRequests.first.review, same(backendReview));
      expect(
        (backend.driftResolveRequests.first.resolution
                as workspace.KeepExternalSkillDrift)
            .artifactId,
        'artifact-0',
      );
      expect(
        backend.driftResolveRequests.last.resolution,
        isA<workspace.RestoreManagedSkillDrift>(),
      );
    },
  );

  for (final streamDelivered in [false, true]) {
    test('captured mutation report cannot regress same-revision integrity '
        '(stream delivered: $streamDelivered)', () async {
      final id = workspace.ManagedSkillId(_managedSkillId);
      workspace.RepositorySnapshot snapshot(
        workspace.SkillIntegrityStatus status,
      ) => _repositorySnapshot(
        revision: 10,
        managedSkillId: id,
        slotKey: 'reviewer',
        integrity: workspace.WorkspaceIntegrity(
          skills: [
            workspace.ManagedSkillIntegrity(managedSkillId: id, status: status),
          ],
        ),
      );
      final captured = snapshot(workspace.SkillIntegrityStatus.driftPending);
      final backend = _ControlledSkillsRepository(captured);
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(() async {
        await repository.close();
        await backend.dispose();
      });
      await _expectCompletion(repository.open());
      backend.driftInspectionOperation = _operation(
        workspace.SkillsSuccess(
          value: FakePackageSkillDriftReview(
            managedSkillId: id,
            effectiveContentHash: _contentHash,
            artifacts: const [],
          ),
        ),
      );
      final review = await _expectCompleted(
        repository.inspectSkillDrift(WorkspaceSkillId(_managedSkillId)),
      );
      backend.driftResolveOperation = _operation(
        workspace.SkillsSuccess(
          value: workspace.MutationReport(
            snapshot: captured,
            affectedSkillIds: {id},
          ),
        ),
      );
      final observed = <WorkspaceSkillIntegrityStatus>[];
      final subscription = repository.snapshots.listen(
        (s) => observed.add(s.skills.single.integrity),
      );
      addTearDown(subscription.cancel);
      Future<WorkspaceCompletion<WorkspaceMutationReceipt>> completion;
      if (streamDelivered) {
        backend.emit(snapshot(workspace.SkillIntegrityStatus.healthy));
        await Future<void>.delayed(Duration.zero);
        expect(
          repository.current!.skills.single.integrity,
          WorkspaceSkillIntegrityStatus.healthy,
        );
        completion = repository
            .resolveSkillDrift(
              review: review,
              resolution: const WorkspaceDriftResolution.restoreManaged(),
            )
            .completed;
      } else {
        completion = repository
            .resolveSkillDrift(
              review: review,
              resolution: const WorkspaceDriftResolution.restoreManaged(),
            )
            .completed;
        // Current advances synchronously; its stream event is still queued.
        backend.emit(snapshot(workspace.SkillIntegrityStatus.healthy));
      }
      final receipt =
          (await completion as WorkspaceCompleted<WorkspaceMutationReceipt>)
              .value;
      await Future<void>.delayed(Duration.zero);
      expect(receipt.snapshot.revision, 10);
      expect(
        receipt.snapshot.skills.single.integrity,
        WorkspaceSkillIntegrityStatus.healthy,
      );
      expect(
        repository.current!.skills.single.integrity,
        WorkspaceSkillIntegrityStatus.healthy,
      );
      expect(observed, [WorkspaceSkillIntegrityStatus.healthy]);
    });
  }

  test(
    'queued integrity events forward only the latest backend Snapshot',
    () async {
      final id = workspace.ManagedSkillId(_managedSkillId);
      workspace.RepositorySnapshot snapshot(
        workspace.SkillIntegrityStatus status,
      ) => _repositorySnapshot(
        revision: 1,
        managedSkillId: id,
        slotKey: 'reviewer',
        integrity: workspace.WorkspaceIntegrity(
          skills: [
            workspace.ManagedSkillIntegrity(managedSkillId: id, status: status),
          ],
        ),
      );
      final backend = _ControlledSkillsRepository(
        snapshot(workspace.SkillIntegrityStatus.driftPending),
      );
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(() async {
        await repository.close();
        await backend.dispose();
      });
      await _expectCompletion(repository.open());
      final observed = <WorkspaceSkillIntegrityStatus>[];
      final subscription = repository.snapshots.listen(
        (s) => observed.add(s.skills.single.integrity),
      );
      addTearDown(subscription.cancel);
      backend.emit(snapshot(workspace.SkillIntegrityStatus.validating));
      backend.emit(snapshot(workspace.SkillIntegrityStatus.healthy));
      await Future<void>.delayed(Duration.zero);
      expect(
        repository.current!.skills.single.integrity,
        WorkspaceSkillIntegrityStatus.healthy,
      );
      expect(observed, [WorkspaceSkillIntegrityStatus.healthy]);
    },
  );

  test('rejects caller-created and other adapter drift reviews before backend writes', () async {
    final id = workspace.ManagedSkillId(_managedSkillId);
    final backend = _ControlledSkillsRepository(
      _repositorySnapshot(revision: 1, managedSkillId: id, slotKey: 'reviewer'),
    );
    addTearDown(backend.dispose);
    backend.driftInspectionOperation = _operation(
      workspace.SkillsSuccess(
        value: FakePackageSkillDriftReview(
          managedSkillId: id,
          effectiveContentHash: _contentHash,
          artifacts: const [],
        ),
      ),
    );
    final first = PackageSkillsWorkspaceRepository(backend: backend);
    final second = PackageSkillsWorkspaceRepository(backend: backend);
    addTearDown(first.close);
    addTearDown(second.close);
    final fromFirst = await _expectCompleted(
      first.inspectSkillDrift(WorkspaceSkillId(_managedSkillId)),
    );
    for (final foreign in [
      fromFirst,
      FakeWorkspaceSkillDriftReview(skillId: fromFirst.skillId),
    ]) {
      final exported = await second
          .exportSkillDriftArtifact(
            review: foreign,
            artifactId: 'repositoryCopy',
            destinationDirectory: '/exports',
          )
          .completed;
      final resolved = await second
          .resolveSkillDrift(
            review: foreign,
            resolution: const WorkspaceDriftResolution.restoreManaged(),
          )
          .completed;
      for (final failure in [
        (exported as WorkspaceFailed).failure,
        (resolved as WorkspaceFailed).failure,
      ]) {
        expect(failure.code, WorkspaceErrorCode.staleDriftReview);
        expect(failure.context['reason'], 'foreignReview');
      }
    }
    expect(backend.driftExportRequests, isEmpty);
    expect(backend.driftResolveRequests, isEmpty);
  });

  test(
    'drift resolve preserves committed-pending identity and warnings',
    () async {
      final id = workspace.ManagedSkillId(_managedSkillId);
      final backend = _ControlledSkillsRepository(
        _repositorySnapshot(
          revision: 1,
          managedSkillId: id,
          slotKey: 'reviewer',
        ),
      );
      addTearDown(backend.dispose);
      backend.driftInspectionOperation = _operation(
        workspace.SkillsSuccess(
          value: FakePackageSkillDriftReview(
            managedSkillId: id,
            effectiveContentHash: _contentHash,
            artifacts: const [],
          ),
        ),
      );
      backend.driftResolveOperation = _operation(
        workspace.SkillsCommittedFinalizationPending<workspace.MutationReport>(
          operationId: workspace.OperationId(_pendingOperationId),
          committedRepositoryRevision: workspace.RepositoryRevision(2),
          warnings: [
            workspace.SkillsWarning(
              code: workspace.SkillsWarningCode.finalizationDeferred,
            ),
          ],
        ),
      );
      final repository = PackageSkillsWorkspaceRepository(backend: backend);
      addTearDown(repository.close);
      final review = await _expectCompleted(
        repository.inspectSkillDrift(WorkspaceSkillId(_managedSkillId)),
      );
      final completion = await repository
          .resolveSkillDrift(
            review: review,
            resolution: const WorkspaceDriftResolution.restoreManaged(),
          )
          .completed;
      expect(
        completion,
        isA<WorkspaceCommittedPending<WorkspaceMutationReceipt>>(),
      );
      final pending =
          completion as WorkspaceCommittedPending<WorkspaceMutationReceipt>;
      expect(pending.operationId, _pendingOperationId);
      expect(pending.committedRevision, 2);
      expect(
        pending.warnings.single.code,
        WorkspaceWarningCode.finalizationDeferred,
      );
    },
  );
}

const _managedSkillId = '11111111-1111-4111-8111-111111111111';
const _pendingOperationId = '22222222-2222-4222-8222-222222222222';
final _timestamp = DateTime.utc(2026, 8, 25, 12);
const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

workspace.RepositorySnapshot _repositorySnapshot({
  required int revision,
  required workspace.ManagedSkillId managedSkillId,
  required String slotKey,
  workspace.SourceDescriptor? source,
  List<workspace.SkillActivation> activations = const [],
  workspace.SkillFavorite favorite = const workspace.SkillFavorite(
    isFavorite: false,
  ),
  workspace.SkillNote? note,
  List<String> personalTagIds = const [],
  workspace.DraftSummary? draft,
  workspace.UpdateCandidateSummary? updateCandidate,
  workspace.WorkspaceIntegrity? integrity,
  List<workspace.PersonalTag> personalTags = const [],
}) => workspace.RepositorySnapshot(
  revision: workspace.RepositoryRevision(revision),
  managedSkills: [
    workspace.ManagedSkill(
      id: managedSkillId,
      slotKey: slotKey,
      declaredName: slotKey,
      displayName: 'Reviewer',
      description: 'A test Skill.',
      source: source ?? workspace.LocalSourceDescriptor(locator: '/source'),
      currentRevision: workspace.ManagedSkillRevisionSummary(
        contentHash: _contentHash,
        fileCount: 2,
        byteSize: 128,
        publishedAt: _timestamp,
      ),
      activations: activations,
      favorite: favorite,
      note: note,
      personalTagIds: personalTagIds,
      draft: draft,
      updateCandidate: updateCandidate,
    ),
  ],
  personalTags: personalTags,
  integrity: integrity,
);

final class _ControlledSkillsRepository implements workspace.SkillsRepository {
  _ControlledSkillsRepository(this._snapshot)
    : openOperation = _operation(workspace.SkillsSuccess(value: _snapshot));

  workspace.RepositorySnapshot _snapshot;
  final StreamController<workspace.RepositorySnapshot> _snapshots =
      StreamController<workspace.RepositorySnapshot>.broadcast();

  workspace.SkillsOperation<workspace.RepositorySnapshot> openOperation;
  workspace.SkillsOperation<workspace.RepositorySnapshot>? refreshOperation;
  workspace.SkillsOperation<workspace.SourceInspection>? inspectSourceOperation;
  workspace.SkillsOperation<workspace.EffectiveSkillFileManifest>?
  listEffectiveFilesOperation;
  workspace.SkillsOperation<workspace.EffectiveSkillFileContent>?
  readEffectiveFileOperation;
  final readEffectiveFileRequests = <workspace.ReadEffectiveFileRequest>[];
  workspace.SkillsOperation<workspace.InstallAttempt>? installOperation;
  final installRequests = <workspace.InstallRequest>[];
  final adoptRequests = <workspace.AdoptRequest>[];
  final activateRequests = <workspace.ActivateRequest>[];
  workspace.SkillsOperation<workspace.MutationReport>?
  confirmInstallTakeoverOperation;
  final confirmedInstallTakeovers = <workspace.InstallTakeoverDraft>[];
  workspace.SkillsOperation<workspace.ActivationAttempt>? activateOperation;
  workspace.SkillsOperation<workspace.AgentRootOwnershipAudit>?
  ownershipOperation;
  workspace.SkillsOperation<workspace.ExternalSkillsDiscovery>?
  discoverExternalSkillsOperation;
  workspace.SkillsOperation<workspace.SkillDriftReview>?
  driftInspectionOperation;
  workspace.SkillsOperation<workspace.SkillDriftExport>? driftExportOperation;
  workspace.SkillsOperation<workspace.MutationReport>? driftResolveOperation;
  final driftInspectionRequests = <workspace.InspectSkillDriftRequest>[];
  final driftExportRequests = <workspace.ExportSkillDriftArtifactRequest>[];
  final driftResolveRequests = <workspace.ResolveSkillDriftRequest>[];

  @override
  workspace.SkillsOperation<workspace.SkillDriftReview> inspectSkillDrift(
    workspace.InspectSkillDriftRequest request,
  ) {
    driftInspectionRequests.add(request);
    return driftInspectionOperation!;
  }

  @override
  workspace.SkillsOperation<workspace.SkillDriftExport>
  exportSkillDriftArtifact(workspace.ExportSkillDriftArtifactRequest request) {
    driftExportRequests.add(request);
    return driftExportOperation ??
        _operation(
          workspace.SkillsSuccess(
            value: const workspace.SkillDriftExport(
              exportedPath: '/exports/skill',
            ),
          ),
        );
  }

  @override
  workspace.SkillsOperation<workspace.MutationReport> resolveSkillDrift(
    workspace.ResolveSkillDriftRequest request,
  ) {
    driftResolveRequests.add(request);
    return driftResolveOperation ??
        _operation(
          workspace.SkillsSuccess(
            value: workspace.MutationReport(
              snapshot: _snapshot,
              affectedSkillIds: {request.review.managedSkillId},
            ),
          ),
        );
  }

  void emit(workspace.RepositorySnapshot snapshot) {
    _snapshot = snapshot;
    _snapshots.add(snapshot);
  }

  Future<void> dispose() => _snapshots.close();

  @override
  bool get isOpen => true;

  @override
  workspace.RepositorySnapshot get snapshot => _snapshot;

  @override
  Stream<workspace.RepositorySnapshot> get snapshots => _snapshots.stream;

  @override
  workspace.SkillsOperation<workspace.RepositorySnapshot> open() =>
      openOperation;

  @override
  workspace.SkillsOperation<workspace.RepositorySnapshot> refresh() =>
      refreshOperation ?? _operation(workspace.SkillsSuccess(value: _snapshot));

  @override
  workspace.SkillsOperation<workspace.EffectiveSkillFileManifest>
  listEffectiveFiles(workspace.ListEffectiveFilesRequest request) =>
      listEffectiveFilesOperation ??
      _operation(
        workspace.SkillsFailure<workspace.EffectiveSkillFileManifest>(
          code: workspace.SkillsErrorCode.effectiveFileNotFound,
        ),
      );

  @override
  workspace.SkillsOperation<workspace.EffectiveSkillFileContent>
  readEffectiveFile(workspace.ReadEffectiveFileRequest request) {
    readEffectiveFileRequests.add(request);
    return readEffectiveFileOperation ??
        _operation(
          workspace.SkillsFailure<workspace.EffectiveSkillFileContent>(
            code: workspace.SkillsErrorCode.effectiveFileNotFound,
          ),
        );
  }

  @override
  workspace.SkillsOperation<void> close() =>
      _operation(workspace.SkillsSuccess<void>(value: null));

  @override
  workspace.SkillsOperation<workspace.SourceInspection> inspectSource(
    workspace.InspectSourceRequest request,
  ) =>
      inspectSourceOperation ??
      _operation(
        workspace.SkillsSuccess(
          value: workspace.SourceInspection(
            source: request.source,
            candidates: const [],
          ),
        ),
      );

  @override
  workspace.SkillsOperation<workspace.ExternalSkillsDiscovery>
  discoverExternalSkills(workspace.DiscoverExternalSkillsRequest request) =>
      discoverExternalSkillsOperation ??
      _operation(
        workspace.SkillsSuccess(
          value: workspace.ExternalSkillsDiscovery(
            candidates: const <workspace.ExternalSkillCandidate>[],
            conflicts: const <workspace.ExternalSkillConflict>[],
          ),
        ),
      );

  @override
  workspace.SkillsOperation<workspace.InstallAttempt> install(
    workspace.InstallRequest request,
  ) {
    installRequests.add(request);
    return installOperation ??
        _operation(
          workspace.SkillsSuccess(
            value: workspace.InstallCompleted(
              workspace.MutationReport(
                snapshot: _snapshot,
                affectedSkillIds: const {},
              ),
            ),
          ),
        );
  }

  @override
  workspace.SkillsOperation<workspace.MutationReport> adopt(
    workspace.AdoptRequest request,
  ) {
    adoptRequests.add(request);
    return _operation(
      workspace.SkillsSuccess(
        value: workspace.MutationReport(
          snapshot: _snapshot,
          affectedSkillIds: const {},
        ),
      ),
    );
  }

  @override
  workspace.SkillsOperation<workspace.MutationReport> confirmInstallTakeover(
    workspace.ConfirmInstallTakeoverRequest request,
  ) {
    confirmedInstallTakeovers.add(request.draft);
    return confirmInstallTakeoverOperation ??
        _operation(
          workspace.SkillsSuccess(
            value: workspace.MutationReport(
              snapshot: _snapshot,
              affectedSkillIds: const {},
            ),
          ),
        );
  }

  @override
  workspace.SkillsOperation<workspace.ActivationAttempt> activate(
    workspace.ActivateRequest request,
  ) {
    activateRequests.add(request);
    return activateOperation ??
        _operation(
          workspace.SkillsSuccess(
            value: workspace.ActivationCompleted(
              workspace.MutationReport(
                snapshot: _snapshot,
                affectedSkillIds: const {},
              ),
            ),
          ),
        );
  }

  @override
  workspace.SkillsOperation<workspace.AgentRootOwnershipAudit>
  inspectAgentRootOwnership(
    workspace.InspectAgentRootOwnershipRequest request,
  ) =>
      ownershipOperation ??
      _operation(
        workspace.SkillsSuccess(
          value: workspace.AgentRootOwnershipAudit(
            supported: false,
            examinedRootCount: 0,
            issues: const [],
          ),
        ),
      );

  workspace.SkillsOperation<workspace.PersonalTag>? personalTagOperation;
  workspace.SkillsOperation<workspace.RepositorySnapshot>?
  personalTagSnapshotOperation;
  final personalTagRequests = <Object>[];

  @override
  workspace.SkillsOperation<workspace.PersonalTag> createPersonalTag(
    workspace.CreatePersonalTagRequest request,
  ) {
    personalTagRequests.add(request);
    return personalTagOperation!;
  }

  @override
  workspace.SkillsOperation<workspace.PersonalTag> updatePersonalTag(
    workspace.UpdatePersonalTagRequest request,
  ) {
    personalTagRequests.add(request);
    return personalTagOperation!;
  }

  @override
  workspace.SkillsOperation<workspace.RepositorySnapshot> deletePersonalTag(
    workspace.DeletePersonalTagRequest request,
  ) {
    personalTagRequests.add(request);
    return personalTagSnapshotOperation!;
  }

  @override
  workspace.SkillsOperation<workspace.RepositorySnapshot> assignPersonalTag(
    workspace.AssignPersonalTagRequest request,
  ) {
    personalTagRequests.add(request);
    return personalTagSnapshotOperation!;
  }

  @override
  workspace.SkillsOperation<workspace.RepositorySnapshot> unassignPersonalTag(
    workspace.UnassignPersonalTagRequest request,
  ) {
    personalTagRequests.add(request);
    return personalTagSnapshotOperation!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BackendInstallTakeoverDraft
    implements workspace.InstallTakeoverDraft {
  @override
  workspace.RepositoryRevision get reviewedRevision =>
      workspace.RepositoryRevision(3);

  @override
  List<workspace.OccupiedInstallTarget> get targets => [
    workspace.OccupiedInstallTarget(
      slotKey: 'debug-log-writer',
      location: '/Users/test/.agents/skills',
      targetPath: '/Users/test/.agents/skills/debug-log-writer',
      agentIds: const ['codex'],
      kind: workspace.ActivationTargetOccupancyKind.brokenSymbolicLink,
      contentRelation: workspace.ActivationContentRelation.indeterminate,
      linkTarget: '/legacy/debug-log-writer',
    ),
  ];
}

final class _StaticOperation<T> implements workspace.SkillsOperation<T> {
  _StaticOperation(this._result);

  final workspace.SkillsResult<T> _result;

  @override
  workspace.OperationId get operationId =>
      workspace.OperationId('33333333-3333-4333-8333-333333333333');

  @override
  Stream<workspace.OperationProgress> get progress => const Stream.empty();

  @override
  Future<workspace.SkillsResult<T>> get completed => Future.value(_result);

  @override
  Future<void> cancel() async {}
}

workspace.SkillsOperation<T> _operation<T>(workspace.SkillsResult<T> result) =>
    _StaticOperation(result);

final class _TakeoverDraft implements workspace.ActivationTakeoverDraft {
  const _TakeoverDraft({required this.reviewedRevision, required this.targets});

  @override
  final workspace.RepositoryRevision reviewedRevision;

  @override
  final List<workspace.OccupiedActivationTarget> targets;
}

Future<T> _expectCompleted<T>(WorkspaceTask<T> task) async {
  final completion = await task.completed;
  return switch (completion) {
    WorkspaceCompleted(:final value) => value,
    WorkspaceFailed(:final failure) => fail('Unexpected failure: $failure'),
    WorkspaceCommittedPending(:final operationId) => fail(
      'Unexpected committed-pending operation: $operationId',
    ),
  };
}

Future<T> _expectCompletion<T>(
  Future<WorkspaceCompletion<T>> completion,
) async {
  return switch (await completion) {
    WorkspaceCompleted(:final value) => value,
    WorkspaceFailed(:final failure) => fail('Unexpected failure: $failure'),
    WorkspaceCommittedPending(:final operationId) => fail(
      'Unexpected committed-pending operation: $operationId',
    ),
  };
}

Future<void> _makeWritable(String rootPath) async {
  if (Platform.isWindows) {
    await Process.run('attrib', ['-R', p.join(rootPath, '*'), '/S', '/D']);
    return;
  }
  await Process.run('chmod', ['-R', 'u+w', rootPath]);
}
