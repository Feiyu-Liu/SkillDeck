import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';

/// Existing content-only fakes fail explicitly if object import is requested.
mixin UnsupportedRevisionObjectGraph {
  Future<RevisionCommitTopology> inspectCommit(
    String repositoryPath,
    RevisionObjectId commit, {
    RevisionCommitInspectionLimits limits =
        const RevisionCommitInspectionLimits(),
  }) async => throw UnsupportedError('Commit topology is not modeled.');

  Future<void> createPackIndex({
    required String packPath,
    required String stagingDirectory,
    RevisionObjectImportLimits limits = const RevisionObjectImportLimits(),
    CancellationToken? cancellationToken,
  }) async => throw UnsupportedError('Pack index is not modeled.');

  Future<RevisionObjectImportReport> importObjects({
    required String repositoryPath,
    required String stagedRepositoryPath,
    required List<RevisionObjectId> retainedRoots,
    RevisionObjectImportLimits limits = const RevisionObjectImportLimits(),
    CancellationToken? cancellationToken,
  }) async => throw UnsupportedError('Object import is not modeled.');
}
