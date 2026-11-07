import 'package:path/path.dart' as path;

import '../../domain/public_models.dart';
import '../activation/activation_models.dart';
import '../activation/activation_result.dart';
import '../ports/agent_activation_ports.dart';

/// Source-agnostic catalog of Agent activation conventions.
final class AgentCatalog {
  AgentCatalog._({
    required this.platform,
    required AgentDetectionPort detectionPort,
    required Map<String, AgentDefinition> definitions,
  }) : _detectionPort = detectionPort,
       _definitions = definitions;

  static ActivationResult<AgentCatalog> create({
    required DesktopPlatform platform,
    required AgentDetectionPort detectionPort,
    required List<AgentDefinition> builtIns,
    List<AgentDefinition> additional = const [],
  }) {
    final definitions = <String, AgentDefinition>{};
    for (final definition in <AgentDefinition>[...builtIns, ...additional]) {
      if (definitions.containsKey(definition.id)) {
        return ActivationFailure<AgentCatalog>(
          code: ActivationFailureCode.duplicateAgentId,
          context: <String, Object?>{'agentId': definition.id},
        );
      }
      definitions[definition.id] = definition;
    }
    return ActivationSuccess<AgentCatalog>(
      value: AgentCatalog._(
        platform: platform,
        detectionPort: detectionPort,
        definitions: Map.unmodifiable(definitions),
      ),
    );
  }

  final DesktopPlatform platform;
  final AgentDetectionPort _detectionPort;
  final Map<String, AgentDefinition> _definitions;

  List<AgentDefinition> get definitions =>
      List.unmodifiable(_definitions.values);

  AgentDefinition? find(String id) => _definitions[id];

  Future<Set<String>> detect({ProjectRoot? projectRoot}) async {
    final detected = <String>{};
    for (final definition in _definitions.values) {
      final rules = definition.onPlatform(platform);
      if (rules == null || rules.detectionPaths.isEmpty) {
        continue;
      }
      final checks = <bool>[];
      for (final detection in rules.detectionPaths) {
        checks.add(
          await _detectionPort.matches(detection, projectRoot: projectRoot),
        );
      }
      final matches = rules.requireAllDetectionPaths
          ? checks.every((value) => value)
          : checks.any((value) => value);
      if (matches) {
        detected.add(definition.id);
      }
    }
    return Set.unmodifiable(detected);
  }

  ActivationResult<ResolvedAgentTarget> resolve({
    required String agentId,
    required ActivationScope scope,
    ProjectRoot? projectRoot,
  }) {
    final definition = _definitions[agentId];
    if (definition == null) {
      return ActivationFailure<ResolvedAgentTarget>(
        code: ActivationFailureCode.agentNotFound,
        context: <String, Object?>{'agentId': agentId},
      );
    }
    final platformDefinition = definition.onPlatform(platform);
    if (platformDefinition == null) {
      return ActivationFailure<ResolvedAgentTarget>(
        code: ActivationFailureCode.activationUnsupported,
        context: <String, Object?>{
          'agentId': agentId,
          'platform': platform.name,
        },
      );
    }

    String? location;
    String? projectRootId;
    String? projectRootPath;
    if (scope == ActivationScope.global) {
      location = platformDefinition.globalSkillsPath;
    } else if (projectRoot == null) {
      return ActivationFailure<ResolvedAgentTarget>(
        code: ActivationFailureCode.projectRootNotFound,
        context: <String, Object?>{'agentId': agentId},
      );
    } else {
      final relative = platformDefinition.projectSkillsPath;
      if (relative != null) {
        location = path.join(projectRoot.path, relative);
        projectRootId = projectRoot.id;
        projectRootPath = projectRoot.path;
      }
    }
    if (location == null) {
      return ActivationFailure<ResolvedAgentTarget>(
        code: ActivationFailureCode.activationUnsupported,
        context: <String, Object?>{
          'agentId': agentId,
          'platform': platform.name,
          'scope': scope.name,
        },
      );
    }

    return ActivationSuccess<ResolvedAgentTarget>(
      value: ResolvedAgentTarget(
        agentId: agentId,
        location: path.normalize(path.absolute(location)),
        scope: scope,
        projectRootId: projectRootId,
        projectRootPath: projectRootPath,
      ),
    );
  }

  /// Resolves every read-only location that may contain Skills for one Agent.
  ///
  /// Each returned location retains the canonical target that must be used by
  /// mutating operations. Compatibility paths never become Activation paths.
  ActivationResult<List<ResolvedAgentDiscoveryTarget>> resolveDiscovery({
    required String agentId,
    required ActivationScope scope,
    ProjectRoot? projectRoot,
  }) {
    final canonical = resolve(
      agentId: agentId,
      scope: scope,
      projectRoot: projectRoot,
    );
    final canonicalTarget = canonical.valueOrNull;
    if (canonicalTarget == null) {
      return ActivationFailure<List<ResolvedAgentDiscoveryTarget>>(
        code: canonical.failureOrNull!.code,
        context: canonical.failureOrNull!.context,
        warnings: canonical.failureOrNull!.warnings,
      );
    }
    final platformDefinition = _definitions[agentId]!.onPlatform(platform)!;
    final aliases = switch (scope) {
      ActivationScope.global => platformDefinition.globalDiscoverySkillsPaths,
      ActivationScope.project =>
        platformDefinition.projectDiscoverySkillsPaths.map(
          (relative) => path.join(projectRoot!.path, relative),
        ),
    };
    final seen = <String>{};
    final locations = <ResolvedAgentDiscoveryTarget>[];
    for (final location in <String>[canonicalTarget.location, ...aliases]) {
      final normalized = path.normalize(path.absolute(location));
      if (!seen.add(normalized)) continue;
      locations.add(
        ResolvedAgentDiscoveryTarget(
          location: normalized,
          canonicalTarget: canonicalTarget,
        ),
      );
    }
    return ActivationSuccess<List<ResolvedAgentDiscoveryTarget>>(
      value: List.unmodifiable(locations),
    );
  }
}
