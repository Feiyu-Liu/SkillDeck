import 'package:path/path.dart' as path;

import '../../domain/activation_selection.dart';
import '../../domain/cancellation.dart';
import '../../domain/public_models.dart';
import '../activation/activation_models.dart';
import '../activation/activation_result.dart';
import '../activation/activation_target_resolver.dart';
import '../agents/agent_catalog.dart';
import '../ports/agent_activation_ports.dart';
import '../ports/external_discovery_ports.dart';
import 'external_discovery_models.dart';

final class ExternalSkillScanner {
  const ExternalSkillScanner({
    required AgentCatalog catalog,
    required ActivationTargetResolver activationTargetResolver,
    required ActivationLocationIdentityPort locationIdentity,
    required ExternalSkillLocationPort locationPort,
  }) : _catalog = catalog,
       _activationTargetResolver = activationTargetResolver,
       _locationIdentity = locationIdentity,
       _locationPort = locationPort;

  final AgentCatalog _catalog;
  final ActivationTargetResolver _activationTargetResolver;
  final ActivationLocationIdentityPort _locationIdentity;
  final ExternalSkillLocationPort _locationPort;

  Future<ExternalDiscoveryResult<ExternalSkillScan>> scanSelection({
    required ActivationSelection selection,
    required RepositorySnapshot snapshot,
    required bool includeInternal,
    CancellationToken? cancellationToken,
  }) async {
    final resolved = await _activationTargetResolver.resolve(
      selection: selection,
      requestedMode: RequestedActivationMode.copy,
      snapshot: snapshot,
    );
    final targets = resolved.valueOrNull;
    if (targets == null) {
      return _mapActivationFailure<ExternalSkillScan>(resolved.failureOrNull!);
    }
    return scanTargets(
      <ResolvedExternalSkillLocation>[
        for (final target in targets.targets)
          ResolvedExternalSkillLocation(
            location: target.location,
            canonicalTargets: <ResolvedActivationTarget>[target],
          ),
      ],
      snapshot: snapshot,
      includeInternal: includeInternal,
      initialWarnings: targets.warnings.map(_mapActivationWarning).toList(),
      cancellationToken: cancellationToken,
    );
  }

  ExternalDiscoveryResult<List<ResolvedExternalSkillLocation>>
  resolveAllLocations(RepositorySnapshot snapshot) {
    final grouped = <String, ResolvedExternalSkillLocation>{};
    final definitions = _catalog.definitions.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    final roots = snapshot.projectRoots.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    for (final definition in definitions) {
      final global = _catalog.resolveDiscovery(
        agentId: definition.id,
        scope: ActivationScope.global,
      );
      final globalTargets = global.valueOrNull;
      if (globalTargets != null) {
        for (final target in globalTargets) {
          final failure = _appendTarget(grouped, target);
          if (failure != null) return failure;
        }
      }
      for (final root in roots) {
        final project = _catalog.resolveDiscovery(
          agentId: definition.id,
          scope: ActivationScope.project,
          projectRoot: root,
        );
        final projectTargets = project.valueOrNull;
        if (projectTargets != null) {
          for (final target in projectTargets) {
            final failure = _appendTarget(grouped, target);
            if (failure != null) return failure;
          }
        }
      }
    }
    final entries = grouped.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return ExternalDiscoverySuccess<List<ResolvedExternalSkillLocation>>(
      value: entries.map((entry) => entry.value).toList(growable: false),
    );
  }

  Future<ExternalDiscoveryResult<ExternalSkillScan>> scanTargets(
    List<ResolvedExternalSkillLocation> targets, {
    required RepositorySnapshot snapshot,
    required bool includeInternal,
    Set<String>? selectedSlotKeys,
    List<ExternalDiscoveryWarning> initialWarnings =
        const <ExternalDiscoveryWarning>[],
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final managedPaths = <String>{
      for (final skill in snapshot.managedSkills)
        for (final activation in skill.activations)
          _locationIdentity.key(path.join(activation.location, skill.slotKey)),
    };
    final managedSlotKeys = <String>{
      for (final skill in snapshot.managedSkills) skill.slotKey,
    };
    final warnings = <ExternalDiscoveryWarning>[...initialWarnings];
    final occurrencesBySlot = <String, List<ExternalSkillOccurrence>>{};
    final seenOccurrenceKeys = <String>{};
    final sortedTargets = targets.toList()
      ..sort(
        (left, right) => _locationIdentity
            .key(left.location)
            .compareTo(_locationIdentity.key(right.location)),
      );

    for (final target in sortedTargets) {
      if (token.isCancelled) {
        return ExternalDiscoveryFailure<ExternalSkillScan>(
          code: ExternalDiscoveryFailureCode.operationCancelled,
          warnings: warnings,
        );
      }
      final scanned = await _locationPort.scanLocation(
        location: target.location,
        selectedSlotKeys: selectedSlotKeys,
        includeInternal: includeInternal,
        cancellationToken: token,
      );
      final skills = scanned.valueOrNull;
      if (skills == null) {
        return copyExternalDiscoveryFailure<
          List<ScannedExternalSkill>,
          ExternalSkillScan
        >(scanned.failureOrNull!, additionalWarnings: warnings);
      }
      warnings.addAll(scanned.warnings);
      for (final skill in skills) {
        if (selectedSlotKeys != null &&
            !selectedSlotKeys.contains(skill.slotKey)) {
          continue;
        }
        final locationKey = _locationIdentity.key(skill.skillLocation);
        final occurrenceKey = '${skill.slotKey}\u0000$locationKey';
        if (!seenOccurrenceKeys.add(occurrenceKey) ||
            managedSlotKeys.contains(skill.slotKey) ||
            managedPaths.contains(locationKey)) {
          continue;
        }
        occurrencesBySlot
            .putIfAbsent(skill.slotKey, () => <ExternalSkillOccurrence>[])
            .add(ExternalSkillOccurrence(skill: skill, target: target));
      }
    }

    final candidates = <ExternalSkillCandidate>[];
    final conflicts = <ExternalSkillConflict>[];
    final slotKeys = occurrencesBySlot.keys.toList()..sort();
    for (final slotKey in slotKeys) {
      final occurrences = occurrencesBySlot[slotKey]!;
      final hashes = occurrences
          .map((entry) => entry.skill.contentHash)
          .toSet();
      if (hashes.length > 1) {
        final byLocation = <String, String>{};
        final agentsByLocation = <String, Set<String>>{};
        for (final occurrence in occurrences) {
          byLocation[occurrence.skillLocation] = occurrence.skill.contentHash;
          agentsByLocation
              .putIfAbsent(occurrence.skillLocation, () => <String>{})
              .addAll(occurrence.target.agentIds);
        }
        conflicts.add(
          ExternalSkillConflict(
            slotKey: slotKey,
            contentHashByLocation: byLocation,
            destinationLocations: _destinationLocations(occurrences, slotKey),
            agentIdsByLocation: {
              for (final entry in agentsByLocation.entries)
                entry.key: entry.value.toList()..sort(),
            },
          ),
        );
        continue;
      }
      final first = occurrences.first;
      final locations =
          occurrences.map((entry) => entry.skillLocation).toSet().toList()
            ..sort();
      final agentIds =
          occurrences.expand((entry) => entry.target.agentIds).toSet().toList()
            ..sort();
      final destinationLocations = _destinationLocations(occurrences, slotKey);
      candidates.add(
        ExternalSkillCandidate(
          slotKey: slotKey,
          declaredName: first.skill.declaredName,
          description: first.skill.description,
          contentHash: first.skill.contentHash,
          locations: locations,
          agentIds: agentIds,
          destinationLocations: destinationLocations,
        ),
      );
    }
    return ExternalDiscoverySuccess<ExternalSkillScan>(
      value: ExternalSkillScan(
        discovery: ExternalSkillsDiscovery(
          candidates: candidates,
          conflicts: conflicts,
        ),
        occurrencesBySlot: occurrencesBySlot,
        warnings: warnings,
      ),
      warnings: warnings,
    );
  }

  ExternalDiscoveryFailure<List<ResolvedExternalSkillLocation>>? _appendTarget(
    Map<String, ResolvedExternalSkillLocation> grouped,
    ResolvedAgentDiscoveryTarget discovery,
  ) {
    final location = _locationIdentity.normalize(discovery.location);
    final key = _locationIdentity.key(location);
    final existing = grouped[key];
    final target = discovery.canonicalTarget;
    final canonical = ResolvedActivationTarget(
      location: _locationIdentity.normalize(target.location),
      scope: target.scope,
      mode: ActivationMode.copy,
      agentIds: <String>[target.agentId],
      projectRootId: target.projectRootId,
      projectRootPath: target.projectRootPath,
    );
    if (existing == null) {
      grouped[key] = ResolvedExternalSkillLocation(
        location: location,
        canonicalTargets: <ResolvedActivationTarget>[canonical],
      );
      return null;
    }
    final first = existing.canonicalTargets.first;
    if (first.scope != target.scope ||
        first.projectRootId != target.projectRootId ||
        first.projectRootPath != target.projectRootPath) {
      return ExternalDiscoveryFailure<List<ResolvedExternalSkillLocation>>(
        code: ExternalDiscoveryFailureCode.activationUnsupported,
        context: <String, Object?>{
          'location': location,
          'reason': 'conflictingLocationProvenance',
        },
      );
    }
    final byCanonical = <String, ResolvedActivationTarget>{
      for (final item in existing.canonicalTargets)
        _locationIdentity.key(item.location): item,
    };
    final canonicalKey = _locationIdentity.key(canonical.location);
    final prior = byCanonical[canonicalKey];
    if (prior == null) {
      byCanonical[canonicalKey] = canonical;
    } else {
      final agentIds = <String>{...prior.agentIds, target.agentId}.toList()
        ..sort();
      byCanonical[canonicalKey] = ResolvedActivationTarget(
        location: prior.location,
        scope: prior.scope,
        mode: prior.mode,
        agentIds: agentIds,
        projectRootId: prior.projectRootId,
        projectRootPath: prior.projectRootPath,
      );
    }
    final canonicalTargets = byCanonical.values.toList()
      ..sort(
        (left, right) => _locationIdentity
            .key(left.location)
            .compareTo(_locationIdentity.key(right.location)),
      );
    grouped[key] = ResolvedExternalSkillLocation(
      location: location,
      canonicalTargets: canonicalTargets,
    );
    return null;
  }
}

List<String> _destinationLocations(
  Iterable<ExternalSkillOccurrence> occurrences,
  String slotKey,
) {
  final destinations = <String>{
    for (final occurrence in occurrences)
      for (final target in occurrence.target.canonicalTargets)
        path.join(target.location, slotKey),
  }.toList()..sort();
  return destinations;
}

ExternalDiscoveryFailure<T> _mapActivationFailure<T>(
  ActivationFailure<Object?> failure,
) => ExternalDiscoveryFailure<T>(
  code: switch (failure.code) {
    ActivationFailureCode.agentNotFound =>
      ExternalDiscoveryFailureCode.agentNotFound,
    ActivationFailureCode.projectRootNotFound =>
      ExternalDiscoveryFailureCode.projectRootNotFound,
    ActivationFailureCode.operationCancelled =>
      ExternalDiscoveryFailureCode.operationCancelled,
    _ => ExternalDiscoveryFailureCode.activationUnsupported,
  },
  context: failure.context,
  warnings: failure.warnings.map(_mapActivationWarning).toList(),
);

ExternalDiscoveryWarning _mapActivationWarning(ActivationWarning warning) =>
    ExternalDiscoveryWarning(
      code: switch (warning.code) {
        ActivationWarningCode.noActivationTarget =>
          ExternalDiscoveryWarningCode.noActivationTarget,
        ActivationWarningCode.projectSymbolicLinkPortability =>
          ExternalDiscoveryWarningCode.projectSymbolicLinkPortability,
        ActivationWarningCode.duplicateExposure =>
          ExternalDiscoveryWarningCode.duplicateExposure,
        ActivationWarningCode.activationTargetSkipped =>
          ExternalDiscoveryWarningCode.activationTargetSkipped,
        ActivationWarningCode.sharedActivationLocation =>
          ExternalDiscoveryWarningCode.sharedActivationLocation,
      },
      context: warning.context,
    );
