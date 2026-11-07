import '../application/destructive/destructive_operation_models.dart';
import '../application/operations/operation_models.dart';
import '../application/operations/workspace_business_changes.dart';
import '../application/ports/destructive_operation_ports.dart';
import '../application/ports/initial_import_ports.dart';
import '../application/runtime/revision_engine_port.dart';
import '../application/source/source_acquisition_coordinator.dart';
import '../application/source/source_acquisition_models.dart';
import '../domain/cancellation.dart';
import '../infrastructure/workspace_layout.dart';
import '../native/revision_engine/revision_recovery_bundle.dart';
import '../platform/filesystem/durable_workspace_filesystem.dart';
import 'revision_recovery_bundle_publisher.dart';

/// Builds the immutable Source Replacement candidate after the Prepared
/// envelope is durable, without publishing any live Workspace path.
final class WorkspaceSourceReplacementPreparation
    implements SourceReplacementPreparationPort {
  const WorkspaceSourceReplacementPreparation({
    required SourceAcquisitionCoordinator sources,
    required SourcePayloadEncodingPort sourcePayloads,
    required RevisionEnginePort revisions,
    required WorkspaceLayout layout,
    required DurableWorkspaceFilesystem filesystem,
    RevisionRecoveryBundleCodec bundleCodec =
        const RevisionRecoveryBundleCodec(),
  }) : _sources = sources,
       _sourcePayloads = sourcePayloads,
       _revisions = revisions,
       _layout = layout,
       _filesystem = filesystem,
       _bundleCodec = bundleCodec;

  final SourceAcquisitionCoordinator _sources;
  final SourcePayloadEncodingPort _sourcePayloads;
  final RevisionEnginePort _revisions;
  final WorkspaceLayout _layout;
  final DurableWorkspaceFilesystem _filesystem;
  final RevisionRecoveryBundleCodec _bundleCodec;

  @override
  Future<SourceReplacementPreparationResult> prepareSourceReplacement(
    SourceReplacementPreparationIntent intent, {
    required PreparedOperationEnvelope envelope,
    required CancellationToken cancellationToken,
  }) async {
    if (envelope.operationId != intent.operationId) {
      return const SourceReplacementPreparationFailure(
        SourceReplacementPreparationFailureCode.revisionPreparationFailed,
      );
    }
    if (cancellationToken.isCancelled) {
      return const SourceReplacementPreparationFailure(
        SourceReplacementPreparationFailureCode.operationCancelled,
      );
    }
    final acquired = await _sources.acquire(
      source: intent.source,
      selectedSkillNames: const <String>{},
      options: SourceAcquisitionOptions(
        includeInternal: intent.includeInternal,
        fullDepth: intent.fullDepth,
      ),
      cancellationToken: cancellationToken,
    );
    final source = acquired.valueOrNull;
    if (source == null) {
      return SourceReplacementPreparationFailure(
        _sourceFailure(acquired.failureOrNull!.code),
      );
    }
    if (source.skills.length != 1) {
      return const SourceReplacementPreparationFailure(
        SourceReplacementPreparationFailureCode.sourceAmbiguous,
      );
    }
    final skill = source.skills.single;
    final payload = _sourcePayloads.encode(skill.provenance);
    if (payload is! SourcePayloadEncoded) {
      return const SourceReplacementPreparationFailure(
        SourceReplacementPreparationFailureCode.sourcePayloadInvalid,
      );
    }
    if (cancellationToken.isCancelled) {
      return const SourceReplacementPreparationFailure(
        SourceReplacementPreparationFailureCode.operationCancelled,
      );
    }

    final candidateRoot = _layout.operationSourceReplacementRoot(
      intent.operationId,
    );
    final storePath = _layout.operationSourceReplacementStore(
      intent.operationId,
    );
    final bundlePath = _layout.operationSourceReplacementBundle(
      intent.operationId,
    );
    try {
      await _filesystem.removeOwnedPath(
        targetPath: candidateRoot,
        ownerRoot: _layout.stagingRoot,
      );
      await _filesystem.ensureDirectory(candidateRoot);
      await _revisions.createStore(storePath);
      _throwIfCancelled(cancellationToken);
      final tree = await _revisions.writeTree(storePath, skill.tree);
      final request = RevisionCommitRequest(
        tree: tree,
        parents: const [],
        kind: RevisionCommitKind.initial,
      );
      final commit = await _revisions.createCommit(storePath, request);
      await _revisions.verifyCommit(storePath, commit, request);
      _throwIfCancelled(cancellationToken);
      await RevisionRecoveryBundlePublisher(
        revisions: _revisions,
        filesystem: _filesystem,
        codec: _bundleCodec,
      ).publish(
        repositoryPath: storePath,
        bundlePath: bundlePath,
        operationStagingRoot: _layout.operationStagingPath(intent.operationId),
        sourceLineage: intent.intendedSourceLineage,
        currentUpstream: commit,
        currentEffective: commit,
        retainedPublishedRoots: <RevisionObjectId>[commit],
      );
      _throwIfCancelled(cancellationToken);
      return SourceReplacementPreparationSuccess(
        PreparedSourceReplacement(
          managedSkillId: intent.managedSkillId,
          sourceLineage: intent.intendedSourceLineage,
          objectId: commit,
          objectFormat: WorkspaceObjectFormat.sha1,
          persistedSourceKind: payload.payload.kind,
          sourcePayloadSchemaVersion: payload.payload.payloadSchemaVersion,
          sourcePayloadJson: payload.payload.payloadJson,
          slotKey: skill.slotKey,
          declaredName: skill.declaredName,
          displayName: skill.declaredName,
          description: skill.description,
          contentHash: skill.tree.contentHash,
          fileCount: skill.tree.fileCount,
          byteSize: skill.tree.byteSize,
        ),
      );
    } on _PreparationCancelled {
      await _cleanup(candidateRoot);
      return const SourceReplacementPreparationFailure(
        SourceReplacementPreparationFailureCode.operationCancelled,
      );
    } on RevisionEngineException {
      await _cleanup(candidateRoot);
      return const SourceReplacementPreparationFailure(
        SourceReplacementPreparationFailureCode.revisionPreparationFailed,
      );
    } on Object {
      await _cleanup(candidateRoot);
      return const SourceReplacementPreparationFailure(
        SourceReplacementPreparationFailureCode.ioFailure,
      );
    }
  }

  Future<void> _cleanup(String candidateRoot) async {
    try {
      await _filesystem.removeOwnedPath(
        targetPath: candidateRoot,
        ownerRoot: _layout.stagingRoot,
      );
    } on Object {
      // Prepared-envelope recovery retains authority over any residue.
    }
  }
}

SourceReplacementPreparationFailureCode _sourceFailure(
  SourceAcquisitionFailureCode code,
) => switch (code) {
  SourceAcquisitionFailureCode.operationCancelled =>
    SourceReplacementPreparationFailureCode.operationCancelled,
  SourceAcquisitionFailureCode.skillNotFound =>
    SourceReplacementPreparationFailureCode.sourceUnavailable,
  SourceAcquisitionFailureCode.duplicateSkillSlot =>
    SourceReplacementPreparationFailureCode.sourceAmbiguous,
  SourceAcquisitionFailureCode.invalidSkill ||
  SourceAcquisitionFailureCode.unsupportedSkillName ||
  SourceAcquisitionFailureCode.skillContentLimitExceeded =>
    SourceReplacementPreparationFailureCode.sourcePayloadInvalid,
  SourceAcquisitionFailureCode.ioFailure =>
    SourceReplacementPreparationFailureCode.ioFailure,
  // Exhaustive rather than wildcarded: preparation has no vocabulary for a
  // missing host toolchain, so a new acquisition code would otherwise be
  // absorbed here silently instead of forcing this decision.
  SourceAcquisitionFailureCode.sourceUnavailable ||
  SourceAcquisitionFailureCode.sourceAuthenticationRequired ||
  SourceAcquisitionFailureCode.gitUnavailable ||
  SourceAcquisitionFailureCode.gitFailed ||
  SourceAcquisitionFailureCode.gitTimedOut ||
  SourceAcquisitionFailureCode.developerToolsRequired ||
  SourceAcquisitionFailureCode.transportRejected ||
  SourceAcquisitionFailureCode.httpFailure ||
  SourceAcquisitionFailureCode.digestMismatch ||
  SourceAcquisitionFailureCode.archiveInvalid ||
  SourceAcquisitionFailureCode.updateUnsupported =>
    SourceReplacementPreparationFailureCode.sourceUnavailable,
};

void _throwIfCancelled(CancellationToken token) {
  if (token.isCancelled) throw const _PreparationCancelled();
}

final class _PreparationCancelled implements Exception {
  const _PreparationCancelled();
}
