import 'dart:async';

import 'package:skills_manager/features/skills/data/services/directory_picker.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import 'fake_skill_drift_reviews.dart';
import 'fake_skills_workspace_repository.dart';

final driftReviewSkillId = WorkspaceSkillId('drift-skill');

FakeWorkspaceSkillDriftReview driftReviewFixture() =>
    FakeWorkspaceSkillDriftReview(
      skillId: driftReviewSkillId,
      artifacts: [
        WorkspaceDriftedArtifact(
          artifactId: 'repositoryCopy',
          locationKind: WorkspaceDriftLocationKind.repositoryCopy,
          driftKind: WorkspaceDriftKind.contentChanged,
          canKeepExternal: true,
          canExport: true,
        ),
        WorkspaceDriftedArtifact(
          artifactId: 'copyActivation',
          locationKind: WorkspaceDriftLocationKind.copyActivation,
          driftKind: WorkspaceDriftKind.contentChanged,
          targetPath: '/agents/sample',
          canKeepExternal: true,
          canExport: true,
        ),
        WorkspaceDriftedArtifact(
          artifactId: 'linkActivation',
          locationKind: WorkspaceDriftLocationKind.symbolicLinkActivation,
          driftKind: WorkspaceDriftKind.wrongLinkTarget,
          canKeepExternal: false,
          canExport: false,
        ),
      ],
      missingArtifactCount: 1,
    );

final class DeferredDriftDirectoryPicker implements DirectoryPicker {
  final completed = Completer<String?>();
  int calls = 0;
  @override
  Future<String?> pickDirectory({String? initialDirectory}) {
    calls += 1;
    return completed.future;
  }
}

final class DeferredDriftReviewTask<T> {
  DeferredDriftReviewTask(this.kind);
  final WorkspaceOperationKind kind;
  final completed = Completer<WorkspaceCompletion<T>>();
  final progress = StreamController<WorkspaceOperationProgress>.broadcast();
  int cancellationCalls = 0;

  WorkspaceTask<T> get task => WorkspaceTask(
    current: WorkspaceOperationProgress(
      operationId: 'drift-${kind.name}',
      kind: kind,
      phase: WorkspaceOperationPhase.inspecting,
    ),
    states: progress.stream,
    completed: completed.future,
    cancel: () async {
      cancellationCalls += 1;
    },
  );

  Future<void> dispose() => progress.close();
}

final driftWidgetSkillId = WorkspaceSkillId('alpha');

SkillsWorkspaceSnapshot driftWidgetSnapshot({
  int revision = 1,
  WorkspaceSkillIntegrityStatus integrity =
      WorkspaceSkillIntegrityStatus.driftPending,
}) => SkillsWorkspaceSnapshot(
  revision: revision,
  projectRoots: const [],
  skills: [
    WorkspaceSkill(
      id: driftWidgetSkillId,
      slotKey: 'alpha',
      declaredName: 'alpha',
      displayName: 'Alpha Skill',
      description: 'Test skill',
      source: const SkillSourceProvenance(
        kind: WorkspaceSourceKind.local,
        locator: '/skills/alpha',
      ),
      currentRevision: SkillRevision(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 7,
        acquiredAt: DateTime.utc(2026),
      ),
      activations: const [],
      integrity: integrity,
    ),
  ],
);

WorkspaceDriftedArtifact driftWidgetArtifact({
  String artifactId = 'repositoryCopy',
  WorkspaceDriftLocationKind locationKind =
      WorkspaceDriftLocationKind.repositoryCopy,
  WorkspaceDriftKind driftKind = WorkspaceDriftKind.contentChanged,
  bool canKeepExternal = true,
  bool canExport = true,
  List<String>? agentIds,
}) => WorkspaceDriftedArtifact(
  artifactId: artifactId,
  locationKind: locationKind,
  driftKind: driftKind,
  targetPath: locationKind == WorkspaceDriftLocationKind.repositoryCopy
      ? null
      : '/agents/codex/alpha',
  scope: locationKind == WorkspaceDriftLocationKind.repositoryCopy
      ? null
      : WorkspaceScope.global,
  agentIds:
      agentIds ??
      (locationKind == WorkspaceDriftLocationKind.repositoryCopy
          ? const []
          : const ['codex']),
  canKeepExternal: canKeepExternal,
  canExport: canExport,
);

FakeWorkspaceSkillDriftReview driftWidgetReview({
  List<WorkspaceDriftedArtifact>? artifacts,
  int missingArtifactCount = 0,
}) => FakeWorkspaceSkillDriftReview(
  skillId: driftWidgetSkillId,
  artifacts: artifacts ?? [driftWidgetArtifact()],
  missingArtifactCount: missingArtifactCount,
);

FakeSkillsWorkspaceRepository driftWidgetWorkspace({
  FakeWorkspaceSkillDriftReview? review,
}) =>
    FakeSkillsWorkspaceRepository(snapshot: driftWidgetSnapshot())
      ..inspectSkillDriftTasks.add(
        completedWorkspaceTask(
          kind: WorkspaceOperationKind.inspectSkillDrift,
          value: review ?? driftWidgetReview(),
        ),
      );

WorkspaceTask<T> pendingDriftWidgetTask<T>({
  required WorkspaceOperationKind kind,
  required Completer<WorkspaceCompletion<T>> completion,
}) => WorkspaceTask<T>(
  current: WorkspaceOperationProgress(
    operationId: 'drift-widget-${kind.name}',
    kind: kind,
    phase: WorkspaceOperationPhase.applying,
  ),
  states: const Stream.empty(),
  completed: completion.future,
  cancel: () async {},
);
