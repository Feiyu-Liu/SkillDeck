import 'package:path/path.dart' as path;

import '../../domain/public_models.dart';
import '../ports/agent_activation_ports.dart';
import 'activation_models.dart';
import 'activation_result.dart';

final class ActivationPlanner {
  const ActivationPlanner();

  ActivationPlan materialize({
    required String slotKey,
    required String copySourcePath,
    required String repositoryCopyPath,
    required ResolvedActivationTargets resolvedTargets,
  }) {
    _requireNonEmpty(slotKey, 'slotKey');
    _requireNonEmpty(copySourcePath, 'copySourcePath');
    _requireNonEmpty(repositoryCopyPath, 'repositoryCopyPath');
    final activations = <SkillActivation>[];
    final mutations = <PlannedActivationMutation>[];
    for (final target in resolvedTargets.targets) {
      final targetPath = path.join(target.location, slotKey);
      activations.add(target.toSkillActivation());
      switch (target.mode) {
        case ActivationMode.copy:
          mutations.add(
            PlannedActivationCopy(
              sourcePath: copySourcePath,
              targetPath: targetPath,
            ),
          );
        case ActivationMode.symbolicLink:
          mutations.add(
            PlannedActivationSymbolicLink(
              linkTarget: repositoryCopyPath,
              targetPath: targetPath,
            ),
          );
      }
    }
    return ActivationPlan(
      activations: activations,
      mutations: mutations,
      warnings: resolvedTargets.warnings,
    );
  }
}

final class ActivationUpdatePlanner {
  const ActivationUpdatePlanner({
    required ActivationUpdateValidationPort validator,
  }) : _validator = validator;

  final ActivationUpdateValidationPort _validator;

  Future<ActivationResult<ActivationPlan>> plan({
    required ManagedSkill skill,
    required String preparedSkillPath,
    required String repositoryCopyPath,
  }) async {
    _requireNonEmpty(preparedSkillPath, 'preparedSkillPath');
    _requireNonEmpty(repositoryCopyPath, 'repositoryCopyPath');
    final mutations = <PlannedActivationMutation>[];
    final validatedLinks = <ValidatedSymbolicLinkActivation>[];
    for (final activation in skill.activations) {
      final targetPath = path.join(activation.location, skill.slotKey);
      switch (activation.mode) {
        case ActivationMode.copy:
          final validation = await _validator.validateCopyTarget(
            activation: activation,
            targetPath: targetPath,
          );
          if (validation.failureOrNull case final failure?) {
            return copyActivationFailure<ActivationPlan>(failure);
          }
          mutations.add(
            PlannedActivationCopy(
              sourcePath: preparedSkillPath,
              targetPath: targetPath,
            ),
          );
        case ActivationMode.symbolicLink:
          final validation = await _validator.validateSymbolicLink(
            activation: activation,
            targetPath: targetPath,
            expectedLinkTarget: repositoryCopyPath,
          );
          if (validation.failureOrNull case final failure?) {
            return copyActivationFailure<ActivationPlan>(failure);
          }
          validatedLinks.add(
            ValidatedSymbolicLinkActivation(
              targetPath: targetPath,
              expectedLinkTarget: repositoryCopyPath,
            ),
          );
      }
    }
    return ActivationSuccess<ActivationPlan>(
      value: ActivationPlan(
        activations: skill.activations,
        mutations: mutations,
        validatedSymbolicLinks: validatedLinks,
      ),
    );
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
