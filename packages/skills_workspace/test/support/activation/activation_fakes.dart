import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/application/ports/agent_activation_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';

final class FakeAgentDetectionPort implements AgentDetectionPort {
  FakeAgentDetectionPort({
    bool Function(AgentDetectionPath detection, ProjectRoot? projectRoot)?
    matches,
  }) : _matches = matches ?? ((_, _) => false);

  final bool Function(AgentDetectionPath detection, ProjectRoot? projectRoot)
  _matches;

  @override
  Future<bool> matches(
    AgentDetectionPath detection, {
    ProjectRoot? projectRoot,
  }) async => _matches(detection, projectRoot);
}

final class FakeSymbolicLinkCapability implements SymbolicLinkCapabilityPort {
  FakeSymbolicLinkCapability({this.defaultResult = false});

  final bool defaultResult;
  final Map<String, bool> results = <String, bool>{};
  final List<String> inspectedLocations = <String>[];

  @override
  Future<bool> supportsSymbolicLinks(String targetLocation) async {
    inspectedLocations.add(targetLocation);
    return results[targetLocation] ?? defaultResult;
  }
}

final class PosixActivationLocationIdentity
    implements ActivationLocationIdentityPort {
  const PosixActivationLocationIdentity({
    this.sameObjectPairs = const <(String, String)>{},
    this.resolvedDirectories = const <String, String>{},
    this.missingDirectories = const <String>{},
  });

  final Set<(String, String)> sameObjectPairs;

  /// Roots that resolve elsewhere, as a symbolic-link root does. Every other
  /// root resolves to itself unless listed in [missingDirectories].
  final Map<String, String> resolvedDirectories;
  final Set<String> missingDirectories;

  @override
  Future<bool> sameExistingObject(String left, String right) async =>
      key(left) == key(right) ||
      sameObjectPairs.contains((left, right)) ||
      sameObjectPairs.contains((right, left));

  @override
  Future<String?> resolveExistingDirectory(String location) async {
    final normalized = normalize(location);
    if (missingDirectories.contains(normalized)) return null;
    final resolved = resolvedDirectories[normalized] ?? normalized;
    return normalize(resolved);
  }

  @override
  String normalize(String location) => path.posix.normalize(
    path.posix.isAbsolute(location) ? location : path.posix.absolute(location),
  );

  @override
  String key(String location) => normalize(location);
}

final class WindowsActivationLocationIdentity
    implements ActivationLocationIdentityPort {
  const WindowsActivationLocationIdentity({
    this.sameObjectPairs = const <(String, String)>{},
    this.resolvedDirectories = const <String, String>{},
    this.missingDirectories = const <String>{},
  });

  final Set<(String, String)> sameObjectPairs;
  final Map<String, String> resolvedDirectories;
  final Set<String> missingDirectories;

  @override
  Future<bool> sameExistingObject(String left, String right) async =>
      key(left) == key(right) ||
      sameObjectPairs.contains((left, right)) ||
      sameObjectPairs.contains((right, left));

  @override
  Future<String?> resolveExistingDirectory(String location) async {
    final normalized = normalize(location);
    if (missingDirectories.contains(normalized)) return null;
    final resolved = resolvedDirectories[normalized] ?? normalized;
    return normalize(resolved);
  }

  @override
  String normalize(String location) => path.windows.normalize(
    path.windows.isAbsolute(location)
        ? location
        : path.windows.absolute(location),
  );

  @override
  String key(String location) => normalize(location).toUpperCase();
}

final class RecordingActivationUpdateValidator
    implements ActivationUpdateValidationPort {
  RecordingActivationUpdateValidator({this.failLocation});

  final String? failLocation;
  final List<String?> copyProjectRootIds = <String?>[];
  final List<String> symbolicLinkTargets = <String>[];

  @override
  Future<ActivationResult<void>> validateCopyTarget({
    required SkillActivation activation,
    required String targetPath,
  }) async {
    copyProjectRootIds.add(activation.projectRootId);
    return _result(activation.location);
  }

  @override
  Future<ActivationResult<void>> validateSymbolicLink({
    required SkillActivation activation,
    required String targetPath,
    required String expectedLinkTarget,
  }) async {
    symbolicLinkTargets.add(expectedLinkTarget);
    return _result(activation.location);
  }

  ActivationResult<void> _result(String location) {
    if (location == failLocation) {
      return ActivationFailure<void>(
        code: ActivationFailureCode.activationUnavailable,
        context: <String, Object?>{'location': location},
      );
    }
    return ActivationSuccess<void>(value: null);
  }
}

final class RecordingActivationOccupancyProbe
    implements ActivationOccupancyProbePort {
  final Map<String, InspectedActivationOccupancy?> results =
      <String, InspectedActivationOccupancy?>{};
  final Map<String, ActivationFailure<InspectedActivationOccupancy?>> failures =
      <String, ActivationFailure<InspectedActivationOccupancy?>>{};
  final List<String> inspectedPaths = <String>[];

  @override
  Future<ActivationResult<InspectedActivationOccupancy?>> inspect({
    required ManagedSkill skill,
    required ResolvedActivationTarget target,
    required String targetPath,
    required CancellationToken cancellationToken,
  }) async {
    inspectedPaths.add(targetPath);
    final failure = failures[targetPath];
    if (failure != null) {
      return failure;
    }
    return ActivationSuccess<InspectedActivationOccupancy?>(
      value: results[targetPath],
    );
  }
}

ManagedSkill activationSkill({List<SkillActivation> activations = const []}) =>
    ManagedSkill(
      id: ManagedSkillId('123e4567-e89b-42d3-a456-426614174999'),
      slotKey: 'example',
      declaredName: 'example',
      displayName: 'Example',
      description: 'Example Skill',
      source: LocalSourceDescriptor(locator: '/source/example'),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        publishedAt: DateTime.utc(2026, 8, 17),
      ),
      activations: activations,
    );

ResolvedActivationTarget activationTarget({
  String location = '/agents/skills',
  ActivationMode mode = ActivationMode.copy,
}) => ResolvedActivationTarget(
  location: location,
  scope: ActivationScope.global,
  mode: mode,
  agentIds: const <String>['agent'],
);
