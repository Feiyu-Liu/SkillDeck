import 'dart:isolate';
import 'dart:typed_data';

import '../../application/ports/revision_content_worker_ports.dart';
import '../../application/ports/draft_snapshot_ports.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/draft_snapshot.dart';
import '../../domain/revision_content.dart';

const int revisionWorkerProtocolVersion = 6;

typedef RevisionWorkerTaskExecutor =
    Future<Object?> Function(RevisionWorkerCommand command);

final class RevisionWorkerBootstrap {
  const RevisionWorkerBootstrap({
    required this.parentPort,
    required this.protocolVersion,
    this.failBeforeStartup = false,
    this.taskExecutor,
  });

  final SendPort parentPort;
  final int protocolVersion;
  final bool failBeforeStartup;
  final RevisionWorkerTaskExecutor? taskExecutor;
}

sealed class RevisionWorkerInboundMessage {
  const RevisionWorkerInboundMessage();
}

final class RevisionWorkerRequest extends RevisionWorkerInboundMessage {
  const RevisionWorkerRequest({
    required this.protocolVersion,
    required this.requestId,
    required this.command,
  });

  final int protocolVersion;
  final int requestId;
  final RevisionWorkerCommand command;
}

final class RevisionWorkerShutdown extends RevisionWorkerInboundMessage {
  const RevisionWorkerShutdown({required this.protocolVersion});

  final int protocolVersion;
}

sealed class RevisionWorkerCommand {
  const RevisionWorkerCommand();
}

final class RevisionWorkerStatusCommand extends RevisionWorkerCommand {
  const RevisionWorkerStatusCommand({this.delayMicroseconds = 0});

  final int delayMicroseconds;
}

final class RevisionWorkerCreateStoreCommand extends RevisionWorkerCommand {
  const RevisionWorkerCreateStoreCommand(this.repositoryPath);

  final String repositoryPath;
}

final class RevisionWorkerVerifyStoreCommand extends RevisionWorkerCommand {
  const RevisionWorkerVerifyStoreCommand(this.repositoryPath);

  final String repositoryPath;
}

final class RevisionWorkerNormalizeContentCommand
    extends RevisionWorkerCommand {
  const RevisionWorkerNormalizeContentCommand({
    required this.entries,
    required this.maximumFileCount,
    required this.maximumByteSize,
  });

  final List<RevisionWorkerContentEntryPayload> entries;
  final int maximumFileCount;
  final int maximumByteSize;
}

final class RevisionWorkerReadFilesystemTreeCommand
    extends RevisionWorkerCommand {
  const RevisionWorkerReadFilesystemTreeCommand({
    required this.rootPath,
    required this.gitMetadataDisposition,
    required this.capturePosixExecutableIntent,
    required this.executableIntentOverrides,
    required this.maximumFileCount,
    required this.maximumByteSize,
  });

  final String rootPath;
  final GitMetadataDisposition gitMetadataDisposition;
  final bool capturePosixExecutableIntent;
  final Map<String, bool> executableIntentOverrides;
  final int maximumFileCount;
  final int maximumByteSize;
}

final class RevisionWorkerCaptureDraftCommand extends RevisionWorkerCommand {
  const RevisionWorkerCaptureDraftCommand(this.request);

  final RevisionWorkerDraftCaptureRequestPayload request;
}

final class RevisionWorkerFingerprintDraftCommand
    extends RevisionWorkerCommand {
  const RevisionWorkerFingerprintDraftCommand(this.request);

  final RevisionWorkerDraftCaptureRequestPayload request;
}

final class RevisionWorkerDiscardDraftCaptureCommand
    extends RevisionWorkerCommand {
  const RevisionWorkerDiscardDraftCaptureCommand(this.stagingPath);

  final String stagingPath;
}

final class RevisionWorkerNormalizeDraftCommand extends RevisionWorkerCommand {
  const RevisionWorkerNormalizeDraftCommand(this.files);

  final List<RevisionWorkerCapturedDraftFilePayload> files;
}

final class RevisionWorkerReadDeclaredNameCommand
    extends RevisionWorkerCommand {
  const RevisionWorkerReadDeclaredNameCommand(this.tree);

  final RevisionWorkerTreePayload tree;
}

final class RevisionWorkerEncodeCanonicalManifestCommand
    extends RevisionWorkerCommand {
  RevisionWorkerEncodeCanonicalManifestCommand({
    required Map<String, Object?> value,
    required this.schemaVersion,
  }) : value = Map<String, Object?>.unmodifiable(value);

  final Map<String, Object?> value;
  final int schemaVersion;
}

final class RevisionWorkerWriteTreeCommand extends RevisionWorkerCommand {
  const RevisionWorkerWriteTreeCommand({
    required this.repositoryPath,
    required this.files,
    required this.contentHash,
    required this.byteSize,
  });

  final String repositoryPath;
  final List<RevisionWorkerFilePayload> files;
  final String contentHash;
  final int byteSize;
}

final class RevisionWorkerReadTreeCommand extends RevisionWorkerCommand {
  const RevisionWorkerReadTreeCommand({
    required this.repositoryPath,
    required this.commitOid,
  });

  final String repositoryPath;
  final String commitOid;
}

final class RevisionWorkerCreateCommitCommand extends RevisionWorkerCommand {
  const RevisionWorkerCreateCommitCommand({
    required this.repositoryPath,
    required this.treeOid,
    required this.parentOids,
    required this.kindIndex,
  });

  final String repositoryPath;
  final String treeOid;
  final List<String> parentOids;
  final int kindIndex;
}

final class RevisionWorkerVerifyCommitCommand extends RevisionWorkerCommand {
  const RevisionWorkerVerifyCommitCommand({
    required this.repositoryPath,
    required this.commitOid,
    required this.treeOid,
    required this.parentOids,
    required this.kindIndex,
  });

  final String repositoryPath;
  final String commitOid;
  final String treeOid;
  final List<String> parentOids;
  final int kindIndex;
}

final class RevisionWorkerIsAncestorCommand extends RevisionWorkerCommand {
  const RevisionWorkerIsAncestorCommand({
    required this.repositoryPath,
    required this.ancestorOid,
    required this.descendantOid,
  });

  final String repositoryPath;
  final String ancestorOid;
  final String descendantOid;
}

final class RevisionWorkerDiffCommand extends RevisionWorkerCommand {
  const RevisionWorkerDiffCommand({
    required this.repositoryPath,
    required this.oldCommitOid,
    required this.newCommitOid,
  });

  final String repositoryPath;
  final String oldCommitOid;
  final String newCommitOid;
}

final class RevisionWorkerMergeCommand extends RevisionWorkerCommand {
  const RevisionWorkerMergeCommand({
    required this.repositoryPath,
    required this.previousUpstreamOid,
    required this.currentEffectiveOid,
    required this.incomingUpstreamOid,
  });

  final String repositoryPath;
  final String previousUpstreamOid;
  final String currentEffectiveOid;
  final String incomingUpstreamOid;
}

final class RevisionWorkerCreateRecoveryPackCommand
    extends RevisionWorkerCommand {
  const RevisionWorkerCreateRecoveryPackCommand({
    required this.repositoryPath,
    required this.bundleStagingPath,
    required this.retainedRootOids,
  });

  final String repositoryPath;
  final String bundleStagingPath;
  final List<String> retainedRootOids;
}

final class RevisionWorkerRestoreRecoveryPackCommand
    extends RevisionWorkerCommand {
  const RevisionWorkerRestoreRecoveryPackCommand({
    required this.stagedRepositoryPath,
    required this.packPath,
    required this.indexPath,
    required this.retainedRootOids,
  });

  final String stagedRepositoryPath;
  final String packPath;
  final String indexPath;
  final List<String> retainedRootOids;
}

final class RevisionWorkerBuildBundleArtifactsCommand
    extends RevisionWorkerCommand {
  RevisionWorkerBuildBundleArtifactsCommand({
    required this.repositoryPath,
    required this.bundlePath,
    required this.sourceLineageId,
    required this.currentUpstreamOid,
    required this.currentEffectiveOid,
    required List<String> retainedRootOids,
  }) : retainedRootOids = List<String>.unmodifiable(retainedRootOids);

  final String repositoryPath;
  final String bundlePath;
  final String sourceLineageId;
  final String currentUpstreamOid;
  final String currentEffectiveOid;
  final List<String> retainedRootOids;
}

final class RevisionWorkerVerifyBundleArtifactsCommand
    extends RevisionWorkerCommand {
  RevisionWorkerVerifyBundleArtifactsCommand({
    required this.bundlePath,
    required this.sourceLineageId,
    required this.currentUpstreamOid,
    required this.currentEffectiveOid,
    required List<String> retainedRootOids,
  }) : retainedRootOids = List<String>.unmodifiable(retainedRootOids);

  final String bundlePath;
  final String sourceLineageId;
  final String currentUpstreamOid;
  final String currentEffectiveOid;
  final List<String> retainedRootOids;
}

final class RevisionWorkerReplaceRetentionRefsCommand
    extends RevisionWorkerCommand {
  const RevisionWorkerReplaceRetentionRefsCommand({
    required this.repositoryPath,
    required this.references,
  });

  final String repositoryPath;
  final List<RevisionWorkerRetentionRefPayload> references;
}

final class RevisionWorkerRetentionRefPayload {
  const RevisionWorkerRetentionRefPayload({
    required this.name,
    required this.targetOid,
  });

  final String name;
  final String targetOid;
}

final class RevisionWorkerCrashCommand extends RevisionWorkerCommand {
  const RevisionWorkerCrashCommand();
}

final class RevisionWorkerFilePayload {
  const RevisionWorkerFilePayload({
    required this.relativePath,
    required this.bytes,
    required this.isExecutable,
  });

  factory RevisionWorkerFilePayload.fromFile(NormalizedSkillFile file) =>
      RevisionWorkerFilePayload(
        relativePath: file.relativePath,
        bytes: TransferableTypedData.fromList(<Uint8List>[
          Uint8List.fromList(file.bytes),
        ]),
        isExecutable: file.isExecutable,
      );

  final String relativePath;
  final TransferableTypedData bytes;
  final bool isExecutable;

  NormalizedSkillFile materialize() => NormalizedSkillFile(
    relativePath: relativePath,
    bytes: bytes.materialize().asUint8List(),
    isExecutable: isExecutable,
  );
}

final class RevisionWorkerContentEntryPayload {
  const RevisionWorkerContentEntryPayload({
    required this.pathBytes,
    required this.bytes,
    required this.isExecutable,
    required this.kindIndex,
  });

  factory RevisionWorkerContentEntryPayload.fromEntry(
    SkillContentEntry entry,
  ) => RevisionWorkerContentEntryPayload(
    pathBytes: TransferableTypedData.fromList(<Uint8List>[
      Uint8List.fromList(entry.pathBytes),
    ]),
    bytes: TransferableTypedData.fromList(<Uint8List>[
      Uint8List.fromList(entry.bytes),
    ]),
    isExecutable: entry.isExecutable,
    kindIndex: entry.kind.index,
  );

  final TransferableTypedData pathBytes;
  final TransferableTypedData bytes;
  final bool isExecutable;
  final int kindIndex;

  SkillContentEntry materialize() {
    if (kindIndex < 0 || kindIndex >= SkillContentEntryKind.values.length) {
      throw ArgumentError.value(kindIndex, 'kindIndex');
    }
    return SkillContentEntry(
      pathBytes: pathBytes.materialize().asUint8List(),
      bytes: bytes.materialize().asUint8List(),
      isExecutable: isExecutable,
      kind: SkillContentEntryKind.values[kindIndex],
    );
  }
}

final class RevisionWorkerDraftCaptureRequestPayload {
  RevisionWorkerDraftCaptureRequestPayload({
    required this.liveDraftPath,
    required this.stagingDestinationPath,
    required this.capturePosixExecutableIntent,
    required Map<String, bool> executableIntentOverrides,
    required this.maximumFileCount,
    required this.maximumByteSize,
  }) : executableIntentOverrides = Map<String, bool>.unmodifiable(
         executableIntentOverrides,
       );

  factory RevisionWorkerDraftCaptureRequestPayload.fromRequest(
    DraftCaptureRequest request,
  ) => RevisionWorkerDraftCaptureRequestPayload(
    liveDraftPath: request.liveDraftPath,
    stagingDestinationPath: request.stagingDestinationPath,
    capturePosixExecutableIntent: request.capturePosixExecutableIntent,
    executableIntentOverrides: request.executableIntentOverrides,
    maximumFileCount: request.maximumFileCount,
    maximumByteSize: request.maximumByteSize,
  );

  final String liveDraftPath;
  final String stagingDestinationPath;
  final bool capturePosixExecutableIntent;
  final Map<String, bool> executableIntentOverrides;
  final int maximumFileCount;
  final int maximumByteSize;

  DraftCaptureRequest materialize() => DraftCaptureRequest(
    liveDraftPath: liveDraftPath,
    stagingDestinationPath: stagingDestinationPath,
    capturePosixExecutableIntent: capturePosixExecutableIntent,
    executableIntentOverrides: executableIntentOverrides,
    maximumFileCount: maximumFileCount,
    maximumByteSize: maximumByteSize,
  );
}

final class RevisionWorkerCapturedDraftFilePayload {
  const RevisionWorkerCapturedDraftFilePayload({
    required this.relativePath,
    required this.bytes,
    required this.isExecutable,
  });

  factory RevisionWorkerCapturedDraftFilePayload.fromFile(
    CapturedDraftFile file,
  ) => RevisionWorkerCapturedDraftFilePayload(
    relativePath: file.relativePath,
    bytes: TransferableTypedData.fromList(<Uint8List>[
      Uint8List.fromList(file.bytes),
    ]),
    isExecutable: file.isExecutable,
  );

  final String relativePath;
  final TransferableTypedData bytes;
  final bool isExecutable;

  CapturedDraftFile materialize() => CapturedDraftFile(
    relativePath: relativePath,
    bytes: bytes.materialize().asUint8List(),
    isExecutable: isExecutable,
  );
}

final class RevisionWorkerDraftCapturePayload {
  const RevisionWorkerDraftCapturePayload({
    required this.liveDraftPath,
    required this.stagingPath,
    required this.fingerprint,
    required this.files,
  });

  factory RevisionWorkerDraftCapturePayload.fromCapture(DraftCapture capture) =>
      RevisionWorkerDraftCapturePayload(
        liveDraftPath: capture.liveDraftPath,
        stagingPath: capture.stagingPath,
        fingerprint: capture.fingerprint,
        files: capture.files
            .map(RevisionWorkerCapturedDraftFilePayload.fromFile)
            .toList(growable: false),
      );

  final String liveDraftPath;
  final String stagingPath;
  final DraftFingerprint fingerprint;
  final List<RevisionWorkerCapturedDraftFilePayload> files;

  DraftCapture materialize() => DraftCapture(
    liveDraftPath: liveDraftPath,
    stagingPath: stagingPath,
    fingerprint: fingerprint,
    files: files.map((file) => file.materialize()).toList(growable: false),
  );
}

sealed class RevisionWorkerDraftResultPayload {
  const RevisionWorkerDraftResultPayload();
}

final class RevisionWorkerDraftCaptureSuccessPayload
    extends RevisionWorkerDraftResultPayload {
  const RevisionWorkerDraftCaptureSuccessPayload(this.capture);

  final RevisionWorkerDraftCapturePayload capture;
}

final class RevisionWorkerDraftFingerprintSuccessPayload
    extends RevisionWorkerDraftResultPayload {
  const RevisionWorkerDraftFingerprintSuccessPayload(this.fingerprint);

  final DraftFingerprint fingerprint;
}

final class RevisionWorkerDraftTreeSuccessPayload
    extends RevisionWorkerDraftResultPayload {
  const RevisionWorkerDraftTreeSuccessPayload(this.tree);

  final RevisionWorkerTreePayload tree;
}

final class RevisionWorkerDraftFailurePayload
    extends RevisionWorkerDraftResultPayload {
  RevisionWorkerDraftFailurePayload({
    required this.codeIndex,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map<String, Object?>.unmodifiable(context);

  final int codeIndex;
  final Map<String, Object?> context;
}

final class RevisionWorkerCanonicalManifestPayload {
  const RevisionWorkerCanonicalManifestPayload({
    required this.manifestBytes,
    required this.completionFenceBytes,
  });

  final TransferableTypedData manifestBytes;
  final TransferableTypedData completionFenceBytes;
}

sealed class RevisionWorkerSkillContentResultPayload {
  const RevisionWorkerSkillContentResultPayload();
}

final class RevisionWorkerSkillContentSuccessPayload
    extends RevisionWorkerSkillContentResultPayload {
  const RevisionWorkerSkillContentSuccessPayload(this.tree);

  final RevisionWorkerTreePayload tree;
}

final class RevisionWorkerSkillContentFailurePayload
    extends RevisionWorkerSkillContentResultPayload {
  RevisionWorkerSkillContentFailurePayload({
    required this.codeIndex,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map<String, Object?>.unmodifiable(context);

  factory RevisionWorkerSkillContentFailurePayload.fromFailure(
    SkillContentFailure<NormalizedSkillTree> failure,
  ) => RevisionWorkerSkillContentFailurePayload(
    codeIndex: failure.code.index,
    context: failure.context,
  );

  final int codeIndex;
  final Map<String, Object?> context;
}

final class RevisionWorkerTreePayload {
  const RevisionWorkerTreePayload({
    required this.files,
    required this.contentHash,
    required this.byteSize,
  });

  factory RevisionWorkerTreePayload.fromTree(NormalizedSkillTree tree) =>
      RevisionWorkerTreePayload(
        files: tree.files
            .map(RevisionWorkerFilePayload.fromFile)
            .toList(growable: false),
        contentHash: tree.contentHash,
        byteSize: tree.byteSize,
      );

  final List<RevisionWorkerFilePayload> files;
  final String contentHash;
  final int byteSize;

  NormalizedSkillTree materialize() => NormalizedSkillTree(
    files: files.map((file) => file.materialize()).toList(growable: false),
    contentHash: contentHash,
    byteSize: byteSize,
  );
}

sealed class RevisionWorkerMergePayload {
  const RevisionWorkerMergePayload();
}

final class RevisionWorkerMergeCleanPayload extends RevisionWorkerMergePayload {
  const RevisionWorkerMergeCleanPayload(this.treeOid);

  final String treeOid;
}

final class RevisionWorkerMergeConflictedPayload
    extends RevisionWorkerMergePayload {
  const RevisionWorkerMergeConflictedPayload({
    required this.treeOid,
    required this.conflicts,
  });

  final String treeOid;
  final List<RevisionMergeConflict> conflicts;
}

sealed class RevisionWorkerOutboundMessage {
  const RevisionWorkerOutboundMessage({required this.protocolVersion});

  final int protocolVersion;
}

final class RevisionWorkerStarted extends RevisionWorkerOutboundMessage {
  const RevisionWorkerStarted({
    required super.protocolVersion,
    required this.commandPort,
  });

  final SendPort commandPort;
}

final class RevisionWorkerSucceeded extends RevisionWorkerOutboundMessage {
  const RevisionWorkerSucceeded({
    required super.protocolVersion,
    required this.requestId,
    required this.payload,
  });

  final int requestId;
  final Object? payload;
}

final class RevisionWorkerRejected extends RevisionWorkerOutboundMessage {
  const RevisionWorkerRejected({
    required super.protocolVersion,
    required this.requestId,
    required this.code,
    this.operationFailureCode,
  });

  final int requestId;
  final RevisionWorkerWireFailureCode code;
  final RevisionEngineFailureCode? operationFailureCode;
}

final class RevisionWorkerStopped extends RevisionWorkerOutboundMessage {
  const RevisionWorkerStopped({required super.protocolVersion});
}

final class RevisionWorkerFatal extends RevisionWorkerOutboundMessage {
  const RevisionWorkerFatal({required super.protocolVersion});
}

enum RevisionWorkerWireFailureCode {
  protocolMismatch,
  unsupportedCommand,
  operationFailed,
}
