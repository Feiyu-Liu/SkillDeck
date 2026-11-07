import 'dart:async';
import 'dart:isolate';

import '../../application/ports/draft_snapshot_ports.dart';
import '../../application/ports/revision_bundle_worker_ports.dart';
import '../../application/ports/revision_content_worker_ports.dart';
import '../../application/ports/revision_manifest_worker_ports.dart';
import '../../application/operations/operation_models.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/draft_snapshot.dart';
import '../../domain/revision_content.dart';
import 'revision_worker_entrypoint.dart';
import 'revision_worker_protocol.dart';

enum RevisionWorkerFailureCode {
  startupFailed,
  protocolMismatch,
  closing,
  closed,
  terminated,
  workerFailed,
  invalidResponse,
}

final class RevisionWorkerException implements Exception {
  const RevisionWorkerException(this.code);

  final RevisionWorkerFailureCode code;

  @override
  String toString() => 'RevisionWorkerException(${code.name})';
}

enum _RevisionWorkerState { starting, running, closing, closed, failed }

/// Project-owned long-lived isolate for Revision Engine work.
///
/// This class owns no SQLite connection and does not create a database isolate.
/// It is intentionally private to the package implementation.
final class RevisionWorker
    implements
        RevisionEnginePort,
        RevisionBundleWorkerPort,
        RevisionContentWorkerPort,
        RevisionManifestWorkerPort,
        DraftSnapshotFilesystemPort,
        DraftContentPort {
  RevisionWorker._({
    required int workerProtocolVersion,
    required bool failBeforeStartup,
    required RevisionWorkerTaskExecutor? taskExecutor,
  }) : _workerProtocolVersion = workerProtocolVersion,
       _failBeforeStartup = failBeforeStartup,
       _taskExecutor = taskExecutor;

  final int _workerProtocolVersion;
  final bool _failBeforeStartup;
  final RevisionWorkerTaskExecutor? _taskExecutor;
  final ReceivePort _responsePort = ReceivePort();
  final ReceivePort _errorPort = ReceivePort();
  final ReceivePort _exitPort = ReceivePort();
  final Completer<void> _startup = Completer<void>();
  final Map<int, _PendingRequest> _pending = {};

  _RevisionWorkerState _state = _RevisionWorkerState.starting;
  Isolate? _isolate;
  SendPort? _commandPort;
  StreamSubscription<Object?>? _responseSubscription;
  StreamSubscription<Object?>? _errorSubscription;
  StreamSubscription<Object?>? _exitSubscription;
  Completer<void>? _closeCompleter;
  RevisionWorkerException? _terminalFailure;
  int _nextRequestId = 1;
  bool _portsClosed = false;

  static Future<RevisionWorker> start({
    RevisionWorkerTaskExecutor? taskExecutor,
  }) => _start(
    workerProtocolVersion: revisionWorkerProtocolVersion,
    failBeforeStartup: false,
    taskExecutor: taskExecutor,
  );

  static Future<RevisionWorker> startForTesting({
    int workerProtocolVersion = revisionWorkerProtocolVersion,
    bool failBeforeStartup = false,
    RevisionWorkerTaskExecutor? taskExecutor,
  }) => _start(
    workerProtocolVersion: workerProtocolVersion,
    failBeforeStartup: failBeforeStartup,
    taskExecutor: taskExecutor,
  );

  static Future<RevisionWorker> _start({
    required int workerProtocolVersion,
    required bool failBeforeStartup,
    required RevisionWorkerTaskExecutor? taskExecutor,
  }) async {
    final worker = RevisionWorker._(
      workerProtocolVersion: workerProtocolVersion,
      failBeforeStartup: failBeforeStartup,
      taskExecutor: taskExecutor,
    );
    await worker._spawn();
    return worker;
  }

  bool get isRunning => _state == _RevisionWorkerState.running;

  bool get isClosed =>
      _state == _RevisionWorkerState.closed ||
      _state == _RevisionWorkerState.failed;

  int get pendingRequestCount => _pending.length;

  Future<void> _spawn() async {
    _responseSubscription = _responsePort.listen(_handleResponse);
    _errorSubscription = _errorPort.listen(_handleWorkerError);
    _exitSubscription = _exitPort.listen(_handleWorkerExit);

    try {
      _isolate = await Isolate.spawn(
        runRevisionWorker,
        RevisionWorkerBootstrap(
          parentPort: _responsePort.sendPort,
          protocolVersion: _workerProtocolVersion,
          failBeforeStartup: _failBeforeStartup,
          taskExecutor: _taskExecutor,
        ),
        errorsAreFatal: true,
        onError: _errorPort.sendPort,
        onExit: _exitPort.sendPort,
        debugName: 'Skills Workspace Revision worker',
      );
      await _startup.future;
    } on RevisionWorkerException {
      rethrow;
    } on Object {
      final failure = const RevisionWorkerException(
        RevisionWorkerFailureCode.startupFailed,
      );
      _fail(failure);
      throw failure;
    }
  }

  @override
  Future<RevisionEngineStatus> status() => _status();

  Future<RevisionEngineStatus> statusForTesting({
    Duration delay = Duration.zero,
  }) => _status(delay: delay);

  Future<RevisionEngineStatus> _status({Duration delay = Duration.zero}) {
    return _send<RevisionEngineStatus>(
      RevisionWorkerStatusCommand(delayMicroseconds: delay.inMicroseconds),
      (payload) {
        if (payload case final int protocolVersion) {
          return RevisionEngineStatus(protocolVersion: protocolVersion);
        }
        throw const RevisionWorkerException(
          RevisionWorkerFailureCode.invalidResponse,
        );
      },
    );
  }

  @override
  Future<void> createStore(String repositoryPath) => _send<void>(
    RevisionWorkerCreateStoreCommand(repositoryPath),
    _decodeVoid,
  );

  @override
  Future<void> verifyStore(String repositoryPath) => _send<void>(
    RevisionWorkerVerifyStoreCommand(repositoryPath),
    _decodeVoid,
  );

  @override
  Future<SkillContentResult<NormalizedSkillTree>> normalizeContent(
    List<SkillContentEntry> entries, {
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) async {
    if (isCancelled()) return _cancelledContent();
    final result = await _send<SkillContentResult<NormalizedSkillTree>>(
      RevisionWorkerNormalizeContentCommand(
        entries: entries
            .map(RevisionWorkerContentEntryPayload.fromEntry)
            .toList(growable: false),
        maximumFileCount: maximumFileCount,
        maximumByteSize: maximumByteSize,
      ),
      _decodeSkillContentResult,
    );
    return isCancelled() ? _cancelledContent() : result;
  }

  @override
  Future<SkillContentResult<NormalizedSkillTree>> readFilesystemTree(
    String rootPath, {
    required GitMetadataDisposition gitMetadataDisposition,
    required bool capturePosixExecutableIntent,
    required Map<String, bool> executableIntentOverrides,
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) async {
    if (isCancelled()) return _cancelledContent();
    final result = await _send<SkillContentResult<NormalizedSkillTree>>(
      RevisionWorkerReadFilesystemTreeCommand(
        rootPath: rootPath,
        gitMetadataDisposition: gitMetadataDisposition,
        capturePosixExecutableIntent: capturePosixExecutableIntent,
        executableIntentOverrides: executableIntentOverrides,
        maximumFileCount: maximumFileCount,
        maximumByteSize: maximumByteSize,
      ),
      _decodeSkillContentResult,
    );
    return isCancelled() ? _cancelledContent() : result;
  }

  @override
  Future<DraftSnapshotResult<DraftCapture>> capture(
    DraftCaptureRequest request,
  ) async {
    if (request.isCancelled?.call() ?? false) return _cancelledDraft();
    final result = await _send<DraftSnapshotResult<DraftCapture>>(
      RevisionWorkerCaptureDraftCommand(
        RevisionWorkerDraftCaptureRequestPayload.fromRequest(request),
      ),
      _decodeDraftCaptureResult,
    );
    if (!(request.isCancelled?.call() ?? false)) return result;
    final capture = result.valueOrNull;
    if (capture != null) await discardStaging(capture);
    return _cancelledDraft();
  }

  @override
  Future<DraftSnapshotResult<DraftFingerprint>> fingerprint(
    DraftCaptureRequest request,
  ) async {
    if (request.isCancelled?.call() ?? false) return _cancelledDraft();
    final result = await _send<DraftSnapshotResult<DraftFingerprint>>(
      RevisionWorkerFingerprintDraftCommand(
        RevisionWorkerDraftCaptureRequestPayload.fromRequest(request),
      ),
      _decodeDraftFingerprintResult,
    );
    return request.isCancelled?.call() ?? false ? _cancelledDraft() : result;
  }

  @override
  Future<void> discardStaging(DraftCapture capture) => _send<void>(
    RevisionWorkerDiscardDraftCaptureCommand(capture.stagingPath),
    _decodeVoid,
  );

  @override
  Future<DraftSnapshotResult<NormalizedSkillTree>> normalize(
    List<CapturedDraftFile> files, {
    bool Function()? isCancelled,
  }) async {
    final cancelled = isCancelled ?? _neverCancelled;
    if (cancelled()) return _cancelledDraft();
    final result = await _send<DraftSnapshotResult<NormalizedSkillTree>>(
      RevisionWorkerNormalizeDraftCommand(
        files
            .map(RevisionWorkerCapturedDraftFilePayload.fromFile)
            .toList(growable: false),
      ),
      _decodeDraftTreeResult,
    );
    return cancelled() ? _cancelledDraft() : result;
  }

  @override
  Future<String?> readDeclaredName(NormalizedSkillTree tree) => _send<String?>(
    RevisionWorkerReadDeclaredNameCommand(
      RevisionWorkerTreePayload.fromTree(tree),
    ),
    (payload) {
      if (payload == null || payload is String) return payload as String?;
      throw const RevisionWorkerException(
        RevisionWorkerFailureCode.invalidResponse,
      );
    },
  );

  @override
  Future<CanonicalManifestArtifacts> encodeCanonicalManifest({
    required Map<String, Object?> value,
    required int schemaVersion,
  }) => _send<CanonicalManifestArtifacts>(
    RevisionWorkerEncodeCanonicalManifestCommand(
      value: value,
      schemaVersion: schemaVersion,
    ),
    (payload) {
      if (payload case RevisionWorkerCanonicalManifestPayload(
        :final manifestBytes,
        :final completionFenceBytes,
      )) {
        return CanonicalManifestArtifacts(
          manifestBytes: manifestBytes.materialize().asUint8List(),
          completionFenceBytes: completionFenceBytes
              .materialize()
              .asUint8List(),
        );
      }
      throw const RevisionWorkerException(
        RevisionWorkerFailureCode.invalidResponse,
      );
    },
  );

  @override
  Future<RevisionObjectId> writeTree(
    String repositoryPath,
    NormalizedSkillTree tree,
  ) {
    return _send<RevisionObjectId>(
      RevisionWorkerWriteTreeCommand(
        repositoryPath: repositoryPath,
        files: tree.files
            .map(RevisionWorkerFilePayload.fromFile)
            .toList(growable: false),
        contentHash: tree.contentHash,
        byteSize: tree.byteSize,
      ),
      (payload) {
        if (payload case final String oid) return RevisionObjectId(oid);
        throw const RevisionWorkerException(
          RevisionWorkerFailureCode.invalidResponse,
        );
      },
    );
  }

  @override
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commit,
  ) {
    return _send<NormalizedSkillTree>(
      RevisionWorkerReadTreeCommand(
        repositoryPath: repositoryPath,
        commitOid: commit.value,
      ),
      (payload) {
        if (payload case final RevisionWorkerTreePayload tree) {
          return tree.materialize();
        }
        throw const RevisionWorkerException(
          RevisionWorkerFailureCode.invalidResponse,
        );
      },
    );
  }

  @override
  Future<RevisionObjectId> createCommit(
    String repositoryPath,
    RevisionCommitRequest request,
  ) {
    return _send<RevisionObjectId>(
      RevisionWorkerCreateCommitCommand(
        repositoryPath: repositoryPath,
        treeOid: request.tree.value,
        parentOids: request.parents.map((parent) => parent.value).toList(),
        kindIndex: request.kind.index,
      ),
      (payload) {
        if (payload case final String oid) return RevisionObjectId(oid);
        throw const RevisionWorkerException(
          RevisionWorkerFailureCode.invalidResponse,
        );
      },
    );
  }

  @override
  Future<void> verifyCommit(
    String repositoryPath,
    RevisionObjectId commit,
    RevisionCommitRequest expected,
  ) {
    return _send<void>(
      RevisionWorkerVerifyCommitCommand(
        repositoryPath: repositoryPath,
        commitOid: commit.value,
        treeOid: expected.tree.value,
        parentOids: expected.parents.map((parent) => parent.value).toList(),
        kindIndex: expected.kind.index,
      ),
      _decodeVoid,
    );
  }

  @override
  Future<bool> isAncestor({
    required String repositoryPath,
    required RevisionObjectId ancestor,
    required RevisionObjectId descendant,
  }) {
    return _send<bool>(
      RevisionWorkerIsAncestorCommand(
        repositoryPath: repositoryPath,
        ancestorOid: ancestor.value,
        descendantOid: descendant.value,
      ),
      (payload) {
        if (payload case final bool value) return value;
        throw const RevisionWorkerException(
          RevisionWorkerFailureCode.invalidResponse,
        );
      },
    );
  }

  @override
  Future<List<RevisionChange>> diff({
    required String repositoryPath,
    required RevisionObjectId oldCommit,
    required RevisionObjectId newCommit,
  }) {
    return _send<List<RevisionChange>>(
      RevisionWorkerDiffCommand(
        repositoryPath: repositoryPath,
        oldCommitOid: oldCommit.value,
        newCommitOid: newCommit.value,
      ),
      (payload) {
        if (payload case final List<Object?> values) {
          return values.cast<RevisionChange>();
        }
        throw const RevisionWorkerException(
          RevisionWorkerFailureCode.invalidResponse,
        );
      },
    );
  }

  @override
  Future<RevisionMergeResult> merge({
    required String repositoryPath,
    required RevisionObjectId previousUpstream,
    required RevisionObjectId currentEffective,
    required RevisionObjectId incomingUpstream,
  }) {
    return _send<RevisionMergeResult>(
      RevisionWorkerMergeCommand(
        repositoryPath: repositoryPath,
        previousUpstreamOid: previousUpstream.value,
        currentEffectiveOid: currentEffective.value,
        incomingUpstreamOid: incomingUpstream.value,
      ),
      (payload) => switch (payload) {
        RevisionWorkerMergeCleanPayload(:final treeOid) => RevisionMergeClean(
          RevisionObjectId(treeOid),
        ),
        RevisionWorkerMergeConflictedPayload(
          :final treeOid,
          :final conflicts,
        ) =>
          RevisionMergeConflicted(
            tree: RevisionObjectId(treeOid),
            conflicts: conflicts,
          ),
        _ => throw const RevisionWorkerException(
          RevisionWorkerFailureCode.invalidResponse,
        ),
      },
    );
  }

  @override
  Future<void> createRecoveryPack({
    required String repositoryPath,
    required String bundleStagingPath,
    required List<RevisionObjectId> retainedRoots,
  }) {
    return _send<void>(
      RevisionWorkerCreateRecoveryPackCommand(
        repositoryPath: repositoryPath,
        bundleStagingPath: bundleStagingPath,
        retainedRootOids: retainedRoots.map((root) => root.value).toList(),
      ),
      _decodeVoid,
    );
  }

  @override
  Future<void> restoreRecoveryPack({
    required String stagedRepositoryPath,
    required String packPath,
    required String indexPath,
    required List<RevisionObjectId> retainedRoots,
  }) {
    return _send<void>(
      RevisionWorkerRestoreRecoveryPackCommand(
        stagedRepositoryPath: stagedRepositoryPath,
        packPath: packPath,
        indexPath: indexPath,
        retainedRootOids: retainedRoots.map((root) => root.value).toList(),
      ),
      _decodeVoid,
    );
  }

  @override
  Future<void> buildRevisionBundleArtifacts({
    required String repositoryPath,
    required String bundlePath,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedRoots,
  }) => _send<void>(
    RevisionWorkerBuildBundleArtifactsCommand(
      repositoryPath: repositoryPath,
      bundlePath: bundlePath,
      sourceLineageId: sourceLineage.encoded,
      currentUpstreamOid: currentUpstream.value,
      currentEffectiveOid: currentEffective.value,
      retainedRootOids: retainedRoots.map((root) => root.value).toList(),
    ),
    _decodeVoid,
  );

  @override
  Future<void> verifyRevisionBundleArtifacts({
    required String bundlePath,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedRoots,
  }) => _send<void>(
    RevisionWorkerVerifyBundleArtifactsCommand(
      bundlePath: bundlePath,
      sourceLineageId: sourceLineage.encoded,
      currentUpstreamOid: currentUpstream.value,
      currentEffectiveOid: currentEffective.value,
      retainedRootOids: retainedRoots.map((root) => root.value).toList(),
    ),
    _decodeVoid,
  );

  @override
  Future<void> replaceRetentionRefs(
    String repositoryPath,
    List<RevisionRetentionRef> references,
  ) => _send<void>(
    RevisionWorkerReplaceRetentionRefsCommand(
      repositoryPath: repositoryPath,
      references: references
          .map(
            (reference) => RevisionWorkerRetentionRefPayload(
              name: reference.name,
              targetOid: reference.target.value,
            ),
          )
          .toList(growable: false),
    ),
    _decodeVoid,
  );

  Future<void> crashForTesting() {
    return _send<void>(const RevisionWorkerCrashCommand(), (_) {});
  }

  void terminateForTesting() {
    _isolate?.kill(priority: Isolate.immediate);
  }

  Future<T> _send<T>(
    RevisionWorkerCommand command,
    T Function(Object? payload) decode,
  ) {
    final unavailable = _unavailableFailure();
    if (unavailable != null) {
      return Future<T>.error(unavailable);
    }

    final requestId = _nextRequestId++;
    final completer = Completer<T>();
    _pending[requestId] = _TypedPendingRequest<T>(completer, decode);
    _commandPort!.send(
      RevisionWorkerRequest(
        protocolVersion: _workerProtocolVersion,
        requestId: requestId,
        command: command,
      ),
    );
    return completer.future;
  }

  RevisionWorkerException? _unavailableFailure() {
    return switch (_state) {
      _RevisionWorkerState.running => null,
      _RevisionWorkerState.starting => const RevisionWorkerException(
        RevisionWorkerFailureCode.startupFailed,
      ),
      _RevisionWorkerState.closing => const RevisionWorkerException(
        RevisionWorkerFailureCode.closing,
      ),
      _RevisionWorkerState.closed => const RevisionWorkerException(
        RevisionWorkerFailureCode.closed,
      ),
      _RevisionWorkerState.failed =>
        _terminalFailure ??
            const RevisionWorkerException(
              RevisionWorkerFailureCode.workerFailed,
            ),
    };
  }

  void _handleResponse(Object? message) {
    if (message is! RevisionWorkerOutboundMessage) {
      _fail(
        const RevisionWorkerException(
          RevisionWorkerFailureCode.invalidResponse,
        ),
      );
      return;
    }
    if (message.protocolVersion != _workerProtocolVersion) {
      _fail(
        const RevisionWorkerException(
          RevisionWorkerFailureCode.protocolMismatch,
        ),
      );
      return;
    }

    switch (message) {
      case RevisionWorkerStarted(:final commandPort):
        if (_state != _RevisionWorkerState.starting) {
          _fail(
            const RevisionWorkerException(
              RevisionWorkerFailureCode.invalidResponse,
            ),
          );
          return;
        }
        _commandPort = commandPort;
        _state = _RevisionWorkerState.running;
        _startup.complete();
      case RevisionWorkerSucceeded(:final requestId, :final payload):
        final request = _pending.remove(requestId);
        if (request == null) {
          _fail(
            const RevisionWorkerException(
              RevisionWorkerFailureCode.invalidResponse,
            ),
          );
          return;
        }
        request.complete(payload);
      case RevisionWorkerRejected(:final requestId, :final code):
        final request = _pending.remove(requestId);
        if (request == null) {
          _fail(
            const RevisionWorkerException(
              RevisionWorkerFailureCode.invalidResponse,
            ),
          );
          return;
        }
        final operationCode = message.operationFailureCode;
        if (code == RevisionWorkerWireFailureCode.operationFailed &&
            operationCode != null) {
          request.failOperation(RevisionEngineException(operationCode));
        } else {
          request.fail(
            RevisionWorkerException(switch (code) {
              RevisionWorkerWireFailureCode.protocolMismatch =>
                RevisionWorkerFailureCode.protocolMismatch,
              RevisionWorkerWireFailureCode.unsupportedCommand ||
              RevisionWorkerWireFailureCode.operationFailed =>
                RevisionWorkerFailureCode.invalidResponse,
            }),
          );
        }
      case RevisionWorkerStopped():
        if (_state != _RevisionWorkerState.closing || _pending.isNotEmpty) {
          _fail(
            const RevisionWorkerException(
              RevisionWorkerFailureCode.invalidResponse,
            ),
          );
          return;
        }
        _state = _RevisionWorkerState.closed;
        _closeCompleter?.complete();
        unawaited(_disposePorts());
      case RevisionWorkerFatal():
        _fail(
          const RevisionWorkerException(RevisionWorkerFailureCode.workerFailed),
        );
    }
  }

  void _handleWorkerError(Object? _) {
    final code = _state == _RevisionWorkerState.starting
        ? RevisionWorkerFailureCode.startupFailed
        : RevisionWorkerFailureCode.workerFailed;
    _fail(RevisionWorkerException(code));
  }

  void _handleWorkerExit(Object? _) {
    if (_state == _RevisionWorkerState.closed ||
        _state == _RevisionWorkerState.failed) {
      return;
    }
    final code = _state == _RevisionWorkerState.starting
        ? RevisionWorkerFailureCode.startupFailed
        : RevisionWorkerFailureCode.terminated;
    _fail(RevisionWorkerException(code));
  }

  void _fail(RevisionWorkerException failure) {
    if (_state == _RevisionWorkerState.closed ||
        _state == _RevisionWorkerState.failed) {
      return;
    }
    _terminalFailure = failure;
    _state = _RevisionWorkerState.failed;
    _isolate?.kill(priority: Isolate.immediate);
    if (!_startup.isCompleted) {
      _startup.completeError(failure);
    }
    for (final request in _pending.values) {
      request.fail(failure);
    }
    _pending.clear();
    if (_closeCompleter case final completer? when !completer.isCompleted) {
      completer.completeError(failure);
    }
    unawaited(_disposePorts());
  }

  @override
  Future<void> close() {
    switch (_state) {
      case _RevisionWorkerState.closed || _RevisionWorkerState.failed:
        return Future<void>.value();
      case _RevisionWorkerState.closing:
        return _closeCompleter!.future;
      case _RevisionWorkerState.starting:
        return Future<void>.error(
          const RevisionWorkerException(
            RevisionWorkerFailureCode.startupFailed,
          ),
        );
      case _RevisionWorkerState.running:
        _state = _RevisionWorkerState.closing;
        final completer = _closeCompleter = Completer<void>();
        _commandPort!.send(
          const RevisionWorkerShutdown(
            protocolVersion: revisionWorkerProtocolVersion,
          ),
        );
        return completer.future;
    }
  }

  Future<void> _disposePorts() async {
    if (_portsClosed) {
      return;
    }
    _portsClosed = true;
    await _responseSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _exitSubscription?.cancel();
    _responsePort.close();
    _errorPort.close();
    _exitPort.close();
  }
}

abstract interface class _PendingRequest {
  void complete(Object? payload);

  void fail(RevisionWorkerException failure);

  void failOperation(RevisionEngineException failure);
}

final class _TypedPendingRequest<T> implements _PendingRequest {
  const _TypedPendingRequest(this.completer, this.decode);

  final Completer<T> completer;
  final T Function(Object? payload) decode;

  @override
  void complete(Object? payload) {
    try {
      completer.complete(decode(payload));
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  @override
  void fail(RevisionWorkerException failure) {
    completer.completeError(failure);
  }

  @override
  void failOperation(RevisionEngineException failure) {
    completer.completeError(failure);
  }
}

void _decodeVoid(Object? payload) {
  if (payload != null) {
    throw const RevisionWorkerException(
      RevisionWorkerFailureCode.invalidResponse,
    );
  }
}

SkillContentResult<NormalizedSkillTree> _decodeSkillContentResult(
  Object? payload,
) => switch (payload) {
  RevisionWorkerSkillContentSuccessPayload(:final tree) =>
    SkillContentSuccess<NormalizedSkillTree>(value: tree.materialize()),
  RevisionWorkerSkillContentFailurePayload(:final codeIndex, :final context)
      when codeIndex >= 0 &&
          codeIndex < SkillContentFailureCode.values.length =>
    SkillContentFailure<NormalizedSkillTree>(
      code: SkillContentFailureCode.values[codeIndex],
      context: context,
    ),
  _ => throw const RevisionWorkerException(
    RevisionWorkerFailureCode.invalidResponse,
  ),
};

SkillContentFailure<NormalizedSkillTree> _cancelledContent() =>
    SkillContentFailure<NormalizedSkillTree>(
      code: SkillContentFailureCode.cancelled,
    );

DraftSnapshotResult<DraftCapture> _decodeDraftCaptureResult(Object? payload) =>
    switch (payload) {
      RevisionWorkerDraftCaptureSuccessPayload(:final capture) =>
        DraftSnapshotSuccess<DraftCapture>(capture.materialize()),
      RevisionWorkerDraftFailurePayload() => _decodeDraftFailure<DraftCapture>(
        payload,
      ),
      _ => throw const RevisionWorkerException(
        RevisionWorkerFailureCode.invalidResponse,
      ),
    };

DraftSnapshotResult<DraftFingerprint> _decodeDraftFingerprintResult(
  Object? payload,
) => switch (payload) {
  RevisionWorkerDraftFingerprintSuccessPayload(:final fingerprint) =>
    DraftSnapshotSuccess<DraftFingerprint>(fingerprint),
  RevisionWorkerDraftFailurePayload() => _decodeDraftFailure<DraftFingerprint>(
    payload,
  ),
  _ => throw const RevisionWorkerException(
    RevisionWorkerFailureCode.invalidResponse,
  ),
};

DraftSnapshotResult<NormalizedSkillTree> _decodeDraftTreeResult(
  Object? payload,
) => switch (payload) {
  RevisionWorkerDraftTreeSuccessPayload(:final tree) =>
    DraftSnapshotSuccess<NormalizedSkillTree>(tree.materialize()),
  RevisionWorkerDraftFailurePayload() =>
    _decodeDraftFailure<NormalizedSkillTree>(payload),
  _ => throw const RevisionWorkerException(
    RevisionWorkerFailureCode.invalidResponse,
  ),
};

DraftSnapshotFailure<T> _decodeDraftFailure<T>(
  RevisionWorkerDraftFailurePayload payload,
) {
  if (payload.codeIndex < 0 ||
      payload.codeIndex >= DraftSnapshotFailureCode.values.length) {
    throw const RevisionWorkerException(
      RevisionWorkerFailureCode.invalidResponse,
    );
  }
  return DraftSnapshotFailure<T>(
    code: DraftSnapshotFailureCode.values[payload.codeIndex],
    context: payload.context,
  );
}

DraftSnapshotFailure<T> _cancelledDraft<T>() =>
    DraftSnapshotFailure<T>(code: DraftSnapshotFailureCode.operationCancelled);

bool _neverCancelled() => false;
