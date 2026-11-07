import '../../domain/cancellation.dart';
import '../discovery/external_discovery_models.dart';

abstract interface class ExternalSkillLocationPort {
  Future<ExternalDiscoveryResult<List<ScannedExternalSkill>>> scanLocation({
    required String location,
    Set<String>? selectedSlotKeys,
    required bool includeInternal,
    required CancellationToken cancellationToken,
  });
}

/// Canonicalizes one caller-selected Project Root without mutating it.
abstract interface class ProjectRootPathPort {
  Future<String?> canonicalizeExistingDirectory(String candidatePath);
}

abstract interface class ProjectRootIdPort {
  String allocate(Set<String> reservedIds);
}

abstract interface class WorkspaceClockPort {
  DateTime now();
}
