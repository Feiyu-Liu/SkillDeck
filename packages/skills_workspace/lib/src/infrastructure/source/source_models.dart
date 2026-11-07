import 'dart:collection';

import '../../domain/source_descriptor.dart';
import '../content/normalized_skill_tree.dart';
import 'source_result.dart';

final class SkillDiscoveryOptions {
  const SkillDiscoveryOptions({
    this.includeInternal = false,
    this.fullDepth = false,
  });

  final bool includeInternal;
  final bool fullDepth;
}

final class SkillFrontmatter {
  SkillFrontmatter({
    required this.declaredName,
    required this.description,
    required Map<String, Object?> values,
  }) : values = _freezeMap(values);

  final String declaredName;
  final String description;
  final Map<String, Object?> values;

  bool get isInternal {
    final metadata = values['metadata'];
    return metadata is Map<String, Object?> && metadata['internal'] == true;
  }
}

/// A validated Skill directory found in a filesystem-backed source.
final class DiscoveredSkill {
  DiscoveredSkill({
    required this.rootPath,
    required this.sourceRelativePath,
    required this.slotKey,
    required this.frontmatter,
    this.pluginName,
    Set<String> aliasPaths = const {},
  }) : aliasPaths = Set.unmodifiable(aliasPaths);

  final String rootPath;
  final String sourceRelativePath;
  final String slotKey;
  final SkillFrontmatter frontmatter;
  final String? pluginName;
  final Set<String> aliasPaths;

  DiscoveredSkill withSelectionPath(String selectedPath) => DiscoveredSkill(
    rootPath: rootPath,
    sourceRelativePath: selectedPath,
    slotKey: slotKey,
    frontmatter: frontmatter,
    pluginName: pluginName,
    aliasPaths: aliasPaths,
  );

  String get declaredName => frontmatter.declaredName;
  String get description => frontmatter.description;
}

final class FilesystemSourceInspection {
  FilesystemSourceInspection({
    required this.sourceRoot,
    required this.searchRoot,
    required List<DiscoveredSkill> candidates,
  }) : candidates = List<DiscoveredSkill>.unmodifiable(candidates);

  final String sourceRoot;
  final String searchRoot;
  final List<DiscoveredSkill> candidates;

  SourceResult<List<DiscoveredSkill>> select(Iterable<String> selectors) {
    if (candidates.isEmpty) {
      return SourceFailure<List<DiscoveredSkill>>(
        code: SourceFailureCode.notFound,
        context: const <String, Object?>{'reason': 'noValidSkills'},
      );
    }
    final requested = selectors.map((value) => value.toLowerCase()).toSet();
    if (requested.isEmpty) {
      return SourceSuccess<List<DiscoveredSkill>>(value: candidates);
    }
    final selected = <DiscoveredSkill>[];
    for (final candidate in candidates) {
      if (requested.contains(candidate.declaredName.toLowerCase()) ||
          requested.contains(candidate.sourceRelativePath.toLowerCase())) {
        selected.add(candidate);
        continue;
      }
      // An explicitly selected alias keeps its path as Source identity.
      final aliases =
          candidate.aliasPaths
              .where((alias) => requested.contains(alias.toLowerCase()))
              .toList()
            ..sort();
      if (aliases.isNotEmpty) {
        selected.add(candidate.withSelectionPath(aliases.first));
      }
    }
    if (selected.isEmpty) {
      return SourceFailure<List<DiscoveredSkill>>(
        code: SourceFailureCode.notFound,
        context: <String, Object?>{
          'requestedSelectors': List<String>.unmodifiable(selectors),
        },
      );
    }
    return SourceSuccess<List<DiscoveredSkill>>(value: selected);
  }
}

/// One source-selected Skill after source-agnostic content normalization.
final class AcquiredSourceSkill {
  AcquiredSourceSkill({
    required this.provenance,
    required this.declaredName,
    required this.description,
    required this.slotKey,
    required this.skillPath,
    required this.frontmatter,
    required this.tree,
    this.pluginName,
  });

  final SourceDescriptor provenance;
  final String declaredName;
  final String description;
  final String slotKey;
  final String skillPath;
  final Map<String, Object?> frontmatter;
  final NormalizedSkillTree tree;
  final String? pluginName;
}

final class AcquiredSource {
  AcquiredSource({
    required this.canonicalSource,
    required List<AcquiredSourceSkill> skills,
    this.resolvedSourceRevision,
  }) : skills = List<AcquiredSourceSkill>.unmodifiable(skills);

  final SourceDescriptor canonicalSource;
  final List<AcquiredSourceSkill> skills;
  final String? resolvedSourceRevision;
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
    UnmodifiableMapView<String, Object?>(
      source.map(
        (key, value) => MapEntry<String, Object?>(key, _freezeValue(value)),
      ),
    );

Object? _freezeValue(Object? value) => switch (value) {
  Map<String, Object?>() => _freezeMap(value),
  List<Object?>() => List<Object?>.unmodifiable(value.map(_freezeValue)),
  _ => value,
};
