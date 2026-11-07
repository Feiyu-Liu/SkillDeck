import 'dart:convert';
import 'dart:typed_data';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../application/operations/destructive_recovery_intent.dart';
import '../../application/operations/operation_models.dart';
import '../../application/operations/workspace_business_changes.dart';
import '../../application/ports/operation_ports.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/identifiers.dart';
import '../../domain/draft_snapshot.dart';

/// Schema 3 records contained symbolic links inside directory snapshots and
/// percent-encodes every manifest string value, because canonical JSON
/// rewrites strings to NFC and would otherwise lose NFD file names.
const int operationRecoveryBundleSchemaVersion = 3;

/// Schema 2 bundles written before an upgrade stay readable so recoveries
/// pending across the upgrade still complete.
const int _legacyOperationRecoveryBundleSchemaVersion = 2;

const Set<int> _readableSchemaVersions = <int>{
  _legacyOperationRecoveryBundleSchemaVersion,
  operationRecoveryBundleSchemaVersion,
};

enum OperationRecoveryAction {
  prepareEvidence,
  applyEntry,
  verifyEntry,
  cleanupEntryResidue,
  backupRotation,
  armDestructiveBarrier,
  prepareDestructiveResources,
  verifyDestructiveResources,
  completeDestructiveBackup,
  cleanupStaging,
  retainRecoveryEvidence,
  finalizeDraftCleanup,
}

enum OperationRecoveryEntryKind { file, directory, symbolicLink }

enum OperationRecoveryFailureReason {
  invalidReference,
  unregisteredPlan,
  bundleMissing,
  bundleCorrupt,
  unsupportedSchema,
  checksumMismatch,
  unsafePath,
  entryTypeChanged,
  operationMismatch,
  unsupportedStepAction,
  conflictingRecoveryEntry,
  restoreIoFailure,
}

final class OperationRecoveryException
    implements Exception, OperationAbortDetailSource {
  const OperationRecoveryException(this.reason);

  final OperationRecoveryFailureReason reason;

  @override
  OperationAbortDetail get abortDetail => switch (reason) {
    OperationRecoveryFailureReason.conflictingRecoveryEntry =>
      OperationAbortDetail.recoveryConflict,
    _ => OperationAbortDetail.recoveryEvidence,
  };

  @override
  String toString() => 'OperationRecoveryException(${reason.name})';
}

final class OperationRecoveryContext {
  const OperationRecoveryContext({
    required this.operationId,
    required this.expectedRepositoryRevision,
    required this.committedRepositoryRevision,
    required this.destructive,
  });

  final OperationId operationId;
  final RepositoryRevision expectedRepositoryRevision;
  final RepositoryRevision committedRepositoryRevision;
  final bool destructive;
}

final class OperationRecoveryStepBinding {
  OperationRecoveryStepBinding({
    required this.reference,
    required this.action,
    this.entryId,
  }) {
    final decoded = decodeOperationRecoveryReference(reference);
    if (decoded.token.trim().isEmpty) {
      throw ArgumentError.value(reference, 'reference', 'invalid token');
    }
    final entryRequired = switch (action) {
      OperationRecoveryAction.applyEntry ||
      OperationRecoveryAction.verifyEntry ||
      OperationRecoveryAction.cleanupEntryResidue ||
      OperationRecoveryAction.finalizeDraftCleanup => true,
      _ => false,
    };
    if (entryRequired != (entryId != null)) {
      throw ArgumentError.value(
        entryId,
        'entryId',
        entryRequired ? 'is required for this action' : 'must be absent',
      );
    }
    if (entryId != null) _requireSafeSegment(entryId!, 'entryId');
  }

  final RecoveryReference reference;
  final OperationRecoveryAction action;
  final String? entryId;
}

/// In-memory preparation input. Paths never cross the application plan or
/// SQLite boundary; [OperationRecoveryBundleManifest] captures them durably.
typedef OperationRecoveryPreCaptureVerifier =
    Future<bool> Function(String resolvedTargetPath);

final class OperationRecoveryEntrySpec {
  OperationRecoveryEntrySpec({
    required this.entryId,
    required this.targetPath,
    required this.intendedSourcePath,
    required this.intendedKind,
    this.intendedSymbolicLinkTarget,
    this.verifyBeforeCapture,
    this.requiresInertBeforeImage = false,
    this.makeReadOnly = true,
    this.requirePlainDirectory = true,
  }) {
    _requireSafeSegment(entryId, 'entryId');
    _requireAbsolutePath(targetPath, 'targetPath');
    final usesSource = intendedSourcePath != null;
    final usesDirectLink = intendedSymbolicLinkTarget != null;
    if (usesSource && usesDirectLink) {
      throw ArgumentError(
        'An intended entry cannot use both a source and a direct link target.',
      );
    }
    if (!usesSource && !usesDirectLink && intendedKind != null) {
      throw ArgumentError('An absent intended entry cannot declare a kind.');
    }
    if (usesSource && intendedKind == null) {
      throw ArgumentError('An intended source path requires an entry kind.');
    }
    if (usesDirectLink &&
        intendedKind != OperationRecoveryEntryKind.symbolicLink) {
      throw ArgumentError(
        'A direct link target requires the symbolic-link entry kind.',
      );
    }
    if (intendedSourcePath != null) {
      _requireAbsolutePath(intendedSourcePath!, 'intendedSourcePath');
    }
    if (intendedSymbolicLinkTarget != null &&
        intendedSymbolicLinkTarget!.trim().isEmpty) {
      throw ArgumentError.value(
        intendedSymbolicLinkTarget,
        'intendedSymbolicLinkTarget',
        'must not be empty',
      );
    }
  }

  final String entryId;
  final String targetPath;
  final String? intendedSourcePath;
  final OperationRecoveryEntryKind? intendedKind;
  final String? intendedSymbolicLinkTarget;

  /// In-memory, operation-scoped guard evaluated before the durable recovery
  /// bundle captures the target's previous bytes.
  ///
  /// It is intentionally not serialized. If the process stops before bundle
  /// publication, Prepared recovery rolls back rather than resuming an
  /// unverified precondition.
  final OperationRecoveryPreCaptureVerifier? verifyBeforeCapture;

  /// Adoption-only condition on the captured image, before any target mutation.
  final bool requiresInertBeforeImage;
  final bool makeReadOnly;
  final bool requirePlainDirectory;
}

/// Private, durable input for one post-commit Draft compare-and-delete.
final class OperationRecoveryDraftCleanupSpec {
  OperationRecoveryDraftCleanupSpec({
    required this.cleanupId,
    required this.managedSkillId,
    required this.expectedBaseObjectId,
    required this.targetPath,
    required this.capturedFingerprint,
  }) {
    _requireSafeSegment(cleanupId, 'cleanupId');
    _requireAbsolutePath(targetPath, 'targetPath');
  }

  final String cleanupId;
  final ManagedSkillId managedSkillId;
  final RevisionObjectId expectedBaseObjectId;
  final String targetPath;
  final DraftFingerprint capturedFingerprint;
}

final class OperationRecoveryBundleSpec {
  OperationRecoveryBundleSpec({
    required this.context,
    required List<OperationRecoveryEntrySpec> entries,
    required List<OperationRecoveryStepBinding> bindings,
    List<OperationRecoveryDraftCleanupSpec> draftCleanups = const [],
    this.destructiveIntent,
  }) : entries = List.unmodifiable(entries),
       bindings = List.unmodifiable(bindings),
       draftCleanups = List.unmodifiable(draftCleanups) {
    if (context.destructive != (destructiveIntent != null)) {
      throw ArgumentError(
        'Destructive context and recovery intent must coexist.',
      );
    }
    final entryIds = entries.map((entry) => entry.entryId).toSet();
    final cleanupIds = draftCleanups
        .map((cleanup) => cleanup.cleanupId)
        .toSet();
    if (entryIds.length != entries.length) {
      throw ArgumentError.value(entries, 'entries', 'contains duplicates');
    }
    if (cleanupIds.length != draftCleanups.length ||
        entryIds.intersection(cleanupIds).isNotEmpty) {
      throw ArgumentError('Recovery Draft cleanup IDs must be unique.');
    }
    final references = <String>{};
    for (final binding in bindings) {
      final decoded = decodeOperationRecoveryReference(binding.reference);
      if (decoded.operationId != context.operationId) {
        throw ArgumentError('A Recovery Reference belongs to another plan.');
      }
      if (!references.add(binding.reference.encoded)) {
        throw ArgumentError.value(
          bindings,
          'bindings',
          'contains duplicate references',
        );
      }
      final expectedIds =
          binding.action == OperationRecoveryAction.finalizeDraftCleanup
          ? cleanupIds
          : entryIds;
      if (binding.entryId != null && !expectedIds.contains(binding.entryId)) {
        throw ArgumentError.value(
          binding.entryId,
          'binding.entryId',
          'does not identify an entry',
        );
      }
    }
  }

  final OperationRecoveryContext context;
  final List<OperationRecoveryEntrySpec> entries;
  final List<OperationRecoveryStepBinding> bindings;
  final List<OperationRecoveryDraftCleanupSpec> draftCleanups;
  final DestructiveOperationRecoveryIntent? destructiveIntent;
}

final class OperationRecoverySpecRegistry {
  final Map<OperationId, OperationRecoveryBundleSpec> _specs = {};
  final Map<OperationId, List<OperationRecoveryEntrySpec>>
  _pendingDestructiveEntries = {};

  void register(OperationRecoveryBundleSpec spec) {
    final existing = _specs[spec.context.operationId];
    if (existing != null && !identical(existing, spec)) {
      throw StateError('A different recovery plan is already registered.');
    }
    _specs[spec.context.operationId] = spec;
  }

  OperationRecoveryBundleSpec? lookup(OperationId operationId) =>
      _specs[operationId];

  void stageDestructiveEntries(
    OperationId operationId,
    List<OperationRecoveryEntrySpec> entries,
  ) {
    if (_specs.containsKey(operationId) ||
        _pendingDestructiveEntries.containsKey(operationId) ||
        entries.isEmpty) {
      throw StateError('Destructive recovery entries cannot be staged.');
    }
    _pendingDestructiveEntries[operationId] = List.unmodifiable(entries);
  }

  List<OperationRecoveryEntrySpec> takeDestructiveEntries(
    OperationId operationId,
  ) {
    final entries = _pendingDestructiveEntries.remove(operationId);
    if (entries == null || entries.isEmpty) {
      throw StateError('Destructive recovery entries were not prepared.');
    }
    return entries;
  }

  void forget(OperationId operationId) {
    _specs.remove(operationId);
    _pendingDestructiveEntries.remove(operationId);
  }
}

/// Concrete recovery-plan factory used by application operation planners.
///
/// It owns reference encoding and registers the private bundle specification;
/// callers receive only ordinary typed operation steps.
final class OperationRecoveryPlanFactory
    implements OperationRecoveryPlanFactoryPort {
  OperationRecoveryPlanFactory({
    required OperationRecoverySpecRegistry registry,
  }) : _registry = registry;

  final OperationRecoverySpecRegistry _registry;

  @override
  List<PreparationOperationStep> createDestructiveEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
  }) {
    _requireAdjacentRevision(
      expectedRepositoryRevision,
      committedRepositoryRevision,
    );
    return <PreparationOperationStep>[
      PreparationOperationStep(
        stepId: 'recovery.prepare-evidence',
        recoveryReference: operationRecoveryReference(
          operationId,
          'destructive-evidence',
        ),
        kind: PreparationStepKind.recoveryEvidence,
      ),
    ];
  }

  @override
  OperationRecoveryPlanSteps createSqliteOnly({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required bool destructive,
  }) {
    if (committedRepositoryRevision != expectedRepositoryRevision.next()) {
      throw ArgumentError(
        'The committed Repository Revision must immediately follow expected.',
      );
    }
    if (destructive) {
      throw ArgumentError(
        'Destructive operations require a typed recovery intent.',
      );
    }
    final evidence = operationRecoveryReference(operationId, 'sqlite-evidence');
    final backup = operationRecoveryReference(operationId, 'sqlite-backup');
    final staging = operationRecoveryReference(operationId, 'sqlite-staging');
    final cleanup = operationRecoveryReference(operationId, 'sqlite-cleanup');
    _registry.register(
      OperationRecoveryBundleSpec(
        context: OperationRecoveryContext(
          operationId: operationId,
          expectedRepositoryRevision: expectedRepositoryRevision,
          committedRepositoryRevision: committedRepositoryRevision,
          destructive: destructive,
        ),
        entries: const [],
        bindings: [
          OperationRecoveryStepBinding(
            reference: evidence,
            action: OperationRecoveryAction.prepareEvidence,
          ),
          OperationRecoveryStepBinding(
            reference: backup,
            action: OperationRecoveryAction.backupRotation,
          ),
          OperationRecoveryStepBinding(
            reference: staging,
            action: OperationRecoveryAction.cleanupStaging,
          ),
          OperationRecoveryStepBinding(
            reference: cleanup,
            action: OperationRecoveryAction.retainRecoveryEvidence,
          ),
        ],
      ),
    );
    return OperationRecoveryPlanSteps(
      preparationSteps: [
        PreparationOperationStep(
          stepId: 'recovery.prepare-evidence',
          recoveryReference: evidence,
          kind: PreparationStepKind.recoveryEvidence,
        ),
      ],
      applyingSteps: const [],
      finalizationSteps: [
        FinalizationOperationStep(
          stepId: 'recovery.rotate-backup',
          recoveryReference: backup,
          kind: FinalizationStepKind.backupRotation,
        ),
        FinalizationOperationStep(
          stepId: 'recovery.cleanup-staging',
          recoveryReference: staging,
          kind: FinalizationStepKind.stagingCleanup,
        ),
        FinalizationOperationStep(
          stepId: 'recovery.retain-evidence-until-completed',
          recoveryReference: cleanup,
          kind: FinalizationStepKind.recoveryEvidenceCleanup,
        ),
      ],
    );
  }

  @override
  OperationRecoveryPlanSteps createDestructive({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required DestructiveOperationRecoveryIntent intent,
  }) {
    _requireAdjacentRevision(
      expectedRepositoryRevision,
      committedRepositoryRevision,
    );
    final envelopeSteps = createDestructiveEnvelope(
      operationId: operationId,
      expectedRepositoryRevision: expectedRepositoryRevision,
      committedRepositoryRevision: committedRepositoryRevision,
    );
    final entries = _registry.takeDestructiveEntries(operationId);
    final evidence = envelopeSteps.single.recoveryReference;
    final barrier = operationRecoveryReference(
      operationId,
      'destructive-barrier',
    );
    final prepare = operationRecoveryReference(
      operationId,
      'destructive-prepare',
    );
    final verify = operationRecoveryReference(
      operationId,
      'destructive-verify',
    );
    final backup = operationRecoveryReference(
      operationId,
      'destructive-backup',
    );
    final staging = operationRecoveryReference(
      operationId,
      'destructive-staging',
    );
    final cleanup = operationRecoveryReference(
      operationId,
      'destructive-cleanup',
    );
    final bindings = <OperationRecoveryStepBinding>[
      OperationRecoveryStepBinding(
        reference: evidence,
        action: OperationRecoveryAction.prepareEvidence,
      ),
      OperationRecoveryStepBinding(
        reference: barrier,
        action: OperationRecoveryAction.armDestructiveBarrier,
      ),
      OperationRecoveryStepBinding(
        reference: prepare,
        action: OperationRecoveryAction.prepareDestructiveResources,
      ),
    ];
    final applying = <ApplyingOperationStep>[];
    final entryVerification = <FinalizationOperationStep>[];
    final entryCleanup = <FinalizationOperationStep>[];
    for (var index = 0; index < entries.length; index += 1) {
      final number = (index + 1).toString().padLeft(4, '0');
      final entry = entries[index];
      final applyEntry = operationRecoveryReference(
        operationId,
        'destructive-entry-apply-$number',
      );
      final verifyEntry = operationRecoveryReference(
        operationId,
        'destructive-entry-verify-$number',
      );
      final cleanupEntry = operationRecoveryReference(
        operationId,
        'destructive-entry-cleanup-$number',
      );
      bindings.addAll(<OperationRecoveryStepBinding>[
        OperationRecoveryStepBinding(
          reference: applyEntry,
          action: OperationRecoveryAction.applyEntry,
          entryId: entry.entryId,
        ),
        OperationRecoveryStepBinding(
          reference: verifyEntry,
          action: OperationRecoveryAction.verifyEntry,
          entryId: entry.entryId,
        ),
        OperationRecoveryStepBinding(
          reference: cleanupEntry,
          action: OperationRecoveryAction.cleanupEntryResidue,
          entryId: entry.entryId,
        ),
      ]);
      applying.add(
        ApplyingOperationStep(
          stepId: 'recovery.apply-destructive-entry-$number',
          recoveryReference: applyEntry,
          kind: ApplyingStepKind.destructiveReplacement,
        ),
      );
      entryVerification.add(
        FinalizationOperationStep(
          stepId: 'recovery.verify-destructive-entry-$number',
          recoveryReference: verifyEntry,
          kind: FinalizationStepKind.materializationVerification,
        ),
      );
      entryCleanup.add(
        FinalizationOperationStep(
          stepId: 'recovery.cleanup-destructive-entry-$number',
          recoveryReference: cleanupEntry,
          kind: FinalizationStepKind.recoveryEvidenceCleanup,
        ),
      );
    }
    bindings.addAll(<OperationRecoveryStepBinding>[
      OperationRecoveryStepBinding(
        reference: verify,
        action: OperationRecoveryAction.verifyDestructiveResources,
      ),
      OperationRecoveryStepBinding(
        reference: backup,
        action: OperationRecoveryAction.completeDestructiveBackup,
      ),
      OperationRecoveryStepBinding(
        reference: staging,
        action: OperationRecoveryAction.cleanupStaging,
      ),
      OperationRecoveryStepBinding(
        reference: cleanup,
        action: OperationRecoveryAction.retainRecoveryEvidence,
      ),
    ]);
    _registry.register(
      OperationRecoveryBundleSpec(
        context: OperationRecoveryContext(
          operationId: operationId,
          expectedRepositoryRevision: expectedRepositoryRevision,
          committedRepositoryRevision: committedRepositoryRevision,
          destructive: true,
        ),
        entries: entries,
        destructiveIntent: intent,
        bindings: bindings,
      ),
    );
    return OperationRecoveryPlanSteps(
      preparationSteps: [
        ...envelopeSteps,
        PreparationOperationStep(
          stepId: 'recovery.arm-destructive-barrier',
          recoveryReference: barrier,
          kind: PreparationStepKind.destructiveBarrier,
        ),
        PreparationOperationStep(
          stepId: 'recovery.prepare-destructive-resources',
          recoveryReference: prepare,
          kind: PreparationStepKind.destructiveResources,
        ),
      ],
      applyingSteps: applying,
      finalizationSteps: [
        ...entryVerification,
        FinalizationOperationStep(
          stepId: 'recovery.verify-destructive-resources',
          recoveryReference: verify,
          kind: FinalizationStepKind.materializationVerification,
        ),
        ...entryCleanup,
        FinalizationOperationStep(
          stepId: 'recovery.complete-destructive-backup',
          recoveryReference: backup,
          kind: FinalizationStepKind.backupRotation,
        ),
        FinalizationOperationStep(
          stepId: 'recovery.cleanup-staging',
          recoveryReference: staging,
          kind: FinalizationStepKind.stagingCleanup,
        ),
        FinalizationOperationStep(
          stepId: 'recovery.retain-evidence-until-completed',
          recoveryReference: cleanup,
          kind: FinalizationStepKind.recoveryEvidenceCleanup,
        ),
      ],
    );
  }
}

void _requireAdjacentRevision(
  RepositoryRevision expected,
  RepositoryRevision committed,
) {
  if (committed != expected.next()) {
    throw ArgumentError(
      'The committed Repository Revision must immediately follow expected.',
    );
  }
}

RecoveryReference operationRecoveryReference(
  OperationId operationId,
  String token,
) {
  _requireSafeToken(token);
  return RecoveryReference('or1:${operationId.value}:$token');
}

({OperationId operationId, String token}) decodeOperationRecoveryReference(
  RecoveryReference reference,
) {
  final parts = reference.encoded.split(':');
  if (parts.length != 3 || parts.first != 'or1') {
    throw const OperationRecoveryException(
      OperationRecoveryFailureReason.invalidReference,
    );
  }
  try {
    final operationId = OperationId(parts[1]);
    _requireSafeToken(parts[2]);
    return (operationId: operationId, token: parts[2]);
  } on ArgumentError {
    throw const OperationRecoveryException(
      OperationRecoveryFailureReason.invalidReference,
    );
  }
}

final class OperationRecoverySnapshotFile {
  OperationRecoverySnapshotFile({
    required this.relativePath,
    required this.sha256Digest,
    required this.executable,
  }) {
    _requireSafeRelativePath(relativePath, 'relativePath');
    _requireSha256(sha256Digest, 'sha256Digest');
  }

  final String relativePath;
  final String sha256Digest;
  final bool executable;
}

/// A symbolic link contained in a directory snapshot.
///
/// The target is the verbatim link text, never resolved, so a rollback
/// recreates exactly the link the user had. Links carry no payload bytes.
final class OperationRecoverySnapshotLink {
  OperationRecoverySnapshotLink({
    required this.relativePath,
    required this.target,
  }) {
    _requireSafeRelativePath(relativePath, 'relativePath');
    _requireLinkTarget(target);
  }

  final String relativePath;
  final String target;
}

final class OperationRecoverySnapshot {
  OperationRecoverySnapshot.absent()
    : present = false,
      kind = null,
      linkTarget = null,
      executable = false,
      directories = const [],
      files = const [],
      links = const [];

  OperationRecoverySnapshot.file({
    required String sha256Digest,
    required this.executable,
  }) : present = true,
       kind = OperationRecoveryEntryKind.file,
       linkTarget = null,
       directories = const [],
       files = [
         OperationRecoverySnapshotFile(
           relativePath: 'content',
           sha256Digest: sha256Digest,
           executable: executable,
         ),
       ],
       links = const [];

  OperationRecoverySnapshot.directory({
    required List<String> directories,
    required List<OperationRecoverySnapshotFile> files,
    List<OperationRecoverySnapshotLink> links = const [],
  }) : present = true,
       kind = OperationRecoveryEntryKind.directory,
       linkTarget = null,
       executable = false,
       directories = List.unmodifiable(directories),
       files = List.unmodifiable(files),
       links = List.unmodifiable(links) {
    for (final directory in directories) {
      _requireSafeRelativePath(directory, 'directories');
    }
    final seen = <String>{};
    for (final entry in <String>[
      ...directories,
      ...files.map((file) => file.relativePath),
      ...links.map((link) => link.relativePath),
    ]) {
      if (!seen.add(entry)) {
        throw ArgumentError('Snapshot paths must be unique.');
      }
    }
    // A file or link has no children; a manifest that nests entries under
    // one would ask restoration to write through a link.
    for (final leaf in <String>[
      ...files.map((file) => file.relativePath),
      ...links.map((link) => link.relativePath),
    ]) {
      final prefix = '$leaf/';
      if (seen.any((entry) => entry.startsWith(prefix))) {
        throw ArgumentError('Snapshot entries cannot nest under a leaf.');
      }
    }
  }

  OperationRecoverySnapshot.symbolicLink(String target)
    : present = true,
      kind = OperationRecoveryEntryKind.symbolicLink,
      linkTarget = _requireLinkTarget(target),
      executable = false,
      directories = const [],
      files = const [],
      links = const [];

  final bool present;
  final OperationRecoveryEntryKind? kind;
  final String? linkTarget;
  final bool executable;
  final List<String> directories;
  final List<OperationRecoverySnapshotFile> files;

  /// Contained symbolic links of a directory snapshot; empty otherwise.
  final List<OperationRecoverySnapshotLink> links;
}

final class OperationRecoveryEntryManifest {
  OperationRecoveryEntryManifest({
    required this.entryId,
    required this.targetPath,
    required this.displacedPath,
    required this.rollbackResiduePath,
    required this.rollForwardResiduePath,
    required this.makeReadOnly,
    required this.requirePlainDirectory,
    required this.before,
    required this.intended,
  }) {
    _requireSafeSegment(entryId, 'entryId');
    _requireAbsolutePath(targetPath, 'targetPath');
    for (final candidate in [
      displacedPath,
      rollbackResiduePath,
      rollForwardResiduePath,
    ]) {
      _requireAbsolutePath(candidate, 'residuePath');
      if (!path.equals(path.dirname(candidate), path.dirname(targetPath)) ||
          path.equals(candidate, targetPath)) {
        throw ArgumentError('Recovery residues must be target siblings.');
      }
    }
  }

  final String entryId;
  final String targetPath;
  final String displacedPath;
  final String rollbackResiduePath;
  final String rollForwardResiduePath;
  final bool makeReadOnly;
  final bool requirePlainDirectory;
  final OperationRecoverySnapshot before;
  final OperationRecoverySnapshot intended;
}

final class OperationRecoveryBundleManifest {
  OperationRecoveryBundleManifest({
    required this.context,
    required List<OperationRecoveryEntryManifest> entries,
    required List<OperationRecoveryStepBinding> bindings,
    List<OperationRecoveryDraftCleanupManifest> draftCleanups = const [],
    this.destructiveIntent,
  }) : entries = List.unmodifiable(entries),
       bindings = List.unmodifiable(bindings),
       draftCleanups = List.unmodifiable(draftCleanups) {
    if (context.destructive != (destructiveIntent != null)) {
      throw ArgumentError(
        'Destructive context and recovery intent must coexist.',
      );
    }
    final entryIds = entries.map((entry) => entry.entryId).toSet();
    final cleanupIds = draftCleanups
        .map((cleanup) => cleanup.cleanupId)
        .toSet();
    final references = <String>{};
    if (entryIds.length != entries.length) {
      throw ArgumentError('Recovery entries contain duplicate IDs.');
    }
    if (cleanupIds.length != draftCleanups.length ||
        entryIds.intersection(cleanupIds).isNotEmpty) {
      throw ArgumentError('Recovery Draft cleanup IDs must be unique.');
    }
    for (final binding in bindings) {
      if (decodeOperationRecoveryReference(binding.reference).operationId !=
          context.operationId) {
        throw ArgumentError('Recovery binding belongs to another operation.');
      }
      final expectedIds =
          binding.action == OperationRecoveryAction.finalizeDraftCleanup
          ? cleanupIds
          : entryIds;
      if (binding.entryId != null && !expectedIds.contains(binding.entryId)) {
        throw ArgumentError('Recovery binding refers to a missing entry.');
      }
      if (!references.add(binding.reference.encoded)) {
        throw ArgumentError('Recovery bindings contain duplicate references.');
      }
    }
  }

  final OperationRecoveryContext context;
  final List<OperationRecoveryEntryManifest> entries;
  final List<OperationRecoveryStepBinding> bindings;
  final List<OperationRecoveryDraftCleanupManifest> draftCleanups;
  final DestructiveOperationRecoveryIntent? destructiveIntent;

  OperationRecoveryStepBinding binding(RecoveryReference reference) {
    final matches = bindings.where((binding) => binding.reference == reference);
    if (matches.length != 1) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.invalidReference,
      );
    }
    return matches.single;
  }

  OperationRecoveryEntryManifest entry(String entryId) => entries.singleWhere(
    (entry) => entry.entryId == entryId,
    orElse: () => throw const OperationRecoveryException(
      OperationRecoveryFailureReason.bundleCorrupt,
    ),
  );

  OperationRecoveryDraftCleanupManifest draftCleanup(String cleanupId) =>
      draftCleanups.singleWhere(
        (cleanup) => cleanup.cleanupId == cleanupId,
        orElse: () => throw const OperationRecoveryException(
          OperationRecoveryFailureReason.bundleCorrupt,
        ),
      );
}

final class OperationRecoveryDraftCleanupManifest {
  OperationRecoveryDraftCleanupManifest({
    required this.cleanupId,
    required this.managedSkillId,
    required this.expectedBaseObjectId,
    required this.targetPath,
    required this.quarantinePath,
    required this.capturedFingerprint,
  }) {
    _requireSafeSegment(cleanupId, 'cleanupId');
    _requireAbsolutePath(targetPath, 'targetPath');
    _requireAbsolutePath(quarantinePath, 'quarantinePath');
    if (!path.equals(path.dirname(targetPath), path.dirname(quarantinePath)) ||
        path.equals(targetPath, quarantinePath)) {
      throw ArgumentError('Draft cleanup quarantine must be a target sibling.');
    }
  }

  final String cleanupId;
  final ManagedSkillId managedSkillId;
  final RevisionObjectId expectedBaseObjectId;
  final String targetPath;
  final String quarantinePath;
  final DraftFingerprint capturedFingerprint;
}

enum OperationRecoveryDraftCleanupDecision { delete, preserve }

final class OperationRecoveryDraftCleanupDecisionRecord {
  const OperationRecoveryDraftCleanupDecisionRecord({
    required this.operationId,
    required this.cleanupId,
    required this.decision,
  });

  final OperationId operationId;
  final String cleanupId;
  final OperationRecoveryDraftCleanupDecision decision;
}

final class OperationRecoveryBundleCodec {
  const OperationRecoveryBundleCodec();

  Map<String, Object?> manifestValue(
    OperationRecoveryBundleManifest manifest,
  ) => Map<String, Object?>.unmodifiable(_manifestJson(manifest));

  Uint8List encodeManifest(OperationRecoveryBundleManifest manifest) =>
      Uint8List.fromList(canonicalJson.encode(_manifestJson(manifest)));

  Uint8List createCompletionFence(List<int> manifestBytes) =>
      Uint8List.fromList(
        canonicalJson.encode({
          'schema': operationRecoveryBundleSchemaVersion,
          'manifestSha256': sha256.convert(manifestBytes).toString(),
        }),
      );

  Uint8List encodeDraftCleanupDecision(
    OperationRecoveryDraftCleanupDecisionRecord record,
  ) => Uint8List.fromList(
    canonicalJson.encode({
      'schema': operationRecoveryBundleSchemaVersion,
      'operationId': record.operationId.value,
      'cleanupId': record.cleanupId,
      'decision': record.decision.name,
    }),
  );

  OperationRecoveryDraftCleanupDecisionRecord decodeDraftCleanupDecision(
    List<int> bytes,
  ) {
    final map = _decodeMap(bytes);
    // Decision records hold only ASCII identifiers, so schema 2 and 3 records
    // read identically; a pending decision must survive an upgrade.
    if (!_readableSchemaVersions.contains(map['schema'])) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.unsupportedSchema,
      );
    }
    try {
      return OperationRecoveryDraftCleanupDecisionRecord(
        operationId: OperationId(_string(map, 'operationId')),
        cleanupId: _string(map, 'cleanupId'),
        decision: _enumByName(
          OperationRecoveryDraftCleanupDecision.values,
          _string(map, 'decision'),
        ),
      );
    } on Object {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.bundleCorrupt,
      );
    }
  }

  OperationRecoveryBundleManifest verifyAndDecode({
    required List<int> manifestBytes,
    required List<int> completionFenceBytes,
  }) {
    final fence = _decodeMap(completionFenceBytes);
    final fenceSchema = fence['schema'];
    if (!_readableSchemaVersions.contains(fenceSchema)) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.unsupportedSchema,
      );
    }
    final expectedDigest = fence['manifestSha256'];
    if (expectedDigest is! String ||
        !_digestEquals(
          expectedDigest,
          sha256.convert(manifestBytes).toString(),
        )) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.checksumMismatch,
      );
    }
    final decoded = _decodeManifestWithSchema(manifestBytes);
    // The fence and the manifest are written as a pair; a schema mismatch
    // between them is corruption rather than a readable older bundle.
    if (decoded.schema != fenceSchema) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.unsupportedSchema,
      );
    }
    return decoded.manifest;
  }

  OperationRecoveryBundleManifest decodeManifest(List<int> bytes) =>
      _decodeManifestWithSchema(bytes).manifest;

  ({OperationRecoveryBundleManifest manifest, int schema})
  _decodeManifestWithSchema(List<int> bytes) {
    final armored = _decodeMap(bytes);
    final schema = armored['schema'];
    if (schema is! int || !_readableSchemaVersions.contains(schema)) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.unsupportedSchema,
      );
    }
    final legacy = schema == _legacyOperationRecoveryBundleSchemaVersion;
    try {
      final map = legacy ? armored : _asMap(_disarmStrings(armored));
      final operationId = OperationId(_string(map, 'operationId'));
      final context = OperationRecoveryContext(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(
          _integer(map, 'expectedRepositoryRevision'),
        ),
        committedRepositoryRevision: RepositoryRevision(
          _integer(map, 'committedRepositoryRevision'),
        ),
        destructive: _boolean(map, 'destructive'),
      );
      if (context.committedRepositoryRevision !=
          context.expectedRepositoryRevision.next()) {
        throw const FormatException();
      }
      final entries = _list(
        map,
        'entries',
      ).map((value) => _decodeEntry(_asMap(value), legacy: legacy)).toList();
      final bindings = _list(map, 'bindings').map((value) {
        final binding = _asMap(value);
        return OperationRecoveryStepBinding(
          reference: RecoveryReference(_string(binding, 'reference')),
          action: _enumByName(
            OperationRecoveryAction.values,
            _string(binding, 'action'),
          ),
          entryId: _optionalString(binding, 'entryId'),
        );
      }).toList();
      final draftCleanups = _listOrEmpty(
        map,
        'draftCleanups',
      ).map((value) => _decodeDraftCleanup(_asMap(value))).toList();
      final manifest = OperationRecoveryBundleManifest(
        context: context,
        entries: entries,
        bindings: bindings,
        draftCleanups: draftCleanups,
        destructiveIntent: _decodeDestructiveIntent(map['destructiveIntent']),
      );
      return (manifest: manifest, schema: schema);
    } on OperationRecoveryException {
      rethrow;
    } on Object {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.bundleCorrupt,
      );
    }
  }
}

/// The schema-3 JSON value: every string value is percent-encoded so the
/// canonical encoder's NFC rewrite cannot change a path; keys stay literal.
Map<String, Object?> _manifestJson(OperationRecoveryBundleManifest manifest) =>
    _armorStrings(_rawManifestJson(manifest))! as Map<String, Object?>;

Object? _armorStrings(Object? value) => switch (value) {
  final String string => Uri.encodeComponent(string),
  final Map<String, Object?> map => <String, Object?>{
    for (final entry in map.entries) entry.key: _armorStrings(entry.value),
  },
  final List<Object?> list => list.map(_armorStrings).toList(),
  _ => value,
};

Object? _disarmStrings(Object? value) => switch (value) {
  final String string => _disarmString(string),
  final Map<String, Object?> map => <String, Object?>{
    for (final entry in map.entries) entry.key: _disarmStrings(entry.value),
  },
  final List<Object?> list => list.map(_disarmStrings).toList(),
  _ => value,
};

String _disarmString(String armored) {
  final decoded = Uri.decodeComponent(armored);
  // Exactly one armored spelling is valid per string, so a hand-edited
  // manifest cannot smuggle an alternate encoding past the fence.
  if (Uri.encodeComponent(decoded) != armored) {
    throw const FormatException();
  }
  return decoded;
}

Map<String, Object?> _rawManifestJson(
  OperationRecoveryBundleManifest manifest,
) => {
  'schema': operationRecoveryBundleSchemaVersion,
  'operationId': manifest.context.operationId.value,
  'expectedRepositoryRevision':
      manifest.context.expectedRepositoryRevision.value,
  'committedRepositoryRevision':
      manifest.context.committedRepositoryRevision.value,
  'destructive': manifest.context.destructive,
  'destructiveIntent': _destructiveIntentJson(manifest.destructiveIntent),
  'entries': manifest.entries.map(_entryJson).toList(),
  'draftCleanups': manifest.draftCleanups.map(_draftCleanupJson).toList(),
  'bindings': manifest.bindings
      .map(
        (binding) => {
          'reference': binding.reference.encoded,
          'action': binding.action.name,
          'entryId': binding.entryId,
        },
      )
      .toList(),
};

Map<String, Object?> _draftCleanupJson(
  OperationRecoveryDraftCleanupManifest cleanup,
) => {
  'cleanupId': cleanup.cleanupId,
  'managedSkillId': cleanup.managedSkillId.value,
  'expectedBaseObjectId': cleanup.expectedBaseObjectId.value,
  'targetPath': cleanup.targetPath,
  'quarantinePath': cleanup.quarantinePath,
  'capturedFingerprint': cleanup.capturedFingerprint.entries
      .map(_draftEvidenceJson)
      .toList(),
};

Map<String, Object?> _draftEvidenceJson(DraftEntryEvidence evidence) => {
  'relativePath': evidence.relativePath,
  'kind': evidence.kind.name,
  'entryVolumeId': evidence.entryIdentity.volumeId,
  'entryFileId': evidence.entryIdentity.fileId,
  'resolvedVolumeId': evidence.resolvedIdentity.volumeId,
  'resolvedFileId': evidence.resolvedIdentity.fileId,
  'modifiedAtMicrosecondsUtc': evidence.modifiedAtMicrosecondsUtc,
  'byteSize': evidence.byteSize,
  'contentHash': evidence.contentHash,
  'isExecutable': evidence.isExecutable,
  'symbolicLinkTarget': evidence.symbolicLinkTarget,
};

OperationRecoveryDraftCleanupManifest _decodeDraftCleanup(
  Map<String, Object?> map,
) => OperationRecoveryDraftCleanupManifest(
  cleanupId: _string(map, 'cleanupId'),
  managedSkillId: ManagedSkillId(_string(map, 'managedSkillId')),
  expectedBaseObjectId: RevisionObjectId(_string(map, 'expectedBaseObjectId')),
  targetPath: _string(map, 'targetPath'),
  quarantinePath: _string(map, 'quarantinePath'),
  capturedFingerprint: DraftFingerprint(
    _list(
      map,
      'capturedFingerprint',
    ).map((value) => _decodeDraftEvidence(_asMap(value))).toList(),
  ),
);

DraftEntryEvidence _decodeDraftEvidence(Map<String, Object?> map) =>
    DraftEntryEvidence(
      relativePath: _possiblyEmptyString(map, 'relativePath'),
      kind: _enumByName(DraftFilesystemEntryKind.values, _string(map, 'kind')),
      entryIdentity: DraftPhysicalIdentity(
        volumeId: _string(map, 'entryVolumeId'),
        fileId: _string(map, 'entryFileId'),
      ),
      resolvedIdentity: DraftPhysicalIdentity(
        volumeId: _string(map, 'resolvedVolumeId'),
        fileId: _string(map, 'resolvedFileId'),
      ),
      modifiedAtMicrosecondsUtc: _integer(map, 'modifiedAtMicrosecondsUtc'),
      byteSize: _optionalInteger(map, 'byteSize'),
      contentHash: _optionalString(map, 'contentHash'),
      isExecutable: _boolean(map, 'isExecutable'),
      symbolicLinkTarget: _optionalString(map, 'symbolicLinkTarget'),
    );

Map<String, Object?>? _destructiveIntentJson(
  DestructiveOperationRecoveryIntent? intent,
) => switch (intent) {
  null => null,
  SourceReplacementRecoveryIntent() => {
    'kind': 'sourceReplacement',
    'skills': intent.skills.map(_destructiveSkillJson).toList(),
    'intendedSourceLineage': intent.intendedSourceLineage.encoded,
    'intendedSlotKey': intent.intendedSlotKey,
    'intendedObjectId': intent.intendedObjectId.value,
    'intendedContentHash': intent.intendedContentHash,
    'intendedObjectFormat': intent.intendedObjectFormat.name,
  },
  RemovalRecoveryIntent() => {
    'kind': 'removal',
    'skills': intent.skills.map(_destructiveSkillJson).toList(),
  },
};

Map<String, Object?> _destructiveSkillJson(
  DestructiveSkillRecoveryIntent skill,
) => {
  'managedSkillId': skill.managedSkillId.value,
  'slotKey': skill.slotKey,
  'sourceLineages': skill.sourceLineages
      .map((lineage) => {'sourceLineage': lineage.sourceLineage.encoded})
      .toList(),
  'activationIds': skill.activationIds,
  'hasDraft': skill.hasDraft,
  'hasUpdateCandidateSession': skill.hasUpdateCandidateSession,
};

DestructiveOperationRecoveryIntent? _decodeDestructiveIntent(Object? value) {
  if (value == null) return null;
  final map = _asMap(value);
  final skills = _list(
    map,
    'skills',
  ).map((item) => _decodeDestructiveSkill(_asMap(item))).toList();
  return switch (_string(map, 'kind')) {
    'sourceReplacement' => SourceReplacementRecoveryIntent(
      skill: skills.single,
      intendedSourceLineage: SourceLineageReference(
        _string(map, 'intendedSourceLineage'),
      ),
      intendedSlotKey: _string(map, 'intendedSlotKey'),
      intendedObjectId: RevisionObjectId(_string(map, 'intendedObjectId')),
      intendedContentHash: _string(map, 'intendedContentHash'),
      intendedObjectFormat: _enumByName(
        WorkspaceObjectFormat.values,
        _string(map, 'intendedObjectFormat'),
      ),
    ),
    'removal' => RemovalRecoveryIntent(skills: skills),
    _ => throw const FormatException(),
  };
}

DestructiveSkillRecoveryIntent _decodeDestructiveSkill(
  Map<String, Object?> map,
) => DestructiveSkillRecoveryIntent(
  managedSkillId: ManagedSkillId(_string(map, 'managedSkillId')),
  slotKey: _string(map, 'slotKey'),
  sourceLineages: _list(map, 'sourceLineages').map((value) {
    final lineage = _asMap(value);
    return RecoverySourceLineageIntent(
      sourceLineage: SourceLineageReference(_string(lineage, 'sourceLineage')),
    );
  }).toList(),
  activationIds: _list(map, 'activationIds').map(_requiredString).toList(),
  hasDraft: _boolean(map, 'hasDraft'),
  hasUpdateCandidateSession: _boolean(map, 'hasUpdateCandidateSession'),
);

Map<String, Object?> _entryJson(OperationRecoveryEntryManifest entry) => {
  'entryId': entry.entryId,
  'targetPath': entry.targetPath,
  'displacedPath': entry.displacedPath,
  'rollbackResiduePath': entry.rollbackResiduePath,
  'rollForwardResiduePath': entry.rollForwardResiduePath,
  'makeReadOnly': entry.makeReadOnly,
  'requirePlainDirectory': entry.requirePlainDirectory,
  'before': _snapshotJson(entry.before),
  'intended': _snapshotJson(entry.intended),
};

Map<String, Object?> _snapshotJson(OperationRecoverySnapshot snapshot) => {
  'present': snapshot.present,
  'kind': snapshot.kind?.name,
  'linkTarget': snapshot.linkTarget,
  'executable': snapshot.executable,
  'directories': snapshot.directories,
  'files': snapshot.files
      .map(
        (file) => {
          'relativePath': file.relativePath,
          'sha256': file.sha256Digest,
          'executable': file.executable,
        },
      )
      .toList(),
  'links': snapshot.links
      .map((link) => {'relativePath': link.relativePath, 'target': link.target})
      .toList(),
};

OperationRecoveryEntryManifest _decodeEntry(
  Map<String, Object?> map, {
  required bool legacy,
}) => OperationRecoveryEntryManifest(
  entryId: _string(map, 'entryId'),
  targetPath: _string(map, 'targetPath'),
  displacedPath: _string(map, 'displacedPath'),
  rollbackResiduePath: _string(map, 'rollbackResiduePath'),
  rollForwardResiduePath: _string(map, 'rollForwardResiduePath'),
  makeReadOnly: _boolean(map, 'makeReadOnly'),
  requirePlainDirectory: _boolean(map, 'requirePlainDirectory'),
  before: _decodeSnapshot(_map(map, 'before'), legacy: legacy),
  intended: _decodeSnapshot(_map(map, 'intended'), legacy: legacy),
);

OperationRecoverySnapshot _decodeSnapshot(
  Map<String, Object?> map, {
  required bool legacy,
}) {
  // Schema 2 never wrote links; schema 3 always writes the key, even empty.
  if (legacy && map.containsKey('links')) throw const FormatException();
  final links = legacy
      ? const <OperationRecoverySnapshotLink>[]
      : _list(map, 'links').map((value) {
          final link = _asMap(value);
          return OperationRecoverySnapshotLink(
            relativePath: _string(link, 'relativePath'),
            target: _string(link, 'target'),
          );
        }).toList();
  if (!_boolean(map, 'present')) {
    if (links.isNotEmpty) throw const FormatException();
    return OperationRecoverySnapshot.absent();
  }
  final kind = _enumByName(
    OperationRecoveryEntryKind.values,
    _string(map, 'kind'),
  );
  if (kind != OperationRecoveryEntryKind.directory && links.isNotEmpty) {
    throw const FormatException();
  }
  return switch (kind) {
    OperationRecoveryEntryKind.file => OperationRecoverySnapshot.file(
      sha256Digest: _string(_asMap(_list(map, 'files').single), 'sha256'),
      executable: _boolean(map, 'executable'),
    ),
    OperationRecoveryEntryKind.directory => OperationRecoverySnapshot.directory(
      directories: _list(
        map,
        'directories',
      ).map((value) => _requiredString(value)).toList(),
      files: _list(map, 'files').map((value) {
        final file = _asMap(value);
        return OperationRecoverySnapshotFile(
          relativePath: _string(file, 'relativePath'),
          sha256Digest: _string(file, 'sha256'),
          executable: _boolean(file, 'executable'),
        );
      }).toList(),
      links: links,
    ),
    OperationRecoveryEntryKind.symbolicLink =>
      OperationRecoverySnapshot.symbolicLink(_string(map, 'linkTarget')),
  };
}

Map<String, Object?> _decodeMap(List<int> bytes) {
  try {
    // canonical_json 1.1.3's decoder rejects the integer zero even though its
    // encoder emits it. Decode with dart:convert, then require a byte-for-byte
    // canonical re-encoding so non-canonical or ambiguous JSON still fails.
    final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    final map = _asMap(value);
    if (!_sameBytes(bytes, canonicalJson.encode(map))) {
      throw const FormatException();
    }
    return map;
  } on OperationRecoveryException {
    rethrow;
  } on Object {
    throw const OperationRecoveryException(
      OperationRecoveryFailureReason.bundleCorrupt,
    );
  }
}

Map<String, Object?> _map(Map<String, Object?> source, String key) =>
    _asMap(source[key]);

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map<String, Object?>) throw const FormatException();
  return value;
}

List<Object?> _list(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! List<Object?>) throw const FormatException();
  return value;
}

List<Object?> _listOrEmpty(Map<String, Object?> source, String key) {
  if (!source.containsKey(key)) return const <Object?>[];
  return _list(source, key);
}

String _string(Map<String, Object?> source, String key) =>
    _requiredString(source[key]);

String _possiblyEmptyString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! String) throw const FormatException();
  return value;
}

String _requiredString(Object? value) {
  if (value is! String || value.trim().isEmpty) throw const FormatException();
  return value;
}

String? _optionalString(Map<String, Object?> source, String key) {
  final value = source[key];
  return value == null ? null : _requiredString(value);
}

int _integer(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! int) throw const FormatException();
  return value;
}

int? _optionalInteger(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) return null;
  if (value is! int) throw const FormatException();
  return value;
}

bool _boolean(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! bool) throw const FormatException();
  return value;
}

T _enumByName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw const FormatException();
}

void _requireSafeSegment(String value, String name) {
  if (value.trim().isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains(r'\') ||
      value.contains('\u0000')) {
    throw ArgumentError.value(value, name, 'must be one safe path segment');
  }
}

void _requireSafeToken(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'token', 'must be an opaque safe token');
  }
}

void _requireAbsolutePath(String value, String name) {
  if (!path.isAbsolute(value) || path.isRootRelative(value)) {
    throw ArgumentError.value(value, name, 'must be fully absolute');
  }
  _requireLosslessText(value, name);
}

void _requireSafeRelativePath(String value, String name) {
  final normalized = path.posix.normalize(value.replaceAll(r'\', '/'));
  if (normalized.isEmpty ||
      normalized == '.' ||
      normalized == '..' ||
      path.posix.isAbsolute(normalized) ||
      normalized.startsWith('../') ||
      normalized != value.replaceAll(r'\', '/')) {
    throw ArgumentError.value(value, name, 'must be a safe relative path');
  }
  _requireLosslessText(value, name);
}

String _requireLinkTarget(String value) {
  if (value.isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(value, 'target', 'must be a valid link target');
  }
  _requireLosslessText(value, 'target');
  return value;
}

/// Percent-encoding goes through UTF-8, which replaces an unpaired surrogate
/// with U+FFFD. Such a name could not be restored byte-for-byte, so it is
/// rejected before it reaches a manifest.
void _requireLosslessText(String value, String name) {
  for (var index = 0; index < value.length; index += 1) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      final next = index + 1 < value.length ? value.codeUnitAt(index + 1) : 0;
      if (next < 0xDC00 || next > 0xDFFF) {
        throw ArgumentError.value(
          value,
          name,
          'contains an unpaired surrogate',
        );
      }
      index += 1;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw ArgumentError.value(value, name, 'contains an unpaired surrogate');
    }
  }
}

void _requireSha256(String value, String name) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a SHA-256 digest');
  }
}

bool _digestEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

String operationRecoveryManifestPath(
  OperationRecoveryLayoutPort layout,
  OperationId id,
) => path.join(layout.operationRecoveryPath(id), 'manifest.json');

String operationRecoveryFencePath(
  OperationRecoveryLayoutPort layout,
  OperationId id,
) => path.join(layout.operationRecoveryPath(id), 'COMPLETE');

String operationRecoveryPayloadPath({
  required String bundleRoot,
  required String entryId,
  required bool intended,
}) => path.join(
  bundleRoot,
  'payloads',
  entryId,
  intended ? 'intended' : 'before',
);

String sha256Bytes(List<int> bytes) => sha256.convert(bytes).toString();

List<int> utf8Bytes(String value) => utf8.encode(value);
