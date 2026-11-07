import 'package:drift/drift.dart';

import '../../application/operations/operation_models.dart';
import '../../application/operations/workspace_business_changes.dart';
import '../../application/ports/operation_ports.dart';
import '../../domain/identifiers.dart';
import 'operation_plan_codec.dart';
import 'workspace_database.dart';

typedef OperationControlPlaneClock = int Function();

/// A fail-closed durable-state error raised before a control-plane mutation.
final class OperationControlPlaneStateException implements Exception {
  const OperationControlPlaneStateException(this.reason);

  final String reason;

  @override
  String toString() => 'OperationControlPlaneStateException($reason)';
}

/// Drift-backed implementation of the operation Journal and Business Commit
/// Point.
///
/// Every method that changes durable state owns one SQLite transaction. Plan
/// values are replayed verbatim; the adapter never derives business rows from
/// the current wall clock or from filesystem state.
final class DriftOperationControlPlane implements OperationControlPlanePort {
  DriftOperationControlPlane({
    required WorkspaceDatabase database,
    OperationPlanCodec codec = const OperationPlanCodec(),
    OperationControlPlaneClock? clock,
  }) : _database = database,
       _codec = codec,
       _clock = clock ?? _utcMicros;

  final WorkspaceDatabase _database;
  final OperationPlanCodec _codec;
  final OperationControlPlaneClock _clock;

  @override
  Future<RepositoryRevision> readRepositoryRevision() async {
    final metadata = await _database
        .select(_database.workspaceMetadata)
        .getSingle();
    return RepositoryRevision(metadata.repositoryRevision);
  }

  @override
  Future<void> persistPrepared(OperationPlan plan) =>
      _persistPreparedDefinition(plan);

  @override
  Future<void> persistPreparedEnvelope(PreparedOperationEnvelope envelope) =>
      _persistPreparedDefinition(envelope);

  Future<void> _persistPreparedDefinition(
    OperationJournalDefinition definition,
  ) => _database.transaction(() async {
    await _requireRepositoryRevision(definition.expectedRepositoryRevision);
    final payload = _codec.encodeDefinition(definition);
    final now = _clock();
    await _database
        .into(_database.operationJournals)
        .insert(
          OperationJournalsCompanion.insert(
            operationId: definition.operationId.value,
            kind: definition.record.kind,
            phase: OperationJournalPhase.prepared.name,
            planSchemaVersion: OperationPlanCodec.currentSchemaVersion,
            planJson: payload,
            operationGeneration: definition.operationGeneration,
            startedAtMicros: now,
            updatedAtMicros: now,
          ),
        );

    var sequence = 0;
    for (final step in _definitionSteps(definition)) {
      await _database
          .into(_database.operationJournalSteps)
          .insert(
            OperationJournalStepsCompanion.insert(
              operationId: definition.operationId.value,
              sequence: sequence,
              stepId: step.stepId,
              kind: _stepKind(step),
              status: OperationStepStatus.planned.name,
              recoveryReference: step.recoveryReference.encoded,
            ),
          );
      sequence += 1;
    }
  });

  @override
  Future<void> sealPreparedPlan(
    PreparedOperationEnvelope envelope,
    OperationPlan plan,
  ) => _database.transaction(() async {
    await _requireRepositoryRevision(envelope.expectedRepositoryRevision);
    if (!envelope.isSealedBy(plan)) {
      throw const OperationControlPlaneStateException(
        'sealedPlanDoesNotPreserveEnvelope',
      );
    }
    final journal = await _requireJournal(envelope.operationId);
    _requirePhase(journal, OperationJournalPhase.prepared);
    final durable = _decodeJournalDefinition(journal);
    if (durable is OperationPlan) {
      if (journal.planJson == _codec.encode(plan)) return;
      throw const OperationControlPlaneStateException(
        'preparedJournalAlreadySealed',
      );
    }
    if (journal.planJson != _codec.encodeDefinition(envelope) ||
        !_sameEnvelope(durable as PreparedOperationEnvelope, envelope)) {
      throw const OperationControlPlaneStateException(
        'journalEnvelopeMismatch',
      );
    }

    final existing =
        await (_database.select(_database.operationJournalSteps)
              ..where(
                (row) => row.operationId.equals(envelope.operationId.value),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
            .get();
    if (existing.length != envelope.preparationSteps.length) {
      throw const OperationControlPlaneStateException('journalStepSetMismatch');
    }
    for (var index = 0; index < existing.length; index += 1) {
      final row = existing[index];
      final expected = envelope.preparationSteps[index];
      if (row.sequence != index ||
          row.stepId != expected.stepId ||
          row.kind != _stepKind(expected) ||
          row.recoveryReference != expected.recoveryReference.encoded) {
        throw const OperationControlPlaneStateException(
          'journalStepSetMismatch',
        );
      }
      _parseStepStatus(row.status);
    }

    final sealedSteps = _allSteps(plan);
    for (
      var sequence = existing.length;
      sequence < sealedSteps.length;
      sequence += 1
    ) {
      final step = sealedSteps[sequence];
      await _database
          .into(_database.operationJournalSteps)
          .insert(
            OperationJournalStepsCompanion.insert(
              operationId: plan.operationId.value,
              sequence: sequence,
              stepId: step.stepId,
              kind: _stepKind(step),
              status: OperationStepStatus.planned.name,
              recoveryReference: step.recoveryReference.encoded,
            ),
          );
    }
    await (_database.update(
      _database.operationJournals,
    )..where((row) => row.operationId.equals(plan.operationId.value))).write(
      OperationJournalsCompanion(
        planJson: Value(_codec.encode(plan)),
        updatedAtMicros: Value(_clock()),
      ),
    );
  });

  @override
  Future<void> markApplying(OperationId operationId) => _transitionPhase(
    operationId,
    from: OperationJournalPhase.prepared,
    to: OperationJournalPhase.applying,
  );

  @override
  Future<void> markFinalizing(OperationId operationId) => _transitionPhase(
    operationId,
    from: OperationJournalPhase.committed,
    to: OperationJournalPhase.finalizing,
  );

  @override
  Future<void> markStepStarted(OperationId operationId, String stepId) =>
      _transitionStep(operationId, stepId, target: OperationStepStatus.started);

  @override
  Future<void> markStepCompleted(OperationId operationId, String stepId) =>
      _transitionStep(
        operationId,
        stepId,
        target: OperationStepStatus.completed,
      );

  @override
  Future<void> commitBusinessState(OperationPlan plan) =>
      _database.transaction(() async {
        await _requireRepositoryRevision(plan.expectedRepositoryRevision);
        final journal = await _requireJournal(plan.operationId);
        _requireJournalMatchesPlan(journal, plan);
        _requirePhase(journal, OperationJournalPhase.applying);

        // Validate every old pointer before any ordered mutation can cascade it
        // away (especially Removal and Source Replacement).
        for (final change in plan.revisionSelectionChanges) {
          await _requirePreviousSelection(change);
        }

        for (final mutation in plan.businessChanges.mutations) {
          await _applyBusinessMutation(mutation);
        }
        for (final change in plan.revisionSelectionChanges) {
          await _applyIntendedSelection(change);
        }

        final metadata = await _database
            .select(_database.workspaceMetadata)
            .getSingle();
        final now = _clock();
        await (_database.update(
          _database.workspaceMetadata,
        )..where((row) => row.singleton.equals(1))).write(
          WorkspaceMetadataCompanion(
            repositoryRevision: Value(plan.committedRepositoryRevision.value),
            destructionEpoch: Value(
              metadata.destructionEpoch +
                  (plan.businessChanges.incrementsDestructionEpoch ? 1 : 0),
            ),
            updatedAtMicros: Value(now),
          ),
        );
        await (_database.update(_database.operationJournals)
              ..where((row) => row.operationId.equals(plan.operationId.value)))
            .write(
              OperationJournalsCompanion(
                phase: Value(OperationJournalPhase.committed.name),
                committedRepositoryRevision: Value(
                  plan.committedRepositoryRevision.value,
                ),
                updatedAtMicros: Value(now),
              ),
            );
      });

  @override
  Future<void> applyFinalizationEffect(
    OperationId operationId,
    OperationFinalizationEffect effect,
  ) => _database.transaction(() async {
    final journal = await _requireJournal(operationId);
    final phase = _parsePhase(journal.phase);
    if (phase != OperationJournalPhase.committed &&
        phase != OperationJournalPhase.finalizing) {
      throw const OperationControlPlaneStateException(
        'illegalFinalizationEffectPhase',
      );
    }
    switch (effect) {
      case DeleteReanchoredDraftEffect(
        :final managedSkillId,
        :final expectedBaseObjectId,
      ):
        await (_database.delete(_database.draftWorkspaces)..where(
              (row) =>
                  row.managedSkillId.equals(managedSkillId.value) &
                  row.baseObjectId.equals(expectedBaseObjectId.value),
            ))
            .go();
    }
  });

  @override
  Future<void> complete(OperationPlan plan) => _database.transaction(() async {
    final journal = await _requireJournal(plan.operationId);
    _requireJournalMatchesPlan(journal, plan);
    final phase = _parsePhase(journal.phase);
    if (phase == OperationJournalPhase.completed) return;
    if (phase != OperationJournalPhase.finalizing) {
      throw const OperationControlPlaneStateException('illegalCompletionPhase');
    }
    if (journal.committedRepositoryRevision !=
        plan.committedRepositoryRevision.value) {
      throw const OperationControlPlaneStateException(
        'committedRevisionMismatch',
      );
    }
    await _writeRecord(plan, journal: journal, status: 'succeeded');
    await _markJournalCompleted(
      journal,
      terminalRevision: plan.committedRepositoryRevision.value,
    );
  });

  @override
  Future<void> completeRollback(
    OperationPlan plan,
    OperationAbortReason reason,
  ) => _database.transaction(() async {
    final journal = await _requireJournal(plan.operationId);
    _requireJournalMatchesPlan(journal, plan);
    final phase = _parsePhase(journal.phase);
    if (phase == OperationJournalPhase.completed) return;
    if (phase != OperationJournalPhase.prepared &&
        phase != OperationJournalPhase.applying) {
      throw const OperationControlPlaneStateException(
        'illegalRollbackCompletionPhase',
      );
    }
    await _writeRecord(
      plan,
      journal: journal,
      status: reason == OperationAbortReason.cancelled ? 'cancelled' : 'failed',
    );
    // Schema v1 requires every Completed Journal to carry a terminal revision.
    // For a pre-commit rollback this is the unchanged expected revision. The
    // phase, not this value, remains the recovery-direction authority.
    await _markJournalCompleted(
      journal,
      terminalRevision: plan.expectedRepositoryRevision.value,
    );
  });

  @override
  Future<void> completePreparedEnvelopeRollback(
    PreparedOperationEnvelope envelope,
    OperationAbortReason reason,
  ) => _database.transaction(() async {
    final journal = await _requireJournal(envelope.operationId);
    _requireJournalMatchesDefinition(journal, envelope);
    final phase = _parsePhase(journal.phase);
    if (phase == OperationJournalPhase.completed) return;
    if (phase != OperationJournalPhase.prepared) {
      throw const OperationControlPlaneStateException(
        'illegalEnvelopeRollbackCompletionPhase',
      );
    }
    await _writeRecord(
      envelope,
      journal: journal,
      status: reason == OperationAbortReason.cancelled ? 'cancelled' : 'failed',
    );
    await _markJournalCompleted(
      journal,
      terminalRevision: envelope.expectedRepositoryRevision.value,
    );
  });

  @override
  Future<List<JournaledOperation>> loadRecoverableOperations() =>
      _database.transaction(() async {
        final journalRows =
            await (_database.select(_database.operationJournals)..orderBy([
                  (row) => OrderingTerm.asc(row.operationGeneration),
                  (row) => OrderingTerm.asc(row.startedAtMicros),
                  (row) => OrderingTerm.asc(row.operationId),
                ]))
                .get();
        final stepRows =
            await (_database.select(_database.operationJournalSteps)..orderBy([
                  (row) => OrderingTerm.asc(row.operationId),
                  (row) => OrderingTerm.asc(row.sequence),
                ]))
                .get();
        final stepsByOperation = <String, List<OperationJournalStep>>{};
        for (final row in stepRows) {
          stepsByOperation.putIfAbsent(row.operationId, () => []).add(row);
        }

        final result = <JournaledOperation>[];
        for (final journal in journalRows) {
          final definition = _decodeJournalDefinition(journal);
          final phase = _parsePhase(journal.phase);
          _requireDefinitionAllowedInPhase(definition, phase);
          _requireTerminalRevisionConsistent(journal, definition, phase);
          final expectedSteps = _definitionSteps(definition);
          final actualSteps =
              stepsByOperation[journal.operationId] ??
              const <OperationJournalStep>[];
          if (actualSteps.length != expectedSteps.length) {
            throw const OperationControlPlaneStateException(
              'journalStepSetMismatch',
            );
          }
          final statuses = <String, OperationStepStatus>{};
          for (var index = 0; index < expectedSteps.length; index += 1) {
            final expected = expectedSteps[index];
            final actual = actualSteps[index];
            if (actual.sequence != index ||
                actual.stepId != expected.stepId ||
                actual.kind != _stepKind(expected) ||
                actual.recoveryReference !=
                    expected.recoveryReference.encoded) {
              throw const OperationControlPlaneStateException(
                'journalStepSetMismatch',
              );
            }
            statuses[actual.stepId] = _parseStepStatus(actual.status);
          }
          result.add(
            JournaledOperation.fromDefinition(
              definition: definition,
              phase: phase,
              stepStatuses: statuses,
            ),
          );
        }
        return List<JournaledOperation>.unmodifiable(result);
      });

  @override
  Future<void> deleteCompletedJournal(OperationId operationId) =>
      _database.transaction(() async {
        final journal =
            await (_database.select(_database.operationJournals)
                  ..where((row) => row.operationId.equals(operationId.value)))
                .getSingleOrNull();
        if (journal == null) return;
        if (_parsePhase(journal.phase) != OperationJournalPhase.completed) {
          throw const OperationControlPlaneStateException(
            'journalNotCompleted',
          );
        }
        await (_database.delete(
          _database.operationJournals,
        )..where((row) => row.operationId.equals(operationId.value))).go();
      });

  Future<void> _transitionPhase(
    OperationId operationId, {
    required OperationJournalPhase from,
    required OperationJournalPhase to,
  }) => _database.transaction(() async {
    final journal = await _requireJournal(operationId);
    final current = _parsePhase(journal.phase);
    if (current == to) return;
    if (current != from) {
      throw const OperationControlPlaneStateException(
        'illegalJournalPhaseTransition',
      );
    }
    if (to == OperationJournalPhase.applying &&
        _decodeJournalDefinition(journal) is! OperationPlan) {
      throw const OperationControlPlaneStateException(
        'unsealedJournalCannotApply',
      );
    }
    await (_database.update(
      _database.operationJournals,
    )..where((row) => row.operationId.equals(operationId.value))).write(
      OperationJournalsCompanion(
        phase: Value(to.name),
        updatedAtMicros: Value(_clock()),
      ),
    );
  });

  Future<void> _transitionStep(
    OperationId operationId,
    String stepId, {
    required OperationStepStatus target,
  }) => _database.transaction(() async {
    final journal = await _requireJournal(operationId);
    if (_parsePhase(journal.phase) == OperationJournalPhase.completed) {
      throw const OperationControlPlaneStateException(
        'completedJournalStepMutation',
      );
    }
    final row =
        await (_database.select(_database.operationJournalSteps)..where(
              (row) =>
                  row.operationId.equals(operationId.value) &
                  row.stepId.equals(stepId),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw const OperationControlPlaneStateException('missingJournalStep');
    }
    final current = _parseStepStatus(row.status);
    if (current == target ||
        (current == OperationStepStatus.completed &&
            target == OperationStepStatus.started)) {
      return;
    }
    final legal =
        (current == OperationStepStatus.planned &&
            target == OperationStepStatus.started) ||
        (current == OperationStepStatus.started &&
            target == OperationStepStatus.completed);
    if (!legal) {
      throw const OperationControlPlaneStateException(
        'illegalJournalStepTransition',
      );
    }
    await (_database.update(_database.operationJournalSteps)..where(
          (candidate) =>
              candidate.operationId.equals(operationId.value) &
              candidate.stepId.equals(stepId),
        ))
        .write(OperationJournalStepsCompanion(status: Value(target.name)));
  });

  Future<void> _requireRepositoryRevision(RepositoryRevision expected) async {
    final metadata = await _database
        .select(_database.workspaceMetadata)
        .getSingle();
    if (metadata.repositoryRevision != expected.value) {
      throw StaleControlPlaneRevision(
        expected: expected.value,
        actual: metadata.repositoryRevision,
      );
    }
  }

  Future<OperationJournal> _requireJournal(OperationId operationId) async {
    final journal =
        await (_database.select(_database.operationJournals)
              ..where((row) => row.operationId.equals(operationId.value)))
            .getSingleOrNull();
    if (journal == null) {
      throw const OperationControlPlaneStateException('missingJournal');
    }
    return journal;
  }

  void _requireJournalMatchesPlan(
    OperationJournal journal,
    OperationPlan plan,
  ) => _requireJournalMatchesDefinition(journal, plan);

  void _requireJournalMatchesDefinition(
    OperationJournal journal,
    OperationJournalDefinition definition,
  ) {
    if (journal.operationId != definition.operationId.value ||
        journal.kind != definition.record.kind ||
        journal.planSchemaVersion != OperationPlanCodec.currentSchemaVersion ||
        journal.planJson != _codec.encodeDefinition(definition) ||
        journal.operationGeneration != definition.operationGeneration) {
      throw const OperationControlPlaneStateException('journalPlanMismatch');
    }
  }

  OperationJournalDefinition _decodeJournalDefinition(
    OperationJournal journal,
  ) {
    final OperationJournalDefinition definition;
    try {
      definition = _codec.decodeDefinition(
        schemaVersion: journal.planSchemaVersion,
        payload: journal.planJson,
      );
    } on Object {
      throw const OperationControlPlaneStateException('invalidJournalPlan');
    }
    if (definition.operationId.value != journal.operationId ||
        definition.record.kind != journal.kind ||
        definition.operationGeneration != journal.operationGeneration) {
      throw const OperationControlPlaneStateException('journalPlanMismatch');
    }
    return definition;
  }

  void _requirePhase(OperationJournal journal, OperationJournalPhase phase) {
    if (_parsePhase(journal.phase) != phase) {
      throw const OperationControlPlaneStateException('unexpectedJournalPhase');
    }
  }

  Future<void> _requirePreviousSelection(
    RevisionSelectionChangePlan change,
  ) async {
    final current =
        await (_database.select(_database.currentRevisionSelection)..where(
              (row) => row.managedSkillId.equals(change.managedSkillId.value),
            ))
            .getSingleOrNull();
    if (change.previousUpstream == null) {
      if (current != null) {
        throw const OperationControlPlaneStateException(
          'revisionSelectionMismatch',
        );
      }
      return;
    }
    if (current == null ||
        current.sourceLineageId !=
            change.previousUpstream!.sourceLineage.encoded ||
        current.upstreamObjectId != change.previousUpstream!.objectId.value ||
        current.effectiveObjectId != change.previousEffective!.objectId.value) {
      throw const OperationControlPlaneStateException(
        'revisionSelectionMismatch',
      );
    }
  }

  Future<void> _applyIntendedSelection(
    RevisionSelectionChangePlan change,
  ) async {
    if (change.intendedUpstream == null) {
      await (_database.delete(_database.currentRevisionSelection)..where(
            (row) => row.managedSkillId.equals(change.managedSkillId.value),
          ))
          .go();
      return;
    }
    await _database
        .into(_database.currentRevisionSelection)
        .insertOnConflictUpdate(
          CurrentRevisionSelectionCompanion.insert(
            managedSkillId: change.managedSkillId.value,
            sourceLineageId: change.intendedUpstream!.sourceLineage.encoded,
            upstreamObjectId: change.intendedUpstream!.objectId.value,
            effectiveObjectId: change.intendedEffective!.objectId.value,
          ),
        );
  }

  Future<void> _applyBusinessMutation(WorkspaceBusinessMutation mutation) =>
      switch (mutation) {
        PutManagedSkill() =>
          _database
              .into(_database.managedSkills)
              .insertOnConflictUpdate(
                ManagedSkillsCompanion.insert(
                  id: mutation.managedSkillId.value,
                  slotKey: mutation.slotKey,
                  declaredName: mutation.declaredName,
                  displayName: mutation.displayName,
                  description: mutation.description,
                  activeSourceLineageId: mutation.activeSourceLineageId,
                  createdAtMicros: mutation.createdAtMicros,
                  updatedAtMicros: mutation.updatedAtMicros,
                ),
              ),
        DeleteManagedSkill() => (_database.delete(
          _database.managedSkills,
        )..where((row) => row.id.equals(mutation.managedSkillId.value))).go(),
        PutSourceLineage() =>
          _database
              .into(_database.sourceLineages)
              .insertOnConflictUpdate(
                SourceLineagesCompanion.insert(
                  id: mutation.sourceLineageId,
                  managedSkillId: mutation.managedSkillId.value,
                  objectFormat: mutation.objectFormat.name,
                  createdAtMicros: mutation.createdAtMicros,
                ),
              ),
        DeleteSourceLineage() => (_database.delete(
          _database.sourceLineages,
        )..where((row) => row.id.equals(mutation.sourceLineageId))).go(),
        PutSkillSource() =>
          _database
              .into(_database.skillSources)
              .insertOnConflictUpdate(
                SkillSourcesCompanion.insert(
                  sourceLineageId: mutation.sourceLineageId,
                  kind: mutation.kind.name,
                  payloadSchemaVersion: mutation.payloadSchemaVersion,
                  payloadJson: mutation.payloadJson,
                ),
              ),
        PutRevisionMetadata() =>
          _database
              .into(_database.revisionMetadata)
              .insertOnConflictUpdate(
                RevisionMetadataCompanion.insert(
                  sourceLineageId: mutation.sourceLineageId,
                  objectId: mutation.objectId,
                  contentHash: mutation.contentHash,
                  fileCount: mutation.fileCount,
                  byteSize: mutation.byteSize,
                  declaredName: mutation.declaredName,
                  validationState: mutation.validationState.name,
                  validationCode: Value(mutation.validationCode),
                  createdAtMicros: mutation.createdAtMicros,
                ),
              ),
        PutProjectRoot() =>
          _database
              .into(_database.projectRoots)
              .insertOnConflictUpdate(
                ProjectRootsCompanion.insert(
                  id: mutation.projectRootId,
                  canonicalPath: mutation.canonicalPath,
                  createdAtMicros: mutation.createdAtMicros,
                  updatedAtMicros: mutation.updatedAtMicros,
                ),
              ),
        DeleteProjectRoot() => (_database.delete(
          _database.projectRoots,
        )..where((row) => row.id.equals(mutation.projectRootId))).go(),
        PutActivation() => _putActivation(mutation),
        DeleteActivation() => (_database.delete(
          _database.activationLocations,
        )..where((row) => row.id.equals(mutation.activationId))).go(),
        PutSkillUserData() =>
          _database
              .into(_database.skillUserData)
              .insertOnConflictUpdate(
                SkillUserDataCompanion.insert(
                  managedSkillId: mutation.managedSkillId.value,
                  favorite: Value(mutation.favorite),
                  favoriteChangedAtMicros: Value(
                    mutation.favoriteChangedAtMicros,
                  ),
                  note: Value(mutation.note),
                  noteUpdatedAtMicros: Value(mutation.noteUpdatedAtMicros),
                ),
              ),
        DeleteSkillUserData() =>
          (_database.delete(_database.skillUserData)..where(
                (row) =>
                    row.managedSkillId.equals(mutation.managedSkillId.value),
              ))
              .go(),
        PutPersonalTag() =>
          _database
              .into(_database.personalTags)
              .insertOnConflictUpdate(
                PersonalTagsCompanion.insert(
                  id: mutation.personalTagId,
                  normalizedKey: mutation.normalizedKey,
                  displayName: mutation.displayName,
                  color: Value(mutation.color),
                  createdAtMicros: mutation.createdAtMicros,
                  updatedAtMicros: mutation.updatedAtMicros,
                ),
              ),
        DeletePersonalTag() => (_database.delete(
          _database.personalTags,
        )..where((row) => row.id.equals(mutation.personalTagId))).go(),
        PutSkillTagAssignment() =>
          _database
              .into(_database.skillTagAssignments)
              .insertOnConflictUpdate(
                SkillTagAssignmentsCompanion.insert(
                  managedSkillId: mutation.managedSkillId.value,
                  personalTagId: mutation.personalTagId,
                  createdAtMicros: mutation.createdAtMicros,
                ),
              ),
        DeleteSkillTagAssignment() =>
          (_database.delete(_database.skillTagAssignments)..where(
                (row) =>
                    row.managedSkillId.equals(mutation.managedSkillId.value) &
                    row.personalTagId.equals(mutation.personalTagId),
              ))
              .go(),
        PutDraftWorkspace() =>
          _database
              .into(_database.draftWorkspaces)
              .insertOnConflictUpdate(
                DraftWorkspacesCompanion.insert(
                  managedSkillId: mutation.managedSkillId.value,
                  sourceLineageId: mutation.sourceLineageId,
                  baseObjectId: mutation.baseObjectId,
                  purpose: mutation.purpose.name,
                  createdAtMicros: mutation.createdAtMicros,
                  updatedAtMicros: mutation.updatedAtMicros,
                ),
              ),
        DeleteDraftWorkspace() =>
          (_database.delete(_database.draftWorkspaces)..where(
                (row) =>
                    row.managedSkillId.equals(mutation.managedSkillId.value),
              ))
              .go(),
        PutUpdateCandidateSession() => _putUpdateCandidateSession(mutation),
        DeleteUpdateCandidateSession() =>
          (_database.delete(_database.updateCandidateSessions)..where(
                (row) =>
                    row.managedSkillId.equals(mutation.managedSkillId.value),
              ))
              .go(),
        SetUpdateCandidateItemResolution() => _setUpdateCandidateItemResolution(
          mutation,
        ),
      };

  Future<void> _setUpdateCandidateItemResolution(
    SetUpdateCandidateItemResolution mutation,
  ) async {
    final changed =
        await (_database.update(_database.updateCandidateItems)..where(
              (row) =>
                  row.managedSkillId.equals(mutation.managedSkillId.value) &
                  row.path.equals(mutation.path),
            ))
            .write(
              UpdateCandidateItemsCompanion(state: Value(mutation.state.name)),
            );
    if (changed != 1) {
      throw StateError('The Update Candidate conflict no longer exists.');
    }
    final sessionChanged =
        await (_database.update(_database.updateCandidateSessions)..where(
              (row) => row.managedSkillId.equals(mutation.managedSkillId.value),
            ))
            .write(
              UpdateCandidateSessionsCompanion(
                updatedAtMicros: Value(mutation.updatedAtMicros),
              ),
            );
    if (sessionChanged != 1) {
      throw StateError('The Update Candidate Session no longer exists.');
    }
  }

  Future<void> _putActivation(PutActivation mutation) async {
    await _database
        .into(_database.activationLocations)
        .insertOnConflictUpdate(
          ActivationLocationsCompanion.insert(
            id: mutation.activationId,
            managedSkillId: mutation.managedSkillId.value,
            canonicalPath: mutation.canonicalPath,
            scope: mutation.scope.name,
            mode: mutation.mode.name,
            projectRootId: Value(mutation.projectRootId),
            projectRootPath: Value(mutation.projectRootPath),
            createdAtMicros: mutation.createdAtMicros,
          ),
        );
    await (_database.delete(_database.activationAgents)..where(
          (row) => row.activationLocationId.equals(mutation.activationId),
        ))
        .go();
    for (final agentId in mutation.agentIds) {
      await _database
          .into(_database.activationAgents)
          .insert(
            ActivationAgentsCompanion.insert(
              activationLocationId: mutation.activationId,
              agentId: agentId,
            ),
          );
    }
  }

  Future<void> _putUpdateCandidateSession(
    PutUpdateCandidateSession mutation,
  ) async {
    await _database
        .into(_database.updateCandidateSessions)
        .insertOnConflictUpdate(
          UpdateCandidateSessionsCompanion.insert(
            managedSkillId: mutation.managedSkillId.value,
            sourceLineageId: mutation.sourceLineageId,
            previousUpstreamObjectId: mutation.previousUpstreamObjectId,
            previousEffectiveObjectId: mutation.previousEffectiveObjectId,
            incomingUpstreamObjectId: mutation.incomingUpstreamObjectId,
            candidateObjectId: mutation.candidateObjectId,
            status: mutation.status.name,
            validationCode: Value(mutation.validationCode),
            createdAtMicros: mutation.createdAtMicros,
            updatedAtMicros: mutation.updatedAtMicros,
          ),
        );
    await (_database.delete(_database.updateCandidateItems)..where(
          (row) => row.managedSkillId.equals(mutation.managedSkillId.value),
        ))
        .go();
    for (final item in mutation.items) {
      await _database
          .into(_database.updateCandidateItems)
          .insert(
            UpdateCandidateItemsCompanion.insert(
              managedSkillId: mutation.managedSkillId.value,
              path: item.path,
              kind: item.kind.name,
              state: item.state.name,
              baseObjectId: Value(item.baseObjectId),
              oursObjectId: Value(item.oursObjectId),
              theirsObjectId: Value(item.theirsObjectId),
            ),
          );
    }
  }

  Future<void> _writeRecord(
    OperationJournalDefinition definition, {
    required OperationJournal journal,
    required String status,
  }) async {
    final survivingSubjects = <OperationSubjectPlan>[];
    for (final subject in definition.record.subjects) {
      final skill =
          await (_database.select(_database.managedSkills)
                ..where((row) => row.id.equals(subject.managedSkillId.value)))
              .getSingleOrNull();
      if (skill == null) continue;
      if (subject.sourceLineage case final lineage?) {
        final lineageRow =
            await (_database.select(_database.sourceLineages)..where(
                  (row) =>
                      row.id.equals(lineage.encoded) &
                      row.managedSkillId.equals(subject.managedSkillId.value),
                ))
                .getSingleOrNull();
        if (lineageRow == null) continue;
      }
      survivingSubjects.add(subject);
    }

    await (_database.delete(
          _database.operationSubjects,
        )..where((row) => row.operationId.equals(definition.operationId.value)))
        .go();
    if (survivingSubjects.isEmpty && !definition.record.retainWithoutSubjects) {
      await (_database.delete(_database.operationRecords)..where(
            (row) => row.operationId.equals(definition.operationId.value),
          ))
          .go();
      return;
    }

    await _database
        .into(_database.operationRecords)
        .insertOnConflictUpdate(
          OperationRecordsCompanion.insert(
            operationId: definition.operationId.value,
            kind: definition.record.kind,
            status: status,
            retainWithoutSubjects: Value(
              definition.record.retainWithoutSubjects,
            ),
            startedAtMicros: journal.startedAtMicros,
            completedAtMicros: _clock(),
          ),
        );
    for (final subject in survivingSubjects) {
      await _database
          .into(_database.operationSubjects)
          .insert(
            OperationSubjectsCompanion.insert(
              subjectId: subject.reference.subjectId,
              operationId: definition.operationId.value,
              managedSkillId: subject.managedSkillId.value,
              sourceLineageId: Value(subject.sourceLineage?.encoded),
              beforeObjectId: Value(subject.beforeObjectId?.value),
              afterObjectId: Value(subject.afterObjectId?.value),
              beforeContentHash: Value(subject.beforeContentHash),
              afterContentHash: Value(subject.afterContentHash),
              displayName: subject.displayName,
            ),
          );
    }
  }

  Future<void> _markJournalCompleted(
    OperationJournal journal, {
    required int terminalRevision,
  }) =>
      (_database.update(
        _database.operationJournals,
      )..where((row) => row.operationId.equals(journal.operationId))).write(
        OperationJournalsCompanion(
          phase: Value(OperationJournalPhase.completed.name),
          committedRepositoryRevision: Value(terminalRevision),
          updatedAtMicros: Value(_clock()),
        ),
      );

  void _requireTerminalRevisionConsistent(
    OperationJournal journal,
    OperationJournalDefinition definition,
    OperationJournalPhase phase,
  ) {
    final terminal = journal.committedRepositoryRevision;
    switch (phase) {
      case OperationJournalPhase.prepared:
      case OperationJournalPhase.applying:
        if (terminal != null) {
          throw const OperationControlPlaneStateException(
            'unexpectedTerminalRevision',
          );
        }
      case OperationJournalPhase.committed:
      case OperationJournalPhase.finalizing:
        if (terminal != definition.committedRepositoryRevision.value) {
          throw const OperationControlPlaneStateException(
            'committedRevisionMismatch',
          );
        }
      case OperationJournalPhase.completed:
        if (terminal != definition.expectedRepositoryRevision.value &&
            terminal != definition.committedRepositoryRevision.value) {
          throw const OperationControlPlaneStateException(
            'terminalRevisionMismatch',
          );
        }
    }
  }

  void _requireDefinitionAllowedInPhase(
    OperationJournalDefinition definition,
    OperationJournalPhase phase,
  ) {
    if (definition is PreparedOperationEnvelope &&
        phase != OperationJournalPhase.prepared &&
        phase != OperationJournalPhase.completed) {
      throw const OperationControlPlaneStateException('unsealedJournalPhase');
    }
  }
}

List<OperationStep> _allSteps(OperationPlan plan) => <OperationStep>[
  ...plan.preparationSteps,
  ...plan.applyingSteps,
  ...plan.finalizationSteps,
];

List<OperationStep> _definitionSteps(OperationJournalDefinition definition) =>
    switch (definition) {
      PreparedOperationEnvelope() => <OperationStep>[
        ...definition.preparationSteps,
      ],
      OperationPlan() => _allSteps(definition),
    };

bool _sameEnvelope(
  PreparedOperationEnvelope left,
  PreparedOperationEnvelope right,
) =>
    left.operationId == right.operationId &&
    left.expectedRepositoryRevision == right.expectedRepositoryRevision &&
    left.committedRepositoryRevision == right.committedRepositoryRevision &&
    left.operationGeneration == right.operationGeneration &&
    left.record.kind == right.record.kind &&
    left.preparationSteps.length == right.preparationSteps.length &&
    Iterable<int>.generate(left.preparationSteps.length).every((index) {
      final leftStep = left.preparationSteps[index];
      final rightStep = right.preparationSteps[index];
      return leftStep.stepId == rightStep.stepId &&
          leftStep.kind == rightStep.kind &&
          leftStep.recoveryReference == rightStep.recoveryReference;
    });

String _stepKind(OperationStep step) => switch (step) {
  PreparationOperationStep() => step.kind.name,
  ApplyingOperationStep() => step.kind.name,
  FinalizationOperationStep() => step.kind.name,
};

OperationJournalPhase _parsePhase(String value) {
  for (final phase in OperationJournalPhase.values) {
    if (phase.name == value) return phase;
  }
  throw const OperationControlPlaneStateException('invalidJournalPhase');
}

OperationStepStatus _parseStepStatus(String value) {
  for (final status in OperationStepStatus.values) {
    if (status.name == value) return status;
  }
  throw const OperationControlPlaneStateException('invalidJournalStepStatus');
}

int _utcMicros() => DateTime.now().toUtc().microsecondsSinceEpoch;
