import 'public_models.dart';

/// Source-agnostic caller intent for choosing Agent activation targets.
sealed class ActivationSelection {
  const ActivationSelection();

  const factory ActivationSelection.none() = NoActivationSelection;
  const factory ActivationSelection.automatic({ActivationScope scope}) =
      AutomaticActivationSelection;
  factory ActivationSelection.explicit(List<ActivationTarget> targets) =
      ExplicitActivationSelection;
}

final class NoActivationSelection extends ActivationSelection {
  const NoActivationSelection();
}

final class AutomaticActivationSelection extends ActivationSelection {
  const AutomaticActivationSelection({this.scope = ActivationScope.global});

  final ActivationScope scope;
}

final class ExplicitActivationSelection extends ActivationSelection {
  ExplicitActivationSelection(List<ActivationTarget> targets)
    : targets = List.unmodifiable(targets) {
    if (targets.isEmpty) {
      throw ArgumentError.value(targets, 'targets', 'must not be empty');
    }
  }

  final List<ActivationTarget> targets;
}

final class ActivationTarget {
  ActivationTarget({
    required this.agentId,
    required this.scope,
    this.projectRootId,
  }) {
    if (agentId.trim().isEmpty) {
      throw ArgumentError.value(agentId, 'agentId', 'must not be empty');
    }
    if (scope == ActivationScope.project && projectRootId == null) {
      throw ArgumentError('Project targets require projectRootId.');
    }
    if (scope == ActivationScope.global && projectRootId != null) {
      throw ArgumentError('Global targets cannot include projectRootId.');
    }
  }

  final String agentId;
  final ActivationScope scope;
  final String? projectRootId;
}
