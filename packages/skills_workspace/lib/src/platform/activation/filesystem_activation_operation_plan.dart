import '../../application/activation/activation_mutation_models.dart';
import '../../application/operations/operation_models.dart';
import '../../application/operations/operation_plan_assembler.dart';
import '../../application/ports/activation_mutation_ports.dart';
import '../../application/ports/operation_ports.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../operations/operation_recovery_bundle.dart';

/// Binds Activation business changes to durable filesystem recovery entries.
///
/// Copy bytes and displaced targets are captured into the operation recovery
/// bundle before Applying. Symbolic links store their target directly in that
/// bundle. Every entry is therefore independently idempotent for rollback and
/// roll-forward after process termination.
final class FilesystemActivationOperationPlan
    implements ActivationOperationPlanPort {
  const FilesystemActivationOperationPlan({
    required ActivationMaterializationPathPort materializationPaths,
    required OperationPlanAssembler assembler,
    required OperationRecoverySpecRegistry recoverySpecs,
    required ActivationTargetExpectationPort targetExpectations,
  }) : _materializationPaths = materializationPaths,
       _assembler = assembler,
       _recoverySpecs = recoverySpecs,
       _targetExpectations = targetExpectations;

  final ActivationMaterializationPathPort _materializationPaths;
  final OperationPlanAssembler _assembler;
  final OperationRecoverySpecRegistry _recoverySpecs;
  final ActivationTargetExpectationPort _targetExpectations;

  @override
  OperationPlan assemble({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositorySnapshot planningSnapshot,
    required WorkspaceOperationKind kind,
    required ActivationMutationPlan mutation,
    required List<OperationSubjectIntent> subjects,
  }) {
    if (kind != WorkspaceOperationKind.activate &&
        kind != WorkspaceOperationKind.confirmActivationTakeover &&
        kind != WorkspaceOperationKind.deactivate) {
      throw ArgumentError.value(kind, 'kind', 'is not an Activation mutation');
    }
    if (!mutation.changed || mutation.businessChanges.isEmpty) {
      throw ArgumentError.value(
        mutation,
        'mutation',
        'must contain a committed Activation change',
      );
    }
    if (mutation.pathMutations.isEmpty) {
      return _assembler.sqliteOnly(
        operationId: operationId,
        expectedRepositoryRevision: expectedRepositoryRevision,
        kind: kind,
        businessChanges: mutation.businessChanges,
        subjects: subjects,
      );
    }

    final committed = expectedRepositoryRevision.next();
    final entries = <OperationRecoveryEntrySpec>[];
    final bindings = <OperationRecoveryStepBinding>[];
    final preparation = <PreparationOperationStep>[];
    final applying = <ApplyingOperationStep>[];
    final finalization = <FinalizationOperationStep>[];

    final evidence = operationRecoveryReference(operationId, 'evidence');
    bindings.add(
      OperationRecoveryStepBinding(
        reference: evidence,
        action: OperationRecoveryAction.prepareEvidence,
      ),
    );
    preparation.add(
      PreparationOperationStep(
        stepId: 'activation.prepare-evidence',
        recoveryReference: evidence,
        kind: PreparationStepKind.recoveryEvidence,
      ),
    );

    for (var index = 0; index < mutation.pathMutations.length; index += 1) {
      final pathMutation = mutation.pathMutations[index];
      final number = (index + 1).toString().padLeft(4, '0');
      final entryId = 'activation-$number';
      final applyReference = operationRecoveryReference(
        operationId,
        'apply-$number',
      );
      final verifyReference = operationRecoveryReference(
        operationId,
        'verify-$number',
      );
      final cleanupReference = operationRecoveryReference(
        operationId,
        'cleanup-$number',
      );
      final skill = planningSnapshot.findSkill(pathMutation.managedSkillId);
      if (skill == null || skill.slotKey != pathMutation.slotKey) {
        throw StateError('Activation plan no longer matches its Snapshot.');
      }

      entries.add(switch (pathMutation) {
        final MaterializeActivationPath materialization =>
          _materializationEntry(
            entryId: entryId,
            skill: skill,
            mutation: materialization,
          ),
        DeleteActivationPath() => OperationRecoveryEntrySpec(
          entryId: entryId,
          targetPath: pathMutation.targetPath,
          intendedSourcePath: null,
          intendedKind: null,
          makeReadOnly: true,
          requirePlainDirectory: false,
        ),
      });
      bindings.addAll(<OperationRecoveryStepBinding>[
        OperationRecoveryStepBinding(
          reference: applyReference,
          action: OperationRecoveryAction.applyEntry,
          entryId: entryId,
        ),
        OperationRecoveryStepBinding(
          reference: verifyReference,
          action: OperationRecoveryAction.verifyEntry,
          entryId: entryId,
        ),
        OperationRecoveryStepBinding(
          reference: cleanupReference,
          action: OperationRecoveryAction.cleanupEntryResidue,
          entryId: entryId,
        ),
      ]);
      applying.add(
        ApplyingOperationStep(
          stepId: 'activation.apply-$number',
          recoveryReference: applyReference,
          kind: ApplyingStepKind.materializationReplacement,
        ),
      );
      finalization.addAll(<FinalizationOperationStep>[
        FinalizationOperationStep(
          stepId: 'activation.verify-$number',
          recoveryReference: verifyReference,
          kind: FinalizationStepKind.materializationVerification,
        ),
        FinalizationOperationStep(
          stepId: 'activation.cleanup-$number',
          recoveryReference: cleanupReference,
          kind: FinalizationStepKind.recoveryEvidenceCleanup,
        ),
      ]);
    }

    final backup = operationRecoveryReference(operationId, 'backup');
    final staging = operationRecoveryReference(operationId, 'staging');
    final retain = operationRecoveryReference(operationId, 'retain');
    bindings.addAll(<OperationRecoveryStepBinding>[
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
    finalization.addAll(<FinalizationOperationStep>[
      FinalizationOperationStep(
        stepId: 'activation.rotate-backup',
        recoveryReference: backup,
        kind: FinalizationStepKind.backupRotation,
      ),
      FinalizationOperationStep(
        stepId: 'activation.cleanup-staging',
        recoveryReference: staging,
        kind: FinalizationStepKind.stagingCleanup,
      ),
      FinalizationOperationStep(
        stepId: 'activation.retain-evidence-until-completed',
        recoveryReference: retain,
        kind: FinalizationStepKind.recoveryEvidenceCleanup,
      ),
    ]);

    final recoverySteps = OperationRecoveryPlanSteps(
      preparationSteps: preparation,
      applyingSteps: applying,
      finalizationSteps: finalization,
    );
    final spec = OperationRecoveryBundleSpec(
      context: OperationRecoveryContext(
        operationId: operationId,
        expectedRepositoryRevision: expectedRepositoryRevision,
        committedRepositoryRevision: committed,
        destructive: false,
      ),
      entries: entries,
      bindings: bindings,
    );
    _recoverySpecs.register(spec);
    return _assembler.assemble(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      kind: kind,
      businessChanges: mutation.businessChanges,
      recoverySteps: recoverySteps,
      subjects: subjects,
    );
  }

  OperationRecoveryEntrySpec _materializationEntry({
    required String entryId,
    required ManagedSkill skill,
    required MaterializeActivationPath mutation,
  }) {
    final repositoryCopyPath = _materializationPaths.repositoryCopyPath(
      skill.slotKey,
    );
    final expectation = mutation.expectation;
    final verifyBeforeCapture =
        expectation.kind == ActivationTargetExpectationKind.managed
        ? null
        : (String resolvedTargetPath) => _targetExpectations.matches(
            skill: skill,
            target: mutation.target,
            targetPath: resolvedTargetPath,
            expectation: expectation,
          );
    return switch (mutation.target.mode) {
      ActivationMode.copy => OperationRecoveryEntrySpec(
        entryId: entryId,
        targetPath: mutation.targetPath,
        intendedSourcePath: repositoryCopyPath,
        intendedKind: OperationRecoveryEntryKind.directory,
        verifyBeforeCapture: verifyBeforeCapture,
        makeReadOnly: true,
        requirePlainDirectory: true,
      ),
      ActivationMode.symbolicLink => OperationRecoveryEntrySpec(
        entryId: entryId,
        targetPath: mutation.targetPath,
        intendedSourcePath: null,
        intendedKind: OperationRecoveryEntryKind.symbolicLink,
        intendedSymbolicLinkTarget: repositoryCopyPath,
        verifyBeforeCapture: verifyBeforeCapture,
        makeReadOnly: false,
        requirePlainDirectory: false,
      ),
    };
  }
}
