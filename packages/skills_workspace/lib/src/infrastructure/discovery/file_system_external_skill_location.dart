import 'dart:io';

import 'package:path/path.dart' as path;

import '../../application/discovery/external_discovery_models.dart';
import '../../application/ports/external_discovery_ports.dart';
import '../../domain/cancellation.dart';
import '../../domain/source_descriptor.dart';
import '../source/local_source.dart';
import '../source/source_models.dart';
import '../source/source_result.dart';

/// Read-only filesystem adapter for one known Agent activation location.
final class FileSystemExternalSkillLocation
    implements ExternalSkillLocationPort {
  FileSystemExternalSkillLocation({LocalSourceAdapter? localSource})
    : _localSource = localSource ?? LocalSourceAdapter();

  final LocalSourceAdapter _localSource;

  @override
  Future<ExternalDiscoveryResult<List<ScannedExternalSkill>>> scanLocation({
    required String location,
    Set<String>? selectedSlotKeys,
    required bool includeInternal,
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return _cancelled();
    }
    final normalizedLocation = path.normalize(path.absolute(location));
    final ordinary = await _acquire(
      LocalSourceDescriptor(locator: normalizedLocation),
      selectedSlotKeys: selectedSlotKeys,
      includeInternal: includeInternal,
      cancellationToken: cancellationToken,
      unavailableIsEmpty: true,
    );
    final ordinarySkills = ordinary.valueOrNull;
    if (ordinarySkills == null) {
      return ordinary;
    }
    final linked = await _scanTopLevelSymbolicLinks(
      normalizedLocation,
      selectedSlotKeys: selectedSlotKeys,
      includeInternal: includeInternal,
      cancellationToken: cancellationToken,
    );
    final linkedSkills = linked.valueOrNull;
    if (linkedSkills == null) {
      return linked;
    }
    final warnings = <ExternalDiscoveryWarning>[
      ...ordinary.warnings,
      ...linked.warnings,
    ];
    return ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
      value: <ScannedExternalSkill>[...ordinarySkills, ...linkedSkills],
      warnings: warnings,
    );
  }

  Future<ExternalDiscoveryResult<List<ScannedExternalSkill>>>
  _scanTopLevelSymbolicLinks(
    String location, {
    required Set<String>? selectedSlotKeys,
    required bool includeInternal,
    required CancellationToken cancellationToken,
  }) async {
    try {
      if (await FileSystemEntity.type(location, followLinks: true) !=
          FileSystemEntityType.directory) {
        return ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
          value: const <ScannedExternalSkill>[],
        );
      }
      final entries =
          await Directory(location).list(followLinks: false).toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      final skills = <ScannedExternalSkill>[];
      final warnings = <ExternalDiscoveryWarning>[];
      for (final entry in entries) {
        if (cancellationToken.isCancelled) {
          return ExternalDiscoveryFailure<List<ScannedExternalSkill>>(
            code: ExternalDiscoveryFailureCode.operationCancelled,
            warnings: warnings,
          );
        }
        if (await FileSystemEntity.type(entry.path, followLinks: false) !=
            FileSystemEntityType.link) {
          continue;
        }
        final result = await _acquire(
          LocalSourceDescriptor(
            locator: path.normalize(path.absolute(entry.path)),
          ),
          selectedSlotKeys: selectedSlotKeys,
          includeInternal: includeInternal,
          cancellationToken: cancellationToken,
          unavailableIsEmpty: true,
        );
        final values = result.valueOrNull;
        if (values == null) {
          if (result.failureOrNull?.code ==
              ExternalDiscoveryFailureCode.operationCancelled) {
            return copyExternalDiscoveryFailure<
              List<ScannedExternalSkill>,
              List<ScannedExternalSkill>
            >(result.failureOrNull!, additionalWarnings: warnings);
          }
          continue;
        }
        warnings.addAll(result.warnings);
        skills.addAll(values.where((skill) => skill.source.skillPath.isEmpty));
      }
      return ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
        value: skills,
        warnings: warnings,
      );
    } on FileSystemException {
      return ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
        value: const <ScannedExternalSkill>[],
      );
    }
  }

  Future<ExternalDiscoveryResult<List<ScannedExternalSkill>>> _acquire(
    LocalSourceDescriptor source, {
    required Set<String>? selectedSlotKeys,
    required bool includeInternal,
    required CancellationToken cancellationToken,
    required bool unavailableIsEmpty,
  }) async {
    final result = await _localSource.acquire(
      source,
      selectedSlotKeys: selectedSlotKeys ?? const <String>{},
      options: SkillDiscoveryOptions(includeInternal: includeInternal),
      candidateFailureDisposition:
          SourceCandidateFailureDisposition.skipWithWarning,
      cancellation: _CancellationSignal(cancellationToken),
    );
    final acquired = result.valueOrNull;
    if (acquired == null) {
      final failure = result.failureOrNull!;
      if (failure.code == SourceFailureCode.cancelled) {
        return _cancelled();
      }
      if (unavailableIsEmpty &&
          (failure.code == SourceFailureCode.unavailable ||
              failure.code == SourceFailureCode.notFound)) {
        return ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
          value: const <ScannedExternalSkill>[],
        );
      }
      return ExternalDiscoveryFailure<List<ScannedExternalSkill>>(
        code: _mapFailure(failure.code),
        context: failure.context,
        warnings: _mapWarnings(failure.warnings),
      );
    }
    final skills = <ScannedExternalSkill>[];
    for (final skill in acquired.skills) {
      final skillLocation = _skillLocation(source.locator, skill.skillPath);
      final resolved = await _resolveSkillPaths(skillLocation);
      skills.add(
        ScannedExternalSkill(
          declaredName: skill.declaredName,
          description: skill.description,
          slotKey: skill.slotKey,
          contentHash: skill.tree.contentHash,
          skillLocation: skillLocation,
          mutationPath: resolved.mutationPath,
          contentIdentityPath: resolved.contentIdentityPath,
          source: LocalSourceDescriptor(
            locator: source.locator,
            skillPath: skill.skillPath,
          ),
        ),
      );
    }
    return ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
      value: skills,
      warnings: _mapWarnings(result.warnings),
    );
  }
}

Future<_ResolvedSkillPaths> _resolveSkillPaths(String skillLocation) async {
  final logical = path.normalize(path.absolute(skillLocation));
  var mutationParent = path.dirname(logical);
  try {
    mutationParent = path.normalize(
      await Directory(mutationParent).resolveSymbolicLinks(),
    );
  } on FileSystemException {
    // The source acquisition already proved the Skill readable. Falling back
    // to its logical parent keeps discovery available when canonicalization is
    // temporarily unavailable; Adoption will revalidate the exact entry.
  }
  final mutationPath = path.join(mutationParent, path.basename(logical));
  var contentIdentityPath = mutationPath;
  try {
    contentIdentityPath = path.normalize(
      await Directory(logical).resolveSymbolicLinks(),
    );
  } on FileSystemException {
    // Preserve the parent-resolved mutation identity as the safe fallback.
  }
  return _ResolvedSkillPaths(
    mutationPath: mutationPath,
    contentIdentityPath: contentIdentityPath,
  );
}

final class _ResolvedSkillPaths {
  const _ResolvedSkillPaths({
    required this.mutationPath,
    required this.contentIdentityPath,
  });

  final String mutationPath;
  final String contentIdentityPath;
}

final class _CancellationSignal implements SourceCancellationSignal {
  const _CancellationSignal(this._token);

  final CancellationToken _token;

  @override
  bool get isCancelled => _token.isCancelled;

  @override
  Future<void> get whenCancelled => _token.whenCancelled;
}

ExternalDiscoveryFailure<List<ScannedExternalSkill>> _cancelled() =>
    ExternalDiscoveryFailure<List<ScannedExternalSkill>>(
      code: ExternalDiscoveryFailureCode.operationCancelled,
    );

String _skillLocation(String root, String skillPath) {
  if (skillPath.isEmpty) {
    return path.normalize(root);
  }
  return path.normalize(
    path.joinAll(<String>[root, ...path.posix.split(skillPath)]),
  );
}

ExternalDiscoveryFailureCode _mapFailure(SourceFailureCode code) =>
    switch (code) {
      SourceFailureCode.cancelled =>
        ExternalDiscoveryFailureCode.operationCancelled,
      SourceFailureCode.contentLimitExceeded =>
        ExternalDiscoveryFailureCode.contentLimitExceeded,
      SourceFailureCode.invalidSource || SourceFailureCode.contentInvalid =>
        ExternalDiscoveryFailureCode.invalidSkill,
      SourceFailureCode.ioFailure => ExternalDiscoveryFailureCode.ioFailure,
      _ => ExternalDiscoveryFailureCode.sourceUnavailable,
    };

List<ExternalDiscoveryWarning> _mapWarnings(List<SourceWarning> warnings) =>
    <ExternalDiscoveryWarning>[
      for (final warning in warnings)
        ExternalDiscoveryWarning(
          code: ExternalDiscoveryWarningCode.sourceEntrySkipped,
          context: warning.context,
        ),
    ];
