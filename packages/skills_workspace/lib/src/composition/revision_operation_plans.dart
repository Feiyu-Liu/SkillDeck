import 'package:path/path.dart' as path;

import '../application/activation/activation_mutation_models.dart';
import '../application/drift/drift_models.dart';
import '../application/ports/published_artifact_ports.dart';
import '../application/ports/workspace_lifecycle_ports.dart';
import '../domain/cancellation.dart';
import '../application/drafts/draft_models.dart';
import '../application/drafts/draft_ports.dart';
import '../application/history/history_models.dart';
import '../application/history/history_ports.dart';
import '../application/install/initial_import_models.dart';
import '../application/operations/operation_models.dart';
import '../application/operations/operation_plan_assembler.dart';
import '../application/operations/workspace_business_changes.dart';
import '../application/ports/activation_mutation_ports.dart';
import '../application/ports/initial_import_ports.dart';
import '../application/ports/operation_ports.dart';
import '../application/runtime/revision_engine_port.dart';
import '../application/update/update_command_ports.dart';
import '../application/update/update_models.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../infrastructure/workspace_layout.dart';
import '../platform/operations/operation_recovery_bundle.dart';

/// Binds revision-backed mutations to one recoverable filesystem transaction.
///
/// Candidate creation remains in [WorkspaceRevisionPreparationService]. This
/// adapter only translates its immutable evidence into private recovery bundle
/// entries and the sealed application [OperationPlan].
final class WorkspaceRevisionOperationPlans
    implements
        InitialImportOperationPlanPort,
        DraftOperationPlanPort,
        UpdateOperationPlanPort,
        RestoreOperationPlanPort,
        DriftOperationPlanPort {
  const WorkspaceRevisionOperationPlans({
    required OperationPlanAssembler assembler,
    required OperationRecoverySpecRegistry recoverySpecs,
    required WorkspaceLayout layout,
    required ActivationTargetExpectationPort targetExpectations,
    required PublishedArtifactInspectorPort artifactInspector,
  }) : _assembler = assembler,
       _recoverySpecs = recoverySpecs,
       _layout = layout,
       _targetExpectations = targetExpectations,
       _artifactInspector = artifactInspector;

  final OperationPlanAssembler _assembler;
  final OperationRecoverySpecRegistry _recoverySpecs;
  final WorkspaceLayout _layout;
  final ActivationTargetExpectationPort _targetExpectations;
  final PublishedArtifactInspectorPort _artifactInspector;

  @override
  PreparedOperationEnvelope createEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required InitialImportPreflight preflight,
  }) => _envelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    kind: _initialKind(preflight.kind),
    preparations: <_PreparationIntent>[
      for (final subject in preflight.subjects) ...<_PreparationIntent>[
        _PreparationIntent(
          token: 'candidate-${subject.managedSkillId.value}',
          kind: PreparationStepKind.revisionCandidate,
        ),
        _PreparationIntent(
          token: 'bundle-${subject.managedSkillId.value}',
          kind: PreparationStepKind.revisionBundle,
        ),
        _PreparationIntent(
          token: 'materialization-${subject.managedSkillId.value}',
          kind: PreparationStepKind.materialization,
        ),
      ],
    ],
  );

  @override
  OperationPlan sealPlan({
    required PreparedOperationEnvelope envelope,
    required InitialImportPreflight preflight,
    required InitialImportPlan initialImportPlan,
  }) {
    final builder = _RecoveryPlanBuilder(
      envelope: envelope,
      registry: _recoverySpecs,
    );
    final evidenceBySkill = <ManagedSkillId, PreparedInitialRevision>{
      for (final evidence in initialImportPlan.preparedRevisions)
        evidence.managedSkillId: evidence,
    };
    for (final subject in preflight.subjects) {
      final evidence = evidenceBySkill[subject.managedSkillId];
      if (evidence == null || evidence.sourceLineage != subject.sourceLineage) {
        throw StateError(
          'Initial-import evidence no longer matches preflight.',
        );
      }
      final candidateRoot = _candidateRevisionRoot(
        envelope.operationId,
        subject.managedSkillId,
      );
      builder.addDirectory(
        targetPath: _storePath(subject.managedSkillId),
        intendedSourcePath: path.join(candidateRoot, 'store.git'),
        makeReadOnly: false,
        requirePlainDirectory: false,
      );
      builder.addDirectory(
        targetPath: _bundlePath(subject.managedSkillId),
        intendedSourcePath: path.join(candidateRoot, 'bundle'),
      );
      final materialization = _candidateMaterializationPath(
        envelope.operationId,
        subject.managedSkillId,
      );
      final repositoryCopy = _layout.repositoryCopyPath(subject.skill.slotKey);
      builder.addDirectory(
        targetPath: repositoryCopy,
        intendedSourcePath: materialization,
      );
      final preview = _previewSkill(subject, preflight.plannedAtMicros);
      for (final target in subject.targets) {
        final expectation = target.mustExist
            ? ActivationTargetExpectation.occupied(
                target.expectedExistingFingerprint ??
                    (throw StateError(
                      'A takeover target must retain its reviewed fingerprint.',
                    )),
              )
            : const ActivationTargetExpectation.vacant();
        Future<bool> verify(String resolvedTargetPath) =>
            _targetExpectations.matches(
              skill: preview,
              target: target.target,
              targetPath: resolvedTargetPath,
              expectation: expectation,
            );
        switch (target.target.mode) {
          case ActivationMode.copy:
            builder.addDirectory(
              targetPath: target.targetPath,
              intendedSourcePath: materialization,
              verifyBeforeCapture: verify,
              requiresInertBeforeImage: target.requiresInertOccupant,
            );
          case ActivationMode.symbolicLink:
            builder.addSymbolicLink(
              targetPath: target.targetPath,
              linkTarget: repositoryCopy,
              verifyBeforeCapture: verify,
              requiresInertBeforeImage: target.requiresInertOccupant,
            );
        }
      }
      for (final retirement in subject.retirements) {
        Future<bool> verify(String resolvedTargetPath) =>
            _targetExpectations.matches(
              skill: preview,
              target: retirement.target,
              targetPath: resolvedTargetPath,
              expectation: ActivationTargetExpectation.occupied(
                retirement.expectedExistingFingerprint,
              ),
            );
        builder.addAbsent(
          targetPath: retirement.targetPath,
          verifyBeforeCapture: verify,
        );
      }
    }
    final recovery = builder.finish();
    final plan = _assembler.assemble(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      kind: _initialKind(initialImportPlan.kind),
      businessChanges: initialImportPlan.businessChanges,
      recoverySteps: recovery.steps,
      revisionSelectionChanges: initialImportPlan.revisionSelectionChanges,
      subjects: <OperationSubjectIntent>[
        for (final subject in preflight.subjects)
          OperationSubjectIntent(
            managedSkillId: subject.managedSkillId,
            displayName: subject.skill.declaredName,
            sourceLineage: subject.sourceLineage,
            afterObjectId: evidenceBySkill[subject.managedSkillId]!.objectId,
            afterContentHash: subject.skill.tree.contentHash,
          ),
      ],
    );
    _requireSealed(envelope, plan);
    recovery.register();
    return plan;
  }

  @override
  PreparedOperationEnvelope createEnsureEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required EnsureDraftPreparationRequired preflight,
  }) => _envelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    kind: WorkspaceOperationKind.ensureDraft,
    preparations: <_PreparationIntent>[
      _PreparationIntent(
        token: 'draft-${preflight.skill.id.value}',
        kind: PreparationStepKind.materialization,
      ),
    ],
  );

  @override
  OperationPlan sealEnsurePlan({
    required PreparedOperationEnvelope envelope,
    required EnsureDraftPreparationRequired preflight,
    required PreparedEnsureDraftPlan preparedPlan,
  }) {
    final builder =
        _RecoveryPlanBuilder(envelope: envelope, registry: _recoverySpecs)
          ..addDirectory(
            targetPath: _layout.draftPath(preflight.skill.id),
            intendedSourcePath: _candidateDraftPath(
              envelope.operationId,
              preflight.skill.id,
            ),
            makeReadOnly: false,
          );
    final recovery = builder.finish();
    final plan = _assembler.assemble(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      kind: WorkspaceOperationKind.ensureDraft,
      businessChanges: preparedPlan.businessChanges,
      recoverySteps: recovery.steps,
      subjects: <OperationSubjectIntent>[
        _nonPublishedSubject(preflight.skill, preflight.state.sourceLineage),
      ],
    );
    _requireSealed(envelope, plan);
    recovery.register();
    return plan;
  }

  @override
  OperationPlan createDiscardPlan({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required DiscardDraftPlan plan,
  }) {
    final builder = _RecoveryPlanBuilder.oneStage(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      registry: _recoverySpecs,
    )..addAbsent(targetPath: _layout.draftPath(plan.skill.id));
    final recovery = builder.finish();
    final operation = _assembler.assemble(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      kind: WorkspaceOperationKind.discardDraft,
      businessChanges: plan.businessChanges,
      recoverySteps: recovery.steps,
      subjects: <OperationSubjectIntent>[
        _nonPublishedSubject(plan.skill, plan.state.sourceLineage),
      ],
    );
    recovery.register();
    return operation;
  }

  @override
  PreparedOperationEnvelope createPublishEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required PublishDraftPreparationRequired preflight,
  }) => _revisionEnvelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    kind: WorkspaceOperationKind.publishDraft,
    managedSkillIds: <ManagedSkillId>[preflight.skill.id],
  );

  @override
  OperationPlan sealPublishPlan({
    required PreparedOperationEnvelope envelope,
    required PublishDraftPreparationRequired preflight,
    required PreparedDraftPublishPlan preparedPlan,
  }) {
    final builder = _RecoveryPlanBuilder(
      envelope: envelope,
      registry: _recoverySpecs,
    );
    _addExistingLineageBundle(
      builder,
      envelope.operationId,
      preparedPlan.recoveryIntent.managedSkillId,
    );
    _addDraftMaterializations(
      builder,
      envelope.operationId,
      preparedPlan.materializationIntents,
    );
    builder.addDraftCleanup(
      targetPath: _layout.draftPath(preflight.skill.id),
      intent: preparedPlan.recoveryIntent.draftCleanup,
    );
    final recovery = builder.finish();
    final intended = preparedPlan.revisionSelectionChanges.single;
    final operation = _assembler.assemble(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      kind: WorkspaceOperationKind.publishDraft,
      businessChanges: preparedPlan.businessChanges,
      recoverySteps: recovery.steps,
      revisionSelectionChanges: preparedPlan.revisionSelectionChanges,
      subjects: <OperationSubjectIntent>[
        OperationSubjectIntent(
          managedSkillId: preflight.skill.id,
          displayName: preflight.skill.displayName,
          sourceLineage: preflight.state.sourceLineage,
          beforeObjectId: preflight.state.currentEffective,
          afterObjectId: intended.intendedEffective!.objectId,
          beforeContentHash: preflight.skill.currentRevision.contentHash,
          afterContentHash: _revisionHash(
            preparedPlan.businessChanges,
            intended.intendedEffective!.objectId,
          ),
        ),
      ],
    );
    _requireSealed(envelope, operation);
    recovery.register();
    return operation;
  }

  @override
  PreparedOperationEnvelope createUpdateEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required List<UpdatePreparationRequired> preflights,
  }) => _revisionEnvelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    kind: WorkspaceOperationKind.update,
    managedSkillIds: <ManagedSkillId>[
      for (final preflight in preflights) preflight.managedSkillId,
    ],
  );

  @override
  OperationPlan sealUpdatePlan({
    required PreparedOperationEnvelope envelope,
    required List<UpdatePreparationRequired> preflights,
    required List<PreparedUpdatePlan> preparedPlans,
  }) => _sealUpdates(
    envelope: envelope,
    kind: WorkspaceOperationKind.update,
    preflights: preflights,
    preparedPlans: preparedPlans,
  );

  @override
  PreparedOperationEnvelope createCandidatePublishEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required UpdateCandidatePublishPreflight preflight,
  }) => _revisionEnvelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    kind: WorkspaceOperationKind.publishUpdateCandidate,
    managedSkillIds: <ManagedSkillId>[preflight.currentSkill.id],
  );

  @override
  OperationPlan sealCandidatePublishPlan({
    required PreparedOperationEnvelope envelope,
    required UpdateCandidatePublishPreflight preflight,
    required PreparedUpdatePlan preparedPlan,
  }) {
    final operation = _sealUpdates(
      envelope: envelope,
      kind: WorkspaceOperationKind.publishUpdateCandidate,
      preflights: <UpdatePreparationRequired>[],
      preparedPlans: <PreparedUpdatePlan>[preparedPlan],
      candidatePreflight: preflight,
    );
    return operation;
  }

  @override
  PreparedOperationEnvelope createCandidateAbandonEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required UpdateCandidateAbandonPlan abandonPlan,
  }) => _envelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    kind: WorkspaceOperationKind.abandonUpdateCandidate,
    preparations: <_PreparationIntent>[
      _PreparationIntent(
        token: 'bundle-${abandonPlan.cleanupIntent.managedSkillId.value}',
        kind: PreparationStepKind.revisionBundle,
      ),
    ],
  );

  @override
  OperationPlan sealCandidateAbandonPlan({
    required PreparedOperationEnvelope envelope,
    required UpdateCandidateAbandonPlan abandonPlan,
    required PreparedUpdateCandidateAbandon prepared,
  }) {
    final intent = abandonPlan.cleanupIntent;
    if (prepared.managedSkillId != intent.managedSkillId ||
        prepared.sourceLineage != intent.sourceLineage ||
        prepared.bundleRecoveryReference !=
            operationRecoveryReference(
              envelope.operationId,
              'bundle-${intent.managedSkillId.value}',
            )) {
      throw StateError('Prepared Abandon Bundle does not match its intent.');
    }
    final builder =
        _RecoveryPlanBuilder(envelope: envelope, registry: _recoverySpecs)
          ..addDirectory(
            targetPath: _bundlePath(intent.managedSkillId),
            intendedSourcePath: _candidateBundlePath(
              envelope.operationId,
              intent.managedSkillId,
            ),
          )
          ..addAbsent(targetPath: _layout.draftPath(intent.managedSkillId));
    final recovery = builder.finish();
    final operation = _assembler.assemble(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      kind: WorkspaceOperationKind.abandonUpdateCandidate,
      businessChanges: abandonPlan.businessChanges,
      recoverySteps: recovery.steps,
      revisionSelectionChanges: abandonPlan.revisionSelectionChanges,
      subjects: <OperationSubjectIntent>[
        OperationSubjectIntent(
          managedSkillId: abandonPlan.cleanupIntent.managedSkillId,
          displayName: abandonPlan.cleanupIntent.managedSkillId.value,
          sourceLineage: abandonPlan.cleanupIntent.sourceLineage,
        ),
      ],
    );
    _requireSealed(envelope, operation);
    recovery.register();
    return operation;
  }

  @override
  OperationPlan createConflictResolutionPlan({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required ManagedSkillId managedSkillId,
    required UpdateConflictResolutionPlan resolutionPlan,
  }) => _assembler.sqliteOnly(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    kind: WorkspaceOperationKind.resolveUpdateConflict,
    businessChanges: resolutionPlan.businessChanges,
    subjects: <OperationSubjectIntent>[
      OperationSubjectIntent(
        managedSkillId: managedSkillId,
        displayName: managedSkillId.value,
      ),
    ],
  );

  @override
  PreparedOperationEnvelope createRestoreEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RestorePublishPreflight preflight,
  }) => _revisionEnvelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    kind: WorkspaceOperationKind.restorePublish,
    managedSkillIds: <ManagedSkillId>[preflight.skill.id],
  );

  @override
  OperationPlan sealRestorePlan({
    required PreparedOperationEnvelope envelope,
    required RestorePublishPreflight preflight,
    required PreparedRestorePublishPlan preparedPlan,
  }) {
    final builder = _RecoveryPlanBuilder(
      envelope: envelope,
      registry: _recoverySpecs,
    );
    _addExistingLineageBundle(
      builder,
      envelope.operationId,
      preparedPlan.recoveryIntent.managedSkillId,
    );
    _addRestoreMaterializations(
      builder,
      envelope.operationId,
      preparedPlan.materializationIntents,
    );
    if (preparedPlan.recoveryIntent.draftCleanup case final cleanup?) {
      builder.addDraftCleanup(
        targetPath: _layout.draftPath(preflight.skill.id),
        intent: cleanup,
      );
    }
    final recovery = builder.finish();
    final intended = preparedPlan.revisionSelectionChanges.single;
    final operation = _assembler.assemble(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      kind: WorkspaceOperationKind.restorePublish,
      businessChanges: preparedPlan.businessChanges,
      recoverySteps: recovery.steps,
      revisionSelectionChanges: preparedPlan.revisionSelectionChanges,
      subjects: <OperationSubjectIntent>[
        OperationSubjectIntent(
          managedSkillId: preflight.skill.id,
          displayName: preflight.skill.displayName,
          sourceLineage: preflight.state.sourceLineage,
          beforeObjectId: preflight.state.currentEffective,
          afterObjectId: intended.intendedEffective!.objectId,
          beforeContentHash: preflight.skill.currentRevision.contentHash,
          afterContentHash: _revisionHash(
            preparedPlan.businessChanges,
            intended.intendedEffective!.objectId,
          ),
        ),
      ],
    );
    _requireSealed(envelope, operation);
    recovery.register();
    return operation;
  }

  @override
  PreparedOperationEnvelope createDriftEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required DriftResolutionPreflight preflight,
  }) => preflight.keepsExternal
      ? _revisionEnvelope(
          operationId: operationId,
          expectedRepositoryRevision: expectedRepositoryRevision,
          kind: WorkspaceOperationKind.resolveSkillDrift,
          managedSkillIds: [preflight.skill.id],
        )
      : _envelope(
          operationId: operationId,
          expectedRepositoryRevision: expectedRepositoryRevision,
          kind: WorkspaceOperationKind.resolveSkillDrift,
          preparations: [
            _PreparationIntent(
              token: 'materialization-${preflight.skill.id.value}',
              kind: PreparationStepKind.materialization,
            ),
          ],
        );

  @override
  OperationPlan sealDriftPlan({
    required PreparedOperationEnvelope envelope,
    required DriftResolutionPreflight preflight,
    required PreparedRestorePublishPlan? publishedPlan,
    required CancellationToken cancellationToken,
  }) {
    final builder = _RecoveryPlanBuilder(
      envelope: envelope,
      registry: _recoverySpecs,
    );
    if (publishedPlan != null) {
      _addExistingLineageBundle(
        builder,
        envelope.operationId,
        preflight.skill.id,
      );
      if (publishedPlan.recoveryIntent.draftCleanup case final cleanup?) {
        builder.addDraftCleanup(
          targetPath: _layout.draftPath(preflight.skill.id),
          intent: cleanup,
        );
      }
    }
    final currentByPath = {
      for (final artifact in preflight.current.artifacts)
        artifact.targetPath: artifact,
    };
    final targets = <SkillMaterializationArtifact>[];
    if (publishedPlan != null) {
      // Consume the assembler's authoritative materialization intents rather
      // than independently inventing a second set of publication targets.
      for (final intent in publishedPlan.materializationIntents) {
        final targetPath = switch (intent) {
          RestoreRepositoryMaterializationIntent(:final slotKey) =>
            _layout.repositoryCopyPath(slotKey),
          RestoreActivationMaterializationIntent(
            :final activation,
            :final slotKey,
          ) =>
            path.join(activation.location, slotKey),
        };
        final artifact = currentByPath[targetPath];
        if (artifact == null ||
            intent.managedSkillId != preflight.skill.id ||
            intent.revision !=
                publishedPlan
                    .revisionSelectionChanges
                    .single
                    .intendedEffective) {
          throw StateError(
            'Drift publication intent no longer matches inspected targets.',
          );
        }
        targets.add(artifact);
      }
      if (targets.length != currentByPath.length ||
          targets.map((a) => a.targetPath).toSet().length != targets.length) {
        throw StateError(
          'Drift publication must rebuild every inspected target once.',
        );
      }
    } else {
      final reviewedPaths = preflight.review.inspected.artifacts
          .where(
            (a) => a.inspection.state == PublishedArtifactState.mismatching,
          )
          .map((a) => a.targetPath)
          .toSet();
      targets.addAll(
        preflight.current.artifacts.where(
          (a) =>
              reviewedPaths.contains(a.targetPath) ||
              a.inspection.state == PublishedArtifactState.missing,
        ),
      );
    }
    final mutatedPaths = targets.map((a) => a.targetPath).toSet();
    Future<void>? untouchedCheck;
    Future<void> verifyUntouched() => untouchedCheck ??= () async {
      // Restore leaves matching projections alone. Still reject a new drift
      // at those locations before capturing any reviewed replacement.
      for (final artifact in preflight.current.artifacts) {
        if (mutatedPaths.contains(artifact.targetPath)) continue;
        final observed = await _inspectExpectedArtifact(
          preflight,
          artifact,
          artifact.targetPath,
          cancellationToken,
        );
        if (cancellationToken.isCancelled) return;
        if (observed.state != PublishedArtifactState.matching &&
            observed.state != PublishedArtifactState.missing) {
          throw const ExternalOperationPreconditionChanged();
        }
      }
    }();
    for (final artifact in targets) {
      final verifier = _driftVerifier(
        preflight,
        artifact,
        cancellationToken,
        verifyUntouched,
      );
      if (artifact.locationKind ==
          SkillDriftLocationKind.symbolicLinkActivation) {
        builder.addSymbolicLink(
          targetPath: artifact.targetPath,
          linkTarget: _layout.repositoryCopyPath(preflight.skill.slotKey),
          verifyBeforeCapture: verifier,
        );
      } else {
        builder.addDirectory(
          targetPath: artifact.targetPath,
          intendedSourcePath: _candidateMaterializationPath(
            envelope.operationId,
            preflight.skill.id,
          ),
          requirePlainDirectory: false,
          verifyBeforeCapture: verifier,
        );
      }
    }
    final recovery = builder.finish();
    final operation = _assembler.assemble(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      kind: WorkspaceOperationKind.resolveSkillDrift,
      businessChanges:
          publishedPlan?.businessChanges ?? WorkspaceBusinessChangeSet.empty,
      recoverySteps: recovery.steps,
      revisionSelectionChanges:
          publishedPlan?.revisionSelectionChanges ?? const [],
      subjects: [
        publishedPlan == null
            ? _nonPublishedSubject(
                preflight.skill,
                preflight.state.sourceLineage,
              )
            : OperationSubjectIntent(
                managedSkillId: preflight.skill.id,
                displayName: preflight.skill.displayName,
                sourceLineage: preflight.state.sourceLineage,
                beforeObjectId: preflight.state.currentEffective,
                afterObjectId: publishedPlan
                    .revisionSelectionChanges
                    .single
                    .intendedEffective!
                    .objectId,
                beforeContentHash: preflight.skill.currentRevision.contentHash,
                afterContentHash: _revisionHash(
                  publishedPlan.businessChanges,
                  publishedPlan
                      .revisionSelectionChanges
                      .single
                      .intendedEffective!
                      .objectId,
                ),
              ),
      ],
    );
    _requireSealed(envelope, operation);
    recovery.register();
    return operation;
  }

  OperationRecoveryPreCaptureVerifier _driftVerifier(
    DriftResolutionPreflight preflight,
    SkillMaterializationArtifact artifact,
    CancellationToken cancellationToken,
    Future<void> Function() verifyUntouched,
  ) => (targetPath) async {
    await verifyUntouched();
    final reviewed = preflight.review.inspected.artifacts.where(
      (a) => a.targetPath == artifact.targetPath,
    );
    if (reviewed.isNotEmpty &&
        reviewed.single.inspection.state ==
            PublishedArtifactState.mismatching) {
      final expected = reviewed.single.inspection;
      // Content-unreadable wrong types remain restore-only. Their review is
      // bound to bounded no-follow metadata, never to a partial content hash.
      final observed = expected.fingerprint == null
          ? await _artifactInspector.observeMetadata(
              path: targetPath,
              cancellationToken: cancellationToken,
            )
          : await _artifactInspector.observe(
              path: targetPath,
              cancellationToken: cancellationToken,
            );
      if (cancellationToken.isCancelled) return true;
      final sameEvidence = expected.fingerprint != null
          ? observed.fingerprint == expected.fingerprint
          : expected.metadataFingerprint != null &&
                observed.metadataFingerprint == expected.metadataFingerprint;
      if (observed.state == PublishedArtifactState.unsafe ||
          observed.observedEntryKind != expected.observedEntryKind ||
          !sameEvidence) {
        throw const ExternalOperationPreconditionChanged();
      }
    } else {
      final observed = await _inspectExpectedArtifact(
        preflight,
        artifact,
        targetPath,
        cancellationToken,
      );
      if (cancellationToken.isCancelled) return true;
      if (observed.state != PublishedArtifactState.matching &&
          observed.state != PublishedArtifactState.missing) {
        throw const ExternalOperationPreconditionChanged();
      }
    }
    return true;
  };

  Future<PublishedArtifactInspection> _inspectExpectedArtifact(
    DriftResolutionPreflight preflight,
    SkillMaterializationArtifact artifact,
    String targetPath,
    CancellationToken cancellationToken,
  ) => artifact.locationKind == SkillDriftLocationKind.symbolicLinkActivation
      ? _artifactInspector.inspectSymbolicLink(
          path: targetPath,
          expectedTarget: _layout.repositoryCopyPath(preflight.skill.slotKey),
          cancellationToken: cancellationToken,
        )
      : _artifactInspector.inspectDirectory(
          path: targetPath,
          expectedContentHash: preflight.review.effectiveContentHash,
          cancellationToken: cancellationToken,
        );

  OperationPlan _sealUpdates({
    required PreparedOperationEnvelope envelope,
    required WorkspaceOperationKind kind,
    required List<UpdatePreparationRequired> preflights,
    required List<PreparedUpdatePlan> preparedPlans,
    UpdateCandidatePublishPreflight? candidatePreflight,
  }) {
    final preflightBySkill = <ManagedSkillId, UpdatePreparationRequired>{
      for (final preflight in preflights) preflight.managedSkillId: preflight,
    };
    if (candidatePreflight == null &&
        (preflightBySkill.length != preflights.length ||
            preflightBySkill.length != preparedPlans.length)) {
      throw StateError('Update plans no longer align with their preflights.');
    }
    final builder = _RecoveryPlanBuilder(
      envelope: envelope,
      registry: _recoverySpecs,
    );
    final subjects = <OperationSubjectIntent>[];
    final businessMutations = <WorkspaceBusinessMutation>[];
    final selections = <RevisionSelectionChangePlan>[];
    for (final prepared in preparedPlans) {
      final id = prepared.recoveryIntent.managedSkillId;
      final preflight = preflightBySkill[id];
      if (candidatePreflight == null && preflight == null) {
        throw StateError('Prepared Update has no matching preflight.');
      }
      _addExistingLineageBundle(builder, envelope.operationId, id);
      _addUpdateMaterializations(
        builder,
        envelope.operationId,
        prepared.materializationIntents,
      );
      if (prepared.recoveryIntent.draftCleanup case final cleanup?) {
        builder.addDraftCleanup(
          targetPath: _layout.draftPath(id),
          intent: cleanup,
        );
      }
      businessMutations.addAll(prepared.businessChanges.mutations);
      selections.addAll(prepared.revisionSelectionChanges);
      final selection = prepared.revisionSelectionChanges.firstOrNull;
      final skill = candidatePreflight?.currentSkill ?? preflight!.currentSkill;
      subjects.add(
        OperationSubjectIntent(
          managedSkillId: id,
          displayName: skill.displayName,
          sourceLineage: prepared.recoveryIntent.sourceLineage,
          beforeObjectId: selection?.previousEffective?.objectId,
          afterObjectId: selection?.intendedEffective?.objectId,
          beforeContentHash: selection == null
              ? null
              : skill.currentRevision.contentHash,
          afterContentHash: selection?.intendedEffective == null
              ? null
              : _revisionHash(
                  prepared.businessChanges,
                  selection!.intendedEffective!.objectId,
                ),
        ),
      );
    }
    final recovery = builder.finish();
    final operation = _assembler.assemble(
      operationId: envelope.operationId,
      expectedRepositoryRevision: envelope.expectedRepositoryRevision,
      kind: kind,
      businessChanges: WorkspaceBusinessChangeSet(mutations: businessMutations),
      recoverySteps: recovery.steps,
      revisionSelectionChanges: selections,
      subjects: subjects,
    );
    _requireSealed(envelope, operation);
    recovery.register();
    return operation;
  }

  void _addExistingLineageBundle(
    _RecoveryPlanBuilder builder,
    OperationId operationId,
    ManagedSkillId managedSkillId,
  ) {
    builder.addDirectory(
      targetPath: _bundlePath(managedSkillId),
      intendedSourcePath: _candidateBundlePath(operationId, managedSkillId),
    );
  }

  void _addDraftMaterializations(
    _RecoveryPlanBuilder builder,
    OperationId operationId,
    List<DraftMaterializationIntent> intents,
  ) {
    for (final intent in intents) {
      final source = _candidateMaterializationPath(
        operationId,
        intent.managedSkillId,
      );
      switch (intent) {
        case DraftRepositoryMaterializationIntent(:final slotKey):
          builder.addDirectory(
            targetPath: _layout.repositoryCopyPath(slotKey),
            intendedSourcePath: source,
          );
        case DraftActivationMaterializationIntent(
          :final activation,
          :final slotKey,
        ):
          _addActivation(
            builder,
            activation: activation,
            slotKey: slotKey,
            repositoryCopy: _layout.repositoryCopyPath(slotKey),
            materialization: source,
          );
      }
    }
  }

  void _addRestoreMaterializations(
    _RecoveryPlanBuilder builder,
    OperationId operationId,
    List<RestoreMaterializationIntent> intents,
  ) {
    for (final intent in intents) {
      final source = _candidateMaterializationPath(
        operationId,
        intent.managedSkillId,
      );
      switch (intent) {
        case RestoreRepositoryMaterializationIntent(:final slotKey):
          builder.addDirectory(
            targetPath: _layout.repositoryCopyPath(slotKey),
            intendedSourcePath: source,
          );
        case RestoreActivationMaterializationIntent(
          :final activation,
          :final slotKey,
        ):
          _addActivation(
            builder,
            activation: activation,
            slotKey: slotKey,
            repositoryCopy: _layout.repositoryCopyPath(slotKey),
            materialization: source,
          );
      }
    }
  }

  void _addUpdateMaterializations(
    _RecoveryPlanBuilder builder,
    OperationId operationId,
    List<UpdateMaterializationIntent> intents,
  ) {
    for (final intent in intents) {
      final source = _candidateMaterializationPath(
        operationId,
        intent.managedSkillId,
      );
      switch (intent) {
        case UpdateRepositoryMaterializationIntent(
          :final oldSlotKey,
          :final newSlotKey,
        ):
          if (oldSlotKey != newSlotKey) {
            builder.addAbsent(
              targetPath: _layout.repositoryCopyPath(oldSlotKey),
            );
          }
          builder.addDirectory(
            targetPath: _layout.repositoryCopyPath(newSlotKey),
            intendedSourcePath: source,
          );
        case UpdateActivationMaterializationIntent(
          :final activation,
          :final oldSlotKey,
          :final newSlotKey,
        ):
          if (oldSlotKey != newSlotKey) {
            builder.addAbsent(
              targetPath: path.join(activation.location, oldSlotKey),
            );
          }
          _addActivation(
            builder,
            activation: activation,
            slotKey: newSlotKey,
            repositoryCopy: _layout.repositoryCopyPath(newSlotKey),
            materialization: source,
          );
        case UpdateCandidateDraftMaterializationIntent():
          builder.addDirectory(
            targetPath: _layout.draftPath(intent.managedSkillId),
            intendedSourcePath: source,
            makeReadOnly: false,
          );
      }
    }
  }

  void _addActivation(
    _RecoveryPlanBuilder builder, {
    required SkillActivation activation,
    required String slotKey,
    required String repositoryCopy,
    required String materialization,
  }) {
    final target = path.join(activation.location, slotKey);
    switch (activation.mode) {
      case ActivationMode.copy:
        builder.addDirectory(
          targetPath: target,
          intendedSourcePath: materialization,
        );
      case ActivationMode.symbolicLink:
        builder.addSymbolicLink(targetPath: target, linkTarget: repositoryCopy);
    }
  }

  PreparedOperationEnvelope _revisionEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required WorkspaceOperationKind kind,
    required List<ManagedSkillId> managedSkillIds,
  }) => _envelope(
    operationId: operationId,
    expectedRepositoryRevision: expectedRepositoryRevision,
    kind: kind,
    preparations: <_PreparationIntent>[
      for (final id in managedSkillIds) ...<_PreparationIntent>[
        _PreparationIntent(
          token: 'candidate-${id.value}',
          kind: PreparationStepKind.revisionCandidate,
        ),
        _PreparationIntent(
          token: 'bundle-${id.value}',
          kind: PreparationStepKind.revisionBundle,
        ),
        _PreparationIntent(
          token: 'materialization-${id.value}',
          kind: PreparationStepKind.materialization,
        ),
        _PreparationIntent(
          token: 'draft-${id.value}',
          kind: PreparationStepKind.materialization,
        ),
      ],
    ],
  );

  PreparedOperationEnvelope _envelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required WorkspaceOperationKind kind,
    required List<_PreparationIntent> preparations,
  }) {
    final committed = expectedRepositoryRevision.next();
    return PreparedOperationEnvelope(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: committed,
      operationGeneration: committed.value,
      preparationSteps: <PreparationOperationStep>[
        for (var index = 0; index < preparations.length; index += 1)
          PreparationOperationStep(
            stepId:
                '${kind.name}.prepare-${(index + 1).toString().padLeft(4, '0')}',
            recoveryReference: operationRecoveryReference(
              operationId,
              preparations[index].token,
            ),
            kind: preparations[index].kind,
          ),
      ],
      record: OperationRecordPlan(
        operationId: operationId,
        kind: kind.name,
        subjects: const <OperationSubjectPlan>[],
        retainWithoutSubjects: true,
      ),
    );
  }

  String _storePath(ManagedSkillId id) => _layout.revisionStorePath(id);

  String _bundlePath(ManagedSkillId id) => _layout.revisionBundlePath(id);

  String _candidateRevisionRoot(OperationId operationId, ManagedSkillId id) =>
      _layout.operationRevisionCandidateRoot(operationId, id);

  String _candidateBundlePath(OperationId operationId, ManagedSkillId id) =>
      _layout.operationBundleCandidatePath(operationId, id);

  String _candidateMaterializationPath(
    OperationId operationId,
    ManagedSkillId id,
  ) => _layout.operationTreeCandidatePath(operationId, id);

  String _candidateDraftPath(OperationId operationId, ManagedSkillId id) =>
      _layout.operationDraftCandidatePath(operationId, id);
}

final class _PreparationIntent {
  const _PreparationIntent({required this.token, required this.kind});

  final String token;
  final PreparationStepKind kind;
}

final class _RecoveryPlanBuilder {
  _RecoveryPlanBuilder({
    required PreparedOperationEnvelope envelope,
    required OperationRecoverySpecRegistry registry,
  }) : _operationId = envelope.operationId,
       _expected = envelope.expectedRepositoryRevision,
       _committed = envelope.committedRepositoryRevision,
       _preparation = <PreparationOperationStep>[...envelope.preparationSteps],
       _registry = registry {
    for (final step in envelope.preparationSteps) {
      _bindings.add(
        OperationRecoveryStepBinding(
          reference: step.recoveryReference,
          action: OperationRecoveryAction.prepareEvidence,
        ),
      );
    }
    // Deferred candidate construction completes the envelope prefix before a
    // sealed recovery spec exists. This appended step publishes and verifies
    // that spec's durable bundle after sealing and before the first apply.
    final evidence = operationRecoveryReference(
      envelope.operationId,
      'sealed-recovery-evidence',
    );
    _preparation.add(
      PreparationOperationStep(
        stepId: 'revision.prepare-sealed-recovery-evidence',
        recoveryReference: evidence,
        kind: PreparationStepKind.recoveryEvidence,
      ),
    );
    _bindings.add(
      OperationRecoveryStepBinding(
        reference: evidence,
        action: OperationRecoveryAction.prepareEvidence,
      ),
    );
  }

  _RecoveryPlanBuilder.oneStage({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required OperationRecoverySpecRegistry registry,
  }) : _operationId = operationId,
       _expected = expectedRepositoryRevision,
       _committed = expectedRepositoryRevision.next(),
       _registry = registry,
       _preparation = <PreparationOperationStep>[
         PreparationOperationStep(
           stepId: 'recovery.prepare-evidence',
           recoveryReference: operationRecoveryReference(
             operationId,
             'revision-evidence',
           ),
           kind: PreparationStepKind.recoveryEvidence,
         ),
       ] {
    _bindings.add(
      OperationRecoveryStepBinding(
        reference: _preparation.single.recoveryReference,
        action: OperationRecoveryAction.prepareEvidence,
      ),
    );
  }

  final OperationId _operationId;
  final RepositoryRevision _expected;
  final RepositoryRevision _committed;
  final OperationRecoverySpecRegistry _registry;
  final List<PreparationOperationStep> _preparation;
  final List<OperationRecoveryEntrySpec> _entries =
      <OperationRecoveryEntrySpec>[];
  final List<OperationRecoveryDraftCleanupSpec> _draftCleanups =
      <OperationRecoveryDraftCleanupSpec>[];
  final List<OperationRecoveryStepBinding> _bindings =
      <OperationRecoveryStepBinding>[];
  final List<ApplyingOperationStep> _applying = <ApplyingOperationStep>[];
  final List<FinalizationOperationStep> _finalization =
      <FinalizationOperationStep>[];

  void addDirectory({
    required String targetPath,
    required String intendedSourcePath,
    bool makeReadOnly = true,
    bool requirePlainDirectory = true,
    OperationRecoveryPreCaptureVerifier? verifyBeforeCapture,
    bool requiresInertBeforeImage = false,
  }) => _addEntry(
    targetPath: targetPath,
    intendedSourcePath: intendedSourcePath,
    intendedKind: OperationRecoveryEntryKind.directory,
    makeReadOnly: makeReadOnly,
    requirePlainDirectory: requirePlainDirectory,
    verifyBeforeCapture: verifyBeforeCapture,
    requiresInertBeforeImage: requiresInertBeforeImage,
  );

  void addSymbolicLink({
    required String targetPath,
    required String linkTarget,
    OperationRecoveryPreCaptureVerifier? verifyBeforeCapture,
    bool requiresInertBeforeImage = false,
  }) => _addEntry(
    targetPath: targetPath,
    intendedKind: OperationRecoveryEntryKind.symbolicLink,
    intendedSymbolicLinkTarget: linkTarget,
    makeReadOnly: false,
    requirePlainDirectory: false,
    verifyBeforeCapture: verifyBeforeCapture,
    requiresInertBeforeImage: requiresInertBeforeImage,
  );

  void addAbsent({
    required String targetPath,
    OperationRecoveryPreCaptureVerifier? verifyBeforeCapture,
  }) => _addEntry(
    targetPath: targetPath,
    intendedKind: null,
    makeReadOnly: false,
    requirePlainDirectory: false,
    verifyBeforeCapture: verifyBeforeCapture,
  );

  void addDraftCleanup({
    required String targetPath,
    required PublishedDraftCleanupIntent intent,
  }) {
    if (_entries.any((entry) => path.equals(entry.targetPath, targetPath)) ||
        _draftCleanups.any(
          (cleanup) => path.equals(cleanup.targetPath, targetPath),
        )) {
      throw StateError('A recovery plan cannot mutate one target twice.');
    }
    final number = (_draftCleanups.length + 1).toString().padLeft(4, '0');
    final cleanupId = 'draft-cleanup-$number';
    final reference = operationRecoveryReference(
      _operationId,
      'draft-finalize-$number',
    );
    _draftCleanups.add(
      OperationRecoveryDraftCleanupSpec(
        cleanupId: cleanupId,
        managedSkillId: intent.managedSkillId,
        expectedBaseObjectId: intent.expectedBaseObjectId,
        targetPath: targetPath,
        capturedFingerprint: intent.capturedFingerprint,
      ),
    );
    _bindings.add(
      OperationRecoveryStepBinding(
        reference: reference,
        action: OperationRecoveryAction.finalizeDraftCleanup,
        entryId: cleanupId,
      ),
    );
    _finalization.add(
      FinalizationOperationStep(
        stepId: 'revision.finalize-draft-$number',
        recoveryReference: reference,
        kind: FinalizationStepKind.draftLifecycle,
      ),
    );
  }

  void _addEntry({
    required String targetPath,
    required OperationRecoveryEntryKind? intendedKind,
    String? intendedSourcePath,
    String? intendedSymbolicLinkTarget,
    required bool makeReadOnly,
    required bool requirePlainDirectory,
    OperationRecoveryPreCaptureVerifier? verifyBeforeCapture,
    bool requiresInertBeforeImage = false,
  }) {
    if (_entries.any((entry) => path.equals(entry.targetPath, targetPath))) {
      throw StateError('A recovery plan cannot mutate one target twice.');
    }
    final number = (_entries.length + 1).toString().padLeft(4, '0');
    final entryId = 'revision-$number';
    final apply = operationRecoveryReference(_operationId, 'apply-$number');
    final verify = operationRecoveryReference(_operationId, 'verify-$number');
    final cleanup = operationRecoveryReference(_operationId, 'cleanup-$number');
    _entries.add(
      OperationRecoveryEntrySpec(
        entryId: entryId,
        targetPath: targetPath,
        intendedSourcePath: intendedSourcePath,
        intendedKind: intendedKind,
        intendedSymbolicLinkTarget: intendedSymbolicLinkTarget,
        verifyBeforeCapture: verifyBeforeCapture,
        requiresInertBeforeImage: requiresInertBeforeImage,
        makeReadOnly: makeReadOnly,
        requirePlainDirectory: requirePlainDirectory,
      ),
    );
    _bindings.addAll(<OperationRecoveryStepBinding>[
      OperationRecoveryStepBinding(
        reference: apply,
        action: OperationRecoveryAction.applyEntry,
        entryId: entryId,
      ),
      OperationRecoveryStepBinding(
        reference: verify,
        action: OperationRecoveryAction.verifyEntry,
        entryId: entryId,
      ),
      OperationRecoveryStepBinding(
        reference: cleanup,
        action: OperationRecoveryAction.cleanupEntryResidue,
        entryId: entryId,
      ),
    ]);
    _applying.add(
      ApplyingOperationStep(
        stepId: 'revision.apply-$number',
        recoveryReference: apply,
        kind: ApplyingStepKind.materializationReplacement,
      ),
    );
    _finalization.addAll(<FinalizationOperationStep>[
      FinalizationOperationStep(
        stepId: 'revision.verify-$number',
        recoveryReference: verify,
        kind: FinalizationStepKind.materializationVerification,
      ),
      FinalizationOperationStep(
        stepId: 'revision.cleanup-$number',
        recoveryReference: cleanup,
        kind: FinalizationStepKind.recoveryEvidenceCleanup,
      ),
    ]);
  }

  _BuiltRecoveryPlan finish() {
    final backup = operationRecoveryReference(_operationId, 'revision-backup');
    final staging = operationRecoveryReference(
      _operationId,
      'revision-staging',
    );
    final retain = operationRecoveryReference(_operationId, 'revision-retain');
    _bindings.addAll(<OperationRecoveryStepBinding>[
      OperationRecoveryStepBinding(
        reference: backup,
        action: OperationRecoveryAction.backupRotation,
      ),
      OperationRecoveryStepBinding(
        reference: staging,
        action: OperationRecoveryAction.cleanupStaging,
      ),
      OperationRecoveryStepBinding(
        reference: retain,
        action: OperationRecoveryAction.retainRecoveryEvidence,
      ),
    ]);
    _finalization.addAll(<FinalizationOperationStep>[
      FinalizationOperationStep(
        stepId: 'revision.rotate-backup',
        recoveryReference: backup,
        kind: FinalizationStepKind.backupRotation,
      ),
      FinalizationOperationStep(
        stepId: 'revision.cleanup-staging',
        recoveryReference: staging,
        kind: FinalizationStepKind.stagingCleanup,
      ),
      FinalizationOperationStep(
        stepId: 'revision.retain-evidence-until-completed',
        recoveryReference: retain,
        kind: FinalizationStepKind.recoveryEvidenceCleanup,
      ),
    ]);
    final spec = OperationRecoveryBundleSpec(
      context: OperationRecoveryContext(
        operationId: _operationId,
        expectedRepositoryRevision: _expected,
        committedRepositoryRevision: _committed,
        destructive: false,
      ),
      entries: _entries,
      bindings: _bindings,
      draftCleanups: _draftCleanups,
    );
    return _BuiltRecoveryPlan(
      steps: OperationRecoveryPlanSteps(
        preparationSteps: _preparation,
        applyingSteps: _applying,
        finalizationSteps: _finalization,
      ),
      register: () => _registry.register(spec),
    );
  }
}

final class _BuiltRecoveryPlan {
  const _BuiltRecoveryPlan({required this.steps, required this.register});

  final OperationRecoveryPlanSteps steps;
  final void Function() register;
}

WorkspaceOperationKind _initialKind(InitialImportKind kind) => switch (kind) {
  InitialImportKind.install => WorkspaceOperationKind.install,
  InitialImportKind.adoption => WorkspaceOperationKind.adopt,
};

ManagedSkill _previewSkill(
  InitialImportSubjectPreflight subject,
  int plannedAtMicros,
) => ManagedSkill(
  id: subject.managedSkillId,
  createdAt: DateTime.fromMicrosecondsSinceEpoch(plannedAtMicros, isUtc: true),
  slotKey: subject.skill.slotKey,
  declaredName: subject.skill.declaredName,
  displayName: subject.skill.declaredName,
  description: subject.skill.description,
  source: subject.skill.provenance,
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: subject.skill.tree.contentHash,
    fileCount: subject.skill.tree.fileCount,
    byteSize: subject.skill.tree.byteSize,
    publishedAt: DateTime.fromMicrosecondsSinceEpoch(
      plannedAtMicros,
      isUtc: true,
    ),
  ),
);

OperationSubjectIntent _nonPublishedSubject(
  ManagedSkill skill,
  SourceLineageReference lineage,
) => OperationSubjectIntent(
  managedSkillId: skill.id,
  displayName: skill.displayName,
  sourceLineage: lineage,
);

String _revisionHash(
  WorkspaceBusinessChangeSet changes,
  RevisionObjectId objectId,
) => changes.mutations
    .whereType<PutRevisionMetadata>()
    .singleWhere((mutation) => mutation.objectId == objectId.value)
    .contentHash;

void _requireSealed(PreparedOperationEnvelope envelope, OperationPlan plan) {
  if (!envelope.isSealedBy(plan)) {
    throw StateError('The revision operation plan changed its Journal prefix.');
  }
}
