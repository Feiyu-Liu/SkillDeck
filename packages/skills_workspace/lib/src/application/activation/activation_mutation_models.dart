import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../operations/workspace_business_changes.dart';
import 'activation_models.dart';
import 'activation_result.dart';

/// Internal persisted projection for one Activation row.
///
/// SQLite row types stay behind the infrastructure adapter. Application
/// planners receive only the stable business identity and domain values they
/// need to update or delete an Activation.
final class PersistedActivation {
  PersistedActivation({
    required this.activationId,
    required this.managedSkillId,
    required this.activation,
    required this.createdAtMicros,
  }) {
    if (activationId.trim().isEmpty) {
      throw ArgumentError.value(
        activationId,
        'activationId',
        'must not be empty',
      );
    }
    if (createdAtMicros < 0) {
      throw ArgumentError.value(
        createdAtMicros,
        'createdAtMicros',
        'must not be negative',
      );
    }
  }

  final String activationId;
  final ManagedSkillId managedSkillId;
  final SkillActivation activation;
  final int createdAtMicros;
}

enum ActivationTargetExpectationKind { managed, vacant, occupiedFingerprint }

/// The target state reviewed before an Activation replacement is journaled.
final class ActivationTargetExpectation {
  const ActivationTargetExpectation.managed()
    : kind = ActivationTargetExpectationKind.managed,
      fingerprint = null;

  const ActivationTargetExpectation.vacant()
    : kind = ActivationTargetExpectationKind.vacant,
      fingerprint = null;

  ActivationTargetExpectation.occupied(String fingerprint)
    : kind = ActivationTargetExpectationKind.occupiedFingerprint,
      fingerprint = _requireFingerprint(fingerprint);

  final ActivationTargetExpectationKind kind;
  final String? fingerprint;
}

sealed class ActivationPathMutation {
  ActivationPathMutation({
    required this.managedSkillId,
    required this.slotKey,
    required this.targetPath,
  }) {
    if (slotKey.trim().isEmpty || targetPath.trim().isEmpty) {
      throw ArgumentError('Activation mutation paths must not be empty.');
    }
  }

  final ManagedSkillId managedSkillId;
  final String slotKey;
  final String targetPath;
}

final class MaterializeActivationPath extends ActivationPathMutation {
  MaterializeActivationPath({
    required super.managedSkillId,
    required super.slotKey,
    required super.targetPath,
    required this.target,
    required this.expectation,
  });

  final ResolvedActivationTarget target;
  final ActivationTargetExpectation expectation;
}

final class DeleteActivationPath extends ActivationPathMutation {
  DeleteActivationPath({
    required super.managedSkillId,
    required super.slotKey,
    required super.targetPath,
  });
}

final class ActivationMutationPlan {
  ActivationMutationPlan({
    required this.businessChanges,
    required List<ActivationPathMutation> pathMutations,
    required Set<ManagedSkillId> affectedSkillIds,
    List<ActivationWarning> warnings = const <ActivationWarning>[],
  }) : pathMutations = List.unmodifiable(pathMutations),
       affectedSkillIds = Set.unmodifiable(affectedSkillIds),
       warnings = List.unmodifiable(warnings);

  final WorkspaceBusinessChangeSet businessChanges;
  final List<ActivationPathMutation> pathMutations;
  final Set<ManagedSkillId> affectedSkillIds;
  final List<ActivationWarning> warnings;

  bool get changed => !businessChanges.isEmpty || pathMutations.isNotEmpty;
}

enum ActivationMutationFailureCode {
  skillNotFound,
  activationUnsupported,
  activationUnavailable,
  stateInconsistent,
}

sealed class ActivationMutationPlanningResult {
  const ActivationMutationPlanningResult();

  ActivationMutationPlan? get valueOrNull;
  ActivationMutationPlanningFailure? get failureOrNull;
}

final class ActivationMutationPlanningSuccess
    extends ActivationMutationPlanningResult {
  const ActivationMutationPlanningSuccess(this.value);

  final ActivationMutationPlan value;

  @override
  ActivationMutationPlan get valueOrNull => value;

  @override
  ActivationMutationPlanningFailure? get failureOrNull => null;
}

final class ActivationMutationPlanningFailure
    extends ActivationMutationPlanningResult {
  ActivationMutationPlanningFailure({
    required this.code,
    Map<String, Object?> context = const <String, Object?>{},
    List<ActivationWarning> warnings = const <ActivationWarning>[],
  }) : context = Map.unmodifiable(context),
       warnings = List.unmodifiable(warnings);

  final ActivationMutationFailureCode code;
  final Map<String, Object?> context;
  final List<ActivationWarning> warnings;

  @override
  ActivationMutationPlan? get valueOrNull => null;

  @override
  ActivationMutationPlanningFailure get failureOrNull => this;
}

bool sameActivation(SkillActivation left, SkillActivation right) =>
    left.location == right.location &&
    left.scope == right.scope &&
    left.mode == right.mode &&
    _sameStrings(left.agentIds.toSet(), right.agentIds.toSet()) &&
    left.projectRootId == right.projectRootId &&
    left.projectRootPath == right.projectRootPath;

String _requireFingerprint(String value) {
  if (value.trim().isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(value, 'fingerprint', 'must be a stable token');
  }
  return value;
}

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
