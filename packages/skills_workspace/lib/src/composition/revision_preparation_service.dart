import 'dart:convert';
import 'dart:io';

import '../application/drift/drift_models.dart';
import '../application/drafts/draft_models.dart';
import '../application/drafts/draft_ports.dart';
import '../application/drafts/draft_snapshot_coordinator.dart';
import '../application/history/history_models.dart';
import '../application/history/history_ports.dart';
import '../application/install/initial_import_models.dart';
import '../application/operations/operation_models.dart';
import '../application/operations/workspace_business_changes.dart';
import '../application/ports/initial_import_ports.dart';
import '../application/ports/draft_snapshot_ports.dart';
import '../application/ports/update_ports.dart';
import '../application/runtime/revision_engine_port.dart';
import '../application/update/update_models.dart';
import '../domain/cancellation.dart';
import '../domain/draft_snapshot.dart';
import '../domain/identifiers.dart';
import '../infrastructure/source/frontmatter_parser.dart';
import '../infrastructure/source/source_models.dart';
import '../infrastructure/content/normalized_skill_tree.dart';
import '../infrastructure/workspace_layout.dart';
import '../native/revision_engine/revision_recovery_bundle.dart';
import '../platform/filesystem/durable_workspace_filesystem.dart';
import '../platform/operations/operation_recovery_bundle.dart';
import 'revision_recovery_bundle_publisher.dart';

/// Shared Revision preparation adapter for Install, Draft, Update and Restore.
///
/// It creates immutable Git objects only after a Prepared envelope exists. All
/// candidate paths are operation-owned staging paths; SQLite and Agent-visible
/// materializations remain the responsibility of the sealed OperationPlan.
final class WorkspaceRevisionPreparationService
    implements
        InitialRevisionCandidatePort,
        DraftRevisionPreparationPort,
        UpdateRevisionPreparationPort,
        RestoreRevisionPreparationPort,
        DriftRevisionPreparationPort {
  WorkspaceRevisionPreparationService({
    required RevisionEnginePort revisions,
    required WorkspaceLayout layout,
    required DurableWorkspaceFilesystem filesystem,
    required DraftSnapshotCoordinator drafts,
    bool? capturePosixExecutableIntent,
    RevisionRecoveryBundleCodec bundleCodec =
        const RevisionRecoveryBundleCodec(),
  }) : _revisions = revisions,
       _layout = layout,
       _filesystem = filesystem,
       _drafts = drafts,
       _capturePosixExecutableIntent =
           capturePosixExecutableIntent ?? !Platform.isWindows,
       _bundleCodec = bundleCodec;

  final RevisionEnginePort _revisions;
  final WorkspaceLayout _layout;
  final DurableWorkspaceFilesystem _filesystem;
  final DraftSnapshotCoordinator _drafts;
  final bool _capturePosixExecutableIntent;
  final RevisionRecoveryBundleCodec _bundleCodec;

  @override
  Future<InitialRevisionPreparationResult> prepareInitialRevisions(
    List<InitialRevisionPreparationIntent> intents, {
    required PreparedOperationEnvelope envelope,
    required CancellationToken cancellationToken,
  }) async {
    final prepared = <PreparedInitialRevision>[];
    try {
      for (final intent in intents) {
        _throwIfCancelled(cancellationToken);
        final root = _candidateRoot(
          envelope.operationId,
          intent.managedSkillId,
        );
        final store = '$root/store.git';
        final bundle = '$root/bundle';
        final evidence = await _createStoreAndBundle(
          operationId: envelope.operationId,
          store: store,
          bundle: bundle,
          tree: intent.tree,
          sourceLineage: intent.sourceLineage,
          parent: null,
          kind: RevisionCommitKind.initial,
          retainedRoots: (commit) => [commit],
          cancellationToken: cancellationToken,
        );
        await _writeTree(
          _candidateMaterializationPath(
            envelope.operationId,
            intent.managedSkillId,
          ),
          intent.tree,
          cancellationToken,
        );
        prepared.add(
          PreparedInitialRevision(
            managedSkillId: intent.managedSkillId,
            sourceLineage: intent.sourceLineage,
            objectId: evidence.commit,
            objectFormat: WorkspaceObjectFormat.sha1,
            candidateRecoveryReference: operationRecoveryReference(
              envelope.operationId,
              'candidate-${intent.managedSkillId.value}',
            ),
            bundleRecoveryReference: operationRecoveryReference(
              envelope.operationId,
              'bundle-${intent.managedSkillId.value}',
            ),
          ),
        );
      }
      return InitialRevisionPreparationSuccess(prepared);
    } on _PreparationCancelled {
      return const InitialRevisionPreparationFailure(
        InitialRevisionPreparationFailureCode.operationCancelled,
      );
    } on RevisionEngineException catch (error) {
      return InitialRevisionPreparationFailure(
        InitialRevisionPreparationFailureCode.revisionStoreUnavailable,
        detail: error.code,
      );
    } on Object {
      return const InitialRevisionPreparationFailure(
        InitialRevisionPreparationFailureCode.ioFailure,
      );
    }
  }

  @override
  Future<DraftPlanningResult<PreparedEnsureDraft>> prepareEnsureDraft({
    required PreparedOperationEnvelope envelope,
    required EnsureDraftPreparationRequired preflight,
    required CancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);
      final store = _storePath(preflight.skill.id);
      final tree = await _revisions.readTree(
        store,
        preflight.state.currentEffective,
      );
      final draftPath = _candidateDraftPath(
        envelope.operationId,
        preflight.skill.id,
      );
      await _writeTree(draftPath, tree, cancellationToken);
      return DraftPlanningSuccess(
        PreparedEnsureDraft(
          managedSkillId: preflight.skill.id,
          sourceLineage: preflight.state.sourceLineage,
          baseObjectId: preflight.state.currentEffective,
          draftRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'draft-${preflight.skill.id.value}',
          ),
        ),
      );
    } on _PreparationCancelled {
      return DraftPlanningFailure(
        code: DraftPlanningFailureCode.operationCancelled,
      );
    } on RevisionEngineException catch (error) {
      return DraftPlanningFailure(
        code: DraftPlanningFailureCode.revisionStoreUnavailable,
        context: {'detail': error.code.name},
      );
    } on Object {
      return DraftPlanningFailure(code: DraftPlanningFailureCode.ioFailure);
    }
  }

  @override
  Future<DraftPlanningResult<PreparedDraftPublish>> preparePublishDraft({
    required PreparedOperationEnvelope envelope,
    required PublishDraftPreparationRequired preflight,
    required CancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);
      final store = _storePath(preflight.skill.id);
      final executableIntentOverrides = <String, bool>{};
      if (!_capturePosixExecutableIntent) {
        final base = await _revisions.readTree(
          store,
          preflight.state.currentEffective,
        );
        executableIntentOverrides.addEntries(
          base.files.map(
            (file) => MapEntry(file.relativePath, file.isExecutable),
          ),
        );
      }
      final capture = await _drafts.captureForDirectPublish(
        request: DraftCaptureRequest(
          liveDraftPath: preflight.skill.draft!.path,
          stagingDestinationPath: _candidateDraftPath(
            envelope.operationId,
            preflight.skill.id,
          ),
          capturePosixExecutableIntent: _capturePosixExecutableIntent,
          executableIntentOverrides: executableIntentOverrides,
          isCancelled: () => cancellationToken.isCancelled,
        ),
        expectedDeclaredName: preflight.skill.declaredName,
      );
      if (capture.failureOrNull case final failure?) {
        return DraftPlanningFailure(
          code: _draftFailure(failure.code),
          context: failure.context,
        );
      }
      final snapshot = capture.valueOrNull!;
      final tree = snapshot.normalizedTree;
      final published = await _publishCapturedTree(
        envelope: envelope,
        managedSkillId: preflight.skill.id,
        sourceLineage: preflight.state.sourceLineage,
        currentUpstream: preflight.state.currentUpstream,
        currentEffective: preflight.state.currentEffective,
        tree: tree,
        kind: RevisionCommitKind.localPublish,
        cancellationToken: cancellationToken,
      );
      final (treeObject, commit, request) = published;
      return DraftPlanningSuccess(
        PreparedDraftPublish(
          managedSkillId: preflight.skill.id,
          sourceLineage: preflight.state.sourceLineage,
          treeObjectId: treeObject,
          effectiveObjectId: commit,
          effectiveRequest: request,
          contentHash: tree.contentHash,
          fileCount: tree.fileCount,
          byteSize: tree.byteSize,
          declaredName: snapshot.declaredName,
          description: _description(tree),
          // The BCP always re-anchors the row. Finalization owns the durable
          // compare-and-delete against this exact captured Draft snapshot.
          draftAction: PublishedDraftAction.preserveAndReanchor,
          capturedDraftFingerprint: snapshot.capture.fingerprint,
          candidateRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'candidate-${preflight.skill.id.value}',
          ),
          bundleRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'bundle-${preflight.skill.id.value}',
          ),
          materializationRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'materialization-${preflight.skill.id.value}',
          ),
          draftRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'draft-${preflight.skill.id.value}',
          ),
        ),
      );
    } on _PreparationCancelled {
      return DraftPlanningFailure(
        code: DraftPlanningFailureCode.operationCancelled,
      );
    } on RevisionEngineException catch (error) {
      return DraftPlanningFailure(
        code: DraftPlanningFailureCode.revisionStoreUnavailable,
        context: {'detail': error.code.name},
      );
    } on Object {
      return DraftPlanningFailure(code: DraftPlanningFailureCode.ioFailure);
    }
  }

  Future<(RevisionObjectId, RevisionObjectId, RevisionCommitRequest)>
  _publishCapturedTree({
    required PreparedOperationEnvelope envelope,
    required ManagedSkillId managedSkillId,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required NormalizedSkillTree tree,
    required RevisionCommitKind kind,
    required CancellationToken cancellationToken,
  }) async {
    final store = _storePath(managedSkillId);
    final treeObject = await _revisions.writeTree(store, tree);
    final request = RevisionCommitRequest(
      tree: treeObject,
      parents: [currentEffective],
      kind: kind,
    );
    final commit = await _revisions.createCommit(store, request);
    await _revisions.verifyCommit(store, commit, request);
    await _writeRecoveryBundle(
      operationId: envelope.operationId,
      managedSkillId: managedSkillId,
      store: store,
      sourceLineage: sourceLineage,
      currentUpstream: currentUpstream,
      currentEffective: commit,
      retainedRoots: <RevisionObjectId>[commit],
    );
    await _writeTree(
      _candidateMaterializationPath(envelope.operationId, managedSkillId),
      tree,
      cancellationToken,
    );
    return (treeObject, commit, request);
  }

  @override
  Future<DriftResult<PreparedRestorePublish>> prepareAcceptExternal({
    required PreparedOperationEnvelope envelope,
    required DriftResolutionPreflight preflight,
    required CancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);
      final store = _storePath(preflight.skill.id);
      final base = await _revisions.readTree(
        store,
        preflight.state.currentEffective,
      );
      DraftFingerprint? cleanDraftFingerprint;
      if (preflight.hadCleanDraft) {
        final inspected = await _drafts.inspectForCleanup(
          request: DraftCaptureRequest(
            liveDraftPath: _layout.draftPath(preflight.skill.id),
            stagingDestinationPath: _candidateDraftPath(
              envelope.operationId,
              preflight.skill.id,
            ),
            capturePosixExecutableIntent: _capturePosixExecutableIntent,
            executableIntentOverrides: _executableIntentOverrides(base),
            isCancelled: () => cancellationToken.isCancelled,
          ),
          draftBase: base,
        );
        if (inspected.failureOrNull case final failure?) {
          return _driftCaptureFailure(failure);
        }
        if (inspected.valueOrNull!.isDirty) {
          return DriftFailure(
            code: DriftFailureCode.dirtyDraftResolutionRequired,
          );
        }
        cleanDraftFingerprint = inspected.valueOrNull!.cleanupFingerprint;
      }
      final capture = await _drafts.captureForDirectPublish(
        request: DraftCaptureRequest(
          liveDraftPath: preflight.selectedPath!,
          stagingDestinationPath: _candidateDraftPath(
            envelope.operationId,
            preflight.skill.id,
          ),
          capturePosixExecutableIntent: _capturePosixExecutableIntent,
          executableIntentOverrides: _executableIntentOverrides(base),
          isCancelled: () => cancellationToken.isCancelled,
        ),
        expectedDeclaredName: preflight.skill.declaredName,
      );
      if (capture.failureOrNull case final failure?) {
        return _driftCaptureFailure(failure);
      }
      final tree = capture.valueOrNull!.normalizedTree;
      if (tree.contentHash != preflight.selectedFingerprint) {
        return DriftFailure(
          code: DriftFailureCode.staleDriftReview,
          context: const {'reason': 'artifactChanged'},
        );
      }
      final (treeObject, commit, request) = await _publishCapturedTree(
        envelope: envelope,
        managedSkillId: preflight.skill.id,
        sourceLineage: preflight.state.sourceLineage,
        currentUpstream: preflight.state.currentUpstream,
        currentEffective: preflight.state.currentEffective,
        tree: tree,
        kind: RevisionCommitKind.localPublish,
        cancellationToken: cancellationToken,
      );
      return DriftSuccess(
        value: PreparedRestorePublish(
          managedSkillId: preflight.skill.id,
          sourceLineage: preflight.state.sourceLineage,
          selectedObjectId: preflight.state.currentEffective,
          treeObjectId: treeObject,
          effectiveObjectId: commit,
          effectiveRequest: request,
          contentHash: tree.contentHash,
          fileCount: tree.fileCount,
          byteSize: tree.byteSize,
          declaredName: capture.valueOrNull!.declaredName,
          description: _description(tree),
          draftAction: preflight.hadCleanDraft
              ? RestoreDraftAction.preserveAndReanchor
              : RestoreDraftAction.noDraft,
          capturedDraftFingerprint: cleanDraftFingerprint,
          candidateRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'candidate-${preflight.skill.id.value}',
          ),
          bundleRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'bundle-${preflight.skill.id.value}',
          ),
          materializationRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'materialization-${preflight.skill.id.value}',
          ),
          draftRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'draft-${preflight.skill.id.value}',
          ),
        ),
      );
    } on _PreparationCancelled {
      return DriftFailure(code: DriftFailureCode.operationCancelled);
    } on RevisionEngineException catch (error) {
      return DriftFailure(
        code: DriftFailureCode.revisionStoreCorrupt,
        context: {'detail': error.code.name},
      );
    } on Object {
      return DriftFailure(code: DriftFailureCode.ioFailure);
    }
  }

  @override
  Future<DriftResult<RevisionObjectId>> prepareRestoreArtifacts({
    required PreparedOperationEnvelope envelope,
    required DriftResolutionPreflight preflight,
    required CancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);
      final tree = await _revisions.readTree(
        _storePath(preflight.skill.id),
        preflight.state.currentEffective,
      );
      await _writeTree(
        _candidateMaterializationPath(envelope.operationId, preflight.skill.id),
        tree,
        cancellationToken,
      );
      return DriftSuccess(value: preflight.state.currentEffective);
    } on _PreparationCancelled {
      return DriftFailure(code: DriftFailureCode.operationCancelled);
    } on RevisionEngineException catch (error) {
      return DriftFailure(
        code: DriftFailureCode.revisionStoreCorrupt,
        context: {'detail': error.code.name},
      );
    } on Object {
      return DriftFailure(code: DriftFailureCode.ioFailure);
    }
  }

  DriftFailure<T> _driftCaptureFailure<T>(
    DraftSnapshotFailure<Object?> failure,
  ) => DriftFailure(
    code: switch (failure.code) {
      DraftSnapshotFailureCode.draftChangedDuringPublish =>
        DriftFailureCode.staleDriftReview,
      DraftSnapshotFailureCode.skillContentLimitExceeded =>
        DriftFailureCode.skillContentLimitExceeded,
      DraftSnapshotFailureCode.operationCancelled =>
        DriftFailureCode.operationCancelled,
      DraftSnapshotFailureCode.declaredNameChangeNotAllowed =>
        DriftFailureCode.declaredNameChangeNotAllowed,
      DraftSnapshotFailureCode.historicalNameMismatch =>
        DriftFailureCode.historicalNameMismatch,
      DraftSnapshotFailureCode.invalidSkill => DriftFailureCode.invalidSkill,
      DraftSnapshotFailureCode.ioFailure => DriftFailureCode.ioFailure,
    },
    context: failure.code == DraftSnapshotFailureCode.draftChangedDuringPublish
        ? const {'reason': 'artifactChanged'}
        : failure.context,
  );

  @override
  Future<UpdateRevisionPreparationResult> prepareUpdate({
    required OperationId operationId,
    required UpdateRevisionPreparationIntent intent,
    required CancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);
      final store = _storePath(intent.managedSkillId);
      DraftFingerprint? cleanDraftFingerprint;
      if (intent.hadCleanDraft) {
        final base = await _revisions.readTree(store, intent.currentEffective);
        final inspected = await _drafts.inspectForCleanup(
          request: DraftCaptureRequest(
            liveDraftPath: _layout.draftPath(intent.managedSkillId),
            stagingDestinationPath: _candidateDraftPath(
              operationId,
              intent.managedSkillId,
            ),
            capturePosixExecutableIntent: _capturePosixExecutableIntent,
            executableIntentOverrides: _executableIntentOverrides(base),
            isCancelled: () => cancellationToken.isCancelled,
          ),
          draftBase: base,
        );
        if (inspected.failureOrNull case final failure?) {
          return UpdateRevisionPreparationFailure(
            _updateDraftFailure(failure.code),
          );
        }
        if (inspected.valueOrNull!.isDirty) {
          return UpdateRevisionPreparationFailure(
            UpdateRevisionPreparationFailureCode.dirtyDraftResolutionRequired,
          );
        }
        cleanDraftFingerprint = inspected.valueOrNull!.cleanupFingerprint;
      }
      final incomingTreeObject = await _revisions.writeTree(
        store,
        intent.incomingTree,
      );
      final incomingRequest = RevisionCommitRequest(
        tree: incomingTreeObject,
        parents: [intent.previousUpstream],
        kind: RevisionCommitKind.upstream,
      );
      final incoming = await _revisions.createCommit(store, incomingRequest);
      await _revisions.verifyCommit(store, incoming, incomingRequest);
      final merged = await _revisions.merge(
        repositoryPath: store,
        previousUpstream: intent.previousUpstream,
        currentEffective: intent.currentEffective,
        incomingUpstream: incoming,
      );
      final outcome = switch (merged) {
        RevisionMergeClean(:final tree) => await _cleanUpdateOutcome(
          store: store,
          treeObject: tree,
          intent: intent,
          incoming: incoming,
          cancellationToken: cancellationToken,
          capturedDraftFingerprint: cleanDraftFingerprint,
        ),
        RevisionMergeConflicted(:final tree, :final conflicts) =>
          PreparedUpdateConflict(
            candidateObjectId: await _createCandidateCommit(
              store: store,
              tree: tree,
              parent: intent.currentEffective,
            ),
            candidateTree: await _revisions.readTree(store, tree),
            conflicts: [
              for (final conflict in conflicts)
                WorkspaceUpdateCandidateItem(
                  path:
                      conflict.currentPath ??
                      conflict.incomingPath ??
                      conflict.ancestorPath ??
                      'SKILL.md',
                  kind: _conflictKind(conflict),
                  state: WorkspaceUpdateCandidateItemState.unresolved,
                  baseObjectId: null,
                  oursObjectId: null,
                  theirsObjectId: null,
                ),
            ],
          ),
      };
      final retainedRoots = switch (outcome) {
        PreparedUpdateClean(:final effectiveObjectId) => <RevisionObjectId>[
          effectiveObjectId,
        ],
        PreparedUpdateConflict(:final candidateObjectId) => <RevisionObjectId>[
          intent.previousUpstream,
          intent.currentEffective,
          incoming,
          candidateObjectId,
        ],
        PreparedUpdateValidationFailure(:final candidateObjectId) =>
          <RevisionObjectId>[
            intent.previousUpstream,
            intent.currentEffective,
            incoming,
            candidateObjectId,
          ],
      };
      final materializedTree = switch (outcome) {
        PreparedUpdateClean(:final mergedTree) => mergedTree,
        PreparedUpdateConflict(:final candidateTree) => candidateTree,
        PreparedUpdateValidationFailure(:final candidateTree) => candidateTree,
      };
      final currentPointers = switch (outcome) {
        PreparedUpdateClean(:final effectiveObjectId) => (
          upstream: incoming,
          effective: effectiveObjectId,
        ),
        PreparedUpdateConflict() || PreparedUpdateValidationFailure() => (
          upstream: intent.previousUpstream,
          effective: intent.currentEffective,
        ),
      };
      await _writeRecoveryBundle(
        operationId: operationId,
        managedSkillId: intent.managedSkillId,
        store: store,
        sourceLineage: intent.sourceLineage,
        currentUpstream: currentPointers.upstream,
        currentEffective: currentPointers.effective,
        retainedRoots: retainedRoots,
      );
      await _writeTree(
        _candidateMaterializationPath(operationId, intent.managedSkillId),
        materializedTree,
        cancellationToken,
      );
      return UpdateRevisionPreparationSuccess(
        PreparedUpdateRevision(
          managedSkillId: intent.managedSkillId,
          sourceLineage: intent.sourceLineage,
          incomingTreeObjectId: incomingTreeObject,
          incomingUpstreamObjectId: incoming,
          incomingRequest: incomingRequest,
          outcome: outcome,
          candidateRecoveryReference: operationRecoveryReference(
            operationId,
            'candidate-${intent.managedSkillId.value}',
          ),
          bundleRecoveryReference: operationRecoveryReference(
            operationId,
            'bundle-${intent.managedSkillId.value}',
          ),
          materializationRecoveryReference: operationRecoveryReference(
            operationId,
            'materialization-${intent.managedSkillId.value}',
          ),
          draftRecoveryReference: operationRecoveryReference(
            operationId,
            'draft-${intent.managedSkillId.value}',
          ),
        ),
      );
    } on _PreparationCancelled {
      return UpdateRevisionPreparationFailure(
        UpdateRevisionPreparationFailureCode.operationCancelled,
      );
    } on RevisionEngineException catch (error) {
      return UpdateRevisionPreparationFailure(
        UpdateRevisionPreparationFailureCode.revisionStoreUnavailable,
        detail: error.code,
      );
    } on Object {
      return UpdateRevisionPreparationFailure(
        UpdateRevisionPreparationFailureCode.ioFailure,
      );
    }
  }

  @override
  Future<UpdateCandidatePublishPreparationResult> prepareCandidatePublish({
    required OperationId operationId,
    required UpdateCandidatePublishPreparationIntent intent,
    required CancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);
      final store = _storePath(intent.managedSkillId);
      final executableIntentOverrides = <String, bool>{};
      if (!_capturePosixExecutableIntent) {
        final base = await _revisions.readTree(store, intent.candidateObjectId);
        executableIntentOverrides.addAll(_executableIntentOverrides(base));
      }
      final capture = await _drafts.captureForDirectPublish(
        request: DraftCaptureRequest(
          liveDraftPath: _layout.draftPath(intent.managedSkillId),
          stagingDestinationPath: _candidateDraftPath(
            operationId,
            intent.managedSkillId,
          ),
          capturePosixExecutableIntent: _capturePosixExecutableIntent,
          executableIntentOverrides: executableIntentOverrides,
          isCancelled: () => cancellationToken.isCancelled,
        ),
        expectedDeclaredName: intent.requiredDeclaredName,
      );
      if (capture.failureOrNull case final failure?) {
        return UpdateCandidatePublishPreparationFailure(
          _updateDraftFailure(failure.code),
        );
      }
      final snapshot = capture.valueOrNull!;
      final tree = snapshot.normalizedTree;
      final request = RevisionCommitRequest(
        tree: await _revisions.writeTree(store, tree),
        parents: [intent.previousEffective, intent.incomingUpstream],
        kind: RevisionCommitKind.effectiveUpdate,
      );
      final commit = await _revisions.createCommit(store, request);
      await _revisions.verifyCommit(store, commit, request);
      await _writeRecoveryBundle(
        operationId: operationId,
        managedSkillId: intent.managedSkillId,
        store: store,
        sourceLineage: intent.sourceLineage,
        currentUpstream: intent.incomingUpstream,
        currentEffective: commit,
        retainedRoots: <RevisionObjectId>[commit],
      );
      await _writeTree(
        _candidateMaterializationPath(operationId, intent.managedSkillId),
        tree,
        cancellationToken,
      );
      return UpdateCandidatePublishPreparationSuccess(
        PreparedUpdateCandidatePublish(
          managedSkillId: intent.managedSkillId,
          sourceLineage: intent.sourceLineage,
          effectiveObjectId: commit,
          publishedTreeObjectId: request.tree,
          effectiveRequest: request,
          publishedTree: tree,
          declaredName: snapshot.declaredName,
          description: _description(tree),
          draftDisposition: UpdateDraftDisposition.preserveAndReanchor,
          capturedDraftFingerprint: snapshot.capture.fingerprint,
          candidateRecoveryReference: operationRecoveryReference(
            operationId,
            'candidate-${intent.managedSkillId.value}',
          ),
          bundleRecoveryReference: operationRecoveryReference(
            operationId,
            'bundle-${intent.managedSkillId.value}',
          ),
          materializationRecoveryReference: operationRecoveryReference(
            operationId,
            'materialization-${intent.managedSkillId.value}',
          ),
          draftRecoveryReference: operationRecoveryReference(
            operationId,
            'draft-${intent.managedSkillId.value}',
          ),
        ),
      );
    } on _PreparationCancelled {
      return UpdateCandidatePublishPreparationFailure(
        UpdateRevisionPreparationFailureCode.operationCancelled,
      );
    } on RevisionEngineException catch (error) {
      return UpdateCandidatePublishPreparationFailure(
        UpdateRevisionPreparationFailureCode.revisionStoreUnavailable,
        detail: error.code,
      );
    } on Object {
      return UpdateCandidatePublishPreparationFailure(
        UpdateRevisionPreparationFailureCode.ioFailure,
      );
    }
  }

  @override
  Future<UpdateCandidateAbandonPreparationResult> prepareCandidateAbandon({
    required OperationId operationId,
    required UpdateCandidateCleanupIntent intent,
    required CancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);
      final store = _storePath(intent.managedSkillId);
      final retainedRoots = <RevisionObjectId>{
        intent.previousUpstream,
        intent.previousEffective,
        ...intent.retainedPublishedRoots,
      }.toList(growable: false);
      await _writeRecoveryBundle(
        operationId: operationId,
        managedSkillId: intent.managedSkillId,
        store: store,
        sourceLineage: intent.sourceLineage,
        currentUpstream: intent.previousUpstream,
        currentEffective: intent.previousEffective,
        retainedRoots: retainedRoots,
      );
      return UpdateCandidateAbandonPreparationSuccess(
        PreparedUpdateCandidateAbandon(
          managedSkillId: intent.managedSkillId,
          sourceLineage: intent.sourceLineage,
          retainedPublishedRoots: retainedRoots,
          bundleRecoveryReference: operationRecoveryReference(
            operationId,
            'bundle-${intent.managedSkillId.value}',
          ),
        ),
      );
    } on _PreparationCancelled {
      return const UpdateCandidateAbandonPreparationFailure(
        UpdateRevisionPreparationFailureCode.operationCancelled,
      );
    } on RevisionEngineException catch (error) {
      return UpdateCandidateAbandonPreparationFailure(
        UpdateRevisionPreparationFailureCode.revisionStoreUnavailable,
        detail: error.code,
      );
    } on Object {
      return const UpdateCandidateAbandonPreparationFailure(
        UpdateRevisionPreparationFailureCode.ioFailure,
      );
    }
  }

  @override
  Future<HistoryResult<PreparedRestorePublish>> prepareRestorePublish({
    required PreparedOperationEnvelope envelope,
    required RestorePublishPreflight preflight,
    required CancellationToken cancellationToken,
  }) async {
    try {
      _throwIfCancelled(cancellationToken);
      final store = _storePath(preflight.skill.id);
      DraftFingerprint? cleanDraftFingerprint;
      if (preflight.hadCleanDraft) {
        final currentTree = await _revisions.readTree(
          store,
          preflight.state.currentEffective,
        );
        final inspected = await _drafts.inspectForCleanup(
          request: DraftCaptureRequest(
            liveDraftPath: _layout.draftPath(preflight.skill.id),
            stagingDestinationPath: _candidateDraftPath(
              envelope.operationId,
              preflight.skill.id,
            ),
            capturePosixExecutableIntent: _capturePosixExecutableIntent,
            executableIntentOverrides: _executableIntentOverrides(currentTree),
            isCancelled: () => cancellationToken.isCancelled,
          ),
          draftBase: currentTree,
        );
        if (inspected.failureOrNull case final failure?) {
          return HistoryFailure(
            code: failure.code == DraftSnapshotFailureCode.operationCancelled
                ? HistoryFailureCode.operationCancelled
                : HistoryFailureCode.draftInspectionFailed,
            context: failure.context,
          );
        }
        if (inspected.valueOrNull!.isDirty) {
          return HistoryFailure(
            code: HistoryFailureCode.dirtyDraftResolutionRequired,
          );
        }
        cleanDraftFingerprint = inspected.valueOrNull!.cleanupFingerprint;
      }
      final tree = await _revisions.readTree(
        store,
        preflight.selected.objectId,
      );
      final valid = await _drafts.validateRestoreDeclaredName(
        expectedDeclaredName: preflight.skill.declaredName,
        historicalTree: tree,
      );
      if (valid.failureOrNull case final failure?) {
        return HistoryFailure(
          code: _historyFailure(failure.code),
          context: failure.context,
        );
      }
      final treeObject = await _revisions.writeTree(store, tree);
      final request = RevisionCommitRequest(
        tree: treeObject,
        parents: [preflight.state.currentEffective],
        kind: RevisionCommitKind.restorePublish,
      );
      final commit = await _revisions.createCommit(store, request);
      await _revisions.verifyCommit(store, commit, request);
      await _writeRecoveryBundle(
        operationId: envelope.operationId,
        managedSkillId: preflight.skill.id,
        store: store,
        sourceLineage: preflight.state.sourceLineage,
        currentUpstream: preflight.state.currentUpstream,
        currentEffective: commit,
        retainedRoots: <RevisionObjectId>[commit],
      );
      await _writeTree(
        _candidateMaterializationPath(envelope.operationId, preflight.skill.id),
        tree,
        cancellationToken,
      );
      return HistorySuccess(
        PreparedRestorePublish(
          managedSkillId: preflight.skill.id,
          sourceLineage: preflight.state.sourceLineage,
          selectedObjectId: preflight.selected.objectId,
          treeObjectId: treeObject,
          effectiveObjectId: commit,
          effectiveRequest: request,
          contentHash: tree.contentHash,
          fileCount: tree.fileCount,
          byteSize: tree.byteSize,
          declaredName: preflight.skill.declaredName,
          description: _description(tree),
          draftAction: preflight.hadCleanDraft
              ? RestoreDraftAction.preserveAndReanchor
              : RestoreDraftAction.noDraft,
          capturedDraftFingerprint: cleanDraftFingerprint,
          candidateRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'candidate-${preflight.skill.id.value}',
          ),
          bundleRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'bundle-${preflight.skill.id.value}',
          ),
          materializationRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'materialization-${preflight.skill.id.value}',
          ),
          draftRecoveryReference: operationRecoveryReference(
            envelope.operationId,
            'draft-${preflight.skill.id.value}',
          ),
        ),
      );
    } on _PreparationCancelled {
      return HistoryFailure(code: HistoryFailureCode.operationCancelled);
    } on RevisionEngineException catch (error) {
      return HistoryFailure(
        code: HistoryFailureCode.revisionStoreUnavailable,
        context: {'detail': error.code.name},
      );
    } on Object {
      return HistoryFailure(code: HistoryFailureCode.ioFailure);
    }
  }

  Map<String, bool> _executableIntentOverrides(NormalizedSkillTree tree) {
    if (_capturePosixExecutableIntent) return const <String, bool>{};
    return <String, bool>{
      for (final file in tree.files) file.relativePath: file.isExecutable,
    };
  }

  Future<PreparedUpdateOutcome> _cleanUpdateOutcome({
    required String store,
    required RevisionObjectId treeObject,
    required UpdateRevisionPreparationIntent intent,
    required RevisionObjectId incoming,
    required CancellationToken cancellationToken,
    DraftFingerprint? capturedDraftFingerprint,
  }) async {
    final tree = await _revisions.readTree(store, treeObject);
    final validation = _validateMergedTree(
      tree,
      requiredDeclaredName: intent.incomingDeclaredName,
    );
    if (validation.failureCode case final failureCode?) {
      return PreparedUpdateValidationFailure(
        candidateObjectId: await _createCandidateCommit(
          store: store,
          tree: treeObject,
          parent: intent.currentEffective,
        ),
        candidateTree: tree,
        validationCode: failureCode,
      );
    }
    final frontmatter = validation.frontmatter!;
    final request = RevisionCommitRequest(
      tree: treeObject,
      parents: [intent.currentEffective, incoming],
      kind: RevisionCommitKind.effectiveUpdate,
    );
    final effective = await _revisions.createCommit(store, request);
    await _revisions.verifyCommit(store, effective, request);
    _throwIfCancelled(cancellationToken);
    return PreparedUpdateClean(
      effectiveObjectId: effective,
      mergedTreeObjectId: treeObject,
      effectiveRequest: request,
      mergedTree: tree,
      declaredName: frontmatter.declaredName,
      description: frontmatter.description,
      draftDisposition: intent.hadCleanDraft
          ? UpdateDraftDisposition.preserveAndReanchor
          : UpdateDraftDisposition.noDraft,
      capturedDraftFingerprint: capturedDraftFingerprint,
    );
  }

  Future<RevisionObjectId> _createCandidateCommit({
    required String store,
    required RevisionObjectId tree,
    required RevisionObjectId parent,
  }) async {
    final request = RevisionCommitRequest(
      tree: tree,
      parents: <RevisionObjectId>[parent],
      kind: RevisionCommitKind.updateCandidate,
    );
    final commit = await _revisions.createCommit(store, request);
    await _revisions.verifyCommit(store, commit, request);
    return commit;
  }

  Future<_PreparedCommitEvidence> _createStoreAndBundle({
    required OperationId operationId,
    required String store,
    required String bundle,
    required NormalizedSkillTree tree,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId? parent,
    required RevisionCommitKind kind,
    required List<RevisionObjectId> Function(RevisionObjectId commit)
    retainedRoots,
    required CancellationToken cancellationToken,
  }) async {
    await _revisions.createStore(store);
    _throwIfCancelled(cancellationToken);
    final treeObject = await _revisions.writeTree(store, tree);
    final request = RevisionCommitRequest(
      tree: treeObject,
      parents: parent == null ? const [] : [parent],
      kind: kind,
    );
    final commit = await _revisions.createCommit(store, request);
    await _revisions.verifyCommit(store, commit, request);
    await _writeRecoveryBundleAt(
      operationStagingRoot: _layout.operationStagingPath(operationId),
      bundle: bundle,
      store: store,
      sourceLineage: sourceLineage,
      currentUpstream: commit,
      currentEffective: commit,
      retainedRoots: retainedRoots(commit),
    );
    return _PreparedCommitEvidence(tree: treeObject, commit: commit);
  }

  Future<void> _writeTree(
    String root,
    NormalizedSkillTree tree,
    CancellationToken token,
  ) => _filesystem.materializeStagedDirectory(
    rootPath: root,
    files: tree.files.map(
      (file) => StagedDirectoryFile(
        relativePath: file.relativePath,
        bytes: file.bytes,
        isExecutable: file.isExecutable,
      ),
    ),
    checkCancelled: () => _throwIfCancelled(token),
  );

  Future<void> _writeRecoveryBundle({
    required OperationId operationId,
    required ManagedSkillId managedSkillId,
    required String store,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedRoots,
  }) async {
    final bundle = _candidateBundlePath(operationId, managedSkillId);
    await _filesystem.removeOwnedPath(
      targetPath: bundle,
      ownerRoot: _layout.stagingRoot,
    );
    await _writeRecoveryBundleAt(
      operationStagingRoot: _layout.operationStagingPath(operationId),
      bundle: bundle,
      store: store,
      sourceLineage: sourceLineage,
      currentUpstream: currentUpstream,
      currentEffective: currentEffective,
      retainedRoots: retainedRoots,
    );
  }

  Future<void> _writeRecoveryBundleAt({
    required String operationStagingRoot,
    required String bundle,
    required String store,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedRoots,
  }) =>
      RevisionRecoveryBundlePublisher(
        revisions: _revisions,
        filesystem: _filesystem,
        codec: _bundleCodec,
      ).publish(
        repositoryPath: store,
        bundlePath: bundle,
        operationStagingRoot: operationStagingRoot,
        sourceLineage: sourceLineage,
        currentUpstream: currentUpstream,
        currentEffective: currentEffective,
        retainedPublishedRoots: retainedRoots,
      );

  String _storePath(ManagedSkillId id) => _layout.revisionStorePath(id);

  String _candidateRoot(OperationId operationId, ManagedSkillId id) =>
      _layout.operationRevisionCandidateRoot(operationId, id);

  String _candidateDraftPath(OperationId operationId, ManagedSkillId id) =>
      _layout.operationDraftCandidatePath(operationId, id);

  String _candidateBundlePath(OperationId operationId, ManagedSkillId id) =>
      _layout.operationBundleCandidatePath(operationId, id);

  String _candidateMaterializationPath(
    OperationId operationId,
    ManagedSkillId id,
  ) => _layout.operationTreeCandidatePath(operationId, id);
}

final class _PreparedCommitEvidence {
  const _PreparedCommitEvidence({required this.tree, required this.commit});
  final RevisionObjectId tree;
  final RevisionObjectId commit;
}

void _throwIfCancelled(CancellationToken token) {
  if (token.isCancelled) throw const _PreparationCancelled();
}

final class _PreparationCancelled implements Exception {
  const _PreparationCancelled();
}

DraftPlanningFailureCode _draftFailure(DraftSnapshotFailureCode code) =>
    switch (code) {
      DraftSnapshotFailureCode.operationCancelled =>
        DraftPlanningFailureCode.operationCancelled,
      DraftSnapshotFailureCode.declaredNameChangeNotAllowed =>
        DraftPlanningFailureCode.declaredNameChangeNotAllowed,
      DraftSnapshotFailureCode.draftChangedDuringPublish =>
        DraftPlanningFailureCode.draftChangedDuringPublish,
      DraftSnapshotFailureCode.invalidSkill ||
      DraftSnapshotFailureCode.skillContentLimitExceeded =>
        DraftPlanningFailureCode.invalidSkill,
      DraftSnapshotFailureCode.ioFailure => DraftPlanningFailureCode.ioFailure,
      DraftSnapshotFailureCode.historicalNameMismatch =>
        DraftPlanningFailureCode.invalidSkill,
    };

HistoryFailureCode _historyFailure(DraftSnapshotFailureCode code) =>
    switch (code) {
      DraftSnapshotFailureCode.operationCancelled =>
        HistoryFailureCode.operationCancelled,
      DraftSnapshotFailureCode.historicalNameMismatch =>
        HistoryFailureCode.historicalNameMismatch,
      DraftSnapshotFailureCode.invalidSkill ||
      DraftSnapshotFailureCode.skillContentLimitExceeded =>
        HistoryFailureCode.invalidSkill,
      _ => HistoryFailureCode.ioFailure,
    };

UpdateRevisionPreparationFailureCode _updateDraftFailure(
  DraftSnapshotFailureCode code,
) => switch (code) {
  DraftSnapshotFailureCode.operationCancelled =>
    UpdateRevisionPreparationFailureCode.operationCancelled,
  DraftSnapshotFailureCode.draftChangedDuringPublish =>
    UpdateRevisionPreparationFailureCode.draftChangedDuringPublish,
  DraftSnapshotFailureCode.declaredNameChangeNotAllowed =>
    UpdateRevisionPreparationFailureCode.declaredNameChangeNotAllowed,
  DraftSnapshotFailureCode.invalidSkill ||
  DraftSnapshotFailureCode.skillContentLimitExceeded ||
  DraftSnapshotFailureCode.historicalNameMismatch =>
    UpdateRevisionPreparationFailureCode.invalidSkill,
  DraftSnapshotFailureCode.ioFailure =>
    UpdateRevisionPreparationFailureCode.ioFailure,
};

WorkspaceUpdateCandidateItemKind _conflictKind(RevisionMergeConflict conflict) {
  final ancestor = conflict.ancestorPath;
  final current = conflict.currentPath;
  final incoming = conflict.incomingPath;
  if (ancestor != null && (current == null || incoming == null)) {
    return WorkspaceUpdateCandidateItemKind.deleteModify;
  }
  if (current != null && incoming != null && current != incoming) {
    return WorkspaceUpdateCandidateItemKind.rename;
  }
  return WorkspaceUpdateCandidateItemKind.text;
}

String _description(NormalizedSkillTree tree) {
  for (final file in tree.files) {
    if (file.relativePath != 'SKILL.md') continue;
    try {
      final frontmatter = parseSkillFrontmatter(
        utf8.decode(file.bytes, allowMalformed: false),
      );
      if (frontmatter != null) return frontmatter.description;
    } on FormatException {
      break;
    }
  }
  throw StateError('Prepared Skill content has no valid description.');
}

SkillFrontmatter? _frontmatter(NormalizedSkillTree tree) {
  for (final file in tree.files) {
    if (file.relativePath != 'SKILL.md') continue;
    try {
      return parseSkillFrontmatter(
        utf8.decode(file.bytes, allowMalformed: false),
      );
    } on FormatException {
      return null;
    }
  }
  return null;
}

({SkillFrontmatter? frontmatter, String? failureCode}) _validateMergedTree(
  NormalizedSkillTree tree, {
  required String requiredDeclaredName,
}) {
  if (tree.fileCount > maximumNormalizedSkillFileCount) {
    return (frontmatter: null, failureCode: 'mergedSkillFileLimitExceeded');
  }
  if (tree.byteSize > maximumNormalizedSkillByteSize) {
    return (frontmatter: null, failureCode: 'mergedSkillByteLimitExceeded');
  }
  final frontmatter = _frontmatter(tree);
  if (frontmatter == null) {
    return (frontmatter: null, failureCode: 'mergedSkillFrontmatterInvalid');
  }
  if (frontmatter.declaredName != requiredDeclaredName) {
    return (
      frontmatter: frontmatter,
      failureCode: 'mergedDeclaredNameMismatch',
    );
  }
  return (frontmatter: frontmatter, failureCode: null);
}
