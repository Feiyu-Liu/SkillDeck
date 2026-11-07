import 'package:path/path.dart' as path;

import '../../domain/activation_selection.dart';
import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../ports/agent_activation_ports.dart';
import 'activation_models.dart';
import 'activation_result.dart';
import 'activation_target_resolver.dart';

/// Coordinates target resolution and occupancy probes without filesystem I/O.
final class ActivationOccupancyInspector {
  const ActivationOccupancyInspector({
    required ActivationTargetResolver targetResolver,
    required ActivationLocationIdentityPort locationIdentity,
    required ActivationOccupancyProbePort occupancyProbe,
  }) : _targetResolver = targetResolver,
       _locationIdentity = locationIdentity,
       _occupancyProbe = occupancyProbe;

  final ActivationTargetResolver _targetResolver;
  final ActivationLocationIdentityPort _locationIdentity;
  final ActivationOccupancyProbePort _occupancyProbe;

  Future<ActivationResult<ActivationTakeoverInspection>> inspect({
    required RepositorySnapshot snapshot,
    required Set<ManagedSkillId> managedSkillIds,
    required ActivationSelection selection,
    required RequestedActivationMode mode,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    if (token.isCancelled) {
      return ActivationFailure<ActivationTakeoverInspection>(
        code: ActivationFailureCode.operationCancelled,
      );
    }
    final resolved = await _targetResolver.resolve(
      selection: selection,
      requestedMode: mode,
      snapshot: snapshot,
    );
    final resolvedTargets = resolved.valueOrNull;
    if (resolvedTargets == null) {
      return copyActivationFailure<ActivationTakeoverInspection>(
        resolved.failureOrNull!,
      );
    }

    final warnings = <ActivationWarning>[...resolvedTargets.warnings];
    final occupancies = <InspectedActivationOccupancy>[];
    final sortedIds = managedSkillIds.toList()
      ..sort((left, right) => left.value.compareTo(right.value));
    for (final managedSkillId in sortedIds) {
      final skill = snapshot.findSkill(managedSkillId);
      if (skill == null) {
        return ActivationFailure<ActivationTakeoverInspection>(
          code: ActivationFailureCode.skillNotFound,
          context: <String, Object?>{'managedSkillId': managedSkillId.value},
          warnings: warnings,
        );
      }
      final managedLocations = <String>{
        for (final activation in skill.activations)
          _locationIdentity.key(activation.location),
      };
      for (final target in resolvedTargets.targets) {
        if (managedLocations.contains(_locationIdentity.key(target.location))) {
          continue;
        }
        if (token.isCancelled) {
          return ActivationFailure<ActivationTakeoverInspection>(
            code: ActivationFailureCode.operationCancelled,
            warnings: warnings,
          );
        }
        final targetPath = path.join(target.location, skill.slotKey);
        final inspected = await _occupancyProbe.inspect(
          skill: skill,
          target: target,
          targetPath: targetPath,
          cancellationToken: token,
        );
        final failure = inspected.failureOrNull;
        if (failure != null) {
          return copyActivationFailure<ActivationTakeoverInspection>(
            failure,
            additionalWarnings: warnings,
          );
        }
        if (inspected is ActivationSuccess<InspectedActivationOccupancy?>) {
          warnings.addAll(inspected.warnings);
        }
        final occupancy = inspected.valueOrNull;
        if (occupancy != null) {
          occupancies.add(occupancy);
        }
      }
    }
    return ActivationSuccess<ActivationTakeoverInspection>(
      value: ActivationTakeoverInspection(
        resolvedTargets: resolvedTargets,
        occupancies: occupancies,
        warnings: warnings,
      ),
      warnings: warnings,
    );
  }
}
