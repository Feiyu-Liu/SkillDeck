part of 'revision_preparation_service.dart';

typedef PreparedCandidateResolution = ({
  WorkspaceBusinessChangeSet changes,
  List<RemoteStoreAddition> additions,
  Future<bool> Function(String) verifyDraft,
});

extension WorkspaceCandidateConflictPreparation
    on WorkspaceRevisionPreparationService {
  Future<DraftSnapshotResult<DraftFingerprint>> fingerprintCandidateDraft({
    required OperationId operationId,
    required UpdateCandidateState state,
    required CancellationToken token,
  }) async {
    final id = state.managedSkillId;
    final tree = await _revisions.readTree(
      _storePath(id),
      state.candidateObjectId,
    );
    return _drafts.fingerprint(
      _conflictCaptureRequest(
        draftPath: _layout.draftPath(id),
        stagingPath: _candidateDraftPath(operationId, id),
        candidate: tree,
        token: token,
      ),
    );
  }

  Future<SkillsResult<PreparedCandidateResolution>> prepareCandidateResolution({
    required OperationId operationId,
    required UpdateCandidateState state,
    required UpdateCandidateSummary summary,
    required UpdateCandidateSide side,
    required DraftFingerprint reviewedDraft,
    required RevisionWorkerRuntime runtime,
    required CancellationToken token,
  }) async {
    SkillsFailure<PreparedCandidateResolution> failure(SkillsErrorCode code) =>
        SkillsFailure(code: code);
    final id = state.managedSkillId;
    try {
      final prepared = await prepareRemoteRevisionStore(
        layout: _layout,
        revisions: runtime,
        operationId: operationId,
        managedSkillId: id,
        targetRevisions: const [],
        cancellationToken: token,
        usePreviouslyStagedPacks: false,
      );
      final store = prepared.storePath;
      final original = await _revisions.readTree(
        store,
        state.candidateObjectId,
      );
      DraftCaptureRequest captureRequest(String path) =>
          _conflictCaptureRequest(
            draftPath: path,
            stagingPath: _candidateDraftPath(operationId, id),
            candidate: original,
            token: token,
          );
      final captured = await _drafts.captureForConflictResolution(
        captureRequest(_layout.draftPath(id)),
      );
      if (captured.failureOrNull case final problem?) {
        return failure(switch (problem.code) {
          DraftSnapshotFailureCode.operationCancelled =>
            SkillsErrorCode.operationCancelled,
          DraftSnapshotFailureCode.draftChangedDuringPublish =>
            SkillsErrorCode.staleSnapshot,
          DraftSnapshotFailureCode.ioFailure => SkillsErrorCode.ioFailure,
          _ => SkillsErrorCode.externalConflict,
        });
      }
      final draft = captured.valueOrNull!;
      if (draft.capture.fingerprint != reviewedDraft) {
        return failure(SkillsErrorCode.staleSnapshot);
      }
      if (reviewedDraft.entries.any(
        (entry) => entry.kind == DraftFilesystemEntryKind.symbolicLink,
      )) {
        return failure(SkillsErrorCode.externalConflict);
      }
      final remoteParent = await _revisions.readMergeParent(
        store,
        state.candidateObjectId,
      );
      final incoming = remoteParent ?? state.incomingUpstream;
      final RevisionMergeResult merge;
      if (remoteParent == null) {
        merge = await _revisions.merge(
          repositoryPath: store,
          previousUpstream: state.previousUpstream,
          currentEffective: state.previousEffective,
          incomingUpstream: incoming,
        );
      } else {
        final base = await _revisions.mergeBase(
          store,
          state.previousEffective,
          incoming,
        );
        if (base == null) return failure(SkillsErrorCode.revisionStoreCorrupt);
        merge = await _revisions.mergeSync(
          repositoryPath: store,
          base: base,
          local: state.previousEffective,
          remote: incoming,
        );
      }
      if (merge is! RevisionMergeConflicted) {
        return failure(SkillsErrorCode.externalConflict);
      }
      final selectedTree = await _revisions.readTree(
        store,
        side == UpdateCandidateSide.current
            ? state.previousEffective
            : incoming,
      );
      final selection = _resolveCandidateFiles(
        working: draft.tree,
        candidate: original,
        chosen: selectedTree,
        conflicts: merge.conflicts,
        persisted: state.conflicts,
        side: side,
        token: token,
      );
      _throwIfCancelled(token);
      if (selection == null) return failure(SkillsErrorCode.externalConflict);

      // Keep executable intent in the candidate's immutable base, including
      // platforms where the Draft filesystem cannot represent that intent.
      final candidate = await _revisions.createCommit(
        store,
        RevisionCommitRequest(
          tree: await _revisions.writeTree(store, selection),
          parents: [state.previousEffective, ?remoteParent],
          kind: remoteParent == null
              ? RevisionCommitKind.updateCandidate
              : RevisionCommitKind.syncCandidate,
        ),
      );
      final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      final lineage = state.sourceLineage;
      final changes = WorkspaceBusinessChangeSet(
        mutations: [
          PutRevisionMetadata(
            sourceLineageId: lineage.encoded,
            objectId: candidate.value,
            contentHash: selection.contentHash,
            fileCount: selection.fileCount,
            byteSize: selection.byteSize,
            declaredName: state.incomingDeclaredName,
            validationState: WorkspaceRevisionValidationState.invalid,
            validationCode: 'updateMergeConflict',
            createdAtMicros: timestamp,
          ),
          PutUpdateCandidateSession(
            managedSkillId: id,
            sourceLineageId: lineage.encoded,
            previousUpstreamObjectId: state.previousUpstream.value,
            previousEffectiveObjectId: state.previousEffective.value,
            incomingUpstreamObjectId: state.incomingUpstream.value,
            candidateObjectId: candidate.value,
            status: WorkspaceUpdateCandidateStatus.conflicted,
            validationCode: null,
            items: [
              for (final item in state.conflicts)
                WorkspaceUpdateCandidateItem(
                  path: item.path,
                  kind: item.kind,
                  state: WorkspaceUpdateCandidateItemState.resolved,
                  baseObjectId: item.baseObjectId,
                  oursObjectId: item.oursObjectId,
                  theirsObjectId: item.theirsObjectId,
                ),
            ],
            createdAtMicros: summary.createdAt.microsecondsSinceEpoch,
            updatedAtMicros: timestamp,
          ),
          PutDraftWorkspace(
            managedSkillId: id,
            sourceLineageId: lineage.encoded,
            baseObjectId: candidate.value,
            purpose: WorkspaceDraftPurpose.updateCandidateResolution,
            createdAtMicros: state.draftCreatedAtMicros,
            updatedAtMicros: timestamp,
          ),
        ],
      );
      await _writeRecoveryBundle(
        operationId: operationId,
        managedSkillId: id,
        store: store,
        sourceLineage: lineage,
        currentUpstream: state.previousUpstream,
        currentEffective: state.previousEffective,
        retainedRoots: [
          ...state.retainedPublishedRoots,
          state.incomingUpstream,
          candidate,
        ],
        includeDraftAndSession: false,
      );
      await _writeTree(
        _candidateMaterializationPath(operationId, id),
        selection,
        token,
        directories: [
          for (final entry in reviewedDraft.entries)
            if (entry.kind == DraftFilesystemEntryKind.directory &&
                entry.relativePath.isNotEmpty)
              entry.relativePath,
        ],
      );
      final additions = await readRemoteStoreAdditions(
        candidateStore: store,
        liveStore: _storePath(id),
        cancellationToken: token,
      );
      return SkillsSuccess(
        value: (
          changes: changes,
          additions: additions,
          verifyDraft: (path) =>
              _drafts.matchesFingerprint(captureRequest(path), reviewedDraft),
        ),
      );
    } on _PreparationCancelled {
      return failure(SkillsErrorCode.operationCancelled);
    } on ManagedRemoteStoreCancelled {
      return failure(SkillsErrorCode.operationCancelled);
    } on RevisionEngineException {
      return failure(SkillsErrorCode.revisionStoreCorrupt);
    } on FileSystemException {
      return failure(SkillsErrorCode.ioFailure);
    } on ArgumentError {
      return failure(SkillsErrorCode.externalConflict);
    }
  }
}

NormalizedSkillTree? _resolveCandidateFiles({
  required NormalizedSkillTree working,
  required NormalizedSkillTree candidate,
  required NormalizedSkillTree chosen,
  required List<RevisionMergeConflict> conflicts,
  required List<WorkspaceUpdateCandidateItem> persisted,
  required UpdateCandidateSide side,
  required CancellationToken token,
}) {
  final saved = {for (final item in persisted) item.path: item.state};
  final seen = <String>{};
  final remove = <String>{};
  final keep = <String>{};
  for (final conflict in conflicts) {
    final path =
        conflict.currentPath ?? conflict.incomingPath ?? conflict.ancestorPath;
    if (path == null || !seen.add(path) || !saved.containsKey(path)) {
      return null;
    }
    final paths = {
      ?conflict.ancestorPath,
      ?conflict.currentPath,
      ?conflict.incomingPath,
    };
    if (saved[path] == WorkspaceUpdateCandidateItemState.resolved) {
      keep.addAll(paths);
    } else {
      remove.addAll(paths);
    }
  }
  if (seen.length != saved.length || remove.any(keep.contains)) return null;

  final incomingFiles = {
    for (final file in chosen.files) file.relativePath: file,
  };
  final before = {for (final file in candidate.files) file.relativePath: file};
  final files = {for (final file in working.files) file.relativePath: file};
  // Renames can involve several paths. An unreviewed file in a destination
  // must never be overwritten by a side selection.
  for (final path in remove) {
    if (before[path] == null && files[path] != null) return null;
    files.remove(path);
  }
  for (final conflict in conflicts) {
    final key =
        conflict.currentPath ?? conflict.incomingPath ?? conflict.ancestorPath;
    if (saved[key] == WorkspaceUpdateCandidateItemState.resolved) continue;
    final path = side == UpdateCandidateSide.current
        ? conflict.currentPath
        : conflict.incomingPath;
    if (path == null) continue;
    final file = incomingFiles[path];
    if (file == null || files.containsKey(path)) return null;
    files[path] = file;
  }
  return const SkillContentNormalizer()
      .normalize(
        files.values.map(
          (file) => SkillContentEntry.file(
            path: file.relativePath,
            bytes: file.bytes,
            isExecutable: file.isExecutable,
          ),
        ),
        isCancelled: () => token.isCancelled,
      )
      .valueOrNull;
}
