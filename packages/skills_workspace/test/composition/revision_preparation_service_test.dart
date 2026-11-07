import 'dart:convert';
import 'dart:io';

import 'package:skills_workspace/src/application/drafts/draft_models.dart';
import 'package:skills_workspace/src/application/drafts/draft_snapshot_coordinator.dart';
import 'package:skills_workspace/src/application/drift/drift_models.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/install/initial_import_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/initial_import_ports.dart';
import 'package:skills_workspace/src/application/ports/update_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/composition/revision_preparation_service.dart';
import 'package:skills_workspace/src/composition/revision_worker_task_executor.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/content/draft_content_adapter.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_recovery_bundle.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker_runtime.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/filesystem/filesystem_draft_snapshot.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';
import 'package:test/test.dart';

import '../support/drift_test_support.dart';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceLayout layout;
  late RevisionWorkerRuntime revisions;
  late WorkspaceRevisionPreparationService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-revision-preparation-',
    );
    layout = WorkspaceLayout(temporaryDirectory.path);
    revisions = RevisionWorkerRuntime(
      taskExecutor: executeComposedRevisionWorkerTask,
    );
    await revisions.start();
    final filesystem = PlatformDurableWorkspaceFilesystem();
    service = WorkspaceRevisionPreparationService(
      revisions: revisions,
      layout: layout,
      filesystem: filesystem,
      drafts: DraftSnapshotCoordinator(
        filesystem: FilesystemDraftSnapshotAdapter(filesystem: filesystem),
        content: const NormalizedDraftContentAdapter(),
      ),
    );
  });

  tearDown(() async {
    await revisions.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<DriftResolutionPreflight> prepareExternalFixture({
    String name = 'sample',
    bool cleanDraft = false,
    bool dirtyDraft = false,
  }) async {
    final store = layout.revisionStorePath(_skillId);
    await revisions.createStore(store);
    final baseTree = _tree(name: 'sample', description: 'Managed');
    final base = await _commitRoot(revisions, store, baseTree);
    final externalTree = _tree(name: name, description: 'External');
    final externalPath = '${temporaryDirectory.path}/external';
    await _writeDraft(externalPath, externalTree);
    if (cleanDraft) {
      await _writeDraft(
        layout.draftPath(_skillId),
        dirtyDraft ? _tree(name: 'sample', description: 'Dirty') : baseTree,
      );
    }
    return driftPreflight(
      skill: cleanDraft
          ? _managedSkill(
              draftPath: layout.draftPath(_skillId),
              contentHash: baseTree.contentHash,
            )
          : driftSkill(),
      state: RestoreRevisionState(
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        currentUpstream: base,
        currentEffective: base,
        managedSkillCreatedAtMicros: 1,
        draftCreatedAtMicros: cleanDraft ? 2 : null,
      ),
      selectedPath: externalPath,
      selectedFingerprint: externalTree.contentHash,
      hadCleanDraft: cleanDraft,
    );
  }

  test(
    'external acceptance produces a verified local publication and recovery Bundle',
    () async {
      final preflight = await prepareExternalFixture();
      final result = await service.prepareAcceptExternal(
        envelope: _envelope('resolveSkillDrift'),
        preflight: preflight,
        cancellationToken: CancellationToken.none(),
      );
      final prepared = result.valueOrNull!;
      expect(prepared.effectiveRequest.kind, RevisionCommitKind.localPublish);
      expect(prepared.effectiveRequest.parents, [
        preflight.state.currentEffective,
      ]);
      expect(prepared.selectedObjectId, preflight.state.currentEffective);
      expect(prepared.draftAction, RestoreDraftAction.noDraft);
      expect(prepared.capturedDraftFingerprint, isNull);
      final store = layout.revisionStorePath(_skillId);
      await revisions.verifyCommit(
        store,
        prepared.effectiveObjectId,
        prepared.effectiveRequest,
      );
      final published = await revisions.readTree(
        store,
        prepared.effectiveObjectId,
      );
      expect(published.contentHash, preflight.selectedFingerprint);
      expect(_text(published, 'SKILL.md'), contains('description: External'));
      final bundle = layout.operationBundleCandidatePath(
        _operationId,
        _skillId,
      );
      final manifest = const RevisionRecoveryBundleCodec().verify(
        manifestBytes: await File('$bundle/manifest.json').readAsBytes(),
        completionFenceBytes: await File('$bundle/COMPLETE').readAsBytes(),
        packBytes: await File('$bundle/objects.pack').readAsBytes(),
        indexBytes: await File('$bundle/objects.idx').readAsBytes(),
      );
      expect(manifest.currentEffective, prepared.effectiveObjectId);
      expect(manifest.currentUpstream, preflight.state.currentUpstream);
      expect(
        await File(
          '${layout.operationTreeCandidatePath(_operationId, _skillId)}/SKILL.md',
        ).readAsString(),
        _text(published, 'SKILL.md'),
      );
      expect(
        await File('${preflight.selectedPath}/SKILL.md').readAsString(),
        _text(published, 'SKILL.md'),
      );
    },
  );

  test(
    'external acceptance preserves clean Draft bytes with cleanup evidence',
    () async {
      final preflight = await prepareExternalFixture(cleanDraft: true);
      final result = await service.prepareAcceptExternal(
        envelope: _envelope('resolveSkillDrift'),
        preflight: preflight,
        cancellationToken: CancellationToken.none(),
      );
      final prepared = result.valueOrNull!;
      expect(prepared.draftAction, RestoreDraftAction.preserveAndReanchor);
      expect(prepared.capturedDraftFingerprint, isNotNull);
      expect(
        await File('${layout.draftPath(_skillId)}/SKILL.md').readAsString(),
        contains('Managed'),
      );
    },
  );

  test('external acceptance rechecks a previously clean Draft', () async {
    final preflight = await prepareExternalFixture(
      cleanDraft: true,
      dirtyDraft: true,
    );
    final result = await service.prepareAcceptExternal(
      envelope: _envelope('resolveSkillDrift'),
      preflight: preflight,
      cancellationToken: CancellationToken.none(),
    );
    expect(
      result.failureOrNull!.code,
      DriftFailureCode.dirtyDraftResolutionRequired,
    );
  });

  test(
    'external acceptance rejects name changes using PublishDraft validation',
    () async {
      final preflight = await prepareExternalFixture(name: 'renamed');
      final result = await service.prepareAcceptExternal(
        envelope: _envelope('resolveSkillDrift'),
        preflight: preflight,
        cancellationToken: CancellationToken.none(),
      );
      expect(
        result.failureOrNull!.code,
        DriftFailureCode.declaredNameChangeNotAllowed,
      );
      expect(
        await Directory(
          layout.operationBundleCandidatePath(_operationId, _skillId),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'external acceptance rejects changed reviewed content before publication',
    () async {
      final preflight = await prepareExternalFixture();
      await File('${preflight.selectedPath}/SKILL.md').writeAsString(
        '---\nname: sample\ndescription: Changed after review\n---\n',
      );
      final result = await service.prepareAcceptExternal(
        envelope: _envelope('resolveSkillDrift'),
        preflight: preflight,
        cancellationToken: CancellationToken.none(),
      );
      expect(result.failureOrNull!.code, DriftFailureCode.staleDriftReview);
      expect(result.failureOrNull!.context['reason'], 'artifactChanged');
      expect(
        await Directory(
          layout.operationBundleCandidatePath(_operationId, _skillId),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'external acceptance reports content limits exceeded after review',
    () async {
      final preflight = await prepareExternalFixture();
      final oversized = await File(
        '${preflight.selectedPath}/oversized.bin',
      ).open(mode: FileMode.write);
      try {
        await oversized.truncate(maximumNormalizedSkillByteSize + 1);
      } finally {
        await oversized.close();
      }
      final result = await service.prepareAcceptExternal(
        envelope: _envelope('resolveSkillDrift'),
        preflight: preflight,
        cancellationToken: CancellationToken.none(),
      );
      expect(
        result.failureOrNull!.code,
        DriftFailureCode.skillContentLimitExceeded,
      );
    },
  );

  test(
    'artifact restore materializes current Effective without a publication or Bundle',
    () async {
      final preflight = await prepareExternalFixture();
      final result = await service.prepareRestoreArtifacts(
        envelope: _envelope('resolveSkillDrift'),
        preflight: preflight,
        cancellationToken: CancellationToken.none(),
      );
      expect(result.valueOrNull, preflight.state.currentEffective);
      expect(
        await File(
          '${layout.operationTreeCandidatePath(_operationId, _skillId)}/SKILL.md',
        ).readAsString(),
        contains('description: Managed'),
      );
      expect(
        await Directory(
          layout.operationBundleCandidatePath(_operationId, _skillId),
        ).exists(),
        isFalse,
      );
      expect(
        await File('${preflight.selectedPath}/SKILL.md').readAsString(),
        contains('description: External'),
      );
    },
  );

  test('drift revision preparation respects preflight cancellation', () async {
    final preflight = await prepareExternalFixture();
    final cancellation = CancellationSource();
    await cancellation.cancel();
    final accept = await service.prepareAcceptExternal(
      envelope: _envelope('resolveSkillDrift'),
      preflight: preflight,
      cancellationToken: cancellation.token,
    );
    final restore = await service.prepareRestoreArtifacts(
      envelope: _envelope('resolveSkillDrift'),
      preflight: preflight,
      cancellationToken: cancellation.token,
    );
    expect(accept.failureOrNull!.code, DriftFailureCode.operationCancelled);
    expect(restore.failureOrNull!.code, DriftFailureCode.operationCancelled);
  });

  test(
    'PublishDraft and external acceptance share verified publication semantics',
    () async {
      final preflight = await prepareExternalFixture();
      final externalTree = _tree(name: 'sample', description: 'External');
      await _writeDraft(layout.draftPath(_skillId), externalTree);
      final draftOperationId = OperationId(
        '123e4567-e89b-42d3-a456-426614174099',
      );
      final draftResult = await service.preparePublishDraft(
        envelope: _envelope('publishDraft', operationId: draftOperationId),
        preflight: PublishDraftPreparationRequired(
          snapshotRevision: preflight.snapshotRevision,
          plannedAtMicros: 2,
          skill: _managedSkill(
            draftPath: layout.draftPath(_skillId),
            contentHash: 'a' * 64,
          ),
          state: DraftRevisionState(
            managedSkillId: _skillId,
            sourceLineage: _lineage,
            currentUpstream: preflight.state.currentUpstream,
            currentEffective: preflight.state.currentEffective,
            managedSkillCreatedAtMicros: 1,
            draftCreatedAtMicros: 2,
          ),
        ),
        cancellationToken: CancellationToken.none(),
      );
      final externalResult = await service.prepareAcceptExternal(
        envelope: _envelope('resolveSkillDrift'),
        preflight: preflight,
        cancellationToken: CancellationToken.none(),
      );
      final draft = draftResult.valueOrNull!;
      final external = externalResult.valueOrNull!;
      expect(draft.contentHash, external.contentHash);
      expect(draft.fileCount, external.fileCount);
      expect(draft.byteSize, external.byteSize);
      expect(draft.effectiveRequest.kind, external.effectiveRequest.kind);
      expect(draft.effectiveRequest.parents, external.effectiveRequest.parents);
      expect(draft.declaredName, external.declaredName);
      expect(draft.description, external.description);
      final store = layout.revisionStorePath(_skillId);
      await revisions.verifyCommit(
        store,
        draft.effectiveObjectId,
        draft.effectiveRequest,
      );
      await revisions.verifyCommit(
        store,
        external.effectiveObjectId,
        external.effectiveRequest,
      );
      expect(
        await File(
          '${layout.operationTreeCandidatePath(draftOperationId, _skillId)}/SKILL.md',
        ).readAsString(),
        await File(
          '${layout.operationTreeCandidatePath(_operationId, _skillId)}/SKILL.md',
        ).readAsString(),
      );
      for (final operationId in [draftOperationId, _operationId]) {
        final bundle = layout.operationBundleCandidatePath(
          operationId,
          _skillId,
        );
        final manifest = const RevisionRecoveryBundleCodec().verify(
          manifestBytes: await File('$bundle/manifest.json').readAsBytes(),
          completionFenceBytes: await File('$bundle/COMPLETE').readAsBytes(),
          packBytes: await File('$bundle/objects.pack').readAsBytes(),
          indexBytes: await File('$bundle/objects.idx').readAsBytes(),
        );
        expect(manifest.currentUpstream, preflight.state.currentUpstream);
        expect(
          (await revisions.readTree(
            store,
            manifest.currentEffective,
          )).contentHash,
          externalTree.contentHash,
        );
      }
    },
  );

  for (final code in RevisionEngineFailureCode.values) {
    test(
      'initial preparation retains ${code.name} as a stable failure detail',
      () async {
        final filesystem = PlatformDurableWorkspaceFilesystem();
        final failing = WorkspaceRevisionPreparationService(
          revisions: _FailingRevisions(code),
          layout: layout,
          filesystem: filesystem,
          drafts: DraftSnapshotCoordinator(
            filesystem: FilesystemDraftSnapshotAdapter(filesystem: filesystem),
            content: const NormalizedDraftContentAdapter(),
          ),
        );
        final result = await failing.prepareInitialRevisions(
          [
            InitialRevisionPreparationIntent(
              managedSkillId: _skillId,
              sourceLineage: _lineage,
              tree: _tree(name: 'sample', description: 'Initial'),
              resolvedSourceRevision: null,
            ),
          ],
          envelope: _envelope('install'),
          cancellationToken: CancellationToken.none(),
        );
        final failure = result as InitialRevisionPreparationFailure;
        expect(
          failure.code,
          InitialRevisionPreparationFailureCode.revisionStoreUnavailable,
        );
        expect(failure.detail, code);
      },
    );
  }

  test(
    'initial preparation creates Store, verified Bundle, and tree',
    () async {
      final tree = _tree(name: 'sample', description: 'Initial description');
      final result = await service.prepareInitialRevisions(
        [
          InitialRevisionPreparationIntent(
            managedSkillId: _skillId,
            sourceLineage: _lineage,
            tree: tree,
            resolvedSourceRevision: null,
          ),
        ],
        envelope: _envelope('install'),
        cancellationToken: CancellationToken.none(),
      );

      expect(result, isA<InitialRevisionPreparationSuccess>());
      final prepared =
          (result as InitialRevisionPreparationSuccess).revisions.single;
      final candidateRoot = layout.operationRevisionCandidateRoot(
        _operationId,
        _skillId,
      );
      final bundle = Directory('$candidateRoot/bundle');
      expect(await Directory('$candidateRoot/store.git').exists(), isTrue);
      expect(await bundle.exists(), isTrue);
      const codec = RevisionRecoveryBundleCodec();
      final verified = codec.verify(
        manifestBytes: await File('${bundle.path}/manifest.json').readAsBytes(),
        completionFenceBytes: await File(
          '${bundle.path}/COMPLETE',
        ).readAsBytes(),
        packBytes: await File('${bundle.path}/objects.pack').readAsBytes(),
        indexBytes: await File('${bundle.path}/objects.idx').readAsBytes(),
      );
      expect(verified.currentUpstream, prepared.objectId);
      expect(verified.currentEffective, prepared.objectId);
      final materialized = File(
        '${layout.operationTreeCandidatePath(_operationId, _skillId)}/SKILL.md',
      );
      expect(await materialized.exists(), isTrue);
      expect(
        await materialized.readAsString(),
        contains('Initial description'),
      );
    },
  );

  test(
    'candidate Abandon Bundle retains published history but excludes Session roots',
    () async {
      final store = layout.revisionStorePath(_skillId);
      await revisions.createStore(store);
      final root = await _commitRoot(
        revisions,
        store,
        _tree(name: 'sample', description: 'Initial'),
      );
      final published = await _commitChild(
        revisions,
        store,
        _tree(name: 'sample', description: 'Published'),
        parent: root,
        kind: RevisionCommitKind.localPublish,
      );
      final incoming = await _commitChild(
        revisions,
        store,
        _tree(name: 'sample', description: 'Incoming'),
        parent: root,
        kind: RevisionCommitKind.upstream,
      );
      final candidate = await _commitChild(
        revisions,
        store,
        _tree(name: 'sample', description: 'Candidate'),
        parent: published,
        kind: RevisionCommitKind.updateCandidate,
      );

      final result = await service.prepareCandidateAbandon(
        operationId: _operationId,
        intent: UpdateCandidateCleanupIntent(
          managedSkillId: _skillId,
          sourceLineage: _lineage,
          previousUpstream: root,
          previousEffective: published,
          incomingUpstream: incoming,
          candidateObjectId: candidate,
          retainedPublishedRoots: <RevisionObjectId>[root, published],
        ),
        cancellationToken: CancellationToken.none(),
      );

      expect(result, isA<UpdateCandidateAbandonPreparationSuccess>());
      final bundle = Directory(
        layout.operationBundleCandidatePath(_operationId, _skillId),
      );
      const codec = RevisionRecoveryBundleCodec();
      final manifest = codec.verify(
        manifestBytes: await File('${bundle.path}/manifest.json').readAsBytes(),
        completionFenceBytes: await File(
          '${bundle.path}/COMPLETE',
        ).readAsBytes(),
        packBytes: await File('${bundle.path}/objects.pack').readAsBytes(),
        indexBytes: await File('${bundle.path}/objects.idx').readAsBytes(),
      );
      expect(manifest.currentUpstream, root);
      expect(manifest.currentEffective, published);
      expect(
        manifest.retainedPublishedRoots,
        <RevisionObjectId>[root, published]
          ..sort((left, right) => left.value.compareTo(right.value)),
      );
      expect(
        manifest.retainedPublishedRoots,
        isNot(containsAll(<RevisionObjectId>[incoming, candidate])),
      );

      final restored = '${temporaryDirectory.path}/abandoned-restored.git';
      await revisions.restoreRecoveryPack(
        stagedRepositoryPath: restored,
        packPath: '${bundle.path}/objects.pack',
        indexPath: '${bundle.path}/objects.idx',
        retainedRoots: manifest.retainedPublishedRoots,
      );
      await revisions.verifyStore(restored);
      expect(await revisions.readTree(restored, published), isNotNull);
      await expectLater(
        revisions.readTree(restored, incoming),
        throwsA(isA<RevisionEngineException>()),
      );
      await expectLater(
        revisions.readTree(restored, candidate),
        throwsA(isA<RevisionEngineException>()),
      );
    },
  );

  test(
    'Windows Draft Publish preserves Base executable intent for existing files',
    () async {
      final store = layout.revisionStorePath(_skillId);
      await revisions.createStore(store);
      final baseTree = _tree(
        name: 'sample',
        description: 'Base',
        extra: const <String, String>{'bin/existing.sh': 'old\n'},
        executablePaths: const <String>{'bin/existing.sh'},
      );
      final baseTreeObject = await revisions.writeTree(store, baseTree);
      final base = await revisions.createCommit(
        store,
        RevisionCommitRequest(
          tree: baseTreeObject,
          parents: const <RevisionObjectId>[],
          kind: RevisionCommitKind.initial,
        ),
      );
      final draftPath = layout.draftPath(_skillId);
      await Directory('$draftPath/bin').create(recursive: true);
      await File('$draftPath/SKILL.md').writeAsString(
        '---\nname: sample\ndescription: Published\n---\n\n# sample\n',
      );
      await File('$draftPath/bin/existing.sh').writeAsString('changed\n');
      await File('$draftPath/bin/new.sh').writeAsString('new\n');
      final windowsService = _windowsService(revisions, layout);

      final result = await windowsService.preparePublishDraft(
        envelope: _envelope('publishDraft'),
        preflight: PublishDraftPreparationRequired(
          snapshotRevision: RepositoryRevision(0),
          plannedAtMicros: 2,
          skill: _managedSkill(
            draftPath: draftPath,
            contentHash: baseTree.contentHash,
          ),
          state: DraftRevisionState(
            managedSkillId: _skillId,
            sourceLineage: _lineage,
            currentUpstream: base,
            currentEffective: base,
            managedSkillCreatedAtMicros: 1,
            draftCreatedAtMicros: 2,
          ),
        ),
        cancellationToken: CancellationToken.none(),
      );

      expect(result, isA<DraftPlanningSuccess<PreparedDraftPublish>>());
      final prepared = result.valueOrNull!;
      final published = await revisions.readTree(
        store,
        prepared.effectiveObjectId,
      );
      expect(
        published.files
            .singleWhere((file) => file.relativePath == 'bin/existing.sh')
            .isExecutable,
        isTrue,
      );
      expect(
        published.files
            .singleWhere((file) => file.relativePath == 'bin/new.sh')
            .isExecutable,
        isFalse,
      );
    },
  );

  test('Windows Update recognizes an executable Base Draft as clean', () async {
    final store = layout.revisionStorePath(_skillId);
    await revisions.createStore(store);
    final baseTree = _tree(
      name: 'sample',
      description: 'Base',
      extra: const <String, String>{'bin/existing.sh': 'base\n'},
      executablePaths: const <String>{'bin/existing.sh'},
    );
    final base = await _commitRoot(revisions, store, baseTree);
    await _writeDraft(layout.draftPath(_skillId), baseTree);

    final result = await _windowsService(revisions, layout).prepareUpdate(
      operationId: _operationId,
      intent: UpdateRevisionPreparationIntent(
        managedSkillId: _skillId,
        expectedRepositoryRevision: RepositoryRevision(0),
        sourceLineage: _lineage,
        previousUpstream: base,
        currentEffective: base,
        currentSlotKey: 'sample',
        currentDeclaredName: 'sample',
        currentDisplayName: 'Sample',
        activations: const <SkillActivation>[],
        managedSkillCreatedAtMicros: 1,
        draftCreatedAtMicros: 2,
        incomingTree: _tree(
          name: 'sample',
          description: 'Incoming',
          extra: const <String, String>{'bin/existing.sh': 'base\n'},
          executablePaths: const <String>{'bin/existing.sh'},
        ),
        incomingDeclaredName: 'sample',
        incomingDescription: 'Incoming',
        incomingSlotKey: 'sample',
        resolvedSourceRevision: null,
        hadCleanDraft: true,
      ),
      cancellationToken: CancellationToken.none(),
    );

    expect(result, isA<UpdateRevisionPreparationSuccess>());
  });

  test(
    'Windows Candidate Publish preserves Candidate executable intent',
    () async {
      final store = layout.revisionStorePath(_skillId);
      await revisions.createStore(store);
      final baseTree = _tree(name: 'sample', description: 'Base');
      final base = await _commitRoot(revisions, store, baseTree);
      final incomingTree = _tree(name: 'sample', description: 'Incoming');
      final incoming = await _commitChild(
        revisions,
        store,
        incomingTree,
        parent: base,
        kind: RevisionCommitKind.upstream,
      );
      final candidateTree = _tree(
        name: 'sample',
        description: 'Resolved',
        extra: const <String, String>{'bin/existing.sh': 'resolved\n'},
        executablePaths: const <String>{'bin/existing.sh'},
      );
      final candidate = await _commitChild(
        revisions,
        store,
        candidateTree,
        parent: base,
        kind: RevisionCommitKind.updateCandidate,
      );
      await _writeDraft(layout.draftPath(_skillId), candidateTree);

      final result = await _windowsService(revisions, layout)
          .prepareCandidatePublish(
            operationId: _operationId,
            intent: UpdateCandidatePublishPreparationIntent(
              managedSkillId: _skillId,
              expectedRepositoryRevision: RepositoryRevision(0),
              sourceLineage: _lineage,
              previousUpstream: base,
              previousEffective: base,
              incomingUpstream: incoming,
              candidateObjectId: candidate,
              requiredDeclaredName: 'sample',
              currentSlotKey: 'sample',
              currentDeclaredName: 'sample',
              currentDisplayName: 'Sample',
              activations: const <SkillActivation>[],
              incomingSlotKey: 'sample',
              incomingDescription: 'Incoming',
              managedSkillCreatedAtMicros: 1,
              draftCreatedAtMicros: 2,
            ),
            cancellationToken: CancellationToken.none(),
          );

      expect(result, isA<UpdateCandidatePublishPreparationSuccess>());
      final published = (result as UpdateCandidatePublishPreparationSuccess)
          .prepared
          .publishedTree;
      expect(
        published.files
            .singleWhere((file) => file.relativePath == 'bin/existing.sh')
            .isExecutable,
        isTrue,
      );
    },
  );

  test(
    'Windows Restore recognizes an executable Base Draft as clean',
    () async {
      final store = layout.revisionStorePath(_skillId);
      await revisions.createStore(store);
      final historicalTree = _tree(name: 'sample', description: 'Historical');
      final historical = await _commitRoot(revisions, store, historicalTree);
      final currentTree = _tree(
        name: 'sample',
        description: 'Current',
        extra: const <String, String>{'bin/existing.sh': 'current\n'},
        executablePaths: const <String>{'bin/existing.sh'},
      );
      final current = await _commitChild(
        revisions,
        store,
        currentTree,
        parent: historical,
        kind: RevisionCommitKind.localPublish,
      );
      final draftPath = layout.draftPath(_skillId);
      await _writeDraft(draftPath, currentTree);

      final result = await _windowsService(revisions, layout)
          .prepareRestorePublish(
            envelope: _envelope('restorePublish'),
            preflight: RestorePublishPreflight(
              snapshotRevision: RepositoryRevision(0),
              plannedAtMicros: 2,
              skill: _managedSkill(
                draftPath: draftPath,
                contentHash: currentTree.contentHash,
              ),
              selected: HistoricalRevisionSelection(
                reference: OperationSubjectReference(
                  operationId: _operationId,
                  subjectId: '123e4567-e89b-42d3-a456-426614174021',
                ),
                managedSkillId: _skillId,
                sourceLineage: _lineage,
                objectId: historical,
                contentHash: historicalTree.contentHash,
                declaredName: 'sample',
              ),
              state: RestoreRevisionState(
                managedSkillId: _skillId,
                sourceLineage: _lineage,
                currentUpstream: historical,
                currentEffective: current,
                managedSkillCreatedAtMicros: 1,
                draftCreatedAtMicros: 2,
              ),
              hadCleanDraft: true,
            ),
            cancellationToken: CancellationToken.none(),
          );

      expect(result, isA<HistorySuccess<PreparedRestorePublish>>());
    },
  );

  test(
    'conflicted Update keeps auto-merged bytes in an unresolved candidate',
    () async {
      final store = layout.revisionStorePath(_skillId);
      await revisions.createStore(store);
      final baseTree = _tree(name: 'sample', description: 'Base');
      final baseTreeObject = await revisions.writeTree(store, baseTree);
      final rootRequest = RevisionCommitRequest(
        tree: baseTreeObject,
        parents: const [],
        kind: RevisionCommitKind.initial,
      );
      final root = await revisions.createCommit(store, rootRequest);
      final localTree = _tree(
        name: 'sample',
        description: 'Local',
        extra: const {'local.md': 'local\n'},
      );
      final localTreeObject = await revisions.writeTree(store, localTree);
      final localRequest = RevisionCommitRequest(
        tree: localTreeObject,
        parents: [root],
        kind: RevisionCommitKind.localPublish,
      );
      final local = await revisions.createCommit(store, localRequest);
      final incomingTree = _tree(
        name: 'sample',
        description: 'Incoming',
        extra: const {'upstream.md': 'upstream\n'},
      );

      final result = await service.prepareUpdate(
        operationId: _operationId,
        intent: UpdateRevisionPreparationIntent(
          managedSkillId: _skillId,
          expectedRepositoryRevision: RepositoryRevision(0),
          sourceLineage: _lineage,
          previousUpstream: root,
          currentEffective: local,
          currentSlotKey: 'sample',
          currentDeclaredName: 'sample',
          currentDisplayName: 'Sample',
          activations: const [],
          managedSkillCreatedAtMicros: 1,
          draftCreatedAtMicros: null,
          incomingTree: incomingTree,
          incomingDeclaredName: 'sample',
          incomingDescription: 'Incoming',
          incomingSlotKey: 'sample',
          resolvedSourceRevision: null,
          hadCleanDraft: false,
        ),
        cancellationToken: CancellationToken.none(),
      );

      expect(
        result,
        isA<UpdateRevisionPreparationSuccess>(),
        reason: result is UpdateRevisionPreparationFailure
            ? result.code.name
            : '$result',
      );
      final prepared = (result as UpdateRevisionPreparationSuccess).prepared;
      final conflict = prepared.outcome as PreparedUpdateConflict;
      expect(
        conflict.conflicts.single.state,
        WorkspaceUpdateCandidateItemState.unresolved,
      );
      final candidate = await revisions.readTree(
        store,
        conflict.candidateObjectId,
      );
      expect(_text(candidate, 'SKILL.md'), contains('description: Local'));
      expect(_text(candidate, 'local.md'), 'local\n');
      expect(_text(candidate, 'upstream.md'), 'upstream\n');
      expect(
        await File(
          '${layout.operationBundleCandidatePath(_operationId, _skillId)}/COMPLETE',
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'clean merge exceeding Skill limits becomes a validation Session candidate',
    () async {
      final store = layout.revisionStorePath(_skillId);
      await revisions.createStore(store);
      final sharedFiles = <String, String>{
        for (var index = 0; index < 998; index += 1)
          'shared/$index.md': 'shared\n',
      };
      final baseTree = _tree(
        name: 'sample',
        description: 'Base',
        extra: sharedFiles,
      );
      final baseTreeObject = await revisions.writeTree(store, baseTree);
      final rootRequest = RevisionCommitRequest(
        tree: baseTreeObject,
        parents: const [],
        kind: RevisionCommitKind.initial,
      );
      final root = await revisions.createCommit(store, rootRequest);
      final localTree = _tree(
        name: 'sample',
        description: 'Base',
        extra: <String, String>{...sharedFiles, 'local.md': 'local\n'},
      );
      final localTreeObject = await revisions.writeTree(store, localTree);
      final local = await revisions.createCommit(
        store,
        RevisionCommitRequest(
          tree: localTreeObject,
          parents: [root],
          kind: RevisionCommitKind.localPublish,
        ),
      );
      final incomingTree = _tree(
        name: 'sample',
        description: 'Base',
        extra: <String, String>{...sharedFiles, 'upstream.md': 'upstream\n'},
      );

      final result = await service.prepareUpdate(
        operationId: _operationId,
        intent: UpdateRevisionPreparationIntent(
          managedSkillId: _skillId,
          expectedRepositoryRevision: RepositoryRevision(0),
          sourceLineage: _lineage,
          previousUpstream: root,
          currentEffective: local,
          currentSlotKey: 'sample',
          currentDeclaredName: 'sample',
          currentDisplayName: 'Sample',
          activations: const [],
          managedSkillCreatedAtMicros: 1,
          draftCreatedAtMicros: null,
          incomingTree: incomingTree,
          incomingDeclaredName: 'sample',
          incomingDescription: 'Base',
          incomingSlotKey: 'sample',
          resolvedSourceRevision: null,
          hadCleanDraft: false,
        ),
        cancellationToken: CancellationToken.none(),
      );

      expect(
        result,
        isA<UpdateRevisionPreparationSuccess>(),
        reason: result is UpdateRevisionPreparationFailure
            ? result.code.name
            : '$result',
      );
      final prepared = (result as UpdateRevisionPreparationSuccess).prepared;
      final failure = prepared.outcome as PreparedUpdateValidationFailure;
      expect(failure.validationCode, 'mergedSkillFileLimitExceeded');
      expect(failure.candidateTree.fileCount, 1001);
      final persistedCandidate = await revisions.readTree(
        store,
        failure.candidateObjectId,
      );
      expect(persistedCandidate.contentHash, failure.candidateTree.contentHash);
      expect(persistedCandidate.fileCount, failure.candidateTree.fileCount);
      expect(
        await File(
          '${layout.operationBundleCandidatePath(_operationId, _skillId)}/COMPLETE',
        ).exists(),
        isTrue,
      );
    },
    timeout: Timeout(
      Platform.isWindows
          ? const Duration(minutes: 2)
          : const Duration(seconds: 30),
    ),
  );
}

PreparedOperationEnvelope _envelope(String kind, {OperationId? operationId}) =>
    PreparedOperationEnvelope(
      operationId: operationId ?? _operationId,
      expectedRepositoryRevision: RepositoryRevision(0),
      committedRepositoryRevision: RepositoryRevision(1),
      operationGeneration: 1,
      preparationSteps: [
        PreparationOperationStep(
          stepId: 'candidate',
          recoveryReference: operationRecoveryReference(
            operationId ?? _operationId,
            'candidate-${_skillId.value}',
          ),
          kind: PreparationStepKind.revisionCandidate,
        ),
        PreparationOperationStep(
          stepId: 'bundle',
          recoveryReference: operationRecoveryReference(
            operationId ?? _operationId,
            'bundle-${_skillId.value}',
          ),
          kind: PreparationStepKind.recoveryEvidence,
        ),
      ],
      record: OperationRecordPlan(
        operationId: operationId ?? _operationId,
        kind: kind,
        subjects: const [],
        retainWithoutSubjects: true,
      ),
    );

NormalizedSkillTree _tree({
  required String name,
  required String description,
  Map<String, String> extra = const {},
  Set<String> executablePaths = const <String>{},
}) {
  final entries = <SkillContentEntry>[
    SkillContentEntry.file(
      path: 'SKILL.md',
      bytes: utf8.encode(
        '---\nname: $name\ndescription: $description\n---\n\n# $name\n',
      ),
      isExecutable: false,
    ),
    for (final entry in extra.entries)
      SkillContentEntry.file(
        path: entry.key,
        bytes: utf8.encode(entry.value),
        isExecutable: executablePaths.contains(entry.key),
      ),
  ];
  return const SkillContentNormalizer().normalize(entries).valueOrNull!;
}

ManagedSkill _managedSkill({
  required String draftPath,
  required String contentHash,
}) => ManagedSkill(
  id: _skillId,
  slotKey: 'sample',
  declaredName: 'sample',
  displayName: 'Sample',
  description: 'Base',
  source: LocalSourceDescriptor(locator: Directory.systemTemp.path),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: contentHash,
    fileCount: 2,
    byteSize: 1,
    publishedAt: DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true),
  ),
  draft: DraftSummary(
    purpose: DraftPurpose.customization,
    path: draftPath,
    isDirty: true,
    updatedAt: DateTime.fromMicrosecondsSinceEpoch(2, isUtc: true),
  ),
);

String _text(NormalizedSkillTree tree, String path) => utf8.decode(
  tree.files.singleWhere((file) => file.relativePath == path).bytes,
);

WorkspaceRevisionPreparationService _windowsService(
  RevisionWorkerRuntime revisions,
  WorkspaceLayout layout,
) => WorkspaceRevisionPreparationService(
  revisions: revisions,
  layout: layout,
  filesystem: PlatformDurableWorkspaceFilesystem(),
  drafts: DraftSnapshotCoordinator(
    filesystem: FilesystemDraftSnapshotAdapter(),
    content: const NormalizedDraftContentAdapter(),
  ),
  capturePosixExecutableIntent: false,
);

Future<RevisionObjectId> _commitRoot(
  RevisionWorkerRuntime revisions,
  String store,
  NormalizedSkillTree tree,
) async {
  final treeObject = await revisions.writeTree(store, tree);
  return revisions.createCommit(
    store,
    RevisionCommitRequest(
      tree: treeObject,
      parents: const <RevisionObjectId>[],
      kind: RevisionCommitKind.initial,
    ),
  );
}

Future<RevisionObjectId> _commitChild(
  RevisionWorkerRuntime revisions,
  String store,
  NormalizedSkillTree tree, {
  required RevisionObjectId parent,
  required RevisionCommitKind kind,
}) async {
  final treeObject = await revisions.writeTree(store, tree);
  return revisions.createCommit(
    store,
    RevisionCommitRequest(
      tree: treeObject,
      parents: <RevisionObjectId>[parent],
      kind: kind,
    ),
  );
}

Future<void> _writeDraft(String draftPath, NormalizedSkillTree tree) async {
  for (final file in tree.files) {
    final target = File('$draftPath/${file.relativePath}');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(file.bytes, flush: true);
  }
}

final _operationId = OperationId('123e4567-e89b-42d3-a456-426614174020');
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _lineage = SourceLineageReference('123e4567-e89b-42d3-8456-426614174001');

final class _FailingRevisions implements RevisionEnginePort {
  _FailingRevisions(this.code);
  final RevisionEngineFailureCode code;

  @override
  Future<void> createStore(String repositoryPath) async =>
      throw RevisionEngineException(code);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
