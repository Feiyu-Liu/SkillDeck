part of 'revision_preparation_service.dart';

typedef PreparedRemoteContent = ({
  RemoteApplyResult result,
  PreparedUpdatePlan? plan,
  List<RemoteStoreAddition> objectAdditions,
  List<String> usedPackStaging,
  OperationRecoveryPreCaptureVerifier? verifyDraft,
});

extension WorkspaceRemoteContentPreparation
    on WorkspaceRevisionPreparationService {
  Future<SkillsResult<PreparedRemoteContent>> prepareRemoteContent({
    required OperationId operationId,
    required RemoteSkillContent request,
    required RepositorySnapshot snapshot,
    required ManagedSkill skill,
    required UpdateRevisionState state,
    required UpdateSlotMigrationInspectionPort slotMigrations,
    required RevisionWorkerRuntime runtime,
    required CancellationToken token,
  }) async {
    final id = skill.id;
    final local = state.currentEffective;
    final remote = RevisionObjectId(request.effective.value);
    final remoteUpstream = switch (request.upstream) {
      final head? => RevisionObjectId(head.value),
      null => null,
    };
    final lineage = state.sourceLineage;
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final liveStore = _storePath(id);

    try {
      _throwIfCancelled(token);
      if (local == remote && request.packPath == null) {
        return _remoteUnchanged(const RemoteApplyNoChange());
      }
      final staged = await prepareRemoteRevisionStore(
        layout: _layout,
        revisions: runtime,
        operationId: operationId,
        managedSkillId: id,
        targetRevisions: [remote, ?remoteUpstream],
        packPath: request.packPath,
        cancellationToken: token,
      );
      _throwIfCancelled(token);
      if (staged.packFailure case final failure?) {
        return _remotePackFailure(failure);
      }
      final store = staged.storePath;
      final incoming = await _revisions.readTree(store, remote);
      if (local == remote ||
          await _revisions.isAncestor(
            repositoryPath: store,
            ancestor: remote,
            descendant: local,
          )) {
        return _remoteUnchanged(const RemoteApplyNoChange());
      }

      if (skill.updateCandidate != null) {
        return _remoteUnchanged(const RemoteApplyDraftResolutionRequired());
      }
      OperationRecoveryPreCaptureVerifier? verifyDraft;
      if (skill.draft != null) {
        final base = await _revisions.readTree(liveStore, local);
        final capture = DraftCaptureRequest(
          liveDraftPath: _layout.draftPath(id),
          stagingDestinationPath: _candidateDraftPath(operationId, id),
          capturePosixExecutableIntent: _capturePosixExecutableIntent,
          executableIntentOverrides: _executableIntentOverrides(base),
          isCancelled: () => token.isCancelled,
        );
        final inspected = await _drafts.inspectForCleanup(
          request: capture,
          draftBase: base,
        );
        _throwIfCancelled(token);
        final value = inspected.valueOrNull;
        if (value == null) {
          return SkillsFailure(code: SkillsErrorCode.ioFailure);
        }
        if (value.isDirty) {
          return _remoteUnchanged(const RemoteApplyDraftResolutionRequired());
        }
        verifyDraft = (_) async {
          final checked = await _drafts.inspectForCleanup(
            request: capture,
            draftBase: base,
          );
          if (token.isCancelled) return true;
          return checked.valueOrNull?.cleanupFingerprint ==
              value.cleanupFingerprint;
        };
      }

      final upstream =
          remoteUpstream == null ||
              await _revisions.isAncestor(
                repositoryPath: store,
                ancestor: remoteUpstream,
                descendant: state.previousUpstream,
              )
          ? state.previousUpstream
          : remoteUpstream;
      final incomingFrontmatter = _frontmatter(incoming);
      if (incomingFrontmatter == null) {
        return SkillsFailure(code: SkillsErrorCode.invalidSkill);
      }
      final declaredName = incomingFrontmatter.declaredName;
      final slot = deriveSlotKeyValue(declaredName).value;
      if (slot == null) {
        return SkillsFailure(code: SkillsErrorCode.unsupportedSkillName);
      }
      if (slot != skill.slotKey) {
        final occupied = snapshot.findSkillBySlotKey(slot);
        if (occupied != null && occupied.id != id) {
          return SkillsFailure(code: SkillsErrorCode.duplicateSkillSlot);
        }
        final migration = await slotMigrations.inspect(
          snapshot: snapshot,
          skill: skill,
          newSlotKey: slot,
          cancellationToken: token,
        );
        if (migration is UpdateSlotMigrationInspectionFailure) {
          _throwIfCancelled(token);
          return SkillsFailure(code: SkillsErrorCode.duplicateSkillSlot);
        }
      }

      RevisionMergeResult? merge;
      if (!await _revisions.isAncestor(
        repositoryPath: store,
        ancestor: local,
        descendant: remote,
      )) {
        final base = await _revisions.mergeBase(store, local, remote);
        if (base == null) {
          return SkillsFailure(
            code: SkillsErrorCode.revisionStoreCorrupt,
            context: const {'reason': 'missingMergeBase'},
          );
        }
        merge = await _revisions.mergeSync(
          repositoryPath: store,
          base: base,
          local: local,
          remote: remote,
        );
      }
      _throwIfCancelled(token);

      final tree = switch (merge) {
        RevisionMergeClean(:final tree) ||
        RevisionMergeConflicted(
          :final tree,
        ) => await _revisions.readTree(store, tree),
        null => incoming,
      };
      final conflicted = merge is RevisionMergeConflicted;
      final validation = conflicted
          ? null
          : _validateMergedTree(tree, requiredDeclaredName: declaredName);
      if (validation?.failureCode case final code?) {
        return SkillsFailure(
          code: SkillsErrorCode.invalidSkill,
          context: {'reason': code},
        );
      }

      final mutations = <WorkspaceBusinessMutation>[];
      PutRevisionMetadata metadata(
        RevisionObjectId object,
        NormalizedSkillTree content,
        String name, {
        bool invalid = false,
      }) => PutRevisionMetadata(
        sourceLineageId: lineage.encoded,
        objectId: object.value,
        contentHash: content.contentHash,
        fileCount: content.fileCount,
        byteSize: content.byteSize,
        declaredName: name,
        validationState: invalid
            ? WorkspaceRevisionValidationState.invalid
            : WorkspaceRevisionValidationState.valid,
        validationCode: invalid ? 'updateMergeConflict' : null,
        createdAtMicros: timestamp,
      );

      if (upstream != state.previousUpstream && upstream != remote) {
        final upstreamTree = await _revisions.readTree(store, upstream);
        final upstreamFrontmatter = _frontmatter(upstreamTree);
        if (upstreamFrontmatter == null) {
          return SkillsFailure(code: SkillsErrorCode.invalidSkill);
        }
        mutations.add(
          metadata(upstream, upstreamTree, upstreamFrontmatter.declaredName),
        );
      }
      if (upstream == remote || merge != null) {
        mutations.add(metadata(remote, incoming, declaredName));
      }

      final object = switch (merge) {
        null => remote,
        RevisionMergeClean(:final tree) ||
        RevisionMergeConflicted(:final tree) => await _revisions.createCommit(
          store,
          RevisionCommitRequest(
            tree: tree,
            parents: [local, remote],
            kind: conflicted
                ? RevisionCommitKind.syncCandidate
                : RevisionCommitKind.effectiveUpdate,
          ),
        ),
      };
      if (object != remote || upstream != remote) {
        mutations.add(
          metadata(object, tree, declaredName, invalid: conflicted),
        );
      }
      await _writeRecoveryBundle(
        operationId: operationId,
        managedSkillId: id,
        store: store,
        sourceLineage: lineage,
        currentUpstream: conflicted ? state.previousUpstream : upstream,
        currentEffective: conflicted ? local : object,
        retainedRoots: {
          local,
          object,
          upstream,
          ...(conflicted ? [remote] : <RevisionObjectId>[]),
        }.toList(),
      );
      await _writeTree(
        _candidateMaterializationPath(operationId, id),
        tree,
        token,
      );

      final address = RevisionAddress(sourceLineage: lineage, objectId: object);
      RecoveryReference reference(String role) =>
          operationRecoveryReference(operationId, '$role-${id.value}');
      final materializations = <UpdateMaterializationIntent>[];
      final selections = <RevisionSelectionChangePlan>[];
      if (merge case RevisionMergeConflicted(:final conflicts)) {
        mutations.addAll([
          PutUpdateCandidateSession(
            managedSkillId: id,
            sourceLineageId: lineage.encoded,
            previousUpstreamObjectId: state.previousUpstream.value,
            previousEffectiveObjectId: local.value,
            incomingUpstreamObjectId: upstream.value,
            candidateObjectId: object.value,
            status: WorkspaceUpdateCandidateStatus.conflicted,
            validationCode: null,
            items: [
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
            createdAtMicros: timestamp,
            updatedAtMicros: timestamp,
          ),
          PutDraftWorkspace(
            managedSkillId: id,
            sourceLineageId: lineage.encoded,
            baseObjectId: object.value,
            purpose: WorkspaceDraftPurpose.updateCandidateResolution,
            createdAtMicros: timestamp,
            updatedAtMicros: timestamp,
          ),
        ]);
        materializations.add(
          UpdateCandidateDraftMaterializationIntent(
            managedSkillId: id,
            revision: address,
            recoveryReference: reference('materialization'),
            draftRecoveryReference: reference('draft'),
          ),
        );
      } else {
        mutations.add(
          PutManagedSkill(
            managedSkillId: id,
            slotKey: slot,
            declaredName: declaredName,
            displayName: skill.displayName == skill.declaredName
                ? declaredName
                : skill.displayName,
            description: validation!.frontmatter!.description,
            activeSourceLineageId: lineage.encoded,
            createdAtMicros: state.managedSkillCreatedAtMicros,
            updatedAtMicros: timestamp,
          ),
        );
        if (verifyDraft != null) {
          mutations.add(
            PutDraftWorkspace(
              managedSkillId: id,
              sourceLineageId: lineage.encoded,
              baseObjectId: object.value,
              purpose: WorkspaceDraftPurpose.customization,
              createdAtMicros: state.draftCreatedAtMicros ?? timestamp,
              updatedAtMicros: timestamp,
            ),
          );
          materializations.add(
            UpdateCandidateDraftMaterializationIntent(
              managedSkillId: id,
              revision: address,
              recoveryReference: reference('materialization'),
              draftRecoveryReference: reference('draft'),
            ),
          );
        }
        selections.add(
          RevisionSelectionChangePlan(
            managedSkillId: id,
            previousUpstream: RevisionAddress(
              sourceLineage: lineage,
              objectId: state.previousUpstream,
            ),
            previousEffective: RevisionAddress(
              sourceLineage: lineage,
              objectId: local,
            ),
            intendedUpstream: RevisionAddress(
              sourceLineage: lineage,
              objectId: upstream,
            ),
            intendedEffective: address,
          ),
        );
        materializations.addAll([
          UpdateRepositoryMaterializationIntent(
            managedSkillId: id,
            revision: address,
            recoveryReference: reference('materialization'),
            oldSlotKey: skill.slotKey,
            newSlotKey: slot,
          ),
          for (final activation in skill.activations)
            UpdateActivationMaterializationIntent(
              managedSkillId: id,
              revision: address,
              recoveryReference: reference('materialization'),
              activation: activation,
              oldSlotKey: skill.slotKey,
              newSlotKey: slot,
            ),
        ]);
      }
      return SkillsSuccess(
        value: (
          result: switch (merge) {
            null => const RemoteApplyFastForwarded(),
            RevisionMergeConflicted() => const RemoteApplyConflicted(),
            RevisionMergeClean() => RemoteApplyMerged(RevisionId(object.value)),
          },
          plan: PreparedUpdatePlan(
            kind: conflicted
                ? PreparedUpdatePlanKind.sessionCreated
                : PreparedUpdatePlanKind.published,
            businessChanges: WorkspaceBusinessChangeSet(mutations: mutations),
            revisionSelectionChanges: selections,
            recoveryIntent: UpdateRevisionRecoveryIntent(
              managedSkillId: id,
              sourceLineage: lineage,
              retainedRoots: {object, upstream}.toList(),
              candidateRecoveryReference: reference('candidate'),
              bundleRecoveryReference: reference('bundle'),
            ),
            materializationIntents: materializations,
          ),
          objectAdditions: await readRemoteStoreAdditions(
            candidateStore: store,
            liveStore: liveStore,
            cancellationToken: token,
          ),
          usedPackStaging: staged.usedPackStaging,
          verifyDraft: verifyDraft,
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

SkillsSuccess<PreparedRemoteContent> _remoteUnchanged(
  RemoteApplyResult result,
) => SkillsSuccess(
  value: (
    result: result,
    plan: null,
    objectAdditions: const [],
    usedPackStaging: const [],
    verifyDraft: null,
  ),
  changed: false,
);
