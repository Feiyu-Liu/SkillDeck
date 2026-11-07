import 'package:flutter/foundation.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

/// Where Agents find the CLI: a copy the App keeps at a stable path, because
/// the bundled binary moves with the App (ADR-0111 decision 8).
enum CommandLineToolStatus {
  /// The stable copy matches the running App.
  ready,

  /// This build ships no CLI binary, as in some development builds.
  notBundled,

  /// The copy could not be written; the previous copy, if any, is unchanged.
  failed,
}

@immutable
final class CommandLineToolState {
  const CommandLineToolState({required this.status, required this.path});

  final CommandLineToolStatus status;

  /// The absolute stable path, such as `/Users/me/.skilldeck/bin/skilldeck`.
  final String path;
}

/// The `skilldeck` Agent Skill that teaches Agents the CLI. The App ships it
/// and installs it like any other Skill, from a local Source it maintains.
@immutable
final class SkillDeckAgentSkillState {
  SkillDeckAgentSkillState({
    required this.installed,
    this.skillId,
    Set<String> activeAgentIds = const {},
  }) : activeAgentIds = Set.unmodifiable(activeAgentIds);

  const SkillDeckAgentSkillState.notInstalled()
    : installed = false,
      skillId = null,
      activeAgentIds = const {};

  final bool installed;
  final WorkspaceSkillId? skillId;

  /// Agents the Skill is active for, from its global Activations.
  final Set<String> activeAgentIds;
}

abstract interface class SkillDeckAgentSkillService {
  /// Installs the shipped Agent Skill and activates it globally for exactly
  /// [agentIds]; an empty set installs it without activating it. Returns null
  /// on success.
  Future<AppFailure?> install({required Set<String> agentIds});
}
