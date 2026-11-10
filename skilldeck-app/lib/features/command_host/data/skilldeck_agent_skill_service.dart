import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

import 'command_line_distribution.dart';

final class LocalSkillDeckAgentSkillService
    implements SkillDeckAgentSkillService {
  LocalSkillDeckAgentSkillService({
    required this.repository,
    required this.sourceDirectory,
  });

  final SkillsWorkspaceRepository Function() repository;
  final Future<String> Function() sourceDirectory;

  @override
  Future<AppFailure?> install({required Set<String> agentIds}) async {
    try {
      final directory = await sourceDirectory();
      return await AppDiagnostics.withoutDetails(() async {
        final completion = await repository()
            .install(
              WorkspaceInstallRequest(
                source: SkillSourceInput(
                  kind: WorkspaceSourceKind.local,
                  locator: directory,
                ),
                skillNames: {'skilldeck'},
                scope: WorkspaceScope.global,
                agentIds: agentIds,
                storeOnly: agentIds.isEmpty,
              ),
            )
            .completed;
        return switch (completion) {
          WorkspaceCompleted(value: WorkspaceInstallCompleted()) => null,
          WorkspaceCompleted(value: WorkspaceInstallTakeoverRequired()) =>
            const AgentSkillInstallFailure('activationTargetOccupied'),
          WorkspaceFailed(:final failure) => failure,
          WorkspaceCommittedPending() => const AgentSkillInstallFailure(
            'committedFinalizationPending',
          ),
        };
      });
    } on Object catch (error) {
      return normalizeAppFailure(
        error,
        operationKey: 'installSkills',
        message: AppFailureMessage.installSkills,
      );
    }
  }
}

/// Stable, detail-free failure for App-only distribution boundaries.
final class AgentSkillInstallFailure implements AppFailure {
  const AgentSkillInstallFailure(this.codeKey);
  @override
  final String codeKey;
  @override
  String get operationKey => 'installSkills';
  @override
  AppFailureMessage get message => AppFailureMessage.installSkills;
  @override
  AppRecoveryPolicy get recoveryPolicy => AppRecoveryPolicy.retryExplicitly;
  @override
  Map<String, Object?> get context => const {};
  @override
  String? get diagnostic => null;
  @override
  Iterable<AppWarning> get warnings => const [];
}
