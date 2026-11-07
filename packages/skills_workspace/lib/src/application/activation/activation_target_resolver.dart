import '../../domain/activation_selection.dart';
import '../../domain/public_models.dart';
import '../agents/agent_catalog.dart';
import '../ports/agent_activation_ports.dart';
import 'activation_models.dart';
import 'activation_result.dart';

final class ActivationTargetResolver {
  const ActivationTargetResolver({
    required AgentCatalog catalog,
    required SymbolicLinkCapabilityPort symbolicLinkCapability,
    required ActivationLocationIdentityPort locationIdentity,
  }) : _catalog = catalog,
       _symbolicLinkCapability = symbolicLinkCapability,
       _locationIdentity = locationIdentity;

  final AgentCatalog _catalog;
  final SymbolicLinkCapabilityPort _symbolicLinkCapability;
  final ActivationLocationIdentityPort _locationIdentity;

  Future<ActivationResult<ResolvedActivationTargets>> resolve({
    required ActivationSelection selection,
    required RequestedActivationMode requestedMode,
    required RepositorySnapshot snapshot,
  }) async {
    if (selection is NoActivationSelection) {
      return ActivationSuccess<ResolvedActivationTargets>(
        value: ResolvedActivationTargets(targets: const []),
      );
    }

    final warnings = <ActivationWarning>[];
    final candidates = selection is AutomaticActivationSelection
        ? await _automaticCandidates(selection, snapshot, warnings)
        : _explicitCandidates(
            selection as ExplicitActivationSelection,
            snapshot,
          );
    final candidatesFailure = candidates.failureOrNull;
    if (candidatesFailure != null) {
      return copyActivationFailure<ResolvedActivationTargets>(
        candidatesFailure,
        additionalWarnings: warnings,
      );
    }

    final grouped = await _groupCandidates(candidates.valueOrNull!, warnings);
    final groupedFailure = grouped.failureOrNull;
    if (groupedFailure != null) {
      return copyActivationFailure<ResolvedActivationTargets>(
        groupedFailure,
        additionalWarnings: warnings,
      );
    }

    final targets = <ResolvedActivationTarget>[];
    for (final group in grouped.valueOrNull!) {
      final modeResult = await _resolveMode(group, requestedMode);
      final mode = modeResult.valueOrNull;
      if (mode == null) {
        return copyActivationFailure<ResolvedActivationTargets>(
          modeResult.failureOrNull!,
          additionalWarnings: warnings,
        );
      }
      if (group.scope == ActivationScope.project &&
          requestedMode == RequestedActivationMode.symbolicLink) {
        warnings.add(
          ActivationWarning(
            code: ActivationWarningCode.projectSymbolicLinkPortability,
            context: <String, Object?>{
              'projectRootId': group.projectRootId,
              'agentIds': group.agentIds,
            },
          ),
        );
      }
      targets.add(
        ResolvedActivationTarget(
          location: group.location,
          scope: group.scope,
          mode: mode,
          agentIds: group.agentIds,
          projectRootId: group.projectRootId,
          projectRootPath: group.projectRootPath,
        ),
      );
    }

    if (selection is AutomaticActivationSelection && targets.isEmpty) {
      warnings.add(
        ActivationWarning(
          code: ActivationWarningCode.noActivationTarget,
          context: <String, Object?>{'scope': selection.scope.name},
        ),
      );
    }
    _appendDuplicateExposureWarnings(targets, warnings);
    return ActivationSuccess<ResolvedActivationTargets>(
      value: ResolvedActivationTargets(targets: targets, warnings: warnings),
      warnings: warnings,
    );
  }

  Future<ActivationResult<List<ResolvedAgentTarget>>> _automaticCandidates(
    AutomaticActivationSelection selection,
    RepositorySnapshot snapshot,
    List<ActivationWarning> warnings,
  ) async {
    final candidates = <ResolvedAgentTarget>[];
    if (selection.scope == ActivationScope.global) {
      final detected = (await _catalog.detect()).toList()..sort();
      for (final agentId in detected) {
        _appendAutomaticCandidate(
          candidates,
          warnings,
          agentId: agentId,
          scope: ActivationScope.global,
        );
      }
    } else {
      final roots = snapshot.projectRoots.toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      for (final root in roots) {
        final detected = (await _catalog.detect(projectRoot: root)).toList()
          ..sort();
        for (final agentId in detected) {
          _appendAutomaticCandidate(
            candidates,
            warnings,
            agentId: agentId,
            scope: ActivationScope.project,
            projectRoot: root,
          );
        }
      }
    }
    return ActivationSuccess<List<ResolvedAgentTarget>>(value: candidates);
  }

  void _appendAutomaticCandidate(
    List<ResolvedAgentTarget> candidates,
    List<ActivationWarning> warnings, {
    required String agentId,
    required ActivationScope scope,
    ProjectRoot? projectRoot,
  }) {
    final resolved = _catalog.resolve(
      agentId: agentId,
      scope: scope,
      projectRoot: projectRoot,
    );
    final target = resolved.valueOrNull;
    if (target != null) {
      candidates.add(target);
      return;
    }
    warnings.add(
      ActivationWarning(
        code: ActivationWarningCode.activationTargetSkipped,
        context: <String, Object?>{
          'agentId': agentId,
          'scope': scope.name,
          if (projectRoot != null) 'projectRootId': projectRoot.id,
          'reason': resolved.failureOrNull!.code.name,
        },
      ),
    );
  }

  ActivationResult<List<ResolvedAgentTarget>> _explicitCandidates(
    ExplicitActivationSelection selection,
    RepositorySnapshot snapshot,
  ) {
    final candidates = <ResolvedAgentTarget>[];
    for (final target in selection.targets) {
      ProjectRoot? projectRoot;
      if (target.scope == ActivationScope.project) {
        projectRoot = snapshot.findProjectRoot(target.projectRootId!);
        if (projectRoot == null) {
          return ActivationFailure<List<ResolvedAgentTarget>>(
            code: ActivationFailureCode.projectRootNotFound,
            context: <String, Object?>{
              'agentId': target.agentId,
              'projectRootId': target.projectRootId,
            },
          );
        }
      }
      final resolved = _catalog.resolve(
        agentId: target.agentId,
        scope: target.scope,
        projectRoot: projectRoot,
      );
      final candidate = resolved.valueOrNull;
      if (candidate == null) {
        return copyActivationFailure<List<ResolvedAgentTarget>>(
          resolved.failureOrNull!,
        );
      }
      candidates.add(candidate);
    }
    return ActivationSuccess<List<ResolvedAgentTarget>>(value: candidates);
  }

  /// Groups Agents by the physical directory their root resolves to, so two
  /// configured roots that are one folder (a dotfiles `~/.agents/skills`
  /// linked to `~/.claude/skills`, for example) become one Activation Group
  /// and one filesystem mutation (ADR-0090). A root that does not exist yet
  /// keeps its own lexical group.
  Future<ActivationResult<List<_TargetGroup>>> _groupCandidates(
    List<ResolvedAgentTarget> candidates,
    List<ActivationWarning> warnings,
  ) async {
    final groups = <String, _MutableTargetGroup>{};
    for (final candidate in candidates) {
      final location = _locationIdentity.normalize(candidate.location);
      final resolved = await _locationIdentity.resolveExistingDirectory(
        location,
      );
      final key = _locationIdentity.key(resolved ?? location);
      final existing = groups[key];
      if (existing == null) {
        groups[key] = _MutableTargetGroup(
          candidate,
          location,
          locationKey: _locationIdentity.key(location),
          resolvedLocation: resolved,
        );
        continue;
      }
      if (!existing.hasSameProvenance(candidate)) {
        return ActivationFailure<List<_TargetGroup>>(
          code: ActivationFailureCode.activationUnsupported,
          context: <String, Object?>{
            'reason': 'conflictingLocationProvenance',
            'agentIds': <String>[existing.agentIds.first, candidate.agentId],
          },
        );
      }
      existing.agentIds.add(candidate.agentId);
      existing.addLocation(location, _locationIdentity.key(location));
    }
    final entries = groups.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final frozen = <_TargetGroup>[];
    for (final entry in entries) {
      final group = entry.value.freeze(_locationIdentity.key);
      if (group.mergedLocations.length > 1) {
        warnings.add(
          ActivationWarning(
            code: ActivationWarningCode.sharedActivationLocation,
            context: <String, Object?>{
              'location': group.location,
              'locations': group.mergedLocations,
              'agentIds': group.agentIds,
            },
          ),
        );
      }
      frozen.add(group);
    }
    return ActivationSuccess<List<_TargetGroup>>(value: frozen);
  }

  Future<ActivationResult<ActivationMode>> _resolveMode(
    _TargetGroup group,
    RequestedActivationMode requested,
  ) async {
    if (requested == RequestedActivationMode.copy ||
        (requested == RequestedActivationMode.automatic &&
            group.scope == ActivationScope.project)) {
      return ActivationSuccess<ActivationMode>(value: ActivationMode.copy);
    }
    final supportsLinks = await _symbolicLinkCapability.supportsSymbolicLinks(
      group.location,
    );
    if (supportsLinks) {
      return ActivationSuccess<ActivationMode>(
        value: ActivationMode.symbolicLink,
      );
    }
    if (requested == RequestedActivationMode.automatic) {
      return ActivationSuccess<ActivationMode>(value: ActivationMode.copy);
    }
    return ActivationFailure<ActivationMode>(
      code: ActivationFailureCode.activationUnsupported,
      context: <String, Object?>{
        'scope': group.scope.name,
        'agentIds': group.agentIds,
        'reason': 'symbolicLinkUnavailable',
      },
    );
  }

  void _appendDuplicateExposureWarnings(
    List<ResolvedActivationTarget> targets,
    List<ActivationWarning> warnings,
  ) {
    final byAgent = <String, List<ResolvedActivationTarget>>{};
    for (final target in targets) {
      for (final agentId in target.agentIds) {
        byAgent
            .putIfAbsent(agentId, () => <ResolvedActivationTarget>[])
            .add(target);
      }
    }
    for (final entry in byAgent.entries) {
      final scopes = entry.value.map((target) => target.scope).toSet();
      if (scopes.length > 1) {
        warnings.add(
          ActivationWarning(
            code: ActivationWarningCode.duplicateExposure,
            context: <String, Object?>{'agentId': entry.key},
          ),
        );
      }
    }
  }
}

final class _MutableTargetGroup {
  _MutableTargetGroup(
    ResolvedAgentTarget target,
    String location, {
    required String locationKey,
    required this.resolvedLocation,
  }) : scope = target.scope,
       projectRootId = target.projectRootId,
       projectRootPath = target.projectRootPath,
       agentIds = <String>{target.agentId},
       locations = <String>[location],
       _locationKeys = <String>{locationKey};

  /// The physical directory every member resolves to, or null when the
  /// single member does not exist yet.
  final String? resolvedLocation;
  final ActivationScope scope;
  final String? projectRootId;
  final String? projectRootPath;
  final Set<String> agentIds;

  /// Every configured root merged into this group, in candidate order.
  final List<String> locations;
  final Set<String> _locationKeys;

  bool hasSameProvenance(ResolvedAgentTarget target) =>
      scope == target.scope &&
      projectRootId == target.projectRootId &&
      projectRootPath == target.projectRootPath;

  void addLocation(String location, String key) {
    if (_locationKeys.add(key)) locations.add(location);
  }

  /// The group's recorded location: the configured root that is the physical
  /// directory itself when one exists, otherwise the lexically first root.
  /// Deterministic, so later plans index persisted Activations by it.
  _TargetGroup freeze(String Function(String location) keyOf) {
    final sortedAgentIds = agentIds.toList()..sort();
    final merged = locations.toList()..sort();
    final physical = resolvedLocation;
    final representative = physical == null
        ? merged.first
        : merged.firstWhere(
            (location) => keyOf(location) == keyOf(physical),
            orElse: () => merged.first,
          );
    return _TargetGroup(
      location: representative,
      mergedLocations: merged,
      scope: scope,
      projectRootId: projectRootId,
      projectRootPath: projectRootPath,
      agentIds: sortedAgentIds,
    );
  }
}

final class _TargetGroup {
  _TargetGroup({
    required this.location,
    required List<String> mergedLocations,
    required this.scope,
    required this.projectRootId,
    required this.projectRootPath,
    required List<String> agentIds,
  }) : mergedLocations = List.unmodifiable(mergedLocations),
       agentIds = List.unmodifiable(agentIds);

  final String location;
  final List<String> mergedLocations;
  final ActivationScope scope;
  final String? projectRootId;
  final String? projectRootPath;
  final List<String> agentIds;
}
