import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../ports/operation_ports.dart';
import '../runtime/revision_engine_port.dart';
import 'destructive_recovery_intent.dart';
import 'operation_models.dart';
import 'workspace_business_changes.dart';

/// Persistence-neutral history data for one Skill affected by an operation.
final class OperationSubjectIntent {
  const OperationSubjectIntent({
    required this.managedSkillId,
    required this.displayName,
    this.sourceLineage,
    this.beforeObjectId,
    this.afterObjectId,
    this.beforeContentHash,
    this.afterContentHash,
  });

  final ManagedSkillId managedSkillId;
  final String displayName;
  final SourceLineageReference? sourceLineage;
  final RevisionObjectId? beforeObjectId;
  final RevisionObjectId? afterObjectId;
  final String? beforeContentHash;
  final String? afterContentHash;
}

/// Assembles the one immutable plan persisted before external mutation.
///
/// Planners own business meaning. Recovery factories own opaque references
/// and physical paths. This assembler is the only place that binds both to the
/// stable public Operation ID and the expected Repository Revision.
final class OperationPlanAssembler {
  const OperationPlanAssembler({
    required OperationSubjectIdentityPort subjectIdentities,
    required OperationRecoveryPlanFactoryPort recoveryPlans,
  }) : _subjectIdentities = subjectIdentities,
       _recoveryPlans = recoveryPlans;

  final OperationSubjectIdentityPort _subjectIdentities;
  final OperationRecoveryPlanFactoryPort _recoveryPlans;

  /// Allocates the minimal destructive Journal that owns operation staging
  /// before a Source Replacement candidate is constructed.
  PreparedOperationEnvelope destructiveEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required WorkspaceOperationKind kind,
  }) {
    if (kind != WorkspaceOperationKind.replaceSource) {
      throw ArgumentError.value(
        kind,
        'kind',
        'only deferred Source Replacement uses a destructive envelope',
      );
    }
    final committed = expectedRepositoryRevision.next();
    return PreparedOperationEnvelope(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: committed,
      operationGeneration: committed.value,
      preparationSteps: _recoveryPlans.createDestructiveEnvelope(
        operationId: operationId,
        expectedRepositoryRevision: expectedRepositoryRevision,
        committedRepositoryRevision: committed,
      ),
      // Candidate display/source facts are intentionally unknown at this
      // point. An empty projection seals to the complete subject record.
      record: OperationRecordPlan(
        operationId: operationId,
        kind: kind.name,
        subjects: const [],
        retainWithoutSubjects: true,
      ),
    );
  }

  OperationPlan sqliteOnly({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required WorkspaceOperationKind kind,
    required WorkspaceBusinessChangeSet businessChanges,
    List<OperationSubjectIntent> subjects = const [],
    bool retainWithoutSubjects = false,
  }) {
    if (businessChanges.isEmpty) {
      throw ArgumentError.value(
        businessChanges,
        'businessChanges',
        'must contain a committed mutation',
      );
    }
    if (businessChanges.incrementsDestructionEpoch) {
      throw ArgumentError.value(
        businessChanges,
        'businessChanges',
        'destructive changes require a typed recovery intent',
      );
    }
    final committed = expectedRepositoryRevision.next();
    final steps = _recoveryPlans.createSqliteOnly(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: committed,
      destructive: businessChanges.incrementsDestructionEpoch,
    );
    return assemble(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      kind: kind,
      businessChanges: businessChanges,
      recoverySteps: steps,
      subjects: subjects,
      retainWithoutSubjects: retainWithoutSubjects,
    );
  }

  OperationPlan destructive({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required WorkspaceOperationKind kind,
    required WorkspaceBusinessChangeSet businessChanges,
    required DestructiveOperationRecoveryIntent recoveryIntent,
    required List<RevisionSelectionChangePlan> revisionSelectionChanges,
    required List<OperationSubjectIntent> subjects,
  }) {
    if (businessChanges.isEmpty ||
        !businessChanges.incrementsDestructionEpoch) {
      throw ArgumentError.value(
        businessChanges,
        'businessChanges',
        'must increment the Destruction Epoch',
      );
    }
    _validateDestructiveAlignment(
      kind: kind,
      businessChanges: businessChanges,
      recoveryIntent: recoveryIntent,
      revisionSelectionChanges: revisionSelectionChanges,
      subjects: subjects,
    );
    final committed = expectedRepositoryRevision.next();
    final steps = _recoveryPlans.createDestructive(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: committed,
      intent: recoveryIntent,
    );
    return assemble(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      kind: kind,
      businessChanges: businessChanges,
      recoverySteps: steps,
      revisionSelectionChanges: revisionSelectionChanges,
      subjects: subjects,
    );
  }

  OperationPlan assemble({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required WorkspaceOperationKind kind,
    required WorkspaceBusinessChangeSet businessChanges,
    required OperationRecoveryPlanSteps recoverySteps,
    List<RevisionSelectionChangePlan> revisionSelectionChanges = const [],
    List<OperationSubjectIntent> subjects = const [],
    bool retainWithoutSubjects = false,
  }) {
    if (subjects.isEmpty && !retainWithoutSubjects) {
      throw ArgumentError(
        'An operation without Skill subjects must retain independent history.',
      );
    }
    final managedSkillIds = subjects
        .map((subject) => subject.managedSkillId)
        .toSet();
    if (managedSkillIds.length != subjects.length) {
      throw ArgumentError.value(
        subjects,
        'subjects',
        'contains duplicate managed Skills',
      );
    }
    final recordSubjects = <OperationSubjectPlan>[
      for (final subject in subjects)
        OperationSubjectPlan(
          reference: OperationSubjectReference(
            operationId: operationId,
            subjectId: _subjectIdentities.allocateOperationSubjectId(),
          ),
          managedSkillId: subject.managedSkillId,
          displayName: subject.displayName,
          sourceLineage: subject.sourceLineage,
          beforeObjectId: subject.beforeObjectId,
          afterObjectId: subject.afterObjectId,
          beforeContentHash: subject.beforeContentHash,
          afterContentHash: subject.afterContentHash,
        ),
    ];
    final committed = expectedRepositoryRevision.next();
    return OperationPlan(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: committed,
      // Writer serialization and the monotonic Repository Revision make this
      // a stable, positive ordering key without a second counter.
      operationGeneration: committed.value,
      preparationSteps: recoverySteps.preparationSteps,
      applyingSteps: recoverySteps.applyingSteps,
      finalizationSteps: recoverySteps.finalizationSteps,
      revisionSelectionChanges: revisionSelectionChanges,
      businessChanges: businessChanges,
      record: OperationRecordPlan(
        operationId: operationId,
        kind: kind.name,
        subjects: recordSubjects,
        retainWithoutSubjects: retainWithoutSubjects,
      ),
    );
  }
}

void _validateDestructiveAlignment({
  required WorkspaceOperationKind kind,
  required WorkspaceBusinessChangeSet businessChanges,
  required DestructiveOperationRecoveryIntent recoveryIntent,
  required List<RevisionSelectionChangePlan> revisionSelectionChanges,
  required List<OperationSubjectIntent> subjects,
}) {
  final recoveryIds = recoveryIntent.skills
      .map((skill) => skill.managedSkillId)
      .toSet();
  final revisionIds = revisionSelectionChanges
      .map((change) => change.managedSkillId)
      .toSet();
  final subjectIds = subjects.map((subject) => subject.managedSkillId).toSet();
  if (recoveryIds.length != revisionSelectionChanges.length ||
      recoveryIds.length != subjects.length ||
      !_sameManagedSkillIds(recoveryIds, revisionIds) ||
      !_sameManagedSkillIds(recoveryIds, subjectIds)) {
    throw ArgumentError(
      'Destructive recovery, revision selection, and history subjects must '
      'identify the same managed Skills.',
    );
  }

  switch (recoveryIntent) {
    case final RemovalRecoveryIntent removal:
      if (kind != WorkspaceOperationKind.remove ||
          revisionSelectionChanges.any(
            (change) =>
                change.intendedUpstream != null ||
                change.intendedEffective != null,
          )) {
        throw ArgumentError(
          'Removal must select absence for every recovered managed Skill.',
        );
      }
      final deletedIds = businessChanges.mutations
          .whereType<DeleteManagedSkill>()
          .map((mutation) => mutation.managedSkillId)
          .toSet();
      if (!_sameManagedSkillIds(recoveryIds, deletedIds) ||
          deletedIds.length != removal.skills.length ||
          businessChanges.mutations.any(
            (mutation) => mutation is DeletePersonalTag,
          )) {
        throw ArgumentError(
          'Removal must delete exactly its managed Skill aggregates and must '
          'not delete reusable Personal Tags.',
        );
      }
    case final SourceReplacementRecoveryIntent replacement:
      if (kind != WorkspaceOperationKind.replaceSource ||
          recoveryIds.length != 1) {
        throw ArgumentError(
          'Source Replacement must target exactly one managed Skill.',
        );
      }
      final change = revisionSelectionChanges.single;
      final intendedUpstream = change.intendedUpstream;
      final intendedEffective = change.intendedEffective;
      final subject = subjects.single;
      final managedSkills = businessChanges.mutations
          .whereType<PutManagedSkill>()
          .toList(growable: false);
      final lineages = businessChanges.mutations
          .whereType<PutSourceLineage>()
          .toList(growable: false);
      final revisions = businessChanges.mutations
          .whereType<PutRevisionMetadata>()
          .toList(growable: false);
      final deletedLineages = businessChanges.mutations
          .whereType<DeleteSourceLineage>()
          .map((mutation) => mutation.sourceLineageId)
          .toSet();
      final formerLineages = replacement.skill.sourceLineages
          .map((lineage) => lineage.sourceLineage.encoded)
          .toSet();
      if (intendedUpstream == null ||
          intendedEffective == null ||
          intendedUpstream != intendedEffective ||
          intendedUpstream.sourceLineage != replacement.intendedSourceLineage ||
          intendedEffective.objectId != replacement.intendedObjectId ||
          subject.sourceLineage != replacement.intendedSourceLineage ||
          subject.beforeObjectId != null ||
          subject.beforeContentHash != null ||
          subject.afterObjectId != intendedEffective.objectId ||
          subject.afterContentHash != replacement.intendedContentHash ||
          managedSkills.length != 1 ||
          managedSkills.single.managedSkillId !=
              replacement.skill.managedSkillId ||
          managedSkills.single.activeSourceLineageId !=
              replacement.intendedSourceLineage.encoded ||
          managedSkills.single.slotKey != replacement.intendedSlotKey ||
          lineages.length != 1 ||
          lineages.single.managedSkillId != replacement.skill.managedSkillId ||
          lineages.single.sourceLineageId !=
              replacement.intendedSourceLineage.encoded ||
          lineages.single.objectFormat != replacement.intendedObjectFormat ||
          revisions.length != 1 ||
          revisions.single.sourceLineageId !=
              replacement.intendedSourceLineage.encoded ||
          revisions.single.objectId != intendedEffective.objectId.value ||
          revisions.single.contentHash != replacement.intendedContentHash ||
          !_sameStrings(formerLineages, deletedLineages) ||
          businessChanges.mutations.any(
            (mutation) => mutation is DeleteManagedSkill,
          )) {
        throw ArgumentError(
          'Source Replacement business state and recovery lineage disagree.',
        );
      }
  }
}

bool _sameManagedSkillIds(
  Set<ManagedSkillId> left,
  Set<ManagedSkillId> right,
) => left.length == right.length && left.containsAll(right);

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
