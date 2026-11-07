import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../application/operations/operation_models.dart';
import '../application/ports/revision_bundle_worker_ports.dart';
import '../application/runtime/revision_engine_port.dart';
import '../native/revision_engine/revision_recovery_bundle.dart';
import '../platform/filesystem/durable_workspace_filesystem.dart';

/// Publishes and reopens one complete Revision Recovery Bundle.
///
/// Candidate construction stays operation-private. The caller remains
/// responsible for atomically moving the verified Bundle into its live path.
final class RevisionRecoveryBundlePublisher {
  const RevisionRecoveryBundlePublisher({
    required RevisionEnginePort revisions,
    required DurableWorkspaceFilesystem filesystem,
    RevisionRecoveryBundleCodec codec = const RevisionRecoveryBundleCodec(),
  }) : _revisions = revisions,
       _filesystem = filesystem,
       _codec = codec;

  final RevisionEnginePort _revisions;
  final DurableWorkspaceFilesystem _filesystem;
  final RevisionRecoveryBundleCodec _codec;

  Future<void> publish({
    required String repositoryPath,
    required String bundlePath,
    required String operationStagingRoot,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedPublishedRoots,
  }) async {
    final rootsByObjectId = <String, RevisionObjectId>{
      for (final root in retainedPublishedRoots) root.value: root,
      currentUpstream.value: currentUpstream,
      currentEffective.value: currentEffective,
    };
    final roots = rootsByObjectId.values.toList()
      ..sort((left, right) => left.value.compareTo(right.value));

    await _filesystem.ensureDirectory(bundlePath);
    final bundleWorker = _revisions is RevisionBundleWorkerPort
        ? _revisions as RevisionBundleWorkerPort
        : null;
    if (bundleWorker != null) {
      await bundleWorker.buildRevisionBundleArtifacts(
        repositoryPath: repositoryPath,
        bundlePath: bundlePath,
        sourceLineage: sourceLineage,
        currentUpstream: currentUpstream,
        currentEffective: currentEffective,
        retainedRoots: roots,
      );
    } else {
      await _revisions.createRecoveryPack(
        repositoryPath: repositoryPath,
        bundleStagingPath: bundlePath,
        retainedRoots: roots,
      );
    }
    await _filesystem.flushRecursively(repositoryPath);

    final packPath = path.join(bundlePath, 'objects.pack');
    final indexPath = path.join(bundlePath, 'objects.idx');
    final manifestPath = path.join(bundlePath, 'manifest.json');
    final fencePath = path.join(bundlePath, 'COMPLETE');
    if (bundleWorker == null) {
      final packBytes = await File(packPath).readAsBytes();
      final indexBytes = await File(indexPath).readAsBytes();
      final manifest = _codec.createManifest(
        sourceLineageId: sourceLineage.encoded,
        currentUpstream: currentUpstream,
        currentEffective: currentEffective,
        retainedPublishedRoots: roots,
        packBytes: packBytes,
        indexBytes: indexBytes,
      );
      final manifestBytes = _codec.encodeManifest(manifest);
      await _filesystem.writeDurableFile(manifestPath, manifestBytes);
      await _filesystem.writeDurableFile(
        fencePath,
        _codec.createCompletionFence(manifestBytes),
      );
    }
    await _filesystem.flushRecursively(bundlePath);

    if (bundleWorker != null) {
      await bundleWorker.verifyRevisionBundleArtifacts(
        bundlePath: bundlePath,
        sourceLineage: sourceLineage,
        currentUpstream: currentUpstream,
        currentEffective: currentEffective,
        retainedRoots: roots,
      );
    } else {
      _codec.verify(
        manifestBytes: await File(manifestPath).readAsBytes(),
        completionFenceBytes: await File(fencePath).readAsBytes(),
        packBytes: await File(packPath).readAsBytes(),
        indexBytes: await File(indexPath).readAsBytes(),
      );
    }

    final verificationKey = sha256
        .convert(utf8.encode(path.normalize(bundlePath)))
        .toString()
        .substring(0, 16);
    final verificationStore = path.join(
      operationStagingRoot,
      '.verify-$verificationKey.git',
    );
    await _filesystem.removeOwnedPath(
      targetPath: verificationStore,
      ownerRoot: operationStagingRoot,
    );
    try {
      await _revisions.restoreRecoveryPack(
        stagedRepositoryPath: verificationStore,
        packPath: packPath,
        indexPath: indexPath,
        retainedRoots: roots,
      );
      await _revisions.verifyStore(verificationStore);
      for (final root in roots) {
        await _revisions.readTree(verificationStore, root);
      }
    } finally {
      await _filesystem.removeOwnedPath(
        targetPath: verificationStore,
        ownerRoot: operationStagingRoot,
      );
    }
  }
}
