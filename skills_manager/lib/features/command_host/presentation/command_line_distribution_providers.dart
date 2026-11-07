import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import '../data/command_line_distribution.dart';
import '../data/command_line_distribution_service.dart';
import '../data/command_line_path_link_service.dart';
import '../data/skilldeck_agent_skill_service.dart';
import 'command_host_providers.dart';

/// No implicit home access: bootstrap must opt in just like the Command Host.
final commandLineDistributionServiceProvider =
    Provider<CommandLineDistributionService?>((ref) {
      final configuration = ref.watch(commandHostConfigurationProvider);
      if (configuration == null) return null;
      return CommandLineDistributionService(
        rootDirectory: p.dirname(
          commandHostRunDirectory(
            environment: configuration.environment,
            isWindows: configuration.isWindows,
          ),
        ),
        // The helper never sits beside the App's own executable: both macOS
        // and Windows treat "skilldeck" and "SkillDeck" as the same file.
        bundledExecutable: configuration.isWindows
            ? p.join(
                p.dirname(Platform.resolvedExecutable),
                'cli',
                'skilldeck.exe',
              )
            : p.normalize(
                p.join(
                  p.dirname(Platform.resolvedExecutable),
                  '..',
                  'Helpers',
                  'skilldeck',
                ),
              ),
        isWindows: configuration.isWindows,
        loadSkill: () async {
          final data = await rootBundle.load(skillDeckAgentSkillAsset);
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        },
        diagnostics: ref.watch(appDiagnosticsProvider),
      );
    });

/// Ensures the stable CLI copy once per App launch and reports where it is.
final commandLineToolProvider = FutureProvider<CommandLineToolState>((
  ref,
) async {
  final service = ref.watch(commandLineDistributionServiceProvider);
  return service == null
      ? const CommandLineToolState(
          status: CommandLineToolStatus.notBundled,
          path: '',
        )
      : service.ensureTool();
});

/// The macOS terminal link, offered only once the stable copy exists.
final commandLinePathLinkServiceProvider = Provider<CommandLinePathLink?>((
  ref,
) {
  final configuration = ref.watch(commandHostConfigurationProvider);
  final home = configuration?.environment['HOME'];
  final tool = ref.watch(commandLineToolProvider).value;
  if (configuration == null ||
      !Platform.isMacOS ||
      home == null ||
      tool?.status != CommandLineToolStatus.ready) {
    return null;
  }
  return MacOsCommandLinePathLink(targetPath: tool!.path, userHomePath: home);
});

final commandLinePathLinkProvider = FutureProvider<CommandLinePathLinkStatus?>((
  ref,
) async {
  return ref.watch(commandLinePathLinkServiceProvider)?.status();
});

/// The maintained Source is refreshed even when Settings is never opened.
final skillDeckAgentSkillSourceProvider = FutureProvider<String?>((ref) async {
  return ref
      .watch(commandLineDistributionServiceProvider)
      ?.ensureAgentSkillSource();
});

/// Only this local Source's managed Skill counts; global Activations supply
/// the selected Agents, independently of project Activations.
final skillDeckAgentSkillProvider = Provider<SkillDeckAgentSkillState>((ref) {
  final directory = ref
      .watch(commandLineDistributionServiceProvider)
      ?.sourceDirectory;
  if (directory == null) {
    return const SkillDeckAgentSkillState.notInstalled();
  }
  final snapshot = ref.watch(workspaceSnapshotProvider).asData?.value;
  if (snapshot == null) {
    return const SkillDeckAgentSkillState.notInstalled();
  }
  final skill = snapshot.findSkillBySlotKey('skilldeck');
  if (skill == null ||
      skill.source.kind != WorkspaceSourceKind.local ||
      !p.equals(p.normalize(skill.source.locator), p.normalize(directory))) {
    return const SkillDeckAgentSkillState.notInstalled();
  }
  return SkillDeckAgentSkillState(
    installed: true,
    skillId: skill.id,
    activeAgentIds: {
      for (final activation in skill.activations)
        if (activation.scope == WorkspaceScope.global) ...activation.agentIds,
    },
  );
});

final skillDeckAgentSkillServiceProvider = Provider<SkillDeckAgentSkillService>(
  (ref) {
    return LocalSkillDeckAgentSkillService(
      repository: () => ref.read(skillsWorkspaceRepositoryProvider),
      sourceDirectory: () async {
        final path = await ref.read(skillDeckAgentSkillSourceProvider.future);
        if (path == null) {
          throw const AgentSkillInstallFailure('sourceUnavailable');
        }
        return path;
      },
    );
  },
);
