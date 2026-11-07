import '../../domain/immutable.dart';
import '../../domain/public_models.dart';
import '../../domain/source_descriptor.dart';
import '../activation/activation_models.dart';

enum ExternalDiscoveryFailureCode {
  agentNotFound,
  activationUnsupported,
  projectRootNotFound,
  sourceUnavailable,
  invalidSkill,
  contentLimitExceeded,
  operationCancelled,
  ioFailure,
}

enum ExternalDiscoveryWarningCode {
  noActivationTarget,
  projectSymbolicLinkPortability,
  duplicateExposure,
  activationTargetSkipped,
  sourceEntrySkipped,
  sharedActivationLocation,
}

final class ExternalDiscoveryWarning {
  ExternalDiscoveryWarning({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
  }) : context = Map.unmodifiable(context);

  final ExternalDiscoveryWarningCode code;
  final Map<String, Object?> context;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalDiscoveryWarning &&
          code == other.code &&
          mapsEqual(context, other.context);

  @override
  int get hashCode => Object.hash(code, unorderedMapHash(context));
}

sealed class ExternalDiscoveryResult<T> {
  const ExternalDiscoveryResult();

  T? get valueOrNull;
  ExternalDiscoveryFailure<T>? get failureOrNull;
  List<ExternalDiscoveryWarning> get warnings;
}

final class ExternalDiscoverySuccess<T> extends ExternalDiscoveryResult<T> {
  ExternalDiscoverySuccess({
    required this.value,
    List<ExternalDiscoveryWarning> warnings =
        const <ExternalDiscoveryWarning>[],
  }) : warnings = List.unmodifiable(warnings);

  final T value;

  @override
  final List<ExternalDiscoveryWarning> warnings;

  @override
  T get valueOrNull => value;

  @override
  ExternalDiscoveryFailure<T>? get failureOrNull => null;
}

final class ExternalDiscoveryFailure<T> extends ExternalDiscoveryResult<T> {
  ExternalDiscoveryFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
    List<ExternalDiscoveryWarning> warnings =
        const <ExternalDiscoveryWarning>[],
  }) : context = Map.unmodifiable(context),
       warnings = List.unmodifiable(warnings);

  final ExternalDiscoveryFailureCode code;
  final Map<String, Object?> context;

  @override
  final List<ExternalDiscoveryWarning> warnings;

  @override
  T? get valueOrNull => null;

  @override
  ExternalDiscoveryFailure<T> get failureOrNull => this;
}

ExternalDiscoveryFailure<TTarget>
copyExternalDiscoveryFailure<TSource, TTarget>(
  ExternalDiscoveryFailure<TSource> failure, {
  List<ExternalDiscoveryWarning> additionalWarnings =
      const <ExternalDiscoveryWarning>[],
}) => ExternalDiscoveryFailure<TTarget>(
  code: failure.code,
  context: failure.context,
  warnings: <ExternalDiscoveryWarning>[
    ...additionalWarnings,
    ...failure.warnings,
  ],
);

/// One normalized Skill occurrence returned by a location adapter.
final class ScannedExternalSkill {
  ScannedExternalSkill({
    required this.declaredName,
    required this.description,
    required this.slotKey,
    required this.contentHash,
    required this.skillLocation,
    required this.source,
    String? mutationPath,
    String? contentIdentityPath,
  }) : mutationPath = mutationPath ?? skillLocation,
       contentIdentityPath =
           contentIdentityPath ?? mutationPath ?? skillLocation {
    if (skillLocation.trim().isEmpty) {
      throw ArgumentError.value(
        skillLocation,
        'skillLocation',
        'must not be empty',
      );
    }
  }

  final String declaredName;
  final String description;
  final String slotKey;
  final String contentHash;
  final String skillLocation;

  /// Stable filesystem path used for mutation. Parent links are resolved, but
  /// the final entry is preserved so retiring a Skill link removes the link.
  final String mutationPath;

  /// Fully resolved directory identity used to recognize duplicate exposure.
  final String contentIdentityPath;

  /// Exact, credential-free source selection used to reacquire this occurrence.
  final LocalSourceDescriptor source;
}

/// One location scanned for External Skills and the canonical targets that
/// any adopted Skill must activate into.
final class ResolvedExternalSkillLocation {
  ResolvedExternalSkillLocation({
    required this.location,
    required List<ResolvedActivationTarget> canonicalTargets,
  }) : canonicalTargets = List.unmodifiable(canonicalTargets) {
    if (location.trim().isEmpty || canonicalTargets.isEmpty) {
      throw ArgumentError('Discovery locations require canonical targets.');
    }
  }

  final String location;
  final List<ResolvedActivationTarget> canonicalTargets;

  List<String> get agentIds => List.unmodifiable(
    canonicalTargets.expand((target) => target.agentIds).toSet().toList()
      ..sort(),
  );

  ResolvedActivationTarget get inspectionTarget {
    final first = canonicalTargets.first;
    return ResolvedActivationTarget(
      location: location,
      scope: first.scope,
      mode: ActivationMode.copy,
      agentIds: agentIds,
      projectRootId: first.projectRootId,
      projectRootPath: first.projectRootPath,
    );
  }
}

final class ExternalSkillOccurrence {
  const ExternalSkillOccurrence({required this.skill, required this.target});

  final ScannedExternalSkill skill;
  final ResolvedExternalSkillLocation target;

  String get skillLocation => skill.skillLocation;
  LocalSourceDescriptor get source => skill.source;
}

final class ExternalSkillScan {
  ExternalSkillScan({
    required this.discovery,
    required Map<String, List<ExternalSkillOccurrence>> occurrencesBySlot,
    List<ExternalDiscoveryWarning> warnings =
        const <ExternalDiscoveryWarning>[],
  }) : occurrencesBySlot = Map.unmodifiable(
         occurrencesBySlot.map<String, List<ExternalSkillOccurrence>>(
           (key, value) =>
               MapEntry(key, List<ExternalSkillOccurrence>.unmodifiable(value)),
         ),
       ),
       warnings = List.unmodifiable(warnings);

  final ExternalSkillsDiscovery discovery;
  final Map<String, List<ExternalSkillOccurrence>> occurrencesBySlot;
  final List<ExternalDiscoveryWarning> warnings;
}
