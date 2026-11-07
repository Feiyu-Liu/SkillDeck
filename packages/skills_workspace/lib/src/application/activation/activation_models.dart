import '../../domain/identifiers.dart';
import '../../domain/immutable.dart';
import '../../domain/public_models.dart';
import 'activation_result.dart';

final class ResolvedAgentTarget {
  const ResolvedAgentTarget({
    required this.agentId,
    required this.location,
    required this.scope,
    this.projectRootId,
    this.projectRootPath,
  });

  final String agentId;
  final String location;
  final ActivationScope scope;
  final String? projectRootId;
  final String? projectRootPath;
}

/// One read-only discovery location associated with its canonical Activation.
///
/// [location] may be a legacy or compatibility path. Mutating operations must
/// use [canonicalTarget] instead.
final class ResolvedAgentDiscoveryTarget {
  const ResolvedAgentDiscoveryTarget({
    required this.location,
    required this.canonicalTarget,
  });

  final String location;
  final ResolvedAgentTarget canonicalTarget;
}

final class ResolvedActivationTarget {
  ResolvedActivationTarget({
    required this.location,
    required this.scope,
    required this.mode,
    required List<String> agentIds,
    this.projectRootId,
    this.projectRootPath,
  }) : agentIds = List.unmodifiable(agentIds) {
    if (location.trim().isEmpty) {
      throw ArgumentError.value(location, 'location', 'must not be empty');
    }
    if (agentIds.isEmpty || agentIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(agentIds, 'agentIds', 'must contain valid IDs');
    }
    if (scope == ActivationScope.project &&
        (projectRootId == null || projectRootPath == null)) {
      throw ArgumentError('Project targets require Project Root provenance.');
    }
    if (scope == ActivationScope.global &&
        (projectRootId != null || projectRootPath != null)) {
      throw ArgumentError(
        'Global targets cannot contain Project Root provenance.',
      );
    }
  }

  final String location;
  final ActivationScope scope;
  final ActivationMode mode;
  final List<String> agentIds;
  final String? projectRootId;
  final String? projectRootPath;

  SkillActivation toSkillActivation() => SkillActivation(
    location: location,
    scope: scope,
    mode: mode,
    agentIds: agentIds,
    projectRootId: projectRootId,
    projectRootPath: projectRootPath,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedActivationTarget &&
          location == other.location &&
          scope == other.scope &&
          mode == other.mode &&
          listsEqual(agentIds, other.agentIds) &&
          projectRootId == other.projectRootId &&
          projectRootPath == other.projectRootPath;

  @override
  int get hashCode => Object.hash(
    location,
    scope,
    mode,
    Object.hashAll(agentIds),
    projectRootId,
    projectRootPath,
  );
}

final class ResolvedActivationTargets {
  ResolvedActivationTargets({
    required List<ResolvedActivationTarget> targets,
    List<ActivationWarning> warnings = const [],
  }) : targets = List.unmodifiable(targets),
       warnings = List.unmodifiable(warnings);

  final List<ResolvedActivationTarget> targets;
  final List<ActivationWarning> warnings;
}

sealed class PlannedActivationMutation {
  PlannedActivationMutation({required this.targetPath}) {
    if (targetPath.trim().isEmpty) {
      throw ArgumentError.value(targetPath, 'targetPath', 'must not be empty');
    }
  }

  final String targetPath;
}

final class PlannedActivationCopy extends PlannedActivationMutation {
  PlannedActivationCopy({required this.sourcePath, required super.targetPath}) {
    if (sourcePath.trim().isEmpty) {
      throw ArgumentError.value(sourcePath, 'sourcePath', 'must not be empty');
    }
  }

  final String sourcePath;
}

final class PlannedActivationSymbolicLink extends PlannedActivationMutation {
  PlannedActivationSymbolicLink({
    required this.linkTarget,
    required super.targetPath,
  }) {
    if (linkTarget.trim().isEmpty) {
      throw ArgumentError.value(linkTarget, 'linkTarget', 'must not be empty');
    }
  }

  final String linkTarget;
}

final class ValidatedSymbolicLinkActivation {
  ValidatedSymbolicLinkActivation({
    required this.targetPath,
    required this.expectedLinkTarget,
  }) {
    if (targetPath.trim().isEmpty || expectedLinkTarget.trim().isEmpty) {
      throw ArgumentError('Symbolic-link paths must not be empty.');
    }
  }

  final String targetPath;
  final String expectedLinkTarget;
}

final class ActivationPlan {
  ActivationPlan({
    required List<SkillActivation> activations,
    required List<PlannedActivationMutation> mutations,
    List<ValidatedSymbolicLinkActivation> validatedSymbolicLinks = const [],
    List<ActivationWarning> warnings = const [],
  }) : activations = List.unmodifiable(activations),
       mutations = List.unmodifiable(mutations),
       validatedSymbolicLinks = List.unmodifiable(validatedSymbolicLinks),
       warnings = List.unmodifiable(warnings);

  final List<SkillActivation> activations;
  final List<PlannedActivationMutation> mutations;
  final List<ValidatedSymbolicLinkActivation> validatedSymbolicLinks;
  final List<ActivationWarning> warnings;
}

enum InspectedActivationOccupancyKind {
  skillDirectory,
  skillSymbolicLink,
  file,
  invalidDirectory,
  brokenSymbolicLink,
  unsupported,
}

enum InspectedActivationContentRelation {
  matchesCurrentRevision,
  differsFromCurrentRevision,
  indeterminate,
}

/// Local adoption diagnostics; deliberately not part of the public API.
enum AdoptionTargetOccupant {
  emptyDirectory,
  danglingLink,
  file,
  invalidSkill,
  directoryWithContent,
  otherSkill,
  sameSlotSkill,
  link,
  unknown;

  bool get isInert => this == emptyDirectory || this == danglingLink;
}

final class InspectedActivationOccupancy {
  const InspectedActivationOccupancy({
    required this.managedSkillId,
    required this.slotKey,
    required this.target,
    required this.targetPath,
    required this.kind,
    required this.contentRelation,
    required this.fingerprint,
    required this.replaceable,
    this.existingSlotKey,
    this.directoryIsEmpty = false,
    this.rootSkillPresent = false,
    this.linkReferentMissing = false,
    this.linkReferentUncertain = false,
    this.occupantFailureCode,
    this.occupantFailureReason,
    this.existingDeclaredName,
    this.existingContentHash,
    this.linkTarget,
    this.pointsToRepositoryCopy = false,
  });

  final ManagedSkillId managedSkillId;
  final String slotKey;
  final ResolvedActivationTarget target;
  final String targetPath;
  final InspectedActivationOccupancyKind kind;
  final InspectedActivationContentRelation contentRelation;
  final String fingerprint;
  final bool replaceable;
  final String? existingSlotKey;
  final bool directoryIsEmpty;
  final bool rootSkillPresent;
  final bool linkReferentMissing;
  final bool linkReferentUncertain;

  AdoptionTargetOccupant get adoptionOccupant {
    if (existingSlotKey case final existing?) {
      return existing == slotKey
          ? AdoptionTargetOccupant.sameSlotSkill
          : AdoptionTargetOccupant.otherSkill;
    }
    if (linkReferentUncertain) return AdoptionTargetOccupant.unknown;
    if (linkTarget != null) {
      return linkReferentMissing
          ? AdoptionTargetOccupant.danglingLink
          : AdoptionTargetOccupant.link;
    }
    if (kind == InspectedActivationOccupancyKind.file) {
      return AdoptionTargetOccupant.file;
    }
    if (kind == InspectedActivationOccupancyKind.invalidDirectory) {
      if (directoryIsEmpty) return AdoptionTargetOccupant.emptyDirectory;
      return rootSkillPresent
          ? AdoptionTargetOccupant.invalidSkill
          : AdoptionTargetOccupant.directoryWithContent;
    }
    return AdoptionTargetOccupant.unknown;
  }

  /// Local source-read diagnostics, never raw exceptions or paths.
  final String? occupantFailureCode;
  final String? occupantFailureReason;

  final String? existingDeclaredName;
  final String? existingContentHash;
  final String? linkTarget;
  final bool pointsToRepositoryCopy;
}

final class ActivationTakeoverInspection {
  ActivationTakeoverInspection({
    required this.resolvedTargets,
    required List<InspectedActivationOccupancy> occupancies,
    required List<ActivationWarning> warnings,
  }) : occupancies = List.unmodifiable(occupancies),
       warnings = List.unmodifiable(warnings);

  final ResolvedActivationTargets resolvedTargets;
  final List<InspectedActivationOccupancy> occupancies;
  final List<ActivationWarning> warnings;

  bool get canReplace => occupancies.every((entry) => entry.replaceable);

  bool get allContentMatches =>
      occupancies.isNotEmpty &&
      occupancies.every(
        (entry) =>
            entry.contentRelation ==
            InspectedActivationContentRelation.matchesCurrentRevision,
      );
}
