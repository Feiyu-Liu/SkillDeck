import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../application/operations/destructive_recovery_intent.dart';
import '../../application/operations/operation_models.dart';
import '../../application/ports/operation_ports.dart';
import '../../application/ports/revision_manifest_worker_ports.dart';
import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/draft_snapshot.dart';
import '../../application/ports/draft_snapshot_ports.dart';
import '../filesystem/filesystem_draft_snapshot.dart';
import '../filesystem/durable_workspace_filesystem.dart';
import 'operation_recovery_bundle.dart';

abstract interface class OperationRecoveryBackupMaintenancePort {
  /// Idempotently establishes the backup generation required after commit.
  Future<void> rotate(OperationRecoveryContext context);

  Future<void> armDestructiveBarrier(OperationRecoveryContext context);

  Future<void> restoreSteadyAfterProvenRollback(
    OperationRecoveryContext context,
  );

  Future<void> completeCommittedDestruction(OperationRecoveryContext context);
}

/// Resolves path-free destructive intent inside the recovery boundary.
///
/// Implementations own Store leases, candidate resources, materialization
/// paths and private rollback evidence. Every method is idempotent.
abstract interface class OperationRecoveryDestructiveMaintenancePort {
  Future<void> prepare(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
    CancellationToken cancellationToken,
  );

  Future<void> verify(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
  );

  Future<void> rollback(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
  );

  Future<void> rollForward(
    OperationRecoveryContext context,
    DestructiveOperationRecoveryIntent intent,
  );
}

enum DraftCleanupFinalizationEvent { deleteDecisionPersisted }

typedef DraftCleanupFinalizationObserver =
    FutureOr<void> Function(
      DraftCleanupFinalizationEvent event,
      String targetPath,
      String quarantinePath,
    );

/// Filesystem-owned operation recovery with one immutable bundle per operation.
///
/// The plan and SQLite retain only opaque references. Target paths, candidate
/// bytes, original bytes, link targets, executable intent and deterministic
/// replacement residues live exclusively inside the verified bundle.
final class FilesystemOperationRecovery
    implements OperationRecoveryPort, PreparedOperationRecoveryPort {
  FilesystemOperationRecovery({
    required OperationRecoveryLayoutPort layout,
    required DurableWorkspaceFilesystem filesystem,
    required OperationRecoverySpecRegistry registry,
    OperationRecoveryBundleCodec codec = const OperationRecoveryBundleCodec(),
    OperationRecoveryBackupMaintenancePort? backupMaintenance,
    OperationRecoveryDestructiveMaintenancePort? destructiveMaintenance,
    DurablePathMutationObserver? onMutationBarrier,
    DraftSnapshotFilesystemPort? draftSnapshots,
    DraftCleanupFinalizationObserver? onDraftCleanupFinalization,
    RevisionManifestWorkerPort? manifestWorker,
    bool? capturePosixExecutableIntent,
  }) : _layout = layout,
       _filesystem = filesystem,
       _registry = registry,
       _codec = codec,
       _backupMaintenance = backupMaintenance,
       _destructiveMaintenance = destructiveMaintenance,
       _onMutationBarrier = onMutationBarrier,
       _draftSnapshots =
           draftSnapshots ??
           FilesystemDraftSnapshotAdapter(filesystem: filesystem),
       _onDraftCleanupFinalization = onDraftCleanupFinalization,
       _manifestWorker = manifestWorker,
       _capturePosixExecutableIntent =
           capturePosixExecutableIntent ?? !Platform.isWindows;

  final OperationRecoveryLayoutPort _layout;
  final DurableWorkspaceFilesystem _filesystem;
  final OperationRecoverySpecRegistry _registry;
  final OperationRecoveryBundleCodec _codec;
  final OperationRecoveryBackupMaintenancePort? _backupMaintenance;
  final OperationRecoveryDestructiveMaintenancePort? _destructiveMaintenance;
  final DurablePathMutationObserver? _onMutationBarrier;
  final DraftSnapshotFilesystemPort _draftSnapshots;
  final DraftCleanupFinalizationObserver? _onDraftCleanupFinalization;
  final RevisionManifestWorkerPort? _manifestWorker;
  final bool _capturePosixExecutableIntent;
  final Map<OperationId, OperationRecoveryBundleManifest> _verifiedBundles =
      <OperationId, OperationRecoveryBundleManifest>{};

  @override
  Future<void> prepareStep(
    PreparationOperationStep step,
    CancellationToken cancellationToken,
  ) async {
    _throwIfCancelled(cancellationToken);
    final decoded = decodeOperationRecoveryReference(step.recoveryReference);
    final manifest = await _loadOrPrepare(
      decoded.operationId,
      cancellationToken,
    );
    final binding = manifest.binding(step.recoveryReference);
    switch (binding.action) {
      case OperationRecoveryAction.prepareEvidence:
        break;
      case OperationRecoveryAction.armDestructiveBarrier:
        await _requireBackupMaintenance().armDestructiveBarrier(
          manifest.context,
        );
      case OperationRecoveryAction.prepareDestructiveResources:
        await _requireDestructiveMaintenance().prepare(
          manifest.context,
          _requireDestructiveIntent(manifest),
          cancellationToken,
        );
      case OperationRecoveryAction.applyEntry:
      case OperationRecoveryAction.verifyEntry:
      case OperationRecoveryAction.cleanupEntryResidue:
      case OperationRecoveryAction.backupRotation:
      case OperationRecoveryAction.verifyDestructiveResources:
      case OperationRecoveryAction.completeDestructiveBackup:
      case OperationRecoveryAction.cleanupStaging:
      case OperationRecoveryAction.retainRecoveryEvidence:
      case OperationRecoveryAction.finalizeDraftCleanup:
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.unsupportedStepAction,
        );
    }
    _throwIfCancelled(cancellationToken);
  }

  @override
  Future<void> applyStep(
    ApplyingOperationStep step,
    CancellationToken cancellationToken,
  ) async {
    _throwIfCancelled(cancellationToken);
    final decoded = decodeOperationRecoveryReference(step.recoveryReference);
    final manifest = await _loadRequired(decoded.operationId);
    final binding = manifest.binding(step.recoveryReference);
    switch (binding.action) {
      case OperationRecoveryAction.applyEntry:
        final entry = manifest.entry(binding.entryId!);
        await _establish(
          manifest,
          entry,
          desired: entry.intended,
          alternate: entry.before,
          residuePath: entry.displacedPath,
        );
      case OperationRecoveryAction.prepareEvidence:
      case OperationRecoveryAction.verifyEntry:
      case OperationRecoveryAction.cleanupEntryResidue:
      case OperationRecoveryAction.backupRotation:
      case OperationRecoveryAction.armDestructiveBarrier:
      case OperationRecoveryAction.prepareDestructiveResources:
      case OperationRecoveryAction.verifyDestructiveResources:
      case OperationRecoveryAction.completeDestructiveBackup:
      case OperationRecoveryAction.cleanupStaging:
      case OperationRecoveryAction.retainRecoveryEvidence:
      case OperationRecoveryAction.finalizeDraftCleanup:
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.unsupportedStepAction,
        );
    }
    _throwIfCancelled(cancellationToken);
  }

  @override
  Future<OperationFinalizationEffect?> finalizeStep(
    FinalizationOperationStep step,
  ) async {
    final decoded = decodeOperationRecoveryReference(step.recoveryReference);
    final manifest = await _loadRequired(decoded.operationId);
    final binding = manifest.binding(step.recoveryReference);
    switch (binding.action) {
      case OperationRecoveryAction.verifyEntry:
        final entry = manifest.entry(binding.entryId!);
        if (!await _matches(entry.targetPath, entry.intended)) {
          throw const OperationRecoveryException(
            OperationRecoveryFailureReason.entryTypeChanged,
          );
        }
        return null;
      case OperationRecoveryAction.cleanupEntryResidue:
        await _cleanupEntryResidues(manifest.entry(binding.entryId!));
        return null;
      case OperationRecoveryAction.backupRotation:
        await _requireBackupMaintenance().rotate(manifest.context);
        return null;
      case OperationRecoveryAction.verifyDestructiveResources:
        await _requireDestructiveMaintenance().verify(
          manifest.context,
          _requireDestructiveIntent(manifest),
        );
        return null;
      case OperationRecoveryAction.completeDestructiveBackup:
        await _requireBackupMaintenance().completeCommittedDestruction(
          manifest.context,
        );
        return null;
      case OperationRecoveryAction.cleanupStaging:
        await _removeOwnedIfPresent(
          _layout.operationStagingPath(manifest.context.operationId),
          _layout.stagingRoot,
        );
        return null;
      case OperationRecoveryAction.retainRecoveryEvidence:
        // Evidence is removed only after SQLite marks the Journal Completed.
        return null;
      case OperationRecoveryAction.finalizeDraftCleanup:
        return _finalizeDraftCleanup(
          manifest,
          manifest.draftCleanup(binding.entryId!),
        );
      case OperationRecoveryAction.prepareEvidence:
      case OperationRecoveryAction.applyEntry:
      case OperationRecoveryAction.armDestructiveBarrier:
      case OperationRecoveryAction.prepareDestructiveResources:
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.unsupportedStepAction,
        );
    }
  }

  @override
  Future<void> rollback(
    OperationPlan plan, {
    required OperationJournalPhase observedPhase,
  }) async {
    if (observedPhase != OperationJournalPhase.prepared &&
        observedPhase != OperationJournalPhase.applying) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.operationMismatch,
      );
    }
    final manifest = await _loadOptional(plan.operationId);
    if (manifest == null) {
      if (observedPhase == OperationJournalPhase.applying) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.bundleMissing,
        );
      }
      await _removeOwnedIfPresent(
        _layout.operationStagingPath(plan.operationId),
        _layout.stagingRoot,
      );
      return;
    }
    _requirePlanMatches(manifest, plan);
    final destructiveIntent = manifest.destructiveIntent;
    for (final entry in manifest.entries.reversed) {
      await _establish(
        manifest,
        entry,
        desired: entry.before,
        alternate: entry.intended,
        residuePath: entry.rollbackResiduePath,
      );
    }
    if (destructiveIntent != null) {
      await _requireDestructiveMaintenance().rollback(
        manifest.context,
        destructiveIntent,
      );
    }
    for (final entry in manifest.entries.reversed) {
      await _cleanupEntryResidues(entry);
    }
    await _removeOwnedIfPresent(
      _layout.operationStagingPath(plan.operationId),
      _layout.stagingRoot,
    );
    if (destructiveIntent != null) {
      await _requireBackupMaintenance().restoreSteadyAfterProvenRollback(
        manifest.context,
      );
    }
  }

  @override
  Future<void> rollbackPreparedEnvelope(
    PreparedOperationEnvelope envelope, {
    required OperationJournalPhase observedPhase,
  }) async {
    if (observedPhase != OperationJournalPhase.prepared) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.operationMismatch,
      );
    }
    final references = _validatePreparedEnvelopeReferences(envelope);
    final manifest = await _loadOptional(envelope.operationId);
    if (manifest != null) {
      final bindings = _requirePreparedEnvelopeMatches(
        manifest,
        envelope,
        references,
      );
      if (bindings.any(
        (binding) =>
            binding.action ==
            OperationRecoveryAction.prepareDestructiveResources,
      )) {
        await _requireDestructiveMaintenance().rollback(
          manifest.context,
          _requireDestructiveIntent(manifest),
        );
      }
    }
    // Candidate construction is forbidden from publishing live workspace
    // artifacts. Its only generic filesystem ownership is the operation's
    // private staging subtree, addressed by the Journaled Operation ID.
    await _removeOwnedIfPresent(
      _layout.operationStagingPath(envelope.operationId),
      _layout.stagingRoot,
    );
  }

  @override
  Future<void> cleanupCompletedPreparedEnvelope(
    PreparedOperationEnvelope envelope,
  ) async {
    final references = _validatePreparedEnvelopeReferences(envelope);
    final manifest = await _loadOptional(envelope.operationId);
    if (manifest != null) {
      _requirePreparedEnvelopeMatches(manifest, envelope, references);
    }
    await _removeOwnedIfPresent(
      _layout.operationStagingPath(envelope.operationId),
      _layout.stagingRoot,
    );
    await _removeOwnedIfPresent(
      _layout.operationRecoveryPath(envelope.operationId),
      _layout.recoveryRoot,
    );
    _verifiedBundles.remove(envelope.operationId);
    _registry.forget(envelope.operationId);
  }

  @override
  Future<List<OperationFinalizationEffect>> rollForward(
    OperationPlan plan,
  ) async {
    final manifest = await _loadRequired(plan.operationId);
    _requirePlanMatches(manifest, plan);
    final destructiveIntent = manifest.destructiveIntent;
    if (destructiveIntent != null) {
      final maintenance = _requireDestructiveMaintenance();
      await maintenance.rollForward(manifest.context, destructiveIntent);
    }
    final effects = <OperationFinalizationEffect>[];
    for (final cleanup in manifest.draftCleanups) {
      final effect = await _finalizeDraftCleanup(manifest, cleanup);
      if (effect != null) effects.add(effect);
    }
    for (final entry in manifest.entries) {
      await _establish(
        manifest,
        entry,
        desired: entry.intended,
        alternate: entry.before,
        residuePath: entry.rollForwardResiduePath,
      );
    }
    if (destructiveIntent != null) {
      await _requireDestructiveMaintenance().verify(
        manifest.context,
        destructiveIntent,
      );
    }
    for (final entry in manifest.entries) {
      await _cleanupEntryResidues(entry);
    }
    if (manifest.bindings.any(
      (binding) => binding.action == OperationRecoveryAction.backupRotation,
    )) {
      final maintenance = _backupMaintenance;
      if (maintenance == null) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.unsupportedStepAction,
        );
      }
      await maintenance.rotate(manifest.context);
    }
    if (destructiveIntent != null) {
      await _requireBackupMaintenance().completeCommittedDestruction(
        manifest.context,
      );
    }
    await _removeOwnedIfPresent(
      _layout.operationStagingPath(plan.operationId),
      _layout.stagingRoot,
    );
    return effects;
  }

  @override
  Future<void> cleanupCompleted(OperationPlan plan) async {
    final manifest = await _loadOptional(plan.operationId);
    if (manifest == null) {
      await _removeOwnedIfPresent(
        _layout.operationStagingPath(plan.operationId),
        _layout.stagingRoot,
      );
      _verifiedBundles.remove(plan.operationId);
      _registry.forget(plan.operationId);
      return;
    }
    _requirePlanMatches(manifest, plan);
    for (final entry in manifest.entries) {
      await _cleanupEntryResidues(entry);
    }
    await _removeOwnedIfPresent(
      _layout.operationStagingPath(plan.operationId),
      _layout.stagingRoot,
    );
    await _removeOwnedIfPresent(
      _layout.operationRecoveryPath(plan.operationId),
      _layout.recoveryRoot,
    );
    _verifiedBundles.remove(plan.operationId);
    _registry.forget(plan.operationId);
  }

  Future<OperationRecoveryBundleManifest> _loadOrPrepare(
    OperationId operationId,
    CancellationToken cancellation,
  ) async {
    final existing = await _loadOptional(operationId);
    if (existing != null) return existing;
    final spec = _registry.lookup(operationId);
    if (spec == null) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.unregisteredPlan,
      );
    }
    return _prepareBundle(spec, cancellation);
  }

  Future<OperationRecoveryBundleManifest> _prepareBundle(
    OperationRecoveryBundleSpec spec,
    CancellationToken cancellation,
  ) async {
    final destination = _layout.operationRecoveryPath(spec.context.operationId);
    await _filesystem.ensureDirectory(_layout.recoveryRoot);
    final staging = await _filesystem.createSiblingStagingPath(
      destination,
      kind: DurableEntryKind.directory,
      purpose: 'recovery-bundle',
    );
    try {
      final entries = <OperationRecoveryEntryManifest>[];
      final resolvedTargets = <String>[];
      final resolvedTargetByEntryId = <String, String>{};
      for (final entry in spec.entries) {
        _throwIfCancelled(cancellation);
        final targetPath = await _filesystem.resolveMutationPath(
          entry.targetPath,
        );
        if (resolvedTargets.any(
          (existing) => path.equals(existing, targetPath),
        )) {
          throw const OperationRecoveryException(
            OperationRecoveryFailureReason.conflictingRecoveryEntry,
          );
        }
        resolvedTargets.add(targetPath);
        resolvedTargetByEntryId[entry.entryId] = targetPath;
        if (entry.verifyBeforeCapture case final verify?) {
          if (!await verify(targetPath)) {
            throw const ExternalOperationPreconditionChanged();
          }
        }
        final beforePayload = operationRecoveryPayloadPath(
          bundleRoot: staging.path,
          entryId: entry.entryId,
          intended: false,
        );
        final intendedPayload = operationRecoveryPayloadPath(
          bundleRoot: staging.path,
          entryId: entry.entryId,
          intended: true,
        );
        // The before image is whatever the user had, links included, so a
        // rollback restores it verbatim. Intended plain materializations keep
        // rejecting contained links.
        final before = await _captureSnapshot(
          targetPath,
          beforePayload,
          expectedKind: null,
          allowContainedLinks: true,
          cancellation: cancellation,
        );
        if (entry.requiresInertBeforeImage) {
          final inert = switch (before.kind) {
            OperationRecoveryEntryKind.directory =>
              before.files.isEmpty &&
                  before.directories.isEmpty &&
                  before.links.isEmpty,
            OperationRecoveryEntryKind.symbolicLink =>
              await _linkReferentIsMissing(targetPath),
            _ => false,
          };
          if (!inert) throw const ExternalOperationPreconditionChanged();
        }
        final OperationRecoverySnapshot intended;
        if (entry.intendedSymbolicLinkTarget case final target?) {
          intended = OperationRecoverySnapshot.symbolicLink(target);
        } else if (entry.intendedSourcePath == null) {
          intended = OperationRecoverySnapshot.absent();
        } else {
          intended = await _captureSnapshot(
            entry.intendedSourcePath!,
            intendedPayload,
            expectedKind: entry.intendedKind,
            allowContainedLinks: !entry.requirePlainDirectory,
            cancellation: cancellation,
          );
        }
        final residueToken = sha256Bytes(
          utf8Bytes('${spec.context.operationId.value}:${entry.entryId}'),
        ).substring(0, 16);
        final prefix =
            '.${path.basename(targetPath)}.skills-recovery.$residueToken';
        entries.add(
          OperationRecoveryEntryManifest(
            entryId: entry.entryId,
            targetPath: path.normalize(path.absolute(targetPath)),
            displacedPath: path.join(
              path.dirname(targetPath),
              '$prefix.applied',
            ),
            rollbackResiduePath: path.join(
              path.dirname(targetPath),
              '$prefix.rollback',
            ),
            rollForwardResiduePath: path.join(
              path.dirname(targetPath),
              '$prefix.roll-forward',
            ),
            makeReadOnly: entry.makeReadOnly,
            requirePlainDirectory: entry.requirePlainDirectory,
            before: before,
            intended: intended,
          ),
        );
      }
      final manifest = OperationRecoveryBundleManifest(
        context: spec.context,
        entries: entries,
        bindings: spec.bindings,
        draftCleanups: <OperationRecoveryDraftCleanupManifest>[
          for (final cleanup in spec.draftCleanups)
            OperationRecoveryDraftCleanupManifest(
              cleanupId: cleanup.cleanupId,
              managedSkillId: cleanup.managedSkillId,
              expectedBaseObjectId: cleanup.expectedBaseObjectId,
              targetPath: path.normalize(path.absolute(cleanup.targetPath)),
              quarantinePath: _draftCleanupQuarantinePath(
                cleanup.targetPath,
                spec.context.operationId,
                cleanup.cleanupId,
              ),
              capturedFingerprint: cleanup.capturedFingerprint,
            ),
        ],
        destructiveIntent: spec.destructiveIntent,
      );
      if (spec.draftCleanups.isNotEmpty) {
        await _filesystem.ensureDirectory(
          path.join(staging.path, 'draft-decisions'),
        );
      }
      final encoded = await _manifestArtifacts(manifest);
      await _filesystem.writeDurableFile(
        path.join(staging.path, 'manifest.json'),
        encoded.manifestBytes,
      );
      await _filesystem.writeDurableFile(
        path.join(staging.path, 'COMPLETE'),
        encoded.completionFenceBytes,
      );
      // Payload writers flush their own trees; writing COMPLETE flushes the
      // staging directory after every payload entry has been created.
      await _filesystem.publish(
        candidatePath: staging.path,
        destinationPath: destination,
        kind: DurableEntryKind.directory,
        requirePlainDirectory: false,
        verify: (bundlePath) async {
          final verified = await _loadBundleAt(bundlePath);
          _requireSpecMatches(verified, spec, resolvedTargetByEntryId);
        },
      );
      return await _loadRequired(spec.context.operationId);
    } on Object {
      await _removeOwnedIfPresent(staging.path, _layout.recoveryRoot);
      rethrow;
    }
  }

  Future<CanonicalManifestArtifacts> _manifestArtifacts(
    OperationRecoveryBundleManifest manifest,
  ) async {
    final worker = _manifestWorker;
    if (worker != null) {
      return worker.encodeCanonicalManifest(
        value: _codec.manifestValue(manifest),
        schemaVersion: operationRecoveryBundleSchemaVersion,
      );
    }
    final manifestBytes = _codec.encodeManifest(manifest);
    return CanonicalManifestArtifacts(
      manifestBytes: manifestBytes,
      completionFenceBytes: _codec.createCompletionFence(manifestBytes),
    );
  }

  Future<OperationRecoverySnapshot> _captureSnapshot(
    String sourcePath,
    String payloadRoot, {
    required OperationRecoveryEntryKind? expectedKind,
    required bool allowContainedLinks,
    required CancellationToken cancellation,
  }) async {
    final source = path.normalize(path.absolute(sourcePath));
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (expectedKind != null) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.entryTypeChanged,
        );
      }
      return OperationRecoverySnapshot.absent();
    }
    final kind = _entryKind(type);
    if (expectedKind != null && expectedKind != kind) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.entryTypeChanged,
      );
    }
    _throwIfCancelled(cancellation);
    final OperationRecoverySnapshot snapshot;
    switch (kind) {
      case OperationRecoveryEntryKind.file:
        final before = await File(source).stat();
        final bytes = await File(source).readAsBytes();
        final after = await File(source).stat();
        if (!_stableFile(before, after)) {
          throw const OperationRecoveryException(
            OperationRecoveryFailureReason.entryTypeChanged,
          );
        }
        await _filesystem.ensureDirectory(payloadRoot);
        await _filesystem.writeDurableFile(
          path.join(payloadRoot, 'content'),
          bytes,
        );
        snapshot = OperationRecoverySnapshot.file(
          sha256Digest: sha256Bytes(bytes),
          executable: _isExecutable(after),
        );
      case OperationRecoveryEntryKind.directory:
        final directories = <String>[];
        final files = <OperationRecoverySnapshotFile>[];
        final links = <OperationRecoverySnapshotLink>[];
        final stagedFiles = <StagedDirectoryFile>[];
        // Listing without following links reports each contained link as a
        // link entity and never descends into a linked directory.
        final entities = await Directory(
          source,
        ).list(recursive: true, followLinks: false).toList();
        entities.sort((left, right) => left.path.compareTo(right.path));
        for (final entity in entities) {
          _throwIfCancelled(cancellation);
          final relative = _safeRelative(entity.path, source);
          final entityType = await FileSystemEntity.type(
            entity.path,
            followLinks: false,
          );
          if (entityType == FileSystemEntityType.directory) {
            directories.add(relative);
            continue;
          }
          if (entityType == FileSystemEntityType.link) {
            if (!allowContainedLinks) {
              throw const OperationRecoveryException(
                OperationRecoveryFailureReason.entryTypeChanged,
              );
            }
            final before = await Link(entity.path).target();
            final after = await Link(entity.path).target();
            if (before != after) {
              throw const OperationRecoveryException(
                OperationRecoveryFailureReason.entryTypeChanged,
              );
            }
            links.add(
              _representable(
                () => OperationRecoverySnapshotLink(
                  relativePath: relative,
                  target: before,
                ),
              ),
            );
            continue;
          }
          if (entityType != FileSystemEntityType.file) {
            throw const OperationRecoveryException(
              OperationRecoveryFailureReason.entryTypeChanged,
            );
          }
          final file = File(entity.path);
          final before = await file.stat();
          final bytes = await file.readAsBytes();
          final after = await file.stat();
          if (!_stableFile(before, after)) {
            throw const OperationRecoveryException(
              OperationRecoveryFailureReason.entryTypeChanged,
            );
          }
          stagedFiles.add(
            StagedDirectoryFile(
              relativePath: relative,
              bytes: bytes,
              isExecutable: _isExecutable(after),
            ),
          );
          files.add(
            _representable(
              () => OperationRecoverySnapshotFile(
                relativePath: relative,
                sha256Digest: sha256Bytes(bytes),
                executable: _isExecutable(after),
              ),
            ),
          );
        }
        // Links carry no payload bytes; only the manifest records them.
        await _filesystem.materializeStagedDirectory(
          rootPath: payloadRoot,
          directories: directories,
          files: stagedFiles,
          checkCancelled: () => _throwIfCancelled(cancellation),
        );
        snapshot = _representable(
          () => OperationRecoverySnapshot.directory(
            directories: directories,
            files: files,
            links: links,
          ),
        );
      case OperationRecoveryEntryKind.symbolicLink:
        final before = await Link(source).target();
        final after = await Link(source).target();
        if (before != after) {
          throw const OperationRecoveryException(
            OperationRecoveryFailureReason.entryTypeChanged,
          );
        }
        snapshot = OperationRecoverySnapshot.symbolicLink(before);
    }
    if (!await _matches(source, snapshot)) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.entryTypeChanged,
      );
    }
    return snapshot;
  }

  Future<OperationRecoveryBundleManifest?> _loadOptional(
    OperationId operationId,
  ) async {
    final cached = _verifiedBundles[operationId];
    if (cached != null) return cached;
    final root = _layout.operationRecoveryPath(operationId);
    final type = await FileSystemEntity.type(root, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.directory) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.bundleCorrupt,
      );
    }
    final manifest = await _loadBundleAt(root);
    _verifiedBundles[operationId] = manifest;
    return manifest;
  }

  Future<OperationRecoveryBundleManifest> _loadRequired(
    OperationId operationId,
  ) async {
    final manifest = await _loadOptional(operationId);
    if (manifest == null) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.bundleMissing,
      );
    }
    return manifest;
  }

  Future<OperationRecoveryBundleManifest> _loadBundleAt(String root) async {
    try {
      final manifestBytes = await File(
        path.join(root, 'manifest.json'),
      ).readAsBytes();
      final fenceBytes = await File(path.join(root, 'COMPLETE')).readAsBytes();
      final manifest = _codec.verifyAndDecode(
        manifestBytes: manifestBytes,
        completionFenceBytes: fenceBytes,
      );
      if (!await _bundleTreeMatches(root, manifest)) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.checksumMismatch,
        );
      }
      for (final entry in manifest.entries) {
        final beforeRoot = operationRecoveryPayloadPath(
          bundleRoot: root,
          entryId: entry.entryId,
          intended: false,
        );
        final intendedRoot = operationRecoveryPayloadPath(
          bundleRoot: root,
          entryId: entry.entryId,
          intended: true,
        );
        if (!await _payloadMatches(beforeRoot, entry.before) ||
            !await _payloadMatches(intendedRoot, entry.intended)) {
          throw const OperationRecoveryException(
            OperationRecoveryFailureReason.checksumMismatch,
          );
        }
      }
      for (final cleanup in manifest.draftCleanups) {
        final decision = await _loadDraftCleanupDecision(
          root,
          manifest.context.operationId,
          cleanup.cleanupId,
        );
        if (decision != null && decision.cleanupId != cleanup.cleanupId) {
          throw const OperationRecoveryException(
            OperationRecoveryFailureReason.bundleCorrupt,
          );
        }
      }
      return manifest;
    } on OperationRecoveryException {
      rethrow;
    } on Object {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.bundleCorrupt,
      );
    }
  }

  Future<void> _establish(
    OperationRecoveryBundleManifest manifest,
    OperationRecoveryEntryManifest entry, {
    required OperationRecoverySnapshot desired,
    required OperationRecoverySnapshot alternate,
    required String residuePath,
  }) async {
    if (await _matches(entry.targetPath, desired)) {
      if (desired.present && entry.makeReadOnly) {
        await _filesystem.makeReadOnly(
          entry.targetPath,
          _durableKind(desired.kind!),
        );
      }
      return;
    }
    final targetAbsent =
        await FileSystemEntity.type(entry.targetPath, followLinks: false) ==
        FileSystemEntityType.notFound;
    if (!targetAbsent && !await _matches(entry.targetPath, alternate)) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.entryTypeChanged,
      );
    }
    await _removeResidueIfSafe(entry, residuePath);
    if (!desired.present) {
      if (targetAbsent) return;
      await _filesystem.displace(
        destinationPath: entry.targetPath,
        displacedPath: residuePath,
        kind: _durableKind(alternate.kind!),
        verify: (candidate) => _requireMatches(candidate, alternate),
        onMutationBarrier: _onMutationBarrier,
      );
      return;
    }

    final payloadRoot = operationRecoveryPayloadPath(
      bundleRoot: _layout.operationRecoveryPath(manifest.context.operationId),
      entryId: entry.entryId,
      intended: identical(desired, entry.intended),
    );
    final staging = await _materializeSnapshot(
      entry.targetPath,
      payloadRoot,
      desired,
    );
    try {
      await _filesystem.publish(
        candidatePath: staging,
        destinationPath: entry.targetPath,
        kind: _durableKind(desired.kind!),
        verify: (candidate) => _requireMatches(candidate, desired),
        makeReadOnly: entry.makeReadOnly,
        // Only an intended managed materialization must be plain; a before
        // image is the user's own bytes and restores verbatim.
        requirePlainDirectory:
            entry.requirePlainDirectory && identical(desired, entry.intended),
        knownDisplacedPath: targetAbsent ? null : residuePath,
        onMutationBarrier: _onMutationBarrier,
      );
    } catch (_) {
      try {
        await _filesystem.removeOwnedPath(
          targetPath: staging,
          ownerRoot: path.dirname(entry.targetPath),
        );
      } on Object {
        // Preserve the publication failure; recovery owns any retained residue.
      }
      rethrow;
    }
  }

  Future<String> _materializeSnapshot(
    String targetPath,
    String payloadRoot,
    OperationRecoverySnapshot snapshot,
  ) async {
    if (!await _payloadMatches(payloadRoot, snapshot)) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.checksumMismatch,
      );
    }
    final staging = await _filesystem.createSiblingStagingPath(
      targetPath,
      kind: _durableKind(snapshot.kind!),
      purpose: 'operation-recovery',
    );
    switch (snapshot.kind!) {
      case OperationRecoveryEntryKind.file:
        await _filesystem.writeDurableFile(
          staging.path,
          await File(path.join(payloadRoot, 'content')).readAsBytes(),
        );
        await _filesystem.setExecutableIntent(
          staging.path,
          snapshot.executable,
        );
      case OperationRecoveryEntryKind.directory:
        final files = <StagedDirectoryFile>[];
        for (final file in snapshot.files) {
          files.add(
            StagedDirectoryFile(
              relativePath: file.relativePath,
              bytes: await File(
                _payloadChild(payloadRoot, file.relativePath),
              ).readAsBytes(),
              isExecutable: file.executable,
            ),
          );
        }
        await _filesystem.materializeStagedDirectory(
          rootPath: staging.path,
          directories: snapshot.directories,
          files: files,
        );
        // Links last, so a relative target can already refer to a sibling.
        for (final link in snapshot.links) {
          try {
            await _filesystem.createSymbolicLink(
              linkPath: _payloadChild(staging.path, link.relativePath),
              targetPath: link.target,
            );
          } on FileSystemException {
            throw const OperationRecoveryException(
              OperationRecoveryFailureReason.restoreIoFailure,
            );
          }
        }
      case OperationRecoveryEntryKind.symbolicLink:
        await _filesystem.createSymbolicLink(
          linkPath: staging.path,
          targetPath: snapshot.linkTarget!,
        );
    }
    await _requireMatches(staging.path, snapshot);
    return staging.path;
  }

  Future<bool> _payloadMatches(
    String payloadRoot,
    OperationRecoverySnapshot snapshot,
  ) async {
    final rootType = await FileSystemEntity.type(
      payloadRoot,
      followLinks: false,
    );
    if (!snapshot.present ||
        snapshot.kind == OperationRecoveryEntryKind.symbolicLink) {
      return rootType == FileSystemEntityType.notFound;
    }
    if (rootType != FileSystemEntityType.directory) return false;

    final actualDirectories = <String>[];
    final actualFiles = <String, File>{};
    final entities = await Directory(
      payloadRoot,
    ).list(recursive: true, followLinks: false).toList();
    for (final entity in entities) {
      final relative = _safeRelative(entity.path, payloadRoot);
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        actualDirectories.add(relative);
      } else if (type == FileSystemEntityType.file) {
        actualFiles[relative] = File(entity.path);
      } else {
        return false;
      }
    }

    final expectedDirectories =
        snapshot.kind == OperationRecoveryEntryKind.directory
        ? ([...snapshot.directories]..sort())
        : <String>[];
    final expectedFiles = snapshot.kind == OperationRecoveryEntryKind.file
        ? {'content': snapshot.files.single.sha256Digest}
        : {
            for (final file in snapshot.files)
              file.relativePath: file.sha256Digest,
          };
    actualDirectories.sort();
    if (!_sameStrings(actualDirectories, expectedDirectories) ||
        actualFiles.length != expectedFiles.length) {
      return false;
    }
    for (final expected in expectedFiles.entries) {
      final candidate = actualFiles[expected.key];
      if (candidate == null || await _fileDigest(candidate) != expected.value) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _bundleTreeMatches(
    String bundleRoot,
    OperationRecoveryBundleManifest manifest,
  ) async {
    final expectedDirectories = <String>{};
    final expectedFiles = <String>{'manifest.json', 'COMPLETE'};
    if (manifest.draftCleanups.isNotEmpty) {
      expectedDirectories.add('draft-decisions');
      for (final cleanup in manifest.draftCleanups) {
        for (final suffix in <String>[
          'json',
          'pending',
          'preserve',
          'preserve-pending',
        ]) {
          final relative = path.posix.join(
            'draft-decisions',
            '${cleanup.cleanupId}.$suffix',
          );
          if (await File(path.join(bundleRoot, relative)).exists()) {
            expectedFiles.add(relative);
          }
        }
      }
    }

    void addPayload(
      String entryId,
      String label,
      OperationRecoverySnapshot snapshot,
    ) {
      if (!snapshot.present ||
          snapshot.kind == OperationRecoveryEntryKind.symbolicLink) {
        return;
      }
      final payloadRoot = path.posix.join('payloads', entryId, label);
      expectedDirectories
        ..add('payloads')
        ..add(path.posix.join('payloads', entryId))
        ..add(payloadRoot);
      if (snapshot.kind == OperationRecoveryEntryKind.file) {
        expectedFiles.add(path.posix.join(payloadRoot, 'content'));
        return;
      }
      for (final directory in snapshot.directories) {
        expectedDirectories.add(path.posix.join(payloadRoot, directory));
      }
      for (final file in snapshot.files) {
        expectedFiles.add(path.posix.join(payloadRoot, file.relativePath));
      }
    }

    for (final entry in manifest.entries) {
      addPayload(entry.entryId, 'before', entry.before);
      addPayload(entry.entryId, 'intended', entry.intended);
    }

    final actualDirectories = <String>{};
    final actualFiles = <String>{};
    final entities = await Directory(
      bundleRoot,
    ).list(recursive: true, followLinks: false).toList();
    for (final entity in entities) {
      final relative = _safeRelative(entity.path, bundleRoot);
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        actualDirectories.add(relative);
      } else if (type == FileSystemEntityType.file) {
        actualFiles.add(relative);
      } else {
        return false;
      }
    }
    return actualDirectories.length == expectedDirectories.length &&
        actualDirectories.containsAll(expectedDirectories) &&
        actualFiles.length == expectedFiles.length &&
        actualFiles.containsAll(expectedFiles);
  }

  Future<bool> _matches(
    String targetPath,
    OperationRecoverySnapshot snapshot,
  ) async {
    final type = await FileSystemEntity.type(targetPath, followLinks: false);
    if (!snapshot.present) return type == FileSystemEntityType.notFound;
    if (type != _fileSystemType(snapshot.kind!)) return false;
    switch (snapshot.kind!) {
      case OperationRecoveryEntryKind.file:
        final file = File(targetPath);
        return await _fileDigest(file) == snapshot.files.single.sha256Digest &&
            _isExecutable(await file.stat()) == snapshot.executable;
      case OperationRecoveryEntryKind.directory:
        final directories = <String>[];
        final files = <String, File>{};
        final links = <String, Link>{};
        final entities = await Directory(
          targetPath,
        ).list(recursive: true, followLinks: false).toList();
        for (final entity in entities) {
          final relative = _safeRelative(entity.path, targetPath);
          final entityType = await FileSystemEntity.type(
            entity.path,
            followLinks: false,
          );
          if (entityType == FileSystemEntityType.directory) {
            directories.add(relative);
          } else if (entityType == FileSystemEntityType.file) {
            files[relative] = File(entity.path);
          } else if (entityType == FileSystemEntityType.link) {
            links[relative] = Link(entity.path);
          } else {
            return false;
          }
        }
        directories.sort();
        final expectedDirectories = [...snapshot.directories]..sort();
        if (!_sameStrings(directories, expectedDirectories) ||
            files.length != snapshot.files.length ||
            links.length != snapshot.links.length) {
          return false;
        }
        for (final expected in snapshot.files) {
          final candidate = files[expected.relativePath];
          if (candidate == null ||
              await _fileDigest(candidate) != expected.sha256Digest ||
              _isExecutable(await candidate.stat()) != expected.executable) {
            return false;
          }
        }
        for (final expected in snapshot.links) {
          final candidate = links[expected.relativePath];
          if (candidate == null ||
              await candidate.target() != expected.target) {
            return false;
          }
        }
        return true;
      case OperationRecoveryEntryKind.symbolicLink:
        return await Link(targetPath).target() == snapshot.linkTarget;
    }
  }

  Future<void> _requireMatches(
    String targetPath,
    OperationRecoverySnapshot snapshot,
  ) async {
    if (!await _matches(targetPath, snapshot)) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.checksumMismatch,
      );
    }
  }

  Future<void> _cleanupEntryResidues(
    OperationRecoveryEntryManifest entry,
  ) async {
    for (final residue in [
      entry.displacedPath,
      entry.rollbackResiduePath,
      entry.rollForwardResiduePath,
    ]) {
      await _removeResidueIfSafe(entry, residue);
    }
  }

  Future<void> _removeResidueIfSafe(
    OperationRecoveryEntryManifest entry,
    String residuePath,
  ) async {
    if (await FileSystemEntity.type(residuePath, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    if (!await _matches(residuePath, entry.before) &&
        !await _matches(residuePath, entry.intended)) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.checksumMismatch,
      );
    }
    await _filesystem.removeOwnedPath(
      targetPath: residuePath,
      ownerRoot: path.dirname(entry.targetPath),
    );
  }

  Future<void> _removeOwnedIfPresent(String target, String ownerRoot) async {
    if (await FileSystemEntity.type(target, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    await _filesystem.removeOwnedPath(targetPath: target, ownerRoot: ownerRoot);
  }

  void _requireSpecMatches(
    OperationRecoveryBundleManifest manifest,
    OperationRecoveryBundleSpec spec,
    Map<String, String> resolvedTargetByEntryId,
  ) {
    if (manifest.context.operationId != spec.context.operationId ||
        manifest.context.expectedRepositoryRevision !=
            spec.context.expectedRepositoryRevision ||
        manifest.context.committedRepositoryRevision !=
            spec.context.committedRepositoryRevision ||
        manifest.context.destructive != spec.context.destructive ||
        !_sameDestructiveIntent(
          manifest.destructiveIntent,
          spec.destructiveIntent,
        ) ||
        manifest.entries.length != spec.entries.length ||
        manifest.draftCleanups.length != spec.draftCleanups.length ||
        manifest.bindings.length != spec.bindings.length) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.operationMismatch,
      );
    }
    final cleanupsById = <String, OperationRecoveryDraftCleanupManifest>{
      for (final cleanup in manifest.draftCleanups) cleanup.cleanupId: cleanup,
    };
    for (final expected in spec.draftCleanups) {
      final actual = cleanupsById[expected.cleanupId];
      if (actual == null ||
          actual.managedSkillId != expected.managedSkillId ||
          actual.expectedBaseObjectId != expected.expectedBaseObjectId ||
          !path.equals(actual.targetPath, expected.targetPath) ||
          actual.capturedFingerprint != expected.capturedFingerprint) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.operationMismatch,
        );
      }
    }
    final entriesById = {
      for (final entry in manifest.entries) entry.entryId: entry,
    };
    for (final expected in spec.entries) {
      final actual = entriesById[expected.entryId];
      final resolvedTarget = resolvedTargetByEntryId[expected.entryId];
      if (actual == null ||
          resolvedTarget == null ||
          !path.equals(actual.targetPath, resolvedTarget) ||
          actual.makeReadOnly != expected.makeReadOnly ||
          actual.requirePlainDirectory != expected.requirePlainDirectory ||
          actual.intended.present !=
              (expected.intendedSourcePath != null ||
                  expected.intendedSymbolicLinkTarget != null) ||
          actual.intended.kind != expected.intendedKind ||
          (expected.intendedSymbolicLinkTarget != null &&
              actual.intended.linkTarget !=
                  expected.intendedSymbolicLinkTarget)) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.operationMismatch,
        );
      }
    }
    final bindingsByReference = {
      for (final binding in manifest.bindings)
        binding.reference.encoded: binding,
    };
    for (final expected in spec.bindings) {
      final actual = bindingsByReference[expected.reference.encoded];
      if (actual == null ||
          actual.action != expected.action ||
          actual.entryId != expected.entryId) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.operationMismatch,
        );
      }
    }
  }

  void _requirePlanMatches(
    OperationRecoveryBundleManifest manifest,
    OperationPlan plan,
  ) {
    if (manifest.context.operationId != plan.operationId ||
        manifest.context.expectedRepositoryRevision !=
            plan.expectedRepositoryRevision ||
        manifest.context.committedRepositoryRevision !=
            plan.committedRepositoryRevision ||
        manifest.context.destructive !=
            plan.businessChanges.incrementsDestructionEpoch) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.operationMismatch,
      );
    }
    final plannedSteps = <OperationStep>[
      ...plan.preparationSteps,
      ...plan.applyingSteps,
      ...plan.finalizationSteps,
    ];
    final plannedReferences = <String>{
      for (final step in plannedSteps) step.recoveryReference.encoded,
    };
    final bundleReferences = manifest.bindings
        .map((binding) => binding.reference.encoded)
        .toSet();
    if (plannedReferences.length != plannedSteps.length ||
        plannedReferences.length != bundleReferences.length ||
        !plannedReferences.containsAll(bundleReferences)) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.operationMismatch,
      );
    }
  }

  Set<String> _validatePreparedEnvelopeReferences(
    PreparedOperationEnvelope envelope,
  ) {
    final references = <String>{};
    for (final step in envelope.preparationSteps) {
      final decoded = decodeOperationRecoveryReference(step.recoveryReference);
      if (decoded.operationId != envelope.operationId ||
          !references.add(step.recoveryReference.encoded)) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.operationMismatch,
        );
      }
    }
    return references;
  }

  List<OperationRecoveryStepBinding> _requirePreparedEnvelopeMatches(
    OperationRecoveryBundleManifest manifest,
    PreparedOperationEnvelope envelope,
    Set<String> references,
  ) {
    if (manifest.context.operationId != envelope.operationId ||
        manifest.context.expectedRepositoryRevision !=
            envelope.expectedRepositoryRevision ||
        manifest.context.committedRepositoryRevision !=
            envelope.committedRepositoryRevision) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.operationMismatch,
      );
    }
    final bindings = <OperationRecoveryStepBinding>[];
    for (final step in envelope.preparationSteps) {
      final binding = manifest.binding(step.recoveryReference);
      if (!references.contains(binding.reference.encoded) ||
          !_preparedEnvelopeActionAllowed(binding.action)) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.operationMismatch,
        );
      }
      bindings.add(binding);
    }
    return bindings;
  }

  OperationRecoveryBackupMaintenancePort _requireBackupMaintenance() {
    final maintenance = _backupMaintenance;
    if (maintenance == null) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.unsupportedStepAction,
      );
    }
    return maintenance;
  }

  OperationRecoveryDestructiveMaintenancePort _requireDestructiveMaintenance() {
    final maintenance = _destructiveMaintenance;
    if (maintenance == null) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.unsupportedStepAction,
      );
    }
    return maintenance;
  }

  DestructiveOperationRecoveryIntent _requireDestructiveIntent(
    OperationRecoveryBundleManifest manifest,
  ) {
    final intent = manifest.destructiveIntent;
    if (intent == null) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.operationMismatch,
      );
    }
    return intent;
  }

  Future<OperationFinalizationEffect?> _finalizeDraftCleanup(
    OperationRecoveryBundleManifest manifest,
    OperationRecoveryDraftCleanupManifest cleanup,
  ) async {
    final bundleRoot = _layout.operationRecoveryPath(
      manifest.context.operationId,
    );
    var record = await _loadDraftCleanupDecision(
      bundleRoot,
      manifest.context.operationId,
      cleanup.cleanupId,
    );
    if (record == null) {
      final decision = await _selectDraftCleanupDecision(cleanup);
      record = OperationRecoveryDraftCleanupDecisionRecord(
        operationId: manifest.context.operationId,
        cleanupId: cleanup.cleanupId,
        decision: decision,
      );
      await _persistDraftCleanupDecision(bundleRoot, record);
    }
    if (record.decision == OperationRecoveryDraftCleanupDecision.preserve) {
      return _preserveDraftCleanup(cleanup);
    }
    try {
      await _onDraftCleanupFinalization?.call(
        DraftCleanupFinalizationEvent.deleteDecisionPersisted,
        cleanup.targetPath,
        cleanup.quarantinePath,
      );
      return await _deleteCapturedDraft(cleanup);
    } on _DraftCleanupMustPreserve {
      // A writable handle can mutate the quarantined inode after the initial
      // delete eligibility decision. Preserve is a monotonic safety override:
      // once durable, no restart may reinterpret this generation as deletable.
      await _persistDraftPreserveOverride(
        bundleRoot,
        OperationRecoveryDraftCleanupDecisionRecord(
          operationId: manifest.context.operationId,
          cleanupId: cleanup.cleanupId,
          decision: OperationRecoveryDraftCleanupDecision.preserve,
        ),
      );
      return _preserveDraftCleanup(cleanup);
    }
  }

  Future<OperationRecoveryDraftCleanupDecision> _selectDraftCleanupDecision(
    OperationRecoveryDraftCleanupManifest cleanup,
  ) async {
    final current = await _draftFingerprint(
      cleanup.targetPath,
      capturedFingerprint: cleanup.capturedFingerprint,
    );
    if (current != cleanup.capturedFingerprint) {
      return OperationRecoveryDraftCleanupDecision.preserve;
    }
    try {
      await _removeOwnedIfPresent(
        cleanup.quarantinePath,
        path.dirname(cleanup.targetPath),
      );
      await _filesystem.displace(
        destinationPath: cleanup.targetPath,
        displacedPath: cleanup.quarantinePath,
        kind: DurableEntryKind.directory,
        verify: (candidate) async {
          if (await _draftFingerprint(
                candidate,
                capturedFingerprint: cleanup.capturedFingerprint,
              ) !=
              cleanup.capturedFingerprint) {
            throw const OperationRecoveryException(
              OperationRecoveryFailureReason.entryTypeChanged,
            );
          }
        },
        onMutationBarrier: _onMutationBarrier,
      );
      final quarantined = await _draftFingerprint(
        cleanup.quarantinePath,
        capturedFingerprint: cleanup.capturedFingerprint,
      );
      final replacementExists =
          await FileSystemEntity.type(cleanup.targetPath, followLinks: false) !=
          FileSystemEntityType.notFound;
      if (quarantined == cleanup.capturedFingerprint && !replacementExists) {
        return OperationRecoveryDraftCleanupDecision.delete;
      }
      return OperationRecoveryDraftCleanupDecision.preserve;
    } on Object {
      return OperationRecoveryDraftCleanupDecision.preserve;
    }
  }

  Future<OperationFinalizationEffect?> _preserveDraftCleanup(
    OperationRecoveryDraftCleanupManifest cleanup,
  ) async {
    final quarantineType = await FileSystemEntity.type(
      cleanup.quarantinePath,
      followLinks: false,
    );
    if (quarantineType == FileSystemEntityType.notFound) return null;
    if (quarantineType != FileSystemEntityType.directory) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.entryTypeChanged,
      );
    }
    final targetType = await FileSystemEntity.type(
      cleanup.targetPath,
      followLinks: false,
    );
    if (targetType == FileSystemEntityType.notFound) {
      await _filesystem.publish(
        candidatePath: cleanup.quarantinePath,
        destinationPath: cleanup.targetPath,
        kind: DurableEntryKind.directory,
        requirePlainDirectory: true,
        makeReadOnly: false,
        verify: (candidate) async {
          if (await FileSystemEntity.type(candidate, followLinks: false) !=
              FileSystemEntityType.directory) {
            throw const OperationRecoveryException(
              OperationRecoveryFailureReason.entryTypeChanged,
            );
          }
        },
        onMutationBarrier: _onMutationBarrier,
      );
      return null;
    }
    if (targetType != FileSystemEntityType.directory ||
        await _draftFingerprint(
              cleanup.quarantinePath,
              capturedFingerprint: cleanup.capturedFingerprint,
            ) !=
            cleanup.capturedFingerprint) {
      throw const OperationRecoveryException(
        OperationRecoveryFailureReason.entryTypeChanged,
      );
    }
    // A new live generation appeared after the captured one was quarantined.
    // The new path is authoritative; only the proven displaced entry is stale.
    await _removeOwnedIfPresent(
      cleanup.quarantinePath,
      path.dirname(cleanup.targetPath),
    );
    return null;
  }

  Future<OperationFinalizationEffect?> _deleteCapturedDraft(
    OperationRecoveryDraftCleanupManifest cleanup,
  ) async {
    final targetExists =
        await FileSystemEntity.type(cleanup.targetPath, followLinks: false) !=
        FileSystemEntityType.notFound;
    final quarantineExists =
        await FileSystemEntity.type(
          cleanup.quarantinePath,
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound;
    if (quarantineExists) {
      if (await _draftFingerprint(
            cleanup.quarantinePath,
            capturedFingerprint: cleanup.capturedFingerprint,
          ) !=
          cleanup.capturedFingerprint) {
        throw const _DraftCleanupMustPreserve();
      }
      await _removeOwnedIfPresent(
        cleanup.quarantinePath,
        path.dirname(cleanup.targetPath),
      );
    }
    if (targetExists) {
      // A post-decision save recreated the Draft path. Never delete its row.
      return null;
    }
    return DeleteReanchoredDraftEffect(
      managedSkillId: cleanup.managedSkillId,
      expectedBaseObjectId: cleanup.expectedBaseObjectId,
    );
  }

  Future<DraftFingerprint?> _draftFingerprint(
    String draftPath, {
    required DraftFingerprint capturedFingerprint,
  }) async {
    final executableIntentOverrides = _capturePosixExecutableIntent
        ? const <String, bool>{}
        : <String, bool>{
            for (final entry in capturedFingerprint.entries)
              if (entry.contentHash != null)
                entry.relativePath: entry.isExecutable,
          };
    final result = await _draftSnapshots.fingerprint(
      DraftCaptureRequest(
        liveDraftPath: draftPath,
        stagingDestinationPath: path.join(
          _layout.stagingRoot,
          '.draft-finalization-fingerprint',
        ),
        capturePosixExecutableIntent: _capturePosixExecutableIntent,
        executableIntentOverrides: executableIntentOverrides,
      ),
    );
    return result.valueOrNull;
  }

  Future<OperationRecoveryDraftCleanupDecisionRecord?>
  _loadDraftCleanupDecision(
    String bundleRoot,
    OperationId operationId,
    String cleanupId,
  ) async {
    final preserve = _draftDecisionPath(bundleRoot, cleanupId, 'preserve');
    final preservePending = _draftDecisionPath(
      bundleRoot,
      cleanupId,
      'preserve-pending',
    );
    final destination = _draftDecisionPath(bundleRoot, cleanupId, 'json');
    final pending = _draftDecisionPath(bundleRoot, cleanupId, 'pending');
    for (final candidate in <String>[
      preserve,
      preservePending,
      destination,
      pending,
    ]) {
      if (!await File(candidate).exists()) continue;
      final record = _codec.decodeDraftCleanupDecision(
        await File(candidate).readAsBytes(),
      );
      if (record.operationId != operationId || record.cleanupId != cleanupId) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.operationMismatch,
        );
      }
      final isPreserveCandidate =
          candidate == preserve || candidate == preservePending;
      if (isPreserveCandidate &&
          record.decision != OperationRecoveryDraftCleanupDecision.preserve) {
        throw const OperationRecoveryException(
          OperationRecoveryFailureReason.bundleCorrupt,
        );
      }
      final publishDestination = isPreserveCandidate ? preserve : destination;
      final isPending = candidate == pending || candidate == preservePending;
      if (isPending && !await File(publishDestination).exists()) {
        await _filesystem.publish(
          candidatePath: candidate,
          destinationPath: publishDestination,
          kind: DurableEntryKind.file,
          verify: (published) async {
            final decoded = _codec.decodeDraftCleanupDecision(
              await File(published).readAsBytes(),
            );
            if (decoded.operationId != operationId ||
                decoded.cleanupId != cleanupId ||
                decoded.decision != record.decision) {
              throw const OperationRecoveryException(
                OperationRecoveryFailureReason.checksumMismatch,
              );
            }
          },
        );
      }
      return record;
    }
    return null;
  }

  Future<void> _persistDraftCleanupDecision(
    String bundleRoot,
    OperationRecoveryDraftCleanupDecisionRecord record,
  ) async {
    final destination = _draftDecisionPath(
      bundleRoot,
      record.cleanupId,
      'json',
    );
    if (await File(destination).exists()) return;
    final pending = _draftDecisionPath(bundleRoot, record.cleanupId, 'pending');
    final bytes = _codec.encodeDraftCleanupDecision(record);
    await _filesystem.writeDurableFile(pending, bytes);
    await _filesystem.publish(
      candidatePath: pending,
      destinationPath: destination,
      kind: DurableEntryKind.file,
      verify: (published) async {
        final decoded = _codec.decodeDraftCleanupDecision(
          await File(published).readAsBytes(),
        );
        if (decoded.operationId != record.operationId ||
            decoded.cleanupId != record.cleanupId ||
            decoded.decision != record.decision) {
          throw const OperationRecoveryException(
            OperationRecoveryFailureReason.checksumMismatch,
          );
        }
      },
    );
  }

  Future<void> _persistDraftPreserveOverride(
    String bundleRoot,
    OperationRecoveryDraftCleanupDecisionRecord record,
  ) async {
    final destination = _draftDecisionPath(
      bundleRoot,
      record.cleanupId,
      'preserve',
    );
    if (await File(destination).exists()) return;
    final pending = _draftDecisionPath(
      bundleRoot,
      record.cleanupId,
      'preserve-pending',
    );
    final bytes = _codec.encodeDraftCleanupDecision(record);
    await _filesystem.writeDurableFile(pending, bytes);
    await _filesystem.publish(
      candidatePath: pending,
      destinationPath: destination,
      kind: DurableEntryKind.file,
      verify: (published) async {
        final decoded = _codec.decodeDraftCleanupDecision(
          await File(published).readAsBytes(),
        );
        if (decoded.operationId != record.operationId ||
            decoded.cleanupId != record.cleanupId ||
            decoded.decision !=
                OperationRecoveryDraftCleanupDecision.preserve) {
          throw const OperationRecoveryException(
            OperationRecoveryFailureReason.checksumMismatch,
          );
        }
      },
    );
  }
}

final class _DraftCleanupMustPreserve implements Exception {
  const _DraftCleanupMustPreserve();
}

String _draftCleanupQuarantinePath(
  String targetPath,
  OperationId operationId,
  String cleanupId,
) => path.join(
  path.dirname(targetPath),
  '.${path.basename(targetPath)}.skills-draft-cleanup.'
  '${sha256Bytes(utf8Bytes('${operationId.value}:$cleanupId')).substring(0, 16)}',
);

String _draftDecisionPath(String bundleRoot, String cleanupId, String suffix) =>
    path.join(bundleRoot, 'draft-decisions', '$cleanupId.$suffix');

bool _preparedEnvelopeActionAllowed(OperationRecoveryAction action) =>
    switch (action) {
      OperationRecoveryAction.prepareEvidence ||
      OperationRecoveryAction.prepareDestructiveResources => true,
      _ => false,
    };

bool _sameDestructiveIntent(
  DestructiveOperationRecoveryIntent? left,
  DestructiveOperationRecoveryIntent? right,
) {
  if (left.runtimeType != right.runtimeType) return false;
  if (left == null || right == null) return left == right;
  if (left.skills.length != right.skills.length) return false;
  for (var index = 0; index < left.skills.length; index += 1) {
    final leftSkill = left.skills[index];
    final rightSkill = right.skills[index];
    if (leftSkill.managedSkillId != rightSkill.managedSkillId ||
        leftSkill.slotKey != rightSkill.slotKey ||
        leftSkill.hasDraft != rightSkill.hasDraft ||
        leftSkill.hasUpdateCandidateSession !=
            rightSkill.hasUpdateCandidateSession ||
        !_sameStrings(leftSkill.activationIds, rightSkill.activationIds) ||
        leftSkill.sourceLineages.length != rightSkill.sourceLineages.length) {
      return false;
    }
    for (
      var lineageIndex = 0;
      lineageIndex < leftSkill.sourceLineages.length;
      lineageIndex += 1
    ) {
      final leftLineage = leftSkill.sourceLineages[lineageIndex];
      final rightLineage = rightSkill.sourceLineages[lineageIndex];
      if (leftLineage.sourceLineage != rightLineage.sourceLineage) {
        return false;
      }
    }
  }
  if (left case final SourceReplacementRecoveryIntent replacementLeft) {
    final replacementRight = right as SourceReplacementRecoveryIntent;
    return replacementLeft.intendedSourceLineage ==
            replacementRight.intendedSourceLineage &&
        replacementLeft.intendedSlotKey == replacementRight.intendedSlotKey &&
        replacementLeft.intendedObjectId == replacementRight.intendedObjectId &&
        replacementLeft.intendedContentHash ==
            replacementRight.intendedContentHash &&
        replacementLeft.intendedObjectFormat ==
            replacementRight.intendedObjectFormat;
  }
  return true;
}

OperationRecoveryEntryKind _entryKind(FileSystemEntityType type) =>
    switch (type) {
      FileSystemEntityType.file => OperationRecoveryEntryKind.file,
      FileSystemEntityType.directory => OperationRecoveryEntryKind.directory,
      FileSystemEntityType.link => OperationRecoveryEntryKind.symbolicLink,
      _ => throw const OperationRecoveryException(
        OperationRecoveryFailureReason.entryTypeChanged,
      ),
    };

DurableEntryKind _durableKind(OperationRecoveryEntryKind kind) =>
    switch (kind) {
      OperationRecoveryEntryKind.file => DurableEntryKind.file,
      OperationRecoveryEntryKind.directory => DurableEntryKind.directory,
      OperationRecoveryEntryKind.symbolicLink => DurableEntryKind.symbolicLink,
    };

FileSystemEntityType _fileSystemType(OperationRecoveryEntryKind kind) =>
    switch (kind) {
      OperationRecoveryEntryKind.file => FileSystemEntityType.file,
      OperationRecoveryEntryKind.directory => FileSystemEntityType.directory,
      OperationRecoveryEntryKind.symbolicLink => FileSystemEntityType.link,
    };

bool _stableFile(FileStat before, FileStat after) =>
    before.type == FileSystemEntityType.file &&
    after.type == FileSystemEntityType.file &&
    before.size == after.size &&
    before.modified == after.modified &&
    before.mode == after.mode;

bool _isExecutable(FileStat stat) =>
    !Platform.isWindows && stat.mode & 0x49 != 0;

Future<String> _fileDigest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

String _safeRelative(String child, String root) {
  final relative = path.relative(child, from: root);
  if (relative.isEmpty ||
      relative == '.' ||
      relative == '..' ||
      path.isAbsolute(relative) ||
      relative.startsWith('../') ||
      relative.startsWith('..${path.separator}')) {
    throw const OperationRecoveryException(
      OperationRecoveryFailureReason.unsafePath,
    );
  }
  return relative.replaceAll(path.separator, '/');
}

/// Builds a manifest value from observed names; a name the manifest cannot
/// hold losslessly fails closed before any evidence is published.
T _representable<T>(T Function() build) {
  try {
    return build();
  } on ArgumentError {
    throw const OperationRecoveryException(
      OperationRecoveryFailureReason.unsafePath,
    );
  }
}

String _payloadChild(String root, String relative) {
  final nativeRelative = relative.replaceAll('/', path.separator);
  final candidate = path.normalize(path.join(root, nativeRelative));
  if (!path.isWithin(path.normalize(root), candidate)) {
    throw const OperationRecoveryException(
      OperationRecoveryFailureReason.unsafePath,
    );
  }
  return candidate;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _throwIfCancelled(CancellationToken token) {
  if (token.isCancelled) throw const _OperationRecoveryCancelled();
}

final class _OperationRecoveryCancelled implements Exception {
  const _OperationRecoveryCancelled();
}

/// Only an explicit missing-path error proves a dangling referent. Type/exists
/// APIs fold permission errors and cycles into notFound and are insufficient.
Future<bool> _linkReferentIsMissing(String linkPath) async {
  try {
    await Link(linkPath).resolveSymbolicLinks();
    return false;
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    return code == 2 || (Platform.isWindows && code == 3);
  }
}
