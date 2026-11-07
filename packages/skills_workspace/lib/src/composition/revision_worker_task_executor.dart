import '../native/revision_worker/revision_worker_protocol.dart';
import 'revision_worker_bundle_tasks.dart';
import 'revision_worker_content_tasks.dart';
import 'revision_worker_manifest_tasks.dart';

Future<Object?> executeComposedRevisionWorkerTask(
  RevisionWorkerCommand command,
) async => switch (command) {
  RevisionWorkerBuildBundleArtifactsCommand() => writeRevisionBundleManifest(
    command,
  ),
  RevisionWorkerVerifyBundleArtifactsCommand() => verifyRevisionBundleArtifacts(
    command,
  ),
  RevisionWorkerEncodeCanonicalManifestCommand() =>
    encodeCanonicalManifestInWorker(command),
  _ => executeRevisionContentTask(command),
};
