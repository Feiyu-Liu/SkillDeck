import '../../application/ports/draft_snapshot_ports.dart';
import '../../application/ports/revision_bundle_worker_ports.dart';
import '../../application/ports/workspace_lifecycle_ports.dart';
import '../../application/ports/revision_content_worker_ports.dart';
import '../../application/ports/revision_manifest_worker_ports.dart';
import '../../application/operations/operation_models.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/draft_snapshot.dart';
import '../../domain/revision_content.dart';
import 'revision_worker.dart';
import 'revision_worker_protocol.dart';

/// Lifecycle-owned Revision worker exposed only through application ports.
final class RevisionWorkerRuntime
    implements
        WorkspaceRevisionWorkerLifecyclePort,
        RevisionEnginePort,
        RevisionBundleWorkerPort,
        RevisionContentWorkerPort,
        RevisionManifestWorkerPort,
        DraftSnapshotFilesystemPort,
        DraftContentPort {
  RevisionWorkerRuntime({RevisionWorkerTaskExecutor? taskExecutor})
    : _taskExecutor = taskExecutor;

  final RevisionWorkerTaskExecutor? _taskExecutor;
  RevisionWorker? _worker;
  Future<void>? _starting;
  bool _closed = false;

  bool get isRunning => _worker?.isRunning ?? false;

  @override
  Future<void> start() {
    if (_closed) {
      return Future<void>.error(
        const RevisionWorkerException(RevisionWorkerFailureCode.closed),
      );
    }
    if (_worker != null) return Future<void>.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      _worker = await RevisionWorker.start(taskExecutor: _taskExecutor);
    } finally {
      _starting = null;
    }
  }

  RevisionWorker get _active {
    final worker = _worker;
    if (worker == null || !worker.isRunning) {
      throw const RevisionWorkerException(RevisionWorkerFailureCode.closed);
    }
    return worker;
  }

  Future<T> _delegate<T>(
    Future<T> Function(RevisionWorker worker) operation,
  ) async {
    return operation(_active);
  }

  @override
  Future<RevisionEngineStatus> status() =>
      _delegate((worker) => worker.status());

  @override
  Future<void> createStore(String repositoryPath) =>
      _delegate((worker) => worker.createStore(repositoryPath));

  @override
  Future<void> verifyStore(String repositoryPath) =>
      _delegate((worker) => worker.verifyStore(repositoryPath));

  @override
  Future<SkillContentResult<NormalizedSkillTree>> normalizeContent(
    List<SkillContentEntry> entries, {
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) => _delegate(
    (worker) => worker.normalizeContent(
      entries,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
      isCancelled: isCancelled,
    ),
  );

  @override
  Future<SkillContentResult<NormalizedSkillTree>> readFilesystemTree(
    String rootPath, {
    required GitMetadataDisposition gitMetadataDisposition,
    required bool capturePosixExecutableIntent,
    required Map<String, bool> executableIntentOverrides,
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) => _delegate(
    (worker) => worker.readFilesystemTree(
      rootPath,
      gitMetadataDisposition: gitMetadataDisposition,
      capturePosixExecutableIntent: capturePosixExecutableIntent,
      executableIntentOverrides: executableIntentOverrides,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
      isCancelled: isCancelled,
    ),
  );

  @override
  Future<DraftSnapshotResult<DraftCapture>> capture(
    DraftCaptureRequest request,
  ) => _delegate((worker) => worker.capture(request));

  @override
  Future<DraftSnapshotResult<DraftFingerprint>> fingerprint(
    DraftCaptureRequest request,
  ) => _delegate((worker) => worker.fingerprint(request));

  @override
  Future<void> discardStaging(DraftCapture capture) =>
      _delegate((worker) => worker.discardStaging(capture));

  @override
  Future<DraftSnapshotResult<NormalizedSkillTree>> normalize(
    List<CapturedDraftFile> files, {
    bool Function()? isCancelled,
  }) =>
      _delegate((worker) => worker.normalize(files, isCancelled: isCancelled));

  @override
  Future<String?> readDeclaredName(NormalizedSkillTree tree) =>
      _delegate((worker) => worker.readDeclaredName(tree));

  @override
  Future<CanonicalManifestArtifacts> encodeCanonicalManifest({
    required Map<String, Object?> value,
    required int schemaVersion,
  }) => _delegate(
    (worker) => worker.encodeCanonicalManifest(
      value: value,
      schemaVersion: schemaVersion,
    ),
  );

  @override
  Future<RevisionObjectId> writeTree(
    String repositoryPath,
    NormalizedSkillTree tree,
  ) => _delegate((worker) => worker.writeTree(repositoryPath, tree));

  @override
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commit,
  ) => _delegate((worker) => worker.readTree(repositoryPath, commit));

  @override
  Future<RevisionObjectId> createCommit(
    String repositoryPath,
    RevisionCommitRequest request,
  ) => _delegate((worker) => worker.createCommit(repositoryPath, request));

  @override
  Future<void> verifyCommit(
    String repositoryPath,
    RevisionObjectId commit,
    RevisionCommitRequest expected,
  ) => _delegate(
    (worker) => worker.verifyCommit(repositoryPath, commit, expected),
  );

  @override
  Future<bool> isAncestor({
    required String repositoryPath,
    required RevisionObjectId ancestor,
    required RevisionObjectId descendant,
  }) => _delegate(
    (worker) => worker.isAncestor(
      repositoryPath: repositoryPath,
      ancestor: ancestor,
      descendant: descendant,
    ),
  );

  @override
  Future<List<RevisionChange>> diff({
    required String repositoryPath,
    required RevisionObjectId oldCommit,
    required RevisionObjectId newCommit,
  }) => _delegate(
    (worker) => worker.diff(
      repositoryPath: repositoryPath,
      oldCommit: oldCommit,
      newCommit: newCommit,
    ),
  );

  @override
  Future<RevisionMergeResult> merge({
    required String repositoryPath,
    required RevisionObjectId previousUpstream,
    required RevisionObjectId currentEffective,
    required RevisionObjectId incomingUpstream,
  }) => _delegate(
    (worker) => worker.merge(
      repositoryPath: repositoryPath,
      previousUpstream: previousUpstream,
      currentEffective: currentEffective,
      incomingUpstream: incomingUpstream,
    ),
  );

  @override
  Future<void> createRecoveryPack({
    required String repositoryPath,
    required String bundleStagingPath,
    required List<RevisionObjectId> retainedRoots,
  }) => _delegate(
    (worker) => worker.createRecoveryPack(
      repositoryPath: repositoryPath,
      bundleStagingPath: bundleStagingPath,
      retainedRoots: retainedRoots,
    ),
  );

  @override
  Future<void> restoreRecoveryPack({
    required String stagedRepositoryPath,
    required String packPath,
    required String indexPath,
    required List<RevisionObjectId> retainedRoots,
  }) => _delegate(
    (worker) => worker.restoreRecoveryPack(
      stagedRepositoryPath: stagedRepositoryPath,
      packPath: packPath,
      indexPath: indexPath,
      retainedRoots: retainedRoots,
    ),
  );

  @override
  Future<void> buildRevisionBundleArtifacts({
    required String repositoryPath,
    required String bundlePath,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedRoots,
  }) => _delegate(
    (worker) => worker.buildRevisionBundleArtifacts(
      repositoryPath: repositoryPath,
      bundlePath: bundlePath,
      sourceLineage: sourceLineage,
      currentUpstream: currentUpstream,
      currentEffective: currentEffective,
      retainedRoots: retainedRoots,
    ),
  );

  @override
  Future<void> verifyRevisionBundleArtifacts({
    required String bundlePath,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedRoots,
  }) => _delegate(
    (worker) => worker.verifyRevisionBundleArtifacts(
      bundlePath: bundlePath,
      sourceLineage: sourceLineage,
      currentUpstream: currentUpstream,
      currentEffective: currentEffective,
      retainedRoots: retainedRoots,
    ),
  );

  @override
  Future<void> replaceRetentionRefs(
    String repositoryPath,
    List<RevisionRetentionRef> references,
  ) => _delegate(
    (worker) => worker.replaceRetentionRefs(repositoryPath, references),
  );

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } on Object {
        // Startup failure already owns worker cleanup.
      }
    }
    final worker = _worker;
    _worker = null;
    await worker?.close();
  }
}
