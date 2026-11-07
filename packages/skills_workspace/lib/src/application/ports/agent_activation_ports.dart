import '../../domain/cancellation.dart';
import '../../domain/public_models.dart';
import '../activation/activation_models.dart';
import '../activation/activation_result.dart';

abstract interface class AgentDetectionPort {
  Future<bool> matches(
    AgentDetectionPath detection, {
    ProjectRoot? projectRoot,
  });
}

abstract interface class SymbolicLinkCapabilityPort {
  Future<bool> supportsSymbolicLinks(String targetLocation);
}

abstract interface class ActivationLocationIdentityPort {
  String normalize(String location);
  String key(String location);

  /// Whether both existing paths identify the same final filesystem entry.
  ///
  /// Does not follow final symbolic links. Returns false if either path cannot
  /// be statted, including when either entry does not exist.
  Future<bool> sameExistingObject(String left, String right);

  /// The normalized physical path of [location] with every symbolic link in
  /// it followed, or null when [location] does not exist, is not a directory,
  /// or cannot be resolved. Never throws.
  ///
  /// Two configured Agent roots that resolve to one physical directory form
  /// one Activation Group (ADR-0090).
  Future<String?> resolveExistingDirectory(String location);
}

abstract interface class ActivationUpdateValidationPort {
  Future<ActivationResult<void>> validateCopyTarget({
    required SkillActivation activation,
    required String targetPath,
  });

  Future<ActivationResult<void>> validateSymbolicLink({
    required SkillActivation activation,
    required String targetPath,
    required String expectedLinkTarget,
  });
}

abstract interface class ActivationOccupancyProbePort {
  Future<ActivationResult<InspectedActivationOccupancy?>> inspect({
    required ManagedSkill skill,
    required ResolvedActivationTarget target,
    required String targetPath,
    required CancellationToken cancellationToken,
  });
}
