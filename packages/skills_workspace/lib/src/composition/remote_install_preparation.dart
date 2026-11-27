part of 'revision_preparation_service.dart';

typedef ReadRemotePackHeads =
    Future<
      ({
        RevisionObjectId effective,
        RevisionObjectId? upstream,
        String sourceEpoch,
      })?
    >
    Function(ManagedSkillId);

typedef PreparedRemoteInstall = ({
  RemoteApplyResult result,
  RemoteInstallEvidence? evidence,
});

typedef RemoteInstallEvidence = ({
  ManagedSkillId managedSkillId,
  String slotKey,
  String declaredName,
  String contentHash,
  RevisionAddress effective,
  RevisionAddress upstream,
  WorkspaceBusinessChangeSet businessChanges,
});

extension WorkspaceRemoteInstallPreparation
    on WorkspaceRevisionPreparationService {
  Future<SkillsResult<PreparedRemoteInstall>> prepareRemoteInstall({
    required OperationId operationId,
    required RemoteSkillInstall request,
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required SourceLineageReference lineage,
    required SourcePayloadEncodingPort sourcePayloads,
    required ReadRemotePackHeads readPackHeads,
    required RevisionWorkerRuntime runtime,
    required CancellationToken token,
    ManagedSkillId? replacing,
  }) async {
    final effective = RevisionObjectId(request.effective.value);
    final upstream = RevisionObjectId(
      request.upstream?.value ?? effective.value,
    );
    final roots = {effective, upstream}.toList();
    try {
      _throwIfCancelled(token);
      final staged = await prepareRemoteRevisionStore(
        layout: _layout,
        revisions: runtime,
        operationId: operationId,
        managedSkillId: managedSkillId,
        targetRevisions: roots,
        packPath: request.packPath,
        createNewStore: true,
        cancellationToken: token,
      );
      if (staged.packFailure case final failure?) {
        return _remotePackFailure(failure);
      }
      final store = staged.storePath;
      final NormalizedSkillTree tree;
      try {
        tree = await _revisions.readTree(store, effective);
      } on RevisionEngineException catch (error) {
        if (error.code == RevisionEngineFailureCode.verificationFailed) {
          return SkillsFailure(code: SkillsErrorCode.invalidSkill);
        }
        rethrow;
      }
      _throwIfCancelled(token);
      final frontmatter = _frontmatter(tree);
      if (frontmatter == null || !_isCanonicalSkillTree(tree, token)) {
        return SkillsFailure(code: SkillsErrorCode.invalidSkill);
      }
      final declaredName = frontmatter.declaredName;
      final slot = deriveSlotKeyValue(declaredName).value;
      if (slot == null) {
        return SkillsFailure(code: SkillsErrorCode.unsupportedSkillName);
      }

      final occupant = snapshot.findSkillBySlotKey(slot);
      if (occupant != null && occupant.id != replacing) {
        final heads = occupant.source == request.source
            ? await readPackHeads(occupant.id)
            : null;
        final same =
            heads != null &&
            heads.effective == effective &&
            heads.upstream?.value == request.upstream?.value;
        return SkillsSuccess(
          value: (
            result: same
                ? RemoteApplyInstalled(
                    occupant.id,
                    sourceEpoch: heads.sourceEpoch,
                  )
                : RemoteApplySkillSlotOccupied(occupant.id),
            evidence: null,
          ),
          changed: false,
        );
      }

      final encoded = sourcePayloads.encode(request.source);
      if (encoded is! SourcePayloadEncoded) {
        return SkillsFailure(code: SkillsErrorCode.invalidSkill);
      }
      final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      PutRevisionMetadata metadata(
        RevisionObjectId object,
        NormalizedSkillTree content,
        String name,
      ) => PutRevisionMetadata(
        sourceLineageId: lineage.encoded,
        objectId: object.value,
        contentHash: content.contentHash,
        fileCount: content.fileCount,
        byteSize: content.byteSize,
        declaredName: name,
        validationState: WorkspaceRevisionValidationState.valid,
        validationCode: null,
        createdAtMicros: timestamp,
      );
      final upstreamTree = upstream == effective
          ? tree
          : await _revisions.readTree(store, upstream);
      final upstreamFrontmatter = _frontmatter(upstreamTree);
      if (upstreamFrontmatter == null) {
        return SkillsFailure(code: SkillsErrorCode.invalidSkill);
      }
      _throwIfCancelled(token);
      await _writeRecoveryBundleAt(
        operationStagingRoot: _layout.operationStagingPath(operationId),
        bundle: _candidateBundlePath(operationId, managedSkillId),
        store: store,
        sourceLineage: lineage,
        currentUpstream: upstream,
        currentEffective: effective,
        retainedRoots: roots,
      );
      await _writeTree(
        _candidateMaterializationPath(operationId, managedSkillId),
        tree,
        token,
      );
      return SkillsSuccess(
        value: (
          result: RemoteApplyInstalled(
            managedSkillId,
            sourceEpoch: lineage.localEpoch,
          ),
          evidence: (
            managedSkillId: managedSkillId,
            slotKey: slot,
            declaredName: declaredName,
            contentHash: tree.contentHash,
            effective: RevisionAddress(
              sourceLineage: lineage,
              objectId: effective,
            ),
            upstream: RevisionAddress(
              sourceLineage: lineage,
              objectId: upstream,
            ),
            businessChanges: WorkspaceBusinessChangeSet(
              mutations: [
                PutManagedSkill(
                  managedSkillId: managedSkillId,
                  slotKey: slot,
                  declaredName: declaredName,
                  displayName: declaredName,
                  description: frontmatter.description,
                  activeSourceLineageId: lineage.encoded,
                  createdAtMicros: timestamp,
                  updatedAtMicros: timestamp,
                ),
                PutSourceLineage(
                  sourceLineageId: lineage.encoded,
                  managedSkillId: managedSkillId,
                  objectFormat: WorkspaceObjectFormat.sha1,
                  createdAtMicros: timestamp,
                ),
                PutSkillSource(
                  sourceLineageId: lineage.encoded,
                  kind: encoded.payload.kind,
                  payloadSchemaVersion: encoded.payload.payloadSchemaVersion,
                  payloadJson: encoded.payload.payloadJson,
                ),
                metadata(effective, tree, declaredName),
                if (upstream != effective)
                  metadata(
                    upstream,
                    upstreamTree,
                    upstreamFrontmatter.declaredName,
                  ),
              ],
            ),
          ),
        ),
      );
    } on ManagedRemoteStoreCancelled {
      return SkillsFailure(code: SkillsErrorCode.operationCancelled);
    } on _PreparationCancelled {
      return SkillsFailure(code: SkillsErrorCode.operationCancelled);
    } on RevisionEngineException {
      return SkillsFailure(code: SkillsErrorCode.revisionStoreCorrupt);
    } on FileSystemException {
      return SkillsFailure(
        code: token.isCancelled
            ? SkillsErrorCode.operationCancelled
            : SkillsErrorCode.ioFailure,
      );
    }
  }
}

bool _isCanonicalSkillTree(NormalizedSkillTree tree, CancellationToken token) {
  if (tree.byteSize > maximumNormalizedSkillByteSize) return false;
  // Validate portable paths without copying the already verified blobs.
  final normalized = const SkillContentNormalizer().normalize(
    tree.files.map(
      (file) =>
          SkillContentEntry.file(path: file.relativePath, bytes: const []),
    ),
    isCancelled: () => token.isCancelled,
  );
  _throwIfCancelled(token);
  if (normalized is! SkillContentSuccess<NormalizedSkillTree>) return false;
  final canonicalFiles = normalized.value.files;
  for (var i = 0; i < canonicalFiles.length; i++) {
    if (canonicalFiles[i].relativePath != tree.files[i].relativePath) {
      return false;
    }
  }
  return true;
}

SkillsFailure<T> _remotePackFailure<T>(RevisionPackStageFailure failure) =>
    SkillsFailure(
      code: switch (failure) {
        RevisionPackStageFailure.malformed => SkillsErrorCode.archiveInvalid,
        RevisionPackStageFailure.incomplete =>
          SkillsErrorCode.revisionStoreCorrupt,
        RevisionPackStageFailure.unreadable => SkillsErrorCode.ioFailure,
      },
      context: {
        'reason': switch (failure) {
          RevisionPackStageFailure.malformed => 'packMalformed',
          RevisionPackStageFailure.incomplete => 'packIncomplete',
          RevisionPackStageFailure.unreadable => 'packUnreadable',
        },
      },
    );
