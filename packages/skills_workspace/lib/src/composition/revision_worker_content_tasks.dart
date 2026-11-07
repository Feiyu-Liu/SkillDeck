import 'package:path/path.dart' as path;

import '../application/ports/draft_snapshot_ports.dart';
import '../infrastructure/content/draft_content_adapter.dart';
import '../infrastructure/content/filesystem_skill_tree_reader.dart';
import '../infrastructure/content/normalized_skill_tree.dart';
import '../native/revision_worker/revision_worker_protocol.dart';
import '../platform/filesystem/durable_workspace_filesystem.dart';
import '../platform/filesystem/filesystem_draft_snapshot.dart';

/// Executes source-agnostic content preparation inside the Revision isolate.
///
/// The worker wire protocol remains private. Infrastructure normalizers and
/// filesystem readers are composed here instead of crossing into application
/// ports or public APIs.
Future<Object?> executeRevisionContentTask(
  RevisionWorkerCommand command,
) async {
  if (command case RevisionWorkerCaptureDraftCommand(:final request)) {
    final result = await _draftFilesystem.capture(request.materialize());
    final failure = result.failureOrNull;
    if (failure != null) return _draftFailure(failure);
    return RevisionWorkerDraftCaptureSuccessPayload(
      RevisionWorkerDraftCapturePayload.fromCapture(result.valueOrNull!),
    );
  }
  if (command case RevisionWorkerFingerprintDraftCommand(:final request)) {
    final result = await _draftFilesystem.fingerprint(request.materialize());
    final failure = result.failureOrNull;
    if (failure != null) return _draftFailure(failure);
    return RevisionWorkerDraftFingerprintSuccessPayload(result.valueOrNull!);
  }
  if (command case RevisionWorkerDiscardDraftCaptureCommand(
    :final stagingPath,
  )) {
    await _draftFilesystemPrimitives.removeOwnedPath(
      targetPath: stagingPath,
      ownerRoot: path.dirname(stagingPath),
    );
    return null;
  }
  if (command case RevisionWorkerNormalizeDraftCommand(:final files)) {
    final result = await _draftContent.normalize(
      files.map((file) => file.materialize()).toList(growable: false),
    );
    final failure = result.failureOrNull;
    if (failure != null) return _draftFailure(failure);
    return RevisionWorkerDraftTreeSuccessPayload(
      RevisionWorkerTreePayload.fromTree(result.valueOrNull!),
    );
  }
  if (command case RevisionWorkerReadDeclaredNameCommand(:final tree)) {
    return _draftContent.readDeclaredName(tree.materialize());
  }

  final result = switch (command) {
    RevisionWorkerNormalizeContentCommand(
      :final entries,
      :final maximumFileCount,
      :final maximumByteSize,
    ) =>
      SkillContentNormalizer(
        maximumFileCount: maximumFileCount,
        maximumByteSize: maximumByteSize,
      ).normalize(entries.map((entry) => entry.materialize())),
    RevisionWorkerReadFilesystemTreeCommand(
      :final rootPath,
      :final gitMetadataDisposition,
      :final capturePosixExecutableIntent,
      :final executableIntentOverrides,
      :final maximumFileCount,
      :final maximumByteSize,
    ) =>
      await FilesystemSkillTreeReader(
        gitMetadataDisposition: gitMetadataDisposition,
        normalizer: SkillContentNormalizer(
          maximumFileCount: maximumFileCount,
          maximumByteSize: maximumByteSize,
        ),
        capturePosixExecutableIntent: capturePosixExecutableIntent,
        executableIntentOverrides: executableIntentOverrides,
      ).read(rootPath),
    _ => throw ArgumentError.value(command, 'command'),
  };
  final failure = result.failureOrNull;
  if (failure != null) {
    return RevisionWorkerSkillContentFailurePayload.fromFailure(failure);
  }
  return RevisionWorkerSkillContentSuccessPayload(
    RevisionWorkerTreePayload.fromTree(result.valueOrNull!),
  );
}

RevisionWorkerDraftFailurePayload _draftFailure<T>(
  DraftSnapshotFailure<T> failure,
) => RevisionWorkerDraftFailurePayload(
  codeIndex: failure.code.index,
  context: failure.context,
);

final _draftFilesystemPrimitives = PlatformDurableWorkspaceFilesystem();
final _draftFilesystem = FilesystemDraftSnapshotAdapter(
  filesystem: _draftFilesystemPrimitives,
);
const _draftContent = NormalizedDraftContentAdapter();
