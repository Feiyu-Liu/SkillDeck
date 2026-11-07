import '../../application/activation/activation_models.dart';
import '../../application/activation/activation_mutation_models.dart';
import '../../application/ports/activation_mutation_ports.dart';
import '../../application/ports/agent_activation_ports.dart';
import '../../domain/cancellation.dart';
import '../../domain/public_models.dart';

/// Reuses the canonical occupancy probe for last-moment takeover validation.
final class ActivationTargetExpectationProbe
    implements ActivationTargetExpectationPort {
  const ActivationTargetExpectationProbe({
    required ActivationOccupancyProbePort occupancyProbe,
  }) : _occupancyProbe = occupancyProbe;

  final ActivationOccupancyProbePort _occupancyProbe;

  @override
  Future<bool> matches({
    required ManagedSkill skill,
    required ResolvedActivationTarget target,
    required String targetPath,
    required ActivationTargetExpectation expectation,
  }) async {
    if (expectation.kind == ActivationTargetExpectationKind.managed) {
      return true;
    }
    final inspected = await _occupancyProbe.inspect(
      skill: skill,
      target: target,
      targetPath: targetPath,
      cancellationToken: CancellationToken.none(),
    );
    if (inspected.failureOrNull != null) return false;
    final occupancy = inspected.valueOrNull;
    return switch (expectation.kind) {
      ActivationTargetExpectationKind.managed => true,
      ActivationTargetExpectationKind.vacant => occupancy == null,
      ActivationTargetExpectationKind.occupiedFingerprint =>
        occupancy != null &&
            occupancy.replaceable &&
            occupancy.fingerprint == expectation.fingerprint,
    };
  }
}
