import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/library/skill_library_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

import '../../support/fake_skills_workspace_repository.dart';

void main() {
  test(
    'routes Favorite and Note mutations by managed Skill identity',
    () async {
      final workspace = FakeSkillsWorkspaceRepository(snapshot: _snapshot());
      final container = _container(workspace);
      addTearDown(container.dispose);
      final commands = container.read(skillLibraryCommandsProvider.notifier);

      await commands.toggleFavorite(skillId: _skillId, isFavorite: false);
      await commands.saveNote(skillId: _skillId, note: 'Keep this handy');
      await commands.saveNote(skillId: _skillId, note: '   ');

      expect(workspace.favoriteRequests, [
        (skillId: _skillId, isFavorite: true),
      ]);
      expect(workspace.noteRequests, [
        (skillId: _skillId, note: 'Keep this handy'),
      ]);
      expect(workspace.deletedNotes, [_skillId]);
    },
  );

  test(
    'retains only transient busy state and rejects duplicate commands',
    () async {
      final completion =
          Completer<WorkspaceCompletion<SkillsWorkspaceSnapshot>>();
      final workspace = FakeSkillsWorkspaceRepository(snapshot: _snapshot())
        ..favoriteTask = WorkspaceTask(
          current: _progress,
          states: const Stream.empty(),
          completed: completion.future,
          cancel: () async {},
        );
      final container = _container(workspace);
      addTearDown(container.dispose);
      final commands = container.read(skillLibraryCommandsProvider.notifier);

      final first = commands.toggleFavorite(
        skillId: _skillId,
        isFavorite: false,
      );
      expect(container.read(skillLibraryCommandsProvider), {_skillId});

      await commands.toggleFavorite(skillId: _skillId, isFavorite: false);
      expect(workspace.favoriteRequests, hasLength(1));

      completion.complete(WorkspaceCompleted(value: workspace.current));
      await first;
      expect(container.read(skillLibraryCommandsProvider), isEmpty);
    },
  );

  test('notifies when a Skill is favorited or unfavorited', () async {
    final workspace = FakeSkillsWorkspaceRepository(snapshot: _snapshot());
    final container = _container(workspace);
    addTearDown(container.dispose);
    final commands = container.read(skillLibraryCommandsProvider.notifier);

    await commands.toggleFavorite(skillId: _skillId, isFavorite: false);
    expect(
      container.read(appNotificationControllerProvider)!.notification.message,
      AppNotificationMessage.skillFavorited,
    );

    await commands.toggleFavorite(skillId: _skillId, isFavorite: true);
    expect(
      container.read(appNotificationControllerProvider)!.notification.message,
      AppNotificationMessage.skillUnfavorited,
    );
  });

  test('surfaces terminal-only warnings from a Library mutation', () async {
    final warning = WorkspaceWarning(
      code: WorkspaceWarningCode.recoveryCleanupDeferred,
    );
    final workspace = FakeSkillsWorkspaceRepository(snapshot: _snapshot())
      ..favoriteTask = WorkspaceTask(
        current: _progress,
        states: const Stream.empty(),
        completed: Future.value(
          WorkspaceCompleted(value: _snapshot(), warnings: [warning]),
        ),
        cancel: () async {},
      );
    final container = _container(workspace);
    addTearDown(container.dispose);

    await container
        .read(skillLibraryCommandsProvider.notifier)
        .toggleFavorite(skillId: _skillId, isFavorite: false);

    final event = container.read(appNotificationControllerProvider)!;
    expect(event.notification.severity, AppNotificationSeverity.warning);
    expect(
      event.notification.message,
      AppNotificationMessage.completedWithWarnings,
    );
  });
}

ProviderContainer _container(FakeSkillsWorkspaceRepository workspace) =>
    ProviderContainer(
      overrides: [
        skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
      ],
    );

SkillsWorkspaceSnapshot _snapshot() => SkillsWorkspaceSnapshot(
  revision: 1,
  projectRoots: const [],
  skills: [
    WorkspaceSkill(
      id: _skillId,
      slotKey: 'alpha',
      declaredName: 'alpha',
      displayName: 'Alpha',
      description: '',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/source',
      ),
      currentRevision: SkillRevision(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 1,
        acquiredAt: DateTime(2026),
        resolvedSourceRevision: 'local',
      ),
      activations: const [],
    ),
  ],
);

final _skillId = WorkspaceSkillId('managed-alpha');

final _progress = WorkspaceOperationProgress(
  operationId: 'favorite-alpha',
  kind: WorkspaceOperationKind.setFavorite,
  phase: WorkspaceOperationPhase.applying,
);
