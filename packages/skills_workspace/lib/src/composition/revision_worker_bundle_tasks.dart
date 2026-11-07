import 'dart:io';

import 'package:path/path.dart' as path;

import '../application/runtime/revision_engine_port.dart';
import '../native/revision_engine/revision_recovery_bundle.dart';
import '../native/revision_worker/revision_worker_protocol.dart';

Future<void> writeRevisionBundleManifest(
  RevisionWorkerBuildBundleArtifactsCommand command,
) async {
  final packPath = path.join(command.bundlePath, 'objects.pack');
  final indexPath = path.join(command.bundlePath, 'objects.idx');
  final packBytes = await File(packPath).readAsBytes();
  final indexBytes = await File(indexPath).readAsBytes();
  const codec = RevisionRecoveryBundleCodec();
  final manifest = codec.createManifest(
    sourceLineageId: command.sourceLineageId,
    currentUpstream: RevisionObjectId(command.currentUpstreamOid),
    currentEffective: RevisionObjectId(command.currentEffectiveOid),
    retainedPublishedRoots: command.retainedRootOids
        .map(RevisionObjectId.new)
        .toList(growable: false),
    packBytes: packBytes,
    indexBytes: indexBytes,
  );
  final manifestBytes = codec.encodeManifest(manifest);
  await File(
    path.join(command.bundlePath, 'manifest.json'),
  ).writeAsBytes(manifestBytes, flush: true);
  await File(
    path.join(command.bundlePath, 'COMPLETE'),
  ).writeAsBytes(codec.createCompletionFence(manifestBytes), flush: true);
}

Future<void> verifyRevisionBundleArtifacts(
  RevisionWorkerVerifyBundleArtifactsCommand command,
) async {
  const codec = RevisionRecoveryBundleCodec();
  final manifest = codec.verify(
    manifestBytes: await File(
      path.join(command.bundlePath, 'manifest.json'),
    ).readAsBytes(),
    completionFenceBytes: await File(
      path.join(command.bundlePath, 'COMPLETE'),
    ).readAsBytes(),
    packBytes: await File(
      path.join(command.bundlePath, 'objects.pack'),
    ).readAsBytes(),
    indexBytes: await File(
      path.join(command.bundlePath, 'objects.idx'),
    ).readAsBytes(),
  );
  final expectedRoots = command.retainedRootOids.toSet();
  final actualRoots = manifest.retainedPublishedRoots
      .map((root) => root.value)
      .toSet();
  if (manifest.sourceLineageId != command.sourceLineageId ||
      manifest.currentUpstream.value != command.currentUpstreamOid ||
      manifest.currentEffective.value != command.currentEffectiveOid ||
      expectedRoots.length != actualRoots.length ||
      !actualRoots.containsAll(expectedRoots)) {
    throw StateError('Revision Bundle identity does not match its request.');
  }
}
