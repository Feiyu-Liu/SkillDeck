import 'dart:convert';

import '../../application/ports/draft_snapshot_ports.dart';
import '../../domain/draft_snapshot.dart';
import '../source/frontmatter_parser.dart';
import 'content_result.dart';
import 'normalized_skill_tree.dart';

final class NormalizedDraftContentAdapter implements DraftContentPort {
  const NormalizedDraftContentAdapter({
    this.normalizer = const SkillContentNormalizer(),
  });

  final SkillContentNormalizer normalizer;

  @override
  Future<DraftSnapshotResult<NormalizedSkillTree>> normalize(
    List<CapturedDraftFile> files, {
    bool Function()? isCancelled,
  }) async {
    final result = normalizer.normalize(
      files.map(
        (file) => SkillContentEntry.file(
          path: file.relativePath,
          bytes: file.bytes,
          isExecutable: file.isExecutable,
        ),
      ),
      isCancelled: isCancelled,
    );
    return switch (result) {
      SkillContentSuccess<NormalizedSkillTree>(:final value) =>
        DraftSnapshotSuccess<NormalizedSkillTree>(value),
      SkillContentFailure<NormalizedSkillTree>(:final code, :final context) =>
        DraftSnapshotFailure<NormalizedSkillTree>(
          code: _mapFailure(code),
          context: context,
        ),
    };
  }

  @override
  Future<String?> readDeclaredName(NormalizedSkillTree tree) async {
    NormalizedSkillFile? skillDocument;
    for (final file in tree.files) {
      if (file.relativePath == 'SKILL.md') {
        skillDocument = file;
        break;
      }
    }
    if (skillDocument == null) {
      return null;
    }
    try {
      final source = utf8.decode(skillDocument.bytes, allowMalformed: false);
      return parseSkillFrontmatter(source)?.declaredName;
    } on FormatException {
      return null;
    }
  }
}

DraftSnapshotFailureCode _mapFailure(SkillContentFailureCode code) =>
    switch (code) {
      SkillContentFailureCode.invalidContent =>
        DraftSnapshotFailureCode.invalidSkill,
      SkillContentFailureCode.limitExceeded =>
        DraftSnapshotFailureCode.skillContentLimitExceeded,
      SkillContentFailureCode.cancelled =>
        DraftSnapshotFailureCode.operationCancelled,
      SkillContentFailureCode.unavailable => DraftSnapshotFailureCode.ioFailure,
    };
