part of 'revision_preparation_service.dart';

extension WorkspaceRemoteReplacementPreparation
    on WorkspaceRevisionPreparationService {
  Future<
    SkillsResult<
      ({RemoteApplyResult result, PreparedSourceReplacement? candidate})
    >
  >
  prepareRemoteSourceReplacement({
    required OperationId operationId,
    required RemoteSkillSourceReplacement request,
    required RepositorySnapshot snapshot,
    required SourceLineageReference lineage,
    required SourcePayloadEncodingPort sourcePayloads,
    required ReadRemotePackHeads readPackHeads,
    required RevisionWorkerRuntime runtime,
    required CancellationToken token,
  }) async {
    final prepared = await prepareRemoteInstall(
      operationId: operationId,
      request: RemoteSkillInstall(
        packPath: request.packPath,
        effective: request.effective,
        upstream: request.upstream,
        source: request.source,
      ),
      snapshot: snapshot,
      managedSkillId: request.managedSkillId,
      lineage: lineage,
      sourcePayloads: sourcePayloads,
      readPackHeads: readPackHeads,
      runtime: runtime,
      token: token,
      replacing: request.managedSkillId,
    );
    if (prepared case SkillsFailure(:final code, :final context)) {
      return SkillsFailure(code: code, context: context);
    }
    final value = (prepared as SkillsSuccess<PreparedRemoteInstall>).value,
        evidence = value.evidence;
    if (evidence == null) {
      return SkillsSuccess(
        value: (result: value.result, candidate: null),
        changed: false,
      );
    }
    final mutations = evidence.businessChanges.mutations;
    final skill = mutations.whereType<PutManagedSkill>().single;
    final source = mutations.whereType<PutSkillSource>().single;
    final metadata = mutations.whereType<PutRevisionMetadata>().toList();
    final effective = metadata.firstWhere(
      (m) => m.objectId == evidence.effective.objectId.value,
    );
    // The existing destructive recovery path consumes these two staging paths.
    await _filesystem.ensureDirectory(
      _layout.operationSourceReplacementRoot(operationId),
    );
    // Both directories are owned by the durable Prepared envelope. No live path
    // is moved here; recovery removes either staging location after a crash.
    await Directory(
      _candidateRoot(operationId, request.managedSkillId),
    ).rename(_layout.operationSourceReplacementStore(operationId));
    await Directory(
      _candidateBundlePath(operationId, request.managedSkillId),
    ).rename(_layout.operationSourceReplacementBundle(operationId));
    await _filesystem.flushDirectory(_layout.operationStagingPath(operationId));
    await _filesystem.flushDirectory(
      _layout.operationSourceReplacementRoot(operationId),
    );
    return SkillsSuccess(
      value: (
        result: const RemoteApplySourceReplaced(),
        candidate: PreparedSourceReplacement(
          managedSkillId: request.managedSkillId,
          sourceLineage: lineage,
          objectId: evidence.effective.objectId,
          upstreamObjectId: evidence.upstream.objectId,
          additionalRevisionMetadata: metadata
              .where((m) => m.objectId != effective.objectId)
              .toList(),
          objectFormat: WorkspaceObjectFormat.sha1,
          persistedSourceKind: source.kind,
          sourcePayloadSchemaVersion: source.payloadSchemaVersion,
          sourcePayloadJson: source.payloadJson,
          slotKey: skill.slotKey,
          declaredName: skill.declaredName,
          displayName: skill.displayName,
          description: skill.description,
          contentHash: effective.contentHash,
          fileCount: effective.fileCount,
          byteSize: effective.byteSize,
        ),
      ),
    );
  }
}
