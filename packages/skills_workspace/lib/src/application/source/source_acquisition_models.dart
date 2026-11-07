import 'dart:collection';

import '../../domain/immutable.dart';
import '../../domain/revision_content.dart';
import '../../domain/source_descriptor.dart';

/// Read-only discovery controls shared by every supported Source adapter.
final class SourceAcquisitionOptions {
  const SourceAcquisitionOptions({
    this.includeInternal = false,
    this.fullDepth = false,
  });

  final bool includeInternal;
  final bool fullDepth;
}

/// One independently selected Source read inside a shared acquisition batch.
final class SourceAcquisitionRequest {
  SourceAcquisitionRequest({
    required this.source,
    Set<String> selectedSkillNames = const <String>{},
    this.options = const SourceAcquisitionOptions(),
  }) : selectedSkillNames = Set.unmodifiable(selectedSkillNames);

  final SourceDescriptor source;
  final Set<String> selectedSkillNames;
  final SourceAcquisitionOptions options;
}

/// One source-selected Skill after source-agnostic content normalization.
final class AcquiredSourceSkill {
  AcquiredSourceSkill({
    required this.provenance,
    required this.declaredName,
    required this.description,
    required this.slotKey,
    required this.skillPath,
    required Map<String, Object?> frontmatter,
    required this.tree,
    this.pluginName,
  }) : frontmatter = _freezeMap(frontmatter) {
    _requireText(declaredName, 'declaredName');
    _requireText(description, 'description');
    _requireText(slotKey, 'slotKey');
  }

  /// Exact credential-free provenance for reacquiring only this Skill.
  final SourceDescriptor provenance;
  final String declaredName;
  final String description;
  final String slotKey;
  final String skillPath;
  final Map<String, Object?> frontmatter;
  final NormalizedSkillTree tree;
  final String? pluginName;
}

/// Immutable source acquisition shared by Install, Update and Replacement.
final class AcquiredSource {
  AcquiredSource({
    required this.canonicalSource,
    required List<AcquiredSourceSkill> skills,
    this.resolvedSourceRevision,
  }) : skills = List<AcquiredSourceSkill>.unmodifiable(skills) {
    if (resolvedSourceRevision != null) {
      _requireText(resolvedSourceRevision!, 'resolvedSourceRevision');
    }
  }

  final SourceDescriptor canonicalSource;
  final List<AcquiredSourceSkill> skills;
  final String? resolvedSourceRevision;
}

enum SourceAcquisitionFailureCode {
  sourceUnavailable,
  sourceAuthenticationRequired,
  gitUnavailable,
  gitTimedOut,
  gitFailed,

  /// The host's developer command line tools are missing or still installing.
  /// Remediation is an operating-system install, never a retry.
  developerToolsRequired,
  transportRejected,
  httpFailure,
  digestMismatch,
  archiveInvalid,
  skillNotFound,
  invalidSkill,
  unsupportedSkillName,
  skillContentLimitExceeded,
  duplicateSkillSlot,
  updateUnsupported,
  operationCancelled,
  ioFailure,
}

enum SourceAcquisitionWarningCode { sourceEntrySkipped }

final class SourceAcquisitionWarning {
  SourceAcquisitionWarning({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map.unmodifiable(context);

  final SourceAcquisitionWarningCode code;
  final Map<String, Object?> context;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceAcquisitionWarning &&
          code == other.code &&
          mapsEqual(context, other.context);

  @override
  int get hashCode => Object.hash(code, unorderedMapHash(context));
}

sealed class SourceAcquisitionResult<T> {
  const SourceAcquisitionResult();

  T? get valueOrNull;
  SourceAcquisitionFailure<T>? get failureOrNull;
  List<SourceAcquisitionWarning> get warnings;
}

final class SourceAcquisitionSuccess<T> extends SourceAcquisitionResult<T> {
  SourceAcquisitionSuccess({
    required this.value,
    List<SourceAcquisitionWarning> warnings =
        const <SourceAcquisitionWarning>[],
  }) : warnings = List.unmodifiable(warnings);

  final T value;

  @override
  final List<SourceAcquisitionWarning> warnings;

  @override
  T get valueOrNull => value;

  @override
  SourceAcquisitionFailure<T>? get failureOrNull => null;
}

final class SourceAcquisitionFailure<T> extends SourceAcquisitionResult<T> {
  SourceAcquisitionFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
    List<SourceAcquisitionWarning> warnings =
        const <SourceAcquisitionWarning>[],
  }) : context = Map.unmodifiable(context),
       warnings = List.unmodifiable(warnings);

  final SourceAcquisitionFailureCode code;
  final Map<String, Object?> context;

  @override
  final List<SourceAcquisitionWarning> warnings;

  @override
  T? get valueOrNull => null;

  @override
  SourceAcquisitionFailure<T> get failureOrNull => this;
}

SourceAcquisitionFailure<TTarget> copySourceAcquisitionFailure<
  TSource,
  TTarget
>(SourceAcquisitionFailure<TSource> failure) =>
    SourceAcquisitionFailure<TTarget>(
      code: failure.code,
      context: failure.context,
      warnings: failure.warnings,
    );

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

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
