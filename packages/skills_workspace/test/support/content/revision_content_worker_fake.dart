import 'package:skills_workspace/src/application/ports/revision_content_worker_ports.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/infrastructure/content/direct_revision_content_worker.dart';

final class RecordingRevisionContentWorker
    implements RevisionContentWorkerPort {
  RecordingRevisionContentWorker({
    RevisionContentWorkerPort delegate = const DirectRevisionContentWorker(),
  }) : _delegate = delegate;

  final RevisionContentWorkerPort _delegate;
  int normalizationCalls = 0;
  int filesystemReadCalls = 0;

  @override
  Future<SkillContentResult<NormalizedSkillTree>> normalizeContent(
    List<SkillContentEntry> entries, {
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) {
    normalizationCalls += 1;
    return _delegate.normalizeContent(
      entries,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
      isCancelled: isCancelled,
    );
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
  }) {
    filesystemReadCalls += 1;
    return _delegate.readFilesystemTree(
      rootPath,
      gitMetadataDisposition: gitMetadataDisposition,
      capturePosixExecutableIntent: capturePosixExecutableIntent,
      executableIntentOverrides: executableIntentOverrides,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
      isCancelled: isCancelled,
    );
  }
}
