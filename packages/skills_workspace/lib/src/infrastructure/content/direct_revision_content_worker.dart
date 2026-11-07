import '../../application/ports/revision_content_worker_ports.dart';
import 'filesystem_skill_tree_reader.dart';
import 'normalized_skill_tree.dart';

/// Direct adapter retained for focused infrastructure tests and standalone
/// adapter use. The production repository injects the long-lived Revision
/// worker instead.
final class DirectRevisionContentWorker implements RevisionContentWorkerPort {
  const DirectRevisionContentWorker();

  @override
  Future<SkillContentResult<NormalizedSkillTree>> normalizeContent(
    List<SkillContentEntry> entries, {
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) async => SkillContentNormalizer(
    maximumFileCount: maximumFileCount,
    maximumByteSize: maximumByteSize,
  ).normalize(entries, isCancelled: isCancelled);

  @override
  Future<SkillContentResult<NormalizedSkillTree>> readFilesystemTree(
    String rootPath, {
    required GitMetadataDisposition gitMetadataDisposition,
    required bool capturePosixExecutableIntent,
    required Map<String, bool> executableIntentOverrides,
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) => FilesystemSkillTreeReader(
    gitMetadataDisposition: gitMetadataDisposition,
    normalizer: SkillContentNormalizer(
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
    ),
    capturePosixExecutableIntent: capturePosixExecutableIntent,
    executableIntentOverrides: executableIntentOverrides,
  ).read(rootPath, isCancelled: isCancelled);
}
