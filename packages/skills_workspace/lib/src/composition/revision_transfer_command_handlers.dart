import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:canonical_json/canonical_json.dart';

import '../api/composite_command_dispatcher.dart';
import '../api/result.dart';
import '../api/revision_transfer.dart';
import '../application/backup/control_plane_backup_codec.dart';
import '../application/backup/control_plane_backup_models.dart';
import '../domain/source_descriptor.dart';
import '../application/operations/operation_coordinator.dart';
import '../application/operations/operation_models.dart';
import '../application/operations/operation_plan_assembler.dart';
import '../application/operations/destructive_recovery_intent.dart';
import '../application/operations/workspace_business_changes.dart';
import '../application/ports/destructive_operation_ports.dart';
import '../application/destructive/destructive_operation_models.dart';
import '../infrastructure/database/source_descriptor_codec.dart';
import '../infrastructure/source/frontmatter_parser.dart';
import '../application/ports/operation_ports.dart';
import '../application/ports/update_ports.dart';
import '../application/update/update_models.dart';
import '../application/revision_store/managed_skill_revision_access_gate.dart';
import '../application/revision_transfer/revision_transfer_models.dart';
import '../application/runtime/revision_engine_port.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../infrastructure/database/workspace_database.dart' as db;
import '../infrastructure/database/operation_plan_codec.dart';
import '../infrastructure/revision_transfer/revision_transfer_codec.dart';
import '../infrastructure/workspace_layout.dart';
import '../platform/filesystem/durable_workspace_filesystem.dart';
import 'mutation_command_support.dart';
import 'revision_operation_plans.dart';
import 'revision_preparation_service.dart';
import 'revision_network_transfers.dart';

/// Composition for a short-lived local capture and object-preserving apply.
/// No account, credential, network lease, cursor or remote event enters DB.
final class WorkspaceRevisionTransferCommands {
  const WorkspaceRevisionTransferCommands({
    required this.network,
    required this.destructiveEntries,
    required this.destructiveState,
    required this.planAssembler,
    required this.database,
    required this.snapshots,
    required this.writerLock,
    required this.accessGate,
    required this.layout,
    required this.filesystem,
    required this.revisions,
    required this.states,
    required this.drafts,
    required this.operations,
    required this.preparation,
    required this.plans,
  });
  final WorkspaceRevisionNetworkTransfers network;
  final DestructiveRecoveryEntryPreparationPort destructiveEntries;
  final DestructivePlanningStatePort destructiveState;
  final OperationPlanAssembler planAssembler;
  final db.WorkspaceDatabase database;
  final WorkspaceSnapshotPublisher snapshots;
  final WorkspaceWriterLockPort writerLock;
  final ManagedSkillRevisionAccessGate accessGate;
  final WorkspaceLayout layout;
  final DurableWorkspaceFilesystem filesystem;
  final RevisionEnginePort revisions;
  final UpdateRevisionStatePort states;
  final UpdateDraftInspectionPort drafts;
  final OperationCoordinator operations;
  final WorkspaceRevisionPreparationService preparation;
  final WorkspaceRevisionOperationPlans plans;

  List<SkillsCommandHandler> get handlers => [
    TypedSkillsCommandHandler<
      InspectIncomingRevisionOutcomeRequest,
      IncomingRevisionOutcome
    >(
      kind: WorkspaceOperationKind.inspectIncomingRevisionOutcome,
      handle: (request, context) async => SkillsSuccess(
        value: await _inspectOutcome(request.binding, context),
        changed: false,
      ),
    ),
    ...network.handlers(prepareIncoming),
    TypedSkillsCommandHandler<
      ReplaceIncomingRevisionRequest,
      IncomingRevisionApplyResult
    >(
      kind: WorkspaceOperationKind.replaceIncomingRevision,
      handle: replaceIncoming,
    ),
    TypedSkillsCommandHandler<
      CaptureAuthoritativeStateRequest,
      AuthoritativeWorkspaceCapture
    >(kind: WorkspaceOperationKind.captureAuthoritativeState, handle: capture),
    TypedSkillsCommandHandler<
      PrepareIncomingRevisionRequest,
      CommittedRevisionBatch
    >(
      kind: WorkspaceOperationKind.prepareIncomingRevision,
      handle: prepareIncoming,
    ),
    TypedSkillsCommandHandler<
      ExportCommittedRevisionRequest,
      CommittedRevisionBatch
    >(kind: WorkspaceOperationKind.exportCommittedRevision, handle: export),
    TypedSkillsCommandHandler<
      InstallIncomingRevisionRequest,
      IncomingRevisionApplyResult
    >(
      kind: WorkspaceOperationKind.installIncomingRevision,
      handle: installIncoming,
    ),
    TypedSkillsCommandHandler<
      ApplyIncomingRevisionRequest,
      IncomingRevisionApplyResult
    >(kind: WorkspaceOperationKind.applyIncomingRevision, handle: apply),
  ];

  Future<SkillsResult<AuthoritativeWorkspaceCapture>> capture(
    CaptureAuthoritativeStateRequest _,
    SkillsCommandContext context,
  ) async {
    final lease = await writerLock.acquire(waitPolicy: context.lockWaitPolicy);
    try {
      return await _captureUnderLock(context);
    } finally {
      await lease.release();
    }
  }

  Future<SkillsResult<AuthoritativeWorkspaceCapture>> _captureUnderLock(
    SkillsCommandContext context,
  ) async {
    try {
      try {
        await network.reconcileInactiveTransfers();
      } on Object {
        /* Proof flags below retain the failure. */
      }
      if (context.cancellationToken.isCancelled) {
        return SkillsFailure(code: SkillsErrorCode.operationCancelled);
      }
      final snapshot = await snapshots.reload();
      final state = await database.transaction(() async {
        final metadata = await database
            .select(database.workspaceMetadata)
            .getSingle();
        final skills = await database.select(database.managedSkills).get();
        final ids = skills.map((row) => row.id).toSet();
        final lineages = {
          for (final skill in skills)
            ManagedSkillId(skill.id): _lineageFingerprint(
              skill.activeSourceLineageId,
            ),
        };
        final journals = await database
            .select(database.operationJournals)
            .get();
        return (
          identity: WorkspaceIdentity(
            workspaceId: metadata.workspaceId,
            recoveryIncarnation: metadata.recoveryIncarnation,
          ),
          revision: metadata.repositoryRevision,
          epoch: metadata.destructionEpoch,
          ids: ids,
          localLineages: Map<ManagedSkillId, String>.unmodifiable(lineages),
          journals: journals,
          artifacts: await database
              .select(database.workspaceTransferArtifacts)
              .get(),
          networkArtifacts: await database
              .select(database.workspaceNetworkTransfers)
              .get(),
        );
      });
      var fenceReady = false;
      try {
        final bytes = await File(layout.backupEligibilityPath).readAsBytes();
        if (bytes.length <= 65536) {
          final fence = const ControlPlaneBackupCodec().decodeEligibility(
            bytes,
          );
          fenceReady =
              fence is SteadyBackupEligibility &&
              fence.destructionEpoch == state.epoch &&
              fence.establishedAtRepositoryRevision <= state.revision;
        }
      } on Object {
        fenceReady = false;
      }
      final recoveryComplete =
          fenceReady &&
          state.journals.every(
            (row) => row.phase == OperationJournalPhase.completed.name,
          );
      final finalizationComplete =
          fenceReady &&
          state.journals.isEmpty &&
          state.artifacts.isEmpty &&
          state.networkArtifacts.isEmpty;
      final visible = snapshot.managedSkills
          .map((skill) => skill.id.value)
          .toSet();
      final complete =
          visible.length == state.ids.length &&
          visible.containsAll(state.ids) &&
          snapshot.revision.value == state.revision &&
          snapshot.integrity.status != WorkspaceIntegrityStatus.corrupt &&
          !snapshot.integrity.skills.any((skill) => skill.mutationBlocked) &&
          recoveryComplete &&
          finalizationComplete &&
          state.artifacts.isEmpty;
      return SkillsSuccess(
        value: AuthoritativeWorkspaceCapture(
          identity: state.identity,
          snapshot: snapshot,
          recoveryComplete: recoveryComplete,
          finalizationComplete: finalizationComplete,
          isComplete: complete,
          localLineageFingerprints: state.localLineages,
        ),
        changed: false,
      );
    } on Object {
      return SkillsFailure(code: SkillsErrorCode.stateCorrupt);
    }
  }

  Future<SkillsResult<CommittedRevisionBatch>> prepareIncoming(
    PrepareIncomingRevisionRequest request,
    SkillsCommandContext context,
  ) async {
    if (request.contentManifest.length > 4 * 1024 * 1024 ||
        request.contentManifest.length + request.packBytes.length >
            RevisionTransferCodec.maximumBytes) {
      return SkillsFailure(code: SkillsErrorCode.skillContentLimitExceeded);
    }
    final lease = await writerLock.acquire(waitPolicy: context.lockWaitPolicy);
    String? artifact;
    final target = request.managedSkillId;
    final store = target == null
        ? layout.stagingRoot
        : layout.revisionStorePath(target);
    var registered = false;
    try {
      final metadata = await database
          .select(database.workspaceMetadata)
          .getSingle();
      final identity = WorkspaceIdentity(
        workspaceId: metadata.workspaceId,
        recoveryIncarnation: metadata.recoveryIncarnation,
      );
      if (identity != request.expectedIdentity ||
          metadata.repositoryRevision != request.expectedRevision.value) {
        return SkillsFailure(code: SkillsErrorCode.staleSnapshot);
      }
      final skill = target == null ? null : snapshots.current.findSkill(target);
      if (target != null && skill == null) {
        return SkillsFailure(code: SkillsErrorCode.skillNotFound);
      }
      if (context.cancellationToken.isCancelled) {
        return SkillsFailure(code: SkillsErrorCode.operationCancelled);
      }
      if (target == null) {
        await database
            .into(database.workspaceTransferArtifacts)
            .insert(
              db.WorkspaceTransferArtifactsCompanion.insert(
                operationId: context.operationId.value,
              ),
            );
        registered = true;
        artifact = layout.operationStagingPath(context.operationId);
      } else {
        final exportRoot = path.join(store, 'export-artifacts');
        await filesystem.removeOwnedPath(
          targetPath: exportRoot,
          ownerRoot: store,
        );
        artifact = path.join(exportRoot, context.operationId.value);
      }
      final indexed = path.join(artifact, 'indexed');
      await filesystem.ensureDirectory(indexed);
      final raw = path.join(artifact, 'received.pack');
      await filesystem.writeDurableFile(raw, request.packBytes);
      await revisions.createPackIndex(
        packPath: raw,
        stagingDirectory: indexed,
        cancellationToken: context.cancellationToken,
      );
      final index = await File(path.join(indexed, 'objects.idx')).readAsBytes();
      final pack = await File(path.join(indexed, 'objects.pack')).readAsBytes();
      if (context.cancellationToken.isCancelled) {
        return SkillsFailure(code: SkillsErrorCode.operationCancelled);
      }
      final batch = await _incomingBatchInWorker(
        identity,
        request.contentManifest,
        pack,
        index,
      );
      final content = await _decodeBatchInWorker(batch);
      await revisions.restoreRecoveryPack(
        stagedRepositoryPath: path.join(artifact, 'verified.git'),
        packPath: path.join(indexed, 'objects.pack'),
        indexPath: path.join(indexed, 'objects.idx'),
        retainedRoots: content.roots,
        limits: const RevisionObjectImportLimits(),
        cancellationToken: context.cancellationToken,
      );
      final bound = request.localOperationId == null
          ? batch
          : await _reserveIncoming(request, batch, metadata);
      return SkillsSuccess(value: bound, changed: false);
    } on IncomingRevisionRejected catch (error) {
      return SkillsFailure(
        code: error.reason == IncomingRevisionPendingReason.limitExceeded
            ? SkillsErrorCode.skillContentLimitExceeded
            : SkillsErrorCode.archiveInvalid,
      );
    } on RevisionEngineException catch (error) {
      return SkillsFailure(
        code: error.code == RevisionEngineFailureCode.limitExceeded
            ? SkillsErrorCode.skillContentLimitExceeded
            : SkillsErrorCode.archiveInvalid,
      );
    } finally {
      try {
        if (artifact != null) {
          await filesystem.removeOwnedPath(
            targetPath: artifact,
            ownerRoot: store,
          );
          if (registered) {
            await (database.delete(database.workspaceTransferArtifacts)..where(
                  (row) => row.operationId.equals(context.operationId.value),
                ))
                .go();
          }
        }
      } finally {
        await lease.release();
      }
    }
  }

  Future<SkillsResult<CommittedRevisionBatch>> export(
    ExportCommittedRevisionRequest request,
    SkillsCommandContext context,
  ) async {
    WorkspaceWriterLease? lease;
    ManagedSkillRevisionAccessPermit? permit;
    String? artifact;
    final store = layout.revisionStorePath(request.managedSkillId);
    try {
      lease = await writerLock.acquire(waitPolicy: context.lockWaitPolicy);
      if (context.cancellationToken.isCancelled) {
        return SkillsFailure(code: SkillsErrorCode.operationCancelled);
      }
      final snapshot = await snapshots.reload();
      if (snapshot.revision != request.expectedRevision) {
        return SkillsFailure(code: SkillsErrorCode.staleSnapshot);
      }
      final skill = snapshot.findSkill(request.managedSkillId);
      if (skill == null) {
        return SkillsFailure(code: SkillsErrorCode.skillNotFound);
      }
      permit = await accessGate.acquireRead(
        skill.id,
        cancellationToken: context.cancellationToken,
      );
      final capture = await database.transaction(() async {
        final state = await states.readUpdateState(skill.id);
        final history = state == null
            ? <RevisionTransferHistoryEntry>[]
            : await _history(skill.id, state.sourceLineage);
        final metadata = await database
            .select(database.workspaceMetadata)
            .getSingle();
        return (
          state: state,
          history: history,
          identity: WorkspaceIdentity(
            workspaceId: metadata.workspaceId,
            recoveryIncarnation: metadata.recoveryIncarnation,
          ),
        );
      });
      final state = capture.state;
      if (state == null) {
        return SkillsFailure(code: SkillsErrorCode.stateCorrupt);
      }
      final effective = await revisions.readTree(store, state.currentEffective);
      if (effective.contentHash != skill.currentRevision.contentHash) {
        return SkillsFailure(code: SkillsErrorCode.revisionStoreCorrupt);
      }
      final exportRoot = path.join(store, 'export-artifacts');
      // A single writer owns captures. Reclaim leftovers from an interrupted
      // earlier read before allocating this operation's temporary artifact.
      await filesystem.removeOwnedPath(
        targetPath: exportRoot,
        ownerRoot: store,
      );
      artifact = path.join(exportRoot, context.operationId.value);
      await filesystem.ensureDirectory(artifact);
      await revisions.createRecoveryPack(
        repositoryPath: store,
        bundleStagingPath: artifact,
        limits: RevisionObjectImportLimits(
          maximumTotalBytes:
              request.maximumBytes < RevisionTransferCodec.maximumBytes
              ? request.maximumBytes
              : RevisionTransferCodec.maximumBytes,
        ),
        retainedRoots: {
          state.previousUpstream,
          state.currentEffective,
          ...capture.history.map((entry) => entry.objectId),
        }.toList(),
      );
      if (context.cancellationToken.isCancelled) {
        return SkillsFailure(code: SkillsErrorCode.operationCancelled);
      }
      final pack = File(path.join(artifact, 'objects.pack'));
      final index = File(path.join(artifact, 'objects.idx'));
      final bytes = await pack.length() + await index.length();
      if (request.maximumBytes < 1 ||
          bytes > request.maximumBytes ||
          bytes > RevisionTransferCodec.maximumBytes) {
        return SkillsFailure(code: SkillsErrorCode.skillContentLimitExceeded);
      }
      final packBytes = await pack.readAsBytes(),
          indexBytes = await index.readAsBytes();
      final batch = await _encodeBatchInWorker(
        identity: capture.identity,
        source: skill.source,
        slotKey: skill.slotKey,
        contentHash: effective.contentHash,
        upstream: state.previousUpstream,
        effective: state.currentEffective,
        history: capture.history,
        packBytes: packBytes,
        indexBytes: indexBytes,
      );
      if (batch.wireManifest.length + bytes > request.maximumBytes) {
        return SkillsFailure(code: SkillsErrorCode.skillContentLimitExceeded);
      }
      return SkillsSuccess(value: batch, changed: false);
    } on IncomingRevisionRejected catch (error) {
      return SkillsFailure(
        code: error.reason == IncomingRevisionPendingReason.limitExceeded
            ? SkillsErrorCode.skillContentLimitExceeded
            : SkillsErrorCode.operationFailed,
      );
    } on RevisionEngineException catch (error) {
      return SkillsFailure(
        code: SkillsErrorCode.revisionStoreCorrupt,
        context: {'reason': error.code.name},
      );
    } on Object {
      return SkillsFailure(
        code: context.cancellationToken.isCancelled
            ? SkillsErrorCode.operationCancelled
            : SkillsErrorCode.operationFailed,
      );
    } finally {
      try {
        if (artifact != null) {
          await filesystem.removeOwnedPath(
            targetPath: artifact,
            ownerRoot: store,
          );
        }
      } finally {
        await permit?.release();
        await lease?.release();
      }
    }
  }

  Future<SkillsResult<IncomingRevisionApplyResult>> apply(
    ApplyIncomingRevisionRequest request,
    SkillsCommandContext context,
  ) async {
    IncomingRevisionPendingReason? rejected;
    try {
      final localBinding = await _validateLocalCommand(
        request.incoming,
        newInstallation: false,
      );
      if (localBinding != null) {
        if (localBinding.managedSkillId != request.managedSkillId ||
            context.operationId != request.incoming.localCommand!.operationId) {
          return _pending(IncomingRevisionPendingReason.invalidPayload);
        }
        final proof = await _inspectOutcome(
          request.incoming.localCommand!,
          context,
        );
        if (proof.status == IncomingRevisionOutcomeStatus.applied) {
          return SkillsSuccess(
            value: IncomingRevisionReplayed(proof),
            changed: false,
          );
        }
        if (proof.status != IncomingRevisionOutcomeStatus.confirmedNotStarted &&
            proof.status != IncomingRevisionOutcomeStatus.rolledBack) {
          return _pending(IncomingRevisionPendingReason.stale);
        }
      }
      final content = await _decodeBatchInWorker(request.incoming);
      final localMetadata = await database
          .select(database.workspaceMetadata)
          .getSingle();
      final localIdentity = WorkspaceIdentity(
        workspaceId: localMetadata.workspaceId,
        recoveryIncarnation: localMetadata.recoveryIncarnation,
      );
      if (localIdentity != request.expectedIdentity) {
        return _pending(IncomingRevisionPendingReason.stale);
      }
      final snapshot = snapshots.current;
      if (snapshot.revision != request.expectedRevision) {
        return _pending(IncomingRevisionPendingReason.stale);
      }
      final skill = snapshot.findSkill(request.managedSkillId);
      if (skill == null) {
        return _pending(IncomingRevisionPendingReason.skillNotFound);
      }
      if (!skill.source.hasSameIdentity(request.incoming.source)) {
        return _pending(IncomingRevisionPendingReason.sourceMismatch);
      }
      if (skill.slotKey != request.incoming.slotKey) {
        return _pending(IncomingRevisionPendingReason.slotMismatch);
      }
      final state = await states.readUpdateState(skill.id);
      if (state == null ||
          revisionTransferReference(state.currentEffective) !=
              request.expectedEffective) {
        return _pending(IncomingRevisionPendingReason.stale);
      }
      await _barrier(skill, context.cancellationToken);
      final localHistory = await _history(skill.id, state.sourceLineage);
      bool containsIncomingHistory(
        List<RevisionTransferHistoryEntry> retained,
      ) {
        final byEvent = {
          for (final event in retained)
            event.descriptor.eventFingerprint: event,
        };
        return content.history.every((incoming) {
          final old = byEvent[incoming.descriptor.eventFingerprint];
          return old != null &&
              old.objectId == incoming.objectId &&
              old.descriptor.kind == incoming.descriptor.kind &&
              old.descriptor.contentHash == incoming.descriptor.contentHash &&
              old.descriptor.publishedAt == incoming.descriptor.publishedAt;
        });
      }

      if (state.currentEffective == content.effective) {
        if (state.previousUpstream != content.upstream) {
          return _pending(IncomingRevisionPendingReason.baselineMismatch);
        }
        if (containsIncomingHistory(localHistory)) {
          final binding = request.incoming.localCommand;
          if (binding != null) {
            final completed = await completeKnownNoop(
              binding: binding,
              expectedRevision: request.expectedRevision,
              contentDigest: _manifestDigest(request.incoming),
              context: context,
              isSatisfied: (_) async {
                final now = await states.readUpdateState(skill.id);
                return now != null &&
                    now.sourceLineage == state.sourceLineage &&
                    now.currentEffective == content.effective &&
                    now.previousUpstream == content.upstream &&
                    containsIncomingHistory(
                      await _history(skill.id, state.sourceLineage),
                    );
              },
            );
            if (!completed) {
              return _pending(IncomingRevisionPendingReason.stale);
            }
            return SkillsSuccess(
              value: IncomingRevisionReplayed(
                await _inspectOutcome(binding, context),
              ),
              changed: false,
            );
          }
          return SkillsSuccess(
            value: IncomingRevisionUnchanged(snapshot),
            changed: false,
          );
        }
      }
      final localRoots = localHistory.map((entry) => entry.objectId).toList();
      final preflight = IncomingRevisionPreflight(
        skill: skill,
        state: state,
        content: content,
        localPublishedRoots: localRoots,
      );
      final outcome = await operations
          .executeDeferred<PreparedIncomingRevision>(
            operationId: context.operationId,
            expectedRepositoryRevision: request.expectedRevision,
            lockWaitPolicy: context.lockWaitPolicy,
            cancellationToken: context.cancellationToken,
            buildEnvelope: (id, revision) =>
                plans.createIncomingRevisionEnvelope(
                  operationId: id,
                  expectedRepositoryRevision: revision,
                  managedSkillId: skill.id,
                  localBinding: localBinding,
                ),
            prepareCandidate: (envelope, token) async {
              try {
                final current = await states.readUpdateState(skill.id);
                if (current == null ||
                    current.sourceLineage != state.sourceLineage ||
                    current.currentEffective != state.currentEffective ||
                    current.previousUpstream != state.previousUpstream ||
                    current.draftCreatedAtMicros !=
                        state.draftCreatedAtMicros) {
                  throw const IncomingRevisionRejected(
                    IncomingRevisionPendingReason.stale,
                  );
                }
                final retained = {
                  for (final entry in await _history(
                    skill.id,
                    state.sourceLineage,
                  ))
                    entry.descriptor.eventFingerprint: entry,
                };
                for (final incoming in content.history) {
                  final old = retained[incoming.descriptor.eventFingerprint];
                  if (old != null &&
                      (old.objectId != incoming.objectId ||
                          old.descriptor.kind != incoming.descriptor.kind ||
                          old.descriptor.contentHash !=
                              incoming.descriptor.contentHash ||
                          old.descriptor.publishedAt !=
                              incoming.descriptor.publishedAt)) {
                    throw const IncomingRevisionRejected(
                      IncomingRevisionPendingReason.invalidPayload,
                    );
                  }
                }
                await _barrier(skill, token);
                final permit = await accessGate.acquireRead(
                  skill.id,
                  cancellationToken: token,
                );
                try {
                  return await preparation.prepareIncomingRevision(
                    operationId: envelope.operationId,
                    preflight: preflight,
                    cancellationToken: token,
                  );
                } finally {
                  await permit.release();
                }
              } on IncomingRevisionRejected catch (error) {
                rejected = error.reason;
                rethrow;
              } on RevisionEngineException catch (error) {
                if (error.code == RevisionEngineFailureCode.limitExceeded) {
                  rejected = IncomingRevisionPendingReason.limitExceeded;
                }
                if (error.code == RevisionEngineFailureCode.bundleInvalid ||
                    error.code ==
                        RevisionEngineFailureCode.verificationFailed ||
                    error.code == RevisionEngineFailureCode.objectUnavailable) {
                  rejected = IncomingRevisionPendingReason.invalidPayload;
                }
                rethrow;
              }
            },
            buildPlan: (envelope, prepared) => plans.sealIncomingRevisionPlan(
              envelope: envelope,
              prepared: prepared,
              plannedAtMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
              cancellationToken: context.cancellationToken,
            ),
            onBusinessCommitted: context.markBusinessCommitted,
          );
      if (outcome is OperationRejected &&
              outcome.reason == OperationAbortReason.staleRepositoryRevision ||
          outcome is OperationRolledBack &&
              outcome.reason ==
                  OperationAbortReason.externalPreconditionChanged) {
        return _pending(IncomingRevisionPendingReason.stale);
      }
      if (outcome is OperationRolledBack && rejected != null) {
        return _pending(rejected!);
      }
      if (outcome is OperationRolledBack &&
          context.cancellationToken.isCancelled) {
        return SkillsFailure(code: SkillsErrorCode.operationCancelled);
      }
      return await mapMutationOutcome(
        outcome: outcome,
        context: context,
        snapshots: snapshots,
        valueFromSnapshot: (committed) => IncomingRevisionApplied(
          MutationReport(snapshot: committed, affectedSkillIds: {skill.id}),
        ),
      );
    } on IncomingRevisionRejected catch (error) {
      return _pending(error.reason);
    } on Object {
      return SkillsFailure(
        code: context.cancellationToken.isCancelled
            ? SkillsErrorCode.operationCancelled
            : SkillsErrorCode.operationFailed,
      );
    }
  }

  Future<CommittedRevisionBatch> _reserveIncoming(
    PrepareIncomingRevisionRequest request,
    CommittedRevisionBatch batch,
    db.WorkspaceMetadataData metadata,
  ) async {
    final operation = request.localOperationId!;
    final previous =
        await (database.select(database.workspaceIncomingReservations)
              ..where((row) => row.operationId.equals(operation.value)))
            .getSingleOrNull();
    final outcome =
        await (database.select(database.workspaceIncomingOutcomes)
              ..where((row) => row.operationId.equals(operation.value)))
            .getSingleOrNull();
    final state = request.managedSkillId == null
        ? null
        : await states.readUpdateState(request.managedSkillId!);
    final target = ManagedSkillId(
      previous?.managedSkillId ??
          outcome?.managedSkillId ??
          request.managedSkillId?.value ??
          const Uuid().v4(),
    );
    final lineage =
        previous?.sourceLineageId ??
        outcome?.sourceLineageId ??
        (request.replaceExistingLineage
            ? const Uuid().v4()
            : state?.sourceLineage.encoded ?? const Uuid().v4());
    final expectedEffective =
        previous?.expectedEffectiveObjectId ??
        outcome?.expectedEffectiveObjectId ??
        state?.currentEffective.value;
    final digest = _manifestDigest(batch);
    if (outcome?.replacement == true) {
      if (!request.replaceExistingLineage ||
          outcome!.contentManifestDigest != digest ||
          outcome.managedSkillId != request.managedSkillId?.value) {
        throw const IncomingRevisionRejected(
          IncomingRevisionPendingReason.invalidPayload,
        );
      }
      return _boundBatch(
        batch,
        IncomingRevisionCommandBinding(
          operationId: operation,
          requestFingerprint: outcome.requestFingerprint,
          targetManagedSkillId: target,
          localLineageFingerprint: _lineageFingerprint(lineage),
          expectedIdentity: batch.identity,
        ),
      );
    }
    final fingerprint = _requestFingerprint(
      identity: batch.identity,
      target: target.value,
      lineage: lineage,
      newInstallation: request.managedSkillId == null,
      expectedEffective: expectedEffective,
      digest: digest,
      replacement: request.replaceExistingLineage,
      previousLineage:
          previous?.previousSourceLineageId ??
          (request.replaceExistingLineage
              ? state?.sourceLineage.encoded
              : null),
    );
    if (previous != null || outcome != null) {
      if ((previous?.requestFingerprint ?? outcome!.requestFingerprint) !=
              fingerprint ||
          (previous != null &&
              previous.recoveryIncarnation != metadata.recoveryIncarnation) ||
          (previous?.replacement ?? outcome!.replacement) !=
              request.replaceExistingLineage ||
          (previous?.newInstallation ?? outcome!.newInstallation) !=
              (request.managedSkillId == null) ||
          (request.managedSkillId != null &&
              target != request.managedSkillId)) {
        throw const IncomingRevisionRejected(
          IncomingRevisionPendingReason.invalidPayload,
        );
      }
    } else {
      if ((await (database.select(
                database.operationRecords,
              )..where((row) => row.operationId.equals(operation.value))).get())
              .isNotEmpty ||
          (await (database.select(
                database.operationJournals,
              )..where((row) => row.operationId.equals(operation.value))).get())
              .isNotEmpty) {
        throw const IncomingRevisionRejected(
          IncomingRevisionPendingReason.invalidPayload,
        );
      }
      if ((await database.select(database.workspaceIncomingReservations).get())
              .length >=
          256) {
        throw const IncomingRevisionRejected(
          IncomingRevisionPendingReason.limitExceeded,
        );
      }
      await database
          .into(database.workspaceIncomingReservations)
          .insert(
            db.WorkspaceIncomingReservationsCompanion.insert(
              operationId: operation.value,
              requestFingerprint: fingerprint,
              recoveryIncarnation: metadata.recoveryIncarnation,
              managedSkillId: target.value,
              sourceLineageId: lineage,
              expectedEffectiveObjectId: Value(expectedEffective),
              contentManifestDigest: digest,
              newInstallation: request.managedSkillId == null,
              replacement: Value(request.replaceExistingLineage),
              previousSourceLineageId: Value(
                request.replaceExistingLineage
                    ? state?.sourceLineage.encoded
                    : null,
              ),
            ),
          );
    }
    return _boundBatch(
      batch,
      IncomingRevisionCommandBinding(
        operationId: operation,
        requestFingerprint: fingerprint,
        targetManagedSkillId: target,
        localLineageFingerprint: _lineageFingerprint(lineage),
        expectedIdentity: batch.identity,
        previousLocalLineageFingerprint: request.replaceExistingLineage
            ? _lineageFingerprint(
                previous?.previousSourceLineageId ??
                    state!.sourceLineage.encoded,
              )
            : null,
        previousEffectiveReference:
            request.replaceExistingLineage && expectedEffective != null
            ? revisionTransferReference(RevisionObjectId(expectedEffective))
            : null,
      ),
    );
  }

  /// Finishes a fresh, durably reserved command whose target already has the
  /// requested state. Receipt insertion changes no business revision/history.
  /// Unknown operations never enter this path merely because values match.
  Future<bool> completeKnownNoop({
    required IncomingRevisionCommandBinding binding,
    required RepositoryRevision expectedRevision,
    required String contentDigest,
    required SkillsCommandContext context,
    required Future<bool> Function(RepositorySnapshot snapshot) isSatisfied,
  }) async {
    final lease = await writerLock.acquire(waitPolicy: context.lockWaitPolicy);
    try {
      final captured = (await _captureUnderLock(context)).valueOrNull;
      if (captured == null ||
          !captured.isComplete ||
          captured.identity != binding.expectedIdentity ||
          captured.snapshot.revision != expectedRevision ||
          context.cancellationToken.isCancelled) {
        return false;
      }
      final completed = await database.transaction(() async {
        final reservation =
            await (database.select(database.workspaceIncomingReservations)
                  ..where(
                    (row) => row.operationId.equals(binding.operationId.value),
                  ))
                .getSingleOrNull();
        final skill =
            await (database.select(database.managedSkills)..where(
                  (row) => row.id.equals(binding.targetManagedSkillId.value),
                ))
                .getSingleOrNull();
        if (reservation == null ||
            skill == null ||
            reservation.newInstallation ||
            reservation.replacement ||
            reservation.requestFingerprint != binding.requestFingerprint ||
            reservation.contentManifestDigest != contentDigest ||
            reservation.recoveryIncarnation !=
                binding.expectedIdentity.recoveryIncarnation ||
            skill.activeSourceLineageId != reservation.sourceLineageId ||
            _lineageFingerprint(reservation.sourceLineageId) !=
                binding.localLineageFingerprint ||
            (await (database.select(database.operationJournals)..where(
                      (row) =>
                          row.operationId.equals(binding.operationId.value),
                    ))
                    .get())
                .isNotEmpty ||
            !await isSatisfied(captured.snapshot)) {
          return false;
        }
        final selected = await (database.select(
          database.currentRevisionSelection,
        )..where((row) => row.managedSkillId.equals(skill.id))).getSingle();
        await database
            .into(database.workspaceIncomingOutcomes)
            .insert(
              db.WorkspaceIncomingOutcomesCompanion.insert(
                operationId: binding.operationId.value,
                requestFingerprint: binding.requestFingerprint,
                managedSkillId: skill.id,
                sourceLineageId: reservation.sourceLineageId,
                expectedEffectiveObjectId: Value(
                  reservation.expectedEffectiveObjectId,
                ),
                contentManifestDigest: reservation.contentManifestDigest,
                newInstallation: false,
                effectiveObjectId: selected.effectiveObjectId,
                upstreamObjectId: selected.upstreamObjectId,
                committedRepositoryRevision: expectedRevision.value,
              ),
            );
        await (database.delete(database.workspaceIncomingReservations)..where(
              (row) => row.operationId.equals(binding.operationId.value),
            ))
            .go();
        return true;
      });
      if (completed) context.markBusinessCommitted();
      return completed;
    } finally {
      await lease.release();
    }
  }

  Future<SkillsResult<AuthoritativeWorkspaceCapture>> captureUnderWriterLock(
    SkillsCommandContext context,
  ) => _captureUnderLock(context);

  Future<IncomingRevisionOutcome> inspectOutcomeForBinding(
    IncomingRevisionCommandBinding binding,
    SkillsCommandContext context,
  ) => _inspectOutcome(binding, context);

  Future<IncomingRevisionOutcome> _inspectOutcome(
    IncomingRevisionCommandBinding binding,
    SkillsCommandContext context,
  ) async {
    final lease = await writerLock.acquire(waitPolicy: context.lockWaitPolicy);
    try {
      return await _outcomeUnderLock(binding, context);
    } finally {
      await lease.release();
    }
  }

  Future<IncomingRevisionOutcome> _outcomeUnderLock(
    IncomingRevisionCommandBinding binding,
    SkillsCommandContext context,
  ) async {
    IncomingRevisionOutcome answer(
      IncomingRevisionOutcomeStatus status, {
      AuthoritativeWorkspaceCapture? capture,
      int? revision,
    }) => IncomingRevisionOutcome(
      status: status,
      binding: binding,
      capture: capture,
      committedRevision: revision == null ? null : RepositoryRevision(revision),
    );
    final captured = (await _captureUnderLock(context)).valueOrNull;
    if (captured == null || captured.identity != binding.expectedIdentity) {
      return answer(IncomingRevisionOutcomeStatus.unknown, capture: captured);
    }
    final reservation =
        await (database.select(database.workspaceIncomingReservations)..where(
              (row) => row.operationId.equals(binding.operationId.value),
            ))
            .getSingleOrNull();
    final outcome =
        await (database.select(database.workspaceIncomingOutcomes)..where(
              (row) => row.operationId.equals(binding.operationId.value),
            ))
            .getSingleOrNull();
    if (reservation != null &&
        (reservation.requestFingerprint != binding.requestFingerprint ||
            reservation.managedSkillId != binding.targetManagedSkillId.value ||
            _lineageFingerprint(reservation.sourceLineageId) !=
                binding.localLineageFingerprint)) {
      return answer(IncomingRevisionOutcomeStatus.conflict, capture: captured);
    }
    if (outcome != null &&
        (outcome.requestFingerprint != binding.requestFingerprint ||
            outcome.managedSkillId != binding.targetManagedSkillId.value ||
            _lineageFingerprint(outcome.sourceLineageId) !=
                binding.localLineageFingerprint)) {
      return answer(IncomingRevisionOutcomeStatus.conflict, capture: captured);
    }
    final journal =
        await (database.select(database.operationJournals)..where(
              (row) => row.operationId.equals(binding.operationId.value),
            ))
            .getSingleOrNull();
    if (journal != null) {
      final definition = const OperationPlanCodec().decodeDefinition(
        schemaVersion: journal.planSchemaVersion,
        payload: journal.planJson,
      );
      if (definition.localCommandBinding?.requestFingerprint !=
              binding.requestFingerprint ||
          definition.localCommandBinding?.managedSkillId !=
              binding.targetManagedSkillId) {
        return answer(
          IncomingRevisionOutcomeStatus.conflict,
          capture: captured,
        );
      }
      if (outcome != null) {
        return answer(
          IncomingRevisionOutcomeStatus.committedFinalizationPending,
          capture: captured,
          revision: outcome.committedRepositoryRevision,
        );
      }
      return answer(
        journal.phase == OperationJournalPhase.completed.name
            ? IncomingRevisionOutcomeStatus.rolledBack
            : IncomingRevisionOutcomeStatus.inProgress,
        capture: captured,
      );
    }
    if (outcome != null) {
      return answer(
        captured.isComplete
            ? IncomingRevisionOutcomeStatus.applied
            : IncomingRevisionOutcomeStatus.committedFinalizationPending,
        capture: captured,
        revision: outcome.committedRepositoryRevision,
      );
    }
    final target =
        await (database.select(database.managedSkills)..where(
              (row) => row.id.equals(binding.targetManagedSkillId.value),
            ))
            .getSingleOrNull();
    if (!captured.isComplete) {
      return answer(IncomingRevisionOutcomeStatus.unknown, capture: captured);
    }
    if (target == null) {
      return answer(
        reservation?.newInstallation == true
            ? IncomingRevisionOutcomeStatus.confirmedNotStarted
            : IncomingRevisionOutcomeStatus.targetAbsent,
        capture: captured,
      );
    }
    if (_lineageFingerprint(target.activeSourceLineageId) !=
            binding.localLineageFingerprint &&
        !(reservation?.replacement == true &&
            target.activeSourceLineageId ==
                reservation?.previousSourceLineageId)) {
      return answer(
        IncomingRevisionOutcomeStatus.superseded,
        capture: captured,
      );
    }
    if (reservation != null) {
      final record =
          await (database.select(database.operationRecords)..where(
                (row) => row.operationId.equals(binding.operationId.value),
              ))
              .getSingleOrNull();
      return answer(
        record == null
            ? IncomingRevisionOutcomeStatus.confirmedNotStarted
            : IncomingRevisionOutcomeStatus.rolledBack,
        capture: captured,
      );
    }
    return answer(IncomingRevisionOutcomeStatus.unknown, capture: captured);
  }

  Future<OperationLocalCommandBinding?> _validateLocalCommand(
    CommittedRevisionBatch batch, {
    required bool newInstallation,
    bool replacement = false,
  }) async {
    final binding = batch.localCommand;
    if (binding == null) return null;
    final reservation =
        await (database.select(database.workspaceIncomingReservations)..where(
              (row) => row.operationId.equals(binding.operationId.value),
            ))
            .getSingleOrNull();
    final outcome =
        await (database.select(database.workspaceIncomingOutcomes)..where(
              (row) => row.operationId.equals(binding.operationId.value),
            ))
            .getSingleOrNull();
    if (reservation == null && outcome == null) {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.invalidPayload,
      );
    }
    final lineage = reservation?.sourceLineageId ?? outcome!.sourceLineageId;
    final target = reservation?.managedSkillId ?? outcome!.managedSkillId;
    final digest = _manifestDigest(batch);
    if (outcome?.replacement == true) {
      if (!replacement ||
          outcome!.contentManifestDigest != digest ||
          outcome.requestFingerprint != binding.requestFingerprint ||
          target != binding.targetManagedSkillId.value ||
          _lineageFingerprint(lineage) != binding.localLineageFingerprint) {
        throw const IncomingRevisionRejected(
          IncomingRevisionPendingReason.invalidPayload,
        );
      }
      return OperationLocalCommandBinding(
        requestFingerprint: binding.requestFingerprint,
        managedSkillId: binding.targetManagedSkillId,
        sourceLineage: SourceLineageReference(lineage),
      );
    }

    final expectedEffective =
        reservation?.expectedEffectiveObjectId ??
        outcome?.expectedEffectiveObjectId;
    final fp = _requestFingerprint(
      identity: batch.identity,
      target: target,
      lineage: lineage,
      newInstallation: newInstallation,
      expectedEffective: expectedEffective,
      digest: digest,
      replacement: replacement,
      previousLineage: reservation?.previousSourceLineageId,
    );
    if (fp != binding.requestFingerprint ||
        fp !=
            (reservation?.requestFingerprint ?? outcome!.requestFingerprint) ||
        target != binding.targetManagedSkillId.value ||
        _lineageFingerprint(lineage) != binding.localLineageFingerprint ||
        (reservation?.replacement ?? outcome!.replacement) != replacement ||
        (reservation?.newInstallation ?? outcome!.newInstallation) !=
            newInstallation ||
        batch.identity != binding.expectedIdentity) {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.invalidPayload,
      );
    }
    return OperationLocalCommandBinding(
      requestFingerprint: fp,
      managedSkillId: binding.targetManagedSkillId,
      sourceLineage: SourceLineageReference(lineage),
    );
  }

  Future<SkillsResult<IncomingRevisionApplyResult>> installIncoming(
    InstallIncomingRevisionRequest request,
    SkillsCommandContext context,
  ) async {
    IncomingRevisionPendingReason? rejected;
    try {
      final localBinding = await _validateLocalCommand(
        request.incoming,
        newInstallation: true,
      );
      if (localBinding != null) {
        if (context.operationId != request.incoming.localCommand!.operationId) {
          return _pending(IncomingRevisionPendingReason.invalidPayload);
        }
        final proof = await _inspectOutcome(
          request.incoming.localCommand!,
          context,
        );
        if (proof.status == IncomingRevisionOutcomeStatus.applied) {
          return SkillsSuccess(
            value: IncomingRevisionReplayed(proof),
            changed: false,
          );
        }
        if (proof.status != IncomingRevisionOutcomeStatus.confirmedNotStarted &&
            proof.status != IncomingRevisionOutcomeStatus.rolledBack) {
          return _pending(IncomingRevisionPendingReason.stale);
        }
      }
      final content = await _decodeBatchInWorker(request.incoming);
      final metadata = await database
          .select(database.workspaceMetadata)
          .getSingle();
      final identity = WorkspaceIdentity(
        workspaceId: metadata.workspaceId,
        recoveryIncarnation: metadata.recoveryIncarnation,
      );
      if (identity != request.expectedIdentity ||
          snapshots.current.revision != request.expectedRevision) {
        return _pending(IncomingRevisionPendingReason.stale);
      }
      final binding = request.incoming.localCommand;
      final reservation = binding == null
          ? null
          : await (database.select(database.workspaceIncomingReservations)
                  ..where(
                    (row) => row.operationId.equals(binding.operationId.value),
                  ))
                .getSingleOrNull();
      if (binding != null &&
          (reservation == null ||
              !reservation.newInstallation ||
              reservation.requestFingerprint != binding.requestFingerprint)) {
        return _pending(IncomingRevisionPendingReason.invalidPayload);
      }
      final id =
          binding?.targetManagedSkillId ?? ManagedSkillId(const Uuid().v4());
      final lineage = SourceLineageReference(
        reservation?.sourceLineageId ?? const Uuid().v4(),
      );
      Future<void> slotBarrier() async {
        final occupied = await (database.select(
          database.managedSkills,
        )..where((row) => row.slotKey.equals(request.incoming.slotKey))).get();
        if (occupied.isNotEmpty ||
            await FileSystemEntity.type(
                  layout.repositoryCopyPath(request.incoming.slotKey),
                  followLinks: false,
                ) !=
                FileSystemEntityType.notFound) {
          throw const IncomingRevisionRejected(
            IncomingRevisionPendingReason.slotConflict,
          );
        }
      }

      await slotBarrier();
      final outcome = await operations
          .executeDeferred<PreparedIncomingInstallation>(
            operationId: context.operationId,
            expectedRepositoryRevision: request.expectedRevision,
            cancellationToken: context.cancellationToken,
            lockWaitPolicy: context.lockWaitPolicy,
            buildEnvelope: (operation, revision) =>
                plans.createIncomingInstallEnvelope(
                  operationId: operation,
                  expectedRepositoryRevision: revision,
                  managedSkillId: id,
                  localBinding: localBinding,
                ),
            prepareCandidate: (envelope, token) async {
              try {
                await slotBarrier();
                return await preparation.prepareIncomingInstallation(
                  operationId: envelope.operationId,
                  managedSkillId: id,
                  lineage: lineage,
                  batch: request.incoming,
                  content: content,
                  cancellationToken: token,
                );
              } on IncomingRevisionRejected catch (error) {
                rejected = error.reason;
                rethrow;
              } on RevisionEngineException catch (error) {
                rejected = error.code == RevisionEngineFailureCode.limitExceeded
                    ? IncomingRevisionPendingReason.limitExceeded
                    : IncomingRevisionPendingReason.invalidPayload;
                rethrow;
              }
            },
            buildPlan: (envelope, prepared) => plans.sealIncomingInstallPlan(
              envelope: envelope,
              prepared: prepared,
              plannedAtMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
            ),
            onBusinessCommitted: context.markBusinessCommitted,
          );
      if (outcome is OperationRolledBack && rejected != null) {
        return _pending(rejected!);
      }
      if (outcome is OperationRejected &&
          outcome.reason == OperationAbortReason.staleRepositoryRevision) {
        return _pending(IncomingRevisionPendingReason.stale);
      }
      return await mapMutationOutcome(
        outcome: outcome,
        context: context,
        snapshots: snapshots,
        valueFromSnapshot: (snapshot) => IncomingRevisionInstalled(
          managedSkillId: id,
          report: MutationReport(snapshot: snapshot, affectedSkillIds: {id}),
        ),
      );
    } on IncomingRevisionRejected catch (error) {
      return _pending(error.reason);
    }
  }

  Future<SkillsResult<IncomingRevisionApplyResult>> replaceIncoming(
    ReplaceIncomingRevisionRequest request,
    SkillsCommandContext context,
  ) async {
    IncomingRevisionPendingReason? rejected;
    try {
      final localBinding = await _validateLocalCommand(
        request.incoming,
        newInstallation: false,
        replacement: true,
      );
      if (localBinding == null ||
          localBinding.managedSkillId != request.managedSkillId) {
        return _pending(IncomingRevisionPendingReason.invalidPayload);
      }
      final proof = await _inspectOutcome(
        request.incoming.localCommand!,
        context,
      );
      if (proof.status == IncomingRevisionOutcomeStatus.applied) {
        return SkillsSuccess(
          value: IncomingRevisionReplayed(proof),
          changed: false,
        );
      }
      if (proof.status == IncomingRevisionOutcomeStatus.rolledBack) {
        await operations.recover();
      }
      if (proof.status != IncomingRevisionOutcomeStatus.confirmedNotStarted &&
          proof.status != IncomingRevisionOutcomeStatus.rolledBack) {
        return _pending(IncomingRevisionPendingReason.stale);
      }
      if (request.incoming.localCommand!.previousLocalLineageFingerprint !=
              request.expectedLocalLineageFingerprint ||
          request.incoming.localCommand!.previousEffectiveReference !=
              request.expectedEffective) {
        return _pending(IncomingRevisionPendingReason.stale);
      }
      final content = await _decodeBatchInWorker(request.incoming);
      final snapshot = snapshots.current;
      if (snapshot.revision != request.expectedRevision) {
        return _pending(IncomingRevisionPendingReason.stale);
      }
      final outcome = await operations.executeDeferred<OperationPlan>(
        operationId: context.operationId,
        expectedRepositoryRevision: request.expectedRevision,
        cancellationToken: context.cancellationToken,
        lockWaitPolicy: context.lockWaitPolicy,
        buildEnvelope: (operation, revision) => planAssembler
            .destructiveEnvelope(
              operationId: operation,
              expectedRepositoryRevision: revision,
              kind: WorkspaceOperationKind.replaceIncomingRevision,
            )
            .withLocalBinding(localBinding),
        prepareCandidate: (envelope, token) async {
          try {
            final metadata = await database
                .select(database.workspaceMetadata)
                .getSingle();
            if (metadata.workspaceId != request.expectedIdentity.workspaceId ||
                metadata.recoveryIncarnation !=
                    request.expectedIdentity.recoveryIncarnation) {
              throw const IncomingRevisionRejected(
                IncomingRevisionPendingReason.stale,
              );
            }
            final locked = await destructiveState.readPlanningSnapshot(
              publicSnapshot: snapshot,
              purpose: DestructivePlanningPurpose.sourceReplacement,
              targetManagedSkillIds: {request.managedSkillId},
              cancellationToken: token,
            );
            final old = locked.findSkill(request.managedSkillId);
            if (old == null ||
                _lineageFingerprint(old.activeSourceLineage.encoded) !=
                    request.expectedLocalLineageFingerprint ||
                revisionTransferReference(old.currentEffective.objectId) !=
                    request.expectedEffective) {
              throw const IncomingRevisionRejected(
                IncomingRevisionPendingReason.stale,
              );
            }
            if (old.draftState == DestructiveDraftState.dirty) {
              throw const IncomingRevisionRejected(
                IncomingRevisionPendingReason.dirtyDraft,
              );
            }
            if (old.hasUpdateCandidateSession) {
              throw const IncomingRevisionRejected(
                IncomingRevisionPendingReason.existingSession,
              );
            }
            if (locked.managedSkills.any(
              (skill) =>
                  skill.managedSkillId != request.managedSkillId &&
                  skill.slotKey == request.incoming.slotKey,
            )) {
              throw const IncomingRevisionRejected(
                IncomingRevisionPendingReason.slotConflict,
              );
            }
            final prepared = await preparation.prepareIncomingInstallation(
              operationId: envelope.operationId,
              managedSkillId: request.managedSkillId,
              lineage: localBinding.sourceLineage,
              batch: request.incoming,
              content: content,
              cancellationToken: token,
            );
            final candidateRoot = layout.operationRevisionCandidateRoot(
              envelope.operationId,
              request.managedSkillId,
            );
            await filesystem.ensureDirectory(
              layout.operationSourceReplacementRoot(envelope.operationId),
            );
            await Directory(path.join(candidateRoot, 'store.git')).rename(
              layout.operationSourceReplacementStore(envelope.operationId),
            );
            await Directory(path.join(candidateRoot, 'bundle')).rename(
              layout.operationSourceReplacementBundle(envelope.operationId),
            );
            final recovery = SourceReplacementRecoveryIntent(
              skill: DestructiveSkillRecoveryIntent(
                managedSkillId: old.managedSkillId,
                slotKey: old.slotKey,
                sourceLineages: old.sourceLineages
                    .map(
                      (lineage) => RecoverySourceLineageIntent(
                        sourceLineage: lineage.sourceLineage,
                      ),
                    )
                    .toList(),
                activationIds: old.activationIds,
                hasDraft: old.draftState != DestructiveDraftState.absent,
                expectedCleanDraftFingerprint: old.cleanDraftFingerprint,
                hasUpdateCandidateSession: old.hasUpdateCandidateSession,
              ),
              intendedSourceLineage: localBinding.sourceLineage,
              intendedSlotKey: request.incoming.slotKey,
              intendedObjectId: content.effective,
              intendedContentHash: content.contentHash,
              intendedObjectFormat: WorkspaceObjectFormat.sha1,
            );
            await destructiveEntries.prepareRecoveryEntries(
              operationId: envelope.operationId,
              intent: recovery,
              cancellationToken: token,
            );
            final source = const SourceDescriptorCodec().encode(
              request.incoming.source,
            );
            final now = DateTime.now().toUtc().microsecondsSinceEpoch;
            final plan = planAssembler.destructive(
              operationId: envelope.operationId,
              expectedRepositoryRevision: envelope.expectedRepositoryRevision,
              kind: WorkspaceOperationKind.replaceIncomingRevision,
              recoveryIntent: recovery,
              localCommandBinding: localBinding,
              businessChanges: WorkspaceBusinessChangeSet(
                incrementsDestructionEpoch: true,
                mutations: [
                  PutSourceLineage(
                    sourceLineageId: localBinding.sourceLineage.encoded,
                    managedSkillId: old.managedSkillId,
                    objectFormat: WorkspaceObjectFormat.sha1,
                    createdAtMicros: now,
                  ),
                  PutSkillSource(
                    sourceLineageId: localBinding.sourceLineage.encoded,
                    kind: WorkspaceSourceKind.values.byName(source.kind),
                    payloadSchemaVersion: source.payloadSchemaVersion,
                    payloadJson: source.payloadJson,
                  ),
                  for (final entry in prepared.historyTrees.entries)
                    PutRevisionMetadata(
                      sourceLineageId: localBinding.sourceLineage.encoded,
                      objectId: entry.key.value,
                      contentHash: entry.value.contentHash,
                      fileCount: entry.value.fileCount,
                      byteSize: entry.value.byteSize,
                      declaredName: parseSkillFrontmatter(
                        utf8.decode(
                          entry.value.files
                              .singleWhere(
                                (file) => file.relativePath == 'SKILL.md',
                              )
                              .bytes,
                        ),
                      )!.declaredName,
                      validationState: WorkspaceRevisionValidationState.valid,
                      validationCode: null,
                      createdAtMicros: now,
                    ),
                  PutManagedSkill(
                    managedSkillId: old.managedSkillId,
                    slotKey: request.incoming.slotKey,
                    declaredName: prepared.declaredName,
                    displayName: old.displayName == old.declaredName
                        ? prepared.declaredName
                        : old.displayName,
                    description: prepared.description,
                    activeSourceLineageId: localBinding.sourceLineage.encoded,
                    createdAtMicros: old.createdAtMicros,
                    updatedAtMicros: now,
                  ),
                  if (old.draftState == DestructiveDraftState.clean)
                    DeleteDraftWorkspace(old.managedSkillId),
                  for (final retired in old.sourceLineages)
                    DeleteSourceLineage(retired.sourceLineage.encoded),
                  for (final event in content.history)
                    PutRevisionPublishedEvent(
                      sourceLineageId: localBinding.sourceLineage.encoded,
                      eventFingerprint: event.descriptor.eventFingerprint,
                      objectId: event.objectId.value,
                      kind: event.descriptor.kind.name,
                      contentHash: event.descriptor.contentHash,
                      publishedAtMicros:
                          event.descriptor.publishedAt.microsecondsSinceEpoch,
                    ),
                ],
              ),
              revisionSelectionChanges: [
                RevisionSelectionChangePlan(
                  managedSkillId: old.managedSkillId,
                  previousUpstream: old.currentUpstream,
                  previousEffective: old.currentEffective,
                  intendedUpstream: RevisionAddress(
                    sourceLineage: localBinding.sourceLineage,
                    objectId: content.upstream,
                  ),
                  intendedEffective: RevisionAddress(
                    sourceLineage: localBinding.sourceLineage,
                    objectId: content.effective,
                  ),
                ),
              ],
              subjects: [
                OperationSubjectIntent(
                  managedSkillId: old.managedSkillId,
                  displayName: prepared.declaredName,
                  sourceLineage: localBinding.sourceLineage,
                ),
              ],
            );
            return plan;
          } on IncomingRevisionRejected catch (error) {
            rejected = error.reason;
            rethrow;
          }
        },
        buildPlan: (_, plan) => plan,
        onBusinessCommitted: context.markBusinessCommitted,
      );
      if (outcome is OperationRolledBack && rejected != null) {
        return _pending(rejected!);
      }
      return await mapMutationOutcome(
        outcome: outcome,
        context: context,
        snapshots: snapshots,
        valueFromSnapshot: (committed) => IncomingRevisionApplied(
          MutationReport(
            snapshot: committed,
            affectedSkillIds: {request.managedSkillId},
          ),
        ),
      );
    } on IncomingRevisionRejected catch (error) {
      return _pending(error.reason);
    }
  }

  Future<void> _barrier(ManagedSkill skill, CancellationToken token) async {
    final session =
        await (database.select(database.updateCandidateSessions)
              ..where((row) => row.managedSkillId.equals(skill.id.value)))
            .getSingleOrNull();
    if (session != null) {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.existingSession,
      );
    }
    if (skill.draft != null) {
      final inspected = await drafts.inspectForUpdate(
        skill: skill,
        cancellationToken: token,
      );
      if (inspected is! UpdateDraftInspectionSuccess ||
          inspected.inspection.isDirty) {
        throw const IncomingRevisionRejected(
          IncomingRevisionPendingReason.dirtyDraft,
        );
      }
    }
  }

  Future<List<RevisionTransferHistoryEntry>> _history(
    ManagedSkillId id,
    SourceLineageReference lineage,
  ) async {
    final subjects = database.operationSubjects,
        records = database.operationRecords;
    final query =
        database.select(subjects).join([
            innerJoin(
              records,
              records.operationId.equalsExp(subjects.operationId),
            ),
          ])
          ..where(
            subjects.managedSkillId.equals(id.value) &
                subjects.sourceLineageId.equals(lineage.encoded) &
                subjects.afterObjectId.isNotNull() &
                subjects.afterContentHash.isNotNull() &
                records.status.equals('succeeded'),
          )
          ..orderBy([
            OrderingTerm.asc(records.completedAtMicros),
            OrderingTerm.asc(records.operationId),
          ]);
    final rows = await query.get();
    if (rows.length > 10000) {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.limitExceeded,
      );
    }
    final local = [
      for (final row in rows)
        RevisionTransferHistoryEntry(
          objectId: RevisionObjectId(row.readTable(subjects).afterObjectId!),
          descriptor: CommittedRevisionHistoryDescriptor(
            eventFingerprint: sha256
                .convert(
                  utf8.encode(
                    'workspace-event:${row.readTable(records).operationId}:${row.readTable(subjects).subjectId}',
                  ),
                )
                .toString(),
            revision: revisionTransferReference(
              RevisionObjectId(row.readTable(subjects).afterObjectId!),
            ),
            kind: WorkspaceOperationKind.values.byName(
              row.readTable(records).kind,
            ),
            contentHash: row.readTable(subjects).afterContentHash!,
            publishedAt: DateTime.fromMicrosecondsSinceEpoch(
              row.readTable(records).completedAtMicros,
              isUtc: true,
            ),
          ),
        ),
    ];
    final imported = await (database.select(
      database.revisionPublishedEvents,
    )..where((row) => row.sourceLineageId.equals(lineage.encoded))).get();
    final combined = <String, RevisionTransferHistoryEntry>{
      for (final entry in local) entry.descriptor.eventFingerprint: entry,
    };
    for (final event in imported) {
      final oid = RevisionObjectId(event.objectId);
      final entry = RevisionTransferHistoryEntry(
        objectId: oid,
        descriptor: CommittedRevisionHistoryDescriptor(
          eventFingerprint: event.eventFingerprint,
          revision: revisionTransferReference(oid),
          kind: WorkspaceOperationKind.values.byName(event.kind),
          contentHash: event.contentHash,
          publishedAt: DateTime.fromMicrosecondsSinceEpoch(
            event.publishedAtMicros,
            isUtc: true,
          ),
        ),
      );
      final previous = combined[event.eventFingerprint];
      if (previous != null &&
          (previous.objectId != oid ||
              previous.descriptor.contentHash != event.contentHash ||
              previous.descriptor.kind.name != event.kind ||
              previous.descriptor.publishedAt.microsecondsSinceEpoch !=
                  event.publishedAtMicros)) {
        throw const IncomingRevisionRejected(
          IncomingRevisionPendingReason.invalidPayload,
        );
      }
      combined[event.eventFingerprint] = entry;
    }
    if (combined.length > 10000) {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.limitExceeded,
      );
    }
    return combined.values.toList()..sort(
      (a, b) => a.descriptor.eventFingerprint.compareTo(
        b.descriptor.eventFingerprint,
      ),
    );
  }
}

SkillsResult<IncomingRevisionApplyResult> _pending(
  IncomingRevisionPendingReason reason,
) => SkillsSuccess(value: IncomingRevisionPending(reason), changed: false);

Future<CommittedRevisionBatch> _encodeBatchInWorker({
  required WorkspaceIdentity identity,
  required SourceDescriptor source,
  required String slotKey,
  required String contentHash,
  required RevisionObjectId upstream,
  required RevisionObjectId effective,
  required List<RevisionTransferHistoryEntry> history,
  required Uint8List packBytes,
  required Uint8List indexBytes,
}) => Isolate.run(
  () => const RevisionTransferCodec().encode(
    identity: identity,
    source: source,
    slotKey: slotKey,
    contentHash: contentHash,
    upstream: upstream,
    effective: effective,
    history: history,
    packBytes: packBytes,
    indexBytes: indexBytes,
  ),
);
Future<IncomingRevisionContent> _decodeBatchInWorker(
  CommittedRevisionBatch batch,
) => Isolate.run(() => const RevisionTransferCodec().decode(batch));

Future<CommittedRevisionBatch> _incomingBatchInWorker(
  WorkspaceIdentity identity,
  Uint8List manifest,
  Uint8List packBytes,
  Uint8List indexBytes,
) => Isolate.run(
  () => const RevisionTransferCodec().fromContentManifest(
    identity: identity,
    manifest: manifest,
    packBytes: packBytes,
    indexBytes: indexBytes,
  ),
);

String _lineageFingerprint(String lineage) =>
    sha256.convert(utf8.encode('local-lineage:$lineage')).toString();
String _manifestDigest(CommittedRevisionBatch batch) {
  final manifest =
      jsonDecode(utf8.decode(batch.wireManifest)) as Map<String, Object?>;
  final history =
      (manifest['publishedHistory'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .toList()
        ..sort(
          (a, b) => (a['eventFingerprint'] as String).compareTo(
            b['eventFingerprint'] as String,
          ),
        );
  return sha256
      .convert(canonicalJson.encode({...manifest, 'publishedHistory': history}))
      .toString();
}

String _requestFingerprint({
  required WorkspaceIdentity identity,
  required String target,
  required String lineage,
  required bool newInstallation,
  required String? expectedEffective,
  required String digest,
  bool replacement = false,
  String? previousLineage,
}) => sha256
    .convert(
      canonicalJson.encode({
        'replacement': replacement,
        if (replacement) 'previousLineage': previousLineage,
        'kind': newInstallation
            ? 'installIncomingRevision'
            : 'applyIncomingRevision',
        'workspaceId': identity.workspaceId,
        'incarnation': identity.recoveryIncarnation,
        'target': target,
        'lineage': lineage,
        'manifestDigest': digest,
        'expectedEffective': expectedEffective,
      }),
    )
    .toString();
CommittedRevisionBatch _boundBatch(
  CommittedRevisionBatch batch,
  IncomingRevisionCommandBinding binding,
) => CommittedRevisionBatch(
  identity: batch.identity,
  source: batch.source,
  slotKey: batch.slotKey,
  contentHash: batch.contentHash,
  currentUpstream: batch.currentUpstream,
  currentEffective: batch.currentEffective,
  publishedHistory: batch.publishedHistory,
  wireManifest: batch.wireManifest,
  packBytes: batch.packBytes,
  indexBytes: batch.indexBytes,
  packSha256: batch.packSha256,
  indexSha256: batch.indexSha256,
  localCommand: binding,
);
