import 'package:skills_workspace/src/application/discovery/external_discovery_models.dart';
import 'package:skills_workspace/src/application/ports/external_discovery_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';

final class FakeExternalSkillLocationPort implements ExternalSkillLocationPort {
  final Map<String, ExternalDiscoveryResult<List<ScannedExternalSkill>>>
  results = <String, ExternalDiscoveryResult<List<ScannedExternalSkill>>>{};
  final List<String> scannedLocations = <String>[];
  final List<Set<String>?> selectedSlotKeyRequests = <Set<String>?>[];

  @override
  Future<ExternalDiscoveryResult<List<ScannedExternalSkill>>> scanLocation({
    required String location,
    Set<String>? selectedSlotKeys,
    required bool includeInternal,
    required CancellationToken cancellationToken,
  }) async {
    scannedLocations.add(location);
    selectedSlotKeyRequests.add(
      selectedSlotKeys == null ? null : Set.unmodifiable(selectedSlotKeys),
    );
    if (cancellationToken.isCancelled) {
      return ExternalDiscoveryFailure<List<ScannedExternalSkill>>(
        code: ExternalDiscoveryFailureCode.operationCancelled,
      );
    }
    return results[location] ??
        ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
          value: const <ScannedExternalSkill>[],
        );
  }
}

final class FakeProjectRootPathPort implements ProjectRootPathPort {
  final Map<String, String?> canonicalPaths = <String, String?>{};

  @override
  Future<String?> canonicalizeExistingDirectory(String candidatePath) async =>
      canonicalPaths[candidatePath];
}

final class FakeProjectRootIdPort implements ProjectRootIdPort {
  FakeProjectRootIdPort(this.nextId);

  final String nextId;
  Set<String>? reservedIds;

  @override
  String allocate(Set<String> reservedIds) {
    this.reservedIds = Set.unmodifiable(reservedIds);
    return nextId;
  }
}

final class FixedWorkspaceClock implements WorkspaceClockPort {
  const FixedWorkspaceClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
