import 'dart:async';

import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/skills/data/repositories/diagnostic_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/package_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_workspace/skills_workspace.dart' as package_workspace;

/// Live catalog boundary used by Settings persistence coordination.
abstract interface class AppSettingsRuntime {
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> reconfigureAgentCatalog(
    AppSettings nextSettings,
  );
}

/// Process-lifetime owner of the App's one local Skill Workspace.
///
/// The Runtime creates one package facade and one App adapter. It deliberately
/// never replaces them when Custom Agent settings change: reconfiguration is an
/// atomic in-memory Workspace operation, so active readers and operations keep
/// their resource ownership and subscriptions intact.
final class SkillsManagerRuntime implements AppSettingsRuntime {
  SkillsManagerRuntime({
    required this.repositoryRoot,
    required this.settings,
    required this.diagnostics,
    required this.failureReporter,
    SkillsWorkspaceRepository? workspace,
  }) : workspace =
           workspace ??
           _diagnosticRepository(
             rootPath: repositoryRoot,
             settings: settings,
             diagnostics: diagnostics,
             failureReporter: failureReporter,
           );

  /// The Workspace root, not the legacy Core `repository/` directory.
  ///
  /// The constructor name is kept temporarily so bootstrap composition can be
  /// switched in a separate, reviewable change.
  final String repositoryRoot;
  final AppDiagnostics diagnostics;
  final AppFailureReporter failureReporter;
  final SkillsWorkspaceRepository workspace;
  AppSettings settings;
  bool _busy = false;
  Future<void>? _closeFuture;

  final Set<Future<void> Function()> _beforeClose = {};

  /// Process resources must stop accepting requests before the Workspace closes.
  void addBeforeClose(Future<void> Function() callback) =>
      _beforeClose.add(callback);
  void removeBeforeClose(Future<void> Function() callback) =>
      _beforeClose.remove(callback);

  bool get isBusy => _busy;

  /// Atomically replaces the in-memory Custom Agent catalog without replacing
  /// the repository, SQLite connection, revision worker, or Snapshot stream.
  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> reconfigureAgentCatalog(
    AppSettings nextSettings,
  ) async {
    if (_busy) throw StateError('Agent configuration is busy.');
    _busy = true;
    try {
      final completion = await workspace
          .reconfigureAgentCatalog(_agentDefinitions(nextSettings))
          .completed;
      switch (completion) {
        case WorkspaceCompleted():
          settings = nextSettings;
        case WorkspaceCommittedPending():
          // The catalog mutation crossed its business commit point. Keep the
          // new settings so a process restart reconstructs the same catalog;
          // the App-level coordinator completes recovery separately.
          settings = nextSettings;
        case WorkspaceFailed():
          break;
      }
      return completion;
    } finally {
      _busy = false;
    }
  }

  /// Closes the Runtime-owned repository exactly once. Borrowers such as page
  /// ViewModels and Snapshot providers must never call this method.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      for (final stop in _beforeClose.toList()) {
        await stop();
      }
    } finally {
      await workspace.close();
    }
  }

  static SkillsWorkspaceRepository _diagnosticRepository({
    required String rootPath,
    required AppSettings settings,
    required AppDiagnostics diagnostics,
    required AppFailureReporter failureReporter,
  }) => DiagnosticSkillsWorkspaceRepository(
    delegate: PackageSkillsWorkspaceRepository.create(
      configuration: package_workspace.SkillsRepositoryConfiguration(
        rootPath: rootPath,
        defaultLockWaitPolicy: package_workspace.LockWaitPolicy.wait(
          timeout: const Duration(seconds: 30),
        ),
        additionalAgents: _packageAgentDefinitions(settings),
      ),
    ),
    diagnostics: diagnostics,
    failureReporter: failureReporter,
  );
}

List<WorkspaceAgentDefinition> _agentDefinitions(AppSettings settings) => [
  for (final agent in settings.customAgents)
    WorkspaceAgentDefinition(
      id: agent.id,
      displayName: agent.displayName,
      platforms: {
        for (final entry in agent.platforms.entries)
          _workspacePlatform(entry.key.name): WorkspaceAgentPlatformDefinition(
            globalSkillsPath: entry.value.globalSkillsPath,
            projectSkillsPath: entry.value.projectSkillsPath,
            globalDiscoverySkillsPaths: entry.value.globalDiscoverySkillsPaths,
            projectDiscoverySkillsPaths:
                entry.value.projectDiscoverySkillsPaths,
          ),
      },
    ),
];

WorkspaceDesktopPlatform _workspacePlatform(String value) => switch (value) {
  'macos' => WorkspaceDesktopPlatform.macos,
  'windows' => WorkspaceDesktopPlatform.windows,
  'linux' => WorkspaceDesktopPlatform.linux,
  _ => throw ArgumentError.value(value, 'value', 'is not a desktop platform'),
};

List<package_workspace.AgentDefinition> _packageAgentDefinitions(
  AppSettings settings,
) => [
  for (final agent in settings.customAgents)
    package_workspace.AgentDefinition(
      id: agent.id,
      displayName: agent.displayName,
      platforms: {
        for (final entry in agent.platforms.entries)
          _packagePlatform(
            entry.key.name,
          ): package_workspace.AgentPlatformDefinition(
            globalSkillsPath: entry.value.globalSkillsPath,
            projectSkillsPath: entry.value.projectSkillsPath,
            globalDiscoverySkillsPaths: entry.value.globalDiscoverySkillsPaths,
            projectDiscoverySkillsPaths:
                entry.value.projectDiscoverySkillsPaths,
            detectionPaths: [
              if (entry.value.globalSkillsPath case final path?)
                package_workspace.AgentDetectionPath.absolute(path),
              for (final path in entry.value.globalDiscoverySkillsPaths)
                package_workspace.AgentDetectionPath.absolute(path),
              if (entry.value.projectSkillsPath case final path?)
                package_workspace.AgentDetectionPath.projectRelative(path),
              for (final path in entry.value.projectDiscoverySkillsPaths)
                package_workspace.AgentDetectionPath.projectRelative(path),
            ],
          ),
      },
    ),
];

package_workspace.DesktopPlatform _packagePlatform(String value) =>
    switch (value) {
      'macos' => package_workspace.DesktopPlatform.macos,
      'windows' => package_workspace.DesktopPlatform.windows,
      'linux' => package_workspace.DesktopPlatform.linux,
      _ => throw ArgumentError.value(
        value,
        'value',
        'is not a desktop platform',
      ),
    };
