import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import '../data/approval_command_handlers.dart';
import '../data/command_approval_registry.dart';
import '../data/command_host_dispatcher.dart';
import '../data/command_host_server.dart';
import '../data/read_command_handlers.dart';
import '../data/skill_selector_resolver.dart';
import '../data/skills_lock_reader.dart';
import '../data/write_command_handlers.dart';
import 'command_line_activity.dart';
import 'command_line_activity_reporter.dart';
import 'command_line_approval.dart';
import 'command_line_distribution_providers.dart';

final class CommandHostConfiguration {
  CommandHostConfiguration({
    required Map<String, String> environment,
    required this.isWindows,
    this.bundleIdentifier,
  }) : environment = Map.unmodifiable(environment);
  final Map<String, String> environment;
  final bool isWindows;
  final String? bundleIdentifier;
}

/// Bootstrap supplies platform inputs. Embedded Apps and tests opt in with an
/// explicit environment, so mounting a test App never accesses the real home.
final commandHostConfigurationProvider = Provider<CommandHostConfiguration?>(
  (ref) => null,
);

final commandHostAppVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// Allows the pre-container Windows tray callback to await an in-flight start.
final commandHostShutdownRegistrarProvider =
    Provider<void Function(Future<void> Function())>((ref) => (_) {});

/// Keep-alive owner: snapshot publications never rebuild the listening server.
final commandHostProvider = FutureProvider<CommandHostServer?>((ref) async {
  final configuration = ref.watch(commandHostConfigurationProvider);
  if (configuration == null) return null;
  final diagnostics = ref.watch(appDiagnosticsProvider);
  final runtime = ref.watch(skillsManagerRuntimeProvider);
  CommandHostServer? server;
  CommandApprovalRegistry? approvals;
  var closing = false;
  Future<void> stop() async {
    closing = true;
    await approvals?.close();
    await server?.stop();
  }

  ref.read(commandHostShutdownRegistrarProvider)(stop);
  runtime.addBeforeClose(stop);
  ref.onDispose(() {
    unawaited(stop().whenComplete(() => runtime.removeBeforeClose(stop)));
  });
  // Use the same open/snapshot pipeline as the GUI, never open a second facade.
  try {
    await ref.read(workspaceSnapshotProvider.future);
    if (!ref.mounted || closing) return null;
    final version = await ref.read(commandHostAppVersionProvider.future);
    if (!ref.mounted || closing) return null;
    final activity = CommandLineActivityReporter(
      controller: () => ref.read(commandLineActivityProvider.notifier),
      agentName: (id) =>
          ref
              .read(deviceAgentCatalogProvider)
              .value
              ?.where((agent) => agent.id == id)
              .firstOrNull
              ?.displayName ??
          id,
    );
    final registry = CommandApprovalRegistry(
      presenter: ref.read(commandApprovalPresenterProvider),
      repository: () => ref.read(skillsWorkspaceRepositoryProvider),
      activity: activity,
    );
    approvals = registry;
    server = CommandHostServer(
      runDirectory: commandHostRunDirectory(
        environment: configuration.environment,
        isWindows: configuration.isWindows,
      ),
      isWindows: configuration.isWindows,
      appVersion: () async => version,
      bundleIdentifier: configuration.bundleIdentifier,
      dispatcher: CommandHostDispatcher({
        ...readCommandHandlers(
          snapshot: () => ref.read(workspaceSnapshotProvider).asData?.value,
          repository: () => ref.read(skillsWorkspaceRepositoryProvider),
          updates: () => ref.read(skillUpdateStatusProvider),
          agents: () => ref.read(deviceAgentCatalogProvider.future),
          members: () => _readMembers(ref),
          globalTargets: () async => readCommandValue(
            await ref.read(
              activationTargetsProvider((
                scope: WorkspaceScope.global,
                projectRootId: null,
              )).future,
            ),
          ),
        ),
        ...approvalCommandHandlers(
          skillsLock: () {
            final home = configuration.environment['HOME'];
            return home == null ? null : FileSkillsLockReader(homePath: home);
          },
          registry: registry,
          repository: () => ref.read(skillsWorkspaceRepositoryProvider),
          snapshot: () => ref.read(workspaceSnapshotProvider).asData?.value,
          updates: () => ref.read(skillUpdateStatusProvider),
          agents: () => ref.read(deviceAgentCatalogProvider.future),
        ),
        ...writeCommandHandlers(
          updateCoordinator: () => ref.read(skillUpdateStatusProvider.notifier),
          snapshot: () => ref.read(workspaceSnapshotProvider).asData?.value,
          repository: () => ref.read(skillsWorkspaceRepositoryProvider),
          updates: () => ref.read(skillUpdateStatusProvider),
          agents: () => ref.read(deviceAgentCatalogProvider.future),
          members: () => _readMembers(ref),
          activity: activity,
        ),
        'status': statusCommandHandler(
          appVersion: version,
          snapshot: () => ref.read(workspaceSnapshotProvider).asData?.value,
        ),
      }),
      diagnostics: diagnostics,
    );
    await server.start();
    if (!ref.mounted || closing) {
      await server.stop();
      return null;
    }
    // Distribution is App-owned and cannot make an otherwise healthy host fail.
    try {
      await ref.read(commandLineToolProvider.future);
    } on Object {
      diagnostics.info('commandLine.tool', context: {'status': 'failed'});
    }
    if (!ref.mounted || closing) return null;
    try {
      await ref.read(skillDeckAgentSkillSourceProvider.future);
    } on Object {
      diagnostics.info('commandLine.agentSkill', context: {'status': 'failed'});
    }
    if (!ref.mounted || closing) return null;
    return server;
  } on Object {
    // Stable diagnostic only; filesystem/plugin exceptions may contain paths.
    diagnostics.info(
      'commandHost.rejected',
      context: {'code': 'startupFailed'},
    );
    return null;
  }
});

Future<Set<String>> _readMembers(Ref ref) async {
  final settled = Completer<Set<String>>();
  final subscription = ref.listen(deviceAgentMembersProvider, (_, next) {
    if (settled.isCompleted) return;
    if (next.hasError) {
      settled.completeError(
        const SkillSelectionFailure('workspaceUnavailable'),
      );
    } else if (next.hasValue) {
      settled.complete(next.requireValue);
    }
  }, fireImmediately: true);
  try {
    return await settled.future.timeout(const Duration(seconds: 4));
  } finally {
    subscription.close();
  }
}
