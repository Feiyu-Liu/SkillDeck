import 'dart:convert';
import 'dart:io';

import '../../application/ports/revision_content_worker_ports.dart';
import '../../domain/slot_key.dart';
import '../../domain/source_descriptor.dart';
import '../content/content_result.dart';
import '../content/direct_revision_content_worker.dart';
import '../content/normalized_skill_tree.dart';
import 'frontmatter_parser.dart';
import 'skill_discovery.dart';
import 'source_models.dart';
import 'source_result.dart';

/// Controls whether one candidate failure aborts a filesystem Source read.
enum SourceCandidateFailureDisposition { failSource, skipWithWarning }

/// Acquires current local working-tree bytes without importing Git metadata.
final class LocalSourceAdapter {
  LocalSourceAdapter({
    this.discovery = const SkillDiscovery(),
    this.followDirectoryLinks = false,
    RevisionContentWorkerPort contentWorker =
        const DirectRevisionContentWorker(),
  }) : _contentWorker = contentWorker;

  final SkillDiscovery discovery;

  /// Source acquisition enables this to follow contained directory aliases;
  /// Activation Location scans keep it off and inspect exposure links
  /// separately.
  final bool followDirectoryLinks;
  final RevisionContentWorkerPort _contentWorker;

  Future<SourceResult<FilesystemSourceInspection>> inspect(
    LocalSourceDescriptor source, {
    SkillDiscoveryOptions options = const SkillDiscoveryOptions(),
    SourceCancellationSignal cancellation = const NoSourceCancellationSignal(),
  }) => discovery.inspect(
    source.locator,
    subpath: source.skillPath,
    options: options,
    cancellation: cancellation,
    followDirectoryLinks: followDirectoryLinks,
  );

  Future<SourceResult<AcquiredSource>> acquire(
    LocalSourceDescriptor source, {
    Iterable<String> selectedSkills = const <String>[],
    Set<String> selectedSlotKeys = const <String>{},
    SkillDiscoveryOptions options = const SkillDiscoveryOptions(),
    SourceCandidateFailureDisposition candidateFailureDisposition =
        SourceCandidateFailureDisposition.failSource,
    SourceCancellationSignal cancellation = const NoSourceCancellationSignal(),
  }) async {
    final inspectionResult = await inspect(
      source,
      options: options,
      cancellation: cancellation,
    );
    final inspection = inspectionResult.valueOrNull;
    if (inspection == null) {
      return copySourceFailure<FilesystemSourceInspection, AcquiredSource>(
        inspectionResult.failureOrNull!,
      );
    }
    final warnings = <SourceWarning>[...inspectionResult.warnings];
    final selection = selectedSlotKeys.isEmpty
        ? inspection.select(selectedSkills)
        : _selectSlotKeys(inspection, selectedSlotKeys);
    final selected = selection.valueOrNull;
    if (selected == null) {
      return _copyFailureWithWarnings<List<DiscoveredSkill>, AcquiredSource>(
        selection.failureOrNull!,
        warnings,
      );
    }

    final acquired = <AcquiredSourceSkill>[];
    for (final candidate in selected) {
      if (cancellation.isCancelled) {
        return SourceFailure<AcquiredSource>(
          code: SourceFailureCode.cancelled,
          warnings: warnings,
        );
      }
      final treeResult = await _contentWorker.readFilesystemTree(
        candidate.rootPath,
        gitMetadataDisposition: GitMetadataDisposition.exclude,
        capturePosixExecutableIntent: !Platform.isWindows,
        executableIntentOverrides: const <String, bool>{},
        maximumFileCount: maximumNormalizedSkillFileCount,
        maximumByteSize: maximumNormalizedSkillByteSize,
        isCancelled: () => cancellation.isCancelled,
      );
      final tree = treeResult.valueOrNull;
      if (tree == null) {
        final failure = _mapContentFailure<NormalizedSkillTree, AcquiredSource>(
          treeResult.failureOrNull!,
        );
        if (_shouldSkipCandidate(candidateFailureDisposition, failure.code)) {
          warnings.add(_candidateWarning(source, candidate, failure));
          continue;
        }
        return _copyFailureWithWarnings<AcquiredSource, AcquiredSource>(
          failure,
          warnings,
        );
      }
      final validated = _buildAcquiredSkill(
        tree,
        source: source,
        skillPath: _joinSkillPath(
          source.skillPath,
          candidate.sourceRelativePath,
        ),
        pluginName: candidate.pluginName,
      );
      final skill = validated.valueOrNull;
      if (skill == null) {
        final failure = validated.failureOrNull!;
        if (_shouldSkipCandidate(candidateFailureDisposition, failure.code)) {
          warnings.add(_candidateWarning(source, candidate, failure));
          continue;
        }
        return _copyFailureWithWarnings<AcquiredSourceSkill, AcquiredSource>(
          failure,
          warnings,
        );
      }
      acquired.add(skill);
    }

    return SourceSuccess<AcquiredSource>(
      value: AcquiredSource(
        canonicalSource: LocalSourceDescriptor(
          locator: inspection.sourceRoot,
          skillPath: source.skillPath,
        ),
        skills: acquired,
      ),
      warnings: warnings,
    );
  }
}

SourceResult<List<DiscoveredSkill>> _selectSlotKeys(
  FilesystemSourceInspection inspection,
  Set<String> selectedSlotKeys,
) {
  final selected = inspection.candidates
      .where((candidate) => selectedSlotKeys.contains(candidate.slotKey))
      .toList(growable: false);
  if (selected.isEmpty) {
    return SourceFailure<List<DiscoveredSkill>>(
      code: SourceFailureCode.notFound,
      context: const <String, Object?>{'reason': 'selectedSlotsNotFound'},
    );
  }
  return SourceSuccess<List<DiscoveredSkill>>(value: selected);
}

bool _shouldSkipCandidate(
  SourceCandidateFailureDisposition disposition,
  SourceFailureCode code,
) =>
    disposition == SourceCandidateFailureDisposition.skipWithWarning &&
    code != SourceFailureCode.cancelled;

SourceWarning _candidateWarning<T>(
  LocalSourceDescriptor source,
  DiscoveredSkill candidate,
  SourceFailure<T> failure,
) {
  final entryPath = failure.context['path'];
  return SourceWarning(
    code: SourceWarningCode.sourceEntrySkipped,
    context: <String, Object?>{
      'skillPath': _joinSkillPath(
        source.skillPath,
        candidate.sourceRelativePath,
      ),
      'reason': failure.context['reason'] ?? failure.code.name,
      if (entryPath is String && entryPath.isNotEmpty) 'entryPath': entryPath,
    },
  );
}

SourceFailure<TTarget> _copyFailureWithWarnings<TSource, TTarget>(
  SourceFailure<TSource> failure,
  List<SourceWarning> warnings,
) => SourceFailure<TTarget>(
  code: failure.code,
  context: failure.context,
  warnings: <SourceWarning>[...warnings, ...failure.warnings],
);

SourceResult<AcquiredSourceSkill> _buildAcquiredSkill(
  NormalizedSkillTree tree, {
  required LocalSourceDescriptor source,
  required String skillPath,
  required String? pluginName,
}) {
  final skillMarkdown = tree.files
      .where((file) => file.relativePath == 'SKILL.md')
      .firstOrNull;
  if (skillMarkdown == null) {
    return SourceFailure<AcquiredSourceSkill>(
      code: SourceFailureCode.invalidSource,
      context: const <String, Object?>{'reason': 'missingSkillMarkdown'},
    );
  }
  SkillFrontmatter? frontmatter;
  try {
    frontmatter = parseSkillFrontmatter(
      utf8.decode(skillMarkdown.bytes, allowMalformed: false),
    );
  } on FormatException {
    frontmatter = null;
  }
  if (frontmatter == null) {
    return SourceFailure<AcquiredSourceSkill>(
      code: SourceFailureCode.invalidSource,
      context: const <String, Object?>{'reason': 'invalidSkillFrontmatter'},
    );
  }
  final slotKey = deriveSlotKeyValue(frontmatter.declaredName).value;
  if (slotKey == null) {
    return SourceFailure<AcquiredSourceSkill>(
      code: SourceFailureCode.invalidSource,
      context: const <String, Object?>{'reason': 'unsupportedSkillName'},
    );
  }
  return SourceSuccess<AcquiredSourceSkill>(
    value: AcquiredSourceSkill(
      provenance: LocalSourceDescriptor(
        locator: source.locator,
        skillPath: skillPath,
      ),
      declaredName: frontmatter.declaredName,
      description: frontmatter.description,
      slotKey: slotKey,
      skillPath: skillPath,
      frontmatter: frontmatter.values,
      tree: tree,
      pluginName: pluginName,
    ),
  );
}

SourceFailure<TTarget> _mapContentFailure<TSource, TTarget>(
  SkillContentFailure<TSource> failure,
) => SourceFailure<TTarget>(
  code: switch (failure.code) {
    SkillContentFailureCode.cancelled => SourceFailureCode.cancelled,
    SkillContentFailureCode.unavailable => SourceFailureCode.unavailable,
    SkillContentFailureCode.invalidContent => SourceFailureCode.contentInvalid,
    SkillContentFailureCode.limitExceeded =>
      SourceFailureCode.contentLimitExceeded,
  },
  context: failure.context,
);

String _joinSkillPath(String prefix, String suffix) {
  if (prefix.isEmpty) {
    return suffix;
  }
  if (suffix.isEmpty) {
    return prefix;
  }
  return '$prefix/$suffix';
}
