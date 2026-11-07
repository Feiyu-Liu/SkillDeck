import 'dart:async';
import 'dart:isolate';

import '../../application/runtime/revision_engine_port.dart';
import '../../application/runtime/normalized_skill_tree_hash.dart';
import '../../domain/revision_content.dart';
import '../revision_engine/revision_native_engine.dart';
import 'revision_worker_protocol.dart';

void runRevisionWorker(RevisionWorkerBootstrap bootstrap) async {
  if (bootstrap.failBeforeStartup) {
    throw StateError('Injected Revision worker startup failure.');
  }

  RevisionNativeEngine? engine;
  final commandPort = ReceivePort();
  try {
    if (bootstrap.protocolVersion != revisionWorkerProtocolVersion) {
      bootstrap.parentPort.send(
        RevisionWorkerStarted(
          protocolVersion: revisionWorkerProtocolVersion,
          commandPort: commandPort.sendPort,
        ),
      );
      commandPort.close();
      return;
    }
    engine = RevisionNativeEngine.open();
    bootstrap.parentPort.send(
      RevisionWorkerStarted(
        protocolVersion: bootstrap.protocolVersion,
        commandPort: commandPort.sendPort,
      ),
    );

    await for (final message in commandPort) {
      switch (message) {
        case RevisionWorkerRequest():
          final shouldStop = await _handleRequest(bootstrap, engine, message);
          if (shouldStop) {
            commandPort.close();
            return;
          }
        case RevisionWorkerShutdown():
          if (message.protocolVersion != bootstrap.protocolVersion) {
            continue;
          }
          engine.close();
          bootstrap.parentPort.send(
            RevisionWorkerStopped(protocolVersion: bootstrap.protocolVersion),
          );
          commandPort.close();
          return;
        default:
          // Only the versioned message types above cross this private boundary.
          // Unknown messages are ignored so they cannot crash the worker.
          continue;
      }
    }
  } finally {
    engine?.close();
    commandPort.close();
  }
}

Future<bool> _handleRequest(
  RevisionWorkerBootstrap bootstrap,
  RevisionNativeEngine engine,
  RevisionWorkerRequest request,
) async {
  if (request.protocolVersion != bootstrap.protocolVersion) {
    bootstrap.parentPort.send(
      RevisionWorkerRejected(
        protocolVersion: bootstrap.protocolVersion,
        requestId: request.requestId,
        code: RevisionWorkerWireFailureCode.protocolMismatch,
      ),
    );
    return false;
  }

  try {
    final payload = await _execute(
      engine,
      request.command,
      taskExecutor: bootstrap.taskExecutor,
    );
    if (payload == _fatalWorkerMarker) {
      bootstrap.parentPort.send(
        RevisionWorkerFatal(protocolVersion: bootstrap.protocolVersion),
      );
      return true;
    }
    bootstrap.parentPort.send(
      RevisionWorkerSucceeded(
        protocolVersion: bootstrap.protocolVersion,
        requestId: request.requestId,
        payload: payload,
      ),
    );
    return false;
  } on RevisionNativeException catch (error) {
    bootstrap.parentPort.send(
      RevisionWorkerRejected(
        protocolVersion: bootstrap.protocolVersion,
        requestId: request.requestId,
        code: RevisionWorkerWireFailureCode.operationFailed,
        operationFailureCode: _mapNativeFailure(error.code),
      ),
    );
    return false;
  } on ArgumentError {
    bootstrap.parentPort.send(
      RevisionWorkerRejected(
        protocolVersion: bootstrap.protocolVersion,
        requestId: request.requestId,
        code: RevisionWorkerWireFailureCode.operationFailed,
        operationFailureCode: RevisionEngineFailureCode.invalidInput,
      ),
    );
    return false;
  } on Object {
    bootstrap.parentPort.send(
      RevisionWorkerRejected(
        protocolVersion: bootstrap.protocolVersion,
        requestId: request.requestId,
        code: RevisionWorkerWireFailureCode.operationFailed,
        operationFailureCode: RevisionEngineFailureCode.unexpectedFailure,
      ),
    );
    return false;
  }
}

Future<Object?> _execute(
  RevisionNativeEngine engine,
  RevisionWorkerCommand command, {
  required RevisionWorkerTaskExecutor? taskExecutor,
}) async {
  switch (command) {
    case RevisionWorkerStatusCommand(:final delayMicroseconds):
      if (delayMicroseconds > 0) {
        await Future<void>.delayed(Duration(microseconds: delayMicroseconds));
      }
      return revisionWorkerProtocolVersion;
    case RevisionWorkerCreateStoreCommand(:final repositoryPath):
      engine.createStore(repositoryPath);
      return null;
    case RevisionWorkerVerifyStoreCommand(:final repositoryPath):
      engine.verifyStore(repositoryPath);
      return null;
    case RevisionWorkerNormalizeContentCommand() ||
        RevisionWorkerReadFilesystemTreeCommand() ||
        RevisionWorkerCaptureDraftCommand() ||
        RevisionWorkerFingerprintDraftCommand() ||
        RevisionWorkerDiscardDraftCaptureCommand() ||
        RevisionWorkerNormalizeDraftCommand() ||
        RevisionWorkerReadDeclaredNameCommand() ||
        RevisionWorkerEncodeCanonicalManifestCommand():
      return _executeInjectedTask(taskExecutor, command);
    case RevisionWorkerWriteTreeCommand(
      :final repositoryPath,
      :final files,
      :final contentHash,
      :final byteSize,
    ):
      final tree = NormalizedSkillTree(
        files: files.map((file) => file.materialize()).toList(growable: false),
        contentHash: contentHash,
        byteSize: byteSize,
      );
      if (computeNormalizedSkillTreeHash(tree.files) != tree.contentHash ||
          tree.files.fold<int>(0, (sum, file) => sum + file.bytes.length) !=
              tree.byteSize) {
        throw ArgumentError.value(tree, 'tree', 'wire integrity mismatch');
      }
      return engine.writeTree(repositoryPath, tree).value;
    case RevisionWorkerReadTreeCommand(:final repositoryPath, :final commitOid):
      return RevisionWorkerTreePayload.fromTree(
        engine.readTree(repositoryPath, RevisionObjectId(commitOid)),
      );
    case RevisionWorkerCreateCommitCommand(
      :final repositoryPath,
      :final treeOid,
      :final parentOids,
      :final kindIndex,
    ):
      return engine
          .createCommit(
            repositoryPath: repositoryPath,
            request: _commitRequest(treeOid, parentOids, kindIndex),
          )
          .value;
    case RevisionWorkerVerifyCommitCommand(
      :final repositoryPath,
      :final commitOid,
      :final treeOid,
      :final parentOids,
      :final kindIndex,
    ):
      engine.verifyCommit(
        repositoryPath: repositoryPath,
        commit: RevisionObjectId(commitOid),
        expected: _commitRequest(treeOid, parentOids, kindIndex),
      );
      return null;
    case RevisionWorkerIsAncestorCommand(
      :final repositoryPath,
      :final ancestorOid,
      :final descendantOid,
    ):
      return engine.isAncestor(
        repositoryPath: repositoryPath,
        ancestor: RevisionObjectId(ancestorOid),
        descendant: RevisionObjectId(descendantOid),
      );
    case RevisionWorkerDiffCommand(
      :final repositoryPath,
      :final oldCommitOid,
      :final newCommitOid,
    ):
      return engine.diff(
        repositoryPath: repositoryPath,
        oldCommit: RevisionObjectId(oldCommitOid),
        newCommit: RevisionObjectId(newCommitOid),
      );
    case RevisionWorkerMergeCommand(
      :final repositoryPath,
      :final previousUpstreamOid,
      :final currentEffectiveOid,
      :final incomingUpstreamOid,
    ):
      return switch (engine.merge(
        repositoryPath: repositoryPath,
        previousUpstream: RevisionObjectId(previousUpstreamOid),
        currentEffective: RevisionObjectId(currentEffectiveOid),
        incomingUpstream: RevisionObjectId(incomingUpstreamOid),
      )) {
        RevisionMergeClean(:final tree) => RevisionWorkerMergeCleanPayload(
          tree.value,
        ),
        RevisionMergeConflicted(:final tree, :final conflicts) =>
          RevisionWorkerMergeConflictedPayload(
            treeOid: tree.value,
            conflicts: conflicts,
          ),
      };
    case RevisionWorkerCreateRecoveryPackCommand(
      :final repositoryPath,
      :final bundleStagingPath,
      :final retainedRootOids,
    ):
      engine.createRecoveryPack(
        repositoryPath: repositoryPath,
        bundleStagingPath: bundleStagingPath,
        retainedRoots: retainedRootOids.map(RevisionObjectId.new).toList(),
      );
      return null;
    case RevisionWorkerRestoreRecoveryPackCommand(
      :final stagedRepositoryPath,
      :final packPath,
      :final indexPath,
      :final retainedRootOids,
    ):
      engine.restoreRecoveryPack(
        stagedRepositoryPath: stagedRepositoryPath,
        packPath: packPath,
        indexPath: indexPath,
        retainedRoots: retainedRootOids.map(RevisionObjectId.new).toList(),
      );
      return null;
    case RevisionWorkerBuildBundleArtifactsCommand(
      :final repositoryPath,
      :final bundlePath,
      :final retainedRootOids,
    ):
      engine.createRecoveryPack(
        repositoryPath: repositoryPath,
        bundleStagingPath: bundlePath,
        retainedRoots: retainedRootOids.map(RevisionObjectId.new).toList(),
      );
      return _executeInjectedTask(taskExecutor, command);
    case RevisionWorkerVerifyBundleArtifactsCommand():
      return _executeInjectedTask(taskExecutor, command);
    case RevisionWorkerReplaceRetentionRefsCommand(
      :final repositoryPath,
      :final references,
    ):
      engine.replaceRetentionRefs(
        repositoryPath: repositoryPath,
        references: references
            .map(
              (reference) => RevisionRetentionRef(
                name: reference.name,
                target: RevisionObjectId(reference.targetOid),
              ),
            )
            .toList(growable: false),
      );
      return null;
    case RevisionWorkerCrashCommand():
      return _fatalWorkerMarker;
  }
}

Future<Object?> _executeInjectedTask(
  RevisionWorkerTaskExecutor? taskExecutor,
  RevisionWorkerCommand command,
) {
  final executor = taskExecutor;
  if (executor == null) {
    throw UnsupportedError('The Revision worker task is not composed.');
  }
  return executor(command);
}

RevisionCommitRequest _commitRequest(
  String treeOid,
  List<String> parentOids,
  int kindIndex,
) {
  if (kindIndex < 0 || kindIndex >= RevisionCommitKind.values.length) {
    throw ArgumentError.value(kindIndex, 'kindIndex');
  }
  return RevisionCommitRequest(
    tree: RevisionObjectId(treeOid),
    parents: parentOids.map(RevisionObjectId.new).toList(growable: false),
    kind: RevisionCommitKind.values[kindIndex],
  );
}

RevisionEngineFailureCode _mapNativeFailure(RevisionNativeFailureCode code) {
  return switch (code) {
    RevisionNativeFailureCode.invalidArgument =>
      RevisionEngineFailureCode.invalidInput,
    RevisionNativeFailureCode.repositoryFailure ||
    RevisionNativeFailureCode.notInitialized ||
    RevisionNativeFailureCode.closed =>
      RevisionEngineFailureCode.storeUnavailable,
    RevisionNativeFailureCode.objectFailure =>
      RevisionEngineFailureCode.objectUnavailable,
    RevisionNativeFailureCode.verificationFailure ||
    RevisionNativeFailureCode.bufferTooSmall =>
      RevisionEngineFailureCode.verificationFailed,
    RevisionNativeFailureCode.bundleFailure =>
      RevisionEngineFailureCode.bundleInvalid,
    RevisionNativeFailureCode.unexpectedFailure =>
      RevisionEngineFailureCode.unexpectedFailure,
  };
}

const _fatalWorkerMarker = _FatalWorkerMarker();

final class _FatalWorkerMarker {
  const _FatalWorkerMarker();
}
