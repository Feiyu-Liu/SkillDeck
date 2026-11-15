import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../api/composite_command_dispatcher.dart';
import '../api/result.dart';
import '../api/requests.dart';
import '../api/revision_transfer.dart';
import '../api/revision_transfer_remote.dart';
import '../application/ports/operation_ports.dart';
import '../application/ports/repository_transport_native_port.dart';
import '../application/runtime/revision_engine_port.dart';
import '../domain/identifiers.dart';
import '../domain/cancellation.dart';
import '../domain/public_models.dart';
import '../infrastructure/database/workspace_database.dart' as db;
import '../infrastructure/revision_transfer/revision_transfer_codec.dart';
import '../infrastructure/revision_transfer/bounded_git_pack_fetcher.dart';
import '../infrastructure/workspace_layout.dart';
import '../native/repository_transport/repository_transport_native.dart';
import '../platform/filesystem/durable_workspace_filesystem.dart';

/// Native transfers own disposable registered bytes; they never hold a writer
/// lease across network I/O. Destruction blocks new transfers and cancels/drains
/// current native calls before taking its own writer transaction.
final class WorkspaceRevisionNetworkTransfers {
  WorkspaceRevisionNetworkTransfers({
    required this.database,
    required this.writerLock,
    required this.layout,
    required this.filesystem,
    required this.revisions,
  });
  final db.WorkspaceDatabase database;
  final WorkspaceWriterLockPort writerLock;
  final WorkspaceLayout layout;
  final DurableWorkspaceFilesystem filesystem;
  final RevisionEnginePort revisions;
  final _active = <OperationId, _ActiveTransfer>{};
  final _blocked = <ManagedSkillId>{};

  List<SkillsCommandHandler> handlers(
    Future<SkillsResult<CommittedRevisionBatch>> Function(
      PrepareIncomingRevisionRequest,
      SkillsCommandContext,
    )
    prepare,
  ) => [
    TypedSkillsCommandHandler<
      PushCommittedRevisionRequest,
      RevisionTransferReport
    >(kind: WorkspaceOperationKind.pushCommittedRevision, handle: push),
    TypedSkillsCommandHandler<
      FetchIncomingRevisionRequest,
      CommittedRevisionBatch
    >(
      kind: WorkspaceOperationKind.fetchIncomingRevision,
      handle: (request, context) async {
        final received = await _run(
          request.managedSkillId,
          request.expectedIdentity,
          request.expectedRevision,
          request.remote,
          context,
          manifest: request.contentManifest,
        );
        if (received.failure != null) return _failure(received.failure!);
        return prepare(
          PrepareIncomingRevisionRequest(
            managedSkillId: request.managedSkillId,
            localOperationId: request.localOperationId,
            replaceExistingLineage: request.replaceExistingLineage,
            expectedIdentity: request.expectedIdentity,
            expectedRevision: request.expectedRevision,
            contentManifest: request.contentManifest,
            packBytes: received.pack!,
          ),
          context,
        );
      },
    ),
  ];

  /// Called only under the local writer lease. Retain a registry row when
  /// cleanup fails so authority remains incomplete and a later retry can heal.
  Future<void> reconcileInactiveTransfers() async {
    final rows = await database
        .select(database.workspaceNetworkTransfers)
        .get();
    for (final row in rows) {
      final id = OperationId(row.operationId);
      if (_active.containsKey(id)) continue;
      final owner = row.managedSkillId == null
          ? layout.stagingRoot
          : layout.revisionStorePath(ManagedSkillId(row.managedSkillId!));
      final root = row.managedSkillId == null
          ? layout.operationStagingPath(id)
          : path.join(owner, 'network-transfers', id.value);
      await filesystem.removeOwnedPath(targetPath: root, ownerRoot: owner);
      await (database.delete(
        database.workspaceNetworkTransfers,
      )..where((entry) => entry.operationId.equals(id.value))).go();
    }
    // Incoming raw preparation holds this same writer lease throughout its
    // short owned operation. A row visible here is an interrupted cleanup.
    final incoming = await database
        .select(database.workspaceTransferArtifacts)
        .get();
    for (final row in incoming) {
      final id = OperationId(row.operationId);
      await filesystem.removeOwnedPath(
        targetPath: layout.operationStagingPath(id),
        ownerRoot: layout.stagingRoot,
      );
      await (database.delete(
        database.workspaceTransferArtifacts,
      )..where((entry) => entry.operationId.equals(id.value))).go();
    }
  }

  List<SkillsCommandHandler> guardDestruction(
    List<SkillsCommandHandler> handlers,
  ) => [
    for (final handler in handlers)
      handler.kind == WorkspaceOperationKind.resumeFinalizationRecovery
          ? _TransferRecoveryGuard(owner: this, delegate: handler)
          : handler.kind == WorkspaceOperationKind.remove ||
                handler.kind == WorkspaceOperationKind.replaceSource ||
                handler.kind == WorkspaceOperationKind.replaceIncomingRevision
          ? _TransferDestructionGuard(owner: this, delegate: handler)
          : handler,
  ];

  Future<SkillsResult<RevisionTransferReport>> push(
    PushCommittedRevisionRequest request,
    SkillsCommandContext context,
  ) async {
    final result = await _run(
      request.managedSkillId,
      request.expectedIdentity,
      request.expectedRevision,
      request.remote,
      context,
      batch: request.batch,
    );
    if (result.failure != null) return _failure(result.failure!);
    return SkillsSuccess(
      value: RevisionTransferReport(refs: result.refs!),
      changed: false,
    );
  }

  Future<
    ({
      RepositoryTransportStatus? failure,
      List<RevisionTransferRefStatus>? refs,
      List<int>? pack,
    })
  >
  _run(
    ManagedSkillId? skill,
    WorkspaceIdentity identity,
    RepositoryRevision revision,
    RevisionTransferRemote remote,
    SkillsCommandContext context, {
    CommittedRevisionBatch? batch,
    List<int>? manifest,
  }) async {
    final lease = await writerLock.acquire(waitPolicy: context.lockWaitPolicy);
    final flag = calloc<ffi.Int32>();
    final active = _ActiveTransfer(skill, flag);
    var registered = false, finished = false;
    String? root;
    try {
      final metadata = await database
          .select(database.workspaceMetadata)
          .getSingle();
      if (metadata.workspaceId != identity.workspaceId ||
          metadata.recoveryIncarnation != identity.recoveryIncarnation ||
          metadata.repositoryRevision != revision.value ||
          (skill != null && _blocked.contains(skill)) ||
          _active.length >= 4) {
        calloc.free(flag);
        return (
          failure: RepositoryTransportStatus.invalidArgument,
          refs: null,
          pack: null,
        );
      }
      final ownerSkill = skill == null
          ? null
          : await (database.select(
              database.managedSkills,
            )..where((row) => row.id.equals(skill.value))).getSingleOrNull();
      if (skill != null && ownerSkill == null) {
        calloc.free(flag);
        return (
          failure: RepositoryTransportStatus.invalidArgument,
          refs: null,
          pack: null,
        );
      }
      root = skill == null
          ? layout.operationStagingPath(context.operationId)
          : path.join(
              layout.revisionStorePath(skill),
              'network-transfers',
              context.operationId.value,
            );
      await database
          .into(database.workspaceNetworkTransfers)
          .insert(
            db.WorkspaceNetworkTransfersCompanion.insert(
              operationId: context.operationId.value,
              managedSkillId: Value(skill?.value),
              sourceLineageId: Value(ownerSkill?.activeSourceLineageId),
            ),
          );
      registered = true;
      _active[context.operationId] = active;
      await filesystem.ensureDirectory(root);
    } catch (_) {
      if (registered && root != null) {
        try {
          await filesystem.removeOwnedPath(
            targetPath: root,
            ownerRoot: skill == null
                ? layout.stagingRoot
                : layout.revisionStorePath(skill),
          );
          await (database.delete(database.workspaceNetworkTransfers)..where(
                (row) => row.operationId.equals(context.operationId.value),
              ))
              .go();
        } on Object {
          /* Keep the owned registry for same-process recovery. */
        }
      }
      _active.remove(context.operationId);
      calloc.free(flag);
      if (!active.done.isCompleted) active.done.complete();
      rethrow;
    } finally {
      await lease.release();
    }
    final cancellation =
        Stream<void>.fromFuture(context.cancellationToken.whenCancelled).listen(
          (_) {
            if (!finished) active.requestCancel();
          },
        );
    try {
      final rootPath = root;
      final native = RepositoryTransportNative(
        allowLoopbackHttpForTesting: remote.allowLoopbackHttpForTesting,
      );
      final headers = await remote.ephemeralHeaders().timeout(
        const Duration(seconds: 30),
      );
      if (context.cancellationToken.isCancelled) flag.value = 1;
      List<String> oids;
      final store = path.join(rootPath, 'transport.git');
      if (batch != null) {
        final decoded = const RevisionTransferCodec().decode(batch);
        oids = {decoded.upstream.value, decoded.effective.value}.toList()
          ..sort();
        final pack = path.join(rootPath, 'objects.pack'),
            index = path.join(rootPath, 'objects.idx');
        await filesystem.writeDurableFile(pack, batch.packBytes);
        await filesystem.writeDurableFile(index, batch.indexBytes);
        await revisions.restoreRecoveryPack(
          stagedRepositoryPath: store,
          packPath: pack,
          indexPath: index,
          retainedRoots: decoded.roots,
          limits: const RevisionObjectImportLimits(),
          cancellationToken: active.cancellation.token,
        );
        final outcome = await native.push(
          repositoryPath: store,
          url: remote.url,
          refspecs: [
            for (final oid in oids) '$oid:refs/skilldeck/commits/$oid',
          ],
          customHeaders: headers,
          cancelFlagAddress: flag.address,
        );
        if (outcome.status != RepositoryTransportStatus.ok) {
          return (failure: outcome.status, refs: null, pack: null);
        }
        return (
          failure: null,
          refs: outcome.refs
              .map((status) => RevisionTransferRefStatus.values[status.index])
              .toList(),
          pack: null,
        );
      }
      if (manifest == null || manifest.length > 4 * 1024 * 1024) {
        return (
          failure: RepositoryTransportStatus.limitExceeded,
          refs: null,
          pack: null,
        );
      }
      final map = jsonDecode(utf8.decode(manifest)) as Map<String, Object?>;
      final roots = <RevisionObjectId>{
        RevisionObjectId(map['currentUpstream'] as String),
        RevisionObjectId(map['currentEffective'] as String),
      }.toList();
      if (roots.length > 256) {
        return (
          failure: RepositoryTransportStatus.limitExceeded,
          refs: null,
          pack: null,
        );
      }
      oids = roots.map((id) => id.value).toList()..sort();
      final received = path.join(rootPath, 'received.pack');
      await const BoundedGitPackFetcher().fetch(
        remote: remote.url,
        roots: oids,
        headers: headers,
        outputPath: received,
        allowLoopbackHttpForTesting: remote.allowLoopbackHttpForTesting,
        isCancelled: () => finished || active.cancellation.token.isCancelled,
      );
      return (
        failure: null,
        refs: null,
        pack: await File(received).readAsBytes(),
      );
    } on BoundedGitFetchFailure catch (error) {
      return (failure: error.status, refs: null, pack: null);
    } on Object {
      return (
        failure: flag.value != 0
            ? RepositoryTransportStatus.cancelled
            : RepositoryTransportStatus.outcomeUnknown,
        refs: null,
        pack: null,
      );
    } finally {
      finished = true;
      await cancellation.cancel();
      final cleanup = await writerLock.acquire();
      try {
        if (registered) {
          await filesystem.removeOwnedPath(
            targetPath: root,
            ownerRoot: skill == null
                ? layout.stagingRoot
                : layout.revisionStorePath(skill),
          );
          await (database.delete(database.workspaceNetworkTransfers)..where(
                (row) => row.operationId.equals(context.operationId.value),
              ))
              .go();
        }
      } finally {
        _active.remove(context.operationId);
        calloc.free(flag);
        active.done.complete();
        await cleanup.release();
      }
    }
  }
}

final class _TransferRecoveryGuard implements SkillsCommandHandler {
  const _TransferRecoveryGuard({required this.owner, required this.delegate});
  final WorkspaceRevisionNetworkTransfers owner;
  final SkillsCommandHandler delegate;
  @override
  WorkspaceOperationKind get kind => delegate.kind;
  @override
  Future<SkillsResult<Object?>> execute(
    Object request,
    SkillsCommandContext context,
  ) async {
    final lease = await owner.writerLock.acquire(
      waitPolicy: context.lockWaitPolicy,
    );
    try {
      await owner.reconcileInactiveTransfers();
    } catch (_) {
      return SkillsFailure(code: SkillsErrorCode.finalizationRecoveryFailed);
    } finally {
      await lease.release();
    }
    return delegate.execute(request, context);
  }
}

final class _ActiveTransfer {
  _ActiveTransfer(this.skill, this.cancel);
  final ManagedSkillId? skill;
  final ffi.Pointer<ffi.Int32> cancel;
  final Completer<void> done = Completer<void>();
  final CancellationSource cancellation = CancellationSource();
  void requestCancel() {
    cancel.value = 1;
    unawaited(cancellation.cancel());
  }
}

final class _TransferDestructionGuard implements SkillsCommandHandler {
  const _TransferDestructionGuard({
    required this.owner,
    required this.delegate,
  });
  final WorkspaceRevisionNetworkTransfers owner;
  final SkillsCommandHandler delegate;
  @override
  WorkspaceOperationKind get kind => delegate.kind;
  @override
  Future<SkillsResult<Object?>> execute(
    Object request,
    SkillsCommandContext context,
  ) async {
    if (request is RemoveRequest && request.expectedIdentity != null) {
      final metadata = await owner.database
          .select(owner.database.workspaceMetadata)
          .getSingle();
      if (metadata.workspaceId != request.expectedIdentity!.workspaceId ||
          metadata.recoveryIncarnation !=
              request.expectedIdentity!.recoveryIncarnation) {
        return SkillsFailure(code: SkillsErrorCode.staleSnapshot);
      }
    }
    final ids = request is RemoveRequest
        ? request.managedSkillIds
        : request is ReplaceIncomingRevisionRequest
        ? {request.managedSkillId}
        : {(request as ReplaceSourceRequest).managedSkillId};
    if (ids.any(owner._blocked.contains)) {
      return SkillsFailure(code: SkillsErrorCode.repositoryBusy);
    }
    owner._blocked.addAll(ids);
    try {
      final pending = owner._active.values
          .where((active) => ids.contains(active.skill))
          .toList();
      for (final active in pending) {
        active.requestCancel();
      }
      try {
        await Future.wait(
          pending.map((active) => active.done.future),
        ).timeout(const Duration(seconds: 70));
      } on TimeoutException {
        return SkillsFailure(code: SkillsErrorCode.repositoryBusy);
      }
      return await delegate.execute(request, context);
    } finally {
      owner._blocked.removeAll(ids);
    }
  }
}

SkillsFailure<T> _failure<T>(RepositoryTransportStatus status) => SkillsFailure(
  code: switch (status) {
    RepositoryTransportStatus.cancelled => SkillsErrorCode.operationCancelled,
    RepositoryTransportStatus.authenticationRequired =>
      SkillsErrorCode.sourceAuthenticationRequired,
    RepositoryTransportStatus.limitExceeded =>
      SkillsErrorCode.skillContentLimitExceeded,
    RepositoryTransportStatus.invalidArgument => SkillsErrorCode.staleSnapshot,
    _ => SkillsErrorCode.httpFailure,
  },
  context: {'reason': status.name},
);
