import '../operations/operation_models.dart';
import '../runtime/revision_engine_port.dart';

/// Worker-owned construction and verification of Revision Bundle artifacts.
///
/// Durable publication remains a filesystem concern. Pack/index generation,
/// canonical manifest encoding, SHA-256 digests, and reopen verification stay
/// inside the same long-lived Revision worker that owns libgit2.
abstract interface class RevisionBundleWorkerPort {
  Future<void> buildRevisionBundleArtifacts({
    required String repositoryPath,
    required String bundlePath,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedRoots,
  });

  Future<void> verifyRevisionBundleArtifacts({
    required String bundlePath,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedRoots,
  });
}
