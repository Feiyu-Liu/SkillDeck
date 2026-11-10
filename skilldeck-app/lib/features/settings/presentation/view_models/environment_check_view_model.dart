import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/settings/models/environment_check.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';

final class EnvironmentCheckState {
  const EnvironmentCheckState({required this.items});

  final List<EnvironmentCheckItem> items;

  bool get isChecking =>
      items.any((item) => item.status == EnvironmentCheckStatus.checking);

  EnvironmentCheckState copyWith({List<EnvironmentCheckItem>? items}) =>
      EnvironmentCheckState(items: items ?? this.items);
}

/// Drives the Environment check section.
///
/// Checks never start on their own. On a macOS host without the developer
/// command line tools, probing causes the operating system to present its own
/// install dialog, so raising it must always be something the user asked for.
final class EnvironmentCheckViewModel extends Notifier<EnvironmentCheckState> {
  @override
  EnvironmentCheckState build() => const EnvironmentCheckState(
    items: [
      EnvironmentCheckItem(
        id: EnvironmentCheckId.git,
        status: EnvironmentCheckStatus.notChecked,
      ),
    ],
  );

  Future<void> check(EnvironmentCheckId id) async {
    if (state.isChecking) return;
    _update(
      id,
      (item) => item.copyWith(
        status: EnvironmentCheckStatus.checking,
        reasonKey: null,
      ),
    );
    final repository = ref.read(skillsWorkspaceRepositoryProvider);
    final result = await _probe(id, repository);
    if (!ref.mounted) return;
    _update(
      id,
      (item) =>
          item.copyWith(status: result.status, reasonKey: result.reasonKey),
    );
  }

  Future<({EnvironmentCheckStatus status, String reasonKey})> _probe(
    EnvironmentCheckId id,
    SkillsWorkspaceRepository repository,
  ) async {
    switch (id) {
      case EnvironmentCheckId.git:
        try {
          return _git(await repository.probeGitEnvironment());
        } on Object {
          return (
            status: EnvironmentCheckStatus.failed,
            reasonKey: 'probeFailed',
          );
        }
    }
  }

  ({EnvironmentCheckStatus status, String reasonKey}) _git(
    WorkspaceGitEnvironmentStatus status,
  ) => switch (status) {
    WorkspaceGitEnvironmentStatus.available => (
      status: EnvironmentCheckStatus.ok,
      reasonKey: 'available',
    ),
    WorkspaceGitEnvironmentStatus.notInstalled => (
      status: EnvironmentCheckStatus.attention,
      reasonKey: 'notInstalled',
    ),
    WorkspaceGitEnvironmentStatus.developerToolsRequired => (
      status: EnvironmentCheckStatus.attention,
      reasonKey: 'developerToolsRequired',
    ),
    // Attention rather than checking: `checking` means our own probe is in
    // flight, and reusing it here would leave the spinner running forever.
    WorkspaceGitEnvironmentStatus.developerToolsInstalling => (
      status: EnvironmentCheckStatus.attention,
      reasonKey: 'developerToolsInstalling',
    ),
    WorkspaceGitEnvironmentStatus.probeFailed => (
      status: EnvironmentCheckStatus.failed,
      reasonKey: 'probeFailed',
    ),
  };

  void _update(
    EnvironmentCheckId id,
    EnvironmentCheckItem Function(EnvironmentCheckItem) transform,
  ) => state = state.copyWith(
    items: [
      for (final item in state.items)
        if (item.id == id) transform(item) else item,
    ],
  );
}
