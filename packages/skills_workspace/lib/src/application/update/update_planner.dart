import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../../domain/revision_content.dart';
import '../../domain/slot_key.dart';
import '../drafts/draft_models.dart';
import '../operations/operation_models.dart';
import '../operations/workspace_business_changes.dart';
import '../ports/update_ports.dart';
import '../runtime/revision_engine_port.dart';
import '../source/source_acquisition_coordinator.dart';
import '../source/source_acquisition_models.dart';
import 'update_models.dart';

/// Read-only Update preflight.
///
/// This planner imports Source bytes only after Draft and Session guards. It
/// never calls the Revision Engine, creates a Store object, writes staging, or
/// constructs operation-scoped recovery evidence.
final class UpdatePlanner {
  const UpdatePlanner({
    required SourceAcquisitionCoordinator sourceAcquisition,
    required UpdateDraftInspectionPort drafts,
    required UpdateRevisionStatePort states,
    required UpdateSlotMigrationInspectionPort slotMigrations,
    required DateTime Function() clock,
  }) : _sourceAcquisition = sourceAcquisition,
       _drafts = drafts,
       _states = states,
       _slotMigrations = slotMigrations,
       _clock = clock;

  final SourceAcquisitionCoordinator _sourceAcquisition;
  final UpdateDraftInspectionPort _drafts;
  final UpdateRevisionStatePort _states;
  final UpdateSlotMigrationInspectionPort _slotMigrations;
  final DateTime Function() _clock;

  /// Operation-wide barrier used before a multi-Skill Update acquires any
  /// Source. [planUpdate] repeats the same authoritative checks immediately
  /// before each individual Source acquisition so a later Draft save is still
  /// observed.
  Future<UpdatePlanningResult<void>> validateUpdateBarrier({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return _failure(UpdatePlanningFailureCode.skillNotFound);
    }
    if (skill.updateCandidate != null) {
      return _failure(
        UpdatePlanningFailureCode.updateCandidateResolutionRequired,
      );
    }
    if (!skill.source.canCheckForUpdates) {
      return _failure(UpdatePlanningFailureCode.updateUnsupported);
    }
    if (token.isCancelled) return _cancelled();
    if (skill.draft != null) {
      final inspected = await _drafts.inspectForUpdate(
        skill: skill,
        cancellationToken: token,
      );
      if (inspected case UpdateDraftInspectionFailure(:final reason)) {
        return _failure(
          _draftInspectionFailureCode(reason),
          context: <String, Object?>{'reason': reason},
        );
      }
      if ((inspected as UpdateDraftInspectionSuccess).inspection.isDirty) {
        return _failure(UpdatePlanningFailureCode.dirtyDraftResolutionRequired);
      }
    }
    return const UpdatePlanningSuccess<void>(null);
  }

  /// Performs one background, read-only comparison.
  Future<UpdatePlanningResult<UpdateCheck>> checkUpdate({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    CancellationToken? cancellationToken,
  }) async => (await checkUpdates(
    snapshot: snapshot,
    managedSkillIds: <ManagedSkillId>[managedSkillId],
    cancellationToken: cancellationToken,
  ))[managedSkillId]!;

  /// Performs a batch of read-only comparisons under one Source acquisition
  /// scope, allowing Git selections with the same locator and ref to share the
  /// same temporary shallow fetch.
  Future<Map<ManagedSkillId, UpdatePlanningResult<UpdateCheck>>> checkUpdates({
    required RepositorySnapshot snapshot,
    required List<ManagedSkillId> managedSkillIds,
    CancellationToken? cancellationToken,
    void Function(
      ManagedSkillId managedSkillId,
      UpdatePlanningResult<UpdateCheck> result,
    )?
    onSettled,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final results = <ManagedSkillId, UpdatePlanningResult<UpdateCheck>>{};
    final prepared = <_PreparedUpdateCheck>[];
    final requests = <SourceAcquisitionRequest>[];

    void settle(
      ManagedSkillId managedSkillId,
      UpdatePlanningResult<UpdateCheck> result,
    ) {
      if (results.containsKey(managedSkillId)) return;
      results[managedSkillId] = result;
      onSettled?.call(managedSkillId, result);
    }

    for (final managedSkillId in managedSkillIds) {
      final skill = snapshot.findSkill(managedSkillId);
      if (skill == null) {
        settle(
          managedSkillId,
          _failure(UpdatePlanningFailureCode.skillNotFound),
        );
        continue;
      }
      if (!skill.source.canCheckForUpdates) {
        settle(
          managedSkillId,
          _failure(UpdatePlanningFailureCode.updateUnsupported),
        );
        continue;
      }
      if (token.isCancelled) {
        settle(managedSkillId, _cancelled());
        continue;
      }
      final state = await _states.readUpdateState(managedSkillId);
      if (state == null || state.managedSkillId != managedSkillId) {
        settle(
          managedSkillId,
          _failure(UpdatePlanningFailureCode.revisionStateUnavailable),
        );
        continue;
      }
      prepared.add(
        _PreparedUpdateCheck(
          managedSkillId: managedSkillId,
          skill: skill,
          state: state,
        ),
      );
      requests.add(SourceAcquisitionRequest(source: skill.source));
    }

    if (requests.isNotEmpty) {
      await _sourceAcquisition.acquireBatch(
        requests: requests,
        cancellationToken: token,
        onResult: (index, acquired) {
          final input = prepared[index];
          settle(input.managedSkillId, _evaluateCheck(input, acquired));
        },
      );
    }
    for (final input in prepared) {
      settle(input.managedSkillId, _cancelled());
    }
    return Map<ManagedSkillId, UpdatePlanningResult<UpdateCheck>>.unmodifiable(
      results,
    );
  }

  UpdatePlanningResult<UpdateCheck> _evaluateCheck(
    _PreparedUpdateCheck input,
    SourceAcquisitionResult<AcquiredSource> acquiredResult,
  ) {
    final skill = input.skill;
    final acquired = acquiredResult.valueOrNull;
    if (acquired == null) {
      final sourceFailure = acquiredResult.failureOrNull!;
      return _failure(
        sourceFailure.code == SourceAcquisitionFailureCode.operationCancelled
            ? UpdatePlanningFailureCode.operationCancelled
            : sourceFailure.code ==
                  SourceAcquisitionFailureCode.updateUnsupported
            ? UpdatePlanningFailureCode.updateUnsupported
            : UpdatePlanningFailureCode.sourceAcquisitionFailed,
        context: <String, Object?>{'sourceCode': sourceFailure.code.name},
        sourceWarnings: sourceFailure.warnings,
      );
    }
    if (!skill.source.hasSameIdentity(acquired.canonicalSource)) {
      return _failure(
        UpdatePlanningFailureCode.sourceContinuityLost,
        context: const <String, Object?>{
          'reason': 'canonicalSourceIdentityChanged',
        },
        sourceWarnings: acquiredResult.warnings,
      );
    }
    final incoming = acquired.skills
        .where(
          (candidate) => candidate.provenance.hasSameIdentity(skill.source),
        )
        .toList(growable: false);
    if (incoming.length != 1) {
      return _failure(
        UpdatePlanningFailureCode.sourceContinuityLost,
        context: <String, Object?>{
          'reason': 'selectedSkillIdentityChanged',
          'matchingSelectionCount': incoming.length,
        },
        sourceWarnings: acquiredResult.warnings,
      );
    }
    final selected = incoming.single;
    final derived = deriveSlotKeyValue(selected.declaredName);
    final incomingSlotKey = derived.value;
    if (incomingSlotKey == null || incomingSlotKey != selected.slotKey) {
      return _failure(
        UpdatePlanningFailureCode.unsupportedSkillName,
        context: <String, Object?>{
          'reason': derived.rejectionReason ?? 'sourceSlotMismatch',
        },
        sourceWarnings: acquiredResult.warnings,
      );
    }
    return UpdatePlanningSuccess<UpdateCheck>(
      UpdateCheck(
        managedSkillId: input.managedSkillId,
        currentUpstreamContentHash: input.state.previousUpstreamContentHash,
        incomingContentHash: selected.tree.contentHash,
        incomingDeclaredName: selected.declaredName,
        incomingSlotKey: incomingSlotKey,
        resolvedSourceRevision: acquired.resolvedSourceRevision,
        sourceWarnings: acquiredResult.warnings,
      ),
    );
  }

  Future<UpdatePlanningResult<PlannedUpdate>> planUpdate({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return _failure(UpdatePlanningFailureCode.skillNotFound);
    }
    if (skill.updateCandidate != null) {
      return _failure(
        UpdatePlanningFailureCode.updateCandidateResolutionRequired,
      );
    }
    if (!skill.source.canCheckForUpdates) {
      return _failure(UpdatePlanningFailureCode.updateUnsupported);
    }
    if (token.isCancelled) return _cancelled();

    var draftInspection = const UpdateDraftInspection.absent();
    if (skill.draft != null) {
      final inspected = await _drafts.inspectForUpdate(
        skill: skill,
        cancellationToken: token,
      );
      if (inspected case UpdateDraftInspectionFailure(:final reason)) {
        return _failure(
          _draftInspectionFailureCode(reason),
          context: <String, Object?>{'reason': reason},
        );
      }
      draftInspection = (inspected as UpdateDraftInspectionSuccess).inspection;
      if (draftInspection.isDirty) {
        return _failure(UpdatePlanningFailureCode.dirtyDraftResolutionRequired);
      }
    }
    if (token.isCancelled) return _cancelled();

    final state = await _states.readUpdateState(managedSkillId);
    if (state == null || state.managedSkillId != managedSkillId) {
      return _failure(UpdatePlanningFailureCode.revisionStateUnavailable);
    }
    final acquiredResult = await _sourceAcquisition.acquire(
      source: skill.source,
      selectedSkillNames: const <String>{},
      options: const SourceAcquisitionOptions(),
      cancellationToken: token,
    );
    final acquired = acquiredResult.valueOrNull;
    if (acquired == null) {
      final sourceFailure = acquiredResult.failureOrNull!;
      return _failure(
        sourceFailure.code == SourceAcquisitionFailureCode.operationCancelled
            ? UpdatePlanningFailureCode.operationCancelled
            : sourceFailure.code ==
                  SourceAcquisitionFailureCode.updateUnsupported
            ? UpdatePlanningFailureCode.updateUnsupported
            : UpdatePlanningFailureCode.sourceAcquisitionFailed,
        context: <String, Object?>{'sourceCode': sourceFailure.code.name},
        sourceWarnings: sourceFailure.warnings,
      );
    }
    if (!skill.source.hasSameIdentity(acquired.canonicalSource)) {
      return _failure(
        UpdatePlanningFailureCode.sourceContinuityLost,
        context: const <String, Object?>{
          'reason': 'canonicalSourceIdentityChanged',
        },
        sourceWarnings: acquiredResult.warnings,
      );
    }
    final incoming = acquired.skills
        .where(
          (candidate) => candidate.provenance.hasSameIdentity(skill.source),
        )
        .toList(growable: false);
    if (incoming.length != 1) {
      return _failure(
        UpdatePlanningFailureCode.sourceContinuityLost,
        context: <String, Object?>{
          'reason': 'selectedSkillIdentityChanged',
          'matchingSelectionCount': incoming.length,
        },
        sourceWarnings: acquiredResult.warnings,
      );
    }
    final selected = incoming.single;
    if (selected.tree.contentHash == state.previousUpstreamContentHash) {
      return UpdatePlanningSuccess<PlannedUpdate>(
        UpdateNoChange(
          managedSkillId: managedSkillId,
          contentHash: selected.tree.contentHash,
          sourceWarnings: acquiredResult.warnings,
        ),
      );
    }
    final derived = deriveSlotKeyValue(selected.declaredName);
    final incomingSlotKey = derived.value;
    if (incomingSlotKey == null || incomingSlotKey != selected.slotKey) {
      return _failure(
        UpdatePlanningFailureCode.unsupportedSkillName,
        context: <String, Object?>{
          'reason': derived.rejectionReason ?? 'sourceSlotMismatch',
        },
        sourceWarnings: acquiredResult.warnings,
      );
    }
    if (incomingSlotKey != skill.slotKey) {
      final occupied = snapshot.findSkillBySlotKey(incomingSlotKey);
      if (occupied != null && occupied.id != managedSkillId) {
        return _failure(
          UpdatePlanningFailureCode.slotMigrationConflict,
          context: <String, Object?>{'slotKey': incomingSlotKey},
          sourceWarnings: acquiredResult.warnings,
        );
      }
      final migration = await _slotMigrations.inspect(
        snapshot: snapshot,
        skill: skill,
        newSlotKey: incomingSlotKey,
        cancellationToken: token,
      );
      if (migration case UpdateSlotMigrationInspectionFailure(:final reason)) {
        return _failure(
          UpdatePlanningFailureCode.slotMigrationConflict,
          context: <String, Object?>{
            'slotKey': incomingSlotKey,
            'reason': reason,
          },
          sourceWarnings: acquiredResult.warnings,
        );
      }
    }
    if (token.isCancelled) return _cancelled();

    final intent = UpdateRevisionPreparationIntent(
      managedSkillId: managedSkillId,
      expectedRepositoryRevision: snapshot.revision,
      sourceLineage: state.sourceLineage,
      previousUpstream: state.previousUpstream,
      currentEffective: state.currentEffective,
      currentSlotKey: skill.slotKey,
      currentDeclaredName: skill.declaredName,
      currentDisplayName: skill.displayName,
      activations: skill.activations,
      managedSkillCreatedAtMicros: state.managedSkillCreatedAtMicros,
      draftCreatedAtMicros: state.draftCreatedAtMicros,
      incomingTree: selected.tree,
      incomingDeclaredName: selected.declaredName,
      incomingDescription: selected.description,
      incomingSlotKey: incomingSlotKey,
      resolvedSourceRevision: acquired.resolvedSourceRevision,
      hadCleanDraft: draftInspection.hasCleanDraft,
    );
    return UpdatePlanningSuccess<PlannedUpdate>(
      UpdatePreparationRequired(
        managedSkillId: managedSkillId,
        snapshotRevision: snapshot.revision,
        plannedAtMicros: _clock().toUtc().microsecondsSinceEpoch,
        currentSkill: skill,
        revisionState: state,
        intent: intent,
        sourceWarnings: acquiredResult.warnings,
      ),
    );
  }
}

final class _PreparedUpdateCheck {
  const _PreparedUpdateCheck({
    required this.managedSkillId,
    required this.skill,
    required this.state,
  });

  final ManagedSkillId managedSkillId;
  final ManagedSkill skill;
  final UpdateRevisionState state;
}

UpdatePlanningFailureCode _draftInspectionFailureCode(String reason) =>
    reason == 'operationCancelled'
    ? UpdatePlanningFailureCode.operationCancelled
    : UpdatePlanningFailureCode.draftInspectionFailed;

/// Read-only preflight for publishing or abandoning a persisted Session.
final class UpdateCandidatePlanner {
  const UpdateCandidatePlanner({
    required UpdateCandidateStatePort states,
    required UpdateSlotMigrationInspectionPort slotMigrations,
    required DateTime Function() clock,
  }) : _states = states,
       _slotMigrations = slotMigrations,
       _clock = clock;

  final UpdateCandidateStatePort _states;
  final UpdateSlotMigrationInspectionPort _slotMigrations;
  final DateTime Function() _clock;

  Future<UpdatePlanningResult<UpdateConflictResolutionPlan>> planResolution({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required String path,
    required UpdateConflictResolutionState resolutionState,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return _failure(UpdatePlanningFailureCode.skillNotFound);
    }
    if (skill.updateCandidate == null) {
      return _failure(UpdatePlanningFailureCode.updateCandidateNotFound);
    }
    if (token.isCancelled) return _cancelled();
    final state = await _states.readCandidateState(
      managedSkillId,
      cancellationToken: token,
    );
    if (state == null || state.managedSkillId != managedSkillId) {
      return _failure(UpdatePlanningFailureCode.updateCandidateNotFound);
    }
    final matches = state.conflicts.where((item) => item.path == path).toList();
    if (matches.length != 1) {
      return _failure(
        UpdatePlanningFailureCode.updateConflictNotFound,
        context: <String, Object?>{'path': path},
      );
    }
    final intended = switch (resolutionState) {
      UpdateConflictResolutionState.unresolved =>
        WorkspaceUpdateCandidateItemState.unresolved,
      UpdateConflictResolutionState.resolved =>
        WorkspaceUpdateCandidateItemState.resolved,
    };
    if (matches.single.state == intended) {
      return const UpdatePlanningSuccess<UpdateConflictResolutionPlan>(
        UpdateConflictResolutionPlan(
          changed: false,
          businessChanges: WorkspaceBusinessChangeSet.empty,
        ),
      );
    }
    return UpdatePlanningSuccess<UpdateConflictResolutionPlan>(
      UpdateConflictResolutionPlan(
        changed: true,
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            SetUpdateCandidateItemResolution(
              managedSkillId: managedSkillId,
              path: path,
              state: intended,
              updatedAtMicros: _clock().toUtc().microsecondsSinceEpoch,
            ),
          ],
        ),
      ),
    );
  }

  Future<UpdatePlanningResult<UpdateCandidatePublishPreflight>> planPublish({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return _failure(UpdatePlanningFailureCode.skillNotFound);
    }
    if (skill.updateCandidate == null) {
      return _failure(UpdatePlanningFailureCode.updateCandidateNotFound);
    }
    if (token.isCancelled) return _cancelled();
    final state = await _states.readCandidateState(
      managedSkillId,
      cancellationToken: token,
    );
    if (state == null || state.managedSkillId != managedSkillId) {
      return _failure(UpdatePlanningFailureCode.updateCandidateNotFound);
    }
    if (state.hasUnresolvedConflicts) {
      return _failure(UpdatePlanningFailureCode.unresolvedUpdateConflicts);
    }
    if (state.incomingSlotKey != skill.slotKey) {
      final occupied = snapshot.findSkillBySlotKey(state.incomingSlotKey);
      if (occupied != null && occupied.id != managedSkillId) {
        return _failure(
          UpdatePlanningFailureCode.slotMigrationConflict,
          context: <String, Object?>{'slotKey': state.incomingSlotKey},
        );
      }
      final migration = await _slotMigrations.inspect(
        snapshot: snapshot,
        skill: skill,
        newSlotKey: state.incomingSlotKey,
        cancellationToken: token,
      );
      if (migration case UpdateSlotMigrationInspectionFailure(:final reason)) {
        return _failure(
          UpdatePlanningFailureCode.slotMigrationConflict,
          context: <String, Object?>{
            'slotKey': state.incomingSlotKey,
            'reason': reason,
          },
        );
      }
    }
    return UpdatePlanningSuccess<UpdateCandidatePublishPreflight>(
      UpdateCandidatePublishPreflight(
        snapshotRevision: snapshot.revision,
        plannedAtMicros: _clock().toUtc().microsecondsSinceEpoch,
        currentSkill: skill,
        state: state,
        intent: UpdateCandidatePublishPreparationIntent(
          managedSkillId: managedSkillId,
          expectedRepositoryRevision: snapshot.revision,
          sourceLineage: state.sourceLineage,
          previousUpstream: state.previousUpstream,
          previousEffective: state.previousEffective,
          incomingUpstream: state.incomingUpstream,
          candidateObjectId: state.candidateObjectId,
          requiredDeclaredName: state.incomingDeclaredName,
          currentSlotKey: skill.slotKey,
          currentDeclaredName: skill.declaredName,
          currentDisplayName: skill.displayName,
          activations: skill.activations,
          incomingSlotKey: state.incomingSlotKey,
          incomingDescription: state.incomingDescription,
          managedSkillCreatedAtMicros: state.managedSkillCreatedAtMicros,
          draftCreatedAtMicros: state.draftCreatedAtMicros,
        ),
      ),
    );
  }

  Future<UpdatePlanningResult<UpdateCandidateAbandonPlan>> planAbandon({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) {
      return _failure(UpdatePlanningFailureCode.skillNotFound);
    }
    if (skill.updateCandidate == null) {
      return _failure(UpdatePlanningFailureCode.updateCandidateNotFound);
    }
    if (token.isCancelled) return _cancelled();
    final state = await _states.readCandidateState(
      managedSkillId,
      cancellationToken: token,
    );
    if (state == null || state.managedSkillId != managedSkillId) {
      return _failure(UpdatePlanningFailureCode.updateCandidateNotFound);
    }
    return UpdatePlanningSuccess<UpdateCandidateAbandonPlan>(
      UpdateCandidateAbandonPlan(
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            DeleteUpdateCandidateSession(managedSkillId),
            DeleteDraftWorkspace(managedSkillId),
          ],
        ),
        revisionSelectionChanges: const <RevisionSelectionChangePlan>[],
        cleanupIntent: UpdateCandidateCleanupIntent(
          managedSkillId: managedSkillId,
          sourceLineage: state.sourceLineage,
          previousUpstream: state.previousUpstream,
          previousEffective: state.previousEffective,
          incomingUpstream: state.incomingUpstream,
          candidateObjectId: state.candidateObjectId,
          retainedPublishedRoots: <RevisionObjectId>{
            state.previousUpstream,
            state.previousEffective,
            ...state.retainedPublishedRoots,
          }.toList(growable: false),
        ),
      ),
    );
  }
}

/// Validates post-Journal evidence and compiles complete business intents.
///
/// Integrating this assembler requires a Coordinator envelope that journals
/// the preflight intent before [UpdateRevisionPreparationPort] runs. The
/// existing generic [OperationPlan] does not yet encode that two-stage update
/// specialization; this class deliberately does not bypass that missing seam.
final class UpdatePlanAssembler {
  const UpdatePlanAssembler();

  UpdatePlanningResult<PreparedUpdatePlan> assembleUpdate({
    required UpdatePreparationRequired preflight,
    required PreparedUpdateRevision prepared,
  }) {
    final intent = preflight.intent;
    if (!_samePreparedIdentity(intent, prepared) ||
        !_matchesCommit(
          prepared.incomingRequest,
          kind: RevisionCommitKind.upstream,
          tree: prepared.incomingTreeObjectId,
          parents: <RevisionObjectId>[intent.previousUpstream],
        )) {
      return _invalidEvidence();
    }
    final incomingAddress = RevisionAddress(
      sourceLineage: intent.sourceLineage,
      objectId: prepared.incomingUpstreamObjectId,
    );
    final previousUpstream = RevisionAddress(
      sourceLineage: intent.sourceLineage,
      objectId: intent.previousUpstream,
    );
    final previousEffective = RevisionAddress(
      sourceLineage: intent.sourceLineage,
      objectId: intent.currentEffective,
    );
    final timestamp = preflight.plannedAtMicros;
    final commonMutations = <WorkspaceBusinessMutation>[
      PutRevisionMetadata(
        sourceLineageId: intent.sourceLineage.encoded,
        objectId: prepared.incomingUpstreamObjectId.value,
        contentHash: intent.incomingTree.contentHash,
        fileCount: intent.incomingTree.fileCount,
        byteSize: intent.incomingTree.byteSize,
        declaredName: intent.incomingDeclaredName,
        validationState: WorkspaceRevisionValidationState.valid,
        validationCode: null,
        createdAtMicros: timestamp,
      ),
    ];

    return switch (prepared.outcome) {
      PreparedUpdateClean() => _assembleCleanUpdate(
        preflight: preflight,
        prepared: prepared,
        outcome: prepared.outcome as PreparedUpdateClean,
        commonMutations: commonMutations,
        previousUpstream: previousUpstream,
        previousEffective: previousEffective,
        incomingAddress: incomingAddress,
      ),
      PreparedUpdateConflict() => _assembleSession(
        preflight: preflight,
        prepared: prepared,
        candidateObjectId:
            (prepared.outcome as PreparedUpdateConflict).candidateObjectId,
        candidateTree:
            (prepared.outcome as PreparedUpdateConflict).candidateTree,
        status: WorkspaceUpdateCandidateStatus.conflicted,
        validationCode: null,
        items: (prepared.outcome as PreparedUpdateConflict).conflicts,
        commonMutations: commonMutations,
      ),
      PreparedUpdateValidationFailure() => _assembleSession(
        preflight: preflight,
        prepared: prepared,
        candidateObjectId: (prepared.outcome as PreparedUpdateValidationFailure)
            .candidateObjectId,
        candidateTree:
            (prepared.outcome as PreparedUpdateValidationFailure).candidateTree,
        status: WorkspaceUpdateCandidateStatus.validationFailed,
        validationCode: (prepared.outcome as PreparedUpdateValidationFailure)
            .validationCode,
        items: const <WorkspaceUpdateCandidateItem>[],
        commonMutations: commonMutations,
      ),
    };
  }

  UpdatePlanningResult<PreparedUpdatePlan> assembleCandidatePublish({
    required UpdateCandidatePublishPreflight preflight,
    required PreparedUpdateCandidatePublish prepared,
  }) {
    final state = preflight.state;
    final intent = preflight.intent;
    if (prepared.managedSkillId != state.managedSkillId ||
        prepared.sourceLineage != state.sourceLineage ||
        !_matchesCommit(
          prepared.effectiveRequest,
          kind: RevisionCommitKind.effectiveUpdate,
          tree: prepared.publishedTreeObjectId,
          parents: <RevisionObjectId>[
            state.previousEffective,
            state.incomingUpstream,
          ],
        )) {
      return _invalidEvidence();
    }
    if (prepared.declaredName != preflight.intent.requiredDeclaredName) {
      return _failure(UpdatePlanningFailureCode.declaredNameChangeNotAllowed);
    }
    final effective = RevisionAddress(
      sourceLineage: state.sourceLineage,
      objectId: prepared.effectiveObjectId,
    );
    final mutations = <WorkspaceBusinessMutation>[
      PutRevisionMetadata(
        sourceLineageId: state.sourceLineage.encoded,
        objectId: prepared.effectiveObjectId.value,
        contentHash: prepared.publishedTree.contentHash,
        fileCount: prepared.publishedTree.fileCount,
        byteSize: prepared.publishedTree.byteSize,
        declaredName: prepared.declaredName,
        validationState: WorkspaceRevisionValidationState.valid,
        validationCode: null,
        createdAtMicros: preflight.plannedAtMicros,
      ),
      _managedSkillMutation(
        managedSkillId: intent.managedSkillId,
        currentDeclaredName: intent.currentDeclaredName,
        currentDisplayName: intent.currentDisplayName,
        declaredName: prepared.declaredName,
        slotKey: intent.incomingSlotKey,
        description: prepared.description,
        sourceLineage: state.sourceLineage,
        createdAtMicros: intent.managedSkillCreatedAtMicros,
        updatedAtMicros: preflight.plannedAtMicros,
      ),
      DeleteUpdateCandidateSession(state.managedSkillId),
      ..._draftMutations(
        disposition: prepared.draftDisposition,
        managedSkillId: state.managedSkillId,
        sourceLineage: state.sourceLineage,
        newBase: prepared.effectiveObjectId,
        draftCreatedAtMicros: state.draftCreatedAtMicros,
        updatedAtMicros: preflight.plannedAtMicros,
      ),
    ];
    return UpdatePlanningSuccess<PreparedUpdatePlan>(
      PreparedUpdatePlan(
        kind: PreparedUpdatePlanKind.published,
        businessChanges: WorkspaceBusinessChangeSet(mutations: mutations),
        revisionSelectionChanges: <RevisionSelectionChangePlan>[
          RevisionSelectionChangePlan(
            managedSkillId: state.managedSkillId,
            previousUpstream: RevisionAddress(
              sourceLineage: state.sourceLineage,
              objectId: state.previousUpstream,
            ),
            previousEffective: RevisionAddress(
              sourceLineage: state.sourceLineage,
              objectId: state.previousEffective,
            ),
            intendedUpstream: RevisionAddress(
              sourceLineage: state.sourceLineage,
              objectId: state.incomingUpstream,
            ),
            intendedEffective: effective,
          ),
        ],
        recoveryIntent: UpdateRevisionRecoveryIntent(
          managedSkillId: state.managedSkillId,
          sourceLineage: state.sourceLineage,
          retainedRoots: <RevisionObjectId>[prepared.effectiveObjectId],
          candidateRecoveryReference: prepared.candidateRecoveryReference,
          bundleRecoveryReference: prepared.bundleRecoveryReference,
          draftCleanup: PublishedDraftCleanupIntent(
            managedSkillId: state.managedSkillId,
            expectedBaseObjectId: prepared.effectiveObjectId,
            capturedFingerprint: prepared.capturedDraftFingerprint,
          ),
        ),
        materializationIntents: _publishedMaterializations(
          managedSkillId: intent.managedSkillId,
          oldSlotKey: intent.currentSlotKey,
          activations: intent.activations,
          newSlotKey: intent.incomingSlotKey,
          effective: effective,
          recoveryReference: prepared.materializationRecoveryReference,
        ),
      ),
    );
  }

  UpdatePlanningResult<PreparedUpdatePlan> _assembleCleanUpdate({
    required UpdatePreparationRequired preflight,
    required PreparedUpdateRevision prepared,
    required PreparedUpdateClean outcome,
    required List<WorkspaceBusinessMutation> commonMutations,
    required RevisionAddress previousUpstream,
    required RevisionAddress previousEffective,
    required RevisionAddress incomingAddress,
  }) {
    final intent = preflight.intent;
    if (!_matchesCommit(
          outcome.effectiveRequest,
          kind: RevisionCommitKind.effectiveUpdate,
          tree: outcome.mergedTreeObjectId,
          parents: <RevisionObjectId>[
            intent.currentEffective,
            prepared.incomingUpstreamObjectId,
          ],
        ) ||
        outcome.declaredName != intent.incomingDeclaredName) {
      return _invalidEvidence();
    }
    if (!_validDraftDisposition(
      hadCleanDraft: intent.hadCleanDraft,
      disposition: outcome.draftDisposition,
    )) {
      return _invalidEvidence();
    }
    final effectiveAddress = RevisionAddress(
      sourceLineage: intent.sourceLineage,
      objectId: outcome.effectiveObjectId,
    );
    final mutations = <WorkspaceBusinessMutation>[
      ...commonMutations,
      PutRevisionMetadata(
        sourceLineageId: intent.sourceLineage.encoded,
        objectId: outcome.effectiveObjectId.value,
        contentHash: outcome.mergedTree.contentHash,
        fileCount: outcome.mergedTree.fileCount,
        byteSize: outcome.mergedTree.byteSize,
        declaredName: outcome.declaredName,
        validationState: WorkspaceRevisionValidationState.valid,
        validationCode: null,
        createdAtMicros: preflight.plannedAtMicros,
      ),
      _managedSkillMutation(
        managedSkillId: intent.managedSkillId,
        currentDeclaredName: intent.currentDeclaredName,
        currentDisplayName: intent.currentDisplayName,
        declaredName: outcome.declaredName,
        slotKey: intent.incomingSlotKey,
        description: outcome.description,
        sourceLineage: intent.sourceLineage,
        createdAtMicros: intent.managedSkillCreatedAtMicros,
        updatedAtMicros: preflight.plannedAtMicros,
      ),
      ..._draftMutations(
        disposition: outcome.draftDisposition,
        managedSkillId: intent.managedSkillId,
        sourceLineage: intent.sourceLineage,
        newBase: outcome.effectiveObjectId,
        draftCreatedAtMicros: intent.draftCreatedAtMicros,
        updatedAtMicros: preflight.plannedAtMicros,
      ),
    ];
    return UpdatePlanningSuccess<PreparedUpdatePlan>(
      PreparedUpdatePlan(
        kind: PreparedUpdatePlanKind.published,
        businessChanges: WorkspaceBusinessChangeSet(mutations: mutations),
        revisionSelectionChanges: <RevisionSelectionChangePlan>[
          RevisionSelectionChangePlan(
            managedSkillId: intent.managedSkillId,
            previousUpstream: previousUpstream,
            previousEffective: previousEffective,
            intendedUpstream: incomingAddress,
            intendedEffective: effectiveAddress,
          ),
        ],
        recoveryIntent: UpdateRevisionRecoveryIntent(
          managedSkillId: intent.managedSkillId,
          sourceLineage: intent.sourceLineage,
          retainedRoots: <RevisionObjectId>[outcome.effectiveObjectId],
          candidateRecoveryReference: prepared.candidateRecoveryReference,
          bundleRecoveryReference: prepared.bundleRecoveryReference,
          draftCleanup: outcome.capturedDraftFingerprint == null
              ? null
              : PublishedDraftCleanupIntent(
                  managedSkillId: intent.managedSkillId,
                  expectedBaseObjectId: outcome.effectiveObjectId,
                  capturedFingerprint: outcome.capturedDraftFingerprint!,
                ),
        ),
        materializationIntents: _publishedMaterializations(
          managedSkillId: intent.managedSkillId,
          oldSlotKey: intent.currentSlotKey,
          activations: intent.activations,
          newSlotKey: intent.incomingSlotKey,
          effective: effectiveAddress,
          recoveryReference: prepared.materializationRecoveryReference,
        ),
      ),
    );
  }

  UpdatePlanningResult<PreparedUpdatePlan> _assembleSession({
    required UpdatePreparationRequired preflight,
    required PreparedUpdateRevision prepared,
    required RevisionObjectId candidateObjectId,
    required NormalizedSkillTree candidateTree,
    required WorkspaceUpdateCandidateStatus status,
    required String? validationCode,
    required List<WorkspaceUpdateCandidateItem> items,
    required List<WorkspaceBusinessMutation> commonMutations,
  }) {
    final intent = preflight.intent;
    final candidateAddress = RevisionAddress(
      sourceLineage: intent.sourceLineage,
      objectId: candidateObjectId,
    );
    final candidateValidationCode = validationCode ?? 'updateMergeConflict';
    return UpdatePlanningSuccess<PreparedUpdatePlan>(
      PreparedUpdatePlan(
        kind: PreparedUpdatePlanKind.sessionCreated,
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            ...commonMutations,
            PutRevisionMetadata(
              sourceLineageId: intent.sourceLineage.encoded,
              objectId: candidateObjectId.value,
              contentHash: candidateTree.contentHash,
              fileCount: candidateTree.fileCount,
              byteSize: candidateTree.byteSize,
              declaredName: intent.incomingDeclaredName,
              validationState: WorkspaceRevisionValidationState.invalid,
              validationCode: candidateValidationCode,
              createdAtMicros: preflight.plannedAtMicros,
            ),
            PutUpdateCandidateSession(
              managedSkillId: intent.managedSkillId,
              sourceLineageId: intent.sourceLineage.encoded,
              previousUpstreamObjectId: intent.previousUpstream.value,
              previousEffectiveObjectId: intent.currentEffective.value,
              incomingUpstreamObjectId: prepared.incomingUpstreamObjectId.value,
              candidateObjectId: candidateObjectId.value,
              status: status,
              validationCode: validationCode,
              items: items,
              createdAtMicros: preflight.plannedAtMicros,
              updatedAtMicros: preflight.plannedAtMicros,
            ),
            PutDraftWorkspace(
              managedSkillId: intent.managedSkillId,
              sourceLineageId: intent.sourceLineage.encoded,
              baseObjectId: candidateObjectId.value,
              purpose: WorkspaceDraftPurpose.updateCandidateResolution,
              createdAtMicros: preflight.plannedAtMicros,
              updatedAtMicros: preflight.plannedAtMicros,
            ),
          ],
        ),
        revisionSelectionChanges: const <RevisionSelectionChangePlan>[],
        recoveryIntent: UpdateRevisionRecoveryIntent(
          managedSkillId: intent.managedSkillId,
          sourceLineage: intent.sourceLineage,
          retainedRoots: <RevisionObjectId>[
            intent.previousUpstream,
            intent.currentEffective,
            prepared.incomingUpstreamObjectId,
            candidateObjectId,
          ],
          candidateRecoveryReference: prepared.candidateRecoveryReference,
          bundleRecoveryReference: prepared.bundleRecoveryReference,
        ),
        materializationIntents: <UpdateMaterializationIntent>[
          UpdateCandidateDraftMaterializationIntent(
            managedSkillId: intent.managedSkillId,
            revision: candidateAddress,
            recoveryReference: prepared.materializationRecoveryReference,
            draftRecoveryReference: prepared.draftRecoveryReference,
          ),
        ],
      ),
    );
  }
}

List<UpdateMaterializationIntent> _publishedMaterializations({
  required ManagedSkillId managedSkillId,
  required String oldSlotKey,
  required List<SkillActivation> activations,
  required String newSlotKey,
  required RevisionAddress effective,
  required RecoveryReference recoveryReference,
}) => <UpdateMaterializationIntent>[
  UpdateRepositoryMaterializationIntent(
    managedSkillId: managedSkillId,
    revision: effective,
    recoveryReference: recoveryReference,
    oldSlotKey: oldSlotKey,
    newSlotKey: newSlotKey,
  ),
  for (final activation in activations)
    UpdateActivationMaterializationIntent(
      managedSkillId: managedSkillId,
      revision: effective,
      recoveryReference: recoveryReference,
      activation: activation,
      oldSlotKey: oldSlotKey,
      newSlotKey: newSlotKey,
    ),
];

PutManagedSkill _managedSkillMutation({
  required ManagedSkillId managedSkillId,
  required String currentDeclaredName,
  required String currentDisplayName,
  required String declaredName,
  required String slotKey,
  required String description,
  required SourceLineageReference sourceLineage,
  required int createdAtMicros,
  required int updatedAtMicros,
}) => PutManagedSkill(
  managedSkillId: managedSkillId,
  slotKey: slotKey,
  declaredName: declaredName,
  displayName: currentDisplayName == currentDeclaredName
      ? declaredName
      : currentDisplayName,
  description: description,
  activeSourceLineageId: sourceLineage.encoded,
  createdAtMicros: createdAtMicros,
  updatedAtMicros: updatedAtMicros,
);

List<WorkspaceBusinessMutation> _draftMutations({
  required UpdateDraftDisposition disposition,
  required ManagedSkillId managedSkillId,
  required SourceLineageReference sourceLineage,
  required RevisionObjectId newBase,
  required int? draftCreatedAtMicros,
  required int updatedAtMicros,
}) => switch (disposition) {
  UpdateDraftDisposition.noDraft => const <WorkspaceBusinessMutation>[],
  UpdateDraftDisposition.deleteUnchanged ||
  UpdateDraftDisposition.preserveAndReanchor => <WorkspaceBusinessMutation>[
    PutDraftWorkspace(
      managedSkillId: managedSkillId,
      sourceLineageId: sourceLineage.encoded,
      baseObjectId: newBase.value,
      purpose: WorkspaceDraftPurpose.customization,
      createdAtMicros: draftCreatedAtMicros ?? updatedAtMicros,
      updatedAtMicros: updatedAtMicros,
    ),
  ],
};

bool _validDraftDisposition({
  required bool hadCleanDraft,
  required UpdateDraftDisposition disposition,
}) => hadCleanDraft
    ? disposition != UpdateDraftDisposition.noDraft
    : disposition == UpdateDraftDisposition.noDraft;

bool _samePreparedIdentity(
  UpdateRevisionPreparationIntent intent,
  PreparedUpdateRevision prepared,
) =>
    prepared.managedSkillId == intent.managedSkillId &&
    prepared.sourceLineage == intent.sourceLineage;

bool _matchesCommit(
  RevisionCommitRequest actual, {
  required RevisionCommitKind kind,
  required RevisionObjectId tree,
  required List<RevisionObjectId> parents,
}) {
  if (actual.kind != kind || actual.tree != tree) return false;
  if (actual.parents.length != parents.length) return false;
  for (var index = 0; index < parents.length; index += 1) {
    if (actual.parents[index] != parents[index]) return false;
  }
  return true;
}

UpdatePlanningFailure<T> _invalidEvidence<T>() =>
    _failure(UpdatePlanningFailureCode.invalidPreparedEvidence);

UpdatePlanningFailure<T> _cancelled<T>() =>
    _failure(UpdatePlanningFailureCode.operationCancelled);

UpdatePlanningFailure<T> _failure<T>(
  UpdatePlanningFailureCode code, {
  Map<String, Object?> context = const <String, Object?>{},
  List<SourceAcquisitionWarning> sourceWarnings =
      const <SourceAcquisitionWarning>[],
}) => UpdatePlanningFailure<T>(
  code: code,
  context: context,
  sourceWarnings: sourceWarnings,
);
